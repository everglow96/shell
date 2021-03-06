#!/usr/bin/env bash
# 脚本备份
source /home/chenxinmao/shell/oplus_backup.conf

function load_config(){
    date_this=`date +%Y%m%d`
    date_before_7=`date -d "7 days ago" +%Y%m%d`
}


function check_mysql_service(){
    mysql_ps=`ps -ef |grep mysql |wc -l`
    mysql_listen=`netstat -an |grep LISTEN |grep ${db_port}|wc -l`
    if [[ ${mysql_ps} -eq 0  ||  ${mysql_listen} -eq 0 ]]; then
        echo "ERROR:MySQL is not running! backup stop!"
        exit
    else
        echo "Backing up database!"
    fi
}

function backup_mysql(){
    echo ${backup_dir}/${date_this}
    `mkdir -p ${backup_dir}/${date_this}`
    `mysqldump -u${db_user} -p${db_password} --host=${db_ip} --port=${db_port} --databases oplus -R | gzip > ${backup_dir}/${date_this}/${date_this}-oplus-FULL.sql.gz`
    flag=`echo $?`
    if [[ ${flag} -eq 0 ]];then
        echo "success backup mysql to $backup_dir/${date_this}/${date_this}-oplus-FULL.sql.gz"
    else
        echo "backup mysql fail!"
        exit
    fi
}


function backup_git(){
    tar -cvf ${backup_dir}/${date_this}/${date_this}-git-repos.tar /opt/oplus/assets/gfs/git-repos/
    flag=`echo $?`
    if [[ ${flag} -eq 0 ]];then
        echo "success backup git to ${backup_dir}/${date_this}/${date_this}-git-repos.tar"
    else
        echo "backup git fail!"
        exit
    fi
}



function backup_file(){
    tar -cvf ${backup_dir}/${date_this}/${date_this}-fs-repos.tar /opt/oplus/assets/gfs/fs-repos/
    flag=`echo $?`
    if [[ ${flag} -eq 0 ]];then
        echo "success backup file to ${backup_dir}/${date_this}/${date_this}-fs-repos.tar"
    else
        echo "backup file fail!"
        exit
    fi
}

function copyFileToRemote() {
    echo "start copy to ${remote_ip}"
    `scp -r ${backup_dir}/${date_this} root@${remote_ip}:${backup_dir}/${date_this}`
}

function delete_file() {
    echo "start delete old folder and file ${date_before_7}"
    `rm -rf /opt/oplus/backup/${date_before_7}`
    `ssh root@${remote_ip} "rm -rf ${backup_dir}/${date_before_7}"`
    echo "backup finish"
}

load_config
check_mysql_service
backup_mysql
backup_git
backup_file
copyFileToRemote
delete_file
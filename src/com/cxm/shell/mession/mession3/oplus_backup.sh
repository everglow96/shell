#!/usr/bin/env bash


function load_config(){
    backup_dir=`cat oplus_backup.conf | grep backup_dir | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    db_ip=`cat oplus_backup.conf | grep db_ip | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    db_port=`cat oplus_backup.conf | grep db_port | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    db_user=`cat oplus_backup.conf | grep db_user | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    db_password=`cat oplus_backup.conf | grep db_password | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    date_this=`date +%Y%m%d`
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
    `mysqldump -u${db_user} -p${db_password} --host=${db_ip} --port=${db_port} -B oplus -R | gzip > ${backup_dir}/${date_this}/${date_this}-oplus-FULL.sql.gz`
    flag=`echo $?`
    if [[ ${flag} -eq 0 ]];then
            echo "success backup to $backup_dir/${date_this}/${date_this}-oplus-FULL.sql.gz"
    else
            echo "backup fail!"
            exit
    fi
}


load_config
check_mysql_service
backup_mysql
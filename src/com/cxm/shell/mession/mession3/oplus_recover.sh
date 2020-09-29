#!/usr/bin/env bash


function load_config(){
    backup_dir=`cat oplus_backup.conf | grep backup_dir | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    db_ip=`cat oplus_backup.conf | grep db_ip | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    db_port=`cat oplus_backup.conf | grep db_port | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    db_user=`cat oplus_backup.conf | grep db_user | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
    db_password=`cat oplus_backup.conf | grep db_password | awk -F'=' '{ print $2 }' | sed s/[[:space:]]//g`
}

function read_input () {
    if [[ $# -gt 0 ]]; then
        key="$1"
        case ${key} in
            -t|--time)
                mysql_recover $*
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                usage
                exit 0
                ;;
        esac
    else
        usage
    fi
}

function usage() {
   echo "Usage: sudo ./build-before.sh -t [time]"
   echo "Time format example: `date +%Y%m%d`"
   echo "Supported deploy project or restart monit"
   echo "-t|--Data for a time"
   echo "-h|--Help parameter help "
}

function mysql_recover_operation(){
    if  ! mysql -h${db_ip} -u${db_user} -p${db_password} -e 'use oplus'; then
        `mysql -u${db_user} -p${db_password} --host=${db_ip} --port=${db_port}  < $*`
        flag1=`echo $?`
        if [[ ${flag1} -eq 0 ]];then
                echo "The database is recovered!"
        else
                echo "Recover fail!"
                exit
        fi
    else
        echo "The database oplus is exist, Please delete manually!"
        exit;
    fi
}



function mysql_recover(){
    load_config
    date_time=$2
    file_gz_name="${backup_dir}/${date_time}/${date_time}-oplus-FULL.sql.gz"
    if [[ ! -f ${file_gz_name} ]]; then
        echo "File ${file_gz_name} dose not exist !"
    fi
    file_sql_name="${backup_dir}/${date_time}/${date_time}-oplus-FULL.sql"
    `gunzip ${file_gz_name}`
    flag=`echo $?`
    if [[ ${flag} -eq 0 ]];then
            echo "Success gunzip to $file_sql_name"
            echo "Restoring database!"
            mysql_recover_operation ${file_sql_name}
    else
            echo "gunzip fail!"
            exit
    fi
}

read_input $*
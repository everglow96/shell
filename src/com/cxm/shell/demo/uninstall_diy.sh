#!/usr/bin/env bash
# 完全删除 MySQL
find_file=()
rpm_file=()

function _find (){
  rpm_file=`rpm -qa|grep -i $1`
# rc=$?; if [[ ${rc} != 0 ]]; then exit ${rc}; fi
  find_file=`find / -name $1`
  rc=$?; if [[ ${rc} != 0 ]]; then exit ${rc}; fi
}


function main(){
   `service $1 stop`
    _find $1

    for each in ${rpm_file[*]} ; do
        `rpm -e --nodeps ${each}`
        echo "already remove " ${each}
    done

    for each in ${find_file[*]} ; do
        `rm -rf ${each}`
        echo "already remove " ${each}
    done
    if [[ '$1' == "mysql" ]]; then
        echo "remove /etc/my.cnf"
        `rm -rf /etc/my.cnf`
    fi

    echo "remove finish"
}

main $*
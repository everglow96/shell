#!/usr/bin/env bash

#./xxx.sh -p -c -h
war_sh=("oplus-svs")
operation=""
projects=()
deploy_or_monit=""

# 首先 如果有restart命令， 一定重启minit中是svs， 如果有其他的模块，我就取build

function operation_sh(){
    operation=${@:1:1}
    if [[ ${@:$#} == "restart" ]]; then
        projects=${@:2:$#-2}
        deploy_or_monit="monit"
    else
        projects=${@:2:$#}
        deploy_or_monit="deploy"
    fi
}


function read_input () {
    if [[ $# -gt 0 ]]; then
        key="$1"
        case ${key} in
            -p|--project)
                operation_sh $*
                ;;
            -c|--checkout)
                 operation_sh $*
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
   echo "Usage: sudo ./build-before.sh -p project_name [restart]"
   echo "Supported deploy project or restart monit"
   echo "-c|--checkout false  Do not checkout source"
   echo "-p|--project false  Do not find project source"
   echo "-h|--help parameter help "
}

function run_build_jar_sh() {
    echo "=======> build-jar.sh deploy start"
#    source "/opt/scripts/oplus/build-jar.sh" ${operation} $1
    source "jar.sh" ${operation} $1
    rc=$?; if [[ ${rc} != 0 ]]; then exit ${rc}; fi
}

function run_build_war_sh() {
    echo "=======> build-war.sh deploy start"
#    source "/opt/scripts/oplus/build-war.sh" ${operation} $1
    source "war.sh" ${operation} $1
    rc=$?; if [[ ${rc} != 0 ]]; then exit ${rc}; fi
}

function run_monit_sh() {
    echo "=======> monit restart"
    for i in ${war_sh[@]}
    do
    echo "run_monit_sh" ${i}
#        (monit restart ${i})
        rc=$?; if [[ ${rc} != 0 ]]; then exit ${rc}; fi
    done
}

function is_war_sh(){
    war_flag="no"
    for i in ${war_sh[@]}
    do
        echo "ever" i ${i}
       [[ "$i" == "$1" ]] && war_flag="yes" && break
    done
}

function main() {
    read_input $*
    # build
    for each  in ${projects[*]} ; do
        is_war_sh ${each}
        if [[ "${war_flag}" == "yes" ]]; then
            run_build_war_sh ${each}
        else
            run_build_jar_sh ${each}
        fi
    done
    # restart monit
    if [[ "${deploy_or_monit}" == "monit" ]]; then
        run_monit_sh
    fi

}

main $*

#!/usr/bin/env bash

source oplus-lib-1.0.sh



#===============================================================================
# @desc /sbin/pvs
#===============================================================================
function check1(){
    write_metric "fs_pvs" "$(/sbin/pvs)" "规范RAID配置"
}

function main() {
    check1
    print_metrics
}

main

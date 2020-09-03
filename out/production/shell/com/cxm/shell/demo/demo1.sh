#!/usr/bin/env bash

b="start"
function main() {
 a=${@:$#}
 echo ${a}
   if [[ ${a} == ${b} ]]; then
        echo  "yes"
   else
    echo  "no"
    fi
}

main $*
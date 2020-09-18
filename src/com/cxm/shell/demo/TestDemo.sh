#!/usr/bin/env bash

declare -A checks;
val=0
declare -A resmap=(["cpu_idle"]=0);
function write_check(){
  local name=$1
  local result=$2
  local actual=$3
  echo $name $result $actual
  checks[${name}]="$result,$actual"
}

#write_check "cpu" ${val} ${resmap["cpu_idle"]}
#echo ${!checks[@]}

function print_checks() {
  # print_map_as_yaml checks
  :
}

print_checks
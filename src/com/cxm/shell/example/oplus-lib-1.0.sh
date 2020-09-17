#!/bin/bash    
#
################################################################################
# OPlus指标采集基础函数库
#
# 使用方法：
# -----------------------------------------
# `source oplus-lib-{version}.sh` 引入函数库
#
# 主要函数：
# -----------------------------------------
# - `print_metrics`：打印指标数据
# - `write_metrics($1指标名称, $2指标值, $3指标说明)`：为一个指标赋值
#
# 配置参数
# -----------------------------------------
# - `yaml_format`: yaml输出格式。可以在调用`print_metrics`之前修改值，可以取值"kv"（默认）, "kdv", "list"。
# - `include_builtin`: 是否获取内置指标，默认"false"
#
# 指标命名规范
# -----------------------------------------
#
# 1. 需要匹配正则`[a-zA-Z_][a-zA-Z0-9_]*`
# 2. 如果是数值或布尔，建议加单位后缀，例如
# _day, _hour, _minute, _second, _d, _h, _m, _s
# _b,_kb,_mb,_gb
# _total(for sum), _count(for count)
# _enabled,
# _active
# 3. 如果返回是JSON，以`_json`为后缀
#
# 内置指标：名称大写
# -----------------------------------------
# 如果设置了include_builtin=true，那么将输出以下指标：
#
# - `OS_ID: string`: 值为小写的字符串，代表操作系统的ID，例如"centos","rhel","ubuntu","opensuse"
# - `OS_VER: string`: 值为是OS版本ID，包括主版本和小版本，例如 "7.7","6.10","18.04.2","15.1"
# - `OS_VER_MAJOR: number`: 值为OS主版本号，整形，例如7,6,18,15
# - `HOSTNAME: string`: 值为主机名
# - `IS_VM: boolean`: 值为布尔型，如果是虚拟机为true，物理机为空
#
# 但即使没有设置include_builtin，脚本也会自动获取以上的变量，可以在脚本中引用。
#
# 自定义指标：通过其它命令获取
# -----------------------------------------
# 指标命名建议规范：`<指标类别>_<名称>`
# - `指标类别`：代表指标的类别，例如fs（文件系统和存储）、vm（内存）、net（网络）、dev（硬件设备）、kernel（内核） 、sw（安装的软件）
# - `名称`：代表指标的含义
#
# @author leoliaolei@gmail.com, 2019/12/03, created
# @author leoliaolei@gmail.com, 2020/03/05, 3 yaml format "list", "simple", "default"
# @author leoliaolei@gmail.com, 2020/08/12, change yaml format to "list", "kv", "kdv"
# @version 1.0
#
################################################################################

IS_RHEL6=false
IS_RHEL7=false
OS_ID=""
OS_VER=""
OS_VER_MAJOR=""
IS_VM=""

# Use associated array `_metric_values` to save metric values, `metric_desc` to save metric descriptions
declare -A _metric_values
declare -A _metric_descs
declare -A params

yaml_format="kv"
include_builtin=false

# simple/kv
#
# {key1}: {value1}
# {key2}: {value2}
# ...
#
# list
#
# - name:  {key1}
#   desc:  {desc1}
#   value: {value1}
# - ...
#
# default/kdv
# 
# {key1}:
#   desc: {desc1}
#   value: {value1}

help() {
  #  https://samizdat.dev/help-message-for-shell-scripts/
  sed -rn 's/^### ?//;T;p' "$0"
}

#===============================================================================
# @desc Verify environment is ready, otherwise exit the script
#===============================================================================
function _assert_env() {
  local bash_ver=$(bash --version | grep -oP "GNU bash, version \K(\d*)")
  local perl_ver=$(perl --version | grep -oP "This is perl.*v\K([\d\.]+)")
  local error
  [ "${bash_ver}" -lt 4 ] && error=true
  local perl=$(type perl 2>/dev/null)
  [ -z "${perl}" ] && error=true
  if [ -n "${error}" ]; then
    echo "错误：脚本需要bash 4和perl支持，当前bash版本${bash_ver}，perl版本${perl_ver}" 1>&2
    exit 1
  fi
}

#===============================================================================
# @desc Get builtin values
# `HOSTNAME`: string, hostname
# `OS_ID`: string, OS identifier, e.g. 'rhel','centos','ubuntu','opensuse-leap'
# `OS_VER`: string, OS version in format of "MAJOR.MINOR", e.g. '7.7', '6.10', '18.04', '15.1'
# `OS_VER_MAJOR`: number, OS major version, e.g. 18, 7, 6, 15
# `IS_VM`: boolean, if this is a virtual machine
#===============================================================================
function _get_builtins() {
  # /etc/os-release is specified as part of systemd, not available for rhel 6
  local rel=""
  local str=""
  if [ "${include_builtin}" == "true" ]; then
    write_metric HOSTNAME "$(hostname)" 主机名
  fi
  if [ -f /etc/redhat-release ]; then
    rel=$(cat /etc/redhat-release)
    OS_ID="rhel"
    if [ "${include_builtin}" == "true" ]; then
      write_metric OS_ID "rhel"
    fi
    OS_VER=$(echo "${rel}" | grep -oP '([\d\.]+)')
    str=$(echo "${rel}" | grep -i "CentOS")
    [[ -n "${str}" ]] && OS_ID="centos"
  elif [ -f /etc/os-release ]; then
    rel=$(cat /etc/os-release)
    OS_ID=$(echo "${rel}" | grep -oP '^ID=\K(.*)$' | sed -e 's/["\x27]//g')
    #https://unix.stackexchange.com/questions/13466/can-grep-output-only-specified-groupings-that-match
    OS_VER=$(echo "${rel}" | grep -oP 'VERSION_ID="\K([\d\.]+)')
  fi
  if [ -n "${OS_VER}" ]; then
    OS_VER_MAJOR=$(echo "${OS_VER}" | cut -d. -f1)
  fi

  local file=/sys/class/dmi/id/product_name
  [ -f ${file} ] && str=$(cat ${file} | grep -iE "KVM|VMware|VirtualBox|Virtual Machine") || str=""
  if [ -n "${str}" ]; then
    IS_VM=true
  fi

  if [ "${include_builtin}" == "true" ]; then
    write_metric "OS_ID" "${OS_ID}" "OS标识"
    write_metric "OS_VER" "${OS_VER}" "OS版本"
    write_metric "OS_VER_MAJOR" "${OS_VER_MAJOR}" "OS主版本号"
    write_metric "IS_VM" "${IS_VM}" "是否虚拟机"
  fi
}

#===============================================================================
# @desc Check env, get builtin values and `IS_RHEL6`, `IS_RHEL7`
#===============================================================================
function _init() {
  _assert_env
  _parse_args "$@"
  _get_builtins
  if [ "${OS_VER_MAJOR}" == 7 ]; then
    IS_RHEL7=true
  elif [ "${OS_VER_MAJOR}" == 6 ]; then
    IS_RHEL6=true
  fi
}

#===============================================================================
# Parse command line arguments and put in `params`
# https://stackoverflow.com/questions/59358858/bash-to-split-string-with-space-separated-value-with-double-quote
#===============================================================================
function _parse_args() {
  # perl version
  # perl -pe 's/"[^"\\]*(?:\\.[^"\\]*)*"(*SKIP)(*F)|\h+/$&\n/g' <<< "$arg_str"
  # shell version
  # https://linuxize.com/post/bash-functions/
  # When double quoted, "$@" expands to separate strings - "$1" "$2" "$n".
  # printf '%s\n' "$@" | while read line; do
  for arg in "$@"; do
    if [[ "${arg}" =~ ^([^=]+)=(.*) ]]; then
      params[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
    fi
  done
}

#===============================================================================
# @desc Print a map (associated array) in YAML format.
# It will convert as below
# - item name: replace `-`,`.` with `_`
# - item value: to YAML value
# @usage _print_map_as_yaml "_metric_values"
# @param $1 the name of map
# https://stackoverflow.com/questions/4069188/how-to-pass-an-associative-array-as-argument-to-a-function-in-bash
#===============================================================================
function _print_map_as_yaml() {
  # Use -p get the `declare -A <arr_name>='(<arr_values>)'` expression
  local expr=$(declare -p "$1")
  # Get value part after `<arr_name>=`
  local arr_expr=${expr#*=}
  # Create a new array by `declare -A <arr_expr>`
  # Direct call of `declare -A items=${arr_expr}` works in bash 4.3+, not for bash 4.2 (CentOS 6.10)
  # Use eval as workaround. TODO: if bash_ver<4.3 eval.. else declare -A items=${arr_expr}
  eval "declare -A items=${arr_ezxpr}"

  # Now we get the associated array in `items`
  # Sort keys
  local keys
  keys=$(
    for key in "${!items[@]}"; do
      echo "${key}"
    done | sort | awk '{print $0}'
  )
  local item
  local value
  for key in ${keys}; do
    item=$(echo "${key}" | sed -e "s/[-\.]/_/g")
    # Use double quotes "${items[$key]}" to preserve line breaks in value
    value=$(_to_safe_yaml "${items[${key}]}")
    echo "${item}": "${value}"
  done
}

#===============================================================================
# @desc Convert input to safe YAML value.
# Belows are invalid YAML
# ```
# status: [always] on
# dev: result: 100
# ```
# NOTE: in yaml format, the value can NOT contains `: `(comma+space)
# @param $@ Input string
#===============================================================================
function _to_safe_yaml() {
  local retval="$@"
  local value_indent=""
  # If not number: escape `"` with `\"`, replace newline with `\\n`, wrap with `"`
  # If not number: replace newline with `\\\n`, wrap with `'`
  if [ -z "${retval}" ]; then
    retval="''"
  elif [[ "${retval}" =~ [a-zA-Z] ]]; then
    if [ $(echo "${retval}" | wc -l) -gt 1 ]; then
      # Option 1: If multilines, use YAML format |
      retval=$(echo "${retval}" | sed -e 's/^/ /')
      retval=$(printf "|\n%s" "${retval}")
      # Option 2: Convert multilines to single line
      # retval=$(echo "${retval}" | sed -e ':a;N;$!ba;s/\n/\\n/g')
    else
      # If not starting with single quote, wrap it
      # https://stackoverflow.com/questions/40317552/shell-script-bash-check-if-string-starts-and-ends-with-single-quotes
      if [ "${retval}" == "true" ] || [ "${retval}" == "false" ]; then
        # Do nothing
        :
      elif ! [[ ${retval} =~ ^\'.*\'$ ]]; then
        retval="'${retval}'"
      fi
    fi
  fi
  echo "${retval}"
}

#function usage() {
#  echo "param_1=value param_2=123 param_a=\"some string \""
#}

#===============================================================================
# @desc Join array
# ```
# arr=(aa bb cc)
# str=$(join_by "|" "${arr[@]}") --> "aa|bb|cc"
# ```
# https://stackoverflow.com/questions/1527049/how-can-i-join-elements-of-an-array-in-bash
# @param $1 a string delimeter
# @param $2 an array in format of "${array[@]}"
#===============================================================================
function join_by() {
  local IFS="$1"
  shift
  echo "$*"
}

#===============================================================================
# @desc Get service status. It works for both `/etc/init.d` and `/usr/bin/systemctl`
# @param $1 service_name
#===============================================================================
function get_service_status() {
  local service_name=$1
  local status=$2
  local check_keyword="running"
  local str=""
  local out="false"
  if [ "${IS_RHEL6}" == "true" ]; then
    if [ "${status}" == "enabled" ]; then
      str=$(/sbin/chkconfig --list | grep -w "${service_name}" | grep "2:on\s*3:on\s*4:on\s*5:on")
    elif [ "${status}" == "active" ]; then
      str=$(/etc/init.d/"${service_name}" status 2>/dev/null | grep -w "is running")
    fi
  # elif [ "${IS_RHEL7}" == "true" ]; then
  else
    if [ "${status}" == "enabled" ]; then
      str=$(systemctl is-enabled "${service_name}" 2>/dev/null | grep -E "enabled|static")
      [[ -n "${str}" ]] && out="true"
    elif [ "${status}" == "active" ]; then
      str=$(systemctl is-active "${service_name}" 2>/dev/null | grep -w "active")
    fi
  fi
  [[ -n "${str}" ]] && out="true"
  echo $out
}

#===============================================================================
# @desc If a service is enabled (auto start)
# @param $1 service_name
#===============================================================================
function is_service_enabled() {
  get_service_status "$1" "enabled"
}

#===============================================================================
# @desc If a service is active (running)
# @param $1 service_name
#===============================================================================
function is_service_active() {
  get_service_status "$1" "active"
}

#===============================================================================
# Print metric values in YAML format.
# @param NONE
#===============================================================================
function print_metrics() {
  # Sort keys
  local keys
  keys=$(
    for key in "${!_metric_values[@]}"; do
      echo "${key}"
    done | sort | awk '{print $0}'
  )
  local item
  local value
  local desc
  echo "####METRIC_BEGIN:yaml"
  if [ "${yaml_format}" == "kv" ]; then
    _print_map_as_yaml "_metric_values"
  else
    for key in ${keys}; do
      item=$(echo "${key}" | sed -e "s/[-\.]/_/g")
      # Use double quotes "${items[$key]}" to preserve line breaks in value
      # Prepend two space indent from second line for embeded value
      # https://stackoverflow.com/questions/18574071/how-to-append-text-in-every-line-of-a-file-except-for-the-first-line
      value=$(_to_safe_yaml "${_metric_values[${key}]}" | sed -e '2,$ s/^/  /')
      desc=$(_to_safe_yaml "${_metric_descs[${key}]}")
      if [ "${yaml_format}" == "list" ]; then
        echo "- name: ${item}"
      else
        echo "${item}:"
      fi
      echo "  desc: ${desc}"
      echo "  value: ${value}"
    done
  fi
  echo "####METRIC_END"
}

#===============================================================================
# @desc Save metric in `metrics`
# @param $1 metric name
# @param $2 metric value
# @param $3 metric description (chinese name)
#===============================================================================
function write_metric() {
  local name=$1
  local value=$2
  local desc=$3
  _metric_descs[${name}]="$desc"
  _metric_values[${name}]="$value"
}

_init "$@"

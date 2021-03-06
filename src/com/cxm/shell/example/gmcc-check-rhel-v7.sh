#!/bin/bash
#
################################################################################
# @desc This script get metrics for audit check RHEL and CentOS
#
# 指标命名规范
#
# 除了内置指标名称全部大写，其它指标都是小写。指标通过`resmap["指标名称"]`进行赋值。
# 名称：
# 1. 需要匹配正则`[a-zA-Z_][a-zA-Z0-9_]*`
# 2. 如果是数值或布尔，需要有单位后缀，单位
# _day
# _second
# _b,_kb,_mb,_gb
# _total(for sum), _count(for count)
# _is_enabled,
# _is_active
# 3. 如果返回是JSON，以json为后缀
#
# 内置指标：名称大写
# -----------------------------------------
# `OS_ID: string`: 值为小写的字符串，代表操作系统的ID，例如"centos","rhel","ubuntu","opensuse"
# `OS_VER: string`: 值为是OS版本ID，包括主版本和小版本，例如 "7.7","6.10","18.04.2","15.1"
# `OS_VER_MAJOR: number`: 值为OS主版本号，整形，例如7,6,18,15
# `HOSTNAME: string`: 值为主机名
# `IS_VM: boolean`: 值为布尔型，如果是虚拟机为true，物理机为空
#
# 服务状态：通过命令`systemctl`, `/etc/init.d`, `chkconfig`获取
# -----------------------------------------
# `<service_name>_service_is_enabled: boolean`
# `<service_name>_service_is_active: boolean`
# 示例：
# ntpd_service_is_enabled: false
# chronyd_service_is_active: true
#
# 内核可调整参数（Kernel tunables）：通过命令`sysctl`获取
# -----------------------------------------
# `<kernel_param_in_sysctl>: string|number`
# 示例：
# kernel_sched_latency_ns: 6000000
# net_ipv4_conf_all_accept_redirects: 1
# net_ipv4_tcp_wmem: 4096 16384   4194304
#
# 软件包或文件： 通过命令`rpm -qa`或`dpkg`获取
# -----------------------------------------
# `pkg_<用途>: string`
# 
# 示例：
# pkg_mcelog: 
# 
# 自定义指标：通过其它命令获取
# -----------------------------------------
# `<category>_<metric_name>: string|number`: 按照分类命名。建议分类包括：
# fs（文件系统和存储）、vm（内存）、net（网络）、dev（硬件设备）、kernel（内核） 、sw（安装的软件）
# `sys_uptime_day: number`
#
# @author leoliaolei@gmail.com, 2019/12/03, created
# @version 1.2
# 
################################################################################

IS_RHEL6=false
IS_RHEL7=false
# Use associated array `resmap` to save metric values, `checks` to save check results
declare -A resmap
declare -A checks
declare -A params

#===============================================================================
# Verify environment is ready, otherwise exit the script
#===============================================================================
function assert_env(){
   bash_ver=$(bash --version | grep -oP "GNU bash, version \K(\d*)")
   perl_ver=$(perl --version | grep -oP "This is perl.*v\K([\d\.]+)")
   error
  [ "${bash_ver}" -lt 4 ] && error=true
   perl=$(type perl 2>/dev/null)
  [ -z "${perl}" ] && error=true 
  if [ ! -z "${error}" ]; then
    echo "错误：脚本需要bash 4和perl支持，当前bash版本${bash_ver}，perl版本${perl_ver}" 1>&2
    exit 1
  fi
}

function usage(){
  echo "param_1=value param_2=123 param_a=\"some string \""
}

#===============================================================================
# @desc Check env, get builtin values and `IS_RHEL6`, `IS_RHEL7`
#===============================================================================
function init() {
  assert_env
  parse_args "$@" 
  get_builtins
  if [ "${resmap["OS_VER_MAJOR"]}" == 7 ]; then
    IS_RHEL7=true
  elif [ "${resmap["OS_VER_MAJOR"]}" == 6 ]; then
    IS_RHEL6=true
  fi
}

#===============================================================================
# @desc Get builtin values
#===============================================================================
function get_builtins() {
  # /etc/os-release is specified as part of systemd, not available for rhel 6
  local rel=""
  local str=""
  resmap["HOSTNAME"]=$(hostname)
  if [ -f /etc/redhat-release ]; then
    rel=$(cat /etc/redhat-release)
    resmap["OS_ID"]="rhel"
    resmap["OS_VER"]=$(echo "${rel}" | grep -oP '([\d\.]+)')
    str=$(echo "${rel}" | grep -i "CentOS")
    [[ ! -z "${str}" ]] && resmap["OS_ID"]="centos"
  elif [ -f /etc/os-release ]; then
    rel=$(cat /etc/os-release)
    resmap["OS_ID"]=$(echo "${rel}" | grep -oP '^ID=\K(.*)$' | sed -e 's/["\x27]//g')
    #https://unix.stackexchange.com/questions/13466/can-grep-output-only-specified-groupings-that-match
    resmap["OS_VER"]=$(echo "${rel}" | grep -oP 'VERSION_ID="\K([\d\.]+)')
  fi
  if [ ! -z ${resmap["OS_VER"]} ]; then
    resmap["OS_VER_MAJOR"]=$(echo ${resmap["OS_VER"]} | cut -d. -f1) 
  fi
  local file=/sys/class/dmi/id/product_name
  [ -f ${file} ] && str=$(cat ${file} | grep -iE "KVM|VMware|VirtualBox|Virtual Machine") || str=""
  if [ ! -z "${str}" ]; then
    resmap["IS_VM"]=true
  fi
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
function to_safe_yaml() {
  local retval="$@"
  # If not number: escape `"` with `\"`, replace newline with `\\n`, wrap with `"`
  # If not number: replace newline with `\\\n`, wrap with `'`
  if [ -z "${retval}" ]; then
    retval="''"
  elif [[ "${retval}" =~ [a-zA-Z] ]]; then
    retval=$(echo "${retval}" | sed -e ':a;N;$!ba;s/\n/\\n/g')
    # If not starting with single quote, wrap it
    # https://stackoverflow.com/questions/40317552/shell-script-bash-check-if-string-starts-and-ends-with-single-quotes
    if [ "${retval}" == "true" ] || [ "${retval}" == "false" ]; then
      # Do nothing
      :
    elif ! [[ ${retval} =~ ^\'.*\'$ ]]; then
      retval="'${retval}'"
    fi
  fi
  echo "${retval}"
}

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
# @desc Print out from `sysctl -a`
#===============================================================================
function run_sysctl() {
  local check_items=(
    fs.aio-max-nr
    fs.file-max
    kernel.msgmax
    kernel.msgmnb
    kernel.pid_max
    kernel.sched_child_runs_first
    kernel.sched_latency_ns
    kernel.sched_migration_cost_ns
    kernel.sched_min_granularity_ns
    kernel.sched_nr_migrate
    kernel.sched_rr_timeslice_ms
    kernel.sched_rt_period_us
    kernel.sched_rt_runtime_us
    kernel.sched_wakeup_granularity_ns
    kernel.sem
    kernel.shmall
    kernel.shmmax
    kernel.shmmni
    net.core.busy_poll
    net.core.busy_read
    net.core.dev_weight
    net.core.rmem_default
    net.core.rmem_max
    net.core.rps_sock_flow_entries
    net.core.somaxconn
    net.core.wmem_default
    net.core.wmem_max
    net.ipv4.conf.all.accept_redirects
    net.ipv4.conf.all.accept_source_route
    net.ipv4.conf.all.rp_filter
    net.ipv4.icmp_echo_ignore_broadcasts
    net.ipv4.icmp_ignore_bogus_error_responses
    net.ipv4.ip_local_port_range
    net.ipv4.ip_local_port_range
    net.ipv4.tcp_fin_timeout
    net.ipv4.tcp_keepalive_time
    net.ipv4.tcp_max_syn_backlog
    net.ipv4.tcp_max_tw_buckets
    net.ipv4.tcp_moderate_rcvbuf
    net.ipv4.tcp_syncookies
    net.ipv4.tcp_wmem
    vm.dirty_background_ratio
    vm.dirty_ratio
    vm.max_map_count
    vm.overcommit_memory
    vm.swappiness
  )
  #https://stackoverflow.com/questions/1527049/how-can-i-join-elements-of-an-array-in-bash
  local name
  for name in ${check_items[@]}; do
    resmap[$name]=$(get_sysctl_value ${name})
  done
}

#===============================================================================
# @desc Get kernel tunable parameter from `sysctl -n`
# @param $1 Parameter name
#===============================================================================
function get_sysctl_value(){
  local name=$1
  local value=$(sysctl -n ${name} 2>/dev/null)
  echo "${value}"
}

#===============================================================================
# @desc Get oracle related config 
#===============================================================================
function check_oracle() {
  local val=false
  [ ! -z $(id -u oracle 2>/dev/null) ] && val=true
  resmap["oracle_installed"]=${val}
  local items=(
    fs.aio-max-nr
    fs.file-max
    kernel.shmall
    kernel.shmmax
    kernel.shmmni
    kernel.sem
    vm.dirty_ratio
    vm.dirty_background_ratio
    net.ipv4.ip_local_port_range
    net.core.rmem_default
    net.core.rmem_max
    net.core.wmem_default
    net.core.wmem_max
  )
  for name in ${items[@]}; do
    resmap[$name]=$(get_sysctl_value ${name})
  done
  resmap["transparent_hugepage_enabled"]=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)
}

#===============================================================================
# @desc Get webapp (weblogic/java/http) related config
#===============================================================================
function check_webapp() {
  local check_items=(
    net.ipv4.tcp_syncookies
    net.ipv4.tcp_fin_timeout
    net.ipv4.tcp_keepalive_time
    net.ipv4.ip_local_port_range
    net.ipv4.tcp_max_syn_backlog
    net.ipv4.tcp_max_tw_buckets
  )
  for name in ${check_items[@]}; do
    resmap[$name]=$(get_sysctl_value ${name})
  done
  local val
  if [[ ${resmap["net.ipv4.tcp_syncookies"]} == 1 ]] && [[ ${resmap["net.ipv4.tcp_fin_timeout"]} == 5 ]]; then val=1; else val=0; fi
  write_check "减少TCP连接中的TIME-WAIT" ${val} 
 
  local range=$(get_sysctl_value "net.ipv4.ip_local_port_range")
  resmap["net_ipv4_ip_local_port_range_min"]=$(echo ${range} | awk '{print $3}')
  resmap["net_ipv4_ip_local_port_range_max"]=$(echo ${range} | awk '{print $4}')
  if [[ ${resmap["net.ipv4.tcp_keepalive_time"]} -le 1200 ]] \
  && [[ ${resmap["net_ipv4_ip_local_port_range_min"]} -ge 10000 ]] \
  && [[ ${resmap["net_ipv4_ip_local_port_range_max"]} -le 65000 ]]  \
  && [[ ${resmap["net.ipv4.tcp_max_syn_backlog"]} -ge 16384 ]] \
  && [[ ${resmap["net.ipv4.tcp_max_tw_buckets"]} -ge 262144 ]]; then val=1; else val=0; fi
  write_check "TCP/IP的可使用端口范围" ${val} 

  resmap["ulimit_open_files"]=$(ulimit -n)
  resmap["ulimit_max_user_processes"]=$(ulimit -u)
  [[ ${resmap["ulimit_open_files"]} -ge 204800 ]] && [[ ${resmap["ulimit_max_user_processes"]} -ge 294800 ]] && val=1 || val=0
  write_check "用户资源限制调整" ${val} 
}

#===============================================================================
# @desc Get software packages with `rpm`
# @param $1 Name to grep
#===============================================================================
function get_package() {
  if [ ${resmap["OS_ID"]} == "ubuntu" ]; then
    dpkg -l | grep -E $1
  else
    rpm -qa 2>/dev/null | grep -E $1
  fi
}

#===============================================================================
# @desc Get file system related config
#===============================================================================
function check_filesystem() {
  resmap["fs_pvs"]=$(/sbin/pvs)
  #resmap["fs_info"]="{"`df -P -x tmpfs -x devtmpfs | tail -n +2 | awk '{print "\""$6"\":{\"fs\":\""$1"\",\"size\":"$2",\"avail\":"$4",\"use_pcent\":"substr($5, 1, length($5)-1)"}"}' | sed ':a;N;$!ba;s/\n/,/g' | sed ':a;N;$!ba;s/\n/,/g'`"}"
  # resmap["fs_json"]=$(df -P -x tmpfs -x devtmpfs | tail -n +2 | awk 'BEGIN {printf "\x27{"} {json=sprintf("\"%s\":{\"fs\":\"%s\",\"size\":%s,\"avail\":%s,\"use_pcent\":%s}",$6,$1,$2,$4,substr($5, 1, length($5)-1));printf json} END {printf "}\x27"}')
  resmap["fs_json"]=$(df -P -x tmpfs -x devtmpfs | tail -n +2 | awk 'BEGIN {printf "\x27{"; json=""} {json=sprintf("%s\"%s\":{\"fs\":\"%s\",\"size\":%s,\"avail\":%s,\"use_pcent\":%s},",json,$6,$1,$2,$4,substr($5, 1, length($5)-1))} END {printf substr(json,1,length(json)-1)"}\x27"}')
  #TODO: resmap["fs_result"]=
  # resmap["fs_part_size[\"boot\"]"]=$(lsblk -b 2>/dev/null | grep -w /boot | awk '{print $4}')
  # Use fs_part_size[boot] as key will cause error when re-declare (in print_map_as_yaml) in bash 4.2 before
  resmap["fs_partsize_boot_gb"]=$(lsblk -b 2>/dev/null | grep -w /boot | awk '{print $4/1024}')
  # resmap["lsblk_boot"]=${resmap["fs_part_size(boot)"]}
  local limit=${params[fs_overuse_limit]:-80}
  resmap["fs_overused_disk"]=$(df -P -x tmpfs -x devtmpfs | tail -n +2 | awk '{print $6": "substr($5,1,length($5)-1) }' \
    | awk -v limit="${limit}" '$2>limit' | sed -e ':a;N;$!ba;s/\n/,/g')
  resmap["fs_overused_inode"]=$(df -P -hi -x tmpfs -x devtmpfs | tail -n +2 | awk '{print $6": "substr($5,1,length($5)-1) }' \
    | awk -v limit="${limit}" '$2>limit' | sed -e ':a;N;$!ba;s/\n/,/g')
  resmap["fs_not_xfs"]=$(df -P -T -x tmpfs -x devtmpfs | tail -n +2 | awk '{if ($2 != "xfs") print $1" "$2}')
  resmap["fs_fstab_boot"]=$(cat /etc/fstab | grep -w /boot)
  resmap["pkg_fcsan"]=$(get_package "sysfsutils|sg3_utils")
}

#===============================================================================
# @desc Get security related config
#===============================================================================
function check_security() {
  #  enforcing, permissive, or disabled
  resmap["sys_selinux_mode"]=$(/usr/sbin/getenforce 2>/dev/null)
  local items=(
    net.ipv4.tcp_syncookies
    net.ipv4.conf.all.accept_source_route
    net.ipv4.conf.all.accept_redirects
    net.ipv4.conf.all.rp_filter
    net.ipv4.icmp_echo_ignore_broadcasts
    net.ipv4.icmp_ignore_bogus_error_responses
  ) 
  for name in ${items[@]}; do
    resmap[$name]=$(get_sysctl_value ${name})
  done
}

#===============================================================================
# @desc Save check result in `checks`
# @param $1 check item name
# @param $2 check result 0:failed,1:passed,-1:uncertain
# @param $3 metric value for review
#===============================================================================
function write_check(){
  local name=$1
  local result=$2
  local actual=$3
  checks[${name}]="$result,$actual" 
}

#===============================================================================
# @desc Get system related config
#===============================================================================
function check_system() {
  local val
  #----OS basic info
  #  09:56:35 up 294 days,  7:47,  1 user,  load average: 1.36, 1.22, 1.08
  #  11:02:46 up 17:52,  3 users,  load average: 0.00, 0.00, 0.00
  resmap["sys_uptime_day"]=$(/usr/bin/uptime |  grep -oP '\d+ (?=days)')
  # resmap["os_version"]=${resmap["OS_VER"]}
  resmap["os_kernel_release"]=$(uname -r)
  write_check "OS内核版本" -1 ${resmap["os_kernel_release"]}
  resmap["cpu_idle"]=$(cat /proc/cmdline | grep 'intel_idle\.max_cstate=0' | grep 'idel=poll' | wc -l)
  [ ${resmap["cpu_idle"]} -gt 0 ] && val=1 || val=0
  write_check "CPU不休眠" ${val} ${resmap["cpu_idle"]}

  #----Memory
  resmap["vm_swap_total_gb"]=$(/usr/bin/free -g | grep -w Swap | awk '{print $2}')
  [ "${resmap["vm_swap_total_gb"]}" -ge 32 ] && val=1 || val=0 
  write_check "交换分区大小" ${val} ${resmap["vm_swap_total_gb"]}"GB"

  resmap["transparent_hugepage_defrag"]=$(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null)
  #----Reliability, Availability and Serviceability
  resmap["pkg_rasdaemon"]=$(get_package rasdaemon)
  #----Storage
  resmap["pkg_multipath"]=$(get_package multipath)
  resmap["multipath_t"]=$(multipath -t 2>/dev/null)
  resmap["multipath_ll"]=$(/sbin/multipath -ll 2>/dev/null)
  #----Hardware diagnosis
  resmap["pkg_mcelog"]=$(get_package mcelog)
  resmap["hw_serial_number"]=$(/usr/sbin/dmidecode -t 1 | grep Serial | awk '{print $3}')

  #----Time and clock
  if [ ${IS_RHEL6} == true ]; then
    resmap["ntpd_conf"]=$(sed -e 's/[[:space:]]*#.*// ; /^[[:space:]]*$/d' /etc/sysconfig/ntpd)
  else #if [ "${IS_RHEL7}" == "true" ]; then
    resmap["chrony_conf"]=$(grep -E "^server|^maxchange 500 0 -1|^maxslewrate 500" /etc/chrony.conf 2>/dev/null)
  fi
  #----Misc
  resmap["iotop"]=$(/sbin/iotop 2>/dev/null)
}

#===============================================================================
# @desc Get network related config
#===============================================================================
function check_network() { 
  local val=-1
  local rmem=$(get_sysctl_value "net.ipv4.tcp_rmem")
  resmap["net.ipv4.tcp_rmem_min"]=$(echo "${rmem}" | awk '{print $1}')
  resmap["net.ipv4.tcp_rmem_default"]=$(echo "${rmem}" | awk '{print $2}')
  resmap["net.ipv4.tcp_rmem_max"]=$(echo "${rmem}" | awk '{print $3}')
  local wmem=$(get_sysctl_value "net.ipv4.tcp_wmem")
  resmap["net.ipv4.tcp_wmem_min"]=$(echo "${wmem}" | awk '{print $1}')
  resmap["net.ipv4.tcp_wmem_default"]=$(echo "${wmem}" | awk '{print $2}')
  resmap["net.ipv4.tcp_wmem_max"]=$(echo "${wmem}" | awk '{print $3}')
  if [ "${resmap["net.ipv4.tcp_wmem_min"]:-0}" -ge 8388608 ]  \
    && [ "${resmap["net.ipv4.tcp_wmem_default"]:-0}" -ge 8388608 ] \
    && [ "${resmap["net.ipv4.tcp_wmem_max"]:-0}" -ge 33554432 ]; then
    val=1
  else
    val=0
  fi
  write_check "tcp_wmem" ${val} "${wmem}"
  resmap["net_if"]=$(ifconfig -a | grep -E "^\w|inet addr")
  resmap["net_gateway"]=$(/bin/netstat -rn | grep "^0.0.0.0" | awk '{print $2}')
  resmap["fc_remote_ports"]=$(ls -l /sys/class/fc_remote_ports/ 2>/dev/null)
  resmap["iptraf"]=$(/sbin/iptraf -ng 2>/dev/null)
  #TODO: output too big
  #resmap["socket_info"]=`/sbin/ss`
}

#===============================================================================
# @desc Get kernel related config
#===============================================================================
function check_kernel() {
  run_sysctl
  local val
  if [ ${IS_RHEL6} == true ]; then
    val=$(cat /etc/inittab |grep 'initdefault:')
  else
    val=$(systemctl get-default)
  fi
  # resmap["systemctl_get_default"]=${val}
  resmap["sys_runlevel"]=${val}
  local output=$(cat /proc/cmdline)
  local re="crashkernel=([^ ]*)"
  [[ $output =~ $re ]] && resmap["crashkernel"]=$(echo ${BASH_REMATCH[1]}) || resmap["crashkernel"]=""
}

#===============================================================================
# @desc If a service is enabled (auto start)
# @param $1 service_name
#===============================================================================
function is_service_enabled() {
  get_service_status $1 "enabled"
}

#===============================================================================
# @desc If a service is active (running)
# @param $1 service_name
#===============================================================================
function is_service_active() {
  get_service_status $1 "active"
}

#===============================================================================
# @desc Get service status. It works for both `/etc/init.d` and `/usr/bin/systemctl`
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
      str=$(/etc/init.d/${service_name} status 2>/dev/null | grep -w "is running")
    fi
  elif [ "${IS_RHEL7}" == "true" ]; then
    if [ "${status}" == "enabled" ]; then
      str=$(/usr/bin/systemctl is-enabled ${service_name} | grep -w "enabled|static")
      [[ ! -z "${str}" ]] && out="true"
    elif [ "${status}" == "active" ]; then
      str=$(/usr/bin/systemctl is-active ${service_name} | grep -w "active")
    fi
  fi
  [[ ! -z "${str}" ]] && out="true"
  echo $out
}

#===============================================================================
# @desc Get service related config
#===============================================================================
function check_service() {
  # Check service items for RHEL 7.5
  # systemctl is-active/is-enabled <item>
  local items=(
    # Sound
    alsa-restore.service
    alsa-state.service
    bluetooth.service
    chronyd.service
    # Printing
    cups.service
    kdump.service
    mcelog.service
    multipathd.service
    ntpdate.service
    pmcd.service
    postfix.service
    rasdaemon.service
    sysstat.service
    tuned.service
  )
  if [ "${IS_RHEL6}" == "true" ]; then
    items=(
      # Power
      acpid
      cpuspeed
      cups
      ip6tables
      ipmi
      iptables
      kdump
      mcelogd
      mdmonitor
      multipathd
      NetworkManager
      ntpd
      postfix
      sysstat
      tuned
    )
  fi

  for item in ${items[@]}; do
    local item_name=${item}
    #    local array=(${element//=/ })
    #    local item=${array[0]}
    # Use command 2> /dev/null to throw away the error output from command
    # resmap["${item}_${command}"]=`/usr/bin/systemctl ${command} ${item} 2> /dev/null`
    [ -z $(echo ${item} | egrep '\.service') ] && item_name=${item}_service
    resmap["${item_name}_is_active"]=$(is_service_active ${item})
    resmap["${item_name}_is_enabled"]=$(is_service_enabled ${item})
  done
}


#===============================================================================
# Print `resmap` in YAML format. 
# @param NONE
#===============================================================================
function print_metrics() {
  echo "####METRIC_BEGIN:yaml"
  print_map_as_yaml "resmap"
  echo "####METRIC_END"
}

#===============================================================================
# Print `checks` in YAML format.
#===============================================================================
function print_checks() {
#   print_map_as_yaml checks
}

#===============================================================================
# @desc Print a map (associated array) in YAML format.
# It will convert as below
# - item name: replace `-`,`.` with `_`
# - item value: to YAML value
# @usage print_map_as_yaml "resmap"
# @param $1 the name of map
# https://stackoverflow.com/questions/4069188/how-to-pass-an-associative-array-as-argument-to-a-function-in-bash
#===============================================================================
function print_map_as_yaml() {
  # Use -p get the `declare -A <arr_name>='(<arr_values>)'` expression
  local expr=$(declare -p $1)
  # Get value part after `<arr_name>=`
  local arr_expr=${expr#*=}
  # Create a new array by `declare -A <arr_expr>`
  # Direct call of `declare -A items=${arr_expr}` works in bash 4.3+, not for bash 4.2 (CentOS 6.10)
  # Use eval as workaround. TODO: if bash_ver<4.3 eval.. else declare -A items=${arr_expr}
  eval "declare -A items=${arr_expr}"
 
  # Now we get the associated array in `items`
  # Sort keys
  local keys=$(
  for key in ${!items[@]}; do
    echo "${key}"
  done | sort | awk '{print $0}'
  )
  local item
  local value
  for key in ${keys}; do
    item=$(echo ${key} | sed -e "s/[-\.]/_/g")
    # Use double quotes "${resmap[$key]}" to preserve line breaks in value
    value=$(to_safe_yaml "${items[${key}]}")
    echo ${item}: "${value}"
  done
}

#===============================================================================
# Parse command line arguments and put in `params`
# https://stackoverflow.com/questions/59358858/bash-to-split-string-with-space-separated-value-with-double-quote
#===============================================================================
function parse_args(){
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
# @desc Main
#===============================================================================
function main() {
  check_kernel
  check_filesystem
  check_network
  check_system
  check_security
  check_service
  check_webapp
  check_oracle
  print_metrics
  print_checks
}

#===============================================================================
# @desc For test only
#===============================================================================
function utest() {
  if [ ${IS_RHEL7} == true ]; then
    echo This is rhel7
  elif [ ${IS_RHEL6} == true ]; then
    echo This is rhel6
  fi
  # print_metrics
  local str="$*"
  declare -A items=()
  items["test[boot]"]=abc
  items["quote[\"boot\"]"]=123
 # print_map_as_yaml "amap"
  local keys=$(
  for key in ${!items[@]}; do
    echo "${key}"
  done | sort | awk '{print $0}'
  )
  for key in ${keys}; do
    item=$(echo ${key} | sed -e "s/[-\.]/_/g")
    # Use double quotes "${resmap[$key]}" to preserve line breaks in value
    value=$(to_safe_yaml "${items[${key}]}")
    echo ${item}: "${value}"
  done
}

init "$@"
if [ "$1" == "test" ]; then
  utest "$@"
else
  main "$@"
fi

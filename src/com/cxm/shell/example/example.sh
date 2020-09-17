#!/usr/bin/env bash

source oplus-lib-1.0.sh

function check_sample() {
  local value
  write_metric "hostname" "$(hostname)"
  value=$(route -n)
  write_metric "net_route" "${value}" "路由信息"
  value=$(df -l | awk '{if ($6 == "/") { print $5 }}' | head -1 | cut -d'%' -f1)
  write_metric "disk_use_pcent" "${value}" "磁盘利用率"
}

check_sample
print_metrics
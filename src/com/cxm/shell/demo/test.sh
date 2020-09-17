#!/usr/bin/env bash

yaml_format="kv"
declare -A _metric_values=(["A"]="a" ["B"]="b" ["C"]="c");
declare -A _metric_descs=(["D"]="d" ["E"]="e" ["F"]="f");

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
function _print_map_as_yaml() {
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
print_metrics
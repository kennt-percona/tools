#!/bin/bash

if [[ "$#" != 3 ]]; then
    echo "Usage: run-test.sh <output-dir> <index|noindex> <tables-count>"
    exit 1
fi

output_dir="${1}"
index_or_no_index="${2}"
tables_count=$3

if [[ "$index_or_no_index" == "index" ]]; then
    test_file="/usr/share/doc/sysbench/tests/db/update_index.lua"
elif [[ "$index_or_no_index" == "noindex" ]]; then
    test_file="/usr/share/doc/sysbench/tests/db/update_non_index.lua"
else
    echo "Only index or noindex are allowed values: $index_or_no_index" 1>&2
    exit 2
fi

. $(dirname $0)/run-common.sh

prepare_timer_file

cpu_usage=100
while [ "$cpu_usage" -gt 10 ]
do
  sleep 3s
  cpu_usage=$(top -p $(pidof mysqld) -n 1 -b | grep mysqld-deb | awk '{ print $9}')
  printf -v cpu_usage "%.0f" $cpu_usage
done
sleep 5s

dump_system_configuration
run_warmup
run_single_test 1 
run_single_test 2
run_single_test 4
run_single_test 8
run_single_test 16
run_single_test 32
run_single_test 48
run_single_test 64
run_single_test 96
run_single_test 128


#!/bin/bash
#
# Runs a single instance of the test (for 64 client threads)
#

timer_pid=0

sig_cleanup()
{
  if [[ $timer_pid -ne 0 ]]; then
    kill $timer_pid
  fi
}

trap sig_cleanup INT TERM EXIT

if [[ "$#" != 3 ]]; then
  echo "Usage: run-multi-test.sh <test-type> <ssl/nossl> <applier-count>"
  exit 1
fi

test_type=$1
ssl_or_nossl=$2
applier_count=$3

printf -v applier_count "%02d" $applier_count

table_count=4
printf -v table_count "%02d" $table_count

test_dir="short-${test_type}-${ssl_or_nossl}-${applier_count}-${table_count}"
mkdir -p $test_dir
cd $test_dir
../run-timer.sh &
timer_pid=$!
cd ..

./run-test-64.sh $test_dir index $table_count
kill $timer_pid
timer_pid=0

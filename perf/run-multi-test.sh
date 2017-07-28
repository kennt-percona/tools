#!/bin/bash
#
# Runs the test multiple times (currently 11)
#

declare -a arr=("4")

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

for i in "${arr[@]}"
do
  table_count=""
  printf -v table_count "%02d" $i

  for test_iter in 1 2 3 4 5 6 7 8 9 10 11
  do
    test_dir="multi-${test_type}-${ssl_or_nossl}-${applier_count}-${table_count}.${test_iter}"
    mkdir -p $test_dir
    cd $test_dir
    ../run-timer.sh &
    timer_pid=$!
    cd ..

    ./run-test.sh $test_dir index "$i"
    kill $timer_pid
    timer_pid=0
  done
done


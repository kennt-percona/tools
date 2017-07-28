#!/bin/bash


#
# This file assumes that these variables have been set.
#
if [[ -z "$output_dir" ]]; then
  echo "The output_dir variable has not been set" 1>&2
  exit 1
fi

if [[ -z "$index_or_no_index" ]]; then
  echo "The index_or_no_index variable has not been set" 1>&2
  exit 1
fi

if [[ -z "$tables_count" ]]; then
  echo "The tables_count variable has not been set" 1>&2
  exit 1
fi

output_dir="${1}"
index_or_no_index="${2}"
tables_count=$3

dump_system_configuration()
{
  stdbuf -o1K ./bin/mysql -uroot -Sdata/socket.sock -e "show status where variable_name in ('wsrep_flow_control_interval', 'wsrep_cluster_size' ); show variables where variable_name in ('wsrep_slave_threads' );" | grep wsrep  | awk '{ print "-- " $0 }' >> $output_dir/timer.txt

  stdbuf -o1K ./bin/mysql -uroot -h10.10.7.165 -e "show status where variable_name in ('wsrep_flow_control_interval', 'wsrep_cluster_size' ); show variables where variable_name in ('wsrep_slave_threads' );" | grep wsrep  | awk '{ print "== " $0 }' >> $output_dir/timer.txt


}

dump_statistics()
{
  stdbuf -o1K ./bin/mysql -uroot -Sdata/socket.sock -e "show status where variable_name in ('wsrep_flow_control_recv', 'wsrep_flow_control_paused', 'wsrep_flow_control_paused_ns', 'wsrep_local_send_queue_avg', 'wsrep_local_send_queue_min', 'wsrep_local_send_queue_max', 'wsrep_cert_deps_distance' );" | grep wsrep  | awk '{ print "-- " $0 }' >> $output_dir/timer.txt


  stdbuf -o1K ./bin/mysql -uroot -h10.10.7.165 -e "show status where variable_name in ( 'wsrep_local_recv_queue_avg', 'wsrep_local_recv_queue_min', 'wsrep_local_recv_queue_max', 'wsrep_cert_deps_distance' );" | grep wsrep  | awk '{ print "== " $0 }' >> $output_dir/timer.txt
}


#
# Warmup the system
#
run_warmup()
{
  local num_threads=16
  local test_output=""

  sleep 2s
  stdbuf -oL echo "Starting warmup" >> $output_dir/timer.txt
  ./bin/mysql -uroot -Sdata/socket.sock -e "flush status"
  ./bin/mysql -uroot -h10.10.7.165 -e "flush status"
  stdbuf -oL echo "Flush status called" >> $output_dir/timer.txt
  dump_statistics

  sysbench --test=$test_file --mysql-user=root --mysql-socket=data/socket.sock --num-threads=$num_threads --max-time=30 --max-requests=0 --report-interval=5 --oltp-tables-size=1000000 --oltp-tables-count=16 run > /dev/null

  stdbuf -oL echo "Ending warmup" >> $output_dir/timer.txt
  dump_statistics
  sleep 5s
  # sleep until the cpu usage drops below 10%
  cpu_usage=100
  while [ "$cpu_usage" -gt 10 ]
  do
    sleep 3s
    cpu_usage=$(top -p $(pidof mysqld) -n 1 -b | grep mysqld-deb | awk '{ print $9}')
    printf -v cpu_usage "%.0f" $cpu_usage

    if [ "$cpu_usage" -le 10 ]; then
      # try again, just to make sure we've hit 0
      sleep 3s
      cpu_usage=$(top -p $(pidof mysqld) -n 1 -b | grep mysqld-deb | awk '{ print $9}')
      printf -v cpu_usage "%.0f" $cpu_usage
    fi
  done
  sleep 5s

}

#
# Get the CPU usage
# does a single run
# writes out a comment to the timing file (assumed to be in test directory
# and named timer.txt
#
# parameters:
#  (1) : number of threads
#

run_single_test()
{
  local num_threads=$1
  local test_output=""
  printf -v test_output "test%03d-1.data" "$num_threads"

  sleep 2s
  stdbuf -oL echo "Starting test with threads=$num_threads" >> $output_dir/timer.txt
  ./bin/mysql -uroot -Sdata/socket.sock -e "flush status"
  stdbuf -oL echo "Flush status called" >> $output_dir/timer.txt
  dump_statistics 

  sysbench --test=$test_file --mysql-user=root --mysql-socket=data/socket.sock --num-threads=$num_threads --max-time=100 --max-requests=0 --report-interval=5 --oltp-tables-size=1000000 --oltp-tables-count=$tables_count run > "$output_dir/$test_output"

  stdbuf -oL echo "Ending test with threads=$num_threads" >> $output_dir/timer.txt
  dump_statistics
  sleep 5s
  # sleep until the cpu usage drops below 10%
  cpu_usage=100
  while [ "$cpu_usage" -gt 10 ]
  do
    sleep 3s
    cpu_usage=$(top -p $(pidof mysqld) -n 1 -b | grep mysqld-deb | awk '{ print $9}')
    printf -v cpu_usage "%.0f" $cpu_usage

    if [ "$cpu_usage" -le 10 ]; then
      # try again, just to make sure we've hit 0
      sleep 3s
      cpu_usage=$(top -p $(pidof mysqld) -n 1 -b | grep mysqld-deb | awk '{ print $9}')
      printf -v cpu_usage "%.0f" $cpu_usage
    fi
  done
  sleep 5s

}

#
# Overwrite the timer file
#

prepare_timer_file()
{
  stdbuf -oL echo "              PID USER      PR  NI    VIRT    RES    SHR S   CPU  MEM      TIME COMMAND"  > $output_dir/timer.txt
}




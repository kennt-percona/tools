#! /bin/sh

#echo "              PID  USER      PR  NI    VIRT    RES    SHR S   CPU  MEM      TIME COMMAND" > timer.txt

while true
do
    date_s=$(date "+%H:%M:%S")
    top_s=$(top -p $(pidof mysqld-debug) -n 1 -b | grep mysqld)
    stdbuf -oL echo "$date_s == $top_s"
    sleep 2
done


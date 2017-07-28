#! /bin/sh

echo "              PID  USER      PR  NI    VIRT    RES    SHR S   CPU  MEM      TIME COMMAND" > timer.txt

while true
do
    date_s=$(date "+%H:%M:%S")
    top_s=$(top -p $(pidof mysqld) -n 1 -b | grep mysqld)
    stdbuf -oL echo "$date_s == $top_s" >> timer.txt
    sleep 2
done


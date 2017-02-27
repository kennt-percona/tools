#! /bin/bash

MYSQL_CLIENT="/home/kennt/dev/pxc/build-bin/bin/mysql"

for i in `seq 1 10`;
do
	# Drop database
	sleep 1
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot -e "drop database $1$i"
done


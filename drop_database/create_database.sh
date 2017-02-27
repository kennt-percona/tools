#! /bin/bash

MYSQL_CLIENT="/home/kennt/dev/pxc/build-bin/bin/mysql"

for i in `seq 1 30`;
do
	# Create a database with 10 tables
	echo "Creating database a$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot -e "create database a$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot --database="a$i" < create_tables.sh
done

for i in `seq 1 30`;
do
	# Create a database with 10 tables
	echo "Creating database b$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot -e "create database b$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot --database="b$i" < create_tables.sh
done

for i in `seq 1 30`;
do
	# Create a database with 10 tables
	echo "Creating database c$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot -e "create database c$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot --database="c$i" < create_tables.sh
done

for i in `seq 1 30`;
do
	# Create a database with 10 tables
	echo "Creating database d$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot -e "create database d$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot --database="d$i" < create_tables.sh
done

for i in `seq 1 30`;
do
	# Create a database with 10 tables
	echo "Creating database e$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot -e "create database e$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot --database="e$i" < create_tables.sh
done

for i in `seq 1 30`;
do
	# Create a database with 10 tables
	echo "Creating database f$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot -e "create database f$i"
	$MYSQL_CLIENT -h127.0.0.1 -P4000 -uroot --database="f$i" < create_tables.sh
done



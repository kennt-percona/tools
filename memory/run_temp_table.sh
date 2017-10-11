#!/bin/bash

while true
  do
  	# Create a temp table
  	./bin/mysql -Snode1/socket.sock -uroot <<EOF
  	    USE ez47_001;
        CREATE TEMPORARY TABLE zztop (id int primary key auto_increment, f2 longblob);
        INSERT INTO zztop(f2) VALUES('abcd');
        DROP TABLE zztop;
EOF
  done

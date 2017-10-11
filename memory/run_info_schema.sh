#!/bin/bash

while true
  do
    ./bin/mysql -Snode1/socket.sock -uroot -e "SELECT table_schema 'dbname', SUM((data_length+index_length)/1024/1024) 'total_size' FROM information_schema.tables WHERE table_schema LIKE 'ez47_%' OR table_schema LIKE 'drupal8_%' GROUP BY table_schema;" > /dev/null
  done

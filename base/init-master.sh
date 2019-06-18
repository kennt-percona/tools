#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#

#
# Global variables
#
declare     BUILD=$(pwd)

if (( "$#" != 1 )); then
  echo "Incorrect number of parameters"
  echo ""
  echo "Usage:  init-master.sh <node-name>"
  echo ""
  echo "Initializes the node for being an async master"
  echo ""
  exit 1
fi

declare     NODE_NAME="${1}"
declare     DATADIR_BASE_PATH="${BUILD}"
declare     NODE_DATADIR="${DATADIR_BASE_PATH}/${NODE_NAME}"

#
# Configure the master for replication
#
echo 'Setting up the user account on the master'

${BUILD}/bin/mysql -S${NODE_DATADIR}/socket.sock -uroot <<EOF
  CREATE USER 'repl'@'%' IDENTIFIED WITH 'mysql_native_password' BY 'repl'; 
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
  FLUSH PRIVILEGES;
EOF

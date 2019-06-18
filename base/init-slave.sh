#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#

#
# Global variables
#
declare     BUILD=$(pwd)

if (( "$#" != 3 )); then
  echo "Incorrect number of parameters"
  echo ""
  echo "Usage:  init-master.sh <node-name> <master-ip> <master-port>"
  echo ""
  echo "Initializes the node for being an async slave
  echo ""
  exit 1
fi

declare     NODE_NAME="${1}"
declare     IPADDR="${2}"
declare     BASE_PORT=${3}

declare     DATADIR_BASE_PATH="${BUILD}"
declare     NODE_DATADIR="${DATADIR_BASE_PATH}/${NODE_NAME}"

#
# Configure the master for replication
#
echo 'Setting up the slave to connect to the master'

${BUILD}/bin/mysql -S${NODE_DATADIR}/socket.sock -uroot <<EOF
  STOP SLAVE;
  CHANGE MASTER TO MASTER_HOST='$IPADDR', MASTER_PORT=$RBASE, MASTER_USER='repl', MASTER_PASSWORD='repl';
EOF

echo "Slave configured.  Run 'start slave'"

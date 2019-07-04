#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#

#
# Global variables
#
declare     BUILD=$(pwd)

if [[ "$#" -ne 2 && "$#" -ne 3 ]]; then
  echo "Incorrect number of parameters"
  echo ""
  echo "Usage:  init-slave.sh <slave-node>  <master-node> [<channel-name>]"
  echo ""
  echo "If <channel-name> is specified, that will be the name used for the channel"
  echo "This is used for multi-source replication"
  echo ""
  echo "Initializes the node for being an async slave"
  echo ""
  exit 1
fi

declare     SLAVE_NODE_NAME=$1
declare     MASTER_NODE_NAME=$2

declare     CHANNDEL_NAME=""
declare     MASTER_CHANNEL=""

if [[ "$#" == "3" ]]; then
  CHANNEL_NAME=$3
  MASTER_CHANNEL="FOR CHANNEL '${3}'"
fi

declare     DATADIR_BASE_PATH="${BUILD}"
declare     NODE_DATADIR="${DATADIR_BASE_PATH}/${SLAVE_NODE_NAME}"

if [[ ! -r "${MASTER_NODE_NAME}.info" ]]; then
  echo "\"Cannot find the \${MASTER_NODE_NAME}}.info\" file"
  exit 1
fi

MASTER_IP=$(cat "${MASTER_NODE_NAME}.info" | grep "IP address" | cut -d':' -f2)
MASTER_IP=$(echo $MASTER_IP)

MASTER_PORT=$(cat "${MASTER_NODE_NAME}.info" | grep "Client port" | cut -d':' -f2)
MASTER_PORT=$(echo $MASTER_PORT)

#
# Configure the slave for replication
#
echo 'Setting up the slave to connect to the master'
echo "Setting the channel: host:$MASTER_IP port:$MASTER_PORT channel_name:$CHANNEL_NAME"

${BUILD}/bin/mysql -S${NODE_DATADIR}/socket.sock -uroot <<EOF
  STOP SLAVE;
  CHANGE MASTER TO MASTER_HOST='$MASTER_IP', MASTER_PORT=$MASTER_PORT, MASTER_USER='repl', MASTER_PASSWORD='repl' ${MASTER_CHANNEL};
EOF

echo "Slave configured.  Run 'start slave'"

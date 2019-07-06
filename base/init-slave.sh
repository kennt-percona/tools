#!/bin/bash
#
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $0)/../include/tools_common.sh

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

declare     MASTER_NODE_NAME=$1
declare     SLAVE_NODE_NAME=$2

declare     CHANNEL_NAME=""
declare     CHANNEL_OPTIONS=""

if [[ "$#" == "3" ]]; then
  CHANNEL_NAME=$3
  CHANNEL_OPTIONS="FOR CHANNEL '${3}'"
fi

master_node_info_path="${MASTER_NODE_NAME}.info"
if [[ ! -r ${master_node_info_path} ]]; then
  echo "Error: Cannot find the ${master_node_info_path} file"
  exit 1
fi

slave_node_info_path="${SLAVE_NODE_NAME}.info"
if [[ ! -r ${slave_node_info_path} ]]; then
  echo "Error: Cannot find the ${slave_node_info_path} file"
  exit 1
fi

# get info from the info file
master_ip_address=$(info_get_variable "${master_node_info_path}" "ip-address")
master_port=$(info_get_variable "${master_node_info_path}" "client-port")

basedir=$(info_get_variable "${slave_node_info_path}" "basedir")
socket=$(info_get_variable "${slave_node_info_path}" "socket")


#
# Configure the slave for replication
#
echo "Setting up the slave($SLAVE_NODE_NAME) to connect to the master($MASTER_NODE_NAME)"
echo "Setting the channel: host:$master_ip_address port:$master_port channel_name:$CHANNEL_NAME"

${basedir}/bin/mysql -S${socket} -uroot <<EOF
  STOP SLAVE;
  CHANGE MASTER TO MASTER_HOST='$master_ip_address', MASTER_PORT=$master_port, MASTER_USER='repl', MASTER_PASSWORD='repl' ${CHANNEL_OPTIONS};
EOF

echo "Slave configured.  Run 'start slave' to start async replication."

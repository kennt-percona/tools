#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#
# This script will create a single PXC node.
# 

. $(dirname $0)/../include/tools_common.sh

# check for config file parameter
if (( "$#" != 4 )); then
  echo "Incorrect number of parameters"
  echo ""
  echo "Usage:  pxc-config.sh <node-name> <config-file> <ipaddr> <base-port>"
  echo ""
  echo "Creates the following scripts:"
  echo "  <node-name>_init    : Creates subdirectories and initializes the datadir"
  echo "  <node-name>_new_cluster : Starts a new cluster"
  echo "  <node-name>_join_cluster : Joins an existing cluster"
  echo "  <node-name>_stop    : Stops the node"
  echo "  <node-name>_cl      : Opens a mysql shell to a node"
  echo "  <node-name>_query   : Sends a query to a node"
  echo "  <node-name>_wipe    : Stops the cluster, removes subdirectories"
  echo ""
  exit 1
fi

#
# Global variables
#
declare     BUILD=$(pwd)

declare     NODE_NAME="${1}"
declare     CONFIG_FILE_PATH="${2}"
declare     IPADDR="${3}"
declare     BASE_PORT=${4}

declare -i  RBASE=${BASE_PORT}

# Listen address
declare -i  LPORT=$(( RBASE + 30 ))
declare     LADDR="$IPADDR:$LPORT"

# Receive address
declare -i  RPORT=$(( RBASE + 20 ))
declare     RADDR="$IPADDR:$RPORT"

declare     DATADIR_BASE_PATH="${BUILD}"
declare     NODE_DATADIR="${DATADIR_BASE_PATH}/${NODE_NAME}"


INIT_SCRIPT_NAME="${NODE_NAME}_init"
NEW_CLUSTER_SCRIPT_NAME="${NODE_NAME}_new_cluster"
JOIN_CLUSTER_SCRIPT_NAME="${NODE_NAME}_join_cluster"
STOP_SCRIPT_NAME="${NODE_NAME}_stop"
CL_SCRIPT_NAME="${NODE_NAME}_cl"
QUERY_SCRIPT_NAME="${NODE_NAME}_query"
WIPE_SCRIPT_NAME="${NODE_NAME}_wipe"
INFO_SCRIPT_NAME="${NODE_NAME}.info"


if [[ ! -r "${CONFIG_FILE_PATH}" ]]; then
  echo "Cannot find the config file : '${CONFIG_FILE_PATH}'"
  exit 1
fi


echo ""
echo "Adding scripts:"
echo "  ${NODE_NAME}_init  : Creates subdirectories and initializes the datadirs"
echo "  ${NODE_NAME}_new_cluster : Starts the node in a new cluster"
echo "  ${NODE_NAME}_join_cluster : Starts the node and joins a cluster"
echo "  ${NODE_NAME}_stop  :  Stops the node"
echo "  ${NODE_NAME}_cl    :  Opens a mysql shell to the node"
echo "  ${NODE_NAME}_query :  Sends a query to a node"
echo "  ${NODE_NAME}_wipe  :  Stops the node, removes the subdirectories"
echo ""


declare mysql_version=$(get_version "${BUILD}/bin/mysqld")

# Info script (prints out information about the node)
echo "Node name     : ${NODE_NAME}" > ./${INFO_SCRIPT_NAME}
echo "MySQL version : ${mysql_version}" >> ./${INFO_SCRIPT_NAME}
echo "Datadir       : ${NODE_DATADIR}" >> ./${INFO_SCRIPT_NAME}
echo "Socket        : ${NODE_DATADIR}/socket.sock" >> ./${INFO_SCRIPT_NAME}
echo "IP address    : ${IPADDR}" >> ./${INFO_SCRIPT_NAME}
echo "Client port   : ${RBASE}" >> ./${INFO_SCRIPT_NAME}
echo "Galera port   : ${LPORT}" >> ./${INFO_SCRIPT_NAME}
echo "SST port      : ${RPORT}" >> ./${INFO_SCRIPT_NAME}
echo "Cluster address: ${IPADDR}:${LPORT}" >> ./${INFO_SCRIPT_NAME}
echo "" >> ./${INFO_SCRIPT_NAME}


#
# Create the init script 
#
echo "" > ./${INIT_SCRIPT_NAME}
echo "echo 'Initializing MySQL $mysql_version'" >> ./${INIT_SCRIPT_NAME}
echo "PXC_START_TIMEOUT=30" >> ./${INIT_SCRIPT_NAME}
echo "" >> ./${INIT_SCRIPT_NAME}
echo "echo 'Creating subdirectores'" >> ./${INIT_SCRIPT_NAME}
echo "mkdir -p $NODE_DATADIR" >> ./${INIT_SCRIPT_NAME}

echo "echo 'Initializing datadirs ($NODE_DATADIR)'" >> ./${INIT_SCRIPT_NAME}

if [[ $mysql_version =~ ^5.6 ]]; then
  echo "MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./${INIT_SCRIPT_NAME}
elif [[ $mysql_version =~ ^5.7 ]]; then
  echo "MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./${INIT_SCRIPT_NAME}
elif [[ $mysql_version =~ ^8.0 ]]; then
  echo "MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./${INIT_SCRIPT_NAME}
else
  echo "Error: Unsupported MySQL version : $mysql_version"
  exit 1
fi
echo -e "\n" >> ./${INIT_SCRIPT_NAME}

echo "\${MID} --datadir=$NODE_DATADIR  > ${BUILD}/startup_${NODE_NAME}.err 2>&1 || exit 1;" >> ./${INIT_SCRIPT_NAME}

echo "echo 'Replacing DATADIR_BASE_PATH with $DATADIR_BASE_PATH in $CONFIG_FILE_PATH'" >> ./${INIT_SCRIPT_NAME}

# Need to escape any slashes in the datadir (since it will contain a path)
# This will change '/' to '\/'
#safe_node_datadir=${node_datadir//\//\/\\/}
echo "sed -i 's/DATADIR_BASE_PATH/${DATADIR_BASE_PATH//\//\\/}/' \"$CONFIG_FILE_PATH\"" >> ./${INIT_SCRIPT_NAME}

echo -e "\n" >> ./${INIT_SCRIPT_NAME}


#
# Creating ${NEW_CLUSTER_SCRIPT_NAME}
#
echo "PXC_MYEXTRA=\"\"" > ./${NEW_CLUSTER_SCRIPT_NAME}
echo "PXC_START_TIMEOUT=30"  >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo -e "\n" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "echo 'Starting PXC nodes..'" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo -e "\n" >> ./${NEW_CLUSTER_SCRIPT_NAME}

echo "echo 'Starting $NODE_NAME..'" >> ./${NEW_CLUSTER_SCRIPT_NAME}

echo "${BUILD}/bin/mysqld --defaults-file="${CONFIG_FILE_PATH}" --defaults-group-suffix=.$NODE_NAME \\" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    --port=$RBASE \\" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    --wsrep_cluster_address=gcomm:// \\" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    --wsrep_sst_receive_address=$RADDR \\" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    --wsrep_node_incoming_address=$IPADDR \\" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR;gmcast.segment=1\" \\" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    --wsrep-new-cluster  > $NODE_DATADIR/error.log 2>&1 &" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "mysqld_pid=\$!" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo -e "\n" >> ./${NEW_CLUSTER_SCRIPT_NAME}

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "  sleep 1" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "  if ! ps --pid \$mysqld_pid >/dev/null; then" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    echo \"Process mysqld (\$mysqld_pid) failed to start\"" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    exit 1" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "  fi" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$NODE_DATADIR/socket.sock ping > /dev/null 2>&1; then" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "    break" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "  fi" >> ./${NEW_CLUSTER_SCRIPT_NAME}
echo "done" >> ./${NEW_CLUSTER_SCRIPT_NAME}

echo -e "\n" >> ./${NEW_CLUSTER_SCRIPT_NAME}


#
# Joining a cluster
#
echo -e "\n" > ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "if (( \"\$#\" != 1 )); then" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  echo \"Usage: ${JOIN_CLUSTER_SCRIPT_NAME} <cluster-address>\"" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  exit 1" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "fi" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo -e "\n" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "CLUSTER_ADDRESS=\$1" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "if [[ -r "\$1.info" ]]; then" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  CLUSTER_ADDRESS=\$(cat "\$1.info" | grep \"Cluster address\" | cut -d':' -f2-)" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  CLUSTER_ADDRESS=\${CLUSTER_ADDRESS# }" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "fi" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "PXC_MYEXTRA=\"\"" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "PXC_START_TIMEOUT=30"  >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo -e "\n" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "echo 'Starting PXC nodes..'" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo -e "\n" >> ./${JOIN_CLUSTER_SCRIPT_NAME}

echo "echo 'Starting $NODE_NAME..'" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "echo \"Joining cluster at \$CLUSTER_ADDRESS\"" >> ./${JOIN_CLUSTER_SCRIPT_NAME}

echo "${BUILD}/bin/mysqld --defaults-file="${CONFIG_FILE_PATH}" --defaults-group-suffix=.$NODE_NAME \\" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    --port=$RBASE \\" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    --wsrep_cluster_address=gcomm://\$CLUSTER_ADDRESS \\" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    --wsrep_sst_receive_address=$RADDR \\" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    --wsrep_node_incoming_address=$IPADDR \\" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR;gmcast.segment=1\" \\" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    > $NODE_DATADIR/error.log 2>&1 &" >> ./${JOIN_CLUSTER_SCRIPT_NAME}

echo "mysqld_pid=\$!" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo -e "\n" >> ./${JOIN_CLUSTER_SCRIPT_NAME}

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  sleep 1" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  if ! ps --pid \$mysqld_pid >/dev/null; then" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    echo \"Process mysqld (\$mysqld_pid) failed to start\"" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    exit 1" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  fi" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$NODE_DATADIR/socket.sock ping > /dev/null 2>&1; then" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "    break" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "  fi" >> ./${JOIN_CLUSTER_SCRIPT_NAME}
echo "done" >> ./${JOIN_CLUSTER_SCRIPT_NAME}

echo -e "\n" >> ./${JOIN_CLUSTER_SCRIPT_NAME}


#
# Creating stop
#
echo "if [[ -r ${NODE_DATADIR}/socket.sock ]]; then" > ./${STOP_SCRIPT_NAME}
echo "  ${BUILD}/bin/mysqladmin -uroot -S${NODE_DATADIR}/socket.sock shutdown" >> ./${STOP_SCRIPT_NAME}
echo "  echo 'Server on socket ${NODE_DATADIR}/socket.sock with datadir ${NODE_DATADIR} halted'" >> ./${STOP_SCRIPT_NAME}
echo "fi" >> ./${STOP_SCRIPT_NAME}
echo  "" >> ./${STOP_SCRIPT_NAME}


#
# Creating wipe
#
echo "if [ -r ./${STOP_SCRIPT_NAME} ]; then ./${STOP_SCRIPT_NAME} 2>/dev/null 1>&2; fi" > ./${WIPE_SCRIPT_NAME}
echo "if [ -d ${NODE_DATADIR} ]; then rm -rf ${NODE_DATADIR}; fi" >> ./${WIPE_SCRIPT_NAME}

echo "rm ./${INIT_SCRIPT_NAME} ./${NEW_CLUSTER_SCRIPT_NAME} ./${JOIN_CLUSTER_SCRIPT_NAME}" >> ./${WIPE_SCRIPT_NAME}
echo "rm ./${CL_SCRIPT_NAME} ./${QUERY_SCRIPT_NAME} " >> ./${WIPE_SCRIPT_NAME}
echo "rm ./${STOP_SCRIPT_NAME} ./${INFO_SCRIPT_NAME} " >> ./${WIPE_SCRIPT_NAME}
echo "" >> ./${WIPE_SCRIPT_NAME}

#
# Creating command-line scripts
#
echo "#! /bin/bash" > ./${CL_SCRIPT_NAME}
echo "" >> ./${CL_SCRIPT_NAME}
echo "if (( \"\$#\" != 0 )); then" >> ./${CL_SCRIPT_NAME}
echo "  echo \"Usage: ${NODE_NAME}_cl\"" >> ./${CL_SCRIPT_NAME}
echo "  exit 1" >> ./${CL_SCRIPT_NAME}
echo "fi" >> ./${CL_SCRIPT_NAME}
echo "" >> ./${CL_SCRIPT_NAME}
echo "$BUILD/bin/mysql -A -S$BUILD/${NODE_NAME}/socket.sock -uroot " >> ./${CL_SCRIPT_NAME}

echo "#! /bin/bash" > ./${QUERY_SCRIPT_NAME}
echo "" >> ./${QUERY_SCRIPT_NAME}
echo "if (( \"\$#\" != 1 )); then" >> ./${QUERY_SCRIPT_NAME}
echo "  echo \"Usage: ${NODE_NAME}_query <query>\"" >> ./${QUERY_SCRIPT_NAME}
echo "  exit 1" >> ./${QUERY_SCRIPT_NAME}
echo "fi" >> ./${QUERY_SCRIPT_NAME}
echo "" >> ./${QUERY_SCRIPT_NAME}
echo "$BUILD/bin/mysql -A -S$BUILD/${NODE_NAME}/socket.sock -uroot -e \"\$1\"" >> ./${QUERY_SCRIPT_NAME}

chmod +x ./${INIT_SCRIPT_NAME} ./${NEW_CLUSTER_SCRIPT_NAME} ./${JOIN_CLUSTER_SCRIPT_NAME}
chmod +x ./${STOP_SCRIPT_NAME} ./${CL_SCRIPT_NAME} ./${QUERY_SCRIPT_NAME} ./${WIPE_SCRIPT_NAME}


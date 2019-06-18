#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#
# This script will create a single standalone node (no cluster).
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
  echo "  <node-name>_start   : Starts a new cluster"
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
declare     LADDR="$IPADDR:$(( RBASE + 30 ))"
# Receive address
declare     RADDR="$IPADDR:$(( RBASE + 20 ))"

declare     DATADIR_BASE_PATH="${BUILD}"
declare     NODE_DATADIR="${DATADIR_BASE_PATH}/${NODE_NAME}"


INIT_SCRIPT_NAME="${NODE_NAME}_init"
START_SCRIPT_NAME="${NODE_NAME}_start"
STOP_SCRIPT_NAME="${NODE_NAME}_stop"
CL_SCRIPT_NAME="${NODE_NAME}_cl"
QUERY_SCRIPT_NAME="${NODE_NAME}_query"
WIPE_SCRIPT_NAME="${NODE_NAME}_wipe"

if [[ ! -r "${CONFIG_FILE_PATH}" ]]; then
  echo "Cannot find the config file : '${CONFIG_FILE_PATH}'"
  exit 1
fi

echo ""
echo "Adding scripts:"
echo "  ${NODE_NAME}_init  :  Creates subdirectories and initializes the datadirs"
echo "  ${NODE_NAME}_start :  Starts the node"
echo "  ${NODE_NAME}_stop  :  Stops the node"
echo "  ${NODE_NAME}_cl    :  Opens a mysql shell to the node"
echo "  ${NODE_NAME}_query :  Sends a query to a node"
echo "  ${NODE_NAME}_wipe  :  Stops the node, removes the subdirectories"
echo ""


declare mysql_version=$(get_version "${BUILD}/bin/mysqld")


#
# Create the init script 
#
echo "" > ./$INIT_SCRIPT_NAME
echo "echo 'Initializing MySQL $mysql_version'" >> ./$INIT_SCRIPT_NAME
echo "PXC_START_TIMEOUT=30" >> ./$INIT_SCRIPT_NAME
echo "" >> ./$INIT_SCRIPT_NAME
echo "echo 'Creating subdirectores'" >> ./$INIT_SCRIPT_NAME
echo "mkdir -p $NODE_DATADIR" >> ./$INIT_SCRIPT_NAME

echo "echo 'Initializing datadirs ($NODE_DATADIR)'" >> ./$INIT_SCRIPT_NAME

if [[ $mysql_version =~ ^5.6 ]]; then
  echo "MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./$INIT_SCRIPT_NAME
elif [[ $mysql_version =~ ^5.7 ]]; then
  echo "MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./$INIT_SCRIPT_NAME
elif [[ $mysql_version =~ ^8.0 ]]; then
  echo "MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./$INIT_SCRIPT_NAME
else
  echo "Error: Unsupported MySQL version : $mysql_version"
  exit 1
fi
echo -e "\n" >> ./$INIT_SCRIPT_NAME

echo "\${MID} --datadir=$NODE_DATADIR  > ${BUILD}/startup_${NODE_NAME}.err 2>&1 || exit 1;" >> ./$INIT_SCRIPT_NAME

echo "echo 'Replacing DATADIR_BASE_PATH with $DATADIR_BASE_PATH in $CONFIG_FILE_PATH'" >> ./$INIT_SCRIPT_NAME

# Need to escape any slashes in the datadir (since it will contain a path)
# This will change '/' to '\/'
#safe_node_datadir=${node_datadir//\//\/\\/}
echo "sed -i 's/DATADIR_BASE_PATH/${DATADIR_BASE_PATH//\//\\/}/' \"$CONFIG_FILE_PATH\"" >> ./$INIT_SCRIPT_NAME

echo -e "\n" >> ./$INIT_SCRIPT_NAME


#
# Creating $START_SCRIPT_NAME
#
echo "PXC_MYEXTRA=\"\"" > ./$START_SCRIPT_NAME
echo "PXC_START_TIMEOUT=30"  >> ./$START_SCRIPT_NAME
echo -e "\n" >> ./$START_SCRIPT_NAME
echo "echo 'Starting PXC nodes..'" >> ./$START_SCRIPT_NAME
echo -e "\n" >> ./$START_SCRIPT_NAME

echo "echo 'Starting $NODE_NAME..'" >> ./$START_SCRIPT_NAME

echo "${BUILD}/bin/mysqld --defaults-file="${CONFIG_FILE_PATH}" --defaults-group-suffix=.$NODE_NAME \\" >> ./$START_SCRIPT_NAME
echo "    --port=$RBASE \\" >> ./$START_SCRIPT_NAME
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./$START_SCRIPT_NAME
echo "    > $NODE_DATADIR/node.err 2>&1 &" >> ./$START_SCRIPT_NAME
echo "mysqld_pid=\$!" >> ./$START_SCRIPT_NAME
echo -e "\n" >> ./$START_SCRIPT_NAME

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./$START_SCRIPT_NAME
echo "  sleep 1" >> ./$START_SCRIPT_NAME
echo "  if ! ps --pid \$mysqld_pid >/dev/null; then" >> ./$START_SCRIPT_NAME
echo "    echo 'Process mysqld (\$mysqld_pid) failed to start'" >> ./$START_SCRIPT_NAME
echo "    exit 1" >> ./$START_SCRIPT_NAME
echo "  fi" >> ./$START_SCRIPT_NAME
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$NODE_DATADIR/socket.sock ping > /dev/null 2>&1; then" >> ./$START_SCRIPT_NAME
echo "    break" >> ./$START_SCRIPT_NAME
echo "  fi" >> ./$START_SCRIPT_NAME
echo "done" >> ./$START_SCRIPT_NAME

echo -e "\n" >> ./$START_SCRIPT_NAME

#
# Creating stop
#
echo "if [[ -r ${NODE_DATADIR}/socket.sock ]]; then" > ./$STOP_SCRIPT_NAME
echo "  ${BUILD}/bin/mysqladmin -uroot -S${NODE_DATADIR}/socket.sock shutdown" >> ./$STOP_SCRIPT_NAME
echo "  echo 'Server on socket ${NODE_DATADIR}/socket.sock with datadir ${NODE_DATADIR} halted'" >> ./$STOP_SCRIPT_NAME
echo "fi" >> ./$STOP_SCRIPT_NAME
echo  "" >> ./$STOP_SCRIPT_NAME


#
# Creating wipe
#
echo "if [ -r ./$STOP_SCRIPT_NAME ]; then ./$STOP_SCRIPT_NAME 2>/dev/null 1>&2; fi" > ./$WIPE_SCRIPT_NAME
echo "if [ -d ${NODE_DATADIR} ]; then rm -rf ${NODE_DATADIR}; fi" >> ./$WIPE_SCRIPT_NAME

echo "rm ./$INIT_SCRIPT_NAME ./$START_SCRIPT_NAME" >> ./$WIPE_SCRIPT_NAME
echo "rm ./$STOP_SCRIPT_NAME ./$CL_SCRIPT_NAME ./$QUERY_SCRIPT_NAME " >> ./$WIPE_SCRIPT_NAME
echo "" >> ./$WIPE_SCRIPT_NAME

#
# Creating command-line scripts
#
echo "#! /bin/bash" > ./$CL_SCRIPT_NAME
echo "" >> ./$CL_SCRIPT_NAME
echo "if (( \"\$#\" != 0 )); then" >> ./$CL_SCRIPT_NAME
echo "  echo \"Usage: ${NODE_NAME}_cl\"" >> ./$CL_SCRIPT_NAME
echo "  exit 1" >> ./$CL_SCRIPT_NAME
echo "fi" >> ./$CL_SCRIPT_NAME
echo "" >> ./$CL_SCRIPT_NAME
echo "$BUILD/bin/mysql -A -S$BUILD/${NODE_NAME}/socket.sock -uroot " >> ./$CL_SCRIPT_NAME

echo "#! /bin/bash" > ./$QUERY_SCRIPT_NAME
echo "" >> ./$QUERY_SCRIPT_NAME
echo "if (( \"\$#\" != 1 )); then" >> ./$QUERY_SCRIPT_NAME
echo "  echo \"Usage: ${NODE_NAME}_query <query>\"" >> ./$QUERY_SCRIPT_NAME
echo "  exit 1" >> ./$QUERY_SCRIPT_NAME
echo "fi" >> ./$QUERY_SCRIPT_NAME
echo "" >> ./$QUERY_SCRIPT_NAME
echo "$BUILD/bin/mysql -A -S$BUILD/${NODE_NAME}/socket.sock -uroot -e '$2'" >> ./$QUERY_SCRIPT_NAME

chmod +x ./$INIT_SCRIPT_NAME  ./$START_SCRIPT_NAME
chmod +x ./$STOP_SCRIPT_NAME ./$CL_SCRIPT_NAME ./$QUERY_SCRIPT_NAME ./$WIPE_SCRIPT_NAME


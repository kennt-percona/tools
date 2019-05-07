#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#
# This script creates files that will recreate the environment
# needed for pxc-761
# 
# An async master feeding into a 2-node PXC Cluster
# There are three mysqld processes:
#     Async Master
#     PXC Node #1 - Async Slave
#     PXC Node #2
#
#
# Procedure:
#   Machine 1:  init_master
#               init_master_repl
#               start_master
#               init_pxc
#               init_slave_repl
#               start_pxc1
#               start_pxc2
#
# (afterwards)
#   Machine 1:  stop_pxc
#               stop_master
#
# (cleanup)
#   Machine 1:  wipe
#

. $(dirname $0)/../include/tools_common.sh

# check for config file parameter
if (( "$#" != 2 )); then
  echo ""
  echo "Usage:  pxc-async-master.sh <config-file> <ipaddr>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_master  : Creates subdirectories and initializes the master datadir"
  echo "  init_master_repl : Initializes the replication configuration on the master"
  echo "  start_master : Starts up the async master node"
  echo "  init_pxc     : Creates subdirectories and initializes the cluster datadir"
  echo "  init_slave_repl : Initializes the replication configuration on the slave"
  echo "  start_pxc1   : Starts up node 1 (the async slave)"
  echo "  start_pxc2   : Starts up node 2"
  echo "  stop_master  : Stops the async master node"
  echo "  stop_pxc     : Stops the cluster"
  echo "  node_cl      : Opens a mysql shell to a node"
  echo "  node_query   : Sends a query to a node"
  echo "  wipe         : Stops the cluster, removes subdirectories"
  echo ""
  exit 1
fi

#
# Global variables
#
declare     BUILD=$(pwd)

declare     CONFIG_FILE_PATH="${1}"
declare     IPADDR="${2}"

declare -i  RBASEM=4000
declare     LADDRM="$IPADDR:$(( RBASEM + 30 ))"

declare -i  RBASE1=4100
declare     LADDR1="$IPADDR:$(( RBASE1 + 30 ))"
declare     RADDR1="$IPADDR:$(( RBASE1 + 20 ))"

declare -i  RBASE2=4200
declare     LADDR2="$IPADDR:$(( RBASE2 + 30 ))"
declare     RADDR2="$IPADDR:$(( RBASE2 + 20 ))"

declare     CLUSTER_ADDRESS="$LADDR1,$LADDR2"

declare     NODEM_DATADIR="${BUILD}/nodem"
declare     NODE1_DATADIR="${BUILD}/node1"
declare     NODE2_DATADIR="${BUILD}/node2"


if [[ ! -r "${CONFIG_FILE_PATH}" ]]; then
  echo "Cannot find the config file : '${CONFIG_FILE_PATH}'"
  exit 1
fi

echo ""
echo "Adding scripts:"
echo "  init_master  : Creates subdirectories and initializes the datadirs"
echo "  init_master_repl : Initializes the replication config on the master"
echo "  start_master : Starts up the async master"
echo "  init_pxc     : Creates subdirectories and initializes the datadirs"
echo "  init_slave_repl : Initializes the replication config on the slave"
echo "  start_pxc1   : Starts up node 1 (the async slave)"
echo "  start_pxc2   : Starts up node 2"
echo "  stop_master  : Stops the async master"
echo "  stop_pxc     : Stops the cluster"
echo "  node_cl      : Opens a mysql shell to a node"
echo "  node_query   : Sends a query to a node"
echo "  wipe         : Stops the cluster, removes subdirectories"
echo ""


declare mysql_version=$(get_version "${BUILD}/bin/mysqld")

#
# Create the init_master script 
#
echo "" > ./init_master
echo "echo 'Initializing MySQL $mysql_version'" >> ./init_master
echo "PXC_START_TIMEOUT=30" >> ./init_master
echo "" >> ./init_master
echo "echo 'Creating subdirectores'" >> ./init_master
echo "mkdir -p $NODEM_DATADIR" >> ./init_master
echo "mkdir -p /tmp/nodem" >> ./init_master

echo "echo 'Initializing datadirs'" >> ./init_master

if [[ $mysql_version =~ ^5.6 ]]; then
  echo "MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_master
elif [[ $mysql_version =~ ^5.7 ]]; then
  echo "MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_master
elif [[ $mysql_version =~ ^8.0 ]]; then
  echo "MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_master
else
  echo "Error: Unsupported MySQL version : $mysql_version"
  exit 1
fi
echo -e "\n" >> ./init_master

echo "\${MID} --datadir=$NODEM_DATADIR  > ${BUILD}/startup_nodem.err 2>&1 || exit 1;" >> ./init_master

echo -e "\n" >> ./init_master

#
# Configure the master for replication
#
echo "" > ./init_master_repl
echo "echo 'Setting up the user account on the master'" >> ./init_master_repl
echo "${BUILD}/bin/mysql -S${NODEM_DATADIR}/socket.sock -uroot <<EOF" >> ./init_master_repl
echo "CREATE USER 'repl'@'%' IDENTIFIED WITH 'mysql_native_password' BY 'repl';" >> ./init_master_repl
echo "GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';" >> ./init_master_repl
echo "FLUSH PRIVILEGES;" >> ./init_master_repl
echo "EOF" >> ./init_master_repl
echo -e "\n" >> ./init_master_repl

#
# Create the init_pxc script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc
echo "mkdir -p $NODE1_DATADIR $NODE2_DATADIR" >> ./init_pxc
echo "mkdir -p /tmp/node1 /tmp/node2" >> ./init_pxc

echo "echo 'Initializing datadirs'" >> ./init_pxc

if [[ $mysql_version =~ ^5.6 ]]; then
  echo "MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc
elif [[ $mysql_version =~ ^5.7 ]]; then
  echo "MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_pxc
elif [[ $mysql_version =~ ^8.0 ]]; then
  echo "MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_pxc
else
  echo "Error: Unsupported MySQL version : $mysql_version"
  exit 1
fi

echo -e "\n" >> ./init_pxc

echo "\${MID} --datadir=$NODE1_DATADIR  > ${BUILD}/startup_node1.err 2>&1 || exit 1;" >> ./init_pxc
echo "\${MID} --datadir=$NODE2_DATADIR  > ${BUILD}/startup_node2.err 2>&1 || exit 1;" >> ./init_pxc

echo -e "\n" >> ./init_pxc


#
# Creating start_master
#
echo "PXC_MYEXTRA=\"\"" > ./start_master
echo "PXC_START_TIMEOUT=30"  >> ./start_master
echo -e "\n" >> ./start_master
echo "echo 'Starting async master nodes..'" >> ./start_master
echo -e "\n" >> ./start_master


#
# Starting async master
#
echo "echo 'Starting async master..'" >> ./start_master

echo "${BUILD}/bin/mysqld --defaults-file="${CONFIG_FILE_PATH}" --defaults-group-suffix=.m \\" >> ./start_master
echo "    --port=$RBASEM \\" >> ./start_master
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_master
echo "    > $NODEM_DATADIR/nodem.err 2>&1 &" >> ./start_master

echo -e "\n" >> ./start_master

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_master
echo "  sleep 1" >> ./start_master
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$NODEM_DATADIR/socket.sock ping > /dev/null 2>&1; then" >> ./start_master
echo "    break" >> ./start_master
echo "  fi" >> ./start_master
echo "done" >> ./start_master

echo -e "\n" >> ./start_master



#
# Creating start_pxc1
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc1
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc1
echo -e "\n" >> ./start_pxc1
echo "echo 'Starting PXC nodes..'" >> ./start_pxc1
echo -e "\n" >> ./start_pxc1


#
# Starting node 1
#
echo "echo 'Starting node 1..'" >> ./start_pxc1

echo "${BUILD}/bin/mysqld --defaults-file="${CONFIG_FILE_PATH}" --defaults-group-suffix=.1 \\" >> ./start_pxc1
echo "    --port=$RBASE1 \\" >> ./start_pxc1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc1
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc1
echo "    --wsrep_sst_receive_address=$RADDR1 \\" >> ./start_pxc1
echo "    --wsrep_node_incoming_address=$IPADDR \\" >> ./start_pxc1
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR1;gmcast.segment=1\" \\" >> ./start_pxc1
echo "    --wsrep-new-cluster  > $NODE1_DATADIR/node1.err 2>&1 &" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc1
echo "  sleep 1" >> ./start_pxc1
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$NODE1_DATADIR/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc1
echo "    break" >> ./start_pxc1
echo "  fi" >> ./start_pxc1
echo "done" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1


#
# Configure the slave (node 1) for replication
#
echo "" > ./init_slave_repl
echo "echo 'Setting up the user account on the slave'" >> ./init_slave_repl
echo "${BUILD}/bin/mysql -S$NODE1_DATADIR/socket.sock -uroot <<EOF" >> ./init_slave_repl
echo "STOP SLAVE;" >> ./init_slave_repl
echo "CHANGE MASTER TO MASTER_HOST='$IPADDR', MASTER_PORT=$RBASEM, MASTER_USER='repl', MASTER_PASSWORD='repl';" >> ./init_slave_repl
echo "EOF" >> ./init_slave_repl

echo -e "\n" >> ./init_slave_repl


#
# Starting node 2
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc2
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc2
echo -e "\n" >> ./start_pxc2
echo "echo 'Starting PXC nodes..'" >> ./start_pxc2
echo -e "\n" >> ./start_pxc2

echo "echo 'Starting node 2..'" >> ./start_pxc2

echo "${BUILD}/bin/mysqld --defaults-file="${CONFIG_FILE_PATH}" --defaults-group-suffix=.2 \\" >> ./start_pxc2
echo "    --port=$RBASE2 \\" >> ./start_pxc2
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc2
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc2
echo "    --wsrep_node_incoming_address=$IPADDR \\" >> ./start_pxc2
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR2;gmcast.segment=1\" \\" >> ./start_pxc2
echo "    > $NODE2_DATADIR/node2.err 2>&1 &" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc2
echo "  sleep 1" >> ./start_pxc2
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$NODE2_DATADIR/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc2
echo "    break" >> ./start_pxc2
echo "  fi" >> ./start_pxc2
echo "done" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2

#
# Starting node 2 (with gdb)
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc2_gdb
echo -e "\n" >> ./start_pxc2_gdb

echo "gdb --args ${BUILD}/bin/mysqld --defaults-file="${CONFIG_FILE_PATH}" --defaults-group-suffix=.2 \\" >> ./start_pxc2_gdb
echo "    --port=$RBASE2 --gdb \\" >> ./start_pxc2_gdb
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2_gdb
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2_gdb
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc2_gdb
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc2_gdb
echo "    --wsrep_node_incoming_address=$IPADDR \\" >> ./start_pxc2_gdb
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR2;gmcast.segment=1\"" >> ./start_pxc2_gdb


#
# Creating stop_master
#
echo "if [[ -r ${NODEM_DATADIR}/socket.sock ]]; then" > ./stop_master
echo "  ${BUILD}/bin/mysqladmin -uroot -S${NODEM_DATADIR}/socket.sock shutdown" >> ./stop_master
echo "  echo 'Server on socket ${NODEM_DATADIR}/socket.sock with datadir ${NODEM_DATADIR} halted'" >> ./stop_master
echo "fi" >> ./stop_master
echo  "" >> ./stop_master


#
# Creating stop_pxc
#
echo "" > ./stop_pxc
echo "if [[ -r $NODE2_DATADIR/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$NODE2_DATADIR/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server on socket $NODE2_DATADIR/socket.sock with datadir ${NODE2_DATADIR} halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc
echo "if [[ -r $NODE1_DATADIR/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$NODE1_DATADIR/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server on socket $NODE1_DATADIR/socket.sock with datadir ${NODE1_DATADIR} halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc
echo  "" >> ./stop_pxc

#
# Creating stop_pxc2
#
echo "" > ./stop_pxc2
echo "if [[ -r $NODE2_DATADIR/socket.sock ]]; then" >> ./stop_pxc2
echo "  ${BUILD}/bin/mysqladmin -uroot -S$NODE2_DATADIR/socket.sock shutdown" >> ./stop_pxc2
echo "  echo 'Server on socket $NODE2_DATADIR/socket.sock with datadir ${NODE2_DATADIR} halted'" >> ./stop_pxc2
echo "fi" >> ./stop_pxc2


#
# Creating wipe
#
echo "if [ -r ./stop_master ]; then ./stop_master 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe

echo "if [ -d ${NODE1_DATADIR} ]; then rm -rf ${NODE1_DATADIR}; fi" >> ./wipe
echo "if [ -d ${NODE2_DATADIR} ]; then rm -rf ${NODE2_DATADIR}; fi" >> ./wipe
echo "if [ -d ${NODEM_DATADIR} ]; then rm -rf ${NODEM_DATADIR}; fi" >> ./wipe

echo "rm -rf /tmp/node1" >> ./wipe
echo "rm -rf /tmp/node2" >> ./wipe
echo "rm -rf /tmp/nodem" >> ./wipe

echo "rm ./init_master ./init_pxc ./start_master ./start_pxc1 ./start_pxc2 ./start_pxc2_gdb" >> ./wipe
echo "rm ./stop_master ./stop_pxc ./stop_pxc2 ./node_cl ./node_query " >> ./wipe
echo "rm ./init_master_repl ./init_slave_repl " >> ./wipe
echo "" >> ./wipe

#
# Creating command-line scripts
#
echo "#! /bin/bash" > ./node_cl
echo "" >> ./node_cl
echo "if (( \"\$#\" != 1 )); then" >> ./node_cl
echo "  echo \"Usage: node_cl <node_number>\"" >> ./node_cl
echo "  exit 1" >> ./node_cl
echo "fi" >> ./node_cl
echo "" >> ./node_cl
echo "$BUILD/bin/mysql -A -S$BUILD/node\$1/socket.sock -uroot " >> ./node_cl

echo "#! /bin/bash" > ./node_query
echo "" >> ./node_query
echo "if (( \"\$#\" != 2 )); then" >> ./node_query
echo "  echo \"Usage: node_query <node_number> <query>\"" >> ./node_query
echo "  exit 1" >> ./node_query
echo "fi" >> ./node_query
echo "" >> ./node_query
echo "$BUILD/bin/mysql -A -S$BUILD/node\$1/socket.sock -uroot -e '$2'" >> ./node_query

chmod +x ./init_master ./init_pxc ./start_master ./start_pxc1 ./start_pxc2 ./start_pxc2_gdb
chmod +x ./stop_master ./stop_pxc ./stop_pxc2 ./node_cl ./node_query ./wipe ./init_master_repl ./init_slave_repl


#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#
# This script will create a multi-source async replication environment.
# This will have two async masters replicating to a single PXC node.
#
# Two async masters feeding into a single PXC node. 
# There are three mysqld processes:
#     Async Master A
#     Async Master B
#     PXC Node #1 - Async Slave
#
# Procedure:
#   Machine 1:  init_master
#               start_master
#               init_pxc
#               start_pxc
#               init_channels
#
# (afterwards)
#   Machine 1:  stop_pxc
#               stop_master
#
# (cleanup)
#   Machine 1:  wipe
#

# check for config file parameter
if (( "$#" != 2 )); then
  echo ""
  echo "Usage:  pxc-async-master.sh <config-file> <ipaddr>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_master  : Creates subdirectories and initializes the master datadirs"
  echo "  start_master : Starts up the two async master nodes"
  echo "  init_pxc     : Creates subdirectories and initializes the cluster datadir"
  echo "  start_pxc    : Starts up node 1 (the async slave)"
  echo "  init_channels: Configures the channels on the PXC node"
  echo "  stop_master  : Stops the async master nodes"
  echo "  stop_pxc     : Stops the cluster"
  echo "  node_cl      : Opens a mysql shell to a node"
  echo "  wipe         : Stops the cluster, removes subdirectories"
  echo ""
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"
ipaddr="${2}"

if [[ ! -r "${config_file_path}" ]]; then
  echo "Cannot find the config file : '${config_file_path}'"
  exit 1
fi

echo ""
echo "Adding scripts:"
echo "  init_master  : Creates subdirectories and initializes the datadirs"
echo "  start_master : Starts up the async masters"
echo "  init_pxc     : Creates subdirectories and initializes the datadirs"
echo "  start_pxc    : Starts up node 1 (the async slave)"
echo "  init_channels: Configures the channels on the PXC node"
echo "  stop_master  : Stops the async master"
echo "  stop_pxc     : Stops the cluster"
echo "  node_cl      : Opens a mysql shell to a node"
echo "  wipe         : Stops the cluster, removes subdirectories"
echo ""

RBASEA=4100
LADDRA="$ipaddr:$(( RBASEA + 30 ))"

RBASEB=4200
LADDRB="$ipaddr:$(( RBASEB + 30 ))"

RBASE1=5000
LADDR1="$ipaddr:$(( RBASE1 + 30 ))"
RADDR1="$ipaddr:$(( RBASE1 + 20 ))"

CLUSTER_ADDRESS="$LADDR1"

nodea="${BUILD}/nodea"
nodeb="${BUILD}/nodeb"
node1="${BUILD}/node1"


#
# Create the init_master script 
#
echo "echo 'Creating subdirectores'" > ./init_master
echo "mkdir -p $nodea $nodeb" >> ./init_master
echo "mkdir -p /tmp/nodea /tmp/nodeb" >> ./init_master

echo "echo 'Initializing datadirs'" >> ./init_master
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_master
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_master
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_master
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_master
echo "fi" >> ./init_master

echo -e "\n" >> ./init_master

echo "\${MID} --datadir=$nodea  > ${BUILD}/startup_nodea.err 2>&1 || exit 1;" >> ./init_master
echo "\${MID} --datadir=$nodeb  > ${BUILD}/startup_nodeb.err 2>&1 || exit 1;" >> ./init_master

echo -e "\n" >> ./init_master

echo "echo 'Starting up async master A to create users'" >> ./init_master
echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.a \\" >> ./init_master
echo "    --port=$RBASEA \\" >> ./init_master
echo "    --basedir=${BUILD} \$PXC_MYEXTRA > $nodeb/error.log 2>&1 &" >> ./init_master
echo -e "\n" >> ./init_master
echo "sleep 2" >> ./init_master
echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./init_master
echo "  sleep 1" >> ./init_master
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$nodea/socket.sock ping > /dev/null 2>&1; then" >> ./init_master
echo "    break" >> ./init_master
echo "  fi" >> ./init_master
echo "done" >> ./init_master
echo -e "\n" >> ./init_master

echo "echo 'Setting up the user account on the master'" >> ./init_master
echo "${BUILD}/bin/mysql -S$nodea/socket.sock -uroot <<EOF" >> ./init_master
echo "CREATE USER IF NOT EXISTS 'repla'@'%' IDENTIFIED BY 'repla';" >> ./init_master
echo "GRANT REPLICATION SLAVE ON *.* TO 'repla'@'%';" >> ./init_master
echo "EOF" >> ./init_master
echo -e "\n" >> ./init_master

echo "echo 'Shutting down the async master A'" >> ./init_master
echo "${BUILD}/bin/mysqladmin -uroot -S$nodea/socket.sock shutdown" >> ./init_master
echo -e "\n" >> ./init_master

echo -e "\n" >> ./init_master

echo "echo 'Starting up async master B to create users'" >> ./init_master
echo "${BUILD}/bin/mysqld --defaults-file='${config_file_path}' --defaults-group-suffix=.b \\" >> ./init_master
echo "    --port=$RBASEB \\" >> ./init_master
echo "    --basedir=${BUILD} \$PXC_MYEXTRA > $nodeb/error.log 2>&1 &" >> ./init_master
echo -e "\n" >> ./init_master
echo "sleep 2" >> ./init_master
echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./init_master
echo "  sleep 1" >> ./init_master
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$nodeb/socket.sock ping > /dev/null 2>&1; then" >> ./init_master
echo "    break" >> ./init_master
echo "  fi" >> ./init_master
echo "done" >> ./init_master
echo -e "\n" >> ./init_master

echo "echo 'Setting up the user account on the master'" >> ./init_master
echo "${BUILD}/bin/mysql -S$nodeb/socket.sock -uroot <<EOF" >> ./init_master
echo "CREATE USER IF NOT EXISTS 'replb'@'%' IDENTIFIED BY 'replb';" >> ./init_master
echo "GRANT REPLICATION SLAVE ON *.* TO 'replb'@'%';" >> ./init_master
echo "EOF" >> ./init_master
echo -e "\n" >> ./init_master

echo "echo 'Shutting down the async master B'" >> ./init_master
echo "${BUILD}/bin/mysqladmin -uroot -S$nodeb/socket.sock shutdown" >> ./init_master
echo -e "\n" >> ./init_master


#
# Create the init_pxc script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc
echo "mkdir -p $node1 " >> ./init_pxc
echo "mkdir -p /tmp/node1 " >> ./init_pxc

echo "echo 'Initializing datadirs'" >> ./init_pxc
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_pxc
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc
echo "fi" >> ./init_pxc

echo -e "\n" >> ./init_pxc

echo "\${MID} --datadir=$node1  > ${BUILD}/startup_node1.err 2>&1 || exit 1;" >> ./init_pxc

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
# Starting async master A
#
echo "echo 'Starting async master..'" >> ./start_master

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.a \\" >> ./start_master
echo "    --port=$RBASEA \\" >> ./start_master
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_master
echo "    > $nodea/error.log 2>&1 &" >> ./start_master

echo -e "\n" >> ./start_master

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_master
echo "  sleep 1" >> ./start_master
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$nodea/socket.sock ping > /dev/null 2>&1; then" >> ./start_master
echo "    break" >> ./start_master
echo "  fi" >> ./start_master
echo "done" >> ./start_master

echo -e "\n" >> ./start_master

#
# Starting async master B
#
echo "echo 'Starting async master..'" >> ./start_master

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.b \\" >> ./start_master
echo "    --port=$RBASEB \\" >> ./start_master
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_master
echo "    > $nodeb/error.log 2>&1 &" >> ./start_master

echo -e "\n" >> ./start_master

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_master
echo "  sleep 1" >> ./start_master
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$nodeb/socket.sock ping > /dev/null 2>&1; then" >> ./start_master
echo "    break" >> ./start_master
echo "  fi" >> ./start_master
echo "done" >> ./start_master

echo -e "\n" >> ./start_master



#
# Creating start_pxc
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc
echo -e "\n" >> ./start_pxc
echo "echo 'Starting PXC nodes..'" >> ./start_pxc
echo -e "\n" >> ./start_pxc


#
# Starting node 1
#
echo "echo 'Starting node 1..'" >> ./start_pxc

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.1 \\" >> ./start_pxc
echo "    --port=$RBASE1 \\" >> ./start_pxc
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc
echo "    --wsrep_sst_receive_address=$RADDR1 \\" >> ./start_pxc
echo "    --wsrep_node_incoming_address=$ipaddr \\" >> ./start_pxc
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR1;gmcast.segment=1\" \\" >> ./start_pxc
echo "    --wsrep-new-cluster  > $node1/node1.err 2>&1 &" >> ./start_pxc

echo -e "\n" >> ./start_pxc

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc
echo "  sleep 1" >> ./start_pxc
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc
echo "    break" >> ./start_pxc
echo "  fi" >> ./start_pxc
echo "done" >> ./start_pxc

echo -e "\n" >> ./start_pxc



#
# Script to intitalize the slave channels
#
echo "echo 'Setting up the channels'" > ./init_channels
echo "${BUILD}/bin/mysql -S$node1/socket.sock -uroot <<EOF" >> ./init_channels
echo "CHANGE MASTER TO MASTER_HOST='$ipaddr', MASTER_PORT=$RBASEA, MASTER_USER='repla', MASTER_PASSWORD='repla', MASTER_AUTO_POSITION=1 FOR CHANNEL 'master-a';" >> ./init_channels
echo "CHANGE MASTER TO MASTER_HOST='$ipaddr', MASTER_PORT=$RBASEB, MASTER_USER='replb', MASTER_PASSWORD='replb', MASTER_AUTO_POSITION=1 FOR CHANNEL 'master-b';" >> ./init_channels
echo "EOF" >> ./init_channels
echo -e "\n" >> ./init_channels



#
# Creating stop_master
#
echo "if [[ -r $nodea/socket.sock ]]; then" > ./stop_master
echo "  ${BUILD}/bin/mysqladmin -uroot -S$nodea/socket.sock shutdown" >> ./stop_master
echo "  echo 'Server on socket $nodea/socket.sock with datadir ${BUILD}/nodea halted'" >> ./stop_master
echo "fi" >> ./stop_master
echo  "" >> ./stop_master

echo "if [[ -r $nodeb/socket.sock ]]; then" >> ./stop_master
echo "  ${BUILD}/bin/mysqladmin -uroot -S$nodeb/socket.sock shutdown" >> ./stop_master
echo "  echo 'Server on socket $nodeb/socket.sock with datadir ${BUILD}/nodeb halted'" >> ./stop_master
echo "fi" >> ./stop_master
echo  "" >> ./stop_master

#
# Creating stop_pxc
#
echo "" > ./stop_pxc
echo "if [[ -r $node1/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server on socket $node1/socket.sock with datadir ${BUILD}/node1 halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc
echo  "" >> ./stop_pxc



#
# Creating wipe
#
echo "if [ -r ./stop_master ]; then ./stop_master 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe

echo "if [ -d $BUILD/node1 ]; then rm -rf $BUILD/node1; fi" >> ./wipe
echo "if [ -d $BUILD/nodea ]; then rm -rf $BUILD/nodea; fi" >> ./wipe
echo "if [ -d $BUILD/nodeb ]; then rm -rf $BUILD/nodeb; fi" >> ./wipe

echo "rm -rf /tmp/node1" >> ./wipe
echo "rm -rf /tmp/nodea" >> ./wipe
echo "rm -rf /tmp/nodeb" >> ./wipe

echo "rm ./init_master ./init_pxc ./start_master ./start_pxc " >> ./wipe
echo "rm ./stop_master ./stop_pxc ./node_cl ./init_channels " >> ./wipe
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

chmod +x ./init_master ./init_pxc ./start_master ./start_pxc ./init_channels
chmod +x ./stop_master ./stop_pxc ./node_cl ./wipe


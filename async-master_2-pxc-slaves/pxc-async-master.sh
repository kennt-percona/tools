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
#               start_master
#               init_pxc
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

# check for config file parameter
if (( "$#" != 2 )); then
  echo ""
  echo "Usage:  pxc-async-master.sh <config-file> <ipaddr>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_master  : Creates subdirectories and initializes the master datadir"
  echo "  start_master : Starts up the async master node"
  echo "  init_pxc     : Creates subdirectories and initializes the cluster datadir"
  echo "  start_pxc1   : Starts up node 1 (the async slave)"
  echo "  start_pxc2   : Starts up node 2"
  echo "  stop_master  : Stops the async master node"
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
echo "  start_master : Starts up the async master"
echo "  init_pxc     : Creates subdirectories and initializes the datadirs"
echo "  start_pxc1   : Starts up node 1 (the async slave)"
echo "  start_pxc2   : Starts up node 2"
echo "  stop_master  : Stops the async master"
echo "  stop_pxc     : Stops the cluster"
echo "  node_cl      : Opens a mysql shell to a node"
echo "  wipe         : Stops the cluster, removes subdirectories"
echo ""

RBASEM=4000
LADDRM="$ipaddr:$(( RBASEM + 30 ))"

RBASE1=4100
LADDR1="$ipaddr:$(( RBASE1 + 30 ))"
RADDR1="$ipaddr:$(( RBASE1 + 20 ))"

RBASE2=4200
LADDR2="$ipaddr:$(( RBASE2 + 30 ))"
RADDR2="$ipaddr:$(( RBASE2 + 20 ))"

CLUSTER_ADDRESS="$LADDR1,$LADDR2"

nodem="${BUILD}/nodem"
node1="${BUILD}/node1"
node2="${BUILD}/node2"


#
# Create the init_master script 
#
echo "echo 'Creating subdirectores'" > ./init_master
echo "mkdir -p $nodem" >> ./init_master
echo "mkdir -p /tmp/nodem" >> ./init_master

echo "echo 'Initializing datadirs'" >> ./init_master
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_master
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_master
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_master
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_master
echo "fi" >> ./init_master

echo -e "\n" >> ./init_master

echo "\${MID} --datadir=$nodem  > ${BUILD}/startup_nodem.err 2>&1 || exit 1;" >> ./init_master

echo -e "\n" >> ./init_master

echo "echo 'Starting up async master to create users'" >> ./init_master
echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.m \\" >> ./init_master
echo "    --port=$RBASEM \\" >> ./init_master
echo "    --basedir=${BUILD} \$PXC_MYEXTRA > $nodem/nodem.err 2>&1 &" >> ./init_master
echo -e "\n" >> ./init_master
echo "sleep 2" >> ./init_master
echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./init_master
echo "  sleep 1" >> ./init_master
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$nodem/socket.sock ping > /dev/null 2>&1; then" >> ./init_master
echo "    break" >> ./init_master
echo "  fi" >> ./init_master
echo "done" >> ./init_master
echo -e "\n" >> ./init_master

echo "echo 'Setting up the user account on the master'" >> ./init_master
echo "${BUILD}/bin/mysql -S$nodem/socket.sock -uroot <<EOF" >> ./init_master
echo "CREATE USER 'repl'@'%' IDENTIFIED BY 'repl';" >> ./init_master
echo "GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';" >> ./init_master
echo "EOF" >> ./init_master
echo -e "\n" >> ./init_master

echo "echo 'Shutting down the async master'" >> ./init_master
echo "${BUILD}/bin/mysqladmin -uroot -S$nodem/socket.sock shutdown" >> ./init_master
echo -e "\n" >> ./init_master


#
# Create the init_pxc script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc
echo "mkdir -p $node1 $node2" >> ./init_pxc
echo "mkdir -p /tmp/node1 /tmp/node2" >> ./init_pxc

echo "echo 'Initializing datadirs'" >> ./init_pxc
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_pxc
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc
echo "fi" >> ./init_pxc

echo -e "\n" >> ./init_pxc

echo "\${MID} --datadir=$node1  > ${BUILD}/startup_node1.err 2>&1 || exit 1;" >> ./init_pxc
echo "\${MID} --datadir=$node2  > ${BUILD}/startup_node2.err 2>&1 || exit 1;" >> ./init_pxc

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

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.m \\" >> ./start_master
echo "    --port=$RBASEM \\" >> ./start_master
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_master
echo "    > $nodem/nodem.err 2>&1 &" >> ./start_master

echo -e "\n" >> ./start_master

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_master
echo "  sleep 1" >> ./start_master
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$nodem/socket.sock ping > /dev/null 2>&1; then" >> ./start_master
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

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.1 \\" >> ./start_pxc1
echo "    --port=$RBASE1 \\" >> ./start_pxc1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc1
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc1
echo "    --wsrep_sst_receive_address=$RADDR1 \\" >> ./start_pxc1
echo "    --wsrep_node_incoming_address=$ipaddr \\" >> ./start_pxc1
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR1;gmcast.segment=1\" \\" >> ./start_pxc1
echo "    --wsrep-new-cluster  > $node1/node1.err 2>&1 &" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc1
echo "  sleep 1" >> ./start_pxc1
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc1
echo "    break" >> ./start_pxc1
echo "  fi" >> ./start_pxc1
echo "done" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1

echo "echo 'Setting up the user account on the slave'" >> ./start_pxc1
echo "${BUILD}/bin/mysql -S$node1/socket.sock -uroot <<EOF" >> ./start_pxc1
echo "STOP SLAVE;" >> ./start_pxc1
echo "CHANGE MASTER TO MASTER_HOST='$ipaddr', MASTER_PORT=$RBASEM, MASTER_USER='repl', MASTER_PASSWORD='repl';" >> ./start_pxc1
echo "EOF" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1

#echo "echo 'Starting async replication on node 1'" >> ./start_pxc1
#echo "${BUILD}/bin/mysql -S$node1/socket.sock -uroot <<EOF" >> ./start_pxc1
#echo "START SLAVE;" >> ./start_pxc1
#echo "SHOW SLAVE STATUS;" >> ./start_pxc1
#echo "EOF" >> ./start_pxc1
#echo -e "\n" >> ./start_pxc1


#
# Starting node 2
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc2
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc2
echo -e "\n" >> ./start_pxc2
echo "echo 'Starting PXC nodes..'" >> ./start_pxc2
echo -e "\n" >> ./start_pxc2

echo "echo 'Starting node 2..'" > ./start_pxc2

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc2
echo "    --port=$RBASE2 \\" >> ./start_pxc2
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc2
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc2
echo "    --wsrep_node_incoming_address=$ipaddr \\" >> ./start_pxc2
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR2;gmcast.segment=1\" \\" >> ./start_pxc2
echo "    > $node2/node2.err 2>&1 &" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc2
echo "  sleep 1" >> ./start_pxc2
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc2
echo "    break" >> ./start_pxc2
echo "  fi" >> ./start_pxc2
echo "done" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2

#
# Starting node 2 (with gdb)
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc2_gdb
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc2_gdb
echo -e "\n" >> ./start_pxc2_gdb
echo "echo 'Starting PXC nodes..'" >> ./start_pxc2_gdb
echo -e "\n" >> ./start_pxc2_gdb

echo "echo 'Starting node 2..'" >> ./start_pxc2_gdb
echo "gdb --args ${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc2_gdb
echo "    --port=$RBASE2 --gdb \\" >> ./start_pxc2_gdb
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2_gdb
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2_gdb
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc2_gdb
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc2_gdb
echo "    --wsrep_node_incoming_address=$ipaddr \\" >> ./start_pxc2_gdb
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR2;gmcast.segment=1\" \\" >> ./start_pxc2_gdb
echo "    > $node2/node2.err 2>&1 &" >> ./start_pxc2_gdb


#
# Creating stop_master
#
echo "if [[ -r $nodem/socket.sock ]]; then" > ./stop_master
echo "  ${BUILD}/bin/mysqladmin -uroot -S$nodem/socket.sock shutdown" >> ./stop_master
echo "  echo 'Server on socket $nodem/socket.sock with datadir ${BUILD}/nodem halted'" >> ./stop_master
echo "fi" >> ./stop_master
echo  "" >> ./stop_master


#
# Creating stop_pxc
#
echo "" > ./stop_pxc
echo "if [[ -r $node2/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server on socket $node2/socket.sock with datadir ${BUILD}/node2 halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc
echo "if [[ -r $node1/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server on socket $node1/socket.sock with datadir ${BUILD}/node1 halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc
echo  "" >> ./stop_pxc

#
# Creating stop_pxc2
#
echo "" > ./stop_pxc2
echo "if [[ -r $node2/socket.sock ]]; then" >> ./stop_pxc2
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock shutdown" >> ./stop_pxc2
echo "  echo 'Server on socket $node2/socket.sock with datadir ${BUILD}/node2 halted'" >> ./stop_pxc2
echo "fi" >> ./stop_pxc2


#
# Creating wipe
#
echo "if [ -r ./stop_master ]; then ./stop_master 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe

echo "if [ -d $BUILD/node1 ]; then rm -rf $BUILD/node1; fi" >> ./wipe
echo "if [ -d $BUILD/node2 ]; then rm -rf $BUILD/node2; fi" >> ./wipe
echo "if [ -d $BUILD/nodem ]; then rm -rf $BUILD/nodem; fi" >> ./wipe

echo "rm -rf /tmp/node1" >> ./wipe
echo "rm -rf /tmp/node2" >> ./wipe
echo "rm -rf /tmp/nodem" >> ./wipe

echo "rm ./init_master ./init_pxc ./start_master ./start_pxc1 ./start_pxc2 ./start_pxc2_gdb" >> ./wipe
echo "rm ./stop_master ./stop_pxc ./stop_pxc2 ./node_cl " >> ./wipe
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

chmod +x ./init_master ./init_pxc ./start_master ./start_pxc1 ./start_pxc2 ./start_pxc2_gdb
chmod +x ./stop_master ./stop_pxc ./stop_pxc2 ./node_cl ./wipe


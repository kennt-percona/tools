#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#
# This script creates files that will recreate the environment
# needed for pxc-686
#
# This will create an enivornment for
#   Machine 1: 2 nodes
#
# Since this is a test of the page store, the size of the pages
# will be pretty small (~1MB)
#
# Procedure:
#   Machine 1:  init_pxc
#               start_pxc1
#
#               start_pxc2 (normal startup)
#               start_pxc2_gdb (startup under the debugger)
#
# (afterwards)
#   Machine 1:  stop_pxc
#
# (cleanup)
#   Machine 1:  wipe
#

# check for config file parameter
if (( "$#" != 2 )); then
  echo ""
  echo "Usage:  pxc-config-file <config-file> <ipaddr>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_pxc   : Creates subdirectories and initializes the datadirs"
  echo "  start_pxc1 : Start up node 1 of 2-node cluster"
  echo "  start_pxc2 : Start up node 2 of 2-node cluster (normal startup)"
  echo "  start_pxc2_gdb : Start up node 2 of 2-node cluster (gdb startup)"
  echo "  stop_pxc   : Stops the cluster"
  echo "  node_cl    : Opens a mysql shell to a node"
  echo "  wipe       : Stops the cluster, removes subdirectories"
  echo ""
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"
ipaddr1="${2}"

# additional options to be passed to wsrep_provider_options
wsrep_options="gcache.size=1M;gcache.page_size=1M;gcache.keep_pages_size=20M;gcache.keep_pages_count=2"

if [[ ! -r "${config_file_path}" ]]; then
  echo "Cannot find the config file : '${config_file_path}'"
  exit 1
fi

echo ""
echo "Adding scripts:"
echo "  init_pxc   : Creates subdirectories and initializes the datadirs"
echo "  start_pxc1 : Starts up a 2-node cluster"
echo "  start_pxc2 : Start up node 2 of 2-node cluster (normal startup)"
echo "  start_pxc2_gdb : Start up node 2 of 2-node cluster (gdb startup)"
echo "  stop_pxc   : Stops the cluster"
echo "  arb        : connect or disconnect the 1-node cluster from the 2-node cluster"
echo "  node_cl    : Opens a mysql shell to a node"
echo "  wipe       : Stops the cluster, removes subdirectories"
echo ""

RBASE1=4100
LADDR1="$ipaddr1:$(( RBASE1 + 30 ))"
RADDR1="$ipaddr1:$(( RBASE1 + 20 ))"

RBASE2=4200
LADDR2="$ipaddr1:$(( RBASE2 + 30 ))"
RADDR2="$ipaddr1:$(( RBASE2 + 20 ))"

CLUSTER_ADDRESS="$LADDR1,$LADDR2"

node1="${BUILD}/node1"
node2="${BUILD}/node2"

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
# Creating start_pxc
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
echo "    --wsrep_node_incoming_address=$ipaddr1 \\" >> ./start_pxc1
echo "    --wsrep_provider_options=\"$wsrep_options;gmcast.listen_addr=tcp://$LADDR1\" \\" >> ./start_pxc1
echo "    --wsrep-new-cluster  > $node1/node1.err 2>&1 &" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc1
echo "  sleep 1" >> ./start_pxc1
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc1
echo "    break" >> ./start_pxc1
echo "  fi" >> ./start_pxc1
echo "done" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1


#
# Starting node 2
#
echo "echo 'Starting node 2..'" > ./start_pxc2

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc2
echo "    --port=$RBASE2 \\" >> ./start_pxc2
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc2
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc2
echo "    --wsrep_node_incoming_address=$ipaddr1 \\" >> ./start_pxc2
echo "    --wsrep_provider_options=\"$wsrep_options;gmcast.listen_addr=tcp://$LADDR2\" \\" >> ./start_pxc2
echo "    > $node2/node2.err 2>&1 &" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc2
echo "  sleep 1" >> ./start_pxc2
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc2
echo "    break" >> ./start_pxc2
echo "  fi" >> ./start_pxc2
echo "done" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2


echo "echo 'Starting node 2 (gdb)..'" > ./start_pxc2_gdb

echo "gdb --args ${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc2_gdb
echo "    --gdb \\" >> ./start_pxc2_gdb
echo "    --port=$RBASE2 \\" >> ./start_pxc2_gdb
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2_gdb
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2_gdb
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc2_gdb
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc2_gdb
echo "    --wsrep_node_incoming_address=$ipaddr1 \\" >> ./start_pxc2_gdb
echo "    --wsrep_provider_options=\"$wsrep_options;gmcast.listen_addr=tcp://$LADDR2\" " >> ./start_pxc2_gdb

echo -e "\n" >> ./start_pxc2_gdb



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
# Creating wipe
#
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe

echo "if [ -d $BUILD/node1 ]; then rm -rf $BUILD/node1; fi" >> ./wipe
echo "if [ -d $BUILD/node2 ]; then rm -rf $BUILD/node2; fi" >> ./wipe

echo "rm -rf /tmp/node1" >> ./wipe
echo "rm -rf /tmp/node2" >> ./wipe

echo "rm ./init_pxc ./start_pxc1 ./start_pxc2 ./start_pxc2_gdb ./stop_pxc ./node_cl" >> ./wipe
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


chmod +x ./init_pxc ./start_pxc1 ./start_pxc2 ./start_pxc2_gdb ./stop_pxc ./node_cl ./wipe


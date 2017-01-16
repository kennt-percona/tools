#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#
# This script creates files that will recreate the environment
# needed for pxc-551
#
# This will create an enivornment for
#   Machine 1: 2 nodes
#   Machine 2: 1 node
#
# Procedure:
#   Machine 1:  init_pxc1
#               start_pxc1
#   Machine 2:  init_pxc2
#               start_pxc2
#
#               sudo arb disconnect
#
#   Machine 1:  run sysbench
#
#   Machine 2:  sudo arb connect
#               sudo arb disconnect
#               (repeat)
#
# (afterwards)
#   Machine 1:  stop_pxc
#   Machine 2:  stop_pxc
#
# (cleanup)
#   Machine 1:  wipe
#   Machine 2:  wipe
#

# check for config file parameter
if (( "$#" != 3 )); then
  echo ""
  echo "Usage:  pxc-config-file <config-file> <ipaddr-seg1> <ipaddr-seg2>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_pxc1  : Creates subdirectories and initializes the datadirs"
  echo "  start_pxc1 : Starts up a 2-node cluster"
  echo "  init_pxc2  : Creates subdirectories and initializes the datadirs"
  echo "  start_pxc2 : Starts up a 1-node cluster"
  echo "  stop_pxc   : Stops the cluster"
  echo "  arb        : connect or disconnect the 1-node cluster from the 2-node cluster"
  echo "  node_cl    : Opens a mysql shell to a node"
  echo "  wipe       : Stops the cluster, removes subdirectories"
  echo ""
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"
ipaddr1="${2}"
ipaddr2="${3}"

if [[ ! -r "${config_file_path}" ]]; then
  echo "Cannot find the config file : '${config_file_path}'"
  exit 1
fi

echo ""
echo "Adding scripts:"
echo "  init_pxc1  : Creates subdirectories and initializes the datadirs"
echo "  start_pxc1 : Starts up a 2-node cluster"
echo "  init_pxc2  : Creates subdirectories and initializes the datadirs"
echo "  start_pxc2 : Starts up a 1-node cluster"
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

RBASE3=5100
LADDR3="$ipaddr2:$(( RBASE3 + 30 ))"
RADDR3="$ipaddr2:$(( RBASE3 + 20 ))"

CLUSTER_ADDRESS="$LADDR1,$LADDR2,$LADDR3"

node1="${BUILD}/node1"
node2="${BUILD}/node2"
node3="${BUILD}/node3"

#
# Create the init_pxc1 script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc1
echo "mkdir -p $node1 $node2" >> ./init_pxc1
echo "mkdir -p /tmp/node1 /tmp/node2" >> ./init_pxc1

echo "echo 'Initializing datadirs'" >> ./init_pxc1
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc1
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_pxc1
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc1
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc1
echo "fi" >> ./init_pxc1

echo -e "\n" >> ./init_pxc1

echo "\${MID} --datadir=$node1  > ${BUILD}/startup_node1.err 2>&1 || exit 1;" >> ./init_pxc1
echo "\${MID} --datadir=$node2  > ${BUILD}/startup_node2.err 2>&1 || exit 1;" >> ./init_pxc1

echo -e "\n" >> ./init_pxc1

#
# Create the init_pxc2 script
#
echo "echo 'Creating subdirectores'" > ./init_pxc2
echo "mkdir -p $node3" >> ./init_pxc2
echo "mkdir -p /tmp/node3" >> ./init_pxc2

echo "echo 'Initializing datadirs'" >> ./init_pxc2
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc2
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --innodb-undo-tablespaces=2 --innodb_log_checksums=ON --basedir=${BUILD}\"" >> ./init_pxc2
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc2
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc2
echo "fi" >> ./init_pxc2

echo -e "\n" >> ./init_pxc2

echo "\${MID} --datadir=$node3  > ${BUILD}/startup_node3.err 2>&1 || exit 1;" >> ./init_pxc2

echo -e "\n" >> ./init_pxc2

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
echo "    --wsrep_node_incoming_address=$ipaddr1 \\" >> ./start_pxc1
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


#
# Starting node 2
#
echo "echo 'Starting node 2..'" >> ./start_pxc1

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc1
echo "    --port=$RBASE2 \\" >> ./start_pxc1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc1
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc1
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc1
echo "    --wsrep_node_incoming_address=$ipaddr1 \\" >> ./start_pxc1
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR2;gmcast.segment=1\" \\" >> ./start_pxc1
echo "    > $node2/node2.err 2>&1 &" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc1
echo "  sleep 1" >> ./start_pxc1
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc1
echo "    break" >> ./start_pxc1
echo "  fi" >> ./start_pxc1
echo "done" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1


#
# Creating start_pxc2
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc2
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc2
echo -e "\n" >> ./start_pxc2
echo "echo 'Starting PXC nodes..'" >> ./start_pxc2
echo -e "\n" >> ./start_pxc2

#
# Starting node 3
#
echo "echo 'Starting node 3..'" >> ./start_pxc2

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.3 \\" >> ./start_pxc2
echo "    --port=$RBASE3 \\" >> ./start_pxc2
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc2
echo "    --wsrep_sst_receive_address=$RADDR3 \\" >> ./start_pxc2
echo "    --wsrep_node_incoming_address=$ipaddr2 \\" >> ./start_pxc2
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR3;gmcast.segment=1\" \\" >> ./start_pxc2
echo "    > $node3/node3.err 2>&1 &" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc2
echo "  sleep 1" >> ./start_pxc2
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc2
echo "    break" >> ./start_pxc2
echo "  fi" >> ./start_pxc2
echo "done" >> ./start_pxc2
echo -e "\n\n" >> ./start_pxc2


#
# Creating stop_pxc
#
echo "" > ./stop_pxc
echo "if [[ -r $node3/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server on socket $node3/socket.sock with datadir ${BUILD}/node3 halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc
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
echo "if [ -d $BUILD/node3 ]; then rm -rf $BUILD/node3; fi" >> ./wipe

echo "rm -rf /tmp/node1" >> ./wipe
echo "rm -rf /tmp/node2" >> ./wipe
echo "rm -rf /tmp/node3" >> ./wipe
echo "rm -rf /tmp/node4" >> ./wipe
echo "rm -rf /tmp/node5" >> ./wipe
echo "rm -rf /tmp/node6" >> ./wipe

echo "rm ./init_pxc1 ./init_pxc2 ./start_pxc1 ./start_pxc2 ./stop_pxc ./node_cl ./arb" >> ./wipe
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


echo "#! /bin/bash" > ./arb
echo "" >> ./arb
echo "if [ \"\$#\" -ne 1 ]; then" >> ./arb
echo "  echo \"Usage: arb [connect | disconnect | list]\"" >> ./arb
echo "  exit 1" >> ./arb
echo "fi" >> ./arb
echo "" >> ./arb

echo "if [ \"\$1\" == \"connect\" ]; then" >> ./arb
echo "  op=\"-D\"" >> ./arb
echo "elif [ \"\$1\" == \"disconnect\" ]; then" >> ./arb
echo "  op=\"-A\"" >> ./arb
echo "elif [ \"\$1\" == \"list\" ]; then" >> ./arb
echo "  date +%H:%M:%S.%0N -u" >> ./arb
echo "  iptables --list" >> ./arb
echo "  exit $?">> ./arb
echo "else" >> ./arb
echo "  echo \"Only 'connect','disconnect', and 'list' are allowed operations : '\$1'\"" >> ./arb
echo "  exit 1" >> ./arb
echo "fi" >> ./arb
echo "" >> ./arb

echo "  date +%H:%M:%S.%0N -u" >> ./arb
echo "iptables \$op INPUT -s $ipaddr1 -j DROP" >> ./arb
echo "iptables \$op OUTPUT -d $ipaddr1 -j DROP" >> ./arb

echo "" >> ./arb

chmod +x ./init_pxc1 ./init_pxc2 ./start_pxc1 ./start_pxc2 ./stop_pxc ./node_cl ./wipe
chmod +x ./arb


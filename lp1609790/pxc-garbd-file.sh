#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#

# This script creates a file that will recreate the environment
# needed to reproduce:
#   https://bugs.launchpad.net/percona-xtradb-cluster/+bug/1609790
#
# This assumes that:
#   Machine 1: segment1 (3 nodes)
#   Machine 2: segment10 (1 node)
#   Machine 3: segment0 (arbitrator)
#
# Procedure:
#   Machine 1:  init_pxc1
#               start_pxc1
#   Machine 2:  init_pxc10
#               start_pxc10
#   Machine 3:  init_arb
#               start_arb
#
#               sudo arb disconnect 1
#               sudo arb disconnect 10
#
#               sudo arb connect 1
#
# (afterwards)
#   Machine 1:  stop_pxc1
#   Machine 2:  stop_pxc10
#   Machine 3:  stop_arb

# check for config file parameter
if (( "$#" != 4 )); then
  echo ""
  echo "Usage:  pxc-config-file <config-file> <ipaddr-seg0> <ipaddr-seg1> <ipaddr-arb>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_pxc1  : Creates subdirectories and initializes the datadirs"
  echo "  start_pxc1 : Starts up a 3-node cluster (segment 1)"
  echo "  init_pxc10 : Creates subdirectories and initializes the datadirs"
  echo "  start_pxc10: Starts up a 1-node cluster (segment 10)"
  echo "  stop_pxc   : Stops the cluster"
  echo "  init_arb   : Creates subdirectories"
  echo "  start_arb  : Starts up the arb"
  echo "  stop_arb   : Stops the arb"
  echo "  arb        : connect or disconnect the arb from either segment"
  echo "  node_cl    : Opens a mysql shell to a non-garbd node"
  echo "  wipe       : Stops the cluster, moves datadir to .PREV, removes subdirectories"
  echo ""
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"
ipaddr1="${2}"
ipaddr10="${3}"
ipaddr0="${4}"

echo ""
echo "Adding scripts:"
echo "  init_pxc1  : Creates subdirectories and initializes the datadirs"
echo "  start_pxc1 : Starts up a 3-node cluster (segment 1)"
echo "  init_pxc10 : Creates subdirectories and initializes the datadirs"
echo "  start_pxc10: Starts up a 1-node cluster (segment 10)"
echo "  stop_pxc   : Stops the cluster"
echo "  init_arb   : "
echo "  start_arb  : "
echo "  stop_arb   : "
echo "  arb        : connect or disconnect the arb from either segment"
echo "  node_cl    : Opens a mysql shell to a non-garbd node"
echo "  wipe       : Stops the cluster, moves datadir to .PREV, removes subdirectories"
echo ""

RBASE1=4100
LADDR1="$ipaddr1:$(( RBASE1 + 30 ))"
RADDR1="$ipaddr1:$(( RBASE1 + 20 ))"

RBASE2=4200
LADDR2="$ipaddr1:$(( RBASE2 + 30 ))"
RADDR2="$ipaddr1:$(( RBASE2 + 20 ))"

RBASE3=4300
LADDR3="$ipaddr1:$(( RBASE3 + 30 ))"
RADDR3="$ipaddr1:$(( RBASE3 + 20 ))"

RBASE4=5000
LADDR4="$ipaddr10:$(( RBASE4 + 30 ))"
RADDR4="$ipaddr10:$(( RBASE4 + 20 ))"

RBASE10=9000
LADDR10="$ipaddr0:$(( RBASE10 + 30 ))"
RADDR10="$ipaddr0:$(( RBASE10 + 20 ))"


node1="${BUILD}/node1"
node2="${BUILD}/node2"
node3="${BUILD}/node3"
node4="${BUILD}/node4"
node10="${BUILD}/node10"

innodb_tempdir1="${BUILD}/innodb_tempdir1"
innodb_tempdir2="${BUILD}/innodb_tempdir2"
innodb_tempdir3="${BUILD}/innodb_tempdir3"
innodb_tempdir4="${BUILD}/innodb_tempdir4"


#
# Create the init_pxc1 script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc1
echo "mkdir -p $node1 $node2 $node3" >> ./init_pxc1
echo "mkdir -p $innodb_tempdir1  $innodb_tempdir2  $innodb_tempdir3" >> ./init_pxc1
echo "mkdir -p /tmp/node1 /tmp/node2 /tmp/node3" >> ./init_pxc1

echo "echo 'Initializing datadirs'" >> ./init_pxc1
echo "if [ \"$(${BUILD}/bin/mysqld-debug --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc1
echo "  MID=\"${BUILD}/bin/mysqld-debug --no-defaults --initialize-insecure --innodb-undo-tablespaces=2 --innodb_log_checksums=ON --basedir=${BUILD}\"" >> ./init_pxc1
echo "elif [ \"$(${BUILD}/bin/mysqld-debug --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc1
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc1
echo "fi" >> ./init_pxc1

echo -e "\n" >> ./init_pxc1

echo "\${MID} --datadir=$node1  > ${BUILD}/startup_node1.err 2>&1 || exit 1;" >> ./init_pxc1
echo "\${MID} --datadir=$node2  > ${BUILD}/startup_node2.err 2>&1 || exit 1;" >> ./init_pxc1
echo "\${MID} --datadir=$node3  > ${BUILD}/startup_node3.err 2>&1 || exit 1;" >> ./init_pxc1

echo -e "\n" >> ./init_pxc1

#
# Create the init_pxc10 script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc10
echo "mkdir -p $node4" >> ./init_pxc10
echo "mkdir -p $innodb_tempdir4" >> ./init_pxc10
echo "mkdir -p /tmp/node4" >> ./init_pxc10

echo "echo 'Initializing datadirs'" >> ./init_pxc10
echo "if [ \"$(${BUILD}/bin/mysqld-debug --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc10
echo "  MID=\"${BUILD}/bin/mysqld-debug --no-defaults --initialize-insecure --innodb-undo-tablespaces=2 --innodb_log_checksums=ON --basedir=${BUILD}\"" >> ./init_pxc10
echo "elif [ \"$(${BUILD}/bin/mysqld-debug --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc10
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc10
echo "fi" >> ./init_pxc10

echo -e "\n" >> ./init_pxc10

echo "\${MID} --datadir=$node4  > ${BUILD}/startup_node4.err 2>&1 || exit 1;" >> ./init_pxc10

echo -e "\n" >> ./init_pxc10

#
# Create the init_arb script
#
echo "echo 'Creating subdirectores'" > ./init_arb
echo "mkdir -p $node10" >> ./init_arb
echo -e "\n" >> ./init_arb


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

echo "${BUILD}/bin/mysqld-debug --defaults-file="${config_file_path}" --defaults-group-suffix=.1 \\" >> ./start_pxc1
echo "    --port=$RBASE1 \\" >> ./start_pxc1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc1
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2,$LADDR3,$LADDR4 \\" >> ./start_pxc1
echo "    --wsrep_sst_receive_address=$RADDR1 \\" >> ./start_pxc1
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc1
echo "    --wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR1;gmcast.segment=1\" \\" >> ./start_pxc1
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

echo "${BUILD}/bin/mysqld-debug --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc1
echo "    --port=$RBASE2 \\" >> ./start_pxc1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc1
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2,$LADDR3,$LADDR4 \\" >> ./start_pxc1
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc1
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc1
echo "    --wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR2;gmcast.segment=1\" \\" >> ./start_pxc1
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
# Starting node 3
#
echo "echo 'Starting node 3..'" >> ./start_pxc1

echo "${BUILD}/bin/mysqld-debug --defaults-file="${config_file_path}" --defaults-group-suffix=.3 \\" >> ./start_pxc1
echo "    --port=$RBASE3 \\" >> ./start_pxc1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc1
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2,$LADDR3,$LADDR4 \\" >> ./start_pxc1
echo "    --wsrep_sst_receive_address=$RADDR3 \\" >> ./start_pxc1
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc1
echo "    --wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR3;gmcast.segment=1\" \\" >> ./start_pxc1
echo "    > $node3/node3.err 2>&1 &" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc1
echo "  sleep 1" >> ./start_pxc1
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc1
echo "    break" >> ./start_pxc1
echo "  fi" >> ./start_pxc1
echo "done" >> ./start_pxc1
echo -e "\n\n" >> ./start_pxc1


#
# Creating start_pxc10
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc10
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc10
echo -e "\n" >> ./start_pxc10
echo "echo 'Starting PXC nodes..'" >> ./start_pxc10
echo -e "\n" >> ./start_pxc10

#
# Starting node 4
#
echo "echo 'Starting node 4..'" >> ./start_pxc10

echo "${BUILD}/bin/mysqld-debug --defaults-file="${config_file_path}" --defaults-group-suffix=.4 \\" >> ./start_pxc10
echo "    --port=$RBASE4 \\" >> ./start_pxc10
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc10
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc10
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2,$LADDR3,$LADDR4 \\" >> ./start_pxc10
echo "    --wsrep_sst_receive_address=$RADDR4 \\" >> ./start_pxc10
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc10
echo "    --wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR4;gmcast.segment=10\" \\" >> ./start_pxc10
echo "    > $node4/node4.err 2>&1 &" >> ./start_pxc10

echo -e "\n" >> ./start_pxc10

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc10
echo "  sleep 1" >> ./start_pxc10
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node4/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc10
echo "    break" >> ./start_pxc10
echo "  fi" >> ./start_pxc10
echo "done" >> ./start_pxc10
echo -e "\n\n" >> ./start_pxc10

#
# Creating start_arb
#

# Start the garbd
echo "" > ./start_arb
echo "${BUILD}/bin/garbd --name=arb --group=my_cluster \\" >> ./start_arb
echo "    --address=gcomm://$LADDR1,$LADDR2,$LADDR3,$LADDR4 \\" >> ./start_arb
echo "    --options=\"gmcast.listen_addr=tcp://$LADDR10;gmcast.segment=0\" \\" >> ./start_arb
echo "    --log=$node10/node10.err \\" >> ./start_arb
echo "    > $node10/node10.err 2>&1 &" >> ./start_arb

#
# Creating stop_pxc
#
echo "" > ./stop_pxc
echo "if [[ -r $node4/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node4/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server on socket $node4/socket.sock with datadir ${BUILD}/node4 halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc
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
# Creating stop_arb
#
echo "killall garbd"  > ./stop_arb

#
# Creating wipe
#
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -d $BUILD/node1.PREV ]; then rm -rf $BUILD/node1.PREV; fi;mv $BUILD/node1 $BUILD/node1.PREV" >> ./wipe
echo "if [ -d $BUILD/node2.PREV ]; then rm -rf $BUILD/node2.PREV; fi;mv $BUILD/node2 $BUILD/node2.PREV" >> ./wipe
echo "if [ -d $BUILD/node3.PREV ]; then rm -rf $BUILD/node3.PREV; fi;mv $BUILD/node3 $BUILD/node3.PREV" >> ./wipe
echo "if [ -d $BUILD/node4.PREV ]; then rm -rf $BUILD/node4.PREV; fi;mv $BUILD/node4 $BUILD/node4.PREV" >> ./wipe
echo "if [ -d $BUILD/node10.PREV ]; then rm -rf $BUILD/node10.PREV; fi;mv $BUILD/node10 $BUILD/node10.PREV" >> ./wipe

echo "rm -rf ${innodb_tempdir1}" >> ./wipe
echo "rm -rf ${innodb_tempdir2}" >> ./wipe
echo "rm -rf ${innodb_tempdir3}" >> ./wipe
echo "rm -rf ${innodb_tempdir4}" >> ./wipe

echo "rm -rf /tmp/node1" >> ./wipe
echo "rm -rf /tmp/node2" >> ./wipe
echo "rm -rf /tmp/node3" >> ./wipe
echo "rm -rf /tmp/node4" >> ./wipe

#
# Creating command-line scripts
#
echo "" > ./node_cl
echo "if (( \"\$#\" != 1 )); then" >> ./node_cl
echo "  echo \"Usage: node_cl <node_number>\"" >> ./node_cl
echo "fi" >> ./node_cl
echo "$BUILD/bin/mysql -A -uroot -S$BUILD/node\$1/socket.sock" >> ./node_cl


echo "#! /bin/bash" > ./arb
echo "" >> ./arb
echo "if [ \"\$#\" -ne 2 ]; then" >> ./arb
echo "  echo \"Usage: arb [connect | disconnect] <segment-no>\"" >> ./arb
echo "  exit 1" >> ./arb
echo "fi" >> ./arb
echo "" >> ./arb

echo "if [ \"\$1\" == \"connect\" ]; then" >> ./arb
echo "  op=\"-D\"" >> ./arb
echo "elif [ \"\$1\" == \"disconnect\" ]; then" >> ./arb
echo "  op=\"-A\"" >> ./arb
echo "else" >> ./arb
echo "  echo \"Only 'connect' and 'disconnect' are allowed operations : '\$1'\"" >> ./arb
echo "  exit 1" >> ./arb
echo "fi" >> ./arb
echo "" >> ./arb

echo "if [ \"\$2\" -eq 1 ]; then" >> ./arb
echo "  addr=\"$ipaddr1\"" >> ./arb
echo "elif [ \"\$2\" -eq 10 ]; then" >> ./arb
echo "  addr=\"$ipaddr10\"" >> ./arb
echo "else" >> ./arb
echo "  echo \"Only segments 1 and 10 are allowed : '\$2'\"" >> ./arb
echo "  exit 1" >> ./arb
echo "fi" >> ./arb

echo "iptables \$op OUTPUT -d \$addr -j DROP" >> ./arb

echo "" >> ./arb

chmod +x ./init_pxc1 ./init_pxc10 ./start_pxc1 ./start_pxc10 ./stop_pxc ./node_cl ./wipe
chmod +x ./init_arb ./start_arb ./arb ./stop_arb


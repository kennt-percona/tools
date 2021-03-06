#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC

# check for config file parameter
if (( "$#" != 1 )); then
  echo "Usage:  pxc-config-file <config-file>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_pxc  : Creates subdirectories and initializes the datadirs"
  echo "  start_pxc : Starts a 3-node cluster, node 1 is bootstrapped"
  echo "  stop_pxc  : Stops the 3-node cluster"
  echo "  node1_cl  : Opens a mysql shell to node 1"
  echo "  node2_cl  : Opens a mysql shell to node 2"
  echo "  node3_cl  : Opens a mysql shell to node 3"
  echo "  wipe      : Stops the cluster, moves datadir to .PREV, removes subdirectories"
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"

echo "Adding scripts: ./init_pxc | ./start_pxc | ./ stop_pxc | ./node1_cl | ./node2_cl | ./node3_cl | ./wipe"


ADDR="127.0.0.1"
RBASE1=4000
LADDR1="$ADDR:$(( RBASE1 + 30 ))"
RADDR1="$ADDR:$(( RBASE1 + 20 ))"

RBASE2=5000
LADDR2="$ADDR:$(( RBASE2 + 30 ))"
RADDR2="$ADDR:$(( RBASE2 + 20 ))"

RBASE3=6000
LADDR3="$ADDR:$(( RBASE3 + 30 ))"
RADDR3="$ADDR:$(( RBASE3 + 20 ))"


node1="${BUILD}/node1"
node2="${BUILD}/node2"
node3="${BUILD}/node3"

keyring_node1="${BUILD}/keyring-node1"
keyring_node2="${BUILD}/keyring-node2"
keyring_node3="${BUILD}/keyring-node3"

#
# Create the init_pxc script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc
echo "mkdir -p $node1 $node2 $node3" >> ./init_pxc
echo "mkdir -p $keyring_node1 $keyring_node2 $keyring_node3" >> ./init_pxc
echo "mkdir -p /tmp/node1 /tmp/node2 /tmp/node3 " >> ./init_pxc

echo "echo 'Initializing datadirs'" >> ./init_pxc
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --innodb_log_checksums=ON --basedir=${BUILD}\"" >> ./init_pxc
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc
echo "fi" >> ./init_pxc

echo -e "\n" >> ./init_pxc

echo "\${MID} --datadir=$node1  > ${BUILD}/startup_node1.err 2>&1 || exit 1;" >> ./init_pxc
echo "\${MID} --datadir=$node2  > ${BUILD}/startup_node2.err 2>&1 || exit 1;" >> ./init_pxc
echo "\${MID} --datadir=$node3  > ${BUILD}/startup_node3.err 2>&1 || exit 1;" >> ./init_pxc

echo -e "\n" >> ./init_pxc


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
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2,$LADDR3 \\" >> ./start_pxc
echo "    --wsrep_sst_receive_address=$RADDR1 \\" >> ./start_pxc
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc
echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$LADDR1 \\" >> ./start_pxc
#echo "    --wsrep_node_address=$RADDR1  \\" >> ./start_pxc
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
# Starting node 2
#
echo "echo 'Starting node 2..'" >> ./start_pxc

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc
echo "    --port=$RBASE2 \\" >> ./start_pxc
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2,$LADDR3 \\" >> ./start_pxc
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc
echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$LADDR2 \\" >> ./start_pxc
#echo "    --wsrep_node_address=$RADDR2  \\" >> ./start_pxc
echo "    > $node2/node2.err 2>&1 &" >> ./start_pxc

echo -e "\n" >> ./start_pxc

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc
echo "  sleep 1" >> ./start_pxc
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc
echo "    break" >> ./start_pxc
echo "  fi" >> ./start_pxc
echo "done" >> ./start_pxc

echo -e "\n" >> ./start_pxc


#
# Starting node 3
#
echo "echo 'Starting node 3..'" >> ./start_pxc

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.3 \\" >> ./start_pxc
echo "    --port=$RBASE3 \\" >> ./start_pxc
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2,$LADDR3 \\" >> ./start_pxc
echo "    --wsrep_sst_receive_address=$RADDR3 \\" >> ./start_pxc
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc
echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$LADDR3 \\" >> ./start_pxc
#echo "    --wsrep_node_address=$RADDR3  \\" >> ./start_pxc
echo "    > $node3/node3.err 2>&1 &" >> ./start_pxc

echo -e "\n" >> ./start_pxc

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc
echo "  sleep 1" >> ./start_pxc
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc
echo "    break" >> ./start_pxc
echo "  fi" >> ./start_pxc
echo "done" >> ./start_pxc
echo -e "\n\n" >> ./start_pxc


#
# Creating stop_pxc
#
echo "${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock shutdown" > ./stop_pxc
echo "echo 'Server on socket $node3/socket.sock with datadir ${BUILD}/node3 halted'" >> ./stop_pxc
echo "${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock shutdown" >> ./stop_pxc
echo "echo 'Server on socket $node2/socket.sock with datadir ${BUILD}/node2 halted'" >> ./stop_pxc
echo "${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock shutdown" >> ./stop_pxc
echo "echo 'Server on socket $node1/socket.sock with datadir ${BUILD}/node1 halted'" >> ./stop_pxc


#
# Creating wsrep-provider
#
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -d $BUILD/node1.PREV ]; then rm -rf $BUILD/node1.PREV; fi" >> ./wipe
echo "if [ -d $BUILD/node2.PREV ]; then rm -rf $BUILD/node2.PREV; fi" >> ./wipe
echo "if [ -d $BUILD/node3.PREV ]; then rm -rf $BUILD/node3.PREV; fi" >> ./wipe

echo "rm -rf ${keyring_node1}" >> ./wipe
echo "rm -rf ${keyring_node2}" >> ./wipe
echo "rm -rf ${keyring_node3}" >> ./wipe

echo "rm -rf /tmp/node1" >> ./wipe
echo "rm -rf /tmp/node2" >> ./wipe
echo "rm -rf /tmp/node3" >> ./wipe
echo "rm ./init_pxc ./start_pxc ./stop_pxc ./node1_cl ./node2_cl ./node3_cl" >> ./wipe


#
# Creating command-line scripts
#
echo "$BUILD/bin/mysql -A -uroot -S$node1/socket.sock" > ./node1_cl
echo "$BUILD/bin/mysql -A -uroot -S$node2/socket.sock" > ./node2_cl
echo "$BUILD/bin/mysql -A -uroot -S$node3/socket.sock" > ./node3_cl

chmod +x ./init_pxc ./start_pxc ./stop_pxc ./node1_cl ./node2_cl ./node3_cl ./wipe


#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC

# check for config file parameter
if (( "$#" != 2 )); then
  echo "Usage:  pxc-config-file <config-file> <ipaddr>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_pxc  : Creates subdirectories and initializes the datadirs"
  echo "  start_pxc : Starts a 3-node cluster, node 1 is bootstrapped"
  echo "  start_pxc1: Starts node 1 (bootstrapped)"
  echo "  stop_pxc  : Stops the 3-node cluster"
  echo "  node_cl  : Opens a mysql shell to a node"
  echo "  wipe      : Stops the cluster, moves datadir to .PREV, removes subdirectories"
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"
ipaddr="${2}"

echo "Adding scripts: ./init_pxc | ./start_pxc | ./start_pxc1 | ./start_pxc2 | ./start_pxc3 | ./ stop_pxc | ./node_cl | ./wipe"


ADDR=$ipaddr
PORT_BASE1=4100
GAL_PORT1=$(( PORT_BASE1 + 30 ))
GAL_ADDR1="$ADDR:$GAL_PORT1"
SST_PORT1=$(( PORT_BASE1 + 20 ))
SST_ADDR1="$ADDR:$SST_PORT1"

PORT_BASE2=4200
GAL_PORT2=$(( PORT_BASE2 + 30 ))
GAL_ADDR2="$ADDR:$GAL_PORT2"
SST_PORT2=$(( PORT_BASE2 + 20 ))
SST_ADDR2="$ADDR:$SST_PORT2"

PORT_BASE3=4300
GAL_PORT3=$(( PORT_BASE3 + 30 ))
GAL_ADDR3="$ADDR:$GAL_PORT3"
SST_PORT3=$(( PORT_BASE3 + 20 ))
SST_ADDR3="$ADDR:$SST_PORT3"


node1="${BUILD}/node1"
node2="${BUILD}/node2"
node3="${BUILD}/node3"

keyring_node1="${BUILD}/keyring-node1"
keyring_node2="${BUILD}/keyring-node2"
keyring_node3="${BUILD}/keyring-node3"

#innodb_tempdir1="${BUILD}/innodb_tempdir1"
#innodb_tempdir2="${BUILD}/innodb_tempdir2"
#innodb_tempdir3="${BUILD}/innodb_tempdir3"


#
# Create the init_pxc script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc
echo "mkdir -p $node1 $node2 $node3" >> ./init_pxc
echo "mkdir -p $keyring_node1 $keyring_node2 $keyring_node3" >> ./init_pxc
#echo "mkdir -p $innodb_tempdir1  $innodb_tempdir2  $innodb_tempdir3" >> ./init_pxc
#echo "mkdir -p /tmp/node1 /tmp/node2 /tmp/node3 " >> ./init_pxc

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
echo "echo 'Starting PXC nodes..'" >> ./start_pxc
echo -e "\n" >> ./start_pxc
echo "./start_pxc1" >> ./start_pxc
echo "./start_pxc2" >> ./start_pxc
echo "./start_pxc3" >> ./start_pxc


#
# Starting node 1
#

echo "PXC_MYEXTRA=\"\"" > ./start_pxc1
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc1
echo -e "\n" >> ./start_pxc1

echo "echo 'Starting node 1..'" >> ./start_pxc1

echo "${BUILD}/bin/mysqld-debug --defaults-file="${config_file_path}" --defaults-group-suffix=.1 \\" >> ./start_pxc1
echo "    --port=$PORT_BASE1 \\" >> ./start_pxc1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc1
echo "    --wsrep_cluster_address=gcomm://$GAL_ADDR1,$GAL_ADDR2,$GAL_ADDR3 \\" >> ./start_pxc1
echo "    --wsrep_sst_receive_address=$SST_ADDR1 \\" >> ./start_pxc1
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc1
echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$GAL_ADDR1 \\" >> ./start_pxc1
#echo "    --wsrep_node_address=$RADDR1  \\" >> ./start_pxc1
echo "    --wsrep-new-cluster  > $node1/error.log 2>&1 &" >> ./start_pxc1

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
echo "PXC_MYEXTRA=\"\"" > ./start_pxc2
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc2
echo -e "\n" >> ./start_pxc2

echo "echo 'Starting node 2..'" >> ./start_pxc2

echo "${BUILD}/bin/mysqld-debug --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc2
echo "    --port=$PORT_BASE2 \\" >> ./start_pxc2
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2
echo "    --wsrep_cluster_address=gcomm://$GAL_ADDR1,$GAL_ADDR2,$GAL_ADDR3 \\" >> ./start_pxc2
echo "    --wsrep_sst_receive_address=$SST_ADDR2 \\" >> ./start_pxc2
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc2
echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$GAL_ADDR2 \\" >> ./start_pxc2
#echo "    --wsrep_node_address=$RADDR2  \\" >> ./start_pxc2
echo "    > $node2/error.log 2>&1 &" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc2
echo "  sleep 1" >> ./start_pxc2
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc2
echo "    break" >> ./start_pxc2
echo "  fi" >> ./start_pxc2
echo "done" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2


#
# Starting node 3
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc3
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc3
echo -e "\n" >> ./start_pxc3
echo "echo 'Starting node 3..'" >> ./start_pxc3

echo "${BUILD}/bin/mysqld-debug --defaults-file="${config_file_path}" --defaults-group-suffix=.3 \\" >> ./start_pxc3
echo "    --port=$PORT_BASE3 \\" >> ./start_pxc3
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc3
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc3
echo "    --wsrep_cluster_address=gcomm://$GAL_ADDR1,$GAL_ADDR2,$GAL_ADDR3 \\" >> ./start_pxc3
echo "    --wsrep_sst_receive_address=$SST_ADDR3 \\" >> ./start_pxc3
echo "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc3
echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$GAL_ADDR3 \\" >> ./start_pxc3
#echo "    --wsrep_node_address=$RADDR3  \\" >> ./start_pxc3
echo "    > $node3/error.log 2>&1 &" >> ./start_pxc3

echo -e "\n" >> ./start_pxc3

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc3
echo "  sleep 1" >> ./start_pxc3
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc3
echo "    break" >> ./start_pxc3
echo "  fi" >> ./start_pxc3
echo "done" >> ./start_pxc3
echo -e "\n\n" >> ./start_pxc3


#
# Creating stop_pxc
#
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


#
# Creating wsrep-provider
#
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -d $BUILD/node1 ]; then rm -rf $BUILD/node1; fi" >> ./wipe
echo "if [ -d $BUILD/node2 ]; then rm -rf $BUILD/node2; fi" >> ./wipe
echo "if [ -d $BUILD/node3 ]; then rm -rf $BUILD/node3; fi" >> ./wipe

echo "rm -rf ${keyring_node1}" >> ./wipe
echo "rm -rf ${keyring_node2}" >> ./wipe
echo "rm -rf ${keyring_node3}" >> ./wipe

#echo "rm -rf ${innodb_tempdir1}" >> ./wipe
#echo "rm -rf ${innodb_tempdir2}" >> ./wipe
#echo "rm -rf ${innodb_tempdir3}" >> ./wipe

#echo "rm -rf /tmp/node1" >> ./wipe
#echo "rm -rf /tmp/node2" >> ./wipe
#echo "rm -rf /tmp/node3" >> ./wipe

echo "rm ./init_pxc ./start_pxc ./start_pxc1 ./start_pxc2 ./start_pxc3 ./stop_pxc ./node_cl" >> ./wipe


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


chmod +x ./init_pxc ./start_pxc ./start_pxc1 ./start_pxc2 ./start_pxc3 ./stop_pxc ./node_cl ./wipe


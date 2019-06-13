#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC

# check for config file parameter
if (( "$#" != 3 )); then
  echo" Error: incorrect number of arguments"
  echo ""
  echo "Usage:  pxc-config-file <config-file> <ipaddr1> <ipaddr2>"
  echo ""
  echo "This will create the same config, it is expected"
  echo "that this will be run on two separate machines."
  echo ""
  echo "Creates the following scripts:"
  echo "  init_pxc : Creates subdir and initiliazes the subdir"
  echo "  start_pxc1 : Starts node 1 of a 2-node cluster, this node is bootstrapped"
  echo "  start_pxc2 : Starts node 2 of a 2-node cluster"
  echo "  stop_pxc  : Stops the cluster"
  echo "  node_cl   : Opens a mysql shell to a node"
  echo "  wipe      : Stops the cluster, removes subdirectories"
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"
ipaddr1="${2}"
ipaddr2="${3}"

echo "Adding scripts: ./init_pxc | ./start_pxc1 | ./start_pxc2 | ./ stop_pxc | ./node_cl | ./wipe"

ADDR1=$ipaddr1
RBASE1=4100
LADDR1="$ADDR1:$(( RBASE1 + 30 ))"
RADDR1="$ADDR1:$(( RBASE1 + 20 ))"

ADDR2=$ipaddr2
RBASE2=4200
LADDR2="$ADDR2:$(( RBASE2 + 30 ))"
RADDR2="$ADDR2:$(( RBASE2 + 20 ))"

node_datadir="${BUILD}/node"

#
# Create the init_pxc script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc
echo "mkdir -p $node_datadir" >> ./init_pxc

echo "echo 'Initializing datadirs'" >> ./init_pxc
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --innodb_log_checksums=ON --basedir=${BUILD}\"" >> ./init_pxc
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc
echo "fi" >> ./init_pxc

echo -e "\n" >> ./init_pxc

echo "\${MID} --datadir=$node_datadir  > ${BUILD}/startup_node.err 2>&1 || exit 1;" >> ./init_pxc

echo -e "\n" >> ./init_pxc

echo "echo 'Copying certs'" >> ./init_pxc
echo "cp ./certs/*.pem ${node_datadir}/" >> ./init_pxc

echo -e "\n" >> ./init_pxc

echo "echo 'Replacing NODE_DATADIR with $node_datadir in $config_file_path'" >> ./init_pxc

# Need to escape any slashes in the datadir (since it will contain a path)
# This will change '/' to '\/'
#safe_node_datadir=${node_datadir//\//\/\\/}
echo "sed -i 's/NODE_DATADIR/${node_datadir//\//\\/}/' \"$config_file_path\"" >> ./init_pxc

echo -e "\n" >> ./init_pxc


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
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2 \\" >> ./start_pxc1
echo "    --wsrep_sst_receive_address=$RADDR1 \\" >> ./start_pxc1
echo "    --wsrep_node_incoming_address=$ADDR1 \\" >> ./start_pxc1
echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$LADDR1 \\" >> ./start_pxc1
#echo "    --wsrep_node_address=$RADDR1  \\" >> ./start_pxc1
echo "    --wsrep-new-cluster  > $node_datadir/node.err 2>&1 &" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc1
echo "  sleep 1" >> ./start_pxc1
echo "  if ${BUILD}/bin/mysqladmin -uroot -S${node_datadir}/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc1
echo "    break" >> ./start_pxc1
echo "  fi" >> ./start_pxc1
echo "done" >> ./start_pxc1

echo -e "\n" >> ./start_pxc1


#
# Creating start_pxc1
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc2
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc2
echo -e "\n" >> ./start_pxc2
echo "echo 'Starting PXC nodes..'" >> ./start_pxc2
echo -e "\n" >> ./start_pxc2

#
# Starting node 2
#
echo "echo 'Starting node 2..'" >> ./start_pxc2

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc2
echo "    --port=$RBASE2 \\" >> ./start_pxc2
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc2
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc2
echo "    --wsrep_cluster_address=gcomm://$LADDR1,$LADDR2 \\" >> ./start_pxc2
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc2
echo "    --wsrep_node_incoming_address=$ADDR2 \\" >> ./start_pxc2
echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$LADDR2 \\" >> ./start_pxc2
#echo "    --wsrep_node_address=$RADDR2  \\" >> ./start_pxc2
echo "    > $node_datadir/node.err 2>&1 &" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc2
echo "  sleep 1" >> ./start_pxc2
echo "  if ${BUILD}/bin/mysqladmin -uroot -S${node_datadir}/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc2
echo "    break" >> ./start_pxc2
echo "  fi" >> ./start_pxc2
echo "done" >> ./start_pxc2

echo -e "\n" >> ./start_pxc2


#
# Creating stop_pxc
#
echo "echo 'Stopping PXC'" > ./stop_pxc
echo "if [[ -r ${node_datadir}/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node_datadir/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server with datadir $node_datadir halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc


#
# Creating wsrep-provider
#
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -d $node_datadir ]; then rm -rf $node_datadir; fi" >> ./wipe

echo "rm ./init_pxc ./start_pxc1 ./start_pxc2 ./stop_pxc ./node_cl" >> ./wipe


#
# Creating command-line scripts
#
echo "#! /bin/bash" > ./node_cl
echo "" >> ./node_cl
echo "$BUILD/bin/mysql -A -S${node_datadir}/socket.sock -uroot " >> ./node_cl


chmod +x ./init_pxc ./start_pxc1 ./start_pxc2 ./stop_pxc ./node_cl ./wipe


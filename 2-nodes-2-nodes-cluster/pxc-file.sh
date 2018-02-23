#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#
# This script will create 2 clusters (each with 2 nodes)
# In addition, this will setup an async-replication
# channel between the two clusters.
#
#  1a- 1b --> 2a - 2b
#  node1 = 1a - cluster 1 node a
#  node2 = 1b - cluster 1 node b (async master)
#  node3 = 2a - cluster 2 node a (async slave)
#  node4 = 2b - cluster 2 node b
#
# Procedure:
#   init_clusters
#   start_cluster1
#   start_cluster2
#   init_master
#   init_slave
#
#   (will require "start slave" on async slave node)
#
# (afterwards)
#   stop_cluster2
#   stop_cluster1
#


# check for config file parameter
if (( "$#" != 2 )); then
  echo ""
  echo "Usage:  pxc-file <config-file> <ipaddr>"
  echo ""
  echo "Creates the following scripts:"
  echo "init_clusters  : creates subdirs and initializes the datadirs"
  echo "start_cluster1 : starts up the 2-node cluster 1"
  echo "start_cluster2 : starts up the 2-node cluster 2"
  echo "init_master    : initializes the async master node"
  echo "init_slave     : initializes the async slave node"
  echo "stop_cluster2  : stops cluster 2"
  echo "stop_cluster1  : stops cluster 1"
  echo "node_cl        : opens up a mysql shell to a node"
  echo "wipe           : stops the clusters, wipes the subdirectories"
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
echo "init_clusters  : creates subdirs and initializes the datadirs"
echo "start_cluster1 : starts up the 2-node cluster 1"
echo "start_cluster2 : starts up the 2-node cluster 2"
echo "init_master    : initializes the async master node"
echo "init_slave     : initializes the async slave node"
echo "stop_cluster2  : stops cluster 2"
echo "stop_cluster1  : stops cluster 1"
echo "node_cl        : opens up a mysql shell to a node"
echo "wipe           : stops the clusters, wipes the subdirectories"
echo ""

RBASE1=4100
LADDR1="$ipaddr:$(( RBASE1 + 30 ))"
RADDR1="$ipaddr:$(( RBASE1 + 20 ))"

RBASE2=4200
LADDR2="$ipaddr:$(( RBASE2 + 30 ))"
RADDR2="$ipaddr:$(( RBASE2 + 20 ))"

RBASE3=5100
LADDR3="$ipaddr:$(( RBASE3 + 30 ))"
RADDR3="$ipaddr:$(( RBASE3 + 20 ))"

RBASE4=5200
LADDR4="$ipaddr:$(( RBASE4 + 30 ))"
RADDR4="$ipaddr:$(( RBASE4 + 20 ))"

CLUSTER1_ADDRESS="$LADDR1,$LADDR2"
CLUSTER2_ADDRESS="$LADDR3,$LADDR4"

node1="${BUILD}/node1"
node2="${BUILD}/node2"
node3="${BUILD}/node3"
node4="${BUILD}/node4"



#
# Create the init_clusters script 
#
echo "echo 'Creating subdirectores'" > ./init_clusters
echo "mkdir -p $node1 $node2 $node3 $node4" >> ./init_clusters

echo "echo 'Initializing datadirs'" >> ./init_clusters
echo "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_clusters
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_clusters
echo "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_clusters
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_clusters
echo "fi" >> ./init_clusters

echo -e "\n" >> ./init_clusters

echo "\${MID} --datadir=$node1  > ${BUILD}/startup_node1.err 2>&1 || exit 1;" >> ./init_clusters
echo "\${MID} --datadir=$node2  > ${BUILD}/startup_node2.err 2>&1 || exit 1;" >> ./init_clusters
echo "\${MID} --datadir=$node3  > ${BUILD}/startup_node3.err 2>&1 || exit 1;" >> ./init_clusters
echo "\${MID} --datadir=$node4  > ${BUILD}/startup_node4.err 2>&1 || exit 1;" >> ./init_clusters

echo -e "\n" >> ./init_clusters


#
# Creating start_cluster1
#
echo "PXC_MYEXTRA=\"\"" > ./start_cluster1
echo "PXC_START_TIMEOUT=30"  >> ./start_cluster1
echo -e "\n" >> ./start_cluster1
echo "echo 'Starting PXC nodes..'" >> ./start_cluster1
echo -e "\n" >> ./start_cluster1


#
# Starting node 1
#
echo "echo 'Starting node 1..'" >> ./start_cluster1

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.1 \\" >> ./start_cluster1
echo "    --port=$RBASE1 \\" >> ./start_cluster1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_cluster1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_cluster1
echo "    --wsrep_cluster_address=gcomm://$CLUSTER1_ADDRESS \\" >> ./start_cluster1
echo "    --wsrep_sst_receive_address=$RADDR1 \\" >> ./start_cluster1
echo "    --wsrep_node_incoming_address=$ipaddr \\" >> ./start_cluster1
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR1;gmcast.segment=1\" \\" >> ./start_cluster1
echo "    --wsrep-new-cluster  > $node1/error.log 2>&1 &" >> ./start_cluster1

echo -e "\n" >> ./start_cluster1

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_cluster1
echo "  sleep 1" >> ./start_cluster1
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock ping > /dev/null 2>&1; then" >> ./start_cluster1
echo "    break" >> ./start_cluster1
echo "  fi" >> ./start_cluster1
echo "done" >> ./start_cluster1

echo -e "\n" >> ./start_cluster1


#
# Starting node 2
#
echo "echo 'Starting node 2..'" >> ./start_cluster1

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_cluster1
echo "    --port=$RBASE2 \\" >> ./start_cluster1
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_cluster1
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_cluster1
echo "    --wsrep_cluster_address=gcomm://$CLUSTER1_ADDRESS \\" >> ./start_cluster1
echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_cluster1
echo "    --wsrep_node_incoming_address=$ipaddr \\" >> ./start_cluster1
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR2;gmcast.segment=1\" \\" >> ./start_cluster1
echo "    > $node2/error.log 2>&1 &" >> ./start_cluster1

echo -e "\n" >> ./start_cluster1

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_cluster1
echo "  sleep 1" >> ./start_cluster1
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock ping > /dev/null 2>&1; then" >> ./start_cluster1
echo "    break" >> ./start_cluster1
echo "  fi" >> ./start_cluster1
echo "done" >> ./start_cluster1

echo -e "\n" >> ./start_cluster1


#
# Creating start_cluster2
#
echo "PXC_MYEXTRA=\"\"" > ./start_cluster2
echo "PXC_START_TIMEOUT=30"  >> ./start_cluster2
echo -e "\n" >> ./start_cluster2
echo "echo 'Starting PXC nodes..'" >> ./start_cluster2
echo -e "\n" >> ./start_cluster2

#
# Starting node 3
#
echo "echo 'Starting node 3..'" >> ./start_cluster2

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.3 \\" >> ./start_cluster2
echo "    --port=$RBASE3 \\" >> ./start_cluster2
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_cluster2
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_cluster2
echo "    --wsrep_cluster_address=gcomm://$CLUSTER2_ADDRESS \\" >> ./start_cluster2
echo "    --wsrep_sst_receive_address=$RADDR3 \\" >> ./start_cluster2
echo "    --wsrep_node_incoming_address=$ipaddr \\" >> ./start_cluster2
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR3;gmcast.segment=1\" \\" >> ./start_cluster2
echo "    --wsrep-new-cluster > $node3/error.log 2>&1 &" >> ./start_cluster2

echo -e "\n" >> ./start_cluster2

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_cluster2
echo "  sleep 1" >> ./start_cluster2
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock ping > /dev/null 2>&1; then" >> ./start_cluster2
echo "    break" >> ./start_cluster2
echo "  fi" >> ./start_cluster2
echo "done" >> ./start_cluster2
echo -e "\n\n" >> ./start_cluster2

#
# Starting node 4
#
echo "echo 'Starting node 4..'" >> ./start_cluster2

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.4 \\" >> ./start_cluster2
echo "    --port=$RBASE4 \\" >> ./start_cluster2
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_cluster2
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_cluster2
echo "    --wsrep_cluster_address=gcomm://$CLUSTER2_ADDRESS \\" >> ./start_cluster2
echo "    --wsrep_sst_receive_address=$RADDR4 \\" >> ./start_cluster2
echo "    --wsrep_node_incoming_address=$ipaddr \\" >> ./start_cluster2
echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR4;gmcast.segment=1\" \\" >> ./start_cluster2
echo "    > $node4/error.log 2>&1 &" >> ./start_cluster2

echo -e "\n" >> ./start_cluster2

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_cluster2
echo "  sleep 1" >> ./start_cluster2
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node4/socket.sock ping > /dev/null 2>&1; then" >> ./start_cluster2
echo "    break" >> ./start_cluster2
echo "  fi" >> ./start_cluster2
echo "done" >> ./start_cluster2
echo -e "\n\n" >> ./start_cluster2


#
# Creating stop_cluster2
#
echo "" > ./stop_cluster2
echo "if [[ -r $node4/socket.sock ]]; then" >> ./stop_cluster2
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node4/socket.sock shutdown" >> ./stop_cluster2
echo "  echo 'Server on socket $node4/socket.sock with datadir in node4 halted'" >> ./stop_cluster2
echo "fi" >> ./stop_cluster2
echo "if [[ -r $node3/socket.sock ]]; then" >> ./stop_cluster2
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock shutdown" >> ./stop_cluster2
echo "  echo 'Server on socket $node3/socket.sock with datadir in node3 halted'" >> ./stop_cluster2
echo "fi" >> ./stop_cluster2
echo  "" >> ./stop_cluster2

#
# Creating stop_cluster1
#
echo "" > ./stop_cluster1
echo "if [[ -r $node2/socket.sock ]]; then" >> ./stop_cluster1
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock shutdown" >> ./stop_cluster1
echo "  echo 'Server on socket $node2/socket.sock with datadir in node2 halted'" >> ./stop_cluster1
echo "fi" >> ./stop_cluster1
echo "if [[ -r $node1/socket.sock ]]; then" >> ./stop_cluster1
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock shutdown" >> ./stop_cluster1
echo "  echo 'Server on socket $node1/socket.sock with datadir in node1 halted'" >> ./stop_cluster1
echo "fi" >> ./stop_cluster1
echo  "" >> ./stop_cluster1


#
# Creating the init_master
#
echo "" > ./init_master
echo "echo 'Setting up the user account on the master'" >> ./init_master
echo "${BUILD}/bin/mysql -S$node2/socket.sock -uroot <<EOF" >> ./init_master
echo "CREATE USER 'repl'@'%' IDENTIFIED BY 'repl';" >> ./init_master
echo "GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';" >> ./init_master
echo "EOF" >> ./init_master
echo -e "\n" >> ./init_master

#
# Creating the init slave
#
echo "" > ./init_slave
echo "echo 'Setting up the user account on the slave'" >> ./init_slave
echo "${BUILD}/bin/mysql -S$node3/socket.sock -uroot <<EOF" >> ./init_slave
echo "STOP SLAVE;" >> ./init_slave
echo "RESET SLAVE;" >> ./init_slave
echo "CHANGE MASTER TO MASTER_HOST='$ipaddr', MASTER_PORT=$RBASE2, MASTER_USER='repl', MASTER_PASSWORD='repl';" >> ./init_slave
echo "EOF" >> ./init_slave

#
# Creating command-line script
#
echo "#! /bin/bash" > ./node_cl
echo "" >> ./node_cl
echo "if (( \"\$#\" != 1 )); then" >> ./node_cl
echo "  echo \"Usage: node_cl <node_number>\"" >> ./node_cl
echo "  exit 1" >> ./node_cl
echo "fi" >> ./node_cl
echo "" >> ./node_cl
echo "$BUILD/bin/mysql -A -S$BUILD/node\$1/socket.sock -uroot " >> ./node_cl


#
# Creating wipe
#
echo "if [ -r ./stop_cluster2 ]; then ./stop_cluster2 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -r ./stop_cluster1 ]; then ./stop_cluster1 2>/dev/null 1>&2; fi" >> ./wipe

echo "if [ -d $BUILD/node1 ]; then rm -rf $BUILD/node1; fi" >> ./wipe
echo "if [ -d $BUILD/node2 ]; then rm -rf $BUILD/node2; fi" >> ./wipe
echo "if [ -d $BUILD/node3 ]; then rm -rf $BUILD/node3; fi" >> ./wipe
echo "if [ -d $BUILD/node4 ]; then rm -rf $BUILD/node4; fi" >> ./wipe

echo "rm ./init_clusters ./start_cluster1 ./start_cluster2" >> ./wipe
echo "rm ./init_master ./init_slave ./stop_cluster1 ./stop_cluster2" >> ./wipe
echo "rm ./node_cl" >> ./wipe
echo "" >> ./wipe


chmod +x ./init_clusters ./start_cluster1 ./start_cluster2 ./init_master ./init_slave
chmod +x ./stop_cluster1 ./stop_cluster2 ./node_cl ./wipe


#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
#
# This script creates files that will create an environment
# with a node on each machine.
#
# This will create an enivornment for
#   Machine 1: 1 nodes
#   Machine 2: 1 node
#   Machine 3: 1 node
#
# Procedure:
#   Machine 1:  init_pxc
#               start_pxc_bootstrap (special script for bootstrap)
#   Machine 2:  init_pxc
#               start_pxc
#   Machine 3:  init_pxc
#               start_pxc
#
#               sudo arb disconnect
#
#   Machine 2:  sudo arb connect
#               sudo arb disconnect
#               (repeat)
#
# (afterwards)
#   Machine 1:  stop_pxc
#   Machine 2:  stop_pxc
#   Machine 3:  stop_pxc
#
# (cleanup)
#   Machine 1:  wipe
#   Machine 2:  wipe
#   Machine 3:  wipe
#

# check for config file parameter
if (( "$#" != 3 )); then
  echo ""
  echo "Usage:  pxc-config-file <config-file> <machine-ipaddr> <cluster-ipaddr>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_pxc   : Creates subdirectories and initializes the datadir"
  echo "  start_pxc_bootstrap  : Starts up the bootstrap node"
  echo "  start_pxc  : Starts up node"
  echo "  stop_pxc   : Stops the node"
  echo "  arb        : connect or disconnect the node from the network"
  echo "  node_cl    : Opens a mysql shell to a node"
  echo "  wipe       : Stops the node, removes subdirectories"
  echo ""
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"
my_ipaddr="${2}"
cluster_ipaddr="${3}"

if [[ ! -r "${config_file_path}" ]]; then
  echo "Cannot find the config file : '${config_file_path}'"
  exit 1
fi

echo ""
echo "Adding scripts:"
echo "  init_pxc   : Creates subdirectories and initializes the datadirs"
echo "  start_pxc  : Starts up a node"
echo "  start_pxc_bootstrap  : Starts up a bootstrapped node"
echo "  stop_pxc   : Stops the node"
echo "  arb        : connect or disconnect the node from the network"
echo "  node_cl    : Opens a mysql shell to a node"
echo "  wipe       : Stops the node, removes subdirectories"
echo ""

#RBASE1=4100
#LADDR1="$ipaddr1:$(( RBASE1 + 30 ))"
#RADDR1="$ipaddr1:$(( RBASE1 + 20 ))"

#RBASE2=4200
#LADDR2="$ipaddr1:$(( RBASE2 + 30 ))"
#RADDR2="$ipaddr1:$(( RBASE2 + 20 ))"

#RBASE3=5100
#LADDR3="$ipaddr2:$(( RBASE3 + 30 ))"
#RADDR3="$ipaddr2:$(( RBASE3 + 20 ))"

CLUSTER_ADDRESS="$my_ipaddr,$cluster_ipaddr"

node1="${BUILD}/data"

#
# Create the init_pxc1 script 
#
echo "echo 'Creating subdirectores'" > ./init_pxc
echo "mkdir -p $node1" >> ./init_pxc
echo "mkdir -p /tmp/pxc_node " >> ./init_pxc

echo "echo 'Initializing datadirs'" >> ./init_pxc
echo "if [ \"\$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./init_pxc
echo "elif [ \"\$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./init_pxc
echo "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./init_pxc
echo "fi" >> ./init_pxc

echo -e "\n" >> ./init_pxc

echo "\${MID} --datadir=$node1  > ${BUILD}/startup_node.err 2>&1 || exit 1;" >> ./init_pxc

echo -e "\n" >> ./init_pxc


#
# Creating start_pxc_bootstrap
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc_bootstrap
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc_bootstrap
echo -e "\n" >> ./start_pxc_bootstrap
echo "echo 'Starting PXC nodes..'" >> ./start_pxc_bootstrap
echo -e "\n" >> ./start_pxc_bootstrap

#
# Starting bootstrap node
#
echo "echo 'Starting bootstrap node ..'" >> ./start_pxc_bootstrap

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.1 \\" >> ./start_pxc_bootstrap
#echo "    --port=$RBASE1 \\" >> ./start_pxc_bootstrap
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc_bootstrap
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc_bootstrap
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc_bootstrap
#echo "    --wsrep_sst_receive_address=$RADDR1 \\" >> ./start_pxc_bootstrap
#echo "    --wsrep_node_incoming_address=$ipaddr1 \\" >> ./start_pxc_bootstrap
#echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR1;gmcast.segment=1\" \\" >> ./start_pxc_bootstrap
echo "    --wsrep-new-cluster  > $node1/error.log 2>&1 &" >> ./start_pxc_bootstrap

echo -e "\n" >> ./start_pxc_bootstrap

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc_bootstrap
echo "  sleep 1" >> ./start_pxc_bootstrap
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc_bootstrap
echo "    break" >> ./start_pxc_bootstrap
echo "  fi" >> ./start_pxc_bootstrap
echo "done" >> ./start_pxc_bootstrap

echo -e "\n" >> ./start_pxc_bootstrap


#
# Starting regular node
#
echo "PXC_MYEXTRA=\"\"" > ./start_pxc
echo "PXC_START_TIMEOUT=30"  >> ./start_pxc
echo -e "\n" >> ./start_pxc
echo "echo 'Starting PXC nodes..'" >> ./start_pxc
echo -e "\n" >> ./start_pxc

echo "echo 'Starting normal node ..'" >> ./start_pxc

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_pxc
#echo "    --port=$RBASE2 \\" >> ./start_pxc
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_pxc
echo "    --wsrep-provider=${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc
echo "    --wsrep_cluster_address=gcomm://$CLUSTER_ADDRESS \\" >> ./start_pxc
#echo "    --wsrep_sst_receive_address=$RADDR2 \\" >> ./start_pxc
#echo "    --wsrep_node_incoming_address=$ipaddr1 \\" >> ./start_pxc
#echo "    --wsrep_provider_options=\"$evs_options;gmcast.listen_addr=tcp://$LADDR2;gmcast.segment=1\" \\" >> ./start_pxc
echo "    > $node1/error.log 2>&1 &" >> ./start_pxc

echo -e "\n" >> ./start_pxc

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_pxc
echo "  sleep 1" >> ./start_pxc
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc
echo "    break" >> ./start_pxc
echo "  fi" >> ./start_pxc
echo "done" >> ./start_pxc

echo -e "\n" >> ./start_pxc



#
# Creating stop_pxc
#
echo "" > ./stop_pxc
echo "if [[ -r $node1/socket.sock ]]; then" >> ./stop_pxc
echo "  ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock shutdown" >> ./stop_pxc
echo "  echo 'Server on socket $node1/socket.sock with datadir node1 halted'" >> ./stop_pxc
echo "fi" >> ./stop_pxc
echo  "" >> ./stop_pxc


#
# Creating wipe
#
echo "if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi" > ./wipe

echo "if [ -d $node1 ]; then rm -rf $node1; fi" >> ./wipe

echo "rm -rf /tmp/pxc_node" >> ./wipe

echo "rm ./init_pxc ./start_pxc_bootstrap ./start_pxc ./stop_pxc ./node_cl ./arb" >> ./wipe
echo "" >> ./wipe

#
# Creating command-line scripts
#
echo "#! /bin/bash" > ./node_cl
echo "" >> ./node_cl
echo "$BUILD/bin/mysql -A -S$node1/socket.sock -uroot " >> ./node_cl


echo "#! /bin/bash" > ./arb
echo "" >> ./arb
echo "if [ \"\$#\" -ne 1 ]; then" >> ./arb
echo "  echo \"echo Usage:\"" >> ./arb
echo "  echo \"echo   arb connect <target-ipaddr>\"" >> ./arb
echo "  echo \"echo   arb disconnect <target-ipaddr>\"" >> ./arb
echo "  echo \"echo   arb list\"" >> ./arb
echo "  exit 1" >> ./arb
echo "fi" >> ./arb
echo "" >> ./arb

echo "arb_cmd=\$1" >> ./arb
echo "if [[ \$arb_cmd == \"connect\" || \$arb_cmd == \"disconnect\" ]]; then" >> ./arb
echo "  if [ \"\$#\" -ne 2 ]; then" >> ./arb
echo "    echo \"Usage:\"" >> ./arb
echo "    echo \"  arb connect <target-ipaddr>\"" >> ./arb
echo "    echo \"  arb disconnect <target-ipaddr>\"" >> ./arb
echo "    echo \"  arb list\"" >> ./arb
echo "  fi" >> ./arb
echo "  arb_target=\$2" >> ./arb
echo "fi" >> ./arb

echo "if [ \"\$arb_cmd\" == \"connect\" ]; then" >> ./arb
echo "  op=\"-D\"" >> ./arb
echo "elif [ \"\$arb_cmd\" == \"disconnect\" ]; then" >> ./arb
echo "  op=\"-A\"" >> ./arb
echo "elif [ \"\$arb_cmd\" == \"list\" ]; then" >> ./arb
echo "  date +%H:%M:%S.%0N -u" >> ./arb
echo "  iptables --list" >> ./arb
echo "  exit $?">> ./arb
echo "else" >> ./arb
echo "  echo \"Only 'connect','disconnect', and 'list' are allowed operations : '\$1'\"" >> ./arb
echo "  exit 1" >> ./arb
echo "fi" >> ./arb
echo "" >> ./arb

echo "  date +%H:%M:%S.%0N -u" >> ./arb
echo "iptables \$op INPUT -s \$arb_target -j DROP" >> ./arb
echo "iptables \$op OUTPUT -d \$arb_target -j DROP" >> ./arb

echo "" >> ./arb

chmod +x ./init_pxc ./start_pxc ./start_pxc_bootstrap ./stop_pxc ./node_cl ./wipe
chmod +x ./arb


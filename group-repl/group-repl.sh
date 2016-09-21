#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC

# check for config file parameter
if (( "$#" != 1 )); then
  echo "Usage:  group_repl.sh <config-file>"
  echo ""
  echo "Creates the following scripts:"
  echo "  init_gr   : Creates subdirectories and initializes the datadirs"
  echo "  start_gr  : Starts a 3-node cluster, node 1 is bootstrapped"
  echo "  stop_gr   : Stops the 3-node cluster"
  echo "  node_cl   : Opens a mysql shell to a node"
  echo "  wipe      : Stops the cluster, moves datadir to .PREV, removes subdirectories"
  exit 1
fi

BUILD=$(pwd)

config_file_path="${1}"

echo "Adding scripts: ./init_gr | ./start_gr | ./ stop_gr | ./node_cl | ./wipe"


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

innodb_tempdir1="${BUILD}/innodb_tempdir1"
innodb_tempdir2="${BUILD}/innodb_tempdir2"
innodb_tempdir3="${BUILD}/innodb_tempdir3"

#
# Creating the gr_init.sql script
# This script is run after initialization to create the necessary users
# for group replication. The "CREATE USER" has to be done only once, changing
# the master user has to be done on each node.
#
echo "" > ./gr_init.sql
echo "# Create the replication user" >> ./gr_init.sql
echo "CREATE USER rpl_user@'%';"  >> ./gr_init.sql
echo "GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';"  >> ./gr_init.sql
echo "FLUSH PRIVILEGES;"  >> ./gr_init.sql
echo ""  >> ./gr_init.sql
echo "# Setup the credentials for recovery" >> ./gr_init.sql
echo "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';" >> ./gr_init.sql
echo ""  >> ./gr_init.sql

echo "" > ./gr_init_short.sql
echo "# Setup the credentials for recovery" >> ./gr_init_short.sql
echo "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';" >> ./gr_init_short.sql
echo ""  >> ./gr_init_short.sql


#
# Create the init_gr script 
#
echo "echo 'Creating subdirectores'" > ./init_gr
echo "mkdir -p $node1 $node2 $node3" >> ./init_gr
echo "mkdir -p $keyring_node1 $keyring_node2 $keyring_node3" >> ./init_gr
echo "mkdir -p $innodb_tempdir1  $innodb_tempdir2  $innodb_tempdir3" >> ./init_gr
echo "mkdir -p /tmp/node1 /tmp/node2 /tmp/node3 " >> ./init_gr

echo "echo 'Initializing datadirs'" >> ./init_gr

# This is 5.7 only
echo "MID=\"${BUILD}/bin/mysqld \
              --no-defaults \
              --initialize-insecure \
              --basedir=. \"">> ./init_gr

echo -e "\n" >> ./init_gr

# Initialize the databases

# After initialization, we have to run a startup script to create
# the necessary replication users (this can't be done at initialization
# since it involves account management, i.e. CREATE USER).
echo -e "\n" >> ./init_gr
echo "echo 'Initializing node1'" >> ./init_gr
echo "\${MID} --server_id=1 --datadir=$node1 > ${BUILD}/startup_node1.err 2>&1 || exit 1;" >> ./init_gr
echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.1 \\" >> ./init_gr
echo "    --port=$RBASE1 \\" >> ./init_gr
echo "    --basedir=${BUILD} \$PXC_MYEXTRA > $node1/node1.err 2>&1 &" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "sleep 2" >> ./init_gr
echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./init_gr
echo "  sleep 1" >> ./init_gr
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock ping > /dev/null 2>&1; then" >> ./init_gr
echo "    break" >> ./init_gr
echo "  fi" >> ./init_gr
echo "done" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "${BUILD}/bin/mysql -S$node1/socket.sock -uroot < ./gr_init.sql >> $node1/node1.err 2>&1" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock shutdown" >> ./init_gr

echo "echo 'Initializing node2'" >> ./init_gr
echo "\${MID} --server_id=2 --datadir=$node2 > ${BUILD}/startup_node2.err 2>&1 || exit 1;" >> ./init_gr
echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./init_gr
echo "    --port=$RBASE2 \\" >> ./init_gr
echo "    --basedir=${BUILD} \$PXC_MYEXTRA > $node2/node2.err 2>&1 &" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "sleep 2" >> ./init_gr
echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./init_gr
echo "  sleep 1" >> ./init_gr
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock ping > /dev/null 2>&1; then" >> ./init_gr
echo "    break" >> ./init_gr
echo "  fi" >> ./init_gr
echo "done" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "${BUILD}/bin/mysql -S$node2/socket.sock -uroot < ./gr_init_short.sql >> $node2/node2.err 2>&1" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock shutdown" >> ./init_gr

echo "echo 'Initializing node3'" >> ./init_gr
echo "\${MID} --server_id=3 --datadir=$node3 > ${BUILD}/startup_node3.err 2>&1 || exit 1;" >> ./init_gr
echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.3 \\" >> ./init_gr
echo "    --port=$RBASE3 \\" >> ./init_gr
echo "    --basedir=${BUILD} \$PXC_MYEXTRA > $node3/node3.err 2>&1 &" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "sleep 2" >> ./init_gr
echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./init_gr
echo "  sleep 1" >> ./init_gr
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock ping > /dev/null 2>&1; then" >> ./init_gr
echo "    break" >> ./init_gr
echo "  fi" >> ./init_gr
echo "done" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "${BUILD}/bin/mysql -S$node3/socket.sock -uroot < ./gr_init_short.sql >> $node3/node3.err 2>&1" >> ./init_gr
echo -e "\n" >> ./init_gr
echo "${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock shutdown" >> ./init_gr

#
# Creating start_gr
#
echo "PXC_MYEXTRA=\"\"" > ./start_gr
echo "PXC_START_TIMEOUT=30"  >> ./start_gr
echo -e "\n" >> ./start_gr
echo "echo 'Starting PXC nodes..'" >> ./start_gr
echo -e "\n" >> ./start_gr


#
# Starting node 1
#
echo "echo 'Starting node 1..'" >> ./start_gr

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.1 \\" >> ./start_gr
echo "    --port=$RBASE1 \\" >> ./start_gr
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_gr
echo "    --plugin-load=group_replication.so \\" >> ./start_gr
echo "    --group_replication_group_name="00010002-0003-0004-0005-000600070008" \\" >> ./start_gr
echo "    --group_replication_local_address=$LADDR1 \\" >> ./start_gr
echo "    --group_replication_start_on_boot=OFF \\" >> ./start_gr
echo "    --group_replication_group_seeds=$LADDR1,$LADDR2,$LADDR3 \\" >> ./start_gr
echo "    > $node1/node1.err 2>&1 &" >> ./start_gr

echo -e "\n" >> ./start_gr
echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_gr
echo "  sleep 1" >> ./start_gr
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock ping > /dev/null 2>&1; then" >> ./start_gr
echo "    break" >> ./start_gr
echo "  fi" >> ./start_gr
echo "done" >> ./start_gr

# Now enable group replication
echo "echo 'Starting group replication on node1'" >> ./start_gr
echo "${BUILD}/bin/mysql -S$node1/socket.sock -uroot -Bse 'SET GLOBAL group_replication_bootstrap_group= 1;' >> $node1/node1.err 2>&1" >> ./start_gr
echo "${BUILD}/bin/mysql -S$node1/socket.sock -uroot -Bse 'START group_replication;' >> $node1/node1.err 2>&1" >> ./start_gr
echo "${BUILD}/bin/mysql -S$node1/socket.sock -uroot -Bse 'SET GLOBAL group_replication_bootstrap_group= 0;' >> $node1/node1.err 2>&1" >> ./start_gr
echo -e "\n" >> ./start_gr


#
# Starting node 2
#
echo "sleep 5" >> ./start_gr
echo "echo 'Starting node 2..'" >> ./start_gr

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.2 \\" >> ./start_gr
echo "    --port=$RBASE2 \\" >> ./start_gr
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_gr
echo "    --plugin-load=group_replication.so \\" >> ./start_gr
echo "    --group_replication_group_name="00010002-0003-0004-0005-000600070008" \\" >> ./start_gr
echo "    --group_replication_local_address=$LADDR2 \\" >> ./start_gr
echo "    --group_replication_start_on_boot=OFF \\" >> ./start_gr
echo "    --group_replication_group_seeds=$LADDR1,$LADDR2,$LADDR3 \\" >> ./start_gr
echo "    > $node2/node2.err 2>&1 &" >> ./start_gr

echo -e "\n" >> ./start_gr

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_gr
echo "  sleep 1" >> ./start_gr
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock ping > /dev/null 2>&1; then" >> ./start_gr
echo "    break" >> ./start_gr
echo "  fi" >> ./start_gr
echo "done" >> ./start_gr

echo "echo 'Starting group replication on node2'" >> ./start_gr
echo "${BUILD}/bin/mysql -S$node2/socket.sock -uroot -Bse 'START group_replication;' >> $node2/node2.err 2>&1" >> ./start_gr
echo -e "\n" >> ./start_gr


#
# Starting node 3
#
echo "sleep 5" >> ./start_gr
echo "echo 'Starting node 3..'" >> ./start_gr

echo "${BUILD}/bin/mysqld --defaults-file="${config_file_path}" --defaults-group-suffix=.3 \\" >> ./start_gr
echo "    --port=$RBASE3 \\" >> ./start_gr
echo "    --basedir=${BUILD} \$PXC_MYEXTRA \\" >> ./start_gr
echo "    --plugin-load=group_replication.so \\" >> ./start_gr
echo "    --group_replication_group_name="00010002-0003-0004-0005-000600070008" \\" >> ./start_gr
echo "    --group_replication_local_address=$LADDR3 \\" >> ./start_gr
echo "    --group_replication_start_on_boot=OFF \\" >> ./start_gr
echo "    --group_replication_group_seeds=$LADDR1,$LADDR2,$LADDR3 \\" >> ./start_gr
echo "    > $node3/node3.err 2>&1 &" >> ./start_gr

echo -e "\n" >> ./start_gr

echo "for X in \$( seq 0 \$PXC_START_TIMEOUT ); do" >> ./start_gr
echo "  sleep 1" >> ./start_gr
echo "  if ${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock ping > /dev/null 2>&1; then" >> ./start_gr
echo "    break" >> ./start_gr
echo "  fi" >> ./start_gr
echo "done" >> ./start_gr

echo "echo 'Starting group replication on node3'" >> ./start_gr
echo "${BUILD}/bin/mysql -S$node3/socket.sock -uroot -Bse 'START group_replication;' >> $node3/node3.err 2>&1" >> ./start_gr
echo -e "\n\n" >> ./start_gr


#
# Creating stop_gr
#
echo "${BUILD}/bin/mysqladmin -uroot -S$node3/socket.sock shutdown" > ./stop_gr
echo "echo 'Server on socket $node3/socket.sock with datadir ${BUILD}/node3 halted'" >> ./stop_gr
echo "${BUILD}/bin/mysqladmin -uroot -S$node2/socket.sock shutdown" >> ./stop_gr
echo "echo 'Server on socket $node2/socket.sock with datadir ${BUILD}/node2 halted'" >> ./stop_gr
echo "${BUILD}/bin/mysqladmin -uroot -S$node1/socket.sock shutdown" >> ./stop_gr
echo "echo 'Server on socket $node1/socket.sock with datadir ${BUILD}/node1 halted'" >> ./stop_gr

#
# Create the wipe (this will save off the datadir)
#
echo "if [ -r ./stop_gr ]; then ./stop_gr 2>/dev/null 1>&2; fi" > ./wipe
echo "if [ -d $BUILD/node1.PREV ]; then rm -rf $BUILD/node1.PREV; fi;mv $BUILD/node1 $BUILD/node1.PREV" >> ./wipe
echo "if [ -d $BUILD/node2.PREV ]; then rm -rf $BUILD/node2.PREV; fi;mv $BUILD/node2 $BUILD/node2.PREV" >> ./wipe
echo "if [ -d $BUILD/node3.PREV ]; then rm -rf $BUILD/node3.PREV; fi;mv $BUILD/node3 $BUILD/node3.PREV" >> ./wipe

echo "rm -rf ${keyring_node1}" >> ./wipe
echo "rm -rf ${keyring_node2}" >> ./wipe
echo "rm -rf ${keyring_node3}" >> ./wipe

echo "rm -rf ${innodb_tempdir1}" >> ./wipe
echo "rm -rf ${innodb_tempdir2}" >> ./wipe
echo "rm -rf ${innodb_tempdir3}" >> ./wipe

echo "rm -rf /tmp/node1" >> ./wipe
echo "rm -rf /tmp/node2" >> ./wipe
echo "rm -rf /tmp/node3" >> ./wipe


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

chmod +x ./init_gr ./start_gr ./stop_gr ./node_cl ./wipe


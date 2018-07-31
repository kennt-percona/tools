#!/bin/bash -ue
# Created by Ramesh Sivaraman, Percona LLC
#
#  This script is used to generate a testing environment for proxysql.
#  This will create two 3-node PXC clusters.
#
#  Usage:
#
#     ./pxc-generate.sh <path-to-workdir> <mysql-config-file> <host-ip-address>
#
#       The working directory ("workdir") is required.  This is the location
#       where the binaries for proxysql and pxc may be found.
#       The following layout is expected:
#         path/to/workdir/
#           pxc_tarball/
#           proxysql_dir/
#           proxysql_admin_dir/
#       The data directories of the pxc nodes will also be created in the workdir.
#
#       Only one config file is used to configure both clusters.
#       Cluster one will use "mysqld.1.1", "mysqld.1.2", and "mysqld.1.3"
#       Cluster two will use "mysqld.2.1", "mysqls.2.2", and "mysqld.2.3"
#
#     ./install_binaries  # prep work before running any code
#                         # extracts tarball, installs code into proper locations
#     ./init_pxc          # Initializes both clusters
#     ./init_proxysql     # Initializes the proxysql config
#     ./start_cluster1    # Starts the 3 nodes in the first cluster
#     ./start_cluster2    # Starts the 3 nodes in the second cluster
#     ./start_proxysql    # Starts up proxysql
#     ./node_cl xx        # Opens up a mysql on a node
#     ./stop_cluster2
#     ./stop_cluster1
#     ./stop_proxysql
#     ./wipe
#


# Exit on command failure
set -o errexit

# Catch errors when piping commands
set -o pipefail

# Error when using unset variables
set -o nounset

if [[ $# -ne 3 ]]; then
    echo "Usage:  pxc-generate <workdir> <config-file-template> <ipaddr>"
    echo ""
    echo "Usage example:"
    echo "    $ ./pxc-generate.sh path/to/workdir sample.cnf 127.0.0.1"
    echo ""
    echo "The workdir must contain the PXC tarball, the proxysql build,"
    echo "and the proxysql-admin.cnf"
    echo "    For example:"
    echo "        /path/to/workdir"
    echo "            percona-xtradb-cluster-5.XX.tar.gz"
    echo "            proxysql-1.X.XX/"
    echo "            proxysql-admin.cnf"
    echo "    The datadirs and the final sample.cnf will be created in the workdir"
    echo ""
    echo "Creates the following scripts:"
    echo "  install_binaries  : extracts and installs binaries"
    echo "  init_pxc          : initializes PXC clusters"
    echo "  init_proxysql     : initializes the proxysql config"
    echo "  start_cluster1    : starts the 3 nodes in the first cluster"
    echo "  start_cluster2    : starts the 3 nodes in the second cluster"
    echo "  start_proxysql    : starts proxysql"
    echo "  node_cl           : opens up a mysql shell to a node"
    echo "  stop_cluster1"
    echo "  stop_cluster2"
    echo "  stop_proxysql"
    echo "  wipe              : removes the datadirs"
    echo ""
    echo "Also generates the sample.cnf from the config-file-template"
    exit 1
fi

#
# User Configurable Variables
#
PXC_START_TIMEOUT=200
PXC_MYEXTRA=""
SUSER=root
SPASS=
OS_USER=$(whoami)


#
# Setup some variables
#
if [[ ! -d $1 ]]; then
    echo "The first parameter (workdir) does not exist : $1"
    exit 1
fi

pushd "$1" > /dev/null
WORKDIR=$(pwd)
popd > /dev/null

if [[ ! -r $2 ]]; then
    echo "The second parameter (config file template path) does not exist or is not readable : $2"
    exit 1
fi
CONFIG_FILE_TEMPLATE_PATH=$2

IPADDR=$3

# The location of the current script
SCRIPTDIR=$(dirname "$0")

# The location where to place the various files
# The generated files will be placed in the location where the script is run.
BUILDDIR=$(pwd)

#
# Setup the IP addresses used by the PXC clusters
#

# Ports in the 4XXX range are for cluster 1
RBASE11=4100
LADDR11="$IPADDR:$(( RBASE11 + 10 ))"
RADDR11="$IPADDR:$(( RBASE11 + 20 ))"

RBASE12=4200
LADDR12="$IPADDR:$(( RBASE12 + 10 ))"
RADDR12="$IPADDR:$(( RBASE12 + 20 ))"

RBASE13=4300
LADDR13="$IPADDR:$(( RBASE13 + 10 ))"
RADDR13="$IPADDR:$(( RBASE13 + 20 ))"

# Ports in the 5XXX are for cluster 2
RBASE21=5100
LADDR21="$IPADDR:$(( RBASE21 + 10 ))"
RADDR21="$IPADDR:$(( RBASE21 + 20 ))"

RBASE22=5200
LADDR22="$IPADDR:$(( RBASE22 + 10 ))"
RADDR22="$IPADDR:$(( RBASE22 + 20 ))"

RBASE23=5300
LADDR23="$IPADDR:$(( RBASE23 + 10 ))"
RADDR23="$IPADDR:$(( RBASE23 + 20 ))"


#
# Create the sample.cnf
#
echo "Creating sample.cnf in ${WORKDIR}..."
cp "$CONFIG_FILE_TEMPLATE_PATH" "${WORKDIR}/sample.cnf"
sed -i -e "s,WORKDIR,$WORKDIR,g" "${WORKDIR}/sample.cnf"

# Specify the paths to the datadirs for the nodes in cluster 1 and cluster 2
node11_datadir="${WORKDIR}/node11"
node12_datadir="${WORKDIR}/node12"
node13_datadir="${WORKDIR}/node13"

node21_datadir="${WORKDIR}/node21"
node22_datadir="${WORKDIR}/node22"
node23_datadir="${WORKDIR}/node23"

#
# Create the "install_binaries" script
#
echo "Creating install_binaries..."
echo "#!/bin/bash -ue" > ${BUILDDIR}/install_binaries
echo -e "\n" >> ${BUILDDIR}/install_binaries

echo "echo Removing existing PXC install" >> ${BUILDDIR}/install_binaries
echo "pushd $WORKDIR >> /dev/null" >> ${BUILDDIR}/install_binaries
echo "find . -maxdepth 1 -type d -name 'Percona-XtraDB-Cluster-5.*' -exec rm -rf {} \+" >> ${BUILDDIR}/install_binaries
echo "" >> ${BUILDDIR}/install_binaries
echo "echo Installing PXC..." >> ${BUILDDIR}/install_binaries
echo "PXC_TAR=\$(ls -1td ?ercona-?tra??-?luster* | grep '.tar' | head -n1)" >> ${BUILDDIR}/install_binaries
echo "if [[ ! -z \$PXC_TAR ]];then" >> ${BUILDDIR}/install_binaries
echo "    echo Extracting PXC..." >> ${BUILDDIR}/install_binaries
echo "    tar -xzf \$PXC_TAR" >> ${BUILDDIR}/install_binaries
echo "    PXC_BASEDIR=\$(ls -1td ?ercona-?tra??-?luster* | grep -v '.tar' | head -n1)" >> ${BUILDDIR}/install_binaries
echo "else" >> ${BUILDDIR}/install_binaries
echo "    echo ERROR! Percona-XtraDB-Cluster binary tarball does not exist. Terminating" >> ${BUILDDIR}/install_binaries
echo "    popd >> /dev/null" >> ${BUILDDIR}/install_binaries
echo "    exit 1" >> ${BUILDDIR}/install_binaries
echo "fi" >> ${BUILDDIR}/install_binaries
echo -e "\n" >> ${BUILDDIR}/install_binaries

echo "if [[ -z \$PXC_BASEDIR ]]; then" >> ${BUILDDIR}/install_binaries
echo "    echo ERROR! Cannot find the Percona-XtraDB-Cluster installation directory. Terminating!" >> ${BUILDDIR}/install_binaries
echo "    popd >> /dev/null" >> ${BUILDDIR}/install_binaries
echo "    exit 1" >> ${BUILDDIR}/install_binaries
echo "fi" >> ${BUILDDIR}/install_binaries
echo -e "\n" >> ${BUILDDIR}/install_binaries

echo "echo Creating symbolic link: pxc-bin -\\> \$PXC_BASEDIR" >> ${BUILDDIR}/install_binaries
echo "ln -s \$PXC_BASEDIR pxc-bin" >> ${BUILDDIR}/install_binaries
echo -e "\n" >> ${BUILDDIR}/install_binaries

echo "if [[ ! -e \$(which \$PXC_BASEDIR/bin/mysql 2> /dev/null) ]] ;then" >> ${BUILDDIR}/install_binaries
echo "  echo ERROR! Cannot find mysql in '\$PXC_BASEDIR/bin/'.  Please check the PXC tarball. Terminating!" >> ${BUILDDIR}/install_binaries
echo "  popd >> /dev/null" >> ${BUILDDIR}/install_binaries
echo "  exit 1" >> ${BUILDDIR}/install_binaries
echo "fi" >> ${BUILDDIR}/install_binaries
echo -e "\n" >> ${BUILDDIR}/install_binaries

# Setup the proxysql directory paths
# Make it so that the local version of proxysql is in the path before
# the system binaries.
#
echo "echo Setting up proxysql" >> ${BUILDDIR}/install_binaries
echo "PROXYSQL_BASE=\$(ls -1td proxysql-1* | grep -v '.tar' | head -n1)" >> ${BUILDDIR}/install_binaries
echo "if [[ -z \$PROXYSQL_BASE ]]; then" >> ${BUILDDIR}/install_binaries
echo "  echo ERROR! Cannot find the proxysql installation directory. Terminating!" >> ${BUILDDIR}/install_binaries
echo "  popd >> /dev/null" >> ${BUILDDIR}/install_binaries
echo "  exit 1" >> ${BUILDDIR}/install_binaries
echo "fi" >> ${BUILDDIR}/install_binaries
echo -e "\n" >> ${BUILDDIR}/install_binaries

echo "echo Creating symbolic link: proxysql-bin -\\> \$PROXYSQL_BASE" >> ${BUILDDIR}/install_binaries
echo "ln -s \$PROXYSQL_BASE proxysql-bin" >> ${BUILDDIR}/install_binaries
echo "PROXYSQL_BASE=\"${WORKDIR}/\$PROXYSQL_BASE\"" >> ${BUILDDIR}/install_binaries
echo "if [[ ! \$PATH =~ \$PROXYSQL_BASE/usr/bin ]]; then" >> ${BUILDDIR}/install_binaries
echo "    export PATH=\"\$PROXYSQL_BASE/usr/bin/:\$PATH\"" >> ${BUILDDIR}/install_binaries
echo "fi" >> ${BUILDDIR}/install_binaries
echo "popd >> /dev/null" >> ${BUILDDIR}/install_binaries
echo -e "\n" >> ${BUILDDIR}/install_binaries


#
# Create the "init_pxc" script
#
echo "Creating init_pxc..."
echo "#!/bin/bash -ue" > ${BUILDDIR}/init_pxc
echo -e "\n" >> ${BUILDDIR}/init_pxc

echo "echo 'Creating subdirectores'" >> ${BUILDDIR}/init_pxc
echo "rm -rf $node11_datadir $node12_datadir $node13_datadir $node21_datadir $node22_datadir $node23_datadir" >> ${BUILDDIR}/init_pxc
echo "mkdir -p $node11_datadir $node12_datadir $node13_datadir $node21_datadir $node22_datadir $node23_datadir" >> ${BUILDDIR}/init_pxc
echo "mkdir -p $WORKDIR/logs" >> ${BUILDDIR}/init_pxc
echo -e "\n" >> ${BUILDDIR}/init_pxc

echo "PXC_BINDIR=$WORKDIR/pxc-bin" >> ${BUILDDIR}/init_pxc
echo "if [[ ! -d \$PXC_BINDIR ]]; then" >> ${BUILDDIR}/init_pxc
echo "    echo Error! Cannot find the PXC bin dir!" >> ${BUILDDIR}/init_pxc
echo "    exit 1" >> ${BUILDDIR}/init_pxc
echo "fi" >> ${BUILDDIR}/init_pxc
echo -e "\n" >> ${BUILDDIR}/init_pxc

echo "echo Initializing datadirs..." >> ${BUILDDIR}/init_pxc
echo "MYSQLD_VERSION=\$(\${PXC_BINDIR}/bin/mysqld --version)"  >> ${BUILDDIR}/init_pxc
echo "if [ \"\$(echo \$MYSQLD_VERSION | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ${BUILDDIR}/init_pxc
echo "  MID=\"\${PXC_BINDIR}/bin/mysqld --no-defaults --initialize-insecure --innodb_log_checksums=ON --basedir=\${PXC_BINDIR}\"" >> ${BUILDDIR}/init_pxc
echo "elif [ \"\$(echo \$MYSQLD_VERSION  | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ${BUILDDIR}/init_pxc
echo "  MID=\"\${PXC_BINDIR}/scripts/mysql_install_db --no-defaults --basedir=\${PXC_BINDIR}\"" >> ${BUILDDIR}/init_pxc
echo "else" >> ${BUILDDIR}/init_pxc
echo "    echo Unexpected mysqld version: \$MYSQLD_VERSION" >> ${BUILDDIR}/init_pxc
echo "    exit 1" >> ${BUILDDIR}/init_pxc
echo "fi" >> ${BUILDDIR}/init_pxc

echo -e "\n" >> ${BUILDDIR}/init_pxc
 
echo "echo Initializing node11..." >> ${BUILDDIR}/init_pxc
echo "rm -rf $node11_datadir; mkdir $node11_datadir" >> ${BUILDDIR}/init_pxc
echo "\${MID} --datadir=$node11_datadir  > ${WORKDIR}/logs/node11.err 2>&1 || exit 1;" >> ${BUILDDIR}/init_pxc

echo "echo Initializing node12..." >> ${BUILDDIR}/init_pxc
echo "rm -rf $node12_datadir; mkdir $node12_datadir" >> ${BUILDDIR}/init_pxc
echo "\${MID} --datadir=$node12_datadir  > ${WORKDIR}/logs/node12.err 2>&1 || exit 1;" >> ${BUILDDIR}/init_pxc

echo "echo Initializing node13..." >> ${BUILDDIR}/init_pxc
echo "rm -rf $node13_datadir; mkdir $node13_datadir" >> ${BUILDDIR}/init_pxc
echo "\${MID} --datadir=$node13_datadir  > ${WORKDIR}/logs/node13.err 2>&1 || exit 1;" >> ${BUILDDIR}/init_pxc
echo -e "\n" >> ${BUILDDIR}/init_pxc

echo "echo Initializing node21..." >> ${BUILDDIR}/init_pxc
echo "rm -rf $node21_datadir; mkdir $node21_datadir" >> ${BUILDDIR}/init_pxc
echo "\${MID} --datadir=$node21_datadir  > ${WORKDIR}/logs/node21.err 2>&1 || exit 1;" >> ${BUILDDIR}/init_pxc

echo "echo Initializing node22..." >> ${BUILDDIR}/init_pxc
echo "rm -rf $node22_datadir; mkdir $node22_datadir" >> ${BUILDDIR}/init_pxc
echo "\${MID} --datadir=$node22_datadir  > ${WORKDIR}/logs/node22.err 2>&1 || exit 1;" >> ${BUILDDIR}/init_pxc

echo "echo Initializing node23..." >> ${BUILDDIR}/init_pxc
echo "rm -rf $node23_datadir; mkdir $node23_datadir" >> ${BUILDDIR}/init_pxc
echo "\${MID} --datadir=$node23_datadir  > ${WORKDIR}/logs/node23.err 2>&1 || exit 1;" >> ${BUILDDIR}/init_pxc
echo -e "\n" >> ${BUILDDIR}/init_pxc

#
# Create the start_cluster scripts
#

function write_node_start()
{
    local output_file=$1
    local node_id=$2
    local rbase=$3
    local laddr=$4
    local raddr=$5
    local cluster_addr=$6
    local bootstrap=$7

    echo "\${PXC_BINDIR}/bin/mysqld-debug --defaults-file=\"${WORKDIR}/sample.cnf\" --defaults-group-suffix=\".$node_id\" \\" >> $output_file
    echo "    --port=$rbase \\" >>  $output_file
    echo "    --basedir=\${PXC_BINDIR} $PXC_MYEXTRA \\" >>  $output_file
    echo "    --wsrep-provider=\${PXC_BINDIR}/lib/libgalera_smm.so \\" >>  $output_file
    echo "    --wsrep_cluster_address=gcomm://$cluster_addr \\" >>  $output_file
    echo "    --wsrep_sst_receive_address=$raddr \\" >>  $output_file
    echo "    --wsrep_node_incoming_address=$IPADDR \\" >>  $output_file
    echo "    --wsrep_provider_options=gmcast.listen_addr=tcp://$laddr \\" >>  $output_file
    #echo "    --wsrep_node_address=$RADDR1  \\" >>  $output_file
    if [[ $bootstrap -eq 1 ]]; then
        echo "    --wsrep-new-cluster \\" >> $output_file
    fi
    echo "    > $WORKDIR/logs/node${node_id}.err 2>&1 &" >>  $output_file

    echo -e "\n" >>  $output_file

    echo "for X in \$( seq 0 $PXC_START_TIMEOUT ); do" >>  $output_file
    echo "  sleep 1" >>  $output_file
    echo "  if \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node${node_id}/socket.sock ping > /dev/null 2>&1; then" >>  $output_file
    echo "    break" >>  $output_file
    echo "  fi" >>  $output_file
    echo "done" >>  $output_file

    echo -e "\n" >>  $output_file
}

#
# Starting cluster 1
#
cluster_address="$LADDR11,$LADDR12,$LADDR13"

echo "Creating start_cluster1..."
echo "#!/bin/bash -ue" > ${BUILDDIR}/start_cluster1
echo -e "\n" >> ${BUILDDIR}/start_cluster1

echo "PXC_BINDIR=$WORKDIR/pxc-bin" >> ${BUILDDIR}/start_cluster1
echo "if [[ ! -d \$PXC_BINDIR ]]; then" >> ${BUILDDIR}/start_cluster1
echo "    echo Error! Cannot find the PXC bin dir!" >> ${BUILDDIR}/start_cluster1
echo "    exit 1" >> ${BUILDDIR}/start_cluster1
echo "fi" >> ${BUILDDIR}/start_cluster1
echo -e "\n" >> ${BUILDDIR}/start_cluster1

echo "echo Starting cluster 1 node 1..." >> ${BUILDDIR}/start_cluster1
write_node_start ${BUILDDIR}/start_cluster1 "11" $RBASE11 $LADDR11 $RADDR11 $cluster_address 1

echo "echo Starting cluster 1 node 2..." >> ${BUILDDIR}/start_cluster1
write_node_start ${BUILDDIR}/start_cluster1 "12" $RBASE12 $LADDR12 $RADDR12 $cluster_address 0

echo "echo Starting cluster 1 node 3..." >> ${BUILDDIR}/start_cluster1
write_node_start ${BUILDDIR}/start_cluster1 "13" $RBASE13 $LADDR13 $RADDR13 $cluster_address 0

echo -e "\n" >> ./start_cluster1


#
# Starting cluster 2
#
cluster_address="$LADDR21,$LADDR22,$LADDR23"

echo "Creating start_cluster2..."
echo "#!/bin/bash -ue" > ${BUILDDIR}/start_cluster2
echo -e "\n" >> ${BUILDDIR}/start_cluster2

echo "PXC_BINDIR=$WORKDIR/pxc-bin" >> ${BUILDDIR}/start_cluster2
echo "if [[ ! -d \$PXC_BINDIR ]]; then" >> ${BUILDDIR}/start_cluster2
echo "    echo Error! Cannot find the PXC bin dir!" >> ${BUILDDIR}/start_cluster2
echo "    exit 1" >> ${BUILDDIR}/start_cluster2
echo "fi" >> ${BUILDDIR}/start_cluster2
echo -e "\n" >> ${BUILDDIR}/start_cluster2

echo "echo Starting cluster 2 node 1..." >> ${BUILDDIR}/start_cluster2
write_node_start ${BUILDDIR}/start_cluster2 "21" $RBASE21 $LADDR21 $RADDR21 $cluster_address 1

echo "echo Starting cluster 2 node 2..." >> ${BUILDDIR}/start_cluster2
write_node_start ${BUILDDIR}/start_cluster2 "22" $RBASE22 $LADDR22 $RADDR22 $cluster_address 0

echo "echo Starting cluster 2 node 3..." >> ${BUILDDIR}/start_cluster2
write_node_start ${BUILDDIR}/start_cluster2 "23" $RBASE23 $LADDR23 $RADDR23 $cluster_address 0

echo -e "\n" >> ./start_cluster2

#
# Create the init_proxysql script
#
echo "Creating init_proxysql..."
echo "#!/bin/bash -ue" > ${BUILDDIR}/init_proxysql
echo -e "\n" >> ${BUILDDIR}/init_proxysql

echo "PXC_BINDIR=$WORKDIR/pxc-bin" >> ${BUILDDIR}/init_proxysql
echo "if [[ ! -d \$PXC_BINDIR ]]; then" >> ${BUILDDIR}/init_proxysql
echo "    echo Error! Cannot find the PXC bin dir!" >> ${BUILDDIR}/init_proxysql
echo "    exit 1" >> ${BUILDDIR}/init_proxysql
echo "fi" >> ${BUILDDIR}/init_proxysql
echo -e "\n" >> ${BUILDDIR}/init_proxysql

echo "if [[ ! -r ${BUILDDIR}/proxysql-admin.cnf ]]; then" >> ${BUILDDIR}/init_proxysql
echo "    echo Cannot find the proxysql-admin.cnf in ${BUILDDIR}" >> ${BUILDDIR}/init_proxysql
echo "    exit 1" >> ${BUILDDIR}/init_proxysql
echo "fi" >> ${BUILDDIR}/init_proxysql
echo -e "\n" >> ${BUILDDIR}/init_proxysql

echo "if (( \$EUID != 0 )); then" >> ${BUILDDIR}/init_proxysql
echo "    echo This script must be run as root \(or sudo\) because it needs" >> ${BUILDDIR}/init_proxysql
echo "    echo to copy the proxysql-admin.cnf to /etc/" >> ${BUILDDIR}/init_proxysql
echo "    exit 1" >> ${BUILDDIR}/init_proxysql
echo "fi" >> ${BUILDDIR}/init_proxysql
echo -e "\n" >> ${BUILDDIR}/init_proxysql

echo "if ! \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node11/socket.sock ping > /dev/null 2>&1; then" >> ${BUILDDIR}/init_proxysql
echo "    echo Error! Cluster 1 node 1 must be running!" >> ${BUILDDIR}/init_proxysql
echo "    exit 1" >> ${BUILDDIR}/init_proxysql
echo "fi" >> ${BUILDDIR}/init_proxysql
echo "echo Granting access to admin user on cluster 1..." >> ${BUILDDIR}/init_proxysql
echo "\${PXC_BINDIR}/bin/mysql -uroot -S$WORKDIR/node11/socket.sock -e \"GRANT ALL ON *.* TO admin@'%' identified by 'admin';flush privileges;\"" >> ${BUILDDIR}/init_proxysql
echo -e "\n" >> ${BUILDDIR}/init_proxysql

echo "if ! \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node21/socket.sock ping > /dev/null 2>&1; then" >> ${BUILDDIR}/init_proxysql
echo "    echo Error! Cluster 2 node 1 must be running!" >> ${BUILDDIR}/init_proxysql
echo "    exit 1" >> ${BUILDDIR}/init_proxysql
echo "fi" >> ${BUILDDIR}/init_proxysql
echo "echo Granting access to admin user on cluster 2..." >> ${BUILDDIR}/init_proxysql
echo "\${PXC_BINDIR}/bin/mysql -uroot -S$WORKDIR/node21/socket.sock -e \"GRANT ALL ON *.* TO admin@'%' identified by 'admin';flush privileges;\"" >> ${BUILDDIR}/init_proxysql
echo -e "\n" >> ${BUILDDIR}/init_proxysql

echo "PROXYSQL_BINDIR=$WORKDIR/proxysql-bin" >> ${BUILDDIR}/init_proxysql
echo -e "\n" >> ${BUILDDIR}/init_proxysql

echo "BUILDDIR=$BUILDDIR" >> ${BUILDDIR}/init_proxysql
echo "echo Copying proxysql config to system location : /etc/proxysql-admin.cnf" >> ./init_proxysql
echo "sudo cp $BUILDDIR/proxysql-admin.cnf /etc/proxysql-admin.cnf" >> ./init_proxysql
echo "sudo chown $OS_USER:$OS_USER /etc/proxysql-admin.cnf" >> ./init_proxysql
echo "sudo sed -i \"s|\/var\/lib\/proxysql|\$BUILDDIR|\" /etc/proxysql-admin.cnf" >> ./init_proxysql
echo -e "\n" >> ${BUILDDIR}/init_proxysql


#
# Startup proxysql
#
echo Creating start_proxysql...
echo "#!/bin/bash -ue" > ${BUILDDIR}/start_proxysql
echo -e "\n" >> ${BUILDDIR}/start_proxysql

echo "PROXYSQL_BINDIR=$WORKDIR/proxysql-bin" >> ${BUILDDIR}/start_proxysql
echo -e "\n" >> ${BUILDDIR}/start_proxysql

echo "echo Recreating proxysql database..." >> ${BUILDDIR}/start_proxysql
echo "rm -rf $WORKDIR/proxysql_db; mkdir $WORKDIR/proxysql_db" >> ${BUILDDIR}/start_proxysql
echo "echo Starting proxysql..." >> ${BUILDDIR}/start_proxysql
echo "\$PROXYSQL_BINDIR/usr/bin/proxysql -D $WORKDIR/proxysql_db  $WORKDIR/proxysql_db/proxysql.log &" >> ${BUILDDIR}/start_proxysql
echo "echo \$! > $WORKDIR/proxysql.pid" >> ${BUILDDIR}/start_proxysql
echo "echo proxysql pid written to $WORKDIR/proxysql.pid" >> ${BUILDDIR}/start_proxysql


#
# stop_cluster1
#
echo Creating stop_cluster1...
echo "#!/bin/bash -ue" > ${BUILDDIR}/stop_cluster1
echo -e "\n" >> ${BUILDDIR}/stop_cluster1

echo "PXC_BINDIR=$WORKDIR/pxc-bin" >> ${BUILDDIR}/stop_cluster1
echo "if [[ ! -d \$PXC_BINDIR ]]; then" >> ${BUILDDIR}/stop_cluster1
echo "    echo Error! Cannot find the PXC bin dir!" >> ${BUILDDIR}/stop_cluster1
echo "    exit 1" >> ${BUILDDIR}/stop_cluster1
echo "fi" >> ${BUILDDIR}/stop_cluster1
echo -e "\n" >> ${BUILDDIR}/stop_cluster1


echo "echo Stopping PXC cluster 1 node 3" > ${BUILDDIR}/stop_cluster1
echo "if [[ -r $WORKDIR/node13/socket.sock ]]; then" >> ${BUILDDIR}/stop_cluster1
echo "  \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node13/socket.sock shutdown" >> ${BUILDDIR}/stop_cluster1
echo "  echo 'Server on socket node13/socket.sock with datadir ${node13_datadir} halted'" >> ${BUILDDIR}/stop_cluster1
echo "fi" >> ${BUILDDIR}/stop_cluster1
echo -e "\n" >> ${BUILDDIR}/stop_cluster1

echo "echo Stopping PXC cluster 1 node 2" > ${BUILDDIR}/stop_cluster1
echo "if [[ -r $WORKDIR/node12/socket.sock ]]; then" >> ${BUILDDIR}/stop_cluster1
echo "  \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node12/socket.sock shutdown" >> ${BUILDDIR}/stop_cluster1
echo "  echo 'Server on socket node12/socket.sock with datadir ${node12_datadir} halted'" >> ${BUILDDIR}/stop_cluster1
echo "fi" >> ${BUILDDIR}/stop_cluster1
echo -e "\n" >> ${BUILDDIR}/stop_cluster1

echo "echo Stopping PXC cluster 1 node 1" > ${BUILDDIR}/stop_cluster1
echo "if [[ -r $WORKDIR/node11/socket.sock ]]; then" >> ${BUILDDIR}/stop_cluster1
echo "  \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node11/socket.sock shutdown" >> ${BUILDDIR}/stop_cluster1
echo "  echo 'Server on socket node11/socket.sock with datadir ${node11_datadir} halted'" >> ${BUILDDIR}/stop_cluster1
echo "fi" >> ${BUILDDIR}/stop_cluster1
echo -e "\n" >> ${BUILDDIR}/stop_cluster1


#
# stop_cluster2
#
echo Creating stop_cluster2...
echo "#!/bin/bash -ue" > ${BUILDDIR}/stop_cluster2
echo -e "\n" >> ${BUILDDIR}/stop_cluster2

echo "PXC_BINDIR=$WORKDIR/pxc-bin" >> ${BUILDDIR}/stop_cluster2
echo "if [[ ! -d \$PXC_BINDIR ]]; then" >> ${BUILDDIR}/stop_cluster2
echo "    echo Error! Cannot find the PXC bin dir!" >> ${BUILDDIR}/stop_cluster2
echo "    exit 1" >> ${BUILDDIR}/stop_cluster2
echo "fi" >> ${BUILDDIR}/stop_cluster2
echo -e "\n" >> ${BUILDDIR}/stop_cluster2

echo "echo Stopping PXC cluster 2 node 3" > ${BUILDDIR}/stop_cluster2
echo "if [[ -r $WORKDIR/node23/socket.sock ]]; then" >> ${BUILDDIR}/stop_cluster2
echo "  \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node23/socket.sock shutdown" >> ${BUILDDIR}/stop_cluster2
echo "  echo 'Server on socket node23/socket.sock with datadir ${node23_datadir} halted'" >> ${BUILDDIR}/stop_cluster2
echo "fi" >> ${BUILDDIR}/stop_cluster2
echo -e "\n" >> ${BUILDDIR}/stop_cluster2

echo "echo Stopping PXC cluster 2 node 2" > ${BUILDDIR}/stop_cluster2
echo "if [[ -r $WORKDIR/node22/socket.sock ]]; then" >> ${BUILDDIR}/stop_cluster2
echo "  \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node22/socket.sock shutdown" >> ${BUILDDIR}/stop_cluster2
echo "  echo 'Server on socket node22/socket.sock with datadir ${node22_datadir} halted'" >> ${BUILDDIR}/stop_cluster2
echo "fi" >> ${BUILDDIR}/stop_cluster2
echo -e "\n" >> ${BUILDDIR}/stop_cluster2

echo "echo Stopping PXC cluster 2 node 1" > ${BUILDDIR}/stop_cluster2
echo "if [[ -r $WORKDIR/node21/socket.sock ]]; then" >> ${BUILDDIR}/stop_cluster2
echo "  \${PXC_BINDIR}/bin/mysqladmin -uroot -S$WORKDIR/node21/socket.sock shutdown" >> ${BUILDDIR}/stop_cluster2
echo "  echo 'Server on socket node21/socket.sock with datadir ${node21_datadir} halted'" >> ${BUILDDIR}/stop_cluster2
echo "fi" >> ${BUILDDIR}/stop_cluster2
echo -e "\n" >> ${BUILDDIR}/stop_cluster2



#
# stop proxysql
#
echo Creating stop_proxysql...
echo "#!/bin/bash -ue" > ${BUILDDIR}/stop_proxysql
echo -e "\n" >> ${BUILDDIR}/stop_proxysql

echo "echo ---- IMPORTANT ----" >> ${BUILDDIR}/stop_proxysql
echo "echo Killing ALL processes named proxysql..." >> ${BUILDDIR}/stop_proxysql
echo "echo -------------------" >> ${BUILDDIR}/stop_proxysql
echo "killall proxysql" >> ${BUILDDIR}/stop_proxysql
echo -e "\n" >> ${BUILDDIR}/stop_proxysql

echo "echo removing $WORKDIR/proxysql.pid" >> ${BUILDDIR}/stop_proxysql
echo "rm -rf $WORKDIR/proxysql.pid" >> ${BUILDDIR}/stop_proxysql

#
# wipe
#
echo Creating wipe...
echo "#!/bin/bash -ue" > ${BUILDDIR}/wipe
echo -e "\n" >> ${BUILDDIR}/wipe

echo "if [ -r ${BUILDDIR}/stop_cluster1 ]; then ${BUILDDIR}/stop_cluster1 2>/dev/null 1>&2; fi" > ${BUILDDIR}/wipe
echo "if [ -r ${BUILDDIR}/stop_cluster2 ]; then ${BUILDDIR}/stop_cluster2 2>/dev/null 1>&2; fi" > ${BUILDDIR}/wipe
echo "rm -rf $node11_datadir" >> ${BUILDDIR}/wipe
echo "rm -rf $node12_datadir" >> ${BUILDDIR}/wipe
echo "rm -rf $node13_datadir" >> ${BUILDDIR}/wipe
echo "rm -rf $node21_datadir" >> ${BUILDDIR}/wipe
echo "rm -rf $node22_datadir" >> ${BUILDDIR}/wipe
echo "rm -rf $node23_datadir" >> ${BUILDDIR}/wipe
echo -e "\n" >> ${BUILDDIR}/wipe

echo "rm -rf ${BUILDDIR}/install_binaries ${BUILDDIR}/init_pxc ${BUILDDIR}/init_proxysql" >> ${BUILDDIR}/wipe
echo "rm -rf ${BUILDDIR}/start_cluster1 ${BUILDDIR}/start_cluster2" >> ${BUILDDIR}/wipe
echo "rm -rf ${BUILDDIR}/stop_cluster1 ${BUILDDIR}/stop_cluster2" >> ${BUILDDIR}/wipe
echo "rm -rf ${BUILDDIR}/start_proxysql ${BUILDDIR}/stop_proxysql" >> ${BUILDDIR}/wipe
echo "rm -rf ${BUILDDIR}/node_cl" >> ${BUILDDIR}/wipe
echo -e "\n" >> ${BUILDDIR}/wipe


#
# node_cl
#
echo Creating node_cl...
echo "#!/bin/bash -ue" > ${BUILDDIR}/node_cl
echo -e "\n" >> ${BUILDDIR}/node_cl

echo "PXC_BINDIR=$WORKDIR/pxc-bin" >> ${BUILDDIR}/node_cl
echo "if [[ ! -d \$PXC_BINDIR ]]; then" >> ${BUILDDIR}/node_cl
echo "    echo Error! Cannot find the PXC bin dir!" >> ${BUILDDIR}/node_cl
echo "    exit 1" >> ${BUILDDIR}/node_cl
echo "fi" >> ${BUILDDIR}/node_cl
echo -e "\n" >> ${BUILDDIR}/node_cl

echo "if (( \"\$#\" != 1 )); then" >> ${BUILDDIR}/node_cl
echo "  echo \"Usage: node_cl <node_number>\"" >> ${BUILDDIR}/node_cl
echo "  exit 1" >> ${BUILDDIR}/node_cl
echo "fi" >> ${BUILDDIR}/node_cl
echo "" >> ${BUILDDIR}/node_cl
echo "\${PXC_BINDIR}/bin/mysql -A -S$WORKDIR/node\$1/socket.sock -uroot " >> ${BUILDDIR}/node_cl
echo -e "\n" >> ${BUILDDIR}/node_cl



chmod +x ${BUILDDIR}/install_binaries ${BUILDDIR}/init_pxc ${BUILDDIR}/init_proxysql
chmod +x ${BUILDDIR}/start_cluster1 ${BUILDDIR}/start_cluster2
chmod +x ${BUILDDIR}/stop_cluster1 ${BUILDDIR}/stop_cluster2
chmod +x ${BUILDDIR}/start_proxysql ${BUILDDIR}/stop_proxysql
chmod +x ${BUILDDIR}/node_cl ${BUILDDIR}/wipe



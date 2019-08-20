#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $(realpath $0))/../include/tools_common.sh

# Globals
declare     BUILD=$(pwd)
declare  -i PXC_START_TIMEOUT=30
declare     PXC_MYEXTRA=""
declare     CLUSTER_ADDRESS=""

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: Incorrect number of parameters"
  echo ""
  echo "Usage: gdb-cluster-start.sh <node-name>"
  echo "  Starts up a bootstrapped PXC cluster node (only one node)"
  echo ""
  echo "  It is also assumed that this is being run from the basedir"
  echo ""
  exit 1
fi

first_node_name="${1}"

# Set this so that the other nodes can use this to connect
# Calling start_node() with is_bootstrapped=1 will make it
# set CLUSTER_ADDRESS.
gdb_start_node "${first_node_name}" 1


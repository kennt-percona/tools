#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $0)/../include/tools_common.sh

# Globals
declare     BUILD=$(pwd)
declare  -i PXC_START_TIMEOUT=30
declare     PXC_MYEXTRA=""
declare     CLUSTER_ADDRESS=""

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: Incorrect number of parameters"
  echo ""
  echo "Usage: cluster-start.sh <node-name1> <node-name2> ..."
  echo "  Takes a list of node-names to be used in the cluster"
  echo "  The first node in the list of nodes will be bootstrapped."
  echo ""
  echo "  It is also assumed that this is being run from the basedir"
  echo ""
  exit 1
fi

first_node_name="${1}"
shift

# Set this so that the other nodes can use this to connect
# Calling start_node() with is_bootstrapped=1 will make it
# set CLUSTER_ADDRESS.
start_node "${first_node_name}" 1

for node_name in "$@"; do
  start_node "${node_name}" 0
done

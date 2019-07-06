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
  echo "Usage: cluster-join.sh <node-name1> <node-name2> ..."
  echo "  Takes a list of node-names to be used in the cluster"
  echo "  The first node in the list of nodes is assumed to be running."
  echo ""
  echo "  It is also assumed that this is being run from the basedir"
  echo ""
  exit 1
fi

first_node_name="${1}"
shift

# Setup the CLUSTER_ADDRESS from the first node
node_info_path="${first_node_name}.info"
if [[ ! -r ${node_info_path} ]]; then
  echo "Error: Cannot find the ${node_info_path} file"
  exit 1
fi
ip_address=$(info_get_variable "${node_info_path}" "ip-address")
galera_port=$(info_get_variable "${node_info_path}" "galera-port")
CLUSTER_ADDRESS="${ip_address}:${galera_port}"

for node_name in "$@"; do
  start_node "${node_name}" 0
done

#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $0)/../include/tools_common.sh

# Globals
declare  -i PXC_START_TIMEOUT=30
declare     PXC_MYEXTRA=""

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: Incorrect number of parameters"
  echo ""
  echo "Usage: mysql-start.sh <node-name1> <node-name2> ..."
  echo "  Starts up the list of standalone nodes (non-PXC)"
  echo ""
  echo "  It is also assumed that this is being run from the basedir"
  echo ""
  exit 1
fi

for node_name in "$@"; do
  start_mysql "${node_name}"
done

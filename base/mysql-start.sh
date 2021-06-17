#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $(realpath $0))/../include/tools_common.sh

# Globals
declare  -i PXC_START_TIMEOUT=30
declare     PXC_MYEXTRA=""

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: Incorrect number of parameters"
  echo ""
  echo "Usage: mysql-start.sh <node-name1> <additional options>"
  echo "  Starts up a single node (as a non-PXC node)"
  echo ""
  echo "  It is also assumed that this is being run from the basedir"
  echo ""
  exit 1
fi

# gather up all the other parameters
node_name="$1"
shift

other_options="$@"

start_mysql "${node_name}" "${other_options}"

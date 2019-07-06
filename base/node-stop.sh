#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $0)/../include/tools_common.sh

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: Incorrect number of parameters"
  echo ""
  echo "Usage: node-stop.sh <node-name1> <node-name2> ..."
  echo "  Takes a list of node-names to be stopped."
  echo "  The nodes will be stopped in the order they appear."
  echo ""
  echo "  It is also assumed that this is being run from the basedir"
  echo ""
  exit 1
fi


for node_name in "$@"; do
  node_info_path="${node_name}.info"

  if [[ ! -r ${node_info_path} ]]; then
    echo "Error: Cannot find the ${node_info_path} file"
    exit 1
  fi

  # get info from the info file
  basedir=$(info_get_variable "${node_info_path}" "basedir")
  socket=$(info_get_variable "${node_info_path}" "socket")

  mysqladmin_path="${basedir}/bin/mysqladmin"
  if [[ ! -x $mysqladmin_path ]]; then
    echo "ERROR: Cannot find the mysqladmin executable"
    echo "Expected location: ${mysqladmin_path}"
    exit 1
  fi

  echo "--------------------------------"
  echo "Stopping ${node_name}"

  if [[ -r $socket ]]; then
    ${mysqladmin_path} -uroot -S${socket} shutdown
    echo 'Server with socket ${socket} halted'
  fi

done

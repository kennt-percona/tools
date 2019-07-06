#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $0)/../include/tools_common.sh

# Globals
if [[ "$#" -ne 1 ]]; then
  echo "ERROR: Incorrect number of parameters"
  echo ""
  echo "Usage: node-cl.sh <node-name>"
  echo "  Opens a mysql shell to a node."
  echo ""
  exit 1
fi

node_name="${1}"
node_info_path="${node_name}.info"

if [[ ! -r ${node_info_path} ]]; then
  echo "Error: Cannot find the ${node_info_path} file"
  exit 1
fi

# get info from the info file
ip_address=$(info_get_variable "${node_info_path}" "ip-address")
port=$(info_get_variable "${node_info_path}" "client-port")
basedir=$(info_get_variable "${node_info_path}" "basedir")
socket=$(info_get_variable "${node_info_path}" "socket")

if [[ -e $socket ]]; then
	# local connection
	${basedir}/bin/mysql -A -S${socket} -uroot
else
	# (possibly) remote connection
	echo "Could not find socket file, trying ${ip_address}:${port}"
	${basedir}/bin/mysql -A --host=${ip_address} --port=${port} --protocol=tcp -uroot
fi

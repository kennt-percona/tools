#!/bin/bash
#
# This script will create the information file for a single node.
# 

set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $(realpath $0))/../include/tools_common.sh

# check for config file parameter
if (( "$#" != 4 )); then
  echo "Incorrect number of parameters"
  echo ""
  echo "Usage:  pxc-config.sh <node-name> <config-file> <ipaddr> <base-port>"
  echo ""
  echo "Creates the information file for the node"
  echo ""
  exit 1
fi

#
# Global variables
#
declare     BUILD=$(pwd)

declare     NODE_NAME="${1}"
declare     CONFIG_FILE_PATH="${2}"
declare     IPADDR="${3}"
declare     BASE_PORT=${4}

declare -i  RBASE=${BASE_PORT}

# Listen address
declare -i  LPORT=$(( RBASE + 30 ))

# Receive address
declare -i  RPORT=$(( RBASE + 20 ))

declare     DATADIR_BASE_PATH="${BUILD}"
declare     NODE_DATADIR="${DATADIR_BASE_PATH}/${NODE_NAME}"


INFO_SCRIPT_NAME="${NODE_NAME}.info"


if [[ ! -r "${CONFIG_FILE_PATH}" ]]; then
  echo "Cannot find the config file : '${CONFIG_FILE_PATH}'"
  exit 1
fi

MYSQLD_PATH="${BUILD}/bin/mysqld"
if [[ ! -x $MYSQLD_PATH ]]; then
  echo "ERROR: Cannot find the mysqld executable"
  echo "Expected location: ${MYSQLD_PATH}"
  exit 1
fi
declare mysql_version=$(get_version "${MYSQLD_PATH}")

# Info file (information about a named node)
echo "node-name     : ${NODE_NAME}" > ./${INFO_SCRIPT_NAME}
echo "mysql-version : ${mysql_version}" >> ./${INFO_SCRIPT_NAME}
echo "basedir       : ${BUILD}" >> ./${INFO_SCRIPT_NAME}
echo "datadir       : ${NODE_DATADIR}" >> ./${INFO_SCRIPT_NAME}
echo "socket        : ${NODE_DATADIR}/socket.sock" >> ./${INFO_SCRIPT_NAME}
echo "ip-address    : ${IPADDR}" >> ./${INFO_SCRIPT_NAME}
echo "client-port   : ${RBASE}" >> ./${INFO_SCRIPT_NAME}
echo "galera-port   : ${LPORT}" >> ./${INFO_SCRIPT_NAME}
echo "sst-port      : ${RPORT}" >> ./${INFO_SCRIPT_NAME}
echo "config-file   : ${CONFIG_FILE_PATH}" >> ./${INFO_SCRIPT_NAME}
echo "error-log-file: ${NODE_DATADIR}/error.log" >> ./${INFO_SCRIPT_NAME}
echo "" >> ./${INFO_SCRIPT_NAME}

echo "Created ${INFO_SCRIPT_NAME}"


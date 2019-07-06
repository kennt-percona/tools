#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $0)/../include/tools_common.sh

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: Incorrect number of parameters"
  echo ""
  echo "Usage: node-init.sh <node-name1> <node-name2> ..."
  echo "  Takes a list of node-names to be initialized"
  echo ""
  echo "  It is assumed that then there is a section in the config-file"
  echo "  for each node:"
  echo "      [mysqld.<node-name>]"
  echo "      # node-specific configuration"
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
  ip_address=$(info_get_variable "${node_info_path}" "ip-address")
  port=$(info_get_variable "${node_info_path}" "client-port")
  basedir=$(info_get_variable "${node_info_path}" "basedir")
  datadir=$(info_get_variable "${node_info_path}" "datadir")
  config_file_path=$(info_get_variable "${node_info_path}" "config-file")


  mysqld_path="${basedir}/bin/mysqld"
  if [[ ! -x $mysqld_path ]]; then
    echo "ERROR: Cannot find the mysqld executable"
    echo "Expected location: ${mysqld_path}"
    exit 1
  fi
  mysql_version=$(get_version "${mysqld_path}")

  echo "--------------------------------"
  echo "Initializing ${node_name} with MySQL ${mysql_version} (${mysqld_path})"

  echo "Creating datadir (${datadir})"
  mkdir -p ${datadir}

  echo "Replacing DATADIR_BASE_PATH with ${basedir} in ${config_file_path}"
  # Need to escape any slashes in the datadir (since it will contain a path)
  # This will change '/' to '\/'
  #safe_node_datadir=${node_datadir//\//\/\\/}
  sed -i "s/DATADIR_BASE_PATH/${basedir//\//\\/}/" "$config_file_path"

  if [[ $mysql_version =~ ^5.6 ]]; then
    MID="${basedir}/scripts/mysql_install_db --no-defaults --basedir=${basedir}"
  elif [[ $mysql_version =~ ^5.7 ]]; then
    MID="${basedir}/bin/mysqld --no-defaults --initialize-insecure --basedir=${basedir}"
  elif [[ $mysql_version =~ ^8.0 ]]; then
    MID="${basedir}/bin/mysqld --no-defaults --initialize-insecure --basedir=${basedir}"
  else
    echo "Error: Unsupported MySQL version : ${mysql_version}"
    exit 1
  fi

  echo "Initializing datadir"
  ${MID} --datadir=${datadir}  > ./startup_${node_name}.err 2>&1 || exit 1;
done

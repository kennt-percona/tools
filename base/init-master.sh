#! /bin/bash
set -o pipefail   # Expose hidden failures
set -o nounset    # Expose unset variables

. $(dirname $(realpath $0))/../include/tools_common.sh

if (( "$#" != 1 )); then
  echo "Incorrect number of parameters"
  echo ""
  echo "Usage:  init-master.sh <node-name>"
  echo ""
  echo "Initializes the node for being an async master"
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

mysqld_path="${basedir}/bin/mysqld"
if [[ ! -x $mysqld_path ]]; then
  echo "ERROR: Cannot find the mysqld executable"
  echo "Expected location: ${mysqld_path}"
  exit 1
fi
mysql_version=$(get_version "${mysqld_path}")

#
# Configure the master for replication
#
echo 'Setting up the user account on the master'

  if [[ $mysql_version =~ ^5.6 ]]; then
    ${basedir}/bin/mysql -S${socket} -uroot <<EOF
      CREATE USER 'repl'@'%' IDENTIFIED BY 'repl';
      GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
      FLUSH PRIVILEGES;
EOF
  elif [[ $mysql_version =~ ^5.7 ]]; then
    ${basedir}/bin/mysql -S${socket} -uroot <<EOF
      CREATE USER 'repl'@'%' IDENTIFIED WITH 'mysql_native_password' BY 'repl';
      GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
      FLUSH PRIVILEGES;
EOF
  elif [[ $mysql_version =~ ^8.0 ]]; then
    ${basedir}/bin/mysql -S${socket} -uroot <<EOF
      CREATE USER 'repl'@'%' IDENTIFIED WITH 'mysql_native_password' BY 'repl';
      GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
      FLUSH PRIVILEGES;
EOF
  else
    echo "Error: Unsupported MySQL version : ${mysql_version}"
    exit 1
  fi

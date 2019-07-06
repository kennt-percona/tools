
# Returns the version string in a standardized format
# Input "1.2.3" => echoes "010203"
# Wrongly formatted values => echoes "000000"
#
# Globals:
#   None
#
# Arguments:
#   Parameter 1: a version string
#                like "5.1.12"
#                anything after the major.minor.revision is ignored
# Outputs:
#   A string that can be used directly with string comparisons.
#   So, the string "5.1.12" is transformed into "050112"
#   Note that individual version numbers can only go up to 99.
#
function normalize_version()
{
    local major=0
    local minor=0
    local patch=0

    # Only parses purely numeric version numbers, 1.2.3
    # Everything after the first three values are ignored
    if [[ $1 =~ ^([0-9]+)\.([0-9]+)\.?([0-9]*)([^ ])* ]]; then
        major=${BASH_REMATCH[1]}
        minor=${BASH_REMATCH[2]}
        patch=${BASH_REMATCH[3]}
    fi

    printf %02d%02d%02d $major $minor $patch
}

# Compares two version strings
#   The version strings passed in will be normalized to a
#   string-comparable version.
#
# Globals:
#   None
#
# Arguments:
#   Parameter 1: The left-side of the comparison
#   Parameter 2: the comparison operation
#                   '>', '>=', '=', '==', '<', '<=', "!="
#   Parameter 3: The right-side of the comparison
#
# Returns:
#   Returns 0 (success) if param1 op param2
#   Returns 1 (failure) otherwise
#
function compare_versions()
{
    local version_1="$( normalize_version $1 )"
    local op=$2
    local version_2="$( normalize_version $3 )"

    if [[ ! " = == > >= < <= != " =~ " $op " ]]; then
        wsrep_log_error "******************* ERROR ********************** "
        wsrep_log_error "Unknown operation : $op"
        wsrep_log_error "Must be one of : = == > >= < <="
        wsrep_log_error "******************* ERROR ********************** "
        return 1
    fi

    [[ $op == "<"  &&   $version_1 <  $version_2 ]] && return 0
    [[ $op == "<=" && ! $version_1 >  $version_2 ]] && return 0
    [[ $op == "="  &&   $version_1 == $version_2 ]] && return 0
    [[ $op == "==" &&   $version_1 == $version_2 ]] && return 0
    [[ $op == ">"  &&   $version_1 >  $version_2 ]] && return 0
    [[ $op == ">=" && ! $version_1 <  $version_2 ]] && return 0
    [[ $op == "!=" &&   $version_1 != $version_2 ]] && return 0

    return 1
}



function convert_normalized_version_to_string()
{
    local normalized=$1
    local major=${normalized:0:2}
    local minor=${normalized:2:2}
    local revision=${normalized:4:2}

    printf "%d.%d.%d" ${major#0} ${minor#0} ${revision#0}
    return 0
}

#
# Get the version from the executable path
#
# Globals
#   None
#
# Arguments
#   Parameter 1 : the path to the executable
#                 Assumes that the executable takes a "--version" option
#
# Returns
#   Writes the normalized version to stdout
#
function get_version()
{
  local exe_path=$1
  local version_output=""

  version_output=$(${exe_path} --version)
  version_output=$(echo $version_output | grep -oe '[[:space:]][[:digit:]].[[:digit:]][^[:space:]]*' | head -1)
  version_output=${version_output# }

  local version_str
  version_str=$(expr match "$version_output" '\([0-9]\+\.[0-9]\+\.[0-9]\+\)')

  printf "%s" "$version_str"
  return 0
}


# Returns the value portion from a line in the .info file
#
# Globals:
#   None
#
# Arguments:
#   Parameter 1 : the name of the .info file
#   Parameter 2 : the variable name
#
# Output:
#   Writes out the value of the variable
#   Whitespace will be removed from the front of the variable
#
function info_get_variable()
{
  local info_file_name=$1
  local variable_name=$2
  local value=""

  value=$(cat ${info_file_name} | grep "${variable_name}" | cut -d':' -f2-)
  value=$(echo $value)

  printf "%s" $value
}

# Tries to ping the node
#
# Globals:
#   BUILD
#
# Arguments:
#   Parameter 1: the IP address of the node
#   Parameter 2: the port of the node
#
function mysql_ping_node()
{
  local ip_address=$1
  local port=$2

  if [[ ! -x "${BUILD}/bin/mysqladmin" ]]; then
    echo "Error: Could not find the mysqladmin binary"
    echo "  location: $BUILD/bin/mysqladmin"
    return 1
  fi

  if ${BUILD}/bin/mysqladmin --user=root --host=$ip_address --port=$port --protocol=tcp ping > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Starts up a PXC
#
# Globals:
#   CLUSTER_ADDRESS (overwrites if bootstrapped = 1)
#   PXC_MYEXTRA
#
# Arguments:
#   (1) : the node name (used to find the info file)
#   (2) : 1 if node is to be bootstrapped, 0 otherwise
#
function start_node()
{
  local node_name=${1}
  local is_bootstrapped=${2}

  local node_info_path
  local ip_address port galera_port sst_port
  local basedir datadir config_file_path socket
  local mysqld_path mysql_version
  local more_options=""
  local mysqld_pid

  node_info_path="${node_name}.info"

  if [[ ! -r ${node_info_path} ]]; then
    echo "Error: Cannot find the ${node_info_path} file"
    exit 1
  fi

  if [[ $is_bootstrapped -eq 0 && -z $CLUSTER_ADDRESS ]]; then
    echo "ERROR: this is not a boostrapped node,"
    echo "so CLUSTER_ADDRESS must be set before calling this function."
    exit 1
  fi

  # get info from the info file
  ip_address=$(info_get_variable "${node_info_path}" "ip-address")
  port=$(info_get_variable "${node_info_path}" "client-port")
  galera_port=$(info_get_variable "${node_info_path}" "galera-port")
  sst_port=$(info_get_variable "${node_info_path}" "sst-port")
  basedir=$(info_get_variable "${node_info_path}" "basedir")
  datadir=$(info_get_variable "${node_info_path}" "datadir")
  config_file_path=$(info_get_variable "${node_info_path}" "config-file")
  error_log_path=$(info_get_variable "${node_info_path}" "error-log-file")
  socket=$(info_get_variable "${node_info_path}" "socket")


  mysqld_path="${basedir}/bin/mysqld"
  if [[ ! -x $mysqld_path ]]; then
    echo "ERROR: Cannot find the mysqld executable"
    echo "Expected location: ${mysqld_path}"
    exit 1
  fi
  mysql_version=$(get_version "${mysqld_path}")

  echo "--------------------------------"
  echo "Starting ${node_name} with MySQL ${mysql_version} (${mysqld_path})"
  if [[ $is_bootstrapped -eq 1 ]]; then
    echo "${node_name} will be bootstrapped (--wsrep-new-cluster)"
    more_options="--wsrep-new-cluster"
  else
    echo "${node_name} will be joining the cluster at (${CLUSTER_ADDRESS})"
  fi

  ${mysqld_path} --defaults-file=${config_file_path} --defaults-group-suffix=.${node_name} \
    --port=${port} \
    --basedir=${basedir} $PXC_MYEXTRA \
    --wsrep-provider=${basedir}/lib/libgalera_smm.so \
    --wsrep_cluster_address=gcomm://${CLUSTER_ADDRESS} \
    --wsrep_sst_receive_address=${ip_address}:${sst_port} \
    --wsrep_node_incoming_address=${ip_address} \
    --wsrep_provider_options=";gmcast.listen_addr=tcp://${ip_address}:${galera_port};gmcast.segment=1" \
    ${more_options}  > ${error_log_path} 2>&1 &
  mysqld_pid=$!


  for X in $( seq 0 $PXC_START_TIMEOUT ); do
    sleep 1
    if ! ps --pid $mysqld_pid >/dev/null; then
      echo "Process mysqld ($mysqld_pid) failed to start"
      exit 1
    fi
    if ${basedir}/bin/mysqladmin -uroot -S${socket} ping > /dev/null 2>&1; then
      break
    fi
  done

  if [[ $is_bootstrapped -eq 1 ]]; then
    CLUSTER_ADDRESS=$(printf "%s:%d" ${ip_address} ${galera_port})
  fi
}


# Starts up a standalone node (non-PXC)
#
# Globals:
#   PXC_MYEXTRA
#
# Arguments:
#   (1) : the node name (used to find the info file)
#
function start_mysql()
{
  local node_name=${1}

  local node_info_path
  local ip_address port galera_port sst_port
  local basedir datadir config_file_path socket
  local mysqld_path mysql_version
  local more_options=""
  local mysqld_pid

  node_info_path="${node_name}.info"

  if [[ ! -r ${node_info_path} ]]; then
    echo "Error: Cannot find the ${node_info_path} file"
    exit 1
  fi

  # get info from the info file
  ip_address=$(info_get_variable "${node_info_path}" "ip-address")
  port=$(info_get_variable "${node_info_path}" "client-port")
  basedir=$(info_get_variable "${node_info_path}" "basedir")
  config_file_path=$(info_get_variable "${node_info_path}" "config-file")
  error_log_path=$(info_get_variable "${node_info_path}" "error-log-file")
  socket=$(info_get_variable "${node_info_path}" "socket")


  mysqld_path="${basedir}/bin/mysqld"
  if [[ ! -x $mysqld_path ]]; then
    echo "ERROR: Cannot find the mysqld executable"
    echo "Expected location: ${mysqld_path}"
    exit 1
  fi
  mysql_version=$(get_version "${mysqld_path}")

  echo "--------------------------------"
  echo "Starting standalone ${node_name} with MySQL ${mysql_version} (${mysqld_path})"

  ${mysqld_path} --defaults-file=${config_file_path} --defaults-group-suffix=.${node_name} \
    --port=${port} \
    --basedir=${basedir} $PXC_MYEXTRA \
    --wsrep-provider= \
    ${more_options}  > ${error_log_path} 2>&1 &
  mysqld_pid=$!


  for X in $( seq 0 $PXC_START_TIMEOUT ); do
    sleep 1
    if ! ps --pid $mysqld_pid >/dev/null; then
      echo "Process mysqld ($mysqld_pid) failed to start"
      exit 1
    fi
    if ${basedir}/bin/mysqladmin -uroot -S${socket} ping > /dev/null 2>&1; then
      break
    fi
  done
}

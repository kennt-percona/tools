
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


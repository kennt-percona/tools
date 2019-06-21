#! /bin/bash
set -o nounset

if [[ "$#" == 0 || "$1" == "help" || "$1" == "--help" ]]; then
  cat <<EOF
  Controls the connectivity for the entire node.

  Usage: ./network.sh <command> [--target=<target>]
            [--port=<port>] [--ports=<ports>]

  <target>  : The IP address that is being targeted
              This is optional and may be left out.
              default (0.0.0.0)
  <port>    : Used only for connect-ports and disconnect-ports
              In addition to numeric values, this may take the
              value of 'mysql' (3306) or 'galera' (4567,4568).
              This option may take multiple ports (separated by commas).

  Commands:
    connect     : enable connectivity (remove rules)
    disconnect  : disable connectivity (add rules to block ports)
    list        : show current iptables ruleset
EOF
  exit 1
fi

net_cmd=$1
shift

target_ip=""
port_option=""
op=""
op_desc=""
target_ports=""

case "$net_cmd" in
    connect )
        # Drop all rules for the target
        op="-D"
        op_desc="Dropping rule"
    ;;
    disconnect )
        # Add a rule for the target
        op="-A"
        op_desc="Adding rule"
    ;;
    list )
        iptables --list | ts "%F %T :"
        exit 0
    ;;
    *)
        echo "Unknown command: $net_cmd"
        exit 1
    ;;
esac

while [[ $# -gt 0 ]]; do
    param=`echo $1 | awk -F= '{print $1}'`
    value=`echo $1 | awk -F= '{print $2}'`

    case $param in
        --target )
            target_ip="${value}"
            shift
        ;;
        --port )
            if [[ $value == 'mysql' ]]; then
                value="3306"
            elif [[ $value == 'galera' ]]; then
                value="4567,4568"
            fi

            target_ports=$value
            if [[ $value =~ , ]]; then
                port_option="--match=multiport --dports $value"
            else
                port_option="--dport $value"
            fi

            shift
        ;;
        *)
          echo "ERROR: unknown parameter \"$1\""
          exit 1
        ;;
    esac
    shift
done

target_source=""
target_dest=""
if [[ -n $target_ip ]]; then
    target_source="-s $target_ip"
    target_dest="-d $target_ip"
else
    target_ip="(anywhere)"
fi

if [[ -z $port_option ]]; then
    echo "$op_desc : drop packets from $target_ip"
    iptables $op INPUT $target_source -j DROP | ts "%F %T :"
    iptables $op OUTPUT $target_dest -j DROP | ts "%F %T :"
else
    echo "$op_desc : drop packets from $target_ip : $target_ports (udp and tcp)"
    iptables $op INPUT $target_source -p tcp $port_option -j DROP | ts "%F %T :"
    iptables $op OUTPUT $target_dest -p tcp $port_option -j DROP | ts "%F %T :"

    echo "$op_desc : drop packets from $target_ip : $target_ports (udp and tcp)"
    iptables $op INPUT $target_source -p udp $port_option -j DROP | ts "%F %T :"
    iptables $op OUTPUT $target_dest -p udp $port_option -j DROP | ts "%F %T :"
fi

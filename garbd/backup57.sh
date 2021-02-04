#!/bin/bash

set -o errexit
#set -o xtrace
set -o nounset

if [[ "$#" -ne 7 ]]; then
    echo "Error: Incorrect number of parameters"
    echo ""
    echo "Usage: backup.sh <cluster-name> <donor-name> <cluster-ip> <cluster-port> <sst-ip> <sst-port> <garbd-port>"
    echo "  It is assumed that the receiver is running on the local machine"
    echo ""
    echo "  cluster-name :  the name of the cluster we are joining"
    echo "  donor-name   :  the wsrep-node-name of the donor node"
    echo "  cluster-ip   : the IP address of a cluster node"
    echo "  cluster-port : the Galera port of a cluster node"
    echo "  sst-ip       : the IP address of this garbd node"
    echo "  sst-port     : the SST port used by this garbd node"
    echo "  garbd-port   : the Galera port used by this garbd node"
    echo ""
    exit 1
fi

CLUSTER_NAME=$1
DONOR_NAME=$2
CLUSTER_IP=$3
CLUSTER_PORT=$4
SST_IP=$5
SST_PORT=$6
GARBD_PORT=$7

#
# Set the wait_prim_timeout.  This will make garbd error out
# if it does not join the cluster within 5 seconds.
#
GARBD_OPTS="pc.wait_prim_timeout=PT5S"
SOCAT_OPTS="TCP-LISTEN:${SST_PORT},reuseaddr"

if [[ $GARBD_PORT -eq $SST_PORT ]]; then
    echo "Error, the garbd-port must be different from the sst-port"
    echo "    garbd:$GARBD_PORT  sst-port:$SST_PORT"
    exit 1
fi

#
# Have garbd send the SST request
#
function request_streaming() {
    local garbd_logfile="garbd.log"

    timeout -k 45 40 \
        /home/kennt/dev/pxc/build-bin/bin/garbd \
            --address "gcomm://${CLUSTER_IP}:${CLUSTER_PORT}?gmcast.listen_addr=tcp://0.0.0.0:${GARBD_PORT}" \
            --donor "${DONOR_NAME}" \
            --group "${CLUSTER_NAME}" \
            --options "${GARBD_OPTS}" \
            --sst "xtrabackup-v2:${SST_IP}:${SST_PORT}/xtrabackup_sst//1" \
            2>&1 | tee ${garbd_logfile}
    rc="${PIPESTATUS[0]}"
    echo "garbd returned : $rc"
    if [[ $rc -ne 0 ]]; then
        echo "garbd failed with $rc"
        exit 1
    fi

    #
    # There are times when garbd returns 0 but has failed
    # to send the SST request.  Check the error log for those
    # conditions (usually this happens when garbd fails to
    # join the cluster).
    #
    if grep 'State transfer request failed' $garbd_logfile; then
        exit 1
    fi
    if grep 'WARN: Protocol violation. JOIN message sender ... (garb) is not in state transfer' ${garbd_logfile}; then
        exit 1
    fi
    if grep 'WARN: Rejecting JOIN message from ... (garb): new State Transfer required.' $garbd_logfile; then
        exit 1
    fi
}

#
# Makes a backup of a pxc node
#
function backup_volume() {
    local backup_dir="backup.${SST_PORT}.d"
    rm -rf "$backup_dir"
    mkdir -p "$backup_dir"
    cd "$backup_dir" || exit

    echo "Backup to $backup_dir started"
    request_streaming

    echo "Starting socat(1)"
    timeout -k 45 40 socat -u "$SOCAT_OPTS" stdio > xtrabackup.stream.1
    if [[ $? -ne 0 ]]; then
        echo "socat(1) failed"
        exit 1
    fi
    echo "socat(1) returned $?"

    stat xtrabackup.stream.1

    echo "Starting socat(2)"
    socat -u "$SOCAT_OPTS" stdio > xtrabackup.stream.2
    echo "socat(2) returned $?"

    echo "Backup finished"

    stat xtrabackup.stream.2
}

backup_volume

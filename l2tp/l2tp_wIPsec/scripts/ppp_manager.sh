#!/bin/bash

PROGRAMNAME="XL2TP ENTRYPOINT INITIAL SCRIPT"

INFO="${PRINT_INFO}"
DEBUG="${PRINT_DEBUG}"
PPP_IF="${PPP_NETIF}"
POLLING_PERIOD=10
SCRIPT="/app/ppp_setup.sh"
KA_HOSTS=("8.8.8.8" "8.8.4.4" "1.1.1.1")

XL2TPD_PID=0
XL2TPD_RESTARTED="false"

IPSEC_PID=0
IPSEC_RESTARTED="false"
IPSEC_TUNNEL_RESTARTED="false"

LOG_DEBUG() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "$1"
        #msg="$1"
        #/usr/bin/logger -t $PROGRAMNAME -p user.debug "$msg"
    fi
}

LOG_INFO() {
    if [[ "$INFO" == "true" ]]; then
        echo "$1"
        #msg="$1"
        #/usr/bin/logger -t $PROGRAMNAME -p user.info "$msg"
    fi
}

LOG_ERROR() {
    echo "$1"
    #msg="$1"
    #/usr/bin/logger -s -t $PROGRAMNAME -p user.error "$msg"
}

LOG_INFO "${PROGRAMNAME} started..."
LOG_INFO " - interface: ${PPP_IF}"

if [ -z "${VPN_SERVER_IP}" ]; then
    LOG_ERROR "VPN SERVER IP: Not set"
    exit 1
else
    LOG_INFO "VPN SERVER IP: ${VPN_SERVER_IP}"
fi

if [ -z "${VPN_USER}" ]; then
    LOG_ERROR "VPN USER: Not set"
    exit 1
else
    LOG_INFO "VPN USER: ${VPN_USER}"
fi

if [ -z "${VPN_PASSWORD}" ]; then
    LOG_ERROR "VPN PASSWORD: Not set"
    exit 1
else
    LOG_INFO "VPN PASSWORD: HIDDEN"
fi

if [[ -z "${VPN_IPSEC_PSK}" ]]; then
    echo "VPN IPSEC PSK: Not set"
else
    echo "VPN IPSEC PSK: HIDDEN"
fi

bash /app/deploy_configs.sh

# Set DNS nameserver's
echo "nameserver ${DNS1}" > /etc/resolv.conf
echo "nameserver ${DNS2}" >> /etc/resolv.conf

get_pid_ipsec() {
    IPSEC_PID=$(pgrep -o -x ipsec)
}

get_pid_xl2tpd() {
    XL2TPD_PID=$(pgrep -o -x xl2tpd)
}

start_ipsec() {
    LOG_INFO "Start service 'IPSec/StrongSwan'..."
    /usr/sbin/ipsec start --nofork &
    IPSEC_PID=$!
    sleep 1
    if ! kill -0 $IPSEC_PID 2>/dev/null; then
        LOG_ERROR "IPSec/StrongSwan crashed! Restarting..."
        exit 1
    else
        LOG_INFO "IPSec/StrongSwan started successfully. PID: $IPSEC_PID"
    fi
}

check_ipsec() {
    LOG_DEBUG "Check if IPSec/StrongSwan is running..."
    if ! kill -0 $IPSEC_PID 2>/dev/null; then
        LOG_ERROR "IPSec/StrongSwan is not running. Restarting..."
        /usr/sbin/ipsec start --nofork &
        IPSEC_PID=$!
        sleep 5

        for i in {1..30}
        do
            if ! kill -0 $IPSEC_PID 2>/dev/null; then
                LOG_ERROR "Failed to restart IPSec/StrongSwan. Retrying..."
                /usr/sbin/ipsec start --nofork &
                IPSEC_PID=$!
                sleep 5
            else
                LOG_INFO "IPSec/StrongSwan restarted successfully."
                IPSEC_RESTARTED="true"
                return
            fi
        done

        if ! kill -0 $IPSEC_PID 2>/dev/null; then
            LOG_ERROR "Failed to restart IPSec/StrongSwan. Aborting..."
            exit 1
        else
            LOG_INFO "IPSec/StrongSwan restarted successfully."
            IPSEC_RESTARTED="true"
            return
        fi
    else
        LOG_DEBUG "IPSec/StrongSwan is already running."
        IPSEC_RESTARTED="false"
    fi
}

start_ipsec_vpn() {
    LOG_INFO "Start IPSec/StrongSwan VPN tunnel..."
    ipsec up myvpn
    sleep 0.5
}

stop_ipsec_vpn() {
    LOG_INFO "Stop IPSec/StrongSwan VPN tunnel..."
    ipsec down myvpn
    sleep 0.5
}

restart_ipsec_vpn() {
    LOG_INFO "Restart IPSec/StrongSwan VPN tunnel..."
    stop_ipsec_vpn
    start_ipsec_vpn
}

show_ipsec_vpn() {
    ipsec status myvpn
}


is_ipsec_vpn_active() {
    ipsec status myvpn | grep -q " ESTABLISHED "
    return $?
}

check_ipsec_vpn() {
    LOG_DEBUG "Check if IPSec/StrongSwan VPN tunnel is running..."
    if ! is_ipsec_vpn_active; then
        LOG_ERROR "IPSec/StrongSwan VPN tunnel is not running. Restarting..."
        restart_ipsec_vpn
        sleep 5

        for i in {1..30}
        do
            if ! is_ipsec_vpn_active; then
                LOG_ERROR "Failed to restart IPSec/StrongSwan VPN tunnel. Retrying..."
                restart_ipsec_vpn
                sleep 5
            else
                LOG_INFO "IPSec/StrongSwan VPN tunnel restarted successfully."
                IPSEC_TUNNEL_RESTARTED="true"
                return
            fi
        done

        if ! is_ipsec_vpn_active; then
            LOG_ERROR "Failed to restart IPSec/StrongSwan VPN tunnel. Aborting..."
            exit 1
        else
            LOG_INFO "IPSec/StrongSwan VPN tunnel restarted successfully."
            IPSEC_TUNNEL_RESTARTED="true"
            return
        fi
    else
        LOG_DEBUG "IPSec/StrongSwan VPN tunnel is already running."
        IPSEC_TUNNEL_RESTARTED="false"
    fi
}


start_xl2tpd() {
    LOG_INFO "Start service 'xl2tpd'..."
    /usr/sbin/xl2tpd -c /etc/xl2tpd/xl2tpd.conf -D &
    XL2TPD_PID=$!
    sleep 1
    if ! kill -0 $XL2TPD_PID 2>/dev/null; then
        LOG_ERROR "xl2tpd crashed! Restarting..."
        exit 1
    else
        LOG_INFO "xl2tpd started successfully. PID: $XL2TPD_PID"
    fi
}

stop_xl2tpd() {
    LOG_INFO "Stop service 'xl2tpd'..."
    get_pid_xl2tpd
    if [ -z "$XL2TPD_PID" ]; then
        LOG_ERROR "xl2tpd service is not running."
    else
        LOG_INFO "Stopping xl2tpd service (PID: $XL2TPD_PID)..."
        kill -TERM $XL2TPD_PID
        if [ $? -eq 0 ]; then
            LOG_INFO "xl2tpd service stopped successfully."
        else
            LOG_ERROR "Failed to stop xl2tpd service."
        fi
    fi
}

restart_xl2tpd(){
    LOG_INFO "Restarting service 'xl2tpd'..."
    stop_xl2tpd
    start_xl2tpd
}

check_xl2tpd() {
    LOG_DEBUG "Check if xl2tpd is running..."
    if ! kill -0 $XL2TPD_PID 2>/dev/null; then
        LOG_ERROR "xl2tpd is not running. Restarting..."
        /usr/sbin/xl2tpd -c /etc/xl2tpd/xl2tpd.conf -D &
        XL2TPD_PID=$!
        sleep 5

        for i in {1..30}
        do
            if ! kill -0 $XL2TPD_PID 2>/dev/null; then
                LOG_ERROR "Failed to restart xl2tpd. Retrying..."
                /usr/sbin/xl2tpd -c /etc/xl2tpd/xl2tpd.conf -D &
                XL2TPD_PID=$!
                sleep 5
            else
                LOG_INFO "xl2tpd restarted successfully."
                XL2TPD_RESTARTED="true"
                return
            fi
        done

        if ! kill -0 $XL2TPD_PID 2>/dev/null; then
            LOG_ERROR "Failed to restart xl2tpd. Aborting..."
            exit 1
        else
            LOG_INFO "xl2tpd restarted successfully."
            XL2TPD_RESTARTED="true"
            return
        fi
    else
        LOG_DEBUG "xl2tpd is already running."
        XL2TPD_RESTARTED="false"
    fi
}

is_ppp_if_exist() {
    LOG_DEBUG "Check ${PPP_IF} interface for exist..."
    ip link show "${PPP_IF}" > /dev/null 2>&1
    return $?
}

is_ppp_if_alive() {
    LOG_DEBUG "Check ${PPP_IF} status..."
    for host in "${KA_HOSTS[@]}"; do
        if ping -I "${PPP_IF}" -c 1 -W 1 "$host" 2>/dev/null 1>/dev/null; then
            return 0  # If at least one host is reachable, return 0
        fi
    done
    return 1
}

start_if_ppp() {
    LOG_INFO "Starting ${PPP_IF} interface..."
    $SCRIPT start
    sleep 5
}

stop_if_ppp() {
    local timeout=60
    while [ $timeout -gt 0 ]; do
        local delay=15
        LOG_INFO "Stopping ${PPP_IF} interface..."
        $SCRIPT stop
        while [ $delay -gt 0 ]; do
            if ! is_ppp_if_exist; then
                # IF ${PPP_IF} interface doesn't exist, then exit
                LOG_INFO "${PPP_IF} interface is down..."
                return 0
            else
                LOG_INFO "${PPP_IF} interface still exist..."
                sleep 1
            fi
            delay=$(( delay - 1 ))
            timeout=$(( timeout - 1 ))
        done
    done
}

restart_if_ppp() {
    LOG_INFO "Restarting ${PPP_IF} interface..."
    stop_if_ppp
    start_if_ppp
}

ctrl_c() {
  LOG_INFO "Caught SIGTERM signal!"
  stop_if_ppp
  exit 0
}
trap ctrl_c SIGTERM

# STARTUP: 1st up
echo ">>>>>>>>>>>>>>>> Start IPSec/StrongSwan service <<<<<<<<<<<<<<<<"
start_ipsec
echo ">>>>>>>>>>>>>>>> Start IPSec/StrongSwan tunnel <<<<<<<<<<<<<<<<"
start_ipsec_vpn
echo "################ IPSec/StrongSwan status ################"
show_ipsec_vpn
echo ">>>>>>>>>>>>>>>> Start XL2TPD service <<<<<<<<<<<<<<<<"
start_xl2tpd
sleep 5
echo ">>>>>>>>>>>>>>>> Start ${PPP_IF} interface <<<<<<<<<<<<<<<<"
start_if_ppp

# Polling
while sleep "${POLLING_PERIOD}"; do
    echo "HEARTBEAT by DATE: $(date)"
    check_ipsec
    if [[ "${IPSEC_RESTARTED}" == "true" ]]; then
        LOG_ERROR "IPSec/strongSwan was restarted! Need reinit IPSec tunel, XL2TPD and ${PPP_IF}..."
        stop_if_ppp
        restart_ipsec_vpn
        restart_xl2tpd
        start_if_ppp
    fi
    check_ipsec_vpn
    if [[ "${IPSEC_TUNNEL_RESTARTED}" == "true" ]]; then
        LOG_ERROR "IPSec/StrongSwan VPN tunnel was restarted! Need reinit XL2TPD and ${PPP_IF}..."
        stop_if_ppp
        restart_xl2tpd
        start_if_ppp
    fi
    check_xl2tpd
    if [[ "${XL2TPD_RESTARTED}" == "true" ]]; then
        LOG_ERROR "XL2TPD was restarted! Need reconfigure ${PPP_IF}..."
        restart_if_ppp
    elif ! is_ppp_if_exist; then
        LOG_ERROR "Interface ${PPP_IF} Doesn't exist! Need reconfigure..."
        restart_if_ppp
    elif ! is_ppp_if_alive; then
        LOG_ERROR "Interface ${PPP_IF} FAILED! Need reconfigure..."
        restart_if_ppp
    else
        LOG_DEBUG "Interface ${PPP_IF} is GOOD!"
    fi
done
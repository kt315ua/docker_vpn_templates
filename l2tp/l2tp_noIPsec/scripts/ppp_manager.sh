#!/bin/bash

PROGRAMNAME="XL2TP ENTRYPOINT INITIAL SCRIPT"

INFO="${PRINT_INFO}"
DEBUG="${PRINT_DEBUG}"
PPP_IF="${PPP_NETIF}"
POLLING_PERIOD=10
SCRIPT="/app/scripts/ppp_setup.sh"
KA_HOSTS=("8.8.8.8" "8.8.4.4" "1.1.1.1")

XL2TPD_PID=0
XL2TPD_RESTARTED="false"

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

cp -vf /app/configs/chap-secrets /etc/ppp/chap-secrets
cp -vf /app/configs/options.myvpn /etc/ppp/options.myvpn
cp -vf /app/configs/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf

sed -i "s|CHANGE_MY_HOST|${VPN_SERVER_IP}|" /etc/xl2tpd/xl2tpd.conf
sed -i "s|CHANGE_MY_NAME|${VPN_USER}|" /etc/ppp/options.myvpn
sed -i "s|CHANGE_MY_NAME|${VPN_USER}|" /etc/ppp/chap-secrets
sed -i "s|CHANGE_MY_PASS|${VPN_PASSWORD}|"   /etc/ppp/chap-secrets

# Set DNS nameserver's
echo "nameserver ${DNS1}" > /etc/resolv.conf
echo "nameserver ${DNS2}" >> /etc/resolv.conf

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
  ppp_if_down
  exit 0
}
trap ctrl_c SIGTERM

# STARTUP: 1st up
echo ">>>>>>>>>>>>>>>> Start XL2TPD service <<<<<<<<<<<<<<<<"
start_xl2tpd
sleep 5
echo ">>>>>>>>>>>>>>>> Start ${PPP_IF} interface <<<<<<<<<<<<<<<<"
start_if_ppp

# Polling
while sleep "${POLLING_PERIOD}"; do
    echo "HEARTBEAT by DATE: $(date)"
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


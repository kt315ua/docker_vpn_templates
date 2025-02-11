#!/bin/bash

NET_IF="${MAIN_NETIF}"
PPP_IF="${PPP_NETIF}"

#NETWORK_1="${SHAPE_NET1}"
#SPEEDLIMIT_1="${SHAPE_SPEED1}"

#NETWORK_2="${SHAPE_NET2}"
#SPEEDLIMIT_2="${SHAPE_SPEED2}"

VPN_SERVER_IP="${VPN_SERVER_IP}"

# Save default gateway before modifying routes
#DEFAULT_GW=$(ip route show default | awk '{print $3}')
DEFAULT_GW="${DEFAULT_GW}"

#enable_shape() {
#    tc qdisc add dev "${NET_IF}" root handle 1:0 htb default 10
#    tc class add dev "${NET_IF}" parent 1:0 classid 1:10 htb rate "${SPEEDLIMIT_1}"Mbit ceil "${SPEEDLIMIT_1}"Mbit prio 0
#    tc class add dev "${NET_IF}" parent 1:0 classid 1:5 htb rate "${SPEEDLIMIT_2}"Mbit ceil "${SPEEDLIMIT_2}"Mbit prio 1
#    tc filter add dev "${NET_IF}" parent 1:0 prio 1 handle 5 fw flowid 1:5
#
#
#    #iptables -t mangle -A PREROUTING -s "${NETWORK_1}" -j MARK --set-mark 1
#    #iptables -t mangle -A POSTROUTING -d "${NETWORK_1}" -j MARK --set-mark 1
#    iptables -t mangle -A PREROUTING -i "${NET_IF}" -j MARK --set-mark 1
#    iptables -t mangle -A POSTROUTING -o "${NET_IF}" -j MARK --set-mark 1
#    iptables -t mangle -A PREROUTING -s "${NETWORK_2}" -j MARK --set-mark 5
#    iptables -t mangle -A POSTROUTING -d "${NETWORK_2}" -j MARK --set-mark 5
#}

#disable_shape() {
#    iptables -t mangle -D PREROUTING -s "${NETWORK_2}" -j MARK --set-mark 5
#    iptables -t mangle -D POSTROUTING -d "${NETWORK_2}" -j MARK --set-mark 5
#    #iptables -t mangle -D PREROUTING -s "${NETWORK_1}" -j MARK --set-mark 1
#    #iptables -t mangle -D POSTROUTING -d "${NETWORK_1}" -j MARK --set-mark 1
#    iptables -t mangle -D PREROUTING -i "${NET_IF}" -j MARK --set-mark 1
#    iptables -t mangle -D POSTROUTING -o "${NET_IF}" -j MARK --set-mark 1
#
#    tc filter del dev "${NET_IF}" parent 1:0
#    tc class del dev "${NET_IF}" parent 1:1 classid 1:5
#    tc class del dev "${NET_IF}" parent 1:0 classid 1:10
#    tc qdisc del dev "${NET_IF}" root
#}


enable_nat_w_routing() {
    echo "Setting up NAT and forwarding..."
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F

    # Enable NAT on PPP_IF
    iptables -t nat -A POSTROUTING -o "${PPP_IF}" -j MASQUERADE

    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow new incoming connections **except from PPP_IF**
    iptables -A INPUT -m state --state NEW -i !"${PPP_IF}" -j ACCEPT

    # Allow VPN traffic
    iptables -A INPUT -i "${PPP_IF}" -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -j DROP -i "${PPP_IF}"   #only if the first two are succesful

    # Reject forwarding between VPN clients
    iptables -A FORWARD -i "${PPP_IF}" -o "${PPP_IF}" -j REJECT

    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

reset_nat_w_routing(){
    # Disable IP forwarding
    #echo 0 > /proc/sys/net/ipv4/ip_forward

    echo "Resetting NAT and forwarding..."
    iptables -t nat -D POSTROUTING -o "${PPP_IF}" -j MASQUERADE 2>/dev/null
    iptables -D INPUT -i "${PPP_IF}" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    iptables -D FORWARD -i "${PPP_IF}" -o "${PPP_IF}" -j REJECT 2>/dev/null

    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
}




start() {
    echo "Starting VPN connection..."
    ip route add "${VPN_SERVER_IP}" via "${DEFAULT_GW}"
    ip route add 8.8.8.8 via "${DEFAULT_GW}"
    ip route add 8.8.4.4 via "${DEFAULT_GW}"
    
    echo "Removing default route..."
    #ip route del default || echo "No default route to remove."
    
    echo "Connecting to VPN..."
    xl2tpd-control connect-lac myvpn
    sleep 5  # Wait for PPP to establish

    if ip link show "${PPP_IF}" up | grep -q "UP" > /dev/null 2>&1; then
        echo "VPN connected. Setting default route..."
        #ip route add default dev "${PPP_IF}"
        enable_nat_w_routing
        #enable_shape
    else
        echo "Error: PPP interface not available."
        stop
        exit 1
    fi
    echo "VPN connection started!"
}


stop() {
    echo "Stopping VPN connection..."
    #disable_shape
    reset_nat_w_routing

    echo "Removing VPN default route..."
    ip route del default || echo "No default route to remove."

    echo "Restoring default gateway..."
    ip route add default via "${DEFAULT_GW}" dev "${NET_IF}"

    echo "Removing temporary routes..."
    ip route del "${VPN_SERVER_IP}" via "${DEFAULT_GW}"
    ip route del 8.8.8.8 via "${DEFAULT_GW}"
    ip route del 8.8.4.4 via "${DEFAULT_GW}"

    echo "Terminate VPN..."
    xl2tpd-control disconnect-lac myvpn
    if ip link show "${PPP_IF}" > /dev/null 2>&1; then
        ip link set "${PPP_IF}" down
        ip link delete "${PPP_IF}"
    fi
    echo "VPN connection stopped!"
}


case "$1" in
    start)  start;;
    stop)   stop;;
    *)      exit 0;;
esac

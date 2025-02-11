#!/bin/bash
# https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients.md

setup_strongswan() {
cat > /etc/ipsec.conf <<EOF
# ipsec.conf - strongSwan IPsec configuration file

conn myvpn
  auto=add
  keyexchange=ikev1
  authby=secret
  type=transport
  left=%defaultroute
  leftprotoport=17/1701
  rightprotoport=17/1701
  right=$VPN_SERVER_IP
  ike=aes128-sha1-modp2048
  esp=aes128-sha1
EOF

cat > /etc/ipsec.secrets <<EOF
: PSK "$VPN_IPSEC_PSK"
EOF

    chmod 600 /etc/ipsec.secrets
}

setup_xl2tpd() {
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[lac myvpn]
lns = $VPN_SERVER_IP
ppp debug = yes
pppoptfile = /etc/ppp/options.myvpn
length bit = yes
EOF

cat > /etc/ppp/options.myvpn <<EOF
lcp-echo-interval 30
lcp-echo-failure 4
ipcp-accept-local
ipcp-accept-remote
refuse-pap
refuse-eap
refuse-chap
refuse-mschap
require-mschap-v2
#require-mppe
require-mppe-128
noccp
noauth
mtu 1450
mru 1450
noipdefault
#nodefaultroute
defaultroute
replacedefaultroute
usepeerdns
connect-delay 5000
noauth
name "$VPN_USER"
password "$VPN_PASSWORD"
EOF

chmod 600 /etc/ppp/options.myvpn

}

if [[ ! -f "/app/deployed" ]]; then
    echo "Services configure required"
    # SETUP IPSEC/strongSwan is PSK defined
    if [[ -n "$VPN_IPSEC_PSK" ]]; then
        setup_strongswan
    fi

    setup_xl2tpd
    touch /app/deployed
else
    echo "Services already configured"
fi


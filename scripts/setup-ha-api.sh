#!/usr/bin/env bash
set -euo pipefail

NODE_NAME="$(hostname)"
VIP="192.168.56.100"
INTERFACE="eth1"

CP1_IP="192.168.56.10"
CP2_IP="192.168.56.11"
CP3_IP="192.168.56.12"

case "${NODE_NAME}" in
  kl-cp-1)
    NODE_IP="${CP1_IP}"
    PRIORITY="150"
    PEERS=("${CP2_IP}" "${CP3_IP}")
    ;;
  kl-cp-2)
    NODE_IP="${CP2_IP}"
    PRIORITY="140"
    PEERS=("${CP1_IP}" "${CP3_IP}")
    ;;
  kl-cp-3)
    NODE_IP="${CP3_IP}"
    PRIORITY="130"
    PEERS=("${CP1_IP}" "${CP2_IP}")
    ;;
  *)
    echo "ERROR: ${NODE_NAME} is not a control-plane node"
    exit 1
    ;;
esac

echo "==> Configuring HA API on ${NODE_NAME} (${NODE_IP})"

sudo apt-get update -y
sudo apt-get install -y haproxy keepalived curl arping

echo "==> Applying sysctl settings for stable VIP behaviour"

cat <<SYSCTL | sudo tee /etc/sysctl.d/99-k8s-ha-api.conf >/dev/null
net.ipv4.ip_nonlocal_bind = 1
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.default.arp_ignore = 1
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.${INTERFACE}.arp_ignore = 1
net.ipv4.conf.${INTERFACE}.arp_announce = 2
SYSCTL

sudo sysctl --system >/dev/null

echo "==> Writing HAProxy config"

sudo cp /etc/haproxy/haproxy.cfg "/etc/haproxy/haproxy.cfg.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

cat <<HAPROXY | sudo tee /etc/haproxy/haproxy.cfg >/dev/null
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 10s
    timeout client 1m
    timeout server 1m

frontend kubernetes_api
    bind *:8443
    mode tcp
    default_backend kubernetes_control_planes

backend kubernetes_control_planes
    mode tcp
    balance roundrobin
    option tcp-check
    default-server inter 2s fall 3 rise 2
    server kl-cp-1 ${CP1_IP}:6443 check
    server kl-cp-2 ${CP2_IP}:6443 check
    server kl-cp-3 ${CP3_IP}:6443 check
HAPROXY

sudo haproxy -c -f /etc/haproxy/haproxy.cfg


echo "==> Installing VIP gratuitous ARP notify script"

cat <<GARPSCRIPT | sudo tee /usr/local/sbin/announce-vip-garp.sh >/dev/null
#!/usr/bin/env bash
set -euo pipefail

VIP="192.168.56.100"
INTERFACE="eth1"

command -v arping >/dev/null 2>&1 || exit 0

arping -U -I "\${INTERFACE}" -c 5 "\${VIP}" || true
arping -A -I "\${INTERFACE}" -c 5 "\${VIP}" || true
GARPSCRIPT

sudo chmod +x /usr/local/sbin/announce-vip-garp.sh

echo "==> Writing Keepalived config"

sudo cp /etc/keepalived/keepalived.conf "/etc/keepalived/keepalived.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

cat <<KEEPALIVED | sudo tee /etc/keepalived/keepalived.conf >/dev/null
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/pidof haproxy"
    interval 2
    weight -60
    fall 2
    rise 2
}

vrrp_instance VI_K8S_API {
    state BACKUP
    interface ${INTERFACE}
    virtual_router_id 56
    priority ${PRIORITY}
    advert_int 1
    nopreempt

    authentication {
        auth_type PASS
        auth_pass k8s-ha
    }

    unicast_src_ip ${NODE_IP}
    unicast_peer {
        ${PEERS[0]}
        ${PEERS[1]}
    }

    virtual_ipaddress {
        ${VIP}/24 dev ${INTERFACE}
    }

    track_script {
        chk_haproxy
    }

    garp_master_delay 1
    garp_master_repeat 5
    garp_master_refresh 10
    garp_master_refresh_repeat 2

    notify_master "/usr/local/sbin/announce-vip-garp.sh"
    notify_backup "/usr/local/sbin/announce-vip-garp.sh"
    notify_fault "/usr/local/sbin/announce-vip-garp.sh"
}
KEEPALIVED

echo "==> Restarting services"

sudo systemctl enable haproxy >/dev/null
sudo systemctl restart haproxy

sudo systemctl enable keepalived >/dev/null
sudo systemctl restart keepalived

echo "==> Verifying HAProxy listener"
sudo ss -lntp | grep ':8443' || {
  echo "ERROR: HAProxy is not listening on 8443"
  exit 1
}

echo "==> Current VIP ownership on ${NODE_NAME}"
ip -4 addr show "${INTERFACE}" | grep "${VIP}" || true

echo "==> Local VIP health check"
curl -k --connect-timeout 3 "https://${VIP}:8443/healthz" || true

echo "==> Done: HA API configured on ${NODE_NAME}"


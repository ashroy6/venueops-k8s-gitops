#!/usr/bin/env bash
set -euo pipefail

VIP="192.168.56.100"
INTERFACE="eth1"

command -v arping >/dev/null 2>&1 || exit 0

# Gratuitous ARP announcement: tell the LAN who owns the VIP.
arping -U -I "${INTERFACE}" -c 5 "${VIP}" || true
arping -A -I "${INTERFACE}" -c 5 "${VIP}" || true

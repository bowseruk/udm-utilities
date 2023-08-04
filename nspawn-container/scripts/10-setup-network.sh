#!/bin/bash
# This script will create a macvlan bridge interface to allow communication
# between container networks and host networks.
# An interface called brX.mac will be created, where X = $VLAN configured below.
# The interface will be assigned an IP of $IPV4_GW, and $IPV6_GW configured below.
# Routes will be added for the container IP $IPV4 and $IPV6. 
# Script is based on 10-dns.sh from unifios-utilities.

## CONFIGURATION VARIABLES

# VLAN ID network container will be on. This VLAN has to first be configured as a 
# network in Unifi Network settings with a unique IP/subnet. Do not use the same 
# IP in the unifi network settings as you will use below for IPV4_IP or IPV4_GW.
VLAN=5

# IP addresses of container.
IPV4_IP="10.0.5.3"
# Gateway IP address of macvlan interface. IP above should be in this subnet.
IPV4_GW="10.0.5.1/24"

# IPv6 container and gateway addresses. These can be empty if not using IPv6.
# Preferably generate your own ULA instead of using the default one below.
# A public IPv6 prefix based on your ISP's prefix can be used too, but any 
# prefix changes for dynamic IPv6 prefixes have to be modified manually. 
IPV6_IP="fd62:89a2:fda9:e23::3"
IPV6_GW="fd62:89a2:fda9:e23::1/64"

## END OF CONFIGURATION

# set VLAN bridge promiscuous
ip link set "br${VLAN}" promisc on

# create macvlan bridge and add IPv4 IP
ip link add "br${VLAN}.mac" link "br${VLAN}" type macvlan mode bridge
ip addr add "${IPV4_GW}" dev "br${VLAN}.mac" noprefixroute

# (optional) add IPv6 IP to VLAN bridge macvlan bridge
if [ -n "${IPV6_GW}" ]; then
  ip -6 addr add "${IPV6_GW}" dev "br${VLAN}.mac" noprefixroute
fi

# set macvlan bridge promiscuous and bring it up
ip link set "br${VLAN}.mac" promisc on
ip link set "br${VLAN}.mac" up

# add IPv4 route to container
ip route add "${IPV4_IP}/32" dev "br${VLAN}.mac"

# (optional) add IPv6 route to container
if [ -n "${IPV6_IP}" ]; then
  ip -6 route add "${IPV6_IP}/128" dev "br${VLAN}.mac"
fi

# Make DNSMasq listen to the container network for split horizon or conditional forwarding
if ! grep -qxF "interface=br${VLAN}.mac" /run/dnsmasq.conf.d/custom.conf; then
  echo "interface=br${VLAN}.mac" >>/run/dnsmasq.conf.d/custom.conf
  kill -9 "$(cat /run/dnsmasq.pid)"
fi

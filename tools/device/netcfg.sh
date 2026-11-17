#!/bin/sh
# Configure the Linux side of the Wi-Fi interface.
# The vendor path (blctld -> sta.sh on IP_UPDATE) is unreliable, and without it
# the netdev has no address and no route, so every TCP connect fails with
# "Network is unreachable" even though the chip itself is online.
sleep 10
echo "=== NETCFG start $(cat /proc/uptime)" > /dev/console
i=0
while [ $i -lt 20 ]; do
  [ -d /sys/class/net/bleth0 ] && break
  sleep 3; i=$((i+1))
done
ifconfig bleth0 192.0.2.20 netmask 255.255.255.0 up
route del default gw 192.0.2.1 2>/dev/null
route add default gw 192.0.2.1
echo "=== NETCFG result" > /dev/console
ifconfig bleth0 > /dev/console 2>&1
route -n > /dev/console 2>&1
echo "=== NETCFG end" > /dev/console

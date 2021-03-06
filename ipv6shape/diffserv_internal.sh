#!/bin/sh

# Simple internal shaper for wireless traffic
# Make dhcp, nd, etc, work well
# Make DNS fast
# Prioritize syn and synack traffic to make starting new connections faster

# This is the external setup

# iptables -t mangle -N Default >&- 2>&-                                                                                                                                                       
# iptables -t mangle -N Default_ct >&- 2>&-                                                                                                                                                    
# iptables -t mangle -A Default_ct -m mark --mark 0 -m tcp -p tcp -m multiport --ports 22,53 -j MARK --set-mark 1
# iptables -t mangle -A Default_ct -m mark --mark 0 -p udp -m udp -m multiport --ports 22,53 -j MARK --set-mark 1
# iptables -t mangle -A Default_ct -m mark --mark 0 -p tcp -m tcp -m multiport --ports 20,21,25,80,110,443,993,995 -j MARK --set-mark 3
# iptables -t mangle -A Default_ct -m mark --mark 0 -m tcp -p tcp -m multiport --ports 5190 -j MARK --set-mark 2
# iptables -t mangle -A Default_ct -m mark --mark 0 -p udp -m udp -m multiport --ports 5190 -j MARK --set-mark 2
# iptables -t mangle -A Default_ct -j CONNMARK --save-mark
# iptables -t mangle -A Default -j CONNMARK --restore-mark
# iptables -t mangle -A Default -m mark --mark 0 -j Default_ct
# iptables -t mangle -A Default -m mark --mark 1 -m length --length 400: -j MARK --set-mark 0
# iptables -t mangle -A Default -m mark --mark 2 -m length --length 800: -j MARK --set-mark 0
# iptables -t mangle -A Default -m mark --mark 0 -p udp -m length --length :500 -j MARK --set-mark 2
# iptables -t mangle -A Default -p icmp -j MARK --set-mark 1
# iptables -t mangle -A Default -m mark --mark 0 -m tcp -p tcp --sport 1024:65535 --dport 1024:65535 -j MARK --set-mark 4
# iptables -t mangle -A Default -m mark --mark 0 -p udp -m udp --sport 1024:65535 --dport 1024:65535 -j MARK --set-mark 4
# iptables -t mangle -A Default -p tcp -m length --length :128 -m mark ! --mark 4 -m tcp --tcp-flags ALL SYN -j MARK --set-mark 1
# iptables -t mangle -A Default -p tcp -m length --length :128 -m mark ! --mark 4 -m tcp --tcp-flags ALL ACK -j MARK --set-mark 1
# iptables -t mangle -A OUTPUT -o eth1 -j Default
# iptables -t mangle -A FORWARD -o eth1 -j Default   

#    This is the relevant table from the RFC

#    |===============+=========+=============+==========================|
#    |Network Control|  CS6    |   110000    | Network routing          |
#    |---------------+---------+-------------+--------------------------|
#    | Telephony     |   EF    |   101110    | IP Telephony bearer      |
#    |---------------+---------+-------------+--------------------------|
#    |  Signaling    |  CS5    |   101000    | IP Telephony signaling   |
#    |---------------+---------+-------------+--------------------------|
#    | Multimedia    |AF41,AF42|100010,100100|   H.323/V2 video         |
#    | Conferencing  |  AF43   |   100110    |  conferencing (adaptive) |
#    |---------------+---------+-------------+--------------------------|
#    |  Real-Time    |  CS4    |   100000    | Video conferencing and   |
#    |  Interactive  |         |             | Interactive gaming       |
#    |---------------+---------+-------------+--------------------------|
#    | Multimedia    |AF31,AF32|011010,011100| Streaming video and      |
#    | Streaming     |  AF33   |   011110    |   audio on demand        |
#    |---------------+---------+-------------+--------------------------|
#    |Broadcast Video|  CS3    |   011000    |Broadcast TV & live events|
#    |---------------+---------+-------------+--------------------------|
#    | Low-Latency   |AF21,AF22|010010,010100|Client/server transactions|
#    |   Data        |  AF23   |   010110    | Web-based ordering       |
#    |---------------+---------+-------------+--------------------------|
#    |     OAM       |  CS2    |   010000    |         OAM&P            |
#    |---------------+---------+-------------+--------------------------|
#    |High-Throughput|AF11,AF12|001010,001100|  Store and forward       |
#    |    Data       |  AF13   |   001110    |     applications         |
#    |---------------+---------+-------------+--------------------------|
#    |    Standard   | DF (CS0)|   000000    | Undifferentiated         |
#    |               |         |             | applications             |
#    |---------------+---------+-------------+--------------------------|
#    | Low-Priority  |  CS1    |   001000    | Any flow that has no BW  |
#    |     Data      |         |             | assurance                |
#     ------------------------------------------------------------------


# 2001:db8::/32 Block entirely
# 2001::/32 Teredo
# fec0::/10 Deprecated

. ./diffserv.cfg

do_qos() {
local iptables=$1
$iptables -t mangle -X Mice
$iptables -t mangle -N Mice
$iptables -t mangle -F Mice

$iptables -t mangle -X Wireless 
$iptables -t mangle -N Wireless
$iptables -t mangle -F Wireless 

# not sure if this matches dhcp actually
# And we should probably have different classes for multicast vs non multicast
$iptables -t mangle -A Mice -p udp -m multiport --ports 53,67,68,123 -j DSCP --set-dscp-class AF11 -m comment --comment 'DNS, DHCP, NTP, are very important'
$iptables -t mangle -A Mice -p udp -m multiport --ports $SIGNALPORTS -j DSCP --set-dscp-class CS5 -m comment --comment 'VOIP Signalling'
$iptables -t mangle -A Mice -p udp -m multiport --ports $VOIPPORTS -j DSCP --set-dscp-class EF -m comment --comment 'VOIP'
$iptables -t mangle -A Mice -p udp -m multiport --ports $GAMINGPORTS -j DSCP --set-dscp-class AF11 -m comment --comment 'Gaming'
$iptables -t mangle -A Mice -p udp -m multiport --ports $MONITORPORTS -j DSCP --set-dscp-class CS4 -m comment --comment 'SNMP'

if [ "$iptables" = "ip6tables" ]
then
# addrtype for ipv6 isn't compiled in by default
$iptables -t mangle -A Mice -s fe80::/10 -j DSCP --set-dscp-class AF12 -m comment --comment 'Link Local sorely needed'
$iptables -t mangle -A Mice -d ff00::/12 -j DSCP --set-dscp-class AF43 -m comment --comment 'Multicast far less needed'
$iptables -t mangle -A Mice -s fe80::/10 -d ff00::/12 -j DSCP --set-dscp-class AF12 -m comment --comment 'But link local multicast is good'
# As is neighbor discovery, etc, but I haven't parsed http://tools.ietf.org/html/rfc4861 well yet
# $iptables -t mangle -A Mice -s fe80::/10 -d ff00::/12 -j DSCP --set-dscp-class AF12 -m comment --comment 'ND working is good too'

else
$iptables -t mangle -A Mice -m addrtype --dst-type MULTICAST -j DSCP --set-dscp-class AF22 -m comment --comment 'Multicast'
fi

$iptables -t mangle -A Wireless ! -p tcp -g Mice
# SSH rule needs to distinguish between interactive and bulk sessions
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $INTERACTIVEPORTS -j DSCP --set-dscp-class AF21 -m comment --comment 'SSH'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $XWINPORTS -j DSCP --set-dscp-class AF11 -m comment --comment 'Xwindows'

# Probably incorrect for gaming, which uses udp usually
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $GAMINGPORTS -j DSCP --set-dscp-class AF11 -m comment --comment 'Gaming'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $ROUTINGPORTS -j DSCP --set-dscp-class AF11 -m comment --comment 'Routing'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $BROWSINGPORTS -j DSCP --set-dscp-class AF32 -m comment --comment 'BROWSING'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $PROXYPORTS -j DSCP --set-dscp-class AF21 -m comment --comment 'Web proxies better for browsing'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $SCMPORTS -j DSCP --set-dscp-class AF22 -m comment --comment 'SCM'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $FILEPORTS -j DSCP --set-dscp-class AF22 -m comment --comment 'Normal File sharing'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $MAILPORTS -j DSCP --set-dscp-class AF32 -m comment --comment 'MAIL clients'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $BACKUPPORTS -j DSCP --set-dscp-class CS1 -m comment --comment 'Backups'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $BULKPORTS -j DSCP --set-dscp-class CS2 -m comment --comment 'BULK'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $TESTPORTS -j DSCP --set-dscp-class CS3 -m comment --comment 'Bandwidth Tests'
$iptables -t mangle -A Wireless -p tcp -m tcp -m multiport --ports $P2PPORTS -j DSCP --set-dscp-class CS4 -m comment --comment 'P2P'

# should probably make these rules separate on a per class basis

$iptables -t mangle -A Wireless -p tcp -m tcp --syn -j DSCP --set-dscp-class AF12 -m comment --comment 'Expedite new connections' 
$iptables -t mangle -A Wireless -p tcp -m tcp --tcp-flags ALL SYN,ACK -j DSCP --set-dscp-class AF12 -m comment --comment 'Expedite new connection ack' 

# FIXME: Maybe make ECN enabled streams mildly higher priority. This just counts the number of ECN and non-ECN streams

$iptables -t mangle -A Wireless -p tcp -m tcp --tcp-flags ALL SYN,ACK -m ecn --ecn-tcp-ece -m recent --name ecn_enabled --set -m comment --comment 'ECN enabled streams' 
$iptables -t mangle -A Wireless -p tcp -m tcp --tcp-flags ALL SYN,ACK -m ecn ! --ecn-tcp-ece -m recent --name ecn_disabled --set -m comment --comment 'ECN disabled streams' 

# --ecn-tcp-remove can be used for blackholes

# I thought I could do this in a prerouting rule, but it didn't work
$iptables -t mangle -F POSTROUTING
$iptables -t mangle -A POSTROUTING -j Wireless

}


do_qos iptables
do_qos ip6tables
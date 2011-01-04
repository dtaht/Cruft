#!/bin/bash
# encoding: UTF-8
# 
# Maciej Bliziński, http://automatthias.wordpress.com/
#
# References:
# http://www.voip-info.org/wiki/view/QoS+Linux+with+HFSC
# http://www.nslu2-linux.org/wiki/HowTo/EnableTrafficShaping
# http://www.cs.cmu.edu/~hzhang/HFSC/main.html

# Specify parameters of your xDSL. Give values slightly lower than the
# nominal ones. For example, my line is 256/128, so I specify 240/100.

# action dev downlink uplink

# Uplink and downlink speeds
DOWNLINK=$3
UPLINK=$4

# Device that connects you to the Internet
DEV=$2

# Action to be performed
ACTION=$1

PRIOIPS=

# IP addresses of the VoIP phones,
# if none, set VOIPIPS=""
VOIPIPS=""

# Interactive class: SSH Terminal, DNS and gaming (Quake)
INTERACTIVEPORTS="22,222,23,53,3389,5900"

# VoIP telephony
VOIPPORTS="5060:5100,10000:11000,5000:5059,8000:8016,5004,1720,1731,4569"

# WWW, jabber and IRC
BROWSINGPORTS="80,443,8080"

BULKPORTS="25,873" 
# The lowest priority traffic: eDonkey, Bittorrent, rsync, etc.
P2PPORTS="110,21,143,445,137:139,4662,4664,6881:6999"

########################################################################
# Configuration ends here
########################################################################

export iptables=ip6tables

CLASSES="C_ULT C_INT C_ACK C_TLK C_BRW C_DEF C_BLK C_UNC C_P2P"
CLASSID=":20   :30   :40   :50   :60   :70   :80   :90   :95"

setclassbyport() {
    port=$1
    CLASS=$2
    $iptables -t mangle -A SHAPER_U -p udp -m multiport --ports $port -g $CLASS
    $iptables -t mangle -A SHAPER_T -p tcp -m multiport --ports $port -g $CLASS
}


function check_device() {
	if [ -z "$DEV" ] ; then
		echo "$0: stop requires a device, aborting."
		exit -1
	fi
}

case "$ACTION" in
status)
	check_device

	echo "[qdisc]"
        tc -s qdisc show dev $DEV

        echo ""
        echo "[class]"
        tc -s class show dev $DEV

        echo ""
        echo "[filter]"
        tc -s filter show dev $DEV

        echo ""
        echo "[$iptables]"
        $iptables -t mangle -L SHAPER -v -x 2> /dev/null
        exit
	;;

stop)
	check_device
        # Reset everything to a known state (cleared)
        tc qdisc del dev $DEV root    > /dev/null 2>&1
        tc qdisc del dev $DEV ingress > /dev/null 2>&1

        # Flush and delete tables
        $iptables -t mangle --delete POSTROUTING -o $DEV -j SHAPER > /dev/null 2>&1
        $iptables -t mangle --flush        SHAPER 2> /dev/null > /dev/null
        $iptables -t mangle --delete-chain SHAPER 2> /dev/null > /dev/null
        $iptables -t mangle --flush        SHAPER_T 2> /dev/null > /dev/null
        $iptables -t mangle --delete-chain SHAPER_T 2> /dev/null > /dev/null
        $iptables -t mangle --flush        SHAPER_I 2> /dev/null > /dev/null
        $iptables -t mangle --delete-chain SHAPER_I 2> /dev/null > /dev/null
        $iptables -t mangle --flush        SHAPER_U 2> /dev/null > /dev/null
        $iptables -t mangle --delete-chain SHAPER_U 2> /dev/null > /dev/null

	for i in $CLASSES
	do
	    $iptables -t mangle --flush $i 2> /dev/null > /dev/null
	    $iptables -t mangle --delete-chain $i 2> /dev/null > /dev/null
	done

        echo "Shaping removed on $DEV."
        exit
	;;
start)
	check_device
	if [ -z "$DOWNLINK" ] ; then
		echo "$0: start requires a downlink speed, aborting."
		exit -1
	fi
	if [ -z "$UPLINK" ] ; then
		echo "$0: start requires an uplink speed, aborting."
		exit -1
	fi

	# Traffic classes:
	# 1:10 Pentultimate Priority (ntp)
        # 1:20 Interactive (SSH, DNS, Quake)
	# 1:25 (ACK)
        # 1:30 Low latency (VoIP)
        # 1:40 Browsing (HTTP, HTTPs)
        # 1:50 Default
	# 1:60 Bulk Services (smtp, rsync)
	# 1:80 Unclassifiable
        # 1:90 Low priority (p2p, pop3, etc)

        # add HFSC root qdisc
        tc qdisc add dev $DEV root handle 1: hfsc default 5

        # add main rate limit class
        tc class add dev $DEV parent 1: classid 1:10 hfsc \
                sc rate ${UPLINK}kbit ul rate ${UPLINK}kbit

        # Interactive traffic: guarantee realtime full uplink for 50ms, then
        # 1/100th of the uplink

        tc class add dev $DEV parent 1:1  classid 1:20 hfsc \
                rt m1   ${UPLINK}kbit d  10ms m2 $(($UPLINK/100))kbit \
                ls m1   ${UPLINK}kbit d  10ms m2 $(($UPLINK/100))kbit \
                ul rate ${UPLINK}kbit

	# For TCP ACKS

        tc class add dev $DEV parent 1:1  classid 1:30 hfsc \
                rt m1   ${UPLINK}kbit d  50ms m2 $((5*$UPLINK/10))kbit \
                ls m1   ${UPLINK}kbit d  50ms m2 $((7*$UPLINK/10))kbit \
                ul rate ${UPLINK}kbit

        # VoIP: guarantee full uplink for 200ms, then 1/10
        tc class add dev $DEV parent 1:1  classid 1:40 hfsc \
                sc m1 ${UPLINK}kbit d 20ms m2 $((1*$UPLINK/10))kbit \
                ul rate ${UPLINK}kbit

        # Browsing: Don't guarantee anything for the first second, then
        # guarantee 1/10

        tc class add dev $DEV parent 1:1  classid 1:50 hfsc \
                sc m1         0 d    1s m2 $((1*$UPLINK/10))kbit \
                ul rate ${UPLINK}kbit

        # Default traffic: don't guarantee anything for the first two seconds,
        # then guarantee 1/20

        tc class add dev $DEV parent 1:1  classid 1:60 hfsc \
                sc m1         0 d    1s m2 $((1*$UPLINK/20))kbit \
                ul rate ${UPLINK}kbit

        # Bulk traffic: don't guarantee anything for the first two seconds,
        # then guarantee 1/20

        tc class add dev $DEV parent 1:1  classid 1:70 hfsc \
                sc m1         0 d    2s m2 $((1*$UPLINK/20))kbit \
                ul rate ${UPLINK}kbit

 
        # Default traffic: don't guarantee anything for the first 10 seconds,
        # then guarantee 1/20

        tc class add dev $DEV parent 1:1  classid 1:80 hfsc \
                sc m1         0 d   10s m2 $((1*$UPLINK/20))kbit \
                ul rate ${UPLINK}kbit

        # add SHAPER chain to the mangle table in $iptables

        $iptables -t mangle --new-chain SHAPER
        $iptables -t mangle --new-chain SHAPER_T
        $iptables -t mangle --new-chain SHAPER_U
        $iptables -t mangle --new-chain SHAPER_I
	
	C=$CLASSIDS
	for i in $CLASSES
	do
	    $iptables -t mangle --new-chain $i
	    A=shift $C
	    $iptables -t mangle -A $i -j CLASSIFY 1:$(A)
	done

	$iptables -t mangle -A SHAPER -p tcp -j SHAPER_T
	$iptables -t mangle -A SHAPER -p udp -j SHAPER_U
	$iptables -t mangle -A SHAPER -p icmp -j SHAPER_I


        # To speed up downloads while an upload is going on, put short ACK
        # packets in the interactive class:
	# Note that a SHORT ACK packet is different in ipv6
	# FIXME

        $iptables -t mangle -A SHAPER_T \
                -p tcp \
                -m tcp --tcp-flags FIN,SYN,RST,ACK ACK \
                -g C_INT

        # put large (512+) icmp packets in browsing category
        $iptables -t mangle -A SHAPER_I \
                -p icmp \
                -m length --length 512: \
                -g C_BRW

        # ICMP (ip protocol 1) in the interactive class
        $iptables -t mangle -A SHAPER_I \
                -p icmp  \
                -m length --length :512 \
                -g C_INT

        for port in $INTERACTIVEPORTS;  do setclassbyport $port C_INT; done
#       for port in $ACKS;              do setclassbyport $port C_ACK; done
        for port in $VOIPPORTS;         do setclassbyport $port C_TLK; done
        for port in $BROWSINGPORTS;     do setclassbyport $port C_BRW; done
        for port in $BULKPORTS;         do setclassbyport $port C_BLK; done
        for port in $P2PPORTS;          do setclassbyport $port C_P2P; done

        for VOIP in $VOIPIPS
        do
                $iptables -t mangle -A SHAPER_U --src $VOIP -g C_TALK
                $iptables -t mangle -A SHAPER_U --dst $VOIP -g C_TALK
        done


# enable the shaper

        $iptables -t mangle --insert POSTROUTING -o $DEV -j SHAPER

        # Try to control the incoming traffic as well.
        # Set up ingress qdisc
        tc qdisc add dev $DEV handle ffff: ingress

        # Filter everything that is coming in too fast
        # It's mostly HTTP downloads that keep jamming the downlink, so try to restrict
        # them to 6/10 of the downlink.
        tc filter add dev $DEV parent ffff: protocol ip prio 50 \
           u32 match ip src 0.0.0.0/0 \
           match ip protocol 6 0xff \
           match ip sport 80 0xffff \
           police rate $((6*${DOWNLINK}/10))kbit \
           burst 10k drop flowid :1

        tc filter add dev $DEV parent ffff: protocol ip prio 50 \
           u32 match ip src 0.0.0.0/0 \
           match ip protocol 6 0xff \
           match ip dport 80 0xffff \
           police rate $((6*${DOWNLINK}/10))kbit \
           burst 10k drop flowid :1
	;;
*)
        echo "$0 [ACTION] [device]"
        echo "ACTION := { start [downlink] [uplink] | stop | status }"
        exit
	;;
esac


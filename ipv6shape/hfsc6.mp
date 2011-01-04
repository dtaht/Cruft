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


# ARGS: action dev [6 4]

. shaper.cfg

# Uplink and downlink speeds

# Device that connects you to the Internet
DEV=$2

# Action to be performed
ACTION=$1

export iptables=ip6tables


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
        (
        # Flush and delete tables
        $iptables -t mangle --delete POSTROUTING -o $DEV -j SHAPER 
        $iptables -t mangle --flush        SHAPER 
        $iptables -t mangle --delete-chain SHAPER 
        $iptables -t mangle --flush        SHAPER_T 
        $iptables -t mangle --delete-chain SHAPER_T 
        $iptables -t mangle --flush        SHAPER_I 
        $iptables -t mangle --delete-chain SHAPER_I 
        $iptables -t mangle --flush        SHAPER_U 
        $iptables -t mangle --delete-chain SHAPER_U 

	for i in $CLASSES
	do
	    $iptables -t mangle --flush $i 2> /dev/null > /dev/null
	    $iptables -t mangle --delete-chain $i 2> /dev/null > /dev/null
	done
	) > /dev/null 2>&1
        echo "Shaping chains removed on $DEV."
        exit
	;;
start)
        # add SHAPER chain to the mangle table in $iptables

        $iptables -t mangle --new-chain SHAPER
        $iptables -t mangle --new-chain SHAPER_T
        $iptables -t mangle --new-chain SHAPER_U
        $iptables -t mangle --new-chain SHAPER_I

	gen_chains $CLASSIDS

	$iptables -t mangle -A SHAPER -p tcp -j SHAPER_T
	$iptables -t mangle -A SHAPER -p udp -j SHAPER_U
	$iptables -t mangle -A SHAPER -p icmp -j SHAPER_I


        # To speed up downloads while an upload is going on, put short ACK
        # packets in the interactive class for packets we care about
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
                $iptables -t mangle -A SHAPER_U --src $VOIP -g C_TLK
                $iptables -t mangle -A SHAPER_U --dst $VOIP -g C_TLK
        done

# enable the shaper chains

        $iptables -t mangle --insert POSTROUTING -o $DEV -j SHAPER
;;

*)
        echo "$0 [ACTION] [device]"
        echo "ACTION := { start | stop | status }"
        exit
	;;
esac


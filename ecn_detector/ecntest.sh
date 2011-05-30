#!/bin/bash

export SYSVAL=net.ipv4.tcp_ecn
export TEST_SITE=testecn.bufferbloat.net
export TEST_FILE=ecn_test_data.mp3
export TEST_MD5_FILE=ecn_test_data.md5
export TEST_MD5=
export WGETOPTS="wget --connect-timeout=10 --dns-timeout=4 --tries 2 "
export HAVE_IPV6=0
export ECN_ENABLED=0 # value of ecn at test start
# FIXME: test ipv4 and 6 explicitly

function ecn_enabled_p {
ECN_ENABLED=`sysctl -a 2> /dev/null | grep $SYSVAL | awk '{ print $3; }'`
return $ECN_ENABLED
}

function get_default_gw {
    :
}

function ecn_get_macaddr {
    :
}

# 1 = enable, 0 = disable

function ecn_enable_temp {
    ecn_enabled_p
    if [ $? == $1 ]
	then
	:
	else
	sysctl -w $SYSVAL=$1
    fi
}

function ecn_enable { 
    # FIXME: Pre-supposes existence of this line
    # FIXME: Need to replace whole line
    sed s/$SYSVAL/$SYSVAL=$1/g /etc/sysctl.conf > /tmp/sysctl.conf
    if [ `diff /tmp/sysctl.conf /etc/sysctl.conf` ]
	then
	# do something intelligent. Remember that running out of memory
	# would be bad here
	:
    fi
}


function remove_test_files {
    rm -f /tmp/$TEST_MD5_FILE /tmp/$TEST_FILE /tmp/sysctl.conf
}

function fetch_test_data {
cd /tmp/
remove_test_files
$WGETOPTS http://$TEST_SITE/$TEST_MD5_FILE
# FIXME: make sure it is longer than 0 instead
TEST_MD5=`cat $TEST_MD5_FILE`
}

# FIXME: We can do dns failures, diagnosis of default routes
# Etc.

function have_ipv6_connectivity_p {
HAVE_IPV6=10
addrs=`ip -6 addr  | grep inet6  | grep -v fe80:: | wc -l`
if [ $addrs -gt 1 ]
    then

# Check for default gw?

    if `ping6 -c 2 $TEST_SITE`
    then
	HAVE_IPV6=7
    fi
fi
return $HAVE_IPV6
}

function establish_connectivity {
    fping -p50 -c2 -r2 -t50 $TEST_SITE
}

function ecn_test_ipv6 {
    have_ipv6_connectivity_p
    case $HAVE_IPV6 in
	0) echo "IPV6 is enabled and working to $TEST_SITE" ;;
	5) echo "IPV6 Partial routing failure" ;;
	6) echo "IPV6 ECN failure" ;;
	7) echo "IPV6 PING failure" ;;
	8) echo "IPV6 DNS lookup failure" ;;
	9) echo "IPV6 GW Detect failure" ;;
	10) echo "IPV6 is not enabled on any interfaces" ;;
	*) echo ;;
    esac
return $HAVE_IPV6
}

function compare_test_data {
    ACTUAL_MD5=`md5sum /tmp/$TEST_DATA | cut -f1 -d\ `
    TEST_MD5=`cat /tmp/$TEST_MD5_FILE | cut -f1 -d\ `
    return [ $ACTUAL_MD5 = $TEST_MD5 ]
}

# 
function remove_ecn_qdisc {
    echo "Removing qdiscs"
# Fixme, have qdiscs to remove
}
# 

function add_ecn_qdisc {
    echo "Adding ecn-enabled qdisc"
# Fixme, have qdiscs to add
}

function cleanup {
    remove_test_files
    remove_ecn_qdisc
    exit
}

function ecn_test {
    ecn_enable_temp 1
    establish_connectivity
    fetch_test_data
    compare_test_data
    cleanup
}


# Test basic connectivity
# Test ipv6 connectivity
# Test ECN through the gateway
# Test ECN assertion on packets
# Enable/disable ECN permanently (retest on boot)

# the various tests are symlinked to this shell script

trap cleanup 1 2 3 4 6 7 8 9 10 11 12 13 14 15 

progname=`basename $0`
case $progname in
    ecn_test) ecn_test ;;
    ecn_test_ipv6) ecn_test_ipv6;;
    ecn_test_all) ecn_test; ecn_test_ipv6;;
    ecn_test_all_and_enable) ;;
    ecn_enable) ecn_enable $1 ;;
    *) echo $0 must be one of ecn_test ecn_test_ipv6 ecn_test_all ecn_test_all_and_enable ecn_enable
esac

#       Wget $? error codes
#       0   No problems occurred.
#       1   Generic error code.
#       2   Parse error---for instance, when parsing command-line options, the
#           .wgetrc or .netrc...
#       3   File I/O error.
#       4   Network failure.
#       5   SSL verification failure.
#       6   Username/password authentication failure.
#       7   Protocol errors.
#       8   Server issued an error response.

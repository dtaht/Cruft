#!/bin/sh

OS=openwrt
DEST=localhost
TESTFILE=bloathost.txt

iam() {
	DEV=$1
	MYADDR=`ip addr show dev $DEV | grep 'inet ' | 
		awk '{print $2;}' | cut -f1 -d/`
	MYMAC=`ip addr show dev $DEV | grep 'ether ' | 
		awk '{print $2;}' | cut -f1 -d\ `
	echo "MYMAC=$MYMAC\nMYADDR=$MYADDR"
}

testdate() {
	TESTDATE=`date`
	}

mkfilename() {
	testdate 
	TEMP=/tmp/t.$$
	mkdir $TEMP
	}

mygateway() {
	:
}

myos() {
	MYOS=ubuntu
	if [ -x /etc/config/qos ] 
	then
		MYOS=wrt
	fi
}

cpconfig() {
	case $MYOS in
		wrt) cp /etc/config/qos /etc/config/network $TEMP ;;
		*) echo "dunno what to track" ;;
	esac
	ifconfig $DEF > $TEMP/devinfo
}

rsync_results() {
	:
}
	
init_test() {
	iam eth0
	myos
	mkfilename
	cpconfig
	cd $TEMP
}

# Port 80

test_ecn_neg() {
	tcpdump -i $DEV -c 6 -w ecn_neg.cap ip host $DEST &
	#CHILD=$WHAT? can't remember
	wget -4 http://$DEST/$TESTFILE
	killall tcpdump
	FILESIZE=HOW
	ecn_setting=`sysctl -a 2> /dev/null | grep net.ipv4.tcp_ecn |
		awk '{print $3;}'`
	if [ "$ecn_setting" = 0 ]
	then 
		echo "ECN=NOT_ENABLED"
		return
	fi
	if [ $FILESIZE -gt 0] 
		then
		if [ "$FILESIZE" -gt 2 ] 
		then
			echo "ECN=NEGOTIATED"
		else
			echo "ECN=ATTEMPTED_FAIL"
		fi
		else
			echo "ECN=NOT_ATTEMPTED"
		fi
	}

run_test() {
	:
	}

start_dump() {
	:
}

stop_dump() {
	:
}

end_test() {
	rsync_results && if [ -d $TEMP ] 
		then 
		echo rm -f $TEMP
		fi
	}

init_test
test_ecn_neg
#run_test
end_test


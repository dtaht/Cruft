
tc qdisc del dev eth0 root
tc qdisc del dev eth0 ingress

tc qdisc add dev eth0 root handle 1: htb default 20
tc class add dev eth0 parent 1: classid 1:1 htb rate 240kbit burst 6k
tc class add dev eth0 parent 1:1 classid 1:10 htb rate 240kbit burst 6k prio 1
tc class add dev eth0 parent 1:1 classid 1:20 htb rate 216kbit burst 6k prio 2
tc class add dev eth0 parent 1:1 classid 1:30 htb rate 192kbit burst 6k prio 2
tc qdisc add dev eth0 parent 1:10 handle 10: sfb # target 30 max 50 penalty_rate 100
tc qdisc add dev eth0 parent 1:20 handle 20: sfb # target 30 max 50 penalty_rate 100
tc qdisc add dev eth0 parent 1:30 handle 30: sfb # target 30 max 50 penalty_rate 100
tc filter add dev eth0 parent 1:0 protocol ip prio 10 u32 match ip tos 0x10 0xff flowid 1:10
tc filter add dev eth0 parent 1:0 protocol ip prio 10 u32 match ip protocol 1 0xff flowid 1:10
tc filter add dev eth0 parent 1: protocol ip prio 10 u32 match ip protocol 6 0xff match u8 0x05 0x0f at 0 match u16 0x0000 0xffc0 at 2 match u8 0x10 0xff at 33 flowid 1:10
tc filter add dev eth0 parent 1: protocol ip prio 14 u32 match ip dport 21 0xffff flowid 1:30
tc filter add dev eth0 parent 1: protocol ip prio 18 u32 match ip dst 0.0.0.0/0 flowid 1:20
tc qdisc add dev eth0 handle ffff: ingress
tc filter add dev eth0 parent ffff: protocol ip prio 50 u32 match ip src 0.0.0.0/0 police rate 2000kbit burst 10k drop flowid :1


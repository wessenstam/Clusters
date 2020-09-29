#!/bin/bash
# ipsec.conf file creation

# Get the needed parameters need to transform into variables in Calm
public_cgw="192.146.154.246"
aws_vgw1="18.157.130.129"
aws_vgw2="52.58.92.66"
onprem_netw="10.38.2.64/26"
aws_vpc_netw="10.0.0.0/16"
vpn_tun1_netwl="169.254.98.196/30"
vpn_tun1_netwr="169.254.98.195/30"
vpn_tun2_netwl="169.254.163.228/30"
vpn_tun2_netwr="169.254.163.227/30"
psk_tun1_aws="tdEGkjWKz8y39z.hd77uJg7_N9hLtafo"
psk_tun2_aws="Qky5qbYx6vPmlSX0wQw9ITniaatjMZUN"

# Install the strongswan package
yum update -y
yum install epel-release
yum update -y
yum install -y strongswan wget

# build the ipsec.conf
cat <<EOF > /etc/strongswan/ipsec.conf
config setup
	strictcrlpolicy=no
	uniqueids = no

conn Tunnel1
	auto=start
	leftid=${public_cgw}
	right=${aws_vgw1}
	type=tunnel
	leftauth=psk
	rightauth=psk
	keyexchange=ikev1
	ike=aes128-sha1-modp1024
	ikelifetime=8h
	esp=aes128-sha1-modp1024
	lifetime=1h
	keyingtries=%forever
	leftsubnet=${onprem_netw}
	rightsubnet=${aws_vpc_netw}
	dpddelay=10s
	dpdtimeout=30s
	dpdaction=restart
	mark=100
	leftupdown="/etc/strongswan/aws-updown.sh -ln Tunnel1 -ll ${vpn_tun1_netwl} -lr ${vpn_tun1_netwr} -m 100 -r ${aws_vpc_netw}"

conn Tunnel2
	auto=start
	leftid=${public_cgw}
	right=${aws_vgw2}
	type=tunnel
	leftauth=psk
	rightauth=psk
	keyexchange=ikev1
	ike=aes128-sha1-modp1024
	ikelifetime=8h
	esp=aes128-sha1-modp1024
	lifetime=1h
	keyingtries=%forever
	leftsubnet=${onprem_netw}
	rightsubnet=${aws_vpc_netw}
	dpddelay=10s
	dpdtimeout=30s
	dpdaction=restart
	mark=200
	leftupdown="/etc/strongswan/aws-updown.sh -ln Tunnel2 -ll ${vpn_tun2_netwl} -lr ${vpn_tun2_netwr} -m 200 -r ${aws_vpc_netw}"
EOF

# Create the ipsec.secrets files
echo ${public_cgw} ${aws_vgw1}" : PSK \"${psk_tun1_aws}\"" > /etc/strongswan/ipsec.secrets
echo ${public_cgw} ${aws_vgw2}" : PSK \"${psk_tun2_aws}\"" >> /etc/strongswan/ipsec.secrets

# Get the aws-updown.sh script and make executable
wget -q https://raw.githubusercontent.com/wessenstam/Clusters/master/aws-updown.sh -O /etc/strongswan/aws-updown.sh
chmod +x /etc/strongswan/aws-updown.sh
# Make sure strongswan starts at boot time
chkconfig --level 35 strongswan on

# start strongswan
strongswan start

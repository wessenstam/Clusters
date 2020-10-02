#!/bin/bash
# Get the needed parameters

if [ "$#" -ne 2 ]; then
    echo "Illegal number of parameters"
    echo "Usage: vpn-install.sh <ONPREM NETWORK> <AWS_VPC CIDR>. Example: vpn-install.sh 10.42.7.0/25 10.0.0.0/16"
else
onprem_netw=$1
aws_vpc_netw=$2

echo "Installing the needed packages. Please be patient...."
# Install the strongswan package
sudo yum install -y -q epel-release wget
sudo yum update -y -q
sudo yum install -y -q strongswan

echo "Setting system network forwarding parameters..."
# Installing the needed rules in sysctl
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.send_redirects = 0" >> /etc/sysctl.conf

echo "Reloading just set system parameters......"
# reloading the sysctl
sysctl -p


local_IP=$(sudo ifconfig eth0 | grep netmask | awk '{print $2}')
cgw_ipaddress=$(curl --insecure --silent https://myexternalip.com | grep "<title>" | tr -s " " ":" | cut -d ":" -f 7)
echo "This is my external IP address, please use it as customer gateway on AWS side" $cgw_ipaddress
echo "Once you created the Site-to-Site configuration in AWS and it is available, Download the Configuration (generic vendor) to your machine."
echo "After the copy, please copy or create a file called /tmp/vpn_file.txt with the content of the downloaded txt file from AWS."
echo "IPaddress to ssh to me is the following: " $local_IP
echo "The script will loop till it sees the file uploaded."


until [ -f /tmp/vpn_file.txt ]
do
     sleep 30
     date
done

grep "Pre-Shared" /tmp/vpn_file.txt | grep -v Auth | awk '{print $5}' > ~/info.txt
grep "Customer Gateway" /tmp/vpn_file.txt | grep ":" | grep -vwE "(ASN|your|ID)" | awk '{print $5}' >> ~/info.txt
grep "Virtual Private Gateway" /tmp/vpn_file.txt | grep ":" | grep -v ID | awk '{print $6}' >> ~/info.txt

psk_tun1_aws=$(sed '1q;d' ~/info.txt)
psk_tun2_aws=$(sed '2q;d' ~/info.txt)
public_cgw=$(sed '3q;d' ~/info.txt)
vpn_tun1_netwl=$(sed '4q;d' ~/info.txt)
vpn_tun2_netwl=$(sed '6q;d' ~/info.txt)
aws_vgw1=$(sed '7q;d' ~/info.txt)
vpn_tun1_netwr=$(sed '8q;d' ~/info.txt)
aws_vgw2=$(sed '9q;d' ~/info.txt)
vpn_tun2_netwr=$(sed '10q;d' ~/info.txt)

rm ~/info.txt

# Ask if correct
echo "The inforamtion that will be used is mentioned below:"
echo "HPOC Gateway: "$cgw_ippaddress
echo "HPOC Network CIDR: "$onprem_netw
echo "VPC AWS network CIDR: "$aws_vpc_netw
echo "Tunnel 1 information:"
echo "  AWS Gateway: "$aws_vgw1
echo "  Tunnel local: "$vpn_tun1_netwl
echo "  Tunnel AWS: "$vpn_tun1_netwr
echo "  Tunnel PSK: "$psk_tun1_aws
echo "Tunnel 2 information:"
echo "  AWS Gateway: "$aws_vgw2
echo "  Tunnel local: "$vpn_tun2_netwl
echo "  Tunnel AWS: "$vpn_tun2_netwr
echo "  Tunnel PSK: "$psk_tun2_aws
echo

read -r -p "Are these correct? [y/N] " response
if [[ "$response" =~ ^([yY])$ ]]; then

echo "
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
    leftupdown=\"/etc/strongswan/aws-updown.sh -ln Tunnel1 -ll ${vpn_tun1_netwl} -lr ${vpn_tun1_netwr} -m 100 -r ${aws_vpc_netw}\"

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
    leftupdown=\"/etc/strongswan/aws-updown.sh -ln Tunnel2 -ll ${vpn_tun2_netwl} -lr ${vpn_tun2_netwr} -m 200 -r ${aws_vpc_netw}\" " | sudo tee /etc/strongswan/ipsec.conf

# Create the ipsec.secrets files
echo "${public_cgw} ${aws_vgw1} : PSK \"${psk_tun1_aws}\"
${public_cgw} ${aws_vgw2} : PSK \"${psk_tun2_aws}\"" | sudo tee /etc/strongswan/ipsec.secrets


# Get the aws-updown.sh script and make executable
sudo wget -q https://raw.githubusercontent.com/wessenstam/Clusters/master/files/aws-updown.sh -O /etc/strongswan/aws-updown.sh
sudo chmod +x /etc/strongswan/aws-updown.sh

# Make sure strongswan starts at boot time
sudo chkconfig --level 35 strongswan on

# start strongswan
sudo strongswan restart


else
        exit 0
fi
fi

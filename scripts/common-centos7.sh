#!/bin/bash
# Common Configuration
# Designed for CentOS/RHEL 7
# Author: Alejandro Galue <agalue@opennms.org>

# Update base OS

sudo yum update -y -q

# Install basic packages and dependencies

if ! rpm -qa | grep -q haveged; then
  sudo yum install -y -q epel-release
  sudo yum install -y -q haveged ntp ntpdate net-tools vim-enhanced wget curl git jq unzip net-snmp net-snmp-utils dstat htop sysstat nmap-ncat sshpass
fi

# Install OpenJDK 11

if ! rpm -qa | grep -q java-11-openjdk-devel; then
  sudo yum install -y -q java-11-openjdk java-11-openjdk-devel java-11-openjdk-headless
fi

# Setting up Time

TIMEZONE=America/New_York
sudo timedatectl set-timezone $TIMEZONE
sudo ntpdate -u pool.ntp.org

NTP_CFG=/etc/ntpd.conf
if [ -e "$NTP_CFG.bak" ]; then
  sudo mv $NTP_CFG $NTP_CFG.bak
fi
cat <<EOF | sudo tee $NTP_CFG
driftfile /var/lib/ntp/drift
restrict default nomodify notrap nopeer noquery kod
restrict -6 default nomodify notrap nopeer noquery kod
restrict 127.0.0.1
restrict ::1
server 0.north-america.pool.ntp.org iburst
server 1.north-america.pool.ntp.org iburst
server 2.north-america.pool.ntp.org iburst
server 3.north-america.pool.ntp.org iburst
includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
disable monitor
EOF
sudo systemctl enable ntpd
sudo systemctl start ntpd

# Enable and start haveged 

sudo systemctl enable haveged
sudo systemctl start haveged

# Configure and enable SNMP

if [ ! -f "/etc/snmp/configured" ]; then
  SNMP_CFG=/etc/snmp/snmpd.conf
  if [ -e "$SNMP_CFG.bak" ]; then
    sudo mv $SNMP_CFG $SNMP_CFG.bak
  fi
  cat <<EOF | sudo tee $SNMP_CFG
com2sec localUser 127.0.0.1/32 public
com2sec localUser 192.168.205.0/24 public
group localGroup v1 localUser
group localGroup v2c localUser
view all included .1 80
access localGroup "" any noauth 0 all none none
syslocation VirtualBox
syscontact Alejandro Galue <agalue@opennms.org>
dontLogTCPWrappersConnects yes
disk /
EOF
  sudo chmod 600 /etc/snmp/snmpd.conf
  sudo systemctl enable snmpd
  sudo systemctl start snmpd
  sudo touch /etc/snmp/configured
fi

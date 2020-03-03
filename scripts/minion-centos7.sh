#!/bin/bash
# OpenNMS Minion
# Designed for CentOS/RHEL 7
# Author: Alejandro Galue <agalue@opennms.org>

ONMS_REPO_NAME="${1-stable}"
ONMS_SERVER="${2-192.168.205.1:8980}"
KAFKA_SERVER="${3-192.168.205.1:9092}"
 
# Install OpenNMS Minion packages

if ! rpm -qa | grep -q opennms-minion; then

  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$ONMS_REPO_NAME-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-$ONMS_REPO_NAME-rhel7.gpg
  sudo yum install -y -q opennms-minion
fi

# Configure Minion

TOTAL_MEM_IN_MB=$(free -m | awk '/:/ {print $2;exit}')
MEM_IN_MB=$(expr $TOTAL_MEM_IN_MB / 2)
if [ "$MEM_IN_MB" -gt "8192" ]; then
  MEM_IN_MB="8192"
fi
sudo sed -r -i "/export JAVA_MIN_MEM/s/.*/export JAVA_MIN_MEM=${MEM_IN_MB}m/" /etc/sysconfig/minion
sudo sed -r -i "/export JAVA_MAX_MEM/s/.*/export JAVA_MAX_MEM=${MEM_IN_MB}m/" /etc/sysconfig/minion
sudo sed -r -i "/export JAVA_HOME/s/.*/export JAVA_HOME=\/usr\/lib\/jvm\/java/" /etc/sysconfig/minion

MINION_HOME=/opt/minion
MINION_ETC=$MINION_HOME/etc

if [ ! -f "$MINION_ETC/configured" ]; then
  cd $MINION_ETC
  sudo git init .
  sudo git add .
  sudo git commit -m "Default Minion configuration for repository $ONMS_REPO_NAME."

  cat <<EOF | sudo tee $MINION_ETC/featuresBoot.d/hawtio.boot
hawtio-offline
EOF

  cat <<EOF | sudo tee $MINION_ETC/featuresBoot.d/kafka.boot
!minion-jms
!opennms-core-ipc-sink-camel
opennms-core-ipc-sink-kafka
!opennms-core-ipc-rpc-jms
opennms-core-ipc-rpc-kafka
EOF

  MINION_ID=$(hostname)
  cat <<EOF | sudo tee $MINION_ETC/org.opennms.minion.controller.cfg
id=$MINION_ID
location=Vagrant
http-url=http://$ONMS_SERVER/opennms
EOF

  sed -r -i '/sshHost/s/127.0.0.1/0.0.0.0/' $MINION_ETC/org.apache.karaf.shell.cfg

  cat <<EOF | sudo tee $MINION_ETC/org.opennms.core.ipc.sink.kafka.cfg
bootstrap.servers=$KAFKA_SERVER
EOF
  cat <<EOF | sudo tee $MINION_ETC/org.opennms.core.ipc.rpc.kafka.cfg
bootstrap.servers=$KAFKA_SERVER
EOF

  cat <<EOF | sudo tee $MINION_ETC/org.opennms.netmgt.trapd.cfg
trapd.listen.interface=0.0.0.0
trapd.listen.port=1162
EOF

  cat <<EOF | sudo tee $MINION_ETC/org.opennms.netmgt.syslog.cfg
syslog.listen.interface=0.0.0.0
syslog.listen.port=1514
EOF

  sudo systemctl enable minion
  sudo systemctl start minion
  sudo touch $MINION_ETC/configured
fi

echo "Done!"

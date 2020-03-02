#!/bin/bash
# OpenNMS Sentinel
# Designed for CentOS/RHEL 7
# Author: Alejandro Galue <agalue@opennms.org>

ONMS_REPO_NAME="${1-stable}"
ONMS_SERVER="${2-192.168.205.1:8980}"
KAFKA_SERVER="${3-192.168.205.1:9092}"
ZOOKEEPER_SERVER="${4-192.168.205.1:2181}"

# Install OpenNMS Sentinel

if ! rpm -qa | grep -q opennms-sentinel; then
  echo "Installing OpenNMS from '$ONMS_REPO_NAME' repository..."
  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$ONMS_REPO_NAME-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-$ONMS_REPO_NAME-rhel7.gpg
  sudo yum install -y -q opennms-sentinel
fi

# Install ALEC

if ! rpm -qa | grep -q sentinel-alec-plugin; then
  echo "Installing ALEC Plugin for Sentinel..."
  sudo yum install -y -q sentinel-alec-plugin
fi

# Configure Sentinel

echo "Configuring Java Heap..."
TOTAL_MEM_IN_MB=$(free -m | awk '/:/ {print $2;exit}')
MEM_IN_MB=$(expr $TOTAL_MEM_IN_MB / 2)
if [ "$MEM_IN_MB" -gt "8192" ]; then
  MEM_IN_MB="8192"
fi
sudo sed -r -i "/export JAVA_MIN_MEM/s/.*/export JAVA_MIN_MEM=${MEM_IN_MB}m/" /etc/sysconfig/sentinel
sudo sed -r -i "/export JAVA_MAX_MEM/s/.*/export JAVA_MAX_MEM=${MEM_IN_MB}m/" /etc/sysconfig/sentinel
sudo sed -r -i "/export JAVA_HOME/s/.*/export JAVA_HOME=\/usr\/lib\/jvm\/java/" /etc/sysconfig/sentinel

SENTINEL_HOME=/opt/sentinel
SENTINEL_ETC=$SENTINEL_HOME/etc
echo "Configuring Sentinel..."

if [ ! -f "$SENTINEL_ETC/configured" ]; then
  cd $SENTINEL_ETC
  sudo git init .
  sudo git add .
  sudo git commit -m "Default Sentinel configuration for repository $ONMS_REPO_NAME."

  SENTINEL_ID=$(hostname)
  cat <<EOF | sudo tee $SENTINEL_ETC/org.opennms.sentinel.controller.cfg
id=$SENTINEL_ID
location=Vagrant
http-url=http://$ONMS_SERVER/opennms
EOF

  sed -r -i '/sshHost/s/127.0.0.1/0.0.0.0/' $SENTINEL_ETC/org.apache.karaf.shell.cfg

  cat <<EOF | sudo tee $SENTINEL_ETC/featuresBoot.d/alec.boot
sentinel-core
sentinel-coordination-zookeeper
alec-sentinel-distributed wait-for-kar=opennms-alec-plugin
EOF

  cat <<EOF | sudo tee $SENTINEL_ETC/org.opennms.features.distributed.coordination.zookeeper.cfg
connectString=$ZOOKEEPER_SERVER
EOF

  cat <<EOF | sudo tee $SENTINEL_ETC/featuresBoot.d/hawtio.boot
hawtio-offline
EOF

  cat <<EOF | sudo tee $SENTINEL_ETC/org.opennms.core.ipc.sink.kafka.consumer.cfg
bootstrap.servers=$KAFKA_SERVER
EOF

  cat <<EOF | sudo tee $SENTINEL_ETC/org.opennms.alec.datasource.opennms.kafka.cfg
# Make sure to configure the topics on OpenNMS the same way
eventSinkTopic=OpenNMS.Sink.Events
inventoryTopic=OpenNMS-alec-inventory
nodeTopic=OpenNMS-nodes
alarmTopic=OpenNMS-alarms
alarmFeedbackTopic=OpenNMS-alarms-feedback
edgesTopic=OpenNMS-topology-edges
EOF

  cat <<EOF | sudo tee $SENTINEL_ETC/org.opennms.alec.datasource.opennms.kafka.producer.cfg
bootstrap.servers=$KAFKA_SERVER
EOF

  cat <<EOF | sudo tee $SENTINEL_ETC/org.opennms.alec.datasource.opennms.kafka.streams.cfg
bootstrap.servers=$KAFKA_SERVER
commit.interval.ms=5000
EOF

  cat <<EOF | sudo tee /etc/security/limits.d/sentinel.conf
sentinel soft nofile 300000
sentinel hard nofile 300000
EOF

  chown sentinel:sentinel $SENTINEL_ETC/* $SENTINEL_HOME/deploy/*
  sudo service minion start
  sudo service sentinel start
  sudo touch $SENTINEL_ETC/configured
fi

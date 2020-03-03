#!/bin/bash
# OpenNMS Horizon
# Designed for CentOS/RHEL 7
# Author: Alejandro Galue <agalue@opennms.org>

ONMS_REPO_NAME="${1-stable}"
PG_SERVER="${2-192.168.205.1:5432}"
KAFKA_SERVER="${3-192.168.205.1:9092}"
ES_SERVER="${4-192.168.205.1:9200}"

# Install OpenNMS dependencies

if ! rpm -qa | grep -q jicmp; then
  echo "Installing OpenNMS dependencies ..."
  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
  sudo yum install -y -q jicmp jicmp6 jrrd jrrd2 rrdtool 'perl(LWP)' 'perl(XML::Twig)'
  sudo yum erase -y -q opennms-repo-stable
fi

# Install Grafana

if ! rpm -qa | grep -q grafana; then
  echo "Installing Grafana..."
  sudo yum install -y -q https://dl.grafana.com/oss/release/grafana-6.6.2-1.x86_64.rpm
fi

# Install OpenNMS Core and Helm

if ! rpm -qa | grep -q opennms-core; then
  echo "Installing OpenNMS from '$ONMS_REPO_NAME' repository..."
  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$ONMS_REPO_NAME-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-$ONMS_REPO_NAME-rhel7.gpg
  sudo yum install -y -q opennms-core opennms-webapp-jetty opennms-webapp-hawtio
  sudo yum install -y -q opennms-helm
fi

# Install ALEC

if ! rpm -qa | grep -q opennms-alec-plugin; then
  echo "Installing ALEC Plugin for OpenNMS..."
  sudo yum install -y -q opennms-alec-plugin
fi

# Configure OpenNMS

ONMS_HOME=/opt/opennms
ONMS_ETC=$ONMS_HOME/etc
echo "Configuring OpenNMS..."
 
if [ ! -f "$ONMS_ETC/configured" ]; then
  cd $ONMS_ETC
  sudo git init .
  sudo git add .
  sudo git commit -m "Default OpenNMS configuration for repository $ONMS_REPO_NAME."

  TOTAL_MEM_IN_MB=$(free -m | awk '/:/ {print $2;exit}')
  MEM_IN_MB=$(expr $TOTAL_MEM_IN_MB / 2)
  if [ "$MEM_IN_MB" -gt "30720" ]; then
    MEM_IN_MB="30720"
  fi
  IP_ADDR=$(ifconfig eth1 | grep "inet " | awk '{print $2}')
  JMX_PORT=18980
  cat <<EOF | sudo tee $ONMS_ETC/opennms.conf
START_TIMEOUT=0
JAVA_HEAP_SIZE=$MEM_IN_MB
MAXIMUM_FILE_DESCRIPTORS=204800

ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseG1GC -XX:+UseStringDeduplication"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Xlog:gc*=debug:file=$ONMS_HOME/logs/gc.log:time,uptime,level,tags:filecount=10,filesize=10m"

# Configure Remote JMX (optional)
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.port=$JMX_PORT"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.rmi.port=$JMX_PORT"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.local.only=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.ssl=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.authenticate=true"

# Listen on all interfaces
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dopennms.poller.server.serverHost=0.0.0.0"

# Accept remote RMI connections on this interface
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.rmi.server.hostname=$IP_ADDR"
EOF

  cat <<EOF | sudo tee $ONMS_ETC/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
org.opennms.rrd.strategyClass=org.opennms.netmgt.rrd.rrdtool.MultithreadedJniRrdStrategy
org.opennms.rrd.interfaceJar=/usr/share/java/jrrd2.jar
opennms.library.jrrd2=/usr/lib64/libjrrd2.so
EOF

  sudo sed -r -i 's/value="DEBUG"/value="WARN"/' $ONMS_ETC/log4j2.xml
  sudo sed -r -i '/manager/s/WARN/DEBUG/'        $ONMS_ETC/log4j2.xml

  sudo sed -r -i 's/"Postgres"/"PostgreSQL"/g' $ONMS_ETC/poller-configuration.xml
  sudo sed -r -i '/pathOutageEnabled/s/false/true/' $ONMS_ETC/poller-configuration.xml

  sudo sed -r -i '/sshHost/s/127.0.0.1/0.0.0.0/' $ONMS_ETC/org.apache.karaf.shell.cfg

  LAST_ENTRY="opennms-karaf-health"
  FEATURES_LIST="opennms-alarm-history-elastic,opennms-kafka-producer,opennms-es-rest,opennms-situation-feedback"
  sudo sed -r -i "s/^  $LAST_ENTRY.*/  $FEATURES_LIST,$LAST_ENTRY/" $ONMS_ETC/org.apache.karaf.features.cfg

  cat <<EOF | sudo tee $ONMS_ETC/featuresBoot.d/alec.boot
alec-opennms-distributed wait-for-kar=opennms-alec-plugin
EOF

  cat <<EOF | sudo tee $ONMS_ETC/opennms.properties.d/event-sink.properties
org.opennms.netmgt.eventd.sink.enable=true
EOF

  cat <<EOF | sudo tee $ONMS_ETC/opennms.properties.d/no-activemq.properties
org.opennms.activemq.broker.disable=true
EOF

  cat <<EOF | sudo tee $ONMS_ETC/opennms.properties.d/kafka-rpc.properties
org.opennms.core.ipc.rpc.initialSleepTime=60000
org.opennms.core.ipc.rpc.strategy=kafka
org.opennms.core.ipc.rpc.kafka.bootstrap.servers=$KAFKA_SERVER
EOF

  cat <<EOF | sudo tee $ONMS_ETC/opennms.properties.d/kafka-sink.properties
org.opennms.core.ipc.sink.initialSleepTime=60000
org.opennms.core.ipc.sink.strategy=kafka
org.opennms.core.ipc.sink.kafka.bootstrap.servers=$KAFKA_SERVER
EOF

  cat <<EOF | sudo tee $ONMS_ETC/org.opennms.features.kafka.producer.cfg
# Make sure to configure the topics on Sentinel the same way
suppressIncrementalAlarms=false
nodeTopic=OpenNMS-nodes
eventTopic=OpenNMS-events
alarmTopic=OpenNMS-alarms
alarmFeedbackTopic=OpenNMS-alarms-feedback
topologyVertexTopic=OpenNMS-topology-vertices
topologyEdgeTopic=OpenNMS-topology-edges
EOF

  cat <<EOF | sudo tee $ONMS_ETC/org.opennms.features.kafka.producer.client.cfg
bootstrap.servers=$KAFKA_SERVER
EOF

  cat <<EOF | sudo tee $ONMS_ETC/org.opennms.features.alarms.history.elastic.cfg
elasticUrl=http://$ES_SERVER
elasticIndexStrategy=monthly
nodeCache.maximumSize=5000
nodeCache.expireAfterWrite=3600
connTimeout=30000
readTimeout=300000
# The following settings should be consistent with your ES cluster
settings.index.number_of_shards=1
settings.index.number_of_replicas=0
EOF

  # TODO This is not working for some reason. It has to be reconfigured after installing the feature
  cat <<EOF | sudo tee $ONMS_ETC/org.opennms.features.situation-feedback.persistence.elastic.cfg
elasticUrl=http://$ES_SERVER
elasticIndexStrategy=monthly
connTimeout=30000
readTimeout=300000
# The following settings should be consistent with your ES cluster
settings.index.number_of_shards=1
settings.index.number_of_replicas=0
EOF

  cat <<EOF | sudo tee $ONMS_ETC/org.opennms.plugin.elasticsearch.rest.forwarder.cfg
elasticUrl=http://$ES_SERVER
elasticIndexStrategy=monthly
groupOidParameters=true
archiveAlarms=false
archiveAlarmChangeEvents=false
connTimeout=30000
readTimeout=300000
# The following settings should be consistent with your ES cluster
settings.index.number_of_shards=1
settings.index.number_of_replicas=0
EOF

  sudo sed -i -r '/opennms-flows/d' $ONMS_ETC/org.apache.karaf.features.cfg
  sudo sed -i 'N;s/service.*\n\(.*Telemetryd\)/service enabled="false">\n\1/;P;D' $ONMS_ETC/service-configuration.xml

  sudo sed -r -i '/enabled="false"/{$!{N;s/ enabled="false"[>]\n(.*OpenNMS:Name=Syslogd.*)/>\n\1/}}' $ONMS_ETC/service-configuration.xml

  WEB_XML=$ONMS_HOME/jetty-webapps/opennms/WEB-INF/web.xml
  sudo cp $WEB_XML $WEB_XML.bak
  sudo sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' $WEB_XML
  sudo sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' $WEB_XML

  mkdir -p $ONMS_ETC/imports/pending
  cat <<EOF | sudo tee $ONMS_ETC/imports/pending/OpenNMS.xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model-import xmlns="http://xmlns.opennms.org/xsd/config/model-import" date-stamp="2017-01-01T00:00:00.000-05:00" foreign-source="OpenNMS">
  <node building="Vagrant" foreign-id="opennms-server" node-label="opennms-server">
    <interface descr="loopback" ip-addr="127.0.0.1" status="1" snmp-primary="P"/>
  </node>
</model-import>
EOF

  sudo $ONMS_HOME/bin/runjava -s
 
  sudo sed -r -i "s/localhost:5432/$PG_SERVER/g" $ONMS_ETC/opennms-datasources.xml
  sudo sed -r -i 's/password=""/password="postgres"/' $ONMS_ETC/opennms-datasources.xml

  sudo $ONMS_HOME/bin/install -dis
  sudo service opennms start

  sudo service grafana-server start
  sleep 10
  GRAFANA_AUTH="admin:admin"
  GRAFANA_URL="http://localhost:3000"
  HELM_URL="$GRAFANA_URL/api/plugins/opennms-helm-app/settings"
  DS_URL="$GRAFANA_URL/api/datasources"
  JSON_FILE=/tmp/data.json
  cat <<EOF | sudo tee $JSON_FILE
{
  "name": "opennms-performance",
  "type": "opennms-helm-performance-datasource",
  "access": "proxy",
  "url": "http://localhost:8980/opennms",
  "basicAuth": true,
  "basicAuthUser": "admin",
  "basicAuthPassword": "admin"
}
EOF
  if curl -u $GRAFANA_AUTH "$HELM_URL" 2>/dev/null | grep -q '"enabled":false'; then
    curl -u $GRAFANA_AUTH -XPOST "$HELM_URL" -d "id=opennms-helm-app&enabled=true" 2>/dev/null
    curl -u $GRAFANA_AUTH -H 'Content-Type: application/json' -XPOST -d @$JSON_FILE $DS_URL 2>/dev/null
    sudo sed -i -r 's/-performance/-entity/g' $JSON_FILE
    curl -u $GRAFANA_AUTH -H 'Content-Type: application/json' -XPOST -d @$JSON_FILE $DS_URL 2>/dev/null
  fi
  sudo rm -f $JSON_FILE

  sleep 120
  /vagrant/scripts/fix-situations-feedback.sh
fi

echo "Done!"

#!/bin/bash

ES_SERVER=192.168.205.1:9200
sshpass -p admin ssh -p 8101 admin@localhost "\
config:edit org.opennms.features.situation-feedback.persistence.elastic;
config:property-set elasticUrl http://$ES_SERVER;
config:property-set elasticIndexStrategy monthly;
config:property-set connTimeout 30000;
config:property-set readTimeout 300000;
config:property-set settings.index.number_of_shards 1;
config:property-set settings.index.number_of_replicas 0;
config:update;
config:list '(service.pid=org.opennms.features.situation-feedback.persistence.elastic)'
"


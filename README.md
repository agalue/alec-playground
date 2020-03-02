Test Environment for ALEC
===

The following link provides a detailed step by step pralecdure on how to install and configure all the components to have an up and running ALEC environment.

https://hackmd.io/HZZG6NU0QtiUhf6gjYGu9w

The following is just a simplifying guide, in terms of deploying the infrastructure on your local machine.

# Requirements

1. [Docker](https://www.docker.com/get-started)
2. [Vagrant](https://www.vagrantup.com/downloads.html)
3. [VirtualBox](https://www.virtualbox.org/wiki/Downloads)

# Installation

1. Start all the dependencies using Docker

```bash
docker-compose up -d
```

> **WARNING**: All the topics must exist prior starting the ALEC engine. This is why the Kafka image will create the required topics. This is missing on the official documents. The required topics are: `OpenNMS-nodes`, `OpenNMS-alarms`, `OpenNMS-alarms-feedback`, `OpenNMS-topology-edges`, and `OpenNMS-alec-inventory`.

2. Update the IP addresses for Kafka, Elasticsearch and PostgreSQl on the `Vagrantfile`.

For example, if the host machine IP where all these services are exposed to is `192.168.205.1`:

```ruby
common = {
  :branch   => "stable",
  :kafka    => "192.168.205.1:9092",
  :elastic  => "192.168.205.1:9200",
  :postgres => "192.168.205.1:5432"
}
```

3. Start the VMs (OpenNMS, Sentinel and the SNMP Test Machine)

```bash
vagrant up
```

4. Configure requisition

```bash
vagrant ssh opennms
```

Then,

```bash
provision.pl requisition add Test
provision.pl node add Test server01 server01
provision.pl interface add Test server01 192.168.205.173
provision.pl interface set Test server01 192.168.205.173 snmp-primary P
provision.pl requisition import Test
```

> **NOTE**: The IP `192.168.205.173` is defined on the `Vagrantfile` for the test server.

# Verification

## From the OpenNMS Karaf Shell

1. Verify OSGi Bundles:

```bash
admin@opennms> bundle:list | grep ALEC
355 │ Active   │  80 │ 1.0.0          │ ALEC :: Integrations :: OpenNMS :: Config
356 │ Active   │  80 │ 1.0.0          │ ALEC :: Integrations :: OpenNMS :: Extension
357 │ Active   │  80 │ 1.0.0          │ ALEC :: Integrations :: OpenNMS :: Model
```

2. Verify that the events configuration from the Integrations API was loaded:

```bash
admin@opennms> events:show-event-config -u uei.opennms.org/vendor/cisco/syslog/ifDown
Event #1
<event xmlns="http://xmlns.opennms.org/xsd/eventconf">
   <uei>uei.opennms.org/vendor/cisco/syslog/ifDown</uei>
   <priority>0</priority>
   <event-label>CISCO defined syslog event: ifDown</event-label>
   <descr>The node: %nodelabel% has indicated that the interface: %parm[ifDescr]% has transistioned from an &quot;Up&quot; state to a &quot;Down&quot; state via a Syslog message.
        </descr>
   <logmsg dest="logndisplay">The interface: %parm[ifDescr]% is Down.</logmsg>
   <severity>Minor</severity>
   <alarm-data reduction-key="%uei%:%dpname%:%nodeid%:%parm[ifDescr]%" alarm-type="1" auto-clean="false">
      <managed-object type="snmp-interface"/>
   </alarm-data>
</event>
```

## From the Test Server

```bash
export ONMS_SERVER="192.168.205.170"
export IFDESCR="eth1"
echo "<189>: $(date +"%Y %b %d %H:%m:%S %Z"): %ETHPORT-5-IF_DOWN_LINK_FAILURE: Interface $IFDESCR is down (Link failure)" | nc -v -u $ONMS_SERVER 10514
sleep 5
echo "<189>: $(date +"%Y %b %d %H:%m:%S %Z"): %PKT_INFRA-LINEPROTO-5-UPDOWN: Line protocol on Interface $IFDESCR, changed state to Down" | nc -v -u $ONMS_SERVER 10514
```

## From the Sentinel Karaf Shell

```bash
admin@sentinel> opennms-alec:list-graphs
dbscan: 1 situations on 6 vertices and 3 edges.
```

To export the graph and visualize it on the OpenNMS WebUI

```bash
ssh -p 8301 admin@localhost opennms-alec:export-graph dbscan /tmp/cluster.graph.xml
curl -X POST -H "Content-Type: application/xml" -u admin:admin -d@/tmp/cluster.graph.xml 'http://192.168.205.170:8980/opennms/rest/graphml/alec'
```

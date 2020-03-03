# -*- mode: ruby -*-
# vi: set ft=ruby :

common = {
  :distributed => false,
  :branch      => "stable",
  :kafka       => "192.168.205.1:9092",
  :zookeeper   => "192.168.205.1:2181",
  :elastic     => "192.168.205.1:9200",
  :postgres    => "192.168.205.1:5432"
}

minion = {
  :name => "OpenNMS-ALEC-Minion",
  :host => "minion.local",
  :ip   => "192.168.205.169",
  :mem  => "2048",
  :cpu  => "1"
}

opennms = {
  :name => "OpenNMS-ALEC-Horizon",
  :host => "horizon.local",
  :ip   => "192.168.205.170",
  :mem  => "4096",
  :cpu  => "2"
}

sentinels = [
  {
    :id   => "sentinel1",
    :name => "OpenNMS-ALEC-Sentinel-1",
    :host => "sentinel01.local",
    :ip   => "192.168.205.171",
    :mem  => "2048",
    :cpu  => "1"
  },{
    :id   => "sentinel2",
    :name => "OpenNMS-ALEC-Sentinel-2",
    :host => "sentinel02.local",
    :ip   => "192.168.205.172",
    :mem  => "2048",
    :cpu  => "1"
  }
]

test = {
  :name => "OpenNMS-Test-Server",
  :host => "test01.local",
  :ip   => "192.168.205.173"
}

Vagrant.configure("2") do |config|
  config.vm.box = "centos/7"

  config.vm.define "opennms" do |config|
    config.vm.hostname = opennms[:host]
    config.vm.provider "virtualbox" do |v|
      v.name = opennms[:name]
      v.customize [ "modifyvm", :id, "--cpus", opennms[:cpu] ]
      v.customize [ "modifyvm", :id, "--memory", opennms[:mem] ]
      v.default_nic_type = "virtio"
    end
    config.vm.network "private_network", ip: opennms[:ip]
    config.vm.provision "common", type: "shell" do |s|
      s.path = "scripts/common-centos7.sh"
    end
    distributed = common[:distributed] ? "true" : "false"
    config.vm.provision "opennms", type: "shell" do |s|
      s.path = "scripts/opennms-centos7.sh"
      s.args = [ distributed, common[:branch], common[:postgres], common[:kafka], common[:elastic] ]
    end
  end

  config.vm.define "minion" do |config|
    config.vm.hostname = minion[:host]
    config.vm.provider "virtualbox" do |v|
      v.name = minion[:name]
      v.customize [ "modifyvm", :id, "--cpus", minion[:cpu] ]
      v.customize [ "modifyvm", :id, "--memory", minion[:mem] ]
      v.default_nic_type = "virtio"
    end
    config.vm.network "private_network", ip: minion[:ip]
    config.vm.provision "common", type: "shell" do |s|
      s.path = "scripts/common-centos7.sh"
    end
    config.vm.provision "minion", type: "shell" do |s|
      s.path = "scripts/minion-centos7.sh"
      s.args = [ common[:branch], opennms[:ip] + ":8980", common[:kafka] ]
    end
  end

  if common[:distributed] == true
    sentinels.each do |sentinel|
      config.vm.define sentinel[:id] do |config|
        config.vm.hostname = sentinel[:host]
        config.vm.provider "virtualbox" do |v|
          v.name = sentinel[:name]
          v.customize [ "modifyvm", :id, "--cpus", sentinel[:cpu] ]
          v.customize [ "modifyvm", :id, "--memory", sentinel[:mem] ]
          v.default_nic_type = "virtio"
        end
        config.vm.network "private_network", ip: sentinel[:ip]
        config.vm.provision "common", type: "shell" do |s|
          s.path = "scripts/common-centos7.sh"
        end
        config.vm.provision "opennms", type: "shell" do |s|
          s.path = "scripts/sentinel-centos7.sh"
          s.args = [ common[:branch], opennms[:ip] + ":8980", common[:kafka], common[:zookeeper] ]
        end
      end
    end
  end

  config.vm.define "test" do |config|
    config.vm.hostname = test[:host]
    config.vm.provider "virtualbox" do |v|
      v.name = test[:name]
      v.default_nic_type = "virtio"
    end
    config.vm.network "private_network", ip: test[:ip]
    config.vm.provision "common", type: "shell" do |s|
      s.path = "scripts/common-centos7.sh"
    end
  end

end

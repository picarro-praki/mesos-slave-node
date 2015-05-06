#
# Cookbook Name:: mesos-slave-node
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

# sudo knife cookbook upload mesos-slave-node
# knife bootstrap IP -j '{"namenodeip":IP, "slaveip":IP}' -x vagrant -P vagrant -r 'recipe[mesos-slave-node]'
include_recipe 'apt'

#####
# Params
# namenodeip: hadoop namenode ip
# slaveip: ip of self
#####
cluster_name = 'beehive'
zk = 'zk://10.0.3.100:2181,10.0.3.101:2181,10.0.3.102:2181/mesos'
namenode_ip = node['namenodeip']
slave_ip = node['slaveip']

raise "namenodeip not provided. Use -j '{\"namenodeip\":\"a,b.c.d\"}'" if namenode_ip.nil?
raise "slaveip not provided. Use -j '{\"slaveip\":\"a,b.c.d\"}'" if slave_ip.nil?

apt_repository 'mesosphere' do
  uri "http://repos.mesosphere.io/#{node['platform']}"
  distribution node['lsb']['codename']
  keyserver 'keyserver.ubuntu.com'
  key 'E56151BF'
  components ['main']
end

execute "apt-get-update" do
    command "apt-get -y update; apt-get -y upgrade"
end

execute "install-mesos" do
    command "apt-get --yes --force-yes install mesos"
end

service "zookeeper" do
	action :disable
end

service "mesos-master" do
	action :disable
end

bash "disable-mesos-zk" do
    code <<-EOF
    service zookeeper stop
    service mesos-master stop
    echo manual > /etc/init/zookeeper.override
    echo manual > /etc/init/mesos-master.override
EOF
end

bash 'create_zk_info' do
    code <<-EOF
        echo "#{zk}" > /etc/mesos/zk
        echo "MASTER=\`cat /etc/mesos/zk\`\nIP=#{slave_ip}\n" > /etc/default/mesos-slave
EOF
    returns [0,2]
end

execute "start_mesos_slave" do
    command "service mesos-slave restart"
end

u = user 'hduser' do
    home "/home/hduser"
      shell "/bin/bash"
    action :create
    manage_home true
end
u.run_action(:create)

group 'hadoop' do
    action :create
    members "hduser"
end


bash 'ssh_login' do
    user 'hduser'
    cwd Dir.home('hduser')
    code <<-EOF
              mkdir -p ~hduser/.ssh
              rm -f ~hduser/.ssh/id_rsa
              ssh-keygen -f ~hduser/.ssh/id_rsa -t rsa -P ""
              cat .ssh/id_rsa.pub >> .ssh/authorized_keys
EOF
end


bash 'install_hadoop' do
    code <<-EOF
        # Install hadoop 
        namenode_ip=#{namenode_ip}
        wget http://archive.cloudera.com/cdh4/one-click-install/precise/amd64/cdh4-repository_1.0_all.deb
        dpkg -i cdh4-repository_1.0_all.deb
        curl -s http://archive.cloudera.com/cdh4/ubuntu/precise/amd64/cdh/archive.key | apt-key add -
        apt-get update
        apt-get --yes --force-yes install hadoop-0.20-mapreduce-tasktracker hadoop-hdfs-datanode
        mkdir -p /var/data/hadoop/hdfs/dn /var/log/hadoop-hdfs
        chown -R hdfs:hdfs /var/data/hadoop/hdfs/dn /var/log/hadoop-hdfs
        chmod 0700 /var/data/hadoop/hdfs/dn

        sudo cp -r /etc/hadoop/conf/. /etc/hadoop/#{cluster_name}.conf
        update-alternatives --install /etc/hadoop/conf hadoop-conf /etc/hadoop/#{cluster_name}.conf 50
        update-alternatives --set hadoop-conf /etc/hadoop/#{cluster_name}.conf

        # Write core-site.xml
        cat > /etc/hadoop/#{cluster_name}.conf/core-site.xml <<EOF2
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
      <property>
            <name>fs.default.name</name>
            <value>hdfs://${namenode_ip}:9000</value>
      </property>
      <property>
            <name>hadoop.http.staticuser.user</name>
            <value>hdfs</value>
      </property>
</configuration>
EOF2

    cat  > /etc/hadoop/#{cluster_name}.conf/hdfs-site.xml <<-EOF2
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
   <property>
     <name>fs.checkpoint.dir</name>
     <value>/var/data/hadoop/hdfs/snn</value>
   </property>
   <property>
     <name>dfs.datanode.data.dir</name>
     <value>/var/data/hadoop/hdfs/dn</value>
   </property>
</configuration>
EOF2
EOF
end

service "hadoop-hdfs-datanode" do
    action :restart
end





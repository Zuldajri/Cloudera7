#!/usr/bin/env bash

LOG_FILE="/var/log/cloudera-azure-initialize.log"

EXECNAME=$0

# logs everything to the $LOG_FILE
log() {
  echo "$(date) [${EXECNAME}]: $*" >> "${LOG_FILE}"
}

#fail on any error
set -e

ClusterName=$1
key=$2
mip=$3
worker_ip=$4
HA=$5
User=$6
Password=$7
VMSIZE=$8
CLUSTERNAME=$9
NAMEPREFIX=${10}
LOCATION=${11}
TSHIRTSIZE=${12}



log "------- initialize-cloudera.sh starting -------"

log "BEGIN: master node deployments"

log "Beginning process of disabling SELinux"

log "Running as $(whoami) on $(hostname)"

# Use the Cloudera-documentation-suggested workaround
log "about to set setenforce to 0"
set +e
setenforce 0

exitcode=$?
log "Done with settiing enforce. Its exit code was $exitcode"

log "Running setenforce inline as $(setenforce 0)"

getenforce
log "Running getenforce inline as $(getenforce)"
getenforce

log "should be done logging things"


cat /etc/selinux/config > /tmp/beforeSelinux.out
log "ABOUT to replace enforcing with disabled"
sed -i 's^SELINUX=enforcing^SELINUX=disabled^g' /etc/selinux/config || true

cat /etc/selinux/config > /tmp/afterSeLinux.out
log "Done disabling selinux"


# Set up python
yum install -y epel-release >> "${LOG_FILE}" 2>&1
yum -y install python-pip >> "${LOG_FILE}" 2>&1
pip install --upgrade pip
pip install cm_client >> "${LOG_FILE}" 2>&1

cp /usr/lib/systemd/system/rngd.service /etc/systemd/system/
systemctl daemon-reload
systemctl start rngd
systemctl enable rngd

echo "-- Installing requirements for Stream Messaging Manager"
yum install -y gcc-c++ make 
curl -sL https://rpm.nodesource.com/setup_10.x | sudo -E bash - 
yum install nodejs -y
npm install forever -g 

echo "-- Configure networking"
PUBLIC_IP=`curl https://api.ipify.org/`
hostnamectl set-hostname `hostname -f`
echo "`hostname -I` `hostname`" >> /etc/hosts
sed -i "s/HOSTNAME=.*/HOSTNAME=`hostname`/" /etc/sysconfig/network
systemctl disable firewalld
systemctl stop firewalld
setenforce 0
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config


echo "-- Install CM and MariaDB"

set +e

log "Set cloudera-manager.repo to CM v7"

wget https://archive.cloudera.com/cm7/7.4.4/redhat7/yum/cloudera-manager-trial.repo -P /etc/yum.repos.d/ >> "${LOG_FILE}" 2>&1

## MariaDB 10.1
cat - >/etc/yum.repos.d/MariaDB.repo <<EOF
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF

yum clean all
rm -rf /var/cache/yum/
yum repolist

# this often fails so adding retry logic
n=0
until [ $n -ge 5 ]
do
    yum install -y cloudera-manager-daemons cloudera-manager-agent cloudera-manager-server >> "${LOG_FILE}" 2>&1 && break
    n=$((n+1))
    sleep 15s
done
if [ $n -ge 5 ]
then 
    log "yum install error, exiting..."
    log "------- initialize-cloudera-server.sh failed -------" 
    exit 1
fi

#######################################################################################################################
log "installing external DB"
sudo yum install -y MariaDB-server MariaDB-client
cat mariadb.config > /etc/my.cnf

log "--Enable and start MariaDB"
systemctl enable mariadb
systemctl start mariadb

log "-- Install JDBC connector"
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.46.tar.gz -P ~
tar zxf ~/mysql-connector-java-5.1.46.tar.gz -C ~
mkdir -p /usr/share/java/
cp ~/mysql-connector-java-5.1.46/mysql-connector-java-5.1.46-bin.jar /usr/share/java/mysql-connector-java.jar
rm -rf ~/mysql-connector-java-5.1.46*

log "-- Create DBs required by CM"
mysql -u root < create_db.sql

log "-- Secure MariaDB"
mysql -u root < secure_mariadb.sql

log "-- Prepare CM database 'scm'"
/opt/cloudera/cm/schema/scm_prepare_database.sh mysql scm scm cloudera

log "finished installing external DB"
#######################################################################################################################

## PostgreSQL see: https://www.postgresql.org/download/linux/redhat/
yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
yum install -y postgresql96
yum install -y postgresql96-server
pip install psycopg2==2.7.5 --ignore-installed

echo 'LC_ALL="en_US.UTF-8"' >> /etc/locale.conf
/usr/pgsql-9.6/bin/postgresql96-setup initdb

cat pg_hba.conf > /var/lib/pgsql/9.6/data/pg_hba.conf
cat postgresql.conf > /var/lib/pgsql/9.6/data/postgresql.conf


echo "--Enable and start pgsql"
systemctl enable postgresql-9.6
systemctl start postgresql-9.6

echo "-- Create DBs required by CM"
sudo -u postgres psql <<EOF 
CREATE DATABASE ranger;
CREATE USER ranger WITH PASSWORD 'cloudera';
GRANT ALL PRIVILEGES ON DATABASE ranger TO ranger;
CREATE DATABASE das;
CREATE USER das WITH PASSWORD 'cloudera';
GRANT ALL PRIVILEGES ON DATABASE das TO das;
EOF





log "-- Install CSDs"
# install local CSDs
mv ~/*.jar /opt/cloudera/csd/
mv /home/centos/*.jar /opt/cloudera/csd/

chown cloudera-scm:cloudera-scm /opt/cloudera/csd/*
chmod 644 /opt/cloudera/csd/*

log "-- Install local parcels"
mv ~/*.parcel ~/*.parcel.sha /opt/cloudera/parcel-repo/
mv /home/centos/*.parcel /home/centos/*.parcel.sha /opt/cloudera/parcel-repo/
chown cloudera-scm:cloudera-scm /opt/cloudera/parcel-repo/*



log "-- Enable passwordless root login via rsa key"
ssh-keygen -f ~/myRSAkey -t rsa -N ""
mkdir ~/.ssh
cat ~/myRSAkey.pub >> ~/.ssh/authorized_keys
chmod 400 ~/.ssh/authorized_keys
ssh-keyscan -H `hostname` >> ~/.ssh/known_hosts
sed -i 's/.*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
systemctl restart sshd

log "-- Start CM, it takes about 2 minutes to be ready"
systemctl start cloudera-scm-server

while [ `curl -s -X GET -u "admin:admin"  http://localhost:7180/api/version` -z ] ;
    do
    echo "waiting 10s for CM to come up..";
    sleep 10;
done

log "-- Now CM is started and the next step is to automate using the CM API"
log "END: master node deployments"


wget https://bootstrap.pypa.io/pip/2.7/get-pip.py
python ./get-pip.py
pip install --upgrade cm_client



sed -i "s/ClusterName/$CLUSTERNAME/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}default_template.json
sed -i "s/dnsNamePrefix/$NAMEPREFIX/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}default_template.json
sed -i "s/region/$LOCATION/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}default_template.json

sed -i "s/utilisateur/$User/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}create_cluster.py
sed -i "s/passe/$Password/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}create_cluster.py

python /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}create_cluster.py /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}default_template.json






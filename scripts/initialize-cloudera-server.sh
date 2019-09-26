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

set +e

log "Set cloudera-manager.repo to CM v6"
yum clean all >> "${LOG_FILE}" 2>&1
rpm --import https://archive.cloudera.com/cm6/6.3.0/redhat7/yum/RPM-GPG-KEY-cloudera >> "${LOG_FILE}" 2>&1
wget https://archive.cloudera.com/cm6/6.3.0/redhat7/yum/cloudera-manager.repo -O /etc/yum.repos.d/cloudera-manager.repo >> "${LOG_FILE}" 2>&1

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

log "-- Install CSDs"
# install local CSDs
mv ~/*.jar /opt/cloudera/csd/

wget https://archive.cloudera.com/CFM/csd/1.0.0.0/NIFI-1.9.0.1.0.0.0-90.jar -P /opt/cloudera/csd/
wget https://archive.cloudera.com/CFM/csd/1.0.0.0/NIFICA-1.9.0.1.0.0.0-90.jar -P /opt/cloudera/csd/
wget https://archive.cloudera.com/CFM/csd/1.0.0.0/NIFIREGISTRY-0.3.0.1.0.0.0-90.jar -P /opt/cloudera/csd/
wget https://archive.cloudera.com/cdsw1/1.6.0/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDH6-1.6.0.jar -P /opt/cloudera/csd/
# CSD for C5
wget https://archive.cloudera.com/cdsw1/1.6.0/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDH5-1.6.0.jar -P /opt/cloudera/csd/
wget https://archive.cloudera.com/spark2/csd/SPARK2_ON_YARN-2.4.0.cloudera1.jar -P /opt/cloudera/csd/

chown cloudera-scm:cloudera-scm /opt/cloudera/csd/*
chmod 644 /opt/cloudera/csd/*

log "-- Install local parcels"
mv ~/*.parcel ~/*.parcel.sha /opt/cloudera/parcel-repo/
chown cloudera-scm:cloudera-scm /opt/cloudera/parcel-repo/*

log "-- Install CEM Tarballs"
mkdir -p /opt/cloudera/cem
wget https://archive.cloudera.com/CEM/centos7/1.x/updates/1.0.0.0/CEM-1.0.0.0-centos7-tars-tarball.tar.gz -P /opt/cloudera/cem
tar xzf /opt/cloudera/cem/CEM-1.0.0.0-centos7-tars-tarball.tar.gz -C /opt/cloudera/cem
tar xzf /opt/cloudera/cem/CEM/centos7/1.0.0.0-54/tars/efm/efm-1.0.0.1.0.0.0-54-bin.tar.gz -C /opt/cloudera/cem
tar xzf /opt/cloudera/cem/CEM/centos7/1.0.0.0-54/tars/minifi/minifi-0.6.0.1.0.0.0-54-bin.tar.gz -C /opt/cloudera/cem
tar xzf /opt/cloudera/cem/CEM/centos7/1.0.0.0-54/tars/minifi/minifi-toolkit-0.6.0.1.0.0.0-54-bin.tar.gz -C /opt/cloudera/cem
rm -f /opt/cloudera/cem/CEM-1.0.0.0-centos7-tars-tarball.tar.gz
ln -s /opt/cloudera/cem/efm-1.0.0.1.0.0.0-54 /opt/cloudera/cem/efm
ln -s /opt/cloudera/cem/minifi-0.6.0.1.0.0.0-54 /opt/cloudera/cem/minifi
ln -s /opt/cloudera/cem/efm/bin/efm.sh /etc/init.d/efm
chown -R root:root /opt/cloudera/cem/efm-1.0.0.1.0.0.0-54
chown -R root:root /opt/cloudera/cem/minifi-0.6.0.1.0.0.0-54
chown -R root:root /opt/cloudera/cem/minifi-toolkit-0.6.0.1.0.0.0-54
rm -f /opt/cloudera/cem/efm/conf/efm.properties
cp efm.properties /opt/cloudera/cem/efm/conf
rm -f /opt/cloudera/cem/minifi/conf/bootstrap.conf
cp bootstrap.conf /opt/cloudera/cem/minifi/conf
sed -i "s/YourHostname/`hostname -f`/g" /opt/cloudera/cem/efm/conf/efm.properties
sed -i "s/YourHostname/`hostname -f`/g" /opt/cloudera/cem/minifi/conf/bootstrap.conf
/opt/cloudera/cem/minifi/bin/minifi.sh install

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


# Set up python
yum install -y epel-release >> "${LOG_FILE}" 2>&1
yum -y install python-pip >> "${LOG_FILE}" 2>&1
pip install --upgrade pip
pip install cm_client >> "${LOG_FILE}" 2>&1



sed -i "s/ClusterName/$CLUSTERNAME/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}default_template.json
sed -i "s/dnsNamePrefix/$NAMEPREFIX/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}default_template.json
sed -i "s/region/$LOCATION/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}default_template.json

sed -i "s/utilisateur/$User/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}create_cluster.py
sed -i "s/passe/$Password/g" /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}create_cluster.py

python /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}create_cluster.py /var/lib/waagent/custom-script/download/1/${TSHIRTSIZE}default_template.json

# configure and start EFM and Minifi
service efm start
#service minifi start



#original

## trap file to indicate done

#log "creating file to indicate finished"
#touch /tmp/readyFile

## Execute script to deploy Cloudera cluster
#log "BEGIN: CM deployment - starting"
#log "Parameters: $ClusterName $mip $worker_ip $VMSIZE"
#status=0
#if $HA; then
#    python cmxDeployOnIbiza.py -n "$ClusterName" -u "$User" -p "$Password" -m "$mip" -w "$worker_ip" -a -c "$cmUser" -s "$cmPassword" -v "$VMSIZE" >> "${LOG_FILE}" 2>&1
#    status=$?
#else
#    python cmxDeployOnIbiza.py -n "$ClusterName" -u "$User" -p "$Password" -m "$mip" -w "$worker_ip" -c "$cmUser" -s "$cmPassword" -v "$VMSIZE" >> "${LOG_FILE}" 2>&1
#    status=$?
#fi

#log "END: CM deployment ended with status '$status'"
#log "-- At this point you can login into Cloudera Manager host on port 7180 and follow the deployment of the cluster"

#if [ $status -eq 0 ]
#then
#    log "------- initialize-cloudera-server.sh succeeded -------" 
#    # always `exit 0` on success
#    exit 0

#else
#    log "------- initialize-cloudera-server.sh failed -------" 
#    exit 1
#fi

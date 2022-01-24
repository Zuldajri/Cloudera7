#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# 
# See the License for the specific language governing permissions and
# limitations under the License.
# Usage: bootstrap-cloudera-1.0.sh {clusterName} {managment_node} {cluster_nodes} {isHA} {sshUserName} [{sshPassword}]

LOG_FILE="/var/log/cloudera-azure-initialize.log"

# Put the command line parameters into named variables
EXECNAME=$0
MASTERIP=$1
WORKERIP=$2
NAMEPREFIX=$3
NAMESUFFIX=$4
MASTERNODES=$5
DATANODES=$6
ADMINUSER=$7
HA=$8
PASSWORD=$9
INSTALLCDH=${10}
VMSIZE=${11}
PRIVATEKEY=${12}
CLUSTERNAME=${13}
LOCATION=${14}
TSHIRTSIZE=${15}

CLUSTERNAME=$NAMEPREFIX

# logs everything to the $LOG_FILE
log() {
  echo "$(date) [${EXECNAME}]: $*" >> "${LOG_FILE}"
}


log "------- prep-cloudera.sh starting -------"

log "Generate private keys for use" 
echo $(date) " - Generating Private keys for Cloudera Installation"

runuser -l $ADMINUSER -c "echo -e \"$PRIVATEKEY\" > ~/.ssh/id_rsa"
runuser -l $ADMINUSER -c "chmod 600 ~/.ssh/id_rsa*"


log "set private key"
#use the key from the key vault as the SSH private key
chmod 600 /home/"$ADMINUSER"/.ssh/id_rsa
chown "$ADMINUSER" /home/"$ADMINUSER"/.ssh/id_rsa

mkdir ~/.ssh

cat /home/"${ADMINUSER}"/.ssh/authorized_keys >> ~/.ssh/authorized_keys
cat /home/"${ADMINUSER}"/.ssh/id_rsa >> ~/.ssh/id_rsa
chmod 400 ~/.ssh/authorized_keys
chmod 400 ~/.ssh/id_rsa
ssh-keyscan -H `hostname` >> ~/.ssh/known_hosts
sed -i 's/.*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
systemctl restart sshd

eval `ssh-agent`
ssh-add ~/.ssh/id_rsa

log "install Docker"
sudo yum update -y --exclude=WALinuxAgent
sudo yum install git -y
sudo yum install ca-certificates curl gnupg  -y
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce docker-ce-cli containerd.io -y
sudo systemctl start docker

log "download repo"
git clone https://github.com/cloudera-labs/cloudera-deploy.git
cd cloudera-deploy

chmod +x quickstart.sh

log "------- prep-cloudera.sh succeeded -------"

# always `exit 0` on success
exit 0

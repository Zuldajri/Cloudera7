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
LICENSE=${15}
ADMIN_PASSWORD=${16}
TSHIRTSIZE=${17}

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

log "------- set the license -------"
mkdir ~/.cdp
touch ~/.cdp/my_cloudera_license_2021.txt
echo echo -e \"$LICENSE\" > ~/.cdp/my_cloudera_license_2021.txt



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

sudo yum update -y --exclude=WALinuxAgent
sudo yum install git -y
sudo yum install ca-certificates curl gnupg  -y
sudo yum install -y yum-utils


log "download repo"
git clone https://github.com/cloudera-labs/cloudera-deploy.git
cd cloudera-deploy

chmod +x quickstart.sh

sudo yum install -y python36-devel git curl which bash gcc sshpass

# 21 or later required otherwise ansible fails because of setuptools_rust. Higher than 21.0.1 gives warnings due to https://github.com/pypa/pip/issues/5599
sudo python3 -m pip install pip==21.0.1 

pip3 install setuptools
pip3 install ansible

ansible-galaxy collection install --force git+https://github.com/cloudera-labs/cloudera.cluster.git
ansible-galaxy collection install --force git+https://github.com/cloudera-labs/cloudera.cloud.git
ansible-galaxy collection install --force git+https://github.com/cloudera-labs/cloudera.exe.git

git clone https://github.com/cloudera-labs/cldr-runner runner
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc;  echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/azure-cli.repo;  sudo yum install -y azure-cli;  pip3 install --no-cache-dir -r runner/payload/deps/python_azure.txt;


ansible-galaxy install -r runner/payload/deps/ansible.yml
pip3 install -r runner/payload/deps/python_base.txt

tee -a ansible.cfg << EOF
[defaults]
inventory=inventory
callback_whitelist = ansible.posix.profile_tasks
host_key_checking = False
gathering = smart
pipelining = True
deprecation_warnings=False
[ssh_connection]
retries = 10
EOF

echo "Example command: "
echo 'export ANSIBLE_LOG_PATH=~/ansible.log; ansible-playbook main.yml -e "definition_path=examples/sandbox"  --ask-pass -vv -i examples/sandbox/inventory_static.ini'

cat <<SSH_HOST_KEY
  *** WARNING: SSH Host Key Checking is disabled by default. ***
  This setting may not be suitable for Production deployments. 
  If you wish to enable host key checking, please set the Ansible environment
  variable, ANSIBLE_HOST_KEY_CHECKING, to True before execution. See the project 
  documentation for further details on managing SSH host key checking.
SSH_HOST_KEY

rm -rf /var/lib/waagent/custom-script/download/1/cloudera-deploy/examples/sandbox/definition.yml
wget https://raw.githubusercontent.com/Zuldajri/Cloudera7/master/scripts/definition.yml -O /var/lib/waagent/custom-script/download/1/cloudera-deploy/examples/sandbox/definition.yml

rm -rf /var/lib/waagent/custom-script/download/1/cloudera-deploy/roles/cloudera_deploy/defaults/basic_cluster.yml
wget https://raw.githubusercontent.com/Zuldajri/Cloudera7/master/scripts/basic_cluster.yml -O /var/lib/waagent/custom-script/download/1/cloudera-deploy/roles/cloudera_deploy/defaults/basic_cluster.yml

rm -rf /var/lib/waagent/custom-script/download/1/cloudera-deploy/profile.yml
wget https://raw.githubusercontent.com/Zuldajri/Cloudera7/master/scripts/profile.yml -O /var/lib/waagent/custom-script/download/1/cloudera-deploy/profile.yml
sudo sed -i "s/MYSECRETPASSWORD/$ADMIN_PASSWORD/g" /var/lib/waagent/custom-script/download/1/cloudera-deploy/profile.yml

wget https://raw.githubusercontent.com/Zuldajri/Cloudera7/master/scripts/inventory_static.ini -O /var/lib/waagent/custom-script/download/1/cloudera-deploy/inventory_static.ini
sudo sed -i "s/NAMEPREFIX/$NAMEPREFIX/g" /var/lib/waagent/custom-script/download/1/cloudera-deploy/inventory_static.ini
sudo sed -i "s/ADMINUSER/$ADMINUSER/g" /var/lib/waagent/custom-script/download/1/cloudera-deploy/inventory_static.ini
sudo sed -i "s/LOCATION/$LOCATION/g" /var/lib/waagent/custom-script/download/1/cloudera-deploy/inventory_static.ini



log "------- prep-cloudera.sh succeeded -------"

# always `exit 0` on success
exit 0

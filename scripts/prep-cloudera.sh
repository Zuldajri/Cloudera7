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
LICENSE="${15}"
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
echo $LICENSE > ~/.cdp/my_cloudera_license_2021.txt



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

set -e

IMAGE_NAME="ghcr.io/cloudera-labs/cldr-runner"
provider=${provider:-full}
IMAGE_VER=${image_ver:-latest}
IMAGE_TAG=${provider}-${IMAGE_VER}
IMAGE_FULL_NAME=${IMAGE_NAME}:${IMAGE_TAG}
CONTAINER_NAME=cloudera-deploy

# dir of script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )";
# parent dir of that dir
PARENT_DIRECTORY="${DIR%/*}"

PROJECT_DIR=${1:-${PARENT_DIRECTORY}}

echo "Checking if Docker is running..."
{ docker info >/dev/null 2>&1; echo "Docker OK"; } || { echo "Docker is required and does not seem to be running - please start Docker and retry" ; exit 1; }

echo "Checking for updated execution container image '${IMAGE_FULL_NAME}'"
docker pull "${IMAGE_FULL_NAME}"

echo "Ensuring default credential paths are available in calling using profile for mounting to execution environment"
for thisdir in ".aws" ".ssh" ".cdp" ".azure" ".kube" ".config" ".config/cloudera-deploy/log" ".config/cloudera-deploy/profiles"
do
  mkdir -p "${HOME}"/$thisdir
done

echo "Ensure Default profile is present"
if [ ! -f "${HOME}"/.config/cloudera-deploy/profiles/default ]; then
  if [ ! -f "${DIR}/profile.yml" ]; then
    curl "https://raw.githubusercontent.com/cloudera-labs/cloudera-deploy/main/profile.yml" -o "${HOME}"/.config/cloudera-deploy/profiles/default
  else
    cp "${DIR}/profile.yml" "${HOME}"/.config/cloudera-deploy/profiles/default
  fi
fi

# If CLDR_COLLECTION_PATH is set, the default version in the container will be removed and this path added to the Ansible Collection path
# The path supplied must be relative to PROJECT_DIR, e.g. ansible_dev/collections
if [ -n "${CLDR_COLLECTION_PATH}" ]; then
  echo "Path to custom Cloudera Collection supplied as ${CLDR_COLLECTION_PATH}, adding to Ansible Collection path"
  ANSIBLE_COLLECTIONS_PATH="/opt/cldr-runner/collections:/runner/project/${CLDR_COLLECTION_PATH}"
  QUICKSTART_PROMPT='Quickstart? Run this command -- ansible-playbook project/cloudera-deploy/main.yml -e "definition_path=examples/sandbox" -t run,default_cluster'
else
  echo "Custom Cloudera Collection path not found"
  ANSIBLE_COLLECTIONS_PATH="/opt/cldr-runner/collections"
  QUICKSTART_PROMPT='Quickstart? Run this command -- ansible-playbook /opt/cloudera-deploy/main.yml -e "definition_path=examples/sandbox" -t run,default_cluster'
fi

# If CLDR_PYTHON_PATH is set, that will be set as the system PYTHONPATH variable in the container
# This is a good way to point at any custom python source code in your /runner/project mount, including CDPY
# The path supplied must be a full path to the source root for each source included, e.g /runner/project/cdpy/src
if [ -n "${CLDR_PYTHON_PATH}" ]; then
  echo "Path to custom Python sourcecode supplied as ${CLDR_PYTHON_PATH}, setting as System PYTHONPATH"
  PYTHONPATH="${CLDR_PYTHON_PATH}"
else
  echo "'CLDR_PYTHON_PATH' is not set, skipping setup of PYTHONPATH in execution container"
fi

echo "Checking if ssh-agent is running..."
if pgrep -x "ssh-agent" >/dev/null
then
    echo "ssh-agent OK"
else
    echo "ssh-agent is stopped, please start it by running: eval `ssh-agent -s` "
    #eval `ssh-agent -s` 
fi

echo "Checking OS"
if [ ! -f "/run/host-services/ssh-auth.sock" ]; 
then
   if [ -n "${SSH_AUTH_SOCK}" ];
   then 
        SSH_AUTH_SOCK=${SSH_AUTH_SOCK}
   else
	echo "ERROR: SSH_AUTH_SOCK is empty or not set, unable to proceed. Exiting"
	exit 1
   fi
else
	SSH_AUTH_SOCK=${SSH_AUTH_SOCK}
fi

echo "SSH authentication for container taken from ${SSH_AUTH_SOCK}"

if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    if [ "$(docker ps -aq -f status=exited -f name=${CONTAINER_NAME})" ]; then
        # cleanup if exited
        echo "Attempting removal of exited execution container named '${CONTAINER_NAME}'"
        docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || echo "Execution container '${CONTAINER_NAME}' already removed, continuing..."
    fi
    # create new container if not running
    echo "Creating new execution container named '${CONTAINER_NAME}' with '${PROJECT_DIR}' mounted to /runner/project from image '${IMAGE_FULL_NAME}'"
    docker run -td \
      --detach-keys="ctrl-@" \
      -v "${PROJECT_DIR}":/runner/project \
      --mount type=bind,src="${SSH_AUTH_SOCK}",target=/run/host-services/ssh-auth.sock \
      -e SSH_AUTH_SOCK="/run/host-services/ssh-auth.sock" \
      -e ANSIBLE_LOG_PATH="/home/runner/.config/cloudera-deploy/log/${CLDR_BUILD_VER:-latest}-$(date +%F_%H%M%S)" \
      -e ANSIBLE_INVENTORY="inventory" \
      -e ANSIBLE_CALLBACK_WHITELIST="ansible.posix.profile_tasks" \
      -e ANSIBLE_GATHERING="smart" \
      -e ANSIBLE_DEPRECATION_WARNINGS=false \
      -e ANSIBLE_HOST_KEY_CHECKING=false \
      -e ANSIBLE_SSH_RETRIES=10 \
      -e ANSIBLE_COLLECTIONS_PATH="${ANSIBLE_COLLECTIONS_PATH}" \
      -e PYTHONPATH="${PYTHONPATH}" \
      -e ANSIBLE_ROLES_PATH="/opt/cldr-runner/roles" \
      -e AWS_DEFAULT_OUTPUT="json" \
      --mount "type=bind,source=${HOME}/.aws,target=/home/runner/.aws" \
      --mount "type=bind,source=${HOME}/.config,target=/home/runner/.config" \
      --mount "type=bind,source=${HOME}/.ssh,target=/home/runner/.ssh" \
      --mount "type=bind,source=${HOME}/.cdp,target=/home/runner/.cdp" \
      --mount "type=bind,source=${HOME}/.azure,target=/home/runner/.azure" \
      --mount "type=bind,source=${HOME}/.kube,target=/home/runner/.kube" \
      --network="host" \
      --name "${CONTAINER_NAME}" \
      "${IMAGE_FULL_NAME}" \
      /usr/bin/env bash

    echo "Installing the cloudera-deploy project to the execution container '${CONTAINER_NAME}'"
    docker exec -td "${CONTAINER_NAME}" /usr/bin/env git clone https://github.com/cloudera-labs/cloudera-deploy.git /opt/cloudera-deploy --depth 1
    
    if [ -n "${CLDR_COLLECTION_PATH}" ]; then
      docker exec -td "${CONTAINER_NAME}" /usr/bin/env rm -rf /opt/cldr-runner/collections/ansible_collections/cloudera
    fi
    if [ -n "${CLDR_PYTHON_PATH}" ]; then
      docker exec -td "${CONTAINER_NAME}" pip uninstall -y cdpy
    fi
fi

cat <<SSH_HOST_KEY
  *** WARNING: SSH Host Key Checking is disabled by default. ***
  This setting may not be suitable for Production deployments. 
  If you wish to enable host key checking, please set the Ansible environment
  variable, ANSIBLE_HOST_KEY_CHECKING, to True before execution. See the project 
  documentation for further details on managing SSH host key checking.
SSH_HOST_KEY






log "------- prep-cloudera.sh succeeded -------"

# always `exit 0` on success
exit 0

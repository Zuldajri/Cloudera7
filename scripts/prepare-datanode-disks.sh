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

LOG_FILE="/var/log/cloudera-azure-initialize.log"

# manually set EXECNAME because this file is called from another script and it $0 contains a 
# relevant path
EXECNAME="prepare-datanode-disks.sh"

# logs everything to the $LOG_FILE
log() {
  echo "$(date) [${EXECNAME}]: $*" >> "${LOG_FILE}"
}

cat > inputs2.sh << 'END'

mountDriveForLogCloudera()
{
  dirname=/log
  drivename=$1
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
  mkdir $dirname
  mount -o noatime,barrier=1 -t ext4 $drivename $dirname
  UUID=`sudo lsblk -no UUID $drivename`
  echo "UUID=$UUID   $dirname    ext4   defaults,noatime,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
  mkdir /log/cloudera
  ln -s /log/cloudera /opt/cloudera
}

mountDriveForQJN1()
{
  dirname=/dfs1/
  drivename=$1
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
  mkdir /dfs1
  mount -o noatime,barrier=1 -t ext4 $drivename $dirname
  UUID=`sudo lsblk -no UUID $drivename`
  echo "UUID=$UUID   $dirname    ext4   defaults,noatime,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
}

mountDriveForQJN2()
{
  dirname=/dfs2/
  drivename=$1
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
  mkdir /dfs2
  mount -o noatime,barrier=1 -t ext4 $drivename $dirname
  UUID=`sudo lsblk -no UUID $drivename`
  echo "UUID=$UUID   $dirname    ext4   defaults,noatime,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
}

mountDriveForQJN3()
{
  dirname=/dfs3/
  drivename=$1
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
  mkdir /dfs3
  mount -o noatime,barrier=1 -t ext4 $drivename $dirname
  UUID=`sudo lsblk -no UUID $drivename`
  echo "UUID=$UUID   $dirname    ext4   defaults,noatime,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
}

mountDriveForQJN4()
{
  dirname=/dfs4/
  drivename=$1
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
  mkdir /dfs4
  mount -o noatime,barrier=1 -t ext4 $drivename $dirname
  UUID=`sudo lsblk -no UUID $drivename`
  echo "UUID=$UUID   $dirname    ext4   defaults,noatime,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
}

mountDriveForQJN5()
{
  dirname=/dfs5/
  drivename=$1
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
  mkdir /dfs5
  mount -o noatime,barrier=1 -t ext4 $drivename $dirname
  UUID=`sudo lsblk -no UUID $drivename`
  echo "UUID=$UUID   $dirname    ext4   defaults,noatime,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
}

mountDriveForQJN6()
{
  dirname=/dfs6/
  drivename=$1
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
  mkdir /dfs6
  mount -o noatime,barrier=1 -t ext4 $drivename $dirname
  UUID=`sudo lsblk -no UUID $drivename`
  echo "UUID=$UUID   $dirname    ext4   defaults,noatime,discard,barrier=0 0 1" | sudo tee -a /etc/fstab
}

prepare_unmounted_volumes()
{
  # Each line contains an entry like /dev/<device name>
  MOUNTED_VOLUMES=$(df -h | grep -o -E "^/dev/[^[:space:]]*")
  
  # Each line contains an entry like <device name> (no /dev/ prefix)
  # (This awk script prints the last field of every line with line number
  # greater than 2.)
  ALL_PARTITIONS=$(awk 'FNR > 2 {print $NF}' /proc/partitions)
  COUNTER=0
  for part in $ALL_PARTITIONS; do
    # If this partition does not end with a number (likely a partition of a
    # mounted volume), is not equivalent to the alphabetic portion of another
    # partition with digits at the end (likely a volume that has already been
    # mounted), and is not contained in $MOUNTED_VOLUMES
    if [[ ! ${part} =~ [0-9]$ && ! ${ALL_PARTITIONS} =~ $part[0-9] && $MOUNTED_VOLUMES != *$part* ]];then
      echo ${part}
      if [[ ${COUNTER} == 0 ]]; then
        mountDriveForLogCloudera "/dev/$part"
      elif [[ ${COUNTER} == 1 ]]; then
        mountDriveForQJN1 "/dev/$part"
      elif [[ ${COUNTER} == 2 ]]; then
        mountDriveForQJN2 "/dev/$part"
      elif [[ ${COUNTER} == 3 ]]; then
        mountDriveForQJN3 "/dev/$part"
      elif [[ ${COUNTER} == 4 ]]; then
        mountDriveForQJN4 "/dev/$part"
      elif [[ ${COUNTER} == 5 ]]; then
        mountDriveForQJN5 "/dev/$part"
      elif [[ ${COUNTER} == 6 ]]; then
        mountDriveForQJN6 "/dev/$part"
      else prepare_disk "/data$COUNTER" "/dev/$part"
      fi
      COUNTER=$(($COUNTER+1))
    fi
  done
  wait # for all the background prepare_disk function calls to complete
}

# This function was lifted from the file prepare_all_disks.sh in the Whirr project
# It's safe to invoke this function in parallel with different arguments because
# the append operation is atomic when the size of the appended string is <1KB. See:
# http://www.notthewizard.com/2014/06/17/are-files-appends-really-atomic/
prepare_disk()
{
  mount=$1
  device=$2
  
  FS=ext4
  FS_OPTS="-E lazy_itable_init=1"
  
  which mkfs.$FS
  # Fall back to ext3
  if [[ $? -ne 0 ]]; then
    FS=ext3
    FS_OPTS=""
  fi
  
  # is device mounted?
  mount | grep -q "${device}"
  if [ $? == 0 ]; then
    echo "$device is mounted"
  else
    echo "Warning: ERASING CONTENTS OF $device"
    mkfs.$FS -F $FS_OPTS $device -m 0
    
    # If $FS is ext3 or ext4, then run tune2fs -i 0 -c 0 to disable fsck checks for data volumes
    
    if [ $FS = "ext3" -o $FS = "ext4" ]; then
    /sbin/tune2fs -i0 -c0 ${device}
    fi
    
    echo "Mounting $device on $mount"
    if [ ! -e "${mount}" ]; then
      mkdir "${mount}"
    fi
    # gather the UUID for the specific device
    
    blockid=$(/sbin/blkid|grep ${device}|awk '{print $2}'|awk -F\= '{print $2}'|sed -e"s/\"//g")
    
    #mount -o defaults,noatime "${device}" "${mount}"
    
    # Set up the blkid for device entry in /etc/fstab
    
    echo "UUID=${blockid} $mount $FS defaults,noatime,discard,barrier=0 0 0" >> /etc/fstab
    mount ${mount}
    
  fi
}

END

log "------- prepare-datanode-disks.sh starting -------"

sudo bash -c "source ./inputs2.sh; prepare_unmounted_volumes"

log "------- prepare-datanode-disks.sh succeeded -------"
 
# always `exit 0` on success
exit 0

#!/bin/bash -xe

#### start universal functions
function base
{

  # variables
  export LOCALIP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  export INSTANCEID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  export SPLUNK_USER=splunk
  export SPLUNK_BIN=/opt/splunk/bin/splunk
  export SPLUNK_HOME=/opt/splunk

  # make cloud-init output log readable by root only to protect sensitive parameter values
  chmod 600 /var/log/cloud-init-output.log

  #- Newer versions of the Splunk AMI do not come with Splunk pre-installed.  Instead Splunk 
  #- is installed via ansible as part of cloud-init.  The following code (line 23 & 24) is 
  #- needed to ensure the ansible code is ran prior to the remainder of this script. Without 
  #- explicitly executing ansible first, the configuration in this user_data.sh script tries 
  #- (and fails) to execute as there isn't a Splunk deployment to configure.

  # run the ansible code 
  (cd /opt/splunk-ansible && time sudo -u ec2-user -E -S bash -c "SPLUNK_BUILD_URL=/tmp/splunk.tgz SPLUNK_ENABLE_SERVICE=true  SPLUNK_PASSWORD=SPLUNK-$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id) ansible-playbook -i inventory/environ.py site.yml")

  # setup auth with user-selected admin password
  mv $SPLUNK_HOME/etc/passwd $SPLUNK_HOME/etc/passwd.bak
  cat >> $SPLUNK_HOME/etc/system/local/user-seed.conf << end
  [user_info]
  USERNAME = admin
  PASSWORD = $ADMIN_PASSWORD
end

  sed -i '/guid/d' $SPLUNK_HOME/etc/instance.cfg
  touch $SPLUNK_HOME/etc/.ui_login

  # restart Splunk for admin password update
  $SPLUNK_BIN restart
}

function restart_signal
{

  # restart splunk
  $SPLUNK_BIN restart

  # communicate back to CloudFormation the status of the instance creation
  /opt/aws/bin/cfn-signal -e $? --stack $STACK_NAME --resource $RESOURCE --region $AWS_REGION

  # disable splunk user login
  usermod --expiredate 1 splunk
}

#### end universal config

#####
#### start role-specific functions
#####

###
# setup nvme drives for i3 indexers
function nvme_setup
{
  # first, determine the instance type.
  ec2_type=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)

  # this script is intended to run on i3* instance types.
  if [[ "$ec2_type" != *"i3"* ]]
  then
    return 0
  fi

  # find the attached nvme drives.  lsblk could work here, but utilizing the nvme-list utility due to
  # json formatting and simpler parsing.  install the nvme-cli and jq packages to accomplish this.
  yum -y install nvme-cli jq >/dev/null

  # save the nvme drive information to a temp file for parsing
  nvme list --output-format=json > /tmp/nvme_drive.json

  # declare the nvme device array
  declare -a nvme_devices
  unset nvme_devices

  for nvme_device in $(jq '.Devices[] | .DevicePath' /tmp/nvme_drive.json)
  do
    # test to ensure that the storage device is instance storage.  in testing, I have
    # seen EBS volues show as NVME.  this logic will ensure attached EBS devices are not
    # added to the nvme raid0
    nvme_model_type=$(jq -r '.Devices[] | select(.DevicePath=='$nvme_device') | .ModelNumber' /tmp/nvme_drive.json)
    if [[ $nvme_model_type = *"NVMe Instance Storage"* ]]
    then
      # unfortunate 'hack' here to remove the quotes from the device name.  without them, the jq lookup
      # will fail in the previous step.  however, they need to be removed for the md raid creation later.
      # additionally, since there needs to be a space between device names for the md create, convert
      # quotes to spaces, and remove leading space.  this leaves "$nvme_device " (note trailing space)
      # stored in the array.  this will allow for simply using the contents of the array as an argument for
      # building the raid0 device
      nvme_device=$(echo $nvme_device|sed 's/"/ /g'| sed 's/^ //g')

      # save device list in nvme_devices array
      nvme_devices+=("$nvme_device")
    else
      # if the nvme model type is not instance storage, continue to the next iteration of the loop
      continue
    fi
  done

  # name of the raid device to create
  raid_device="/dev/md0"

  # mount point of the raid device
  raid_mount="/opt/splunk"

  # make directory for mount point
  mkdir -p $raid_mount

  # create the raid device
  mdadm --create $raid_device --level=raid0 --raid-devices=${#nvme_devices[@]} ${nvme_devices[@]}

  # create filesystem on raid device
  if [ ${#nvme_devices[@]} -eq 1 ]
   then
      discardOption=""
    else
      discardOption="-E nodiscard"
  fi

  mkfs.ext4 -m 2 -F -F ${discardOption} $raid_device

  # add entry to fstab for mounting on reboot
  echo "$raid_device $raid_mount auto defaults,nofail,noatime 0 2" >>/etc/fstab

  # mount device
  mount $raid_device

}

###
# Splunk Cluster Manager / License Manager
###
function splunk_cm
{
  # execute base install and configuration
  base

  #export RESOURCE="SplunkCM"
  printf '%s\t%s\n' "$LOCALIP" 'splunklicense' >> /etc/hosts
  hostname splunklicense

  #- for the CM, we can't reference CM_PRIVATEIP in the CloudFormation UserData like
  #- we do in the other resources because the CM hasn't been created yet.  To keep the
  #- syntax consistent across each resource in user_data.sh, export $CM_PRIVATEIP to
  #- the CM's local ip address
  export CM_PRIVATEIP=$LOCALIP

  # Install license from metadata.
  if [ $INSTALL_LICENSE = 1 ]; then
    mkdir -p $SPLUNK_HOME/etc/licenses/enterprise/
    mv /tmp/splunk.license $SPLUNK_HOME/etc/licenses/enterprise/splunk.license
    chown -R $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/licenses/enterprise
    #/opt/aws/bin/cfn-init -v --stack $STACK_NAME --resource $RESOURCE --region $AWS_REGION
  fi

  # Increase splunkweb connection timeout with splunkd
  mkdir -p $SPLUNK_HOME/etc/apps/base-autogenerated/local
  cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/web.conf <<end
  [settings]
  splunkdConnectionTimeout = 300
end

 # Forward to indexer cluster using indexer discovery\n",
 cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/outputs.conf <<end
  # Turn off indexing
  [indexAndForward]
  index = false

  [tcpout]
  defaultGroup = indexer_cluster_peers
  forwardedindex.filter.disable = true
  indexAndForward = false

  [tcpout:indexer_cluster_peers]
  indexerDiscovery = cluster_master

  [indexer_discovery:cluster_master]
  pass4SymmKey = $SYMMKEY
  master_uri = https://127.0.0.1:8089
end

  chown -R $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/apps/base-autogenerated
  $SPLUNK_BIN restart
  # sleep 20 seconds to make sure Splunk has restarted before applying the configuration
  sleep 20

  # log in to splunk to execute several commands without requiring -auth
  sudo -u $SPLUNK_USER $SPLUNK_BIN login -auth admin:$ADMIN_PASSWORD

  # create the indexer cluster
  sudo -u $SPLUNK_USER $SPLUNK_BIN edit cluster-config -mode master -multisite true \
  -replication_factor $REPFACTOR -available_sites $SITELIST -site site1 \
  -site_replication_factor origin:1,total:$REPFACTOR -site_search_factor \
  origin:1,total:$SEARCHFACTOR -secret $SPLUNK_CLUSTER_SECRET -cluster_label SplunkIndexersASG


  # Configure indexer discovery
  cat >>$SPLUNK_HOME/etc/system/local/server.conf <<end

  [indexer_discovery]
  pass4SymmKey = $SYMMKEY
  indexerWeightByDiskCapacity = true
end
  chown $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/system/local/server.conf

  # generate the config file and HEC token
  sudo -u $SPLUNK_USER $SPLUNK_BIN http-event-collector enable \
  -uri https://localhost:8089

  sudo -u $SPLUNK_USER $SPLUNK_BIN http-event-collector create default-token \
  -uri https://localhost:8089 > /tmp/token
  TOKEN=`sed -n 's/\\ttoken=//p' /tmp/token` && rm /tmp/token

  # place generated config into master-apps
  mkdir -p $SPLUNK_HOME/etc/master-apps/peer-base-autogenerated/local
  mv $SPLUNK_HOME/etc/apps/splunk_httpinput/local/inputs.conf $SPLUNK_HOME/etc/master-apps/peer-base-autogenerated/local

  # peer config 2: enable splunk tcp input
  cat >>$SPLUNK_HOME/etc/master-apps/peer-base-autogenerated/local/inputs.conf <<end
  [splunktcp://9997]
  disabled=0
end

  # Configure smartstore as a configuration in a bundle.

  mkdir -p $SPLUNK_HOME/etc/master-apps/_cluster/local/
  touch $SPLUNK_HOME/etc/master-apps/_cluster/local/indexes.conf

  cat >>$SPLUNK_HOME/etc/master-apps/_cluster/local/indexes.conf <<end
  [default]
  repFactor = auto
  remotePath = volume:remote_store/splunk_db/$_index_name
  coldPath=$SPLUNK_DB/$_index_name/colddb
  thawedPath=$SPLUNK_DB/$_index_name/thaweddb

  [volume:remote_store]
  storageType = remote

  path = s3://$SMARTSTORE_BUCKET
  remote.s3.encryption = sse-s3
end

  chown $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/master-apps/_cluster/local/indexes.conf
  restart_signal

  # signal with the generated HEC to show on cloudformation outputs section
  /opt/aws/bin/cfn-signal -e 0 -i token -d $TOKEN $SplunkCMWaitHandle

}

function splunk_indexer
{
  #- run through setting up nvme raid device.
  #- if the indexer is not an i3, the function immediately exits and continues to base config as normal
  nvme_setup

  #- execute base install and configuration
  base

  export INSTANCE_MAC_ADDR=$(curl -s http://169.254.169.254/latest/meta-data/mac)
  export INSTANCE_SUBNET_ID=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$INSTANCE_MAC_ADDR/subnet-id)
  export RESOURCE="SplunkIndexerNodesASG"

  #- configure smartstore as if it were a bundle already pushed by the CM.

  mkdir -p $SPLUNK_HOME/etc/slave-apps/_cluster/local
  touch $SPLUNK_HOME/etc/slave-apps/_cluster/local/indexes.conf

  cat >> $SPLUNK_HOME/etc/slave-apps/_cluster/local/indexes.conf << end
  [default]
  repFactor = auto
  remotePath = volume:remote_store/splunk_db/$_index_name
  coldPath=$SPLUNK_DB/$_index_name/colddb
  thawedPath=$SPLUNK_DB/$_index_name/thaweddb
end

  cat >>$SPLUNK_HOME/etc/slave-apps/_cluster/local/indexes.conf <<end

  [volume:remote_store]
  storageType = remote
  path = s3://$SMARTSTORE_BUCKET
  remote.s3.encryption = sse-s3
end

  chown -R splunk:splunk $SPLUNK_HOME/etc/slave-apps/_cluster/
  $SPLUNK_BIN restart


  # set splunk server name to local hostname.
  sudo -u $SPLUNK_USER $SPLUNK_BIN set servername $HOSTNAME -auth admin:$ADMIN_PASSWORD

  # Increase splunkweb connection timeout with splunkd"
  mkdir -p $SPLUNK_HOME/etc/apps/base-autogenerated/local

  cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/web.conf <<end
  [settings]
  splunkdConnectionTimeout = 300
end
  # Configure some SHC parameters
  cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/server.conf <<end
  [shclustering]
  register_replication_address = $LOCALIP
end

  # Configure instance as license slave
  cat >>$SPLUNK_HOME/etc/system/local/server.conf <<end
  [license]
  master_uri = https://$CM_PRIVATEIP:8089
end

  chown -R $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/apps/base-autogenerated

  case $INSTANCE_SUBNET_ID in
    "$SUBNET1_ID")
      site=site1
    ;;
    "$SUBNET2_ID")
      site=site2
    ;;
    "$SUBNET3_ID")
      site=site3
    ;;
    *)
      echo "Unexpected subnet id"
      exit 1
  esac


  # sleep to ensure splunkd is up before modifying cluster config
  sleep 10

  sudo -u $SPLUNK_USER $SPLUNK_BIN edit cluster-config -mode slave \
    -site $site \
    -manager_uri https://$CM_PRIVATEIP:8089 \
    -auth admin:$ADMIN_PASSWORD \
    -replication_port 9887 \
    -secret $SPLUNK_CLUSTER_SECRET

  restart_signal
}

function splunk_cluster_sh
{

  # the splunk search head cluster in quickstart is pre-defined with 3 nodes.
  # verify that the argument passed is 1, 2, or 3

  if [[ "$1" =~ ^[1-3]$ ]]
  then
      # execute base install and configuration
      base

      # search head number is the argument passed.  1 = SH1, 2 = SH2, etc.
      num=$1

      # if this is a 3AZ deployment, place the third search head in site3.
      # if not, place the third search head in site1.
      # in all cases searchhead1 is site1, and searchhead2 is site2

      if [ $THREEAZ -eq 0 ] && [ $num -eq 3 ]
      then
        sitenum="site1"
      else
        sitenum="site$num"
      fi

      #export RESOURCE="SplunkSHCMember$num"

      printf '%s\t%s\n' \"$LOCALIP\" \"splunksearch-$num\" >> /etc/hosts
      hostname "splunksearch-$num"

      # set splunk servername
      sudo -u $SPLUNK_USER $SPLUNK_BIN set servername SHC$num

      # Increase splunkweb connection timeout with splunkd
      cat >$SPLUNK_HOME/etc/system/local/web.conf <<end
      [settings]
      splunkdConnectionTimeout = 300
end
      # Configure some SHC parameters
      cat >>$SPLUNK_HOME/etc/system/local/server.conf <<end
    [shclustering]
    register_replication_address = $LOCALIP
end
      chown -R $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/system/local
      $SPLUNK_BIN restart

      #- sleep 20 seconds to make sure Splunk has restarted before applying the configuration
      sleep 20

      #- log in to splunk to execute several commands without requiring -auth
      sudo -u $SPLUNK_USER $SPLUNK_BIN login -auth admin:$ADMIN_PASSWORD

      sudo -u $SPLUNK_USER $SPLUNK_BIN edit licenser-localslave \
      -master_uri https://$CM_PRIVATEIP:8089

      #- configure searchhead cluster
      #echo "### setup splunk search head cluster"
      #echo "### sudo -u $SPLUNK_USER $SPLUNK_BIN init shcluster-config -mgmt_uri https://$LOCALIP:8089 -replication_port 8090 -replication_factor $SH_REPLICATION_FACTOR -conf_deploy_fetch_url https://$SH_DEPLOYER_IP:8089 \ -shcluster_label SplunkSHC -secret $SPLUNK_CLUSTER_SECRET"

      sudo -u $SPLUNK_USER $SPLUNK_BIN init shcluster-config \
      -auth admin:$ADMIN_PASSWORD \
      -mgmt_uri https://$LOCALIP:8089 \
      -replication_port 8090 \
      -replication_factor $SH_REPLICATION_FACTOR \
      -conf_deploy_fetch_url https://$SH_DEPLOYER_IP:8089 \
      -shcluster_label SplunkSHC\
      -secret $SPLUNK_CLUSTER_SECRET

      $SPLUNK_BIN restart
      sleep 20

      #echo "### sudo -u $SPLUNK_USER $SPLUNK_BIN edit cluster-config -mode searchhead -site $sitenum -manager_uri https://$CM_PRIVATEIP:8089 -secret $SPLUNK_CLUSTER_SECRET"

      sudo -u $SPLUNK_USER $SPLUNK_BIN edit cluster-config \
      -mode searchhead \
      -site $sitenum \
      -manager_uri https://$CM_PRIVATEIP:8089 \
      -secret $SPLUNK_CLUSTER_SECRET \
      -auth admin:$ADMIN_PASSWORD 

      # Bootstrap SHC captain

      # Since we need all three searchhead ip addresses in order to make a captain,
      # and searchhead3 is the last to be created, it will be bootstrapped as the
      # first searchhead cluster captain.
      if [ $num -eq 3 ]
      then
        export SH3_IP=$LOCALIP

        #echo "### sudo -u $SPLUNK_USER $SPLUNK_BIN bootstrap shcluster-captain -servers_list https://$SH1_IP:8089,https://$SH2_IP:8089,https://$SH3_IP:8089"

        sudo -u $SPLUNK_USER $SPLUNK_BIN bootstrap shcluster-captain \
        -servers_list https://$SH1_IP:8089,https://$SH2_IP:8089,https://$SH3_IP:8089 \
        -auth admin:$ADMIN_PASSWORD
      fi
      restart_signal
  else
    echo "Incorrect value passed.  \"$1\" is not 1, 2, or 3."
    # communicate back to CloudFormation the status of the instance creation
    /opt/aws/bin/cfn-signal -e 1 --stack $STACK_NAME --resource $RESOURCE --region $AWS_REGION
    exit 1
  fi
}

###
# Splunk Deployer
###
function splunk_deployer
{
  # execute base install and configuration
  base

  #export RESOURCE="SplunkSHCDeployer"
  printf "$LOCALIP \t splunk-shc-deployer\n" >> /etc/hosts
  hostname splunk-shc-deployer

  # Increase splunkweb connection timeout with splunkd
  mkdir -p $SPLUNK_HOME/etc/apps/base-autogenerated/local
  cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/web.conf <<end
[settings]
splunkdConnectionTimeout = 300
end

  # Configure some SHC parameters
  cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/server.conf <<end
[shclustering]
pass4SymmKey = $SYMMKEY
shcluster_label = SplunkSHC
end

  # Forward to indexer cluster using indexer discovery
  cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/outputs.conf <<end
# Turn off indexing on the search head
[indexAndForward]
index = false

[tcpout]
defaultGroup = indexer_cluster_peers
forwardedindex.filter.disable = true
indexAndForward = false

[tcpout:indexer_cluster_peers]
indexerDiscovery = cluster_master

[indexer_discovery:cluster_master]
pass4SymmKey = $SYMMKEY
master_uri = https://$CM_PRIVATEIP:8089
end

  # update permissions
  chown -R $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/apps/base-autogenerated

  # Add base config for search head cluster members
  mkdir -p $SPLUNK_HOME/etc/shcluster/apps/member-base-autogenerated/local
  cat >>$SPLUNK_HOME/etc/shcluster/apps/member-base-autogenerated/local/outputs.conf <<end
# Turn off indexing on the search head
[indexAndForward]
index = false

[tcpout]
defaultGroup = indexer_cluster_peers
forwardedindex.filter.disable = true
indexAndForward = false

[tcpout:indexer_cluster_peers]
indexerDiscovery = cluster_master

[indexer_discovery:cluster_master]
pass4SymmKey = $SYMMKEY
master_uri = https://$CM_PRIVATEIP:8089
end

  #- set ownership
  chown -R $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/apps

  $SPLUNK_BIN restart
  sleep 10

  sudo -u $SPLUNK_USER $SPLUNK_BIN edit licenser-localslave \
  -master_uri https://$CM_PRIVATEIP:8089 \
  -auth admin:$ADMIN_PASSWORD

  sudo -u $SPLUNK_USER $SPLUNK_BIN apply shcluster-bundle -action stage --answer-yes

  restart_signal
}

## splunk single search head
function splunk_single_sh
{
  # execute base install and configuration
  base

  #export RESOURCE="SplunkSearchHeadInstance"

  # sleep 20 seconds to make sure Splunk has restarted before applying the configuration
  sleep 20

  # add hostname to /etc/hosts and set hostname
  printf "$LOCALIP \t splunksearch\n" >> /etc/hosts
  hostname splunksearch

  # Increase splunkweb connection timeout with splunkd
  mkdir -p $SPLUNK_HOME/etc/apps/base-autogenerated/local
  cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/web.conf <<end
  [settings]
  splunkdConnectionTimeout = 300
end

  # Forward to indexer cluster using indexer discovery
  cat >>$SPLUNK_HOME/etc/apps/base-autogenerated/local/outputs.conf <<end
  # Turn off indexing on the search head
  [indexAndForward]
  index = false

  [tcpout]
  defaultGroup = indexer_cluster_peers
  forwardedindex.filter.disable = true
  indexAndForward = false
  [tcpout:indexer_cluster_peers]
  indexerDiscovery = cluster_master
  [indexer_discovery:cluster_master]
  pass4SymmKey = $SYMMKEY
  master_uri = https://$CM_PRIVATEIP:8089
end

  # update permissions
  chown -R $SPLUNK_USER:$SPLUNK_USER $SPLUNK_HOME/etc/apps/base-autogenerated

  # setup license server communication
  sudo -u $SPLUNK_USER $SPLUNK_BIN edit licenser-localslave -master_uri https://$CM_PRIVATEIP:8089 -auth admin:$ADMIN_PASSWORD

  # configure communication to the splunk indexer cluster
  sudo -u $SPLUNK_USER $SPLUNK_BIN edit cluster-config \
  -secret $SPLUNK_CLUSTER_SECRET \
  -mode searchhead \
  -site site1 \
  -master_uri https://$CM_PRIVATEIP:8089 \
  -auth admin:$ADMIN_PASSWORD

  # final restart and cfn signal
  restart_signal
}

case "$1" in
  "single_sh")
  splunk_single_sh
  ;;
  "cluster_sh")
  splunk_cluster_sh $2
  ;;
  "indexer")
  splunk_indexer
  ;;
  "cm")
  splunk_cm
  ;;
  "deployer")
  splunk_deployer
  ;;
  *)
  echo "Usage:  $(basename -- "$0") [single_sh|cluster_sh|indexer|cm|deployer]";
  echo "        Note: a single argument of integers 1,2, or 3 must be passed to cluster_sh to specify the specific search head cluster node."
  exit 0
esac

#!/bin/bash

oml_app_repo_url=https://gitlab.com/omnileads/ominicontacto.git
SRC=/usr/src
PATH_DEPLOY=install/onpremise/deploy/ansible
CALLREC_DIR_DST=/opt/omnileads/asterisk/var/spool/asterisk/monitor
SSM_AGENT_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
S3FS="/bin/s3fs"
PATH_CERTS="$(cd "$(dirname "$BASH_SOURCE")" &> /dev/null && pwd)/certs"


# if callrec device like DISK BLOCK DEVICE
if [[ ${oml_callrec_device} == "disk" ]];then
  CALLREC_BLOCK_DEVICE=/dev/disk/by-label/callrec-${oml_tenant_name}
fi

echo "******************** OML RELEASE = ${oml_app_release} ********************"

sleep 5

echo "******************** block_device mount ********************"

if [[ ${optoml_device} != "NULL" ]];then
  mkdir /opt/omnileads
  echo "${optoml_device} /opt/omnileads ext4 defaults,nofail,discard 0 0" >> /etc/fstab
fi

if [[ ${pgsql_device} != "NULL" ]];then
  mkdir /var/lib/pgsql
  echo "${pgsql_device} /var/lib/pgsql ext4 defaults,nofail,discard 0 0" >> /etc/fstab
fi

mount -a
sleep 10
mount

echo "******************** IPV4 address config ********************"

case ${oml_infras_stage} in
  aws)
    echo -n "AWS"
    PRIVATE_IPV4=$(ip addr show ${oml_nic} | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    PUBLIC_IPV4=$(curl ifconfig.co)
    ;;
  digitalocean)
    echo -n "DigitalOcean"
    PUBLIC_IPV4=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
    PRIVATE_IPV4=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
    ;;
  linode)
    echo -n "Linode"
    PRIVATE_IPV4=$(ip addr show ${oml_nic} |grep "inet 192.168" |awk '{print $2}' | cut -d/ -f1)
    PUBLIC_IPV4=$(curl checkip.amazonaws.com)
    ;;
  onpremise)
    echo -n "Onpremise CentOS7 Minimal"
    PRIVATE_IPV4=$(ip addr show ${oml_nic} | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    PUBLIC_IPV4=$(curl ifconfig.co)
    ;;
  vagrant)
    echo -n "Vagrant CentOS7 Minimal CI/CD"
    PRIVATE_IPV4=$STAGING_IP_CENTOS
    PUBLIC_IPV4=$(curl ifconfig.co)
    ;;
  *)
    echo -n "You must to set STAGE variable\n"
    ;;
esac

echo "******************** SELinux and firewalld disable ********************"

setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/sysconfig/selinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
systemctl disable firewalld > /dev/null 2>&1
systemctl stop firewalld > /dev/null 2>&1

echo "******************** yum update and install packages ********************"

case ${oml_infras_stage} in
  aws)
    yum remove -y python3 python3-pip
    yum install -y $SSM_AGENT_URL
    yum install -y patch libedit-devel libuuid-devel git podman
    amazon-linux-extras install -y epel
    amazon-linux-extras install python3 -y
    systemctl start amazon-ssm-agent
    ;;
  *)
    yum -y install git python3 python3-pip kernel-devel epel-release libselinux-python3 awscli podman
    ;;
esac

echo "******************** Ansible installation ********************"

pip3 install --upgrade pip
pip3 install boto3  'ansible==2.9.2'
export PATH="$HOME/.local/bin/:$PATH"

echo "******************** git clone omnileads repo ********************"

cd $SRC
git clone --recurse-submodules --branch ${oml_app_release} ${oml_app_repo_url}
cd ominicontacto
git submodule update --remote

echo "******************** inventory setting ********************"

sed -i "s/#localhost ansible/localhost ansible/g" $PATH_DEPLOY/inventory

# sed -i "s/oml_lan_ip=/oml_lan_ip=$PRIVATE_IPV4/g" $PATH_DEPLOY/inventory
# sed -i "s/oml_wan_ip=/oml_wan_ip=$PUBLIC_IPV4/g" $PATH_DEPLOY/inventory

# PGSQL edit inventory params **************************************************

if [[ "${oml_pgsql_cloud}"  == "true" ]];then
  sed -i "s/postgres_cloud=false/postgres_cloud=true/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_pgsql_db}"  != "NULL" ]];then
  sed -i "s/postgres_database=omnileads/postgres_database=${oml_pgsql_db}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_pgsql_user}"  != "NULL" ]];then
  sed -i "s/#postgres_user=omnileads/postgres_user=${oml_pgsql_user}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_pgsql_password}"  != "NULL" ]];then
  sed -i "s/#postgres_password=my_very_strong_pass/postgres_password=${oml_pgsql_password}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_pgsql_host}"  != "NULL" ]];then
  sed -i "s/#postgres_host=/postgres_host=${oml_pgsql_host}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_pgsql_port}"  != "NULL" ]];then
  sed -i "s/#postgres_port=/postgres_port=${oml_pgsql_port}/g" $PATH_DEPLOY/inventory
fi

# Asterisk ACD parameters *******

if [[ "${oml_ami_user}"  != "NULL" ]];then
  sed -i "s/#ami_user=omnileadsami/ami_user=${oml_ami_user}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_ami_password}"  != "NULL" ]];then
  sed -i "s/#ami_password=5_MeO_DMT/ami_password=${oml_ami_password}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_acd_host}"  != "NULL" ]];then
  sed -i "s/#asterisk_host=/asterisk_host=${oml_acd_host}/g" $PATH_DEPLOY/inventory
fi

# Wombat Dialer parameters *******

if [[ "${api_dialer_user}"  != "NULL" ]];then
  sed -i "s/#dialer_user=demoadmin/dialer_user=${api_dialer_user}/g" $PATH_DEPLOY/inventory
fi
if [[ "${api_dialer_password}"  != "NULL" ]];then
  sed -i "s/#dialer_password=demo/dialer_password=${api_dialer_password}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_dialer_host}" != "NULL" ]];then
  sed -i "s/#dialer_host=/dialer_host=${oml_dialer_host}/g" $PATH_DEPLOY/inventory
fi

# WebRTC kamailio & rtpengine params *******

if [[ "${oml_kamailio_host}"  != "NULL" ]];then
  sed -i "s/#kamailio_host=/kamailio_host=${oml_kamailio_host}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_rtpengine_host}" != "NULL" ]];then
  sed -i "s/#rtpengine_host=/rtpengine_host=${oml_rtpengine_host}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_extern_ip}" != "NULL" ]];then
  sed -i "s/#extern_ip=auto/extern_ip=${oml_extern_ip}/g" $PATH_DEPLOY/inventory
fi

# Redis, Nginx and Websockets params *******
if [[ "${oml_redis_host}" != "NULL" ]];then
  sed -i "s/#redis_host=/redis_host=${oml_redis_host}/g" $PATH_DEPLOY/inventory
fi

if [[ "${oml_redis_ha}" == "true" ]];then
sed -i "s/redis_ha=false/redis_ha=true/g" $PATH_DEPLOY/inventory
sed -i "s/#sentinel_host_01=/sentinel_host_01=${oml_sentinel_host_01}/g" $PATH_DEPLOY/inventory
sed -i "s/#sentinel_host_02=/sentinel_host_02=${oml_sentinel_host_02}/g" $PATH_DEPLOY/inventory
sed -i "s/#sentinel_host_03=/sentinel_host_03=${oml_sentinel_host_03}/g" $PATH_DEPLOY/inventory
fi


if [[ "$NGINX_HOST" != "NULL" ]];then
  sed -i "s/#nginx_host=/nginx_host=$NGINX_HOST/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_websocket_host}" != "NULL" ]];then
  sed -i "s/#websocket_host=/websocket_host=${oml_websocket_host}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_websocket_port}" != "NULL" ]];then
  sed -i "s/#websocket_port=/websocket_port=${oml_websocket_port}/g" $PATH_DEPLOY/inventory
fi

# Others App params *******

sed -i "s%\#TZ=%TZ=${oml_tz}%g" $PATH_DEPLOY/inventory

if [[ "$${oml_app_sca}" != "NULL" ]];then
  sed -i "s/sca=3600/sca=${oml_app_sca}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_app_ecctl}" != "NULL" ]];then
  sed -i "s/sca=28800/sca=${oml_app_ecctl}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_app_login_fail_limit}" != "NULL" ]];then
  sed -i "s/LOGIN_FAILURE_LIMIT=10/LOGIN_FAILURE_LIMIT=${oml_app_login_fail_limit}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_app_reset_admin_pass}" == "true" ]];then
  sed -i "s/reset_admin_password=false/reset_admin_password=true/g" $PATH_DEPLOY/inventory
fi

if [[ "${oml_callrec_device}" != "NULL" ]];then
sed -i "s/callrec_device=local/callrec_device=${oml_callrec_device}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_backup_filename}" != "NULL" ]];then
sed -i "s%\#backup_file_name=%backup_file_name=${oml_backup_filename}%g" $PATH_DEPLOY/inventory
fi
if [[ "${s3_access_key}" != "NULL" ]];then
sed -i "s%\#s3_access_key=%s3_access_key=${s3_access_key}%g" $PATH_DEPLOY/inventory
fi
if [[ "${s3_secret_key}" != "NULL" ]];then
sed -i "s%\#s3_secret_key=%s3_secret_key=${s3_secret_key}%g" $PATH_DEPLOY/inventory
fi
if [[ "${s3_bucket_name}" != "NULL" ]];then
sed -i "s%\#s3_bucket_name=%s3_bucket_name=${s3_bucket_name}%g" $PATH_DEPLOY/inventory
fi
if [[ "${s3_endpoint_url}" != "NULL" ]];then
sed -i "s%\#s3url=%s3url=${s3_endpoint_url}%g" $PATH_DEPLOY/inventory
fi
if [[ "${s3_region}" != "NULL" ]];then
sed -i "s%\#s3_region=%s3_region=${s3_region}%g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_auto_restore}" != "NULL" ]];then
sed -i "s/auto_restore=false/auto_restore=${oml_auto_restore}/g" $PATH_DEPLOY/inventory
fi
if [[ "${oml_high_load}" != "NULL" ]];then
sed -i "s/high_load=false/high_load=${oml_high_load}/g" $PATH_DEPLOY/inventory
fi

if [[ "${oml_google_maps_api_key}" != "NULL" ]];then
sed -i "s%\#google_maps_api_key=%google_maps_api_key=${oml_google_maps_api_key}%g" $PATH_DEPLOY/inventory
sed -i "s%\#google_maps_center=%google_maps_center='${oml_google_maps_center}'%g" $PATH_DEPLOY/inventory
fi

# User certs verification *******

if [ -f $PATH_CERTS/key.pem ] && [ -f $PATH_CERTS/cert.pem ];then
        cp $PATH_CERTS/key.pem $SRC/ominicontacto/install/onpremise/deploy/ansible/certs
        cp $PATH_CERTS/cert.pem $SRC/ominicontacto/install/onpremise/deploy/ansible/certs
fi

sleep 2
echo "******************** deploy.sh execution ********************"

cd $PATH_DEPLOY
./deploy.sh -i --iface=${oml_nic}

echo "******************** NET File Systen callrec ********************"

case ${oml_callrec_device} in
  nfs)
    echo "Callrec device: NFS \n"
    yum install -y nfs-utils nfs-utils-lib
    if [ ! -d $CALLREC_DIR_DST ];then
      mkdir -p $CALLREC_DIR_DST
      chown omnileads.omnileads -R $CALLREC_DIR_DST
    fi
    echo "${nfs_host}:$CALLREC_DIR_DST $CALLREC_DIR_DST nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0" >> /etc/fstab
    mount -a
    ;;
  disk)
    echo "Callrec device: Disk \n"
    mkdir -p $CALLREC_DIR_DST
    echo "$CALLREC_BLOCK_DEVICE  $CALLREC_DIR_DST ext4 defaults,nofail,discard 0 0" >> /etc/fstab
    mount -a
    ;;
  *)
    echo "other method ... \n"
    ;;
 esac

sleep 5

echo "******************** Exec task if RTP run AIO ********************"

if [[ "${oml_rtpengine_host}" == "NULL" && "${oml_infras_stage}" != "onpremise" ]];then
  echo -n "STAGE rtpengine \n"
  echo "OPTIONS="-i $PUBLIC_IPV4 -o 60 -a 3600 -d 30 -s 120 -n 127.0.0.1:22222 -m 20000 -M 30000 -L 7 --log-facility=local1""  > /etc/rtpengine-config.conf
  systemctl start rtpengine
fi

echo "********************* Deactivate cron callrec convert to mp3 *****************"
if [ "${oml_acd_host}"  != "NULL" ] &&  [ "${oml_callrec_device}"  == "nfs" ];then
sed -i "s/0 1 \* \* \* source/#0 1 \* \* \* source/g" /var/spool/cron/omnileads
fi

if [ "${oml_acd_host}"  != "NULL" ] &&  [ "${oml_callrec_device}"  != "nfs" ];then
sed -i "s/conversor.sh 1 0/conversor.sh 2 0/g" /var/spool/cron/omnileads
fi

echo "******************** sngrep SIP sniffer install ********************"

if [[ "${oml_app_install_sngrep}" == "true" ]];then
  yum install ncurses-devel make libpcap-devel pcre-devel \
      openssl-devel git gcc autoconf automake -y
  cd /root && git clone https://github.com/irontec/sngrep
  cd sngrep && ./bootstrap.sh && ./configure && make && make install
  ln -s /usr/local/bin/sngrep /usr/bin/sngrep
fi

reboot

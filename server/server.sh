#!/bin/bash

echo "Hello Consul Server"

#yum install -y yum-utils
#yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
#yum -y install consul

### INSTALL CONSUL ###
unzip consul_1.20.4_linux_arm64.zip
sudo chown root:root consul
sudo mv consul /usr/bin/

consul --version

consul -autocomplete-install
complete -C /usr/bin/consul consul
sudo useradd --system --home /etc/consul.d --shell /bin/false consul
sudo mkdir --parents /opt/consul
sudo chown --recursive consul:consul /opt/consul


LOCAL_IP=`ip -o route get to 169.254.169.254 | sed -n 's/.*src \([0-9.]\+\).*/\1/p'`
echo "Fetchec local ip : ${LOCAL_IP}"

consul tls cert create -server -dc us-east-1 -domain consul -additional-ipaddress=${LOCAL_IP} -additional-ipaddress=127.0.0.1 -additional-dnsname="proconsul.internal" -additional-dnsname="localhost"

mkdir -p /etc/consul.d/cert
mv consul-agent-ca.pem /etc/consul.d/cert
mv us-east-1-server-consul-0.pem /etc/consul.d/cert
mv us-east-1-server-consul-0-key.pem /etc/consul.d/cert

source server.env

cat > consul.hcl <<- EOF
log_level  = "INFO"
server     = true
datacenter = "${DATACENTER}"

# # Authoritative datacenter for Federation
# primary_datacenter = "dc1"

ui_config {
  enabled = true
}

# TLS Configuration
tls {
  defaults {
    key_file               = "/etc/consul.d/cert/us-east-1-server-consul-0-key.pem"
    cert_file              = "/etc/consul.d/cert/us-east-1-server-consul-0.pem"
    ca_file                = "/etc/consul.d/cert/consul-agent-ca.pem"
    verify_incoming        = true
    verify_outgoing        = true
    verify_server_hostname = true
  }
}

# Gossip Encryption - generate key using consul keygen
encrypt = "${GOSSIP_ENCRYPTION}"

leave_on_terminate = true
data_dir           = "/opt/consul"

# Agent Network Configuration
client_addr    = "0.0.0.0"
bind_addr      = "${LOCAL_IP}"
advertise_addr = "${LOCAL_IP}"

ports {
  http  = 8500
  https = 8501
}

# Cluster Join - Using Cloud Auto Join
bootstrap_expect = ${BOOTSTRAP_SERVER}
retry_join       = ["provider=aws tag_key=${TAG_NAME} tag_value=${TAG_VALUE} region=${REGION}"]

# Enable and Configure Consul ACLs
# acl = {
#   enabled        = true
#   default_policy = "deny"
#   down_policy    = "extend-cache"
#   tokens = {
#     agent = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   }
# }

# Set raft multiplier to lowest value (best performance) - 1 is recommended for Production servers
performance = {
    raft_multiplier = 1
}

# Enable service mesh capability for Consul datacenter
connect = {
  enabled = true
}
EOF

tr -d $'\r' < consul.hcl > /etc/consul.d/consul.hcl

sudo chown --recursive consul:consul /etc/consul.d
sudo chmod 640 /etc/consul.d/consul.hcl


cat > /etc/systemd/system/consul.service <<- EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.hcl

[Service]
EnvironmentFile=-/etc/consul.d/consul.env
User=consul
Group=consul
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

EOF

systemctl start consul
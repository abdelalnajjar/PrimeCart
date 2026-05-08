#!/bin/bash
set -euo pipefail

# Baked into user-data so launch template revision changes when the artifact or script changes.
# app-zip-md5 (matches zip content): ${app_zip_md5}
# bootstrap-sh: ${bootstrap_hash}

dnf install -y nodejs npm unzip amazon-cloudwatch-agent

rm -rf /opt/primecart
mkdir -p /opt/primecart
mkdir -p /var/log/primecart
touch /var/log/primecart/app.log /var/log/primecart/worker.log
chmod 0644 /var/log/primecart/app.log /var/log/primecart/worker.log

cd /opt/primecart
aws s3 cp "s3://${s3_bucket}/${s3_key}" /tmp/primecart.zip --region "${aws_region}"
unzip -o /tmp/primecart.zip -d /opt/primecart
npm ci --omit=dev

cat >/etc/sysconfig/primecart <<EOF
AWS_REGION=${aws_region}
ORDERS_TABLE_NAME=${orders_table}
ORDERS_QUEUE_URL=${orders_queue_url}
PORT=80
EOF

cat >/etc/systemd/system/primecart.service <<'UNIT'
[Unit]
Description=PrimeCart Node.js app
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/sysconfig/primecart
WorkingDirectory=/opt/primecart
ExecStart=/usr/bin/node app.js
Restart=always
RestartSec=5
User=root
StandardOutput=append:/var/log/primecart/app.log
StandardError=append:/var/log/primecart/app.log

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/primecart-worker.service <<'UNIT'
[Unit]
Description=PrimeCart SQS to DynamoDB worker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/sysconfig/primecart
WorkingDirectory=/opt/primecart
ExecStart=/usr/bin/node worker.js
Restart=always
RestartSec=5
User=root
StandardOutput=append:/var/log/primecart/worker.log
StandardError=append:/var/log/primecart/worker.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now primecart.service
systemctl enable --now primecart-worker.service

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWJSON
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/primecart/app.log",
            "log_group_name": "${log_group_app}",
            "log_stream_name": "{instance_id}/app"
          },
          {
            "file_path": "/var/log/primecart/worker.log",
            "log_group_name": "${log_group_worker}",
            "log_stream_name": "{instance_id}/worker"
          }
        ]
      }
    }
  }
}
CWJSON

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

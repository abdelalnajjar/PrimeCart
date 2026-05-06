#!/bin/bash
set -euo pipefail

dnf install -y nodejs npm unzip

rm -rf /opt/primecart
mkdir -p /opt/primecart
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

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now primecart.service
systemctl enable --now primecart-worker.service

# AWS deploy (Terraform)

Single-instance stack in the **default VPC**: EC2 runs the Node app on **port 80**, persists orders to **DynamoDB**, and on **first boot only** downloads the app from a **private S3** artifact bucket. There is **no** Application Load Balancer, **no** Auto Scaling Group, and **no** SQS in this configuration.

## S3 caveat (product images vs deployment)

**Product images** are already stored on a **different** S3 bucket: URLs in `data/products.json` point at objects someone uploaded separately (for example `primecart-images-abdel` in `us-west-1`). Terraform does **not** create or manage that bucket.

The **S3 bucket Terraform creates** is **only** for **automating deployment**: a private bucket holding a **zip of the app** so EC2 can download and unpack it on first boot. Browsers load catalog images from the URLs in `products.json`, not from the Terraform artifact bucket.

## What Terraform creates

| Resource | Purpose |
| -------- | ------- |
| `aws_instance.app` | Amazon Linux 2023, Node from user-data (`bootstrap.sh`), systemd unit `primecart.service` |
| `aws_security_group.app` | Inbound **TCP 80** from `0.0.0.0/0`; unrestricted egress |
| `aws_dynamodb_table.orders` | Table name **`${var.environment}-orders`** (default `primecart-orders`), billing **PAY_PER_REQUEST**, partition key **`orderId`** (string) |
| `aws_s3_bucket.app_artifacts` + `aws_s3_object.app_zip` | **Private** bucket; holds **one zip** of the repo (`releases/app.zip`) for EC2 to `aws s3 cp` on boot |
| IAM role + instance profile | **`s3:GetObject`** on that zip only; **`dynamodb:PutItem`** and **`dynamodb:DescribeTable`** on the orders table ARN |

Instance metadata: **IMDSv2 required** (`http_tokens = "required"`).

## What is not in this Terraform

- **ALB / NLB**, **Auto Scaling Group**, **SQS**, **CloudWatch** dashboards/alarms (not defined here).
- **Product images:** the catalog in `data/products.json` uses **separate** public S3 object URLs. That image bucket is **not** created by this module; only the **deployment zip** bucket is.

## Runtime vs first boot

- **Shoppers:** browser → EC2 public DNS/IP on **HTTP** → Express/EJS; checkout **`POST /orders`** → DynamoDB.
- **First boot:** EC2 user-data runs `bootstrap.sh` → **`GetObject`** on the artifact zip → `npm ci` → start `app.js`. The app does **not** read product images from the artifact bucket; it uses URLs in `products.json`.

## Diagram

```mermaid
flowchart LR
  subgraph Internet
    C[Client]
  end
  subgraph AWS["AWS default VPC"]
    C -->|HTTP 80| EC2["EC2\nAL2023 + Node"]
    EC2 --> DDB[(DynamoDB\norders table)]
    EC2 -.->|first boot only| S3zip[(S3 private\napp zip)]
  end
```

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform/install) installed.
- AWS credentials in the default credential chain (same as `aws` CLI).
- A **default VPC** with at least one subnet. The config prefers a subnet with **`map_public_ip_on_launch` enabled**; otherwise it uses the first default subnet (see `main.tf`).

## Configuration

Optional: copy `terraform.tfvars.example` to `terraform.tfvars` and set `aws_region`, `environment`, `instance_type`.

On the instance, `/etc/sysconfig/primecart` sets **`AWS_REGION`**, **`ORDERS_TABLE_NAME`** (to the Terraform table name), and **`PORT=80`** so the app matches the provisioned table (unlike local defaults in `app.js`, which use table name `orders` unless overridden).

## Apply / destroy

```bash
cd deploy/terraform
terraform init
terraform apply
```

Cold start (user-data: install packages, download zip, `npm ci`, start service) often takes **a few minutes** before HTTP responds.

```bash
cd deploy/terraform
terraform destroy
```

## Outputs

After `terraform apply`, useful outputs include:

| Output | Meaning |
| ------ | ------- |
| `app_url` | `http://<instance-public-dns>` (port 80) |
| `app_public_ip` | Instance public IPv4 |
| `orders_table_name` | DynamoDB table name to use for local testing against the same account (with matching credentials) |
| `app_artifact_bucket` | S3 bucket containing the deployment zip |
| `app_artifact_key` | Object key (`releases/app.zip`) |

## Cost / free tier

Estimates below match **this repo’s defaults** (`instance_type = t2.micro`, `aws_region = us-west-1` in `terraform.tfvars.example`). They are **rough USD order-of-magnitude** for **on-demand** pricing: AWS changes list prices, your account may have credits, tax, or different regions/types—use the [AWS Pricing Calculator](https://calculator.aws/) before relying on a budget.

### What drives the bill

Almost always **EC2 run hours** plus the **EBS root volume** attached to that instance. This stack has **no ALB** and **no NAT Gateway**, so you avoid those common fixed monthly charges.

### Ballpark (off free tier, instance left running ~24×7)

| Piece | Typical monthly range (USD) | Notes |
| ----- | --------------------------- | ----- |
| **EC2 `t2.micro`** | **~$9–12** | ~730 h/mo × on-demand **~$0.012–0.016/h** in **us-west-1**–class US regions (check [EC2 On-Demand](https://aws.amazon.com/ec2/pricing/on-demand/) for your region and type). |
| **EBS (root disk)** | **~$1–4** | Charged for **allocated GiB** while the volume exists (even if the instance is **stopped**). Size follows the AMI (commonly on the order of **8–30 GiB** for Amazon Linux 2023). See [EBS pricing](https://aws.amazon.com/ebs/pricing/). |
| **DynamoDB** (on-demand table, light traffic) | **~$0–1** | Demo / coursework traffic is usually negligible vs EC2. |
| **S3** (deployment zip + versioning if enabled) | **~$0–0.25** | One small object; occasional full instance refresh downloads. |

**Combined:** about **US$12–18/month** if the instance runs continuously with default-ish settings, with **EC2 + EBS** making up almost all of it. **`t3.micro`** is in a similar ballpark but slightly higher on-demand—override in `terraform.tfvars` and re-check the calculator.

### Free tier and savings

- **EC2 / EBS:** New accounts often get **12 months** of limited free EC2 + EBS; eligibility and caps depend on [AWS Free Tier](https://aws.amazon.com/free/) and your account—confirm in the console. A **`t2.micro`** is the usual free-tier size for that offer when it applies.
- **DynamoDB / S3:** Often within free allowances for this workload; still verify for your account.

### Keeping cost down

- Run **`terraform destroy`** when the environment is not needed (removes EC2 hourly charges and, after the final bill cycle, the EBS volume for that instance).
- **Stop** the instance to avoid EC2 compute charges while experimenting; you still pay for the **EBS** volume until the instance (and its root volume) is terminated.
- Do not upsize `instance_type` unless required; larger types scale cost roughly linearly or faster per vCPU-hour.

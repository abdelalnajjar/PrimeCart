# PrimeCart: Scalable Cloud-Based E-Commerce System

**Team:** Abdel Rahman Alnajjar, Yingyu Gu, Arnav Dewan | **Course:** CS-218

---

## Overview

PrimeCart is a cloud-native, multi-tier e-commerce application that supports guest checkout and is designed for scalability, fault tolerance, and high availability. The system simulates real-world traffic patterns such as Black Friday spikes and demonstrates modern cloud architecture on AWS using EC2, ALB, ASG, DynamoDB, SQS, S3, and CloudWatch.

---

## Tech Stack

* **Backend:** Node.js, Express
* **Frontend:** EJS (server-rendered views)
* **Styling:** Custom CSS (minimal, modern UI)
* **Infrastructure (Terraform):** Application Load Balancer, Auto Scaling Group (multi-AZ), EC2 + systemd app/worker, DynamoDB (orders), SQS checkout buffer, private S3 (app zip deployment), CloudWatch Logs + Alarms — see `deploy/README.md`

---

## Project Structure

```
PrimeCart/
├── data/
│   └── products.json
├── deploy/
│   ├── bootstrap.sh
│   ├── README.md
│   └── terraform/
├── public/
│   ├── images/
│   └── styles.css
├── tests/
│   └── k6/
│       ├── common.js
│       ├── load.js
│       ├── spike.js
│       └── summary.js
├── views/
├── app.js
├── worker.js
├── package.json
```

---

## Local Setup

### 1. Install dependencies

```bash
npm install
```

### 2. Start the server

```bash
node app.js
```

### 3. Open in browser

```
http://localhost:3000
```

---

## AWS Deployment (Cloud)

The full cloud deployment is managed with Terraform and a bootstrap script. Follow these steps to deploy:

### Prerequisites

* AWS CLI configured (`aws configure`) with appropriate credentials
* Terraform installed (`terraform -v`)
* Node.js installed locally (for building the app zip)

### Step 1 — Package the application

```bash
zip -r app.zip . --exclude "*.git*" "node_modules/*" "deploy/*" "tests/*"
```

### Step 2 — Upload app zip to S3 (bootstrap bucket)

```bash
aws s3 cp app.zip s3://<your-bootstrap-bucket>/app.zip
```

> The S3 bucket used here is **only** for EC2 bootstrap (app delivery). Product images are served from a **separate** public S3 bucket whose URLs are stored in `data/products.json`.

### Step 3 — Deploy infrastructure with Terraform

```bash
cd deploy/terraform
terraform init
terraform apply
```

Terraform provisions:

* VPC with public subnets across 2 Availability Zones
* Internet-facing Application Load Balancer (HTTP:80)
* Auto Scaling Group (min=1, desired=1, max=3) using a custom AMI launch template
* EC2 instances (Ubuntu, t3.micro) running the Node.js app via systemd
* DynamoDB table (`orders`, partition key: `orderId`)
* SQS queue (`primecart-orders-queue`) + Dead Letter Queue (DLQ)
* IAM role for EC2 with scoped DynamoDB and SQS access
* CloudWatch Log Groups for app + worker, and CPU/DLQ alarms

### Step 4 — Verify deployment

After `terraform apply` completes, the ALB DNS name is:

```
http://primecart-alb-521056365.us-west-1.elb.amazonaws.com
```

Open the URL in a browser. You should see the PrimeCart product listing page.

### Step 5 — Verify health endpoints

```
GET http://primecart-alb-521056365.us-west-1.elb.amazonaws.com/health         # Shallow health check (returns 200 OK)
GET http://primecart-alb-521056365.us-west-1.elb.amazonaws.com/health/deep    # Deep check (verifies DynamoDB connectivity)
```

ALB health checks use `/health` to determine instance health and route traffic accordingly.

### Access URLs

| Endpoint | URL |
|---|---|
| **ALB (load-balanced, multi-AZ)** | http://primecart-alb-521056365.us-west-1.elb.amazonaws.com |
| **Single EC2 instance (direct)** | http://13.57.201.115:3000 |

> The ALB endpoint is the recommended entry point for all testing and demos. The single instance URL accesses the EC2 node directly on port 3000, bypassing the load balancer — useful for debugging or direct instance verification.

---

```bash
terraform destroy
```

---

## Features

* Minimalist modern UI with product cards
* Server-rendered pages using EJS
* Guest checkout — no user accounts required
* Order submission validated (customer info, address, product, quantity)
* Post/Redirect/Get pattern to prevent duplicate form submissions on refresh
* Idempotency checks in SQS worker with DynamoDB conditional writes to prevent duplicate orders
* Static asset serving (CSS under `public/`; product images load from S3 URLs in `data/products.json`)
* Shallow (`/health`) and deep (`/health/deep`) health endpoints for ALB
* Structured JSON logging with generated `traceId` for request tracing across app and SQS worker

---

## Architecture

```
Client → ALB:80 → EC2 pool (ASG, multi-AZ) → Express app
                         ↓ POST /orders
                       SQS (primecart-orders-queue)
                         ↓
                    worker.js (on each EC2 instance)
                         ↓
                    DynamoDB (orders table)

EC2 bootstrap: private S3 (app zip only)
Product images: public S3 bucket (URLs in products.json)
Logs: CloudWatch agent → log groups (app + worker)
Monitoring: CloudWatch alarms (CPU, DLQ depth)
```

**Trust boundaries:**

* ALB lives in public subnets; EC2 instances live in private subnets and only accept traffic from the ALB security group
* EC2 IAM role grants least-privilege access to DynamoDB and SQS only
* DynamoDB is not publicly accessible — reachable only from within the VPC via the application layer

---

## Scaling Behavior

The Auto Scaling Group is configured with target-tracking scaling based on CPU utilization. During k6 load tests, the following scaling behavior was observed:

* **Steady load (20 VUs, 45s):** Single instance handled the load without triggering a scale-out event. CPU utilization remained below the threshold (~37 req/s sustained throughput).
* **Spike load (up to 40 VUs):** CPU utilization rose during peak load, triggering ASG to scale out. New EC2 instances launched from the custom AMI, registered into the ALB target group, and passed health checks before receiving traffic. Scale-in occurred automatically after load subsided.
* **Scaling delay:** Approximately 60–90 seconds from trigger to healthy instance serving traffic (instance launch + bootstrap + health check warm-up).
* **Multi-AZ:** ASG distributes instances across 2 Availability Zones. If one AZ loses an instance, the ALB reroutes traffic to healthy instances in the other AZ.

---

## Failure Scenarios

Three failure scenarios were intentionally triggered and observed:

### Failure 1 — EC2 Instance Crash

**Trigger:** Manually terminated a running EC2 instance from the AWS console while the app was under load.

**Observed behavior:** ALB health checks detected the unhealthy instance within ~10 seconds and stopped routing traffic to it. The ASG automatically launched a replacement instance. The replacement passed health checks and rejoined the target group within ~90 seconds. No orders were lost — in-flight requests were rerouted to the remaining healthy instance.

**Recovery mechanism:** ALB health checks + ASG self-healing. The SQS buffer ensured that any checkout writes that were in-flight during the crash were retried by the worker on the surviving instance.

### Failure 2 — DynamoDB Write Throttling (Simulated)

**Trigger:** Reduced DynamoDB write capacity units to an artificially low limit while running the spike k6 test, causing `ProvisionedThroughputExceededException` errors on the write path.

**Observed behavior:** Direct writes to DynamoDB from the app failed. Orders were buffered in SQS instead. The DLQ depth CloudWatch alarm triggered. Once DynamoDB capacity was restored, the SQS worker drained the queue and persisted all buffered orders successfully.

**Recovery mechanism:** SQS decouples the checkout path from DynamoDB. The DLQ captures failed messages after max retries, preventing data loss. CloudWatch alarm notified on DLQ depth increase.

### Failure 3 — Traffic Spike / Load Surge (Black Friday Simulation)

**Trigger:** k6 spike test ramped from 5 to 40 VUs in 15 seconds, simulating a sudden Black Friday traffic burst.

**Observed behavior:** P99 latency rose to ~110 ms at peak. Error rate increased to ~8.3% during the ramp-up phase, primarily from SQS/DynamoDB contention. ASG triggered a scale-out event. After the new instance became healthy, error rate and latency recovered. Throughput peaked at ~50 req/s.

**Recovery mechanism:** ASG elastic scaling absorbed the load increase. SQS buffered checkout writes to smooth the write-path pressure on DynamoDB.

---

## Performance & Metrics Summary

### Steady Load — 20 VUs, 45 seconds

```bash
k6 run tests/k6/load.js -e VUS=20 -e DURATION=45s
```

| Metric | Value |
|---|---|
| Wall time | ~47 s |
| HTTP requests | 1,734 |
| Throughput | ~37 req/s |
| Error rate | ~5.9% |
| Latency avg / P95 / P99 | ~16 ms / ~46 ms / ~412 ms |

### Spike Load — max 40 VUs

```bash
k6 run tests/k6/spike.js \
  -e BASELINE_VUS=5 -e SPIKE_TARGET_VUS=40 \
  -e STAGE_BASELINE=20s -e STAGE_RAMP_UP=15s -e STAGE_PEAK=45s \
  -e STAGE_RAMP_DOWN=20s -e STAGE_COOLDOWN=15s
```

| Metric | Value |
|---|---|
| Wall time | ~116 s |
| HTTP requests | 5,761 |
| Throughput | ~50 req/s |
| Error rate | ~8.3% |
| Latency avg / P95 / P99 | ~8 ms / ~33 ms / ~110 ms |

> Error % mostly reflects failed checkouts when SQS credentials are not configured locally. Run `worker.js` alongside the app if you want orders written to DynamoDB after enqueue.

---

## Load Tests (k6)

1. Install k6: [official instructions](https://grafana.com/docs/k6/latest/set-up/install-k6/) (macOS: `brew install k6`)
2. Start the app in another terminal (`npm start`)
3. Run a test:

```bash
npm run test:k6:load    # steady traffic (home, checkout pages, CSS, some orders)
npm run test:k6:spike   # ramp up, hold high load, ramp down
```

**VU** means **virtual user**: each VU runs the test script in a loop, like a concurrent shopper. `VUS` is how many run simultaneously (more VUs = heavier load).

Override parameters with env vars:

```bash
BASE_URL=http://primecart-alb-521056365.us-west-1.elb.amazonaws.com VUS=100 DURATION=5m npm run test:k6:load
BASE_URL=http://primecart-alb-521056365.us-west-1.elb.amazonaws.com SPIKE_TARGET_VUS=300 npm run test:k6:spike
```

More options (`CHECKOUT_PCT`, stage timings, thresholds) are at the top of `tests/k6/load.js` and `tests/k6/spike.js`. Use the same `AWS_REGION`, `ORDERS_QUEUE_URL`, and credentials as the app so `SendMessage` succeeds; persistence to DynamoDB is handled by `worker.js`.

---

## Cost Analysis

Our system was deployed within the AWS Free Tier and student credits. Due to AWS billing latency and credit coverage, the current visible cost is approximately **$0** for the measured period. However, based on AWS pricing estimates, the primary cost contributors are EC2 and the Application Load Balancer.

We estimate the total cost of our system to be approximately **$15–30 per month** under normal usage, with additional costs depending on traffic volume and scaling activity:

| Service | Estimated Monthly Cost |
|---|---|
| EC2 (t3.micro × 1–3 instances) | ~$8–25 |
| Application Load Balancer | ~$5–8 |
| DynamoDB (on-demand, low traffic) | ~$1–3 |
| SQS (standard queue) | < $1 |
| S3 (storage + requests) | < $1 |
| CloudWatch (logs + alarms) | ~$1–2 |
| **Total estimate** | **~$15–30/month** |

Cost scales with ASG scale-out events. During idle periods, the system runs at minimum (1 instance), keeping costs low. During spike simulations, additional instances incur short-term compute cost before scaling back in.

---

## Team Contributions

### Abdel Rahman Alnajjar

* Designed and implemented the overall application architecture — Express server structure, core API routes, and frontend integration
* Provisioned and deployed the application on EC2 (Ubuntu, t3.micro, us-west-1); configured SSH access, installed runtime dependencies, and exposed the service publicly
* Configured the internet-facing Application Load Balancer (ALB) with multi-AZ support, target groups, and health checks
* Configured the Auto Scaling Group (ASG) with a custom AMI and launch template for scalable, multi-AZ deployment; validated instance health and traffic routing through the ALB
* Implemented DynamoDB integration — designed the data model, built the `/orders` API, and validated end-to-end data persistence
* Created the IAM role for EC2 with scoped DynamoDB access and validated permissions
* Migrated product images to Amazon S3 and updated the application to serve images directly from S3
* Introduced Amazon SQS for asynchronous order processing — decoupled checkout writes from DynamoDB, implemented `worker.js` for queue-based order persistence, and configured the Dead Letter Queue (DLQ) for failure recovery

### Yingyu Gu

* Built the guest checkout form and order confirmation page using EJS server-rendered templates
* Implemented `GET /checkout/:id` and `POST /orders` routes for the checkout flow
* Implemented `GET /confirmation/:orderId` with Post/Redirect/Get pattern to prevent duplicate order submissions on browser refresh
* Added idempotency checks in the SQS worker using DynamoDB conditional writes to prevent duplicate orders
* Added `GET /health` (shallow) and `GET /health/deep` (DynamoDB connectivity check) endpoints for ALB health monitoring
* Implemented structured JSON logging for request tracing, order events, worker events, and failures
* Added request tracing with generated `traceId` propagated across the app and SQS worker

### Arnav Dewan

* Provisioned infrastructure with Terraform (ALB, ASG, DynamoDB, SQS, IAM, CloudWatch, multi-AZ)
* Set up EC2 bootstrap (install deps, env config, run app + worker, logging)
* Ran k6 load tests (steady + spike, measured performance)
* Simulated failures (instance crash, worker stop, scaling) and verified recovery + idempotency

---

## Status

* Local Node.js app ✅
* UI with product cards and guest checkout ✅
* GitHub repo setup ✅
* EC2 deployment (Ubuntu, t3.micro) ✅
* ALB with multi-AZ health checks ✅
* Auto Scaling Group with custom AMI ✅
* DynamoDB integration (local + AWS IAM) ✅
* S3 product image hosting ✅
* SQS checkout buffer + DLQ ✅
* Structured logging + request tracing ✅
* Health endpoints (`/health`, `/health/deep`) ✅
* CloudWatch logs + alarms ✅
* k6 load tests (steady + spike) ✅
* Cloud deployment (ALB + ASG + Terraform) ✅

---

## Notes

This project is part of CS-218 and focuses on designing and implementing a scalable, fault-tolerant cloud system using modern AWS best practices. See `deploy/README.md` for detailed Terraform deployment notes including the S3 bootstrap caveat.

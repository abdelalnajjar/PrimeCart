# PrimeCart: Scalable Cloud-Based E-Commerce System

**Name:** Abdel Rahman Alnajjar, Yingyu Gu, Arnav Dewan | **Course:** CS-218

---

## Overview

PrimeCart is a cloud-based e-commerce application that supports guest checkout and is designed for scalability, fault tolerance, and high availability. The system simulates real-world traffic patterns such as Black Friday spikes and demonstrates modern cloud architecture using AWS services.

---

## Tech Stack

* **Backend:** Node.js, Express
* **Frontend:** EJS (server-rendered views)
* **Styling:** Custom CSS (minimal, modern UI)
* **Cloud (Terraform, current):** Application Load Balancer, Auto Scaling Group (multi-AZ), EC2 + systemd app/worker, DynamoDB (orders), SQS, private S3 (app zip), CloudWatch Logs for app + worker, basic alarms — see `deploy/README.md`

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

## Features (Current)

* Minimalist modern UI with product cards
* Server-rendered pages using EJS
* Static asset serving (CSS under `public/`; product images load from URLs in `data/products.json`, typically S3)
* Sample product catalog (electronics)

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
├── package.json
```

---

## Load tests (k6)

1. Install k6: [official instructions](https://grafana.com/docs/k6/latest/set-up/install-k6/) (macOS: `brew install k6`).
2. Start the app in another terminal (`npm start`).
3. Run a test:

```bash
npm run test:k6:load    # steady traffic (home, checkout pages, CSS, some orders)
npm run test:k6:spike   # ramp up, hold high load, ramp down
```

**VU** means **virtual user**: each VU runs the test script in a loop, like a concurrent shopper. `VUS` is how many of those run at the same time (more VUs = heavier load).

The run ends with a short summary (requests per second, error %, avg / P95 / P99 latency). k6 prints full stats as well.

Scripts use `data/products.json` for product IDs. Change the target or load with env vars, for example:

```bash
BASE_URL=http://localhost:3000 VUS=100 DURATION=5m npm run test:k6:load
BASE_URL=http://localhost:3000 SPIKE_TARGET_VUS=300 npm run test:k6:spike
```

More options (`CHECKOUT_PCT`, stage timings, thresholds) are at the top of `tests/k6/load.js` and `tests/k6/spike.js`. Successful checkout **enqueues SQS** (`POST /orders` then redirect to the confirmation page). Use the same **`AWS_REGION`**, **`ORDERS_QUEUE_URL`**, and credentials as the app so `SendMessage` succeeds; persistence to DynamoDB is done by **`worker.js`** if it is running.

### Sample results (local, May 2026)

Same machine as the app, `BASE_URL=http://localhost:3000`. Error % mostly reflects failed checkouts when **SQS** (or credentials) is not configured; run **`worker.js`** as well if you want orders written to DynamoDB after enqueue.

**Steady load** — 20 VUs for 45 seconds:

```bash
k6 run tests/k6/load.js -e VUS=20 -e DURATION=45s
```

| Metric | Value |
| --- | --- |
| Wall time | ~47 s |
| HTTP requests | 1,734 |
| Throughput | ~37 req/s |
| Error rate | ~5.9% |
| Latency avg / P95 / P99 | ~16 ms / ~46 ms / ~412 ms |

**Spike** — shortened profile (faster than default `npm run test:k6:spike`); max 40 VUs, stages 20s → 15s → 45s → 20s → 15s:

```bash
k6 run tests/k6/spike.js \
  -e BASELINE_VUS=5 -e SPIKE_TARGET_VUS=40 \
  -e STAGE_BASELINE=20s -e STAGE_RAMP_UP=15s -e STAGE_PEAK=45s \
  -e STAGE_RAMP_DOWN=20s -e STAGE_COOLDOWN=15s
```

| Metric | Value |
| --- | --- |
| Wall time | ~116 s |
| HTTP requests | 5,761 |
| Throughput | ~50 req/s |
| Error rate | ~8.3% |
| Latency avg / P95 / P99 | ~8 ms / ~33 ms / ~110 ms |

Your numbers will differ by hardware, network, and AWS setup.

---

## Sample Products

See `data/products.json` (e.g. AirPods Pro 3, Galaxy Buds4 Pro, Galaxy XR).

---

## Future Enhancements (Cloud Integration)

* **Product catalog in DynamoDB** (today: JSON file; **orders** already use DynamoDB in AWS/local when configured)
* **Richer monitoring:** CloudWatch dashboards, SNS on alarms, X-Ray tracing

---

## Architecture

**Deployed today (Terraform)** — ALB, ASG across two AZs, SQS checkout buffer, CloudWatch Logs for app + worker:

```
Client → ALB:80 → EC2 pool (ASG) → Express
                         ↓ POST /orders
                       SQS → worker on each instance → DynamoDB (orders)
         first boot per instance: private S3 (app zip only)
         logs: CloudWatch agent → log groups
```

Catalog images: HTTPS URLs in `products.json` pointing at objects **already uploaded** to a **separate** S3 bucket (not created by Terraform). The S3 bucket in `deploy/terraform` exists **only** to host the **deployment zip** for EC2 bootstrap—see `deploy/README.md` (“S3 caveat”).

---

## Goals

* Demonstrate scalable cloud architecture
* Handle traffic spikes efficiently
* Maintain low latency and high availability
* Simulate real-world e-commerce workloads

---

## Status

* Local Node.js app ✅
* UI with product cards ✅
* GitHub repo setup ✅
* Cloud deployment (ALB + ASG + Terraform) ✅ — see `deploy/README.md`

---

## Notes

This project is part of CS-218 and focuses on designing and implementing a scalable, fault-tolerant cloud system using modern best practices.

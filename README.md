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
* **Cloud (Planned):** AWS EC2, ALB, DynamoDB, S3, SQS, CloudWatch

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
* Static asset serving (images, CSS)
* Sample product catalog (electronics)

---

## Project Structure

```
PrimeCart/
├── public/
│   ├── images/
│   └── styles.css
├── views/
│   └── index.ejs
├── app.js
├── package.json
```

---

## Sample Products

* Wireless Earbuds
* Mechanical Keyboard
* Smartwatch
* Portable Speaker
* Fast Charger

---

## Future Enhancements (Cloud Integration)

* **Product storage:** DynamoDB
* **Images:** AWS S3
* **Checkout queue:** AWS SQS
* **Auto-scaling:** EC2 + Auto Scaling Group
* **Load balancing:** Application Load Balancer (ALB)
* **Monitoring:** CloudWatch

---

## Architecture (Planned)

```
Client → ALB → EC2 (Node.js API) → DynamoDB
                      ↓
                     S3 (images)
                      ↓
                     SQS (checkout queue)
```

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
* Cloud deployment ⏳ (in progress)

---

## Notes

This project is part of CS-218 and focuses on designing and implementing a scalable, fault-tolerant cloud system using modern best practices.

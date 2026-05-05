const express = require("express");
const path = require("path");
require("dotenv").config();

const app = express();
const PORT = process.env.PORT || 3000;

// AWS dynamoDB
// import AWS SDK
const { DynamoDBClient, DescribeTableCommand } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { v4: uuidv4 } = require("uuid");
//SQS
const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

//create DynamoDB client
const client = new DynamoDBClient({
  region: process.env.AWS_REGION || "us-west-1"
});
const docClient = DynamoDBDocumentClient.from(client);


// Initialize SQS client to send and receive messages from the orders queue
const sqsClient = new SQSClient({
  region: process.env.AWS_REGION || "us-west-1"
});

const ORDERS_QUEUE_URL =
  process.env.ORDERS_QUEUE_URL ||
  "https://sqs.us-west-1.amazonaws.com/774676933701/primecart-orders-queue";


// Load product data
const products = require("./data/products.json");

// Middleware
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// View engine
app.set("view engine", "ejs");
app.set("views", path.join(__dirname, "views"));

// Static files
app.use(express.static(path.join(__dirname, "public")));

// Logging Middleware
app.use((req, res, next) => {
  const start = Date.now();

  res.on("finish", () => {
    const duration = Date.now() - start;

    console.log(
      JSON.stringify({
        timestamp: new Date().toISOString(),
        method: req.method,
        path: req.originalUrl,
        statusCode: res.statusCode,
        durationMs: duration,
        ip: req.ip,
        userAgent: req.get("user-agent")
      })
    );
  });

  next();
});

// Routes
app.get("/", (req, res) => {
  res.render("index", {
    title: "PrimeCart",
    products,
  });
});

// POST  /orders route
app.post("/orders", async (req, res) => {
  try {
    const {
      firstName,
      lastName,
      email,
      street,
      city,
      state,
      zip,
      country,
      productId,
      quantity
    } = req.body;

    const product = products.find((p) => p.id === productId);

    // if product not found, return error
    if (!product) {
      return res.status(400).json({
        success: false,
        error: "Invalid product ID"
      });
    }

    const qty = Number(quantity);
    const shippingAddress = {
      street,
      city,
      state,
      zip,
      country
    };

    if (
      !firstName ||
      !lastName ||
      !email ||
      !shippingAddress.street ||
      !shippingAddress.city ||
      !shippingAddress.state ||
      !shippingAddress.zip ||
      !shippingAddress.country ||
      !qty ||
      qty < 1
    ) {
      return res.status(400).json({
        success: false,
        error: "Missing or invalid checkout fields",
      });
    }

    const order = {
      orderId: uuidv4(),
      firstName,
      lastName,
      email,
      shippingAddress,
      productId,
      productName: product.name,
      quantity: qty,
      unitPrice: product.price,
      total: Number((product.price * qty).toFixed(2)),
      status: "SUBMITTED",
      createdAt: new Date().toISOString()
    };

    await sqsClient.send(
      new SendMessageCommand({
        QueueUrl: ORDERS_QUEUE_URL,
        MessageBody: JSON.stringify(order)
      })
    );

    console.log(
      JSON.stringify({
        event: "ORDER_CREATED",
        orderId: order.orderId,
        productId: order.productId,
        quantity: order.quantity,
        total: order.total,
        timestamp: new Date().toISOString()
      })
    );

    return res.status(201).render("confirmation", {
      title: "Order Confirmation - PrimeCart",
      order
    });

  } catch (err) {
    console.error(
      JSON.stringify({
        event: "ORDER_CREATE_FAILED",
        error: err.message,
        timestamp: new Date().toISOString()
      })
    );

    res.status(500).json({
      success: false,
      error: "Failed to save order"
    });
  }
});

app.get("/checkout/:id", (req, res) => {
  const product = products.find((p) => p.id === req.params.id);

  if (!product) {
    return res.status(404).send("Product not found");
  }

  res.render("checkout", {
    title: "Checkout - PrimeCart",
    product
  });
});

// shallow health check that only checks if the app is running and responsive
// does not check database connectivity or other dependencies
// only removes instances if app is down
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "ok",
    service: "PrimeCart",
    timestamp: new Date().toISOString()
  });
});

// deep health check that checks both app and database connectivity
// removes instances if database is unreachable, even if app may be running
app.get("/health/deep", async (req, res) => {
  try {
    await client.send(
      new DescribeTableCommand({
        TableName: process.env.ORDERS_TABLE_NAME || "orders"
      })
    );

    console.log(
      JSON.stringify({
        event: "HEALTH_DEEP_OK",
        timestamp: new Date().toISOString()
      })
    );

    res.status(200).json({
      status: "ok",
      app: "running",
      db: "connected",
      timestamp: new Date().toISOString()
    });

  } catch (err) {
    console.error(
      JSON.stringify({
        event: "HEALTH_DEEP_FAILED",
        error: err.message,
        timestamp: new Date().toISOString()
      })
    );

    res.status(500).json({
      status: "error",
      app: "running",
      db: "unreachable",
      timestamp: new Date().toISOString()
    });
  }
});

// Start server
app.listen(PORT, "0.0.0.0", () => {
  console.log(
    JSON.stringify({
      event: "APP_STARTED",
      port: PORT,
      region: process.env.AWS_REGION || "us-west-1",
      table: process.env.ORDERS_TABLE_NAME || "orders",
      timestamp: new Date().toISOString()
    })
  );
});

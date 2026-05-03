const express = require("express");
const path = require("path");
require("dotenv").config();

const app = express();
const PORT = process.env.PORT || 3000;

// AWS dynamoDB
// import AWS SDK
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { v4: uuidv4 } = require("uuid");

//create DynamoDB client
const client = new DynamoDBClient({
  region: process.env.AWS_REGION || "us-west-1"
});
const docClient = DynamoDBDocumentClient.from(client);

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

    await docClient.send(
      new PutCommand({
        TableName: process.env.ORDERS_TABLE_NAME || "orders",
        Item: order,
      }),
    );

    res.status(201).json({
      success: true,
      message: "Order saved",
      order,
    });
  } catch (err) {
    console.error("Failed to save order:", err);

    res.status(500).json({
      success: false,
      error: "Failed to save order"
    });
  }
});

// Start server
app.listen(PORT, "0.0.0.0", () => {
  console.log(`PrimeCart server running on port ${PORT}`);
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
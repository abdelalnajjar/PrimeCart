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
const client = new DynamoDBClient({ region: "us-west-1" });
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
    products
  });
});


//  /orders route
app.post("/orders", async (req, res) => {
  try {
    const { name, item } = req.body;

    if (!name || !item) {
      return res.status(400).json({ error: "Missing fields" });
    }

    const order = {
      orderId: uuidv4(),
      name,
      item,
      createdAt: new Date().toISOString()
    };

    await docClient.send(
      new PutCommand({
        TableName: "orders",
        Item: order
      })
    );

    res.status(201).json({ message: "Order saved", order });

  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to save order" });
  }
});


// Start server
app.listen(PORT, "0.0.0.0", () => {
  console.log(`PrimeCart server running on port ${PORT}`);
});
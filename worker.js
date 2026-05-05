require("dotenv").config();

const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");
const {
  SQSClient,
  ReceiveMessageCommand,
  DeleteMessageCommand
} = require("@aws-sdk/client-sqs");

const REGION = process.env.AWS_REGION || "us-west-1";
const ORDERS_TABLE_NAME = process.env.ORDERS_TABLE_NAME || "orders";
const ORDERS_QUEUE_URL =
  process.env.ORDERS_QUEUE_URL ||
  "https://sqs.us-west-1.amazonaws.com/774676933701/primecart-orders-queue";

const dynamoClient = new DynamoDBClient({ region: REGION });
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const sqsClient = new SQSClient({ region: REGION });

async function processOrders() {
  try {
    const result = await sqsClient.send(
      new ReceiveMessageCommand({
        QueueUrl: ORDERS_QUEUE_URL,
        MaxNumberOfMessages: 5,
        WaitTimeSeconds: 10
      })
    );

    if (!result.Messages) {
      console.log("No messages found");
      return;
    }

    for (const message of result.Messages) {
      const order = JSON.parse(message.Body);

      await docClient.send(
        new PutCommand({
          TableName: ORDERS_TABLE_NAME,
          Item: order
        })
      );

      await sqsClient.send(
        new DeleteMessageCommand({
          QueueUrl: ORDERS_QUEUE_URL,
          ReceiptHandle: message.ReceiptHandle
        })
      );

      console.log(`Order saved and message deleted: ${order.orderId}`);
    }
  } catch (err) {
    console.error("Worker error:", err.message);
  }
}

setInterval(processOrders, 5000);

console.log("SQS worker started...");
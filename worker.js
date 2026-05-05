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
      console.log(
        JSON.stringify({
          event: "SQS_NO_MESSAGES",
          timestamp: new Date().toISOString()
        })
      );
      return;
    }

    for (const message of result.Messages) {
      const order = JSON.parse(message.Body);

      try {
        await docClient.send(
          new PutCommand({
            TableName: ORDERS_TABLE_NAME,
            Item: order,
            ConditionExpression: "attribute_not_exists(orderId)"    // Prevent duplicate orders
          })
        );

        console.log(
          JSON.stringify({
            event: "ORDER_SAVED",
            orderId: order.orderId,
            timestamp: new Date().toISOString()
          })
        );
      } catch (err) {
        if (err.name === "ConditionalCheckFailedException") {
          console.warn(
            JSON.stringify({
              event: "DUPLICATE_ORDER_PREVENTED",
              orderId: order.orderId,
              timestamp: new Date().toISOString()
            })
          );
        } else {
          throw err;
        }
      }

      await sqsClient.send(
        new DeleteMessageCommand({
          QueueUrl: ORDERS_QUEUE_URL,
          ReceiptHandle: message.ReceiptHandle
        })
      );

      console.log(
        JSON.stringify({
          event: "SQS_MESSAGE_DELETED",
          orderId: order.orderId,
          timestamp: new Date().toISOString()
        })
      );
    }
  } catch (err) {
    console.error(
      JSON.stringify({
        event: "SQS_WORKER_ERROR",
        error: err.message,
        timestamp: new Date().toISOString()
      })
    );
  }
}

setInterval(processOrders, 5000);

console.log(
  JSON.stringify({
    event: "SQS_WORKER_STARTED",
    region: REGION,
    table: ORDERS_TABLE_NAME,
    timestamp: new Date().toISOString()
  })
);
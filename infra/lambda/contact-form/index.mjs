import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({});
const dynamo = DynamoDBDocumentClient.from(client);

export const handler = async (event) => {
    console.log("Received event:", JSON.stringify(event, null, 2));

    let body;
    try {
        body = JSON.parse(event.body);
    } catch (err) {
        return { statusCode: 400, body: JSON.stringify({ message: "Invalid JSON" }) };
    }

    const { name, email, message } = body;

    if (!name || !email || !message) {
        return { statusCode: 400, body: JSON.stringify({ message: "Missing required fields" }) };
    }

    const id = Date.now().toString();

    try {
        await dynamo.send(
            new PutCommand({
                TableName: process.env.TABLE_NAME,
                Item: { id, name, email, message, createdAt: new Date().toISOString() },
            })
        );

        return {
            statusCode: 200,
            headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*", // Configure properly in production
                "Access-Control-Allow-Methods": "POST, OPTIONS"
            },
            body: JSON.stringify({ message: "Success" }),
        };
    } catch (err) {
        console.error(err);
        return {
            statusCode: 500,
            headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            body: JSON.stringify({ message: "Internal Server Error" }),
        };
    }
};

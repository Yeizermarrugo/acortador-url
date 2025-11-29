import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyHandler } from "aws-lambda";
import { randomBytes } from "crypto";
import process from "process";

//Configuraion de Aws
//Usamos las variables de entorno de la Lambda
const client = new DynamoDBClient({});
const ddbDocClient = DynamoDBDocumentClient.from(client);

const Table_Name = process.env.DYNAMODB_TABLE_NAME;
const Base_Url = process.env.BASE_URL;

const generate = (): string => {
  return randomBytes(4).toString("hex").substring(0, 7);
};

export const handler: APIGatewayProxyHandler = async (event) => {
 let parsedBody = JSON.parse(event.body as string);

  const logURl: string = parsedBody.url;

  if (!logURl) {
    return {
      statusCode: 400,
      body: JSON.stringify({ message: "Missing or invalid url" }),
    };
  }
  //Logica de Acortamiento
  const shortID = generate();
  const shortUrl = `${Base_Url}/${shortID}`;

  const timeStamps = new Date().toISOString();

  try {
    const params = {
      TableName: Table_Name,
      Item: {
        short_id: shortID,
        long_url: logURl,
        created_at: timeStamps,
      },
    };

    await ddbDocClient.send(new PutCommand(params));
    console.log(`URL Saved: ${shortID}${logURl}`);

    return {
      statusCode: 201,
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        short_Url: shortUrl,
        long_url: logURl,
        short_id: shortID,
      }),
    };
  } catch (error) {
    console.error("Error al guardar", error);
    return {
      statusCode: 500,
      body: JSON.stringify({ message: "Internal server Error" }),
    };
  }
};
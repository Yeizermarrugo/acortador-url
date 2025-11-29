import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand } from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyHandlerV2 } from "aws-lambda";
import process from "process";

// Configuración de AWS
// Reutiliza la configuración de DDB
const client = new DynamoDBClient({});
const ddbDocClient = DynamoDBDocumentClient.from(client);

// Obtiene el nombre de la tabla de las variables de entorno de Lambda
const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME; 

export const handler: APIGatewayProxyHandlerV2 = async (event) => {
    console.log("Evento de Redirección (GET) recibido:", JSON.stringify(event, null, 2));

    // 1. Extraer el ID de la URL
    // API Gateway V2 coloca el parámetro de ruta '{short_id}' en event.pathParameters
    const shortId = event.pathParameters?.short_id;

    if (!shortId) {
        return { 
            statusCode: 400, 
            body: JSON.stringify({ message: "Missing short ID in path." }) 
        };
    }

    try {
        // 2. Buscar la URL larga en DynamoDB
        const result = await ddbDocClient.send(new GetCommand({
            TableName: TABLE_NAME,
            Key: { short_id: shortId } // Busca usando la clave primaria
        }));

        const item = result.Item;

        if (!item || !item.long_url) {
            // Si no se encuentra, devuelve 404 Not Found
            return { 
                statusCode: 404, 
                body: JSON.stringify({ message: "URL not found." }) 
            };
        }

        // 3. Redirección HTTP 302
        return {
            statusCode: 302, // 🚨 Código crucial: Redirección Temporal
            headers: {
                // El navegador lee este header y navega a la URL larga
                'Location': item.long_url, 
                // Headers estándar para evitar que el navegador o proxies cacheen la redirección
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Expires': '0'
            },
            body: '' // El cuerpo debe estar vacío para una redirección 302 limpia
        };

    } catch (error) {
        console.error("Error al buscar o redireccionar:", error);
        return { 
            statusCode: 500, 
            body: JSON.stringify({ message: "Internal server error during redirection." }) 
        };
    }
};
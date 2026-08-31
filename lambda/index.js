'use strict';

const { randomUUID } = require('node:crypto');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
  ScanCommand,
} = require('@aws-sdk/lib-dynamodb');

const RESERVED_KEYS = new Set(['id', 'createdAt']);
const MAX_BODY_BYTES = 10240;

function res(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

function parseBody(raw) {
  if (!raw) return { error: 'Body is required', statusCode: 400 };
  if (Buffer.byteLength(raw, 'utf8') > MAX_BODY_BYTES) {
    return { error: 'Payload too large (max 10KB)', statusCode: 413 };
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { error: 'Body must be valid JSON', statusCode: 400 };
  }
  if (typeof parsed !== 'object' || Array.isArray(parsed) || parsed === null) {
    return { error: 'Body must be a JSON object', statusCode: 400 };
  }
  RESERVED_KEYS.forEach((k) => delete parsed[k]);
  if (Object.keys(parsed).length === 0) {
    return { error: 'Body must contain at least one non-reserved field', statusCode: 400 };
  }
  return { data: parsed };
}

function makeHandler(docClient, tableName) {
  return async function handler(event) {
    try {
      const method = event.httpMethod;
      const id = event.pathParameters && event.pathParameters.id;

      if (method === 'GET' && !id) {
        const result = await docClient.send(new ScanCommand({ TableName: tableName }));
        return res(200, result.Items ?? []);
      }

      if (method === 'GET' && id) {
        const result = await docClient.send(
          new GetCommand({ TableName: tableName, Key: { id } })
        );
        if (!result.Item) return res(404, { message: 'Item not found' });
        return res(200, result.Item);
      }

      if (method === 'POST') {
        const { data, error, statusCode } = parseBody(event.body);
        if (error) return res(statusCode, { message: error });
        const item = {
          ...data,
          id: randomUUID(),
          createdAt: new Date().toISOString(),
        };
        await docClient.send(new PutCommand({ TableName: tableName, Item: item }));
        return res(201, item);
      }

      if (method === 'PUT' && id) {
        const { data, error, statusCode } = parseBody(event.body);
        if (error) return res(statusCode, { message: error });
        const keys = Object.keys(data);
        const updateExpr = 'SET ' + keys.map((_, i) => `#k${i} = :v${i}`).join(', ');
        const names = Object.fromEntries(keys.map((k, i) => [`#k${i}`, k]));
        const values = Object.fromEntries(keys.map((k, i) => [`:v${i}`, data[k]]));
        const result = await docClient.send(
          new UpdateCommand({
            TableName: tableName,
            Key: { id },
            UpdateExpression: updateExpr,
            ExpressionAttributeNames: names,
            ExpressionAttributeValues: values,
            ReturnValues: 'ALL_NEW',
          })
        );
        return res(200, result.Attributes);
      }

      if (method === 'DELETE' && id) {
        await docClient.send(new DeleteCommand({ TableName: tableName, Key: { id } }));
        return res(200, { message: 'Item deleted' });
      }

      return res(405, { message: 'Method not allowed' });
    } catch (err) {
      console.error(err);
      return res(500, { message: 'Internal server error' });
    }
  };
}

const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({}));

module.exports = {
  handler: makeHandler(docClient, process.env.TABLE_NAME),
  makeHandler,
};

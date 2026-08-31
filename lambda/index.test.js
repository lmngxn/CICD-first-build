'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler } = require('./index');

const TABLE = 'test-table';

function event({ method, id, body } = {}) {
  return {
    httpMethod: method,
    pathParameters: id ? { id } : null,
    body: body !== undefined
      ? (typeof body === 'string' ? body : JSON.stringify(body))
      : null,
  };
}

function mockClient(sendFn) {
  return { send: sendFn };
}

// ---------------------------------------------------------------------------
// GET /items
// ---------------------------------------------------------------------------

test('GET /items returns all items', async () => {
  const items = [{ id: '1', name: 'foo' }];
  const handler = makeHandler(mockClient(async () => ({ Items: items })), TABLE);
  const result = await handler(event({ method: 'GET' }));
  assert.equal(result.statusCode, 200);
  assert.deepEqual(JSON.parse(result.body), items);
});

test('GET /items returns empty array when table is empty', async () => {
  const handler = makeHandler(mockClient(async () => ({ Items: [] })), TABLE);
  const result = await handler(event({ method: 'GET' }));
  assert.equal(result.statusCode, 200);
  assert.deepEqual(JSON.parse(result.body), []);
});

// ---------------------------------------------------------------------------
// GET /items/{id}
// ---------------------------------------------------------------------------

test('GET /items/{id} returns item when found', async () => {
  const item = { id: '1', name: 'foo' };
  const handler = makeHandler(mockClient(async () => ({ Item: item })), TABLE);
  const result = await handler(event({ method: 'GET', id: '1' }));
  assert.equal(result.statusCode, 200);
  assert.deepEqual(JSON.parse(result.body), item);
});

test('GET /items/{id} returns 404 when not found', async () => {
  const handler = makeHandler(mockClient(async () => ({ Item: undefined })), TABLE);
  const result = await handler(event({ method: 'GET', id: 'missing' }));
  assert.equal(result.statusCode, 404);
});

// ---------------------------------------------------------------------------
// POST /items
// ---------------------------------------------------------------------------

test('POST /items creates item and returns 201', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const result = await handler(event({ method: 'POST', body: { name: 'test' } }));
  assert.equal(result.statusCode, 201);
  const body = JSON.parse(result.body);
  assert.ok(body.id, 'id should be set');
  assert.ok(body.createdAt, 'createdAt should be set');
  assert.equal(body.name, 'test');
});

test('POST /items strips reserved keys id and createdAt', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const result = await handler(
    event({ method: 'POST', body: { id: 'hack', createdAt: 'hack', name: 'real' } })
  );
  assert.equal(result.statusCode, 201);
  const body = JSON.parse(result.body);
  assert.notEqual(body.id, 'hack');
  assert.notEqual(body.createdAt, 'hack');
  assert.equal(body.name, 'real');
});

test('POST /items returns 400 when body is missing', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const result = await handler(event({ method: 'POST' }));
  assert.equal(result.statusCode, 400);
});

test('POST /items returns 400 when body is invalid JSON', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const result = await handler(event({ method: 'POST', body: 'not-json' }));
  assert.equal(result.statusCode, 400);
});

test('POST /items returns 400 when body is a JSON array', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const e = event({ method: 'POST' });
  e.body = JSON.stringify([{ name: 'foo' }]);
  const result = await handler(e);
  assert.equal(result.statusCode, 400);
});

test('POST /items returns 400 when body contains only reserved keys', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const result = await handler(
    event({ method: 'POST', body: { id: '1', createdAt: 'now' } })
  );
  assert.equal(result.statusCode, 400);
});

test('POST /items returns 413 when payload exceeds 10KB', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const e = event({ method: 'POST' });
  e.body = JSON.stringify({ name: 'x'.repeat(11000) });
  const result = await handler(e);
  assert.equal(result.statusCode, 413);
});

// ---------------------------------------------------------------------------
// PUT /items/{id}
// ---------------------------------------------------------------------------

test('PUT /items/{id} returns 200 with updated attributes', async () => {
  const updated = { id: '1', name: 'updated' };
  const handler = makeHandler(
    mockClient(async () => ({ Attributes: updated })),
    TABLE
  );
  const result = await handler(event({ method: 'PUT', id: '1', body: { name: 'updated' } }));
  assert.equal(result.statusCode, 200);
  assert.deepEqual(JSON.parse(result.body), updated);
});

test('PUT /items/{id} returns 400 when body is missing', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const result = await handler(event({ method: 'PUT', id: '1' }));
  assert.equal(result.statusCode, 400);
});

// ---------------------------------------------------------------------------
// DELETE /items/{id}
// ---------------------------------------------------------------------------

test('DELETE /items/{id} returns 200 with confirmation', async () => {
  const handler = makeHandler(mockClient(async () => ({})), TABLE);
  const result = await handler(event({ method: 'DELETE', id: '1' }));
  assert.equal(result.statusCode, 200);
  assert.deepEqual(JSON.parse(result.body), { message: 'Item deleted' });
});

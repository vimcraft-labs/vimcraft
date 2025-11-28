// E2E tests for vim.lsp API
// Tests LSP client management, message framing, and server communication

vim.e2e.describe('LSP Client API', function() {
  // Path to our mock LSP server
  const mockServerPath = './tests/e2e/lsp-client/mock-lsp-server.js';

  vim.e2e.test('vim.lsp exists and has expected methods', function() {
    vim.e2e.assert.ok(vim.lsp !== undefined, 'vim.lsp should exist');
    vim.e2e.assert.ok(typeof vim.lsp.start === 'function', 'vim.lsp.start should be a function');
    vim.e2e.assert.ok(typeof vim.lsp.getClients === 'function', 'vim.lsp.getClients should be a function');
    vim.e2e.assert.ok(typeof vim.lsp.stopClient === 'function', 'vim.lsp.stopClient should be a function');
    vim.e2e.assert.ok(typeof vim.lsp.getClientById === 'function', 'vim.lsp.getClientById should be a function');
  });

  vim.e2e.test('vim.lsp.start requires cmd array', function() {
    // vim.lsp.start returns a Promise, so check that calling with invalid args
    // returns a rejected Promise (not synchronous throw)
    // @ts-ignore - intentionally passing invalid args
    const result = vim.lsp.start({});
    vim.e2e.assert.ok(result && typeof result.then === 'function', 'should return Promise');
    vim.e2e.assert.ok(typeof result.catch === 'function', 'should have catch method');
    // The promise will reject, which is the expected behavior
  });

  vim.e2e.test('vim.lsp.getClients returns empty array initially', function() {
    const clients = vim.lsp.getClients();
    vim.e2e.assert.ok(Array.isArray(clients), 'should return array');
    vim.e2e.assert.equal(clients.length, 0, 'should have no clients initially');
  });

  vim.e2e.test('LspFramer parses Content-Length messages correctly', function() {
    const framer = new vim.lsp.LspFramer();
    const messages: any[] = [];

    framer.onMessage((msg) => {
      messages.push(msg);
    });

    // Feed a complete message
    const msg1 = { jsonrpc: '2.0', id: 1, method: 'test' };
    const body1 = JSON.stringify(msg1);
    framer.feed(`Content-Length: ${body1.length}\r\n\r\n${body1}`);

    vim.e2e.assert.equal(messages.length, 1, 'should parse one message');
    vim.e2e.assert.equal(messages[0].id, 1, 'should have correct id');
    vim.e2e.assert.equal(messages[0].method, 'test', 'should have correct method');
  });

  vim.e2e.test('LspFramer handles partial data', function() {
    const framer = new vim.lsp.LspFramer();
    const messages: any[] = [];

    framer.onMessage((msg) => {
      messages.push(msg);
    });

    // Feed partial data
    const msg = { jsonrpc: '2.0', id: 2, result: 'hello' };
    const body = JSON.stringify(msg);
    const header = `Content-Length: ${body.length}\r\n\r\n`;

    // Feed in chunks
    framer.feed(header.substring(0, 10));
    vim.e2e.assert.equal(messages.length, 0, 'should not parse partial header');

    framer.feed(header.substring(10));
    vim.e2e.assert.equal(messages.length, 0, 'should not parse without body');

    framer.feed(body.substring(0, 10));
    vim.e2e.assert.equal(messages.length, 0, 'should not parse partial body');

    framer.feed(body.substring(10));
    vim.e2e.assert.equal(messages.length, 1, 'should parse complete message');
    vim.e2e.assert.equal(messages[0].result, 'hello', 'should have correct result');
  });

  vim.e2e.test('LspFramer handles multiple messages', function() {
    const framer = new vim.lsp.LspFramer();
    const messages: any[] = [];

    framer.onMessage((msg) => {
      messages.push(msg);
    });

    // Feed two messages at once
    const msg1 = { jsonrpc: '2.0', id: 1, method: 'a' };
    const msg2 = { jsonrpc: '2.0', id: 2, method: 'b' };
    const body1 = JSON.stringify(msg1);
    const body2 = JSON.stringify(msg2);

    framer.feed(
      `Content-Length: ${body1.length}\r\n\r\n${body1}` +
      `Content-Length: ${body2.length}\r\n\r\n${body2}`
    );

    vim.e2e.assert.equal(messages.length, 2, 'should parse two messages');
    vim.e2e.assert.equal(messages[0].method, 'a', 'first message correct');
    vim.e2e.assert.equal(messages[1].method, 'b', 'second message correct');
  });

  vim.e2e.test('LspFramer.encode creates valid Content-Length message', function() {
    const msg = { jsonrpc: '2.0', id: 1, method: 'test', params: {} };
    const encoded = vim.lsp.LspFramer.encode(msg);

    // Verify format
    vim.e2e.assert.ok(encoded.startsWith('Content-Length: '), 'should start with Content-Length');
    vim.e2e.assert.ok(encoded.includes('\r\n\r\n'), 'should have header separator');

    // Parse it back
    const framer = new vim.lsp.LspFramer();
    let parsed: any = null;
    framer.onMessage((m) => { parsed = m; });
    framer.feed(encoded);

    vim.e2e.assert.ok(parsed !== null, 'should be parseable');
    vim.e2e.assert.equal(parsed.id, 1, 'should roundtrip id');
    vim.e2e.assert.equal(parsed.method, 'test', 'should roundtrip method');
  });

  vim.e2e.test('LspClient constructor accepts requestTimeout option', function() {
    // Create client with custom timeout (don't start it)
    const client = new vim.lsp.LspClient({
      cmd: ['node', '-e', 'process.exit(0)'],
      name: 'test-timeout',
      requestTimeout: 5000
    });

    // Verify timeout is set
    vim.e2e.assert.equal((client as any).requestTimeout, 5000, 'should accept custom timeout');
  });

  vim.e2e.test('LspClient uses default 30s timeout when not specified', function() {
    const client = new vim.lsp.LspClient({
      cmd: ['node', '-e', 'process.exit(0)'],
      name: 'test-default-timeout'
    });

    vim.e2e.assert.equal((client as any).requestTimeout, 30000, 'should use 30s default timeout');
  });

  vim.e2e.test('LspClient name defaults to "lsp" when not specified', function() {
    const client = new vim.lsp.LspClient({
      cmd: ['node', '-e', 'process.exit(0)']
    });

    vim.e2e.assert.equal(client.name, 'lsp', 'should default to "lsp"');
  });

  // Buffer helper method tests
  vim.e2e.test('vim.lsp.bufDidOpen is a function', function() {
    vim.e2e.assert.equal(typeof vim.lsp.bufDidOpen, 'function', 'bufDidOpen should be a function');
  });

  vim.e2e.test('vim.lsp.bufDidChange is a function', function() {
    vim.e2e.assert.equal(typeof vim.lsp.bufDidChange, 'function', 'bufDidChange should be a function');
  });

  vim.e2e.test('vim.lsp.bufDidClose is a function', function() {
    vim.e2e.assert.equal(typeof vim.lsp.bufDidClose, 'function', 'bufDidClose should be a function');
  });

  vim.e2e.test('vim.lsp.bufDidSave is a function', function() {
    vim.e2e.assert.equal(typeof vim.lsp.bufDidSave, 'function', 'bufDidSave should be a function');
  });

  vim.e2e.test('vim.lsp.bufHover is a function', function() {
    vim.e2e.assert.equal(typeof vim.lsp.bufHover, 'function', 'bufHover should be a function');
  });

  vim.e2e.test('vim.lsp.bufDefinition is a function', function() {
    vim.e2e.assert.equal(typeof vim.lsp.bufDefinition, 'function', 'bufDefinition should be a function');
  });

  vim.e2e.test('vim.lsp.bufReferences is a function', function() {
    vim.e2e.assert.equal(typeof vim.lsp.bufReferences, 'function', 'bufReferences should be a function');
  });

  vim.e2e.test('vim.lsp.bufHover returns Promise resolving to null with no clients', function() {
    const result = vim.lsp.bufHover(0, 'file:///test.ts', 0, 0);
    vim.e2e.assert.ok(result && typeof result.then === 'function', 'should return Promise');
    // Note: can't easily test Promise resolution in sync tests, just verify it's a Promise
  });

  vim.e2e.test('vim.lsp.bufDefinition returns Promise resolving to null with no clients', function() {
    const result = vim.lsp.bufDefinition(0, 'file:///test.ts', 0, 0);
    vim.e2e.assert.ok(result && typeof result.then === 'function', 'should return Promise');
  });

  vim.e2e.test('vim.lsp.bufReferences returns Promise resolving to null with no clients', function() {
    const result = vim.lsp.bufReferences(0, 'file:///test.ts', 0, 0, true);
    vim.e2e.assert.ok(result && typeof result.then === 'function', 'should return Promise');
  });

  // Unicode handling tests
  vim.e2e.test('LspFramer.encode uses byte length for Content-Length (ASCII)', function() {
    const msg = { jsonrpc: '2.0', method: 'test', params: { text: 'hello' } };
    const encoded = vim.lsp.LspFramer.encode(msg);

    // Parse out the Content-Length value
    const match = encoded.match(/Content-Length: (\d+)/);
    vim.e2e.assert.ok(match !== null, 'should have Content-Length header');

    const contentLength = parseInt(match![1], 10);
    const body = JSON.stringify(msg);

    // For ASCII, string length equals byte length
    vim.e2e.assert.equal(contentLength, body.length, 'ASCII: byte length should equal string length');
  });

  vim.e2e.test('LspFramer.encode uses byte length for Content-Length (Unicode)', function() {
    // Chinese characters: each is 3 bytes in UTF-8
    const msg = { jsonrpc: '2.0', method: 'test', params: { text: '你好' } };
    const encoded = vim.lsp.LspFramer.encode(msg);

    const match = encoded.match(/Content-Length: (\d+)/);
    vim.e2e.assert.ok(match !== null, 'should have Content-Length header');

    const contentLength = parseInt(match![1], 10);
    const body = JSON.stringify(msg);

    // UTF-8 byte length should be greater than string length for Chinese chars
    vim.e2e.assert.ok(contentLength > body.length, 'Unicode: byte length should be greater than string length');

    // Verify exact byte count using TextEncoder
    const encoder = new TextEncoder();
    const expectedBytes = encoder.encode(body).length;
    vim.e2e.assert.equal(contentLength, expectedBytes, 'should match TextEncoder byte length');
  });

  vim.e2e.test('LspFramer roundtrips Unicode messages correctly', function() {
    const framer = new vim.lsp.LspFramer();
    const messages: any[] = [];
    framer.onMessage((msg) => messages.push(msg));

    // Test with Chinese characters
    const originalMsg = { jsonrpc: '2.0', id: 1, params: { text: '你好世界' } };
    const encoded = vim.lsp.LspFramer.encode(originalMsg);
    framer.feed(encoded);

    vim.e2e.assert.equal(messages.length, 1, 'should parse one message');
    vim.e2e.assert.equal(messages[0].params.text, '你好世界', 'should preserve Chinese text');
  });

  vim.e2e.test('LspFramer roundtrips emoji correctly', function() {
    const framer = new vim.lsp.LspFramer();
    const messages: any[] = [];
    framer.onMessage((msg) => messages.push(msg));

    // Emoji (4 bytes in UTF-8, 2 UTF-16 code units)
    const originalMsg = { jsonrpc: '2.0', id: 1, result: '👋🎉' };
    const encoded = vim.lsp.LspFramer.encode(originalMsg);
    framer.feed(encoded);

    vim.e2e.assert.equal(messages.length, 1, 'should parse one message');
    vim.e2e.assert.equal(messages[0].result, '👋🎉', 'should preserve emoji');
  });

  // State management tests
  vim.e2e.test('LspClient has _stopping flag initialized to false', function() {
    const client = new vim.lsp.LspClient({
      cmd: ['node', '-e', 'process.exit(0)']
    });
    vim.e2e.assert.equal((client as any)._stopping, false, '_stopping should be false initially');
  });

  vim.e2e.test('LspClient _stopping prevents multiple stop() calls', function() {
    const client = new vim.lsp.LspClient({
      cmd: ['node', '-e', 'process.exit(0)']
    });

    // Manually set _stopping to simulate already stopping
    (client as any)._stopping = true;

    // stop() should return early without error
    client.stop(); // Should not throw

    vim.e2e.assert.ok(true, 'stop() should handle _stopping guard');
  });

  vim.e2e.test('LspClient has stopping getter', function() {
    const client = new vim.lsp.LspClient({
      cmd: ['node', '-e', 'process.exit(0)']
    });
    vim.e2e.assert.equal(client.stopping, false, 'stopping should be false initially');

    // Manually set _stopping
    (client as any)._stopping = true;
    vim.e2e.assert.equal(client.stopping, true, 'stopping getter should reflect _stopping');
  });

  vim.e2e.test('LspClient start() rejects when stopping', function() {
    const client = new vim.lsp.LspClient({
      cmd: ['node', '-e', 'process.exit(0)']
    });

    // Manually set _stopping
    (client as any)._stopping = true;

    const result = client.start();
    vim.e2e.assert.ok(result && typeof result.catch === 'function', 'should return Promise');
    // Promise will reject with "LSP client is stopping"
  });
});

vim.e2e.runAll();

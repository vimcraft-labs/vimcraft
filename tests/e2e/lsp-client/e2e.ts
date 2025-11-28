// E2E tests for vim.lsp API
// Tests LSP client management, message framing, and server communication

vim.e2e.describe('LSP Client API', function() {
  // Path to our mock LSP server
  const mockServerPath = './tests/e2e/lsp-client/mock-lsp-server.js';

  vim.e2e.test('vim.lsp exists and has expected methods', function() {
    vim.e2e.assert.ok(vim.lsp !== undefined, 'vim.lsp should exist');
    vim.e2e.assert.ok(typeof vim.lsp.start === 'function', 'vim.lsp.start should be a function');
    vim.e2e.assert.ok(typeof vim.lsp.get_clients === 'function', 'vim.lsp.get_clients should be a function');
    vim.e2e.assert.ok(typeof vim.lsp.stop_client === 'function', 'vim.lsp.stop_client should be a function');
    vim.e2e.assert.ok(typeof vim.lsp.get_client_by_id === 'function', 'vim.lsp.get_client_by_id should be a function');
  });

  vim.e2e.test('vim.lsp.start requires cmd array', function() {
    let threw = false;
    try {
      // @ts-ignore - intentionally passing invalid args
      vim.lsp.start({});
    } catch (e) {
      threw = true;
    }
    vim.e2e.assert.true(threw, 'should throw without cmd');
  });

  vim.e2e.test('vim.lsp.get_clients returns empty array initially', function() {
    const clients = vim.lsp.get_clients();
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
});

vim.e2e.runAll();

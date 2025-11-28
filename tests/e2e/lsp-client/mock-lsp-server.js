#!/usr/bin/env node
// Mock LSP server for testing vim.lsp API
// Implements minimal LSP protocol over stdio

let buffer = '';
let contentLength = -1;

// Read stdin
process.stdin.setEncoding('utf8');
process.stdin.on('data', (data) => {
  buffer += data;
  parseMessages();
});

function parseMessages() {
  while (true) {
    // Looking for Content-Length header
    if (contentLength === -1) {
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd === -1) return;

      const headers = buffer.substring(0, headerEnd);
      const match = headers.match(/Content-Length:\s*(\d+)/i);
      if (!match) {
        // Skip malformed
        buffer = buffer.substring(headerEnd + 4);
        continue;
      }
      contentLength = parseInt(match[1], 10);
      buffer = buffer.substring(headerEnd + 4);
    }

    // Waiting for body
    if (buffer.length < contentLength) return;

    const body = buffer.substring(0, contentLength);
    buffer = buffer.substring(contentLength);
    contentLength = -1;

    try {
      const msg = JSON.parse(body);
      handleMessage(msg);
    } catch (e) {
      // Ignore parse errors
    }
  }
}

function sendMessage(msg) {
  const body = JSON.stringify(msg);
  const header = `Content-Length: ${body.length}\r\n\r\n`;
  process.stdout.write(header + body);
}

function sendResponse(id, result) {
  sendMessage({ jsonrpc: '2.0', id, result });
}

function sendNotification(method, params) {
  sendMessage({ jsonrpc: '2.0', method, params });
}

function handleMessage(msg) {
  if ('id' in msg && 'method' in msg) {
    // Request from client
    handleRequest(msg);
  } else if ('method' in msg) {
    // Notification from client
    handleNotification(msg);
  }
}

function handleRequest(msg) {
  const { id, method, params } = msg;

  switch (method) {
    case 'initialize':
      // Return mock capabilities
      sendResponse(id, {
        capabilities: {
          textDocumentSync: 1, // Full sync
          hoverProvider: true,
          definitionProvider: true,
          referencesProvider: true,
          completionProvider: {
            triggerCharacters: ['.'],
          },
        },
        serverInfo: {
          name: 'mock-lsp-server',
          version: '1.0.0',
        },
      });
      break;

    case 'shutdown':
      sendResponse(id, null);
      break;

    case 'textDocument/hover':
      // Return mock hover
      sendResponse(id, {
        contents: {
          kind: 'plaintext',
          value: `Hover info for line ${params.position.line}, char ${params.position.character}`,
        },
        range: {
          start: params.position,
          end: { line: params.position.line, character: params.position.character + 5 },
        },
      });
      break;

    case 'textDocument/definition':
      // Return mock definition
      sendResponse(id, {
        uri: params.textDocument.uri,
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 10 },
        },
      });
      break;

    case 'textDocument/references':
      // Return mock references
      sendResponse(id, [
        {
          uri: params.textDocument.uri,
          range: {
            start: { line: 5, character: 0 },
            end: { line: 5, character: 10 },
          },
        },
        {
          uri: params.textDocument.uri,
          range: {
            start: { line: 10, character: 0 },
            end: { line: 10, character: 10 },
          },
        },
      ]);
      break;

    default:
      // Unknown method - return error
      sendMessage({
        jsonrpc: '2.0',
        id,
        error: { code: -32601, message: `Method not found: ${method}` },
      });
  }
}

function handleNotification(msg) {
  const { method, params } = msg;

  switch (method) {
    case 'initialized':
      // Client is ready, send a test diagnostic
      setTimeout(() => {
        sendNotification('textDocument/publishDiagnostics', {
          uri: 'file:///test/file.ts',
          diagnostics: [
            {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 0, character: 5 },
              },
              severity: 1, // Error
              message: 'Test error from mock LSP',
              source: 'mock-lsp',
            },
          ],
        });
      }, 100);
      break;

    case 'exit':
      process.exit(0);
      break;

    case 'textDocument/didOpen':
    case 'textDocument/didChange':
    case 'textDocument/didClose':
    case 'textDocument/didSave':
      // Acknowledge document sync notifications silently
      break;
  }
}

// Handle stdin close
process.stdin.on('end', () => {
  process.exit(0);
});

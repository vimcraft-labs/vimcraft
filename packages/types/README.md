# @openvim/types

TypeScript type definitions for OpenVim configuration API.

## Installation

```bash
npm install --save-dev @openvim/types
# or
yarn add --dev @openvim/types
# or
pnpm add --save-dev @openvim/types
```

## Usage

### JavaScript with JSDoc

Add type checking to your `init.js`:

```javascript
// @ts-check
/// <reference types="@openvim/types" />

// Now you get autocomplete and type checking!
vim.highlight('CursorLine', { bg: '#2b2b2b' });
vim.opt.cursorline = true;

setInterval(() => {
  console.log('Timer tick');
}, 1000);
```

### TypeScript

Create `init.ts`:

```typescript
/// <reference types="@openvim/types" />

vim.highlight('Comment', {
  fg: '#6c6c6c',
  italic: true
});

vim.opt.cursorline = true;

// You get full autocomplete and type checking
```

Then compile to JavaScript:

```bash
npx tsc init.ts --outDir ~/.config/openvim
```

### Available APIs

#### `vim.highlight(name, opts)`

Define syntax highlighting:

```typescript
vim.highlight('CursorLine', { bg: '#2b2b2b' });
vim.highlight('LineNr', { fg: '#6c6c6c' });
vim.highlight('String', { fg: '#98c379', bold: true });
```

#### `vim.opt`

Editor options:

```typescript
vim.opt.cursorline = true;
```

#### `console.log(...args)`

Debug logging to Chrome DevTools:

```typescript
console.log('Hello from OpenVim!');
console.log('Multiple', 'arguments', { foo: 'bar' });
```

#### Timers

```typescript
// setTimeout
const timeoutId = setTimeout(() => {
  console.log('Delayed execution');
}, 1000);
clearTimeout(timeoutId);

// setInterval
const intervalId = setInterval(() => {
  console.log('Repeating');
}, 2000);
clearInterval(intervalId);
```

## Type Definitions

See [src/index.d.ts](./src/index.d.ts) for full type definitions.

## Development

This package contains only type definitions. There is no runtime code.

## License

MIT

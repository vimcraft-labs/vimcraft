# TypeScript Setup Guide

Enable IDE autocomplete and type checking for Vimcraft configuration.

---

## Why TypeScript?

- ✅ Full autocomplete for all APIs
- ✅ Type checking catches errors
- ✅ Inline documentation
- ✅ Better refactoring

---

## Installation

### 1. Install Dependencies

```bash
cd /path/to/vimcraft

# Install @vimcraft/types package
npm install --save-dev ./packages/types
```

### 2. Create tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2017",
    "module": "commonjs",
    "lib": ["ES2017"],
    "outDir": "/Users/yourusername/.config/vimcraft",
    "rootDir": "./",
    "strict": false,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "typeRoots": ["./node_modules/@types", "./packages/types/src"],
    "moduleResolution": "node"
  },
  "include": ["init.ts"],
  "exclude": ["node_modules", "dist", "vendor"]
}
```

### 3. Create init.ts

```typescript
/// <reference types="@vimcraft/types" />

// Now you get full autocomplete!
vim.opt.cursorLine = true;
vim.opt.number = true;

vim.highlight('Comment', {
  fg: '#6c6c6c',
  italic: true
});

console.log('✅ TypeScript config loaded!');
```

### 4. Build Config

```bash
# Build once
npm run build:config

# Or watch for changes
npm run watch:config
```

---

## IDE Integration

### VS Code

1. Open Vimcraft folder in VS Code
2. Open init.ts
3. Start typing `vim.` - see autocomplete!

### Other IDEs

Any IDE with TypeScript support will work.

---

## Benefits

```typescript
// ❌ Without types - typo goes unnoticed
vim.opt.relativenumber = true;  // Wrong name!

// ✅ With types - error caught immediately
vim.opt.relativeNumber = true;  // Correct!
```

---

See [TypeScript Types Reference](../api/typescript-types.md) for more details.

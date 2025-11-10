# Contributing Guidelines

How to contribute to OpenVim.

---

## Contribution Workflow

1. **Fork & Clone**
```bash
git clone https://github.com/vimcraft-labs/vimcraft
cd openvim
```

2. **Create Branch**
```bash
git checkout -b feature/my-feature
```

3. **Make Changes**
- Write code
- Add tests
- Update docs

4. **Test**
```bash
zig build test
```

5. **Commit**
```bash
git add .
git commit -m "feat: add feature"
```

6. **Push & PR**
```bash
git push origin feature/my-feature
```

Then create Pull Request on GitHub.

---

## Code Style

### Zig

- Run `zig fmt` before committing
- 4-space indentation
- snake_case for functions
- PascalCase for types

### JavaScript/TypeScript

- camelCase for variables
- Use TypeScript types
- Document public APIs

---

## Commit Messages

Format:
```
<type>(<scope>): <subject>
```

Types: feat, fix, docs, refactor, test, chore

Example:
```
feat(movement): add word motion (w/b/e)
```

---

## Pull Request Process

1. Ensure all tests pass
2. Update documentation
3. Describe changes clearly
4. Link related issues
5. Wait for review

---

## Community Guidelines

- Be respectful
- Help others
- Share knowledge
- Have fun!

---

Thank you for contributing! 🚀

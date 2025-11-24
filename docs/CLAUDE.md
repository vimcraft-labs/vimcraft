# Documentation

Domain-specific guidance for documentation structure and maintenance.

## Overview

Documentation is first-class in Vimcraft. All features must be documented before merge.

## Key Files

| Component | File:Line | Purpose |
|-----------|-----------|---------|
| **Main Index** | `README.md:1` | Navigation hub |
| **API Index** | `api/README.md:1` | API references |
| **Architecture Index** | `architecture/README.md:1` | Design docs |
| **Development Index** | `development/README.md:1` | Dev guides |
| **Roadmap Index** | `roadmap/README.md:1` | Phase plans |

## Decision Tree

```
Adding documentation?
├── API reference → docs/api/
├── Architecture design → docs/architecture/
├── Development guide → docs/development/
├── Feature roadmap → docs/roadmap/
├── Bug case study → docs/bugfixes/
├── Design proposal → docs/design/
└── Research notes → docs/research/

Updating docs?
├── Code changed → Update same commit
├── API added → Update api/*.md
├── Feature complete → Update roadmap/*.md
├── Bug fixed → Add bugfixes/*.md
└── Process changed → Update development/*.md
```

## Documentation Structure

| Category | Location | Purpose | Audience |
|----------|----------|---------|----------|
| **api/** | API references | Complete API docs | Plugin devs |
| **architecture/** | Design documents | Technical depth | Contributors |
| **development/** | Dev guides | How-to guides | Contributors |
| **guides/** | User guides | Step-by-step | Users |
| **roadmap/** | Phase plans | Implementation | All |
| **research/** | Analysis docs | Deep dives | Advanced |
| **design/** | Proposals | Future features | Contributors |
| **bugfixes/** | Case studies | Lessons learned | Contributors |

## Common Tasks

| Task | Steps | Location |
|------|-------|----------|
| **Add API** | Document → Add types → Examples | `api/*.md` |
| **Document bug** | Create file → Symptoms → Root cause → Fix | `bugfixes/*.md` |
| **Update roadmap** | Check items → Add dates → Link PRs | `roadmap/*.md` |
| **Write guide** | Step-by-step → Examples → Troubleshooting | `guides/*.md` |

## Documentation Patterns

### API Documentation
```markdown
## vim.motion.left()

Moves cursor left by one character.

**Returns**: `void`

**Example**:
```javascript
vim.motion.left();
```

**Behavior**:
- Stops at line beginning
- No-op at position (0,0)
```

### Architecture Document
```markdown
# Feature Architecture

## Why This Design
[Rationale and alternatives]

## Components
| Component | Purpose | Location |
|-----------|---------|----------|

## Performance
[Benchmarks and implications]

## Future Work
[Extensions and improvements]
```

### Bug Fix Case Study
```markdown
# Bug: [Name]

## Symptoms
- User reports X
- Visible as Y

## Root Cause
[Technical explanation]

## Fix
[Solution with code]

## Lessons Learned
- Key insight 1
- Pattern to watch for
```

## Quality Checklist

| Item | Check | Tool/Method |
|------|-------|-------------|
| **Spelling** | ✓ | Spell checker |
| **Links** | ✓ | `grep -r "\[.*\]("` |
| **Code examples** | ✓ | Test compilation |
| **Cross-refs** | ✓ | Link between docs |
| **Category README** | ✓ | Update index |
| **Main README** | ✓ | Update navigation |

## Markdown Standards

### Tables (Preferred over lists)
```markdown
| Column | Description |
|--------|-------------|
| Use | For structured data |
```

### Code Blocks with Language
```zig
// Always specify language
test "example" {
    try std.testing.expect(true);
}
```

### Status Markers
| Marker | Meaning |
|--------|---------|
| ✅ | Complete |
| 🚧 | In Progress |
| 📅 | Planned |
| ❌ | Cancelled |
| ⚠️ | Warning |

### Cross-References
```markdown
See [Testing Guide](../development/testing-architecture.md)
Related: [JSI Design](../architecture/jsi-hostobject-architecture.md)
```

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|--------------|-----|
| Broken links | File moved/renamed | Update paths |
| Outdated examples | Code changed | Test and update |
| Missing in index | Forgot to add | Update README.md |
| Wrong category | Misunderstood purpose | Move to correct dir |
| No timestamps | Missing context | Add dates to time-sensitive |

## Maintenance Schedule

| Frequency | Tasks | Priority |
|-----------|-------|----------|
| **Per Commit** | Update affected docs | High |
| **Weekly** | Fix broken links, update status | Medium |
| **Per Release** | Archive old, create notes | High |
| **Continuous** | Improve unclear sections | Low |

## Documentation Metrics

| Metric | Target | Current |
|--------|--------|---------|
| API coverage | 100% | Track in api/ |
| Broken links | 0 | Check weekly |
| Example accuracy | 100% | Test on change |
| Cross-references | All related | Add continuously |

## Common Pitfalls

| Pitfall | Symptom | Prevention |
|---------|---------|------------|
| Outdated docs | Confusion | Update with code |
| No examples | Hard to understand | Always include |
| Wrong location | Hard to find | Follow structure |
| Missing cross-refs | Incomplete picture | Link related |
| No update date | Unknown freshness | Add timestamps |

## Writing Guidelines

| Principle | Do | Don't |
|-----------|-----|-------|
| **Clarity** | Use tables | Long paragraphs |
| **Examples** | Show real code | Abstract descriptions |
| **Structure** | Clear headers | Deep nesting |
| **Updates** | Same commit as code | Defer to later |
| **Links** | Test before commit | Assume they work |

## Tools and Commands

### Find Broken Links
```bash
# Check internal links
grep -r "\[.*\](" docs/ | grep -v http | while read line; do
    # Validate each link
done
```

### Documentation Size
```bash
# Total documentation
find docs -name "*.md" | xargs wc -l
```

### Check Structure
```bash
# Ensure all categories have README
for dir in docs/*/; do
    test -f "$dir/README.md" || echo "Missing: $dir/README.md"
done
```

## Future Improvements

| Feature | Priority | Benefit |
|---------|----------|---------|
| Auto link checking | High | CI validation |
| Coverage metrics | Medium | Quality tracking |
| Interactive examples | Low | Better learning |
| Search functionality | Medium | Easy discovery |
| Video tutorials | Low | Visual learning |

## Cross-References

**Parent**: [Main CLAUDE.md](../CLAUDE.md)
**Categories**: [API](api/) · [Architecture](architecture/) · [Development](development/) · [Roadmap](roadmap/)
**Key Docs**: [Testing](development/testing-architecture.md) · [JSI](architecture/jsi-hostobject-architecture.md) · [Contributing](development/contributing.md)
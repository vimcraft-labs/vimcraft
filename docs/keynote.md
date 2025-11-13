# Vimcraft Demo Script (Final)
## IDE for Agentic AI Development

---

## OPENING (1 minute)

[Simple. Direct.]

**"We believe in something."**

**"Neovim's genius isn't features. It's philosophy: you build your own environment using primitives."**

**"You compose the tools you need. You own your future."**

**"That philosophy should apply to agent development too."**

**"We built Vimcraft on that belief."**

---

## PART 1: THE PHILOSOPHY (1 minute)

**"Agent developers should own their development environment."**

**"Not vendor-locked. Not proprietary. Not decided by others."**

**"You should have primitives. Combine them your way. Build custom agents for your use case."**

**"Like Unix pipes. Like Neovim Lua. Like developers have been doing forever."**

**"Agent development deserves the same respect."**

---

## PART 2: PRIMITIVE BLOCKS (2 minutes)

**"Neovim doesn't give you 'features.' It gives you APIs."**

**[Screen shows]**

```lua
-- Neovim primitives
vim.api.nvim_buf_get_lines(buf, start, end)
vim.fn.search(pattern)
vim.api.nvim_command("set number")

-- You compose these into custom tools
```

**"Vimcraft does the same for agents."**

**[Screen shows]**

```javascript
// Vimcraft primitives for agents

// Buffer API
agent.buffer.read(fileId)
agent.buffer.write(fileId, content)
agent.buffer.list()

// Debugger API
agent.debugger.breakpoint(file, line)
agent.debugger.step()
agent.debugger.getStackTrace()
agent.debugger.getVariables()

// Context API (persistent state)
agent.context.write("key", data)
agent.context.read("key")
agent.context.clear()

// Shell API
agent.shell.run(command)
agent.shell.readOutput()

// Search API
agent.search.grep(pattern)
agent.search.findDefinition(symbol)

// Navigation API
agent.navigate.goto(file, line)
agent.navigate.openFile(path)
```

**"Low-level. Composable. Yours to combine."**

---

## PART 3: SHOW IT (4 minutes)

**[Open Vimcraft]**

**"Watch what a developer does with primitives."**

---

### **Agent 1: Code Analyzer**

```javascript
// ~/.config/vimcraft/agents/analyzer.js

export const analyzer = {
  async analyze(filePath) {
    const code = await agent.buffer.read(filePath);
    
    await agent.context.write("code_to_analyze", code);
    
    const issues = await agent.shell.run(`eslint ${filePath}`);
    
    await agent.context.write("analysis", { issues, code });
    
    return agent.context.read("analysis");
  }
};

// Use it:
// :RunAgent analyzer.analyze("src/main.js")
```

**"This developer used: buffer.read, context.write, shell.run."**

**"That's it. They built their analyzer."**

---

### **Agent 2: Debug Helper**

```javascript
// ~/.config/vimcraft/agents/debug-helper.js

export const debugHelper = {
  async help(errorMsg) {
    const stackTrace = await agent.debugger.getStackTrace();
    const vars = await agent.debugger.getVariables();
    
    await agent.context.write("debug_context", {
      error: errorMsg,
      stackTrace,
      variables: vars
    });
    
    const suggestion = await claude.chat(
      agent.context.read("debug_context")
    );
    
    await agent.buffer.write("debug_output.md", suggestion);
    await agent.navigate.openFile("debug_output.md");
  }
};

// Use it:
// :RunAgent debugHelper.help("TypeError: x is undefined")
```

**"This developer used: debugger.getStackTrace, context.write, shell (claude call), buffer.write, navigate."**

**"Different combination. Different use case."**

---

### **Agent 3: Test Generator**

```javascript
// ~/.config/vimcraft/agents/test-generator.js

export const testGen = {
  async generateFor(functionName) {
    const files = await agent.search.findDefinition(functionName);
    const funcCode = await agent.buffer.read(files[0]);
    
    await agent.context.write("function_to_test", {
      name: functionName,
      code: funcCode
    });
    
    const tests = await claude.generate(
      agent.context.read("function_to_test")
    );
    
    const testFile = files[0].replace("src/", "tests/");
    await agent.buffer.write(testFile, tests);
    
    const results = await agent.shell.run(`npm test ${testFile}`);
    await agent.context.write("test_results", results);
    
    await agent.navigate.openFile(testFile);
  }
};

// Use it:
// :RunAgent testGen.generateFor("calculateTotal")
```

**"This developer used: search.findDefinition, buffer.read, context, claude.generate, shell.run, navigate."**

**"Again, different combination."**

---

**"See the pattern?"**

**"Nobody told these developers 'here's test generation.' They composed primitives into it."**

**"Buffer read. Search. Context. Shell execution. Navigation."**

**"That's power. That's ownership."**

---

## PART 4: THE PHILOSOPHY AGAIN (1 minute)

**"We're not saying 'here's a test generator.'"**

**"We're saying 'here are primitives. You decide what they become.'"**

**"Like Unix: `cat`, `grep`, `awk` → you build what you need."**

**"Like Neovim: buffer API, window API, command API → you build your editor."**

**"Like Vimcraft: buffer API, debugger API, context API → you build your agents."**

**"We give you primitives. You own the future."**

---

## PART 5: WHO THIS IS FOR (1 minute)

**"This is for developers who:"**

- **Build agents** (not just use them)
- **Write JavaScript** (native language)
- **Want to own their environment** (customize, fork, modify)
- **Think in compositions** (combine pieces, like Unix)
- **Iterate safely** (sandbox, not production risk)

**"If you're this person, Vimcraft is for you."**

**"If you prefer finished products, that's fine too. Use Claude Code or Cursor."**

---

## PART 6: OPEN SOURCE (1 minute)

**"Vimcraft is open source. MIT license."**

**"You can:"**

- **Fork it** (own your version)
- **Extend primitives** (add new APIs)
- **Build agents** (share on GitHub)
- **Run offline** (no dependency)
- **Own your future** (all yours)

**"This is infrastructure. For developers who want to own it."**

---

## PART 7: SHOW IT WORKING (1 minute)

**[Terminal]**

```bash
$ vimcraft

# Open Vimcraft, see Neovim as always

:RunAgent analyzer.analyze("src/main.js")
# Results in context blocks

# Edit agent:
:e ~/.config/vimcraft/agents/analyzer.js

# Modify for your needs

:RunAgent analyzer.analyze("src/main.js")
# Run modified version

# See new results. Iterate.
# No vendor approval. No lock-in.
# Just you and your primitives.
```

**"That's the workflow."**

---

## PART 8: THE ASK (30 seconds)

**"If you build agents, try Vimcraft."**

**"Use primitives to build something custom for your workflow."**

**"See if you like owning your environment."**

**"If you do, build more. Share with community."**

**"If you don't, no problem. Use what works for you."**

**[Link]**

```
github.com/vimcraft-labs/vimcraft

Primitives for agent development.
Open source. Yours.
```

**[Done.]**

---

## CORE CONCEPT

**Vimcraft = Primitives for agent development**

Like:
- **Unix:** `cat`, `grep`, `awk` (system automation)
- **Neovim:** buffer API, window API (editor customization)
- **Vimcraft:** buffer API, debugger API, context API (agent development)

**Not products. Primitives.**

**Developers compose them into custom agents.**

---

## POSITIONING

> **"Vimcraft: Primitives for agentic AI development. Open source. Yours to own."**

---

## BELIEFS (Not Problems)

We believe:
- ✓ Developers should own their agent dev environment
- ✓ Primitives enable composition and customization
- ✓ JavaScript is the right language for AI tooling
- ✓ Open source empowers builders
- ✓ Sandbox safety matters for agent iteration

**Not:**
- ✗ "Claude Code is broken"
- ✗ "Cursor is locked-in"
- ✗ "Other tools are wrong"

Just what we believe in. That's it.

---

## REALISTIC SCOPE

**Vimcraft is:**
- A sandbox environment
- With primitive APIs for agents
- Written in JavaScript
- Customizable like Neovim
- Open source
- For agent developers specifically

**Vimcraft is NOT:**
- The only way to build agents
- Better than all alternatives
- For everyone
- A finished product you use as-is

---

## THE HONEST TRUTH

We built something for a specific person:
- Developer who builds agents
- Wants ownership over environment
- Thinks in compositions (Unix philosophy)
- Writes JavaScript
- Values open source

**If that's you, try Vimcraft.**

**If not, that's fine. Use what works for you.**

---

**That's Vimcraft. Honest. Specific. Powerful for the right people.**
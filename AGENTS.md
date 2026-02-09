# AGENTS.md

## Interaction Mode

By default, operate in **minimal mode**:
- Answer questions directly in the message. Do not write code, edit files, or make
  tool calls unless a command word is used.
- Reading files to inform your answer is always allowed.
- When in doubt, just write it in the message.

## Command Words

These keywords grant specific permissions. You MUST wait for the exact keyword — 
"yes", "sure", "go ahead" do NOT count. The user must say the word itself.

| Command         | Permission                                              |
|-----------------|---------------------------------------------------------|
| `build`         | Write/edit code in the codebase                         |
| `search`        | Use web fetch to research external information          |
| `output`        | Write the response or context-specific output to a .md  |
| `run`           | Execute shell commands (tests, builds, scripts)         |
| `commit`        | Stage and commit changes with git                       |

Commands can be combined: "search and build" grants both web search and code editing.

## Suggestions

You should proactively suggest when an action would help, but never act on it:
- "Searching might help here" — if external info would improve the answer
- "Should I build?" — if you notice a good moment to write code
- When asked how to implement something, show the snippet in the chat message,
  then ask "Should I build?"

These are suggestions only. Do not proceed until the user responds with the
exact command word.

---

This is a personal Neovim configuration repo (Lua-based). It includes custom utility
modules (`lua/utils/`) with test coverage, plugin specs for lazy.nvim (`lua/plugins/`),
and companion configs for WezTerm, Zsh, and PowerShell.

## Build & Test

Tests use **plenary.nvim's busted** framework and run headless.

```bash
# Run all tests
make test

# Run a single test file
nvim --headless -u ./specs/init.lua -c "PlenaryBustedFile specs/ai_chat_spec.lua"
```

There is no build step or linter configured. No CI pipeline.

## Project Structure

```
init.lua                  Entry point (leader key, requires top-level modules)
lua/
  set.lua                 Editor options (vim.opt)
  keymaps.lua             Global keybindings
  autocommands.lua        Autocmds
  commands.lua            User commands
  initlazy.lua            lazy.nvim bootstrap
  plugins/                One file per lazy.nvim plugin spec (auto-imported)
  plugins/lsp_custom/     Custom LSP integration modules
  snippets/               LuaSnip snippet definitions
  utils/                  Homegrown utility modules (terminal, ai)
specs/                    Test files (*_spec.lua)
  init.lua                Test bootstrap (loads plenary)
```

Custom utility modules under `lua/utils/` are the primary things with test coverage.
Plugin specs under `lua/plugins/` generally do not have tests.

## Testing Conventions

Tests are **functional, not unit tests**. They exercise real Neovim APIs (buffers,
windows, keymaps) from the user's perspective. Test doubles are used sparingly.

### Structure

```lua
local eq = assert.are.same

local function helper() end

describe("Feature Name", function()
    local mod = require("utils.module")

    before_each(function()
        -- reset state
    end)

    it("behavior description", function()
        -- arrange (if needed)

        -- act

        -- assert
    end)
end)
```

### Rules

- **Test from the user's perspective.** If the user opens an input popup, types text,
  and presses Enter, the test should do exactly that. Do not call internal functions
  that the user doesn't interact with.
- **Arrange / Act / Assert** separated by blank lines. No comments labeling the sections.
  If arrange is trivial or combined with act, two sections is fine.
- **No mocking frameworks.** Stubs are manual, same pattern as the codebase's
  `spyOnTermOpen` — replace the function on the module table directly, reset in
  `before_each`.
- **Snapshot shared state** with `vim.deepcopy()` when spying on tables that callbacks
  will mutate.
- **Every assertion has a failure message:** `eq(actual, expected, "what went wrong")`
  or `assert(condition, "what went wrong")`.
- **Test idempotency** — calling the same operation twice should be safe.
- **Test edge cases** — empty state, no-op operations, error paths.
- **No waits, no sleeps.** Tests must run fast and deterministically.
- **No brittleness.** If the app works, all tests pass. If a test fails, that same
  functionality would fail for a real user.
- **Helpers** are `local function` at file scope before the `describe` block.

## Git Conventions

- Short, single-line commit messages
- Imperative or descriptive tone: `"Add functional tests for AI chat plugin"`
- No conventional-commits prefix required

## Cross-Platform

The codebase targets Windows, macOS, and Linux:
- Shell detection: `vim.fn.has("win32")`, `vim.fn.has("mac")`, `vim.fn.has("linux")`
- Windows paths use `\\`, Unix uses `/`
- External commands branch by platform (e.g. `cmd /c type` vs `sh -c cat`)

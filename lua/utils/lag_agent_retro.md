# Lag Agent Retrospective

A Neovim AI chat plugin with lag mode (auto-fix on save), session management, and
multi-provider streaming. Built Feb–Mar 2026, then removed. This doc captures the
functional design, technical decisions, patterns, and lessons learned.

---

See [myFunction](./ai/init.lua#L3)

## What We Built

### Chat Panel

A right-side vertical split that renders user messages, assistant responses, tool use
indicators, and collapsible thinking/reasoning blocks. The chat panel was a read-only
buffer with extmark-based highlighting.

```lua
-- chat.lua — core state
local state = {
    buf_id = nil,
    win_id = nil,
    is_streaming = false,
    thinking_blocks = {},  -- tracks collapsed/expanded thinking regions
}
```

The panel opened with `winfixwidth` to prevent Neovim's `equalalways` from resizing it
when other splits changed. This was discovered after the chat panel kept collapsing when
lag mode opened quickfix lists.

### Lag Mode

Watched buffer saves globally. On each save it:

1. Diff the buffer against a baseline snapshot
2. Send the diff regions + full buffer to an LLM
3. Parse the LLM's JSON response into modifications
4. Apply modifications only within the diff regions (boundary enforcement)
5. Render inline indicators with extmarks

```lua
-- Diff computation using Neovim's built-in vim.diff
local function compute_diff_regions(old_lines, new_lines)
    local old_text = table.concat(old_lines, "\n") .. "\n"
    local new_text = table.concat(new_lines, "\n") .. "\n"
    local diff = vim.diff(old_text, new_text, { result_type = "indices" })
    local regions = {}
    for _, hunk in ipairs(diff) do
        local new_start = hunk[3]
        local new_count = hunk[4]
        if new_count > 0 then
            table.insert(regions, { new_start, new_start + new_count - 1 })
        end
    end
    return regions
end
```

The baseline was a snapshot of the buffer at last save. AI modifications updated the
baseline so they wouldn't show as diffs on the next save. User edits to AI-touched
lines pruned those modifications automatically.

Key concepts:
- **Baseline advancement**: After applying AI mods, baseline = current buffer state
- **Boundary enforcement**: Modifications outside diff regions were rejected
- **Queue system**: Rapid saves while LLM was processing were coalesced into one
- **Modification pruning**: Before each save, check if user edited AI lines → remove those mods

### Session Management

Each `activate()` created a new opencode server session. Sessions persisted on the
server and could be browsed via a Telescope picker (`<leader>fi`).

```lua
-- Telescope picker showing sessions sorted by most recent
-- <CR> to resume, <C-d> / d to delete
function M.pick(opts)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    -- ... fetches session list from opencode API
    -- previewer shows first user message text
end
```

Resume loaded the full conversation history from the server, stripped editor context
metadata from user messages, merged consecutive assistant messages (tool steps + text
response), and replayed everything into the chat panel.

### Provider Architecture

Two providers behind a common interface:

```lua
-- Provider contract
-- Every provider exposes: { name, stream(messages, config, callbacks) }
-- callbacks: { on_delta, on_done, on_error, on_thinking?, on_tool_use? }

-- Provider dispatch
function M.stream(messages, on_delta, on_done, on_error, opts)
    local provider = get_provider()  -- "opencode" or "anthropic"
    provider.stream(messages, provider_config, {
        on_delta = on_delta,
        on_done = on_done,
        on_error = on_error,
        on_thinking = opts.on_thinking,
        on_tool_use = opts.on_tool_use,
    })
end
```

**OpenCode provider**: HTTP + SSE. Started a local server (`opencode serve --port N`),
created sessions via REST, sent messages via `prompt_async`, and listened for responses
on the `/event` SSE stream. Session-scoped event filtering.

**Anthropic provider**: Direct API calls to `api.anthropic.com/v1/messages` with
streaming SSE responses. Required `ANTHROPIC_API_KEY` env var.

Provider selection: `AI_WORK` env var → anthropic, otherwise opencode.

---

## Key Technical Decisions

### Editor Context as Metadata Injection

Rather than trying to register custom tools with opencode (which doesn't support it),
we prepended a metadata block to every user message:

```
EDITOR CONTEXT:
Project: /home/user/myproject
Open buffers: src/main.lua, src/utils.lua
Visible windows: src/main.lua (cursor: 42:10)

<actual user message>
```

This was stripped when loading messages back from the server for display.

### SSE Event Routing

OpenCode streams events as Server-Sent Events. The critical routing logic for
thinking vs. text deltas:

```lua
-- Delta events have a `field` property ("reasoning" or "text")
-- Models may also embed <think> tags in text streams
local is_reasoning = in_think_tag
    or props.field == "reasoning"
    or (props.field ~= "text" and active_part_type == "reasoning")
```

Priority: `in_think_tag` (explicit `<think>` block) > `props.field` (SSE metadata) >
`active_part_type` (part.updated state). This was refined through three bug fixes where
post-tool reasoning leaked into the response area.

### `vim.fn.json_encode({})` Produces `[]`

Lua tables are ambiguous — `{}` could be an empty array or object. For JSON POST bodies
with no content, use `vim.fn.json_encode(vim.empty_dict())` to get `{}` instead of `[]`.

### `vim.system():wait()` Blocks in `-c` Context

Synchronous HTTP calls during startup (health checks) must use `vim.fn.system()`, not
`vim.system():wait()`. The latter blocks the Neovim event loop when called from `-c`
command context (e.g., test runners).

### `winfixwidth` for Chat Panel

Without `winfixwidth`, Neovim's `equalalways` redistributes window space every time a
new split opens. Setting `vim.wo[win].winfixwidth = true` on the chat panel window
prevents this.

### No Mocking Frameworks

Tests used manual stubs — replace the function on the module table, reset in
`before_each`. This kept tests readable and close to real behavior.

```lua
-- Stubbing pattern
local api = require("utils.ai.api")
local function stub_api()
    api.stream = function(messages, on_delta, on_done, on_error)
        stream_messages_spy = vim.deepcopy(messages)
        on_delta("test response")
        on_done()
        return function() end  -- cancel function
    end
end

before_each(function()
    ai.reset_all()
    stub_api()
end)
```

### Sending User Input Programmatically

Tests simulated real user interaction — open input popup, write to the buffer, press
Enter:

```lua
local function send_user_message(ai, message)
    local input_buf = ai.prompt()
    assert(input_buf ~= nil, "Input popup should have opened")
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { message })
    vim.cmd("stopinsert")
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false
    )
end
```

---

## Architecture

```
init.lua          require("utils.ai").setup()
                          |
                  lua/utils/ai/
                  ├── init.lua         Public API, keymaps, lifecycle
                  ├── api.lua          Config, provider dispatch, request building
                  ├── chat.lua         Buffer management, rendering, extmarks
                  ├── input.lua        Floating input popup
                  ├── lag.lua          Diff → LLM → apply cycle
                  ├── job.lua          curl wrappers, streaming job runner
                  ├── debug.lua        File logging, dump utilities
                  ├── spinner.lua      Inline spinner animation
                  ├── usage.lua        Token tracking, tabline formatting
                  ├── sessions.lua     Telescope session picker
                  └── providers/
                      ├── init.lua     Provider registry
                      ├── opencode.lua HTTP + SSE provider
                      └── anthropic.lua Direct API provider
```

### Data Flow (Chat)

```
User types message
  → input.lua captures text
  → init.lua prepends editor context metadata
  → api.lua dispatches to provider
  → provider streams SSE events
  → on_delta → chat.lua appends to buffer word-by-word
  → on_thinking → chat.lua appends to thinking region
  → on_tool_use → chat.lua renders tool indicator
  → on_done → init.lua stores in conversation, finishes chat message
```

### Data Flow (Lag)

```
User saves buffer (:w)
  → BufWritePost autocmd fires
  → lag.lua diffs buffer vs baseline
  → If diff exists, send to LLM with system prompt
  → LLM returns JSON array of modifications
  → Filter to diff regions only
  → Apply to buffer, render extmarks
  → Advance baseline
```

---

## Testing Patterns

### Unit Tests (plenary busted)

261 tests across 6 spec files. Tests were functional — simulating real user
interactions rather than testing internal functions.

**Test structure convention**: Every `it()` block had 2-3 sections separated by blank
lines. No section-labeling comments (`-- arrange`, `-- act`). Every `eq()` required a
3rd failure message. Every `assert()` required a 2nd failure message.

```lua
it("sending a message opens chat and shows response", function()
    send_user_message(ai, "hello")

    assert(chat.is_open(), "Chat panel should be open after sending")
    assert(chat_contains("hello"), "Chat should show the user message")
    assert(chat_contains("test response"), "Chat should show the response")
end)
```

**Global state isolation**: Tests cleaned up buffers, windows, keymaps, and module
state in `before_each`/`after_each`. Leaked state caused false passes in unrelated
tests.

**Snapshot mutable state**: When spying on tables that callbacks mutate, use
`vim.deepcopy()`:

```lua
api.stream = function(messages, ...)
    stream_messages_spy = vim.deepcopy(messages)  -- not just = messages
    ...
end
```

### E2E Tests (mock HTTP server)

4 e2e tests verified the full stack: real provider code → real HTTP → mock server →
real SSE parsing → real chat rendering.

**Mock server** (Python `ThreadingHTTPServer`): Replayed SSE events from fixture files.
Fixture key = sanitized slug of user message + 12-char SHA256 hash.

```python
def fixture_key(text):
    text = text.strip()
    slug = re.sub(r"[^a-zA-Z0-9 _-]", "_", text)
    slug = slug.replace(" ", "_")[:60].rstrip("_")
    h = hashlib.sha256(text.encode()).hexdigest()[:12]
    return f"{slug}_{h}"
```

**E2e script structure**: cleanup → setup → test → cleanup (trap EXIT).

```bash
# Start mock server
python3 "$E2E_DIR/mock_server.py" --port "$MOCK_PORT" &
MOCK_SERVER_PID=$!

# Wait for ready
for i in $(seq 1 20); do
    curl -s "http://127.0.0.1:$MOCK_PORT/global/health" && break
    sleep 0.25
done

# Symlink mock CLI onto PATH
MOCK_BIN_DIR=$(mktemp -d)
ln -s "$E2E_DIR/mock_opencode.sh" "$MOCK_BIN_DIR/opencode"
export PATH="$MOCK_BIN_DIR:$PATH"

# Run tests
nvim --headless -u ./e2e/specs/init.lua \
    -c "PlenaryBustedDirectory e2e/specs/ { ... }"
```

### Custom Test Linter

A Lua script (`scripts/lint_tests.lua`) enforced test conventions at lint time:

- Every `it()` must have 2-3 sections (separated by blank lines)
- No section-labeling comments (`-- arrange`, `-- act`, `-- assert`)
- Every `eq()` must have a 3rd failure message argument
- Every `assert()` must have a 2nd failure message argument

This prevented tests from becoming walls of code with no structure and ensured
meaningful failure messages.

---

## Bugs & Lessons

### SSE Routing Was the Hardest Problem

Three separate bugs in how SSE deltas were routed to thinking vs. response:

1. **`active_part_type` stale after tools**: After a tool use, `step-start` reset the
   part type, so subsequent reasoning deltas went to `on_delta`. Fix: use `props.field`
   as authoritative source.

2. **`props.field` overrode `in_think_tag`**: Models embedding `<think>` tags in text
   streams had `field="text"` on all deltas. The `in_think_tag` flag was ignored when
   `field="text"` was present. Fix: give `in_think_tag` highest priority.

3. **Thinking leaking past collapsed region**: Chat rendering didn't account for
   multi-line thinking content when calculating where to place the response text.

### `vim.ui.select` is Async

When using `vim.ui.select` inside a Telescope mapping, the picker's prompt buffer
context goes stale by the time the callback fires. Must capture the picker reference
before the async call. We later removed the confirmation dialog entirely — delete was
made immediate.

### Lag Baseline Must Advance After AI Writes

If the baseline isn't updated after applying AI modifications, those modifications show
as a diff on the next save, creating an infinite loop. The baseline must be set to
the buffer state *after* AI modifications are applied.

### Lag JSON Parsing: Brackets in Strings

The LLM sometimes returned JSON with brackets inside string values. Naive extraction
of the JSON array (finding `[` and `]`) broke on these. Fix: use the full response as
JSON, with markdown fence stripping as a fallback.

### OpenCode Permission System

OpenCode tools can be configured as `allow`, `deny`, or `ask`. When set to `ask`, the
server emits `permission.asked` SSE events and blocks until the client responds via
`POST /session/:id/permissions/:permissionID`. We never handled these, so write tools
would hang forever. The planned fix was to auto-deny write tools and restrict via
system prompt.

---

## What Was Left Unfinished

- **Permission handling**: Auto-deny write tools, restrict LLM to read-only tools
- **"Endeavor" concept**: Named persistent focus contexts with LLM-generated mental models
- **Session browsing e2e tests**: Mock server didn't have session list/delete/messages endpoints
- **Context window limit**: Tabline showed `?` for max context since no provider returned it
- **Cost display**: Cost was accumulated but never shown in the UI
- **Reasoning tokens**: `tokens.reasoning` from `step-finish` events was ignored

---

## Environment Variables

- `ANTHROPIC_API_KEY` — API key for direct Anthropic calls
- `AI_WORK` — When set, used anthropic provider instead of opencode
- `OPENCODE_E2E_PORT` — Port override for e2e test mock server (default 42070)

## File Inventory (at time of removal)

```
lua/utils/ai/
  init.lua           (741 lines)  Public API, lifecycle, keymaps
  api.lua            (187 lines)  Config, provider dispatch
  chat.lua           (902 lines)  Buffer rendering, extmarks, thinking
  input.lua          (~80 lines)  Floating input popup
  lag.lua            (1225 lines) Diff → LLM → apply cycle
  job.lua            (170 lines)  curl/job wrappers
  debug.lua          (~120 lines) File logging, dump
  spinner.lua        (~60 lines)  Inline animation
  usage.lua          (~200 lines) Token tracking, tabline
  sessions.lua       (~250 lines) Telescope session picker
  providers/
    init.lua         (~50 lines)  Provider registry
    opencode.lua     (570 lines)  HTTP + SSE provider
    anthropic.lua    (~200 lines) Direct API provider

specs/ai/
  ai_chat_spec.lua      (1277 lines, 76 tests)
  ai_lag_spec.lua       (~900 lines, 67 tests)
  ai_providers_spec.lua (~665 lines, 28 tests)
  ai_sessions_spec.lua  (~600 lines, 36 tests)
  ai_usage_spec.lua     (~400 lines, 34 tests)

e2e/
  run.sh                E2e orchestrator
  mock_server.py        Python mock HTTP server
  mock_opencode.sh      Mock CLI wrapper
  fixtures/opencode/    SSE fixture files
  specs/
    init.lua            E2e test bootstrap
    chat_e2e_spec.lua   (4 tests)

Total: 261 unit tests, 4 e2e tests, ~6000 lines of plugin code, ~4000 lines of tests
```



# MY AI Manifesto:
 AI output should not be the output of the the system
 User input should not be the input into the AI

Rule - Reasoning
AI is great at searching a lot of code THIS IS ITS STRENGTH - its amazing at crunching large sets of tokens
Suspicious of generative AI, dont generate code - generated code doesnt just risk hdiden bugs or bad design decisions it limits the engineers ability to internalize the system
AI should make the user faster and better at their task AND at their craft - ai doing the work for the eng will atrophy their skills

---

## Feature Ideas

Every feature below uses AI for **reasoning/search over tokens**. None produce code as
output. The engineer stays in the driver's seat.

| # | Feature                  | AI Role                           | Output Mechanism                  |
|---|--------------------------|-----------------------------------|-----------------------------------|
| 1 | Diff Completer           | Pattern recognition + application | TBD (completion/virtual text)     |
| 2 | Passive Observer         | Code analysis + annotation        | Virtual text + quickfix list      |
| 3 | Codebase Cartographer    | Structural analysis               | Scratch buffer / float            |
| 4 | Reviewer / Interrogator  | Critical analysis                 | Questions in chat/float           |
| 5 | Symbol Tracer            | Data flow analysis                | Structured summary buffer         |
| 6 | Commit Narrator          | Diff analysis                     | Scratch buffer                    |
| 7 | Semantic Searcher        | Semantic matching                 | Telescope picker                  |

### 1. Diff Completer

Read the git diff (current file or whole repo), recognize the *pattern* of what the user
is doing, and complete the remaining mechanical instances of that pattern.

**Why it fits**: The user is the author — they wrote the first instances, establishing the
pattern and design decisions. AI completes *their* pattern, not its own design. It's
"intelligent find-and-apply-my-pattern" rather than "write code for me."

**Design questions**:
- Output: vim completion menu, inline virtual text to accept/reject, or direct apply?
- Scope toggle: current file diff vs. whole repo diff
- Should it show *where* it wants to apply changes before doing so?

### 2. Passive Observer / Annotator

Watch the repo and user editing activity. Read code, form observations, and leave notes
as virtual text annotations throughout the codebase. These also populate a quickfix list
for navigation.

**Why it fits**: Annotations are *commentary*, not artifacts. It points things out the
engineer might miss, teaches them about their own codebase. AI reads far more code than
you can hold in your head and surfaces insights.

**Possible note types**: inconsistencies, potential bugs, "this function is similar to X",
dead code, missing error handling, style drift from the rest of the codebase.

**Design questions**:
- What triggers observation? File save? Periodic? On buffer enter?
- Persistence — do notes survive sessions or are they ephemeral?
- Staleness — how do notes get cleaned up when code changes?

### 3. Codebase Cartographer

On demand, read a module/directory/subsystem and produce a mental model summary: data
flow, key abstractions, invariants, where state lives. Not code — a *map*. Displayed in a
scratch buffer or floating window.

**Why it fits**: Instead of the AI maintaining a persistent mental model for itself, it
builds one *for the engineer*. Pure structural reasoning, no generation.

**Design questions**:
- Scope: single file, directory, or user-selected set of files?
- Format: prose summary, ASCII diagram, structured outline?
- Can it diff two maps to show how a subsystem changed over time?

### 4. Reviewer / Interrogator

You write code. You hit a keymap. The agent reads what you wrote and *asks you questions*
about it. "What happens if this returns nil?" "Is this lock held across the await?" "This
looks similar to the pattern in `utils/cache.lua:45` — intentional divergence?"

**Why it fits**: It doesn't tell you what's wrong — it makes you *think* about whether
something could be wrong. Socratic method. Sharpens the engineer's critical thinking
instead of replacing it.

**Design questions**:
- Scope: visual selection, current function, whole buffer, staged diff?
- Interaction: one-shot list of questions, or conversational back-and-forth?
- Should it track which questions you've "resolved" vs. ignored?

### 5. Symbol Tracer

Cursor on a function/variable. Keymap. The agent traces all usages, call chains, data
flow paths, and presents a structured summary. "This value originates at X, flows through
Y and Z, is consumed at W. It can be nil if path P is taken."

**Why it fits**: Pure analysis, no generation. Gives the engineer a view of the system
they couldn't easily build manually without reading dozens of files.

**Design questions**:
- Depth: direct callers only, or full transitive trace?
- Output: structured buffer, quickfix list of call sites, or both?
- Should it integrate with LSP references as a starting point?

### 6. Commit Narrator

Before you commit, read your staged diff and describe what the changes do and why they
might matter. Not a commit message — context that helps you write a better one. Also
flags: "you changed X but didn't update the related Y."

**Why it fits**: The engineer writes the commit message. The AI provides analysis of what
changed to inform that message. AI reasons about the diff; engineer decides the narrative.

**Design questions**:
- Trigger: keymap, pre-commit hook, or automatic on `git add`?
- Output: floating window, scratch buffer, or echo area?
- Should it warn about suspicious omissions (changed a function but not its tests)?

### 7. Semantic Searcher

A Telescope-style picker where instead of grep (literal match) or filename fuzzy find,
you type a *description of what you're looking for* in natural language and the AI finds
files/symbols/code regions that match the *meaning*.

Examples:
- "where do we handle auth token refresh" → finds token refresh logic even if it's called
  `renewCredentials` in `session_manager.lua`
- "error recovery after network failure" → finds retry logic, reconnect handlers
- "anything that mutates global state" → finds side-effectful functions

**Why it fits**: AI's core strength — crunching large sets of tokens to find semantic
matches. Output is a list of locations, not code. Surfaces code the engineer didn't know
existed, expanding their mental model.

**Implementation approaches**:
- **Embedding-based**: Pre-compute vector embeddings, similarity search at query time.
  Fast but requires indexing step + local vector store.
- **LLM-as-judge**: Send query + batches of files to LLM, ask "which match?" Simpler,
  no indexing, but slower and costs tokens per search.
- **Hybrid**: Cheap heuristics (filenames, symbols, comments) narrow candidates, then
  LLM-as-judge on the shortlist.

**Design questions**:
- Latency tolerance: 2-5 seconds? 10? Async results that populate as they come in?
- Scope: whole repo, current directory subtree, configurable?
- Output: Telescope picker with file paths + line ranges + match explanation?

### 8. Smart Marks

Neovim has marks (`ma`, `'a`) but they're manual and positional. The AI watches editing
patterns and automatically places marks at **semantically significant locations** — the
function you keep jumping back to, the config block you've edited 5 times this session,
the boundary between "done" and "in progress" in a refactor.

**Why it fits**: No generation. It observes behavior and makes navigation faster. The
engineer is still doing all the work — the AI just noticed where attention keeps going.

**Output**: Neovim marks (uppercase for cross-file, lowercase for in-buffer) + a quickfix
list of "your hot spots."

**Neovim integration**: `m` + uppercase letters for global marks, `getmarklist()` for
introspection, sign column indicators for visibility.

**Design questions**:
- How many marks before it becomes noise? Cap at N most significant?
- Should it explain *why* a location was marked? ("you've visited this 7 times")
- Decay — do marks lose significance if you stop visiting them?

### 9. LSP-Augmented Diagnostics Explainer

LSP diagnostics are often terse and cryptic (`E0308: mismatched types`). The AI reads the
diagnostic, the surrounding code, the type definitions, and the recent diff, then provides
a **contextual explanation** as virtual text or a float.

Not "here's the fix" — instead: "This expects `Option<String>` but you're passing
`String` because `get_name()` on line 42 was changed from returning `String` to
`Option<String>` in your current diff."

**Why it fits**: Makes the engineer better at understanding type systems and error
messages. Connects the diagnostic to *their recent changes* so they understand causality,
not just symptoms.

**Output**: Extended virtual text below the diagnostic line, or a float on keymap.

**Neovim integration**: `vim.diagnostic.get()`, `vim.lsp.buf.hover()`, diagnostic
handlers.

**Design questions**:
- Trigger: automatic on new diagnostics, or keymap on cursor over a diagnostic?
- Should it cross-reference the git diff to explain *why* the error appeared?
- Scope: single diagnostic under cursor, or batch-explain all diagnostics in buffer?


### dump:
- ai powered snippets (eg vim.system({ 'curl', '-X', 'POST'....  can be created using a ai snippet vimssystem('curl -X POST') 

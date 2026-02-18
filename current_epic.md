# Epic

A custom AI chat plugin built into the Neovim config that lets the user interact
with LLMs directly from the editor. The plugin supports dual providers (opencode CLI
for personal use, Anthropic API for work), streams responses into a chat split buffer,
handles multi-step tool use, and includes a floating input popup for composing messages.

# Story Log

## User Story 1: Initial AI chat plugin

As a user, I want to open a chat panel in Neovim, type a message in a popup, and
receive a streamed AI response in a side split, so that I can interact with an LLM
without leaving my editor.

Created the full plugin skeleton: API module with dual provider support (opencode CLI
and Anthropic curl streaming), chat buffer as a read-only markdown split on the right,
floating input popup with Enter to submit and Esc/q to cancel, debug toggle, and
conversation orchestration with file context injection on the first message. Wired
into the config entry point with `require("utils.ai").setup()`.

Files: `init.lua`, `lua/utils/ai/api.lua`, `lua/utils/ai/chat.lua`,
`lua/utils/ai/init.lua`, `lua/utils/ai/input.lua`, `lua/utils/ai/debug.lua`

## User Story 2: Tool-use spinner and session tagging

As a user, I want to see a visual spinner when the AI is using tools like web search,
and I want my plugin's opencode sessions tagged as "nvim-ai", so that I have feedback
during delays and my opencode session list stays uncluttered.

Fixed multi-step handling so the plugin no longer cuts off responses after the first
tool call. Added `show_spinner`/`hide_spinner` to the chat module so the spinner
restarts during tool-use gaps. Added `--title nvim-ai` to the opencode CLI command.
Added `tool_use` event rendering in the chat buffer.

Files: `lua/utils/ai/api.lua`, `lua/utils/ai/chat.lua`

## User Story 3: Functional test coverage

As a user, I want functional tests that verify the full chat flow from the user's
perspective (open input, type, submit, see response), so that I can refactor the
plugin with confidence that real user workflows still work.

Added 18 tests covering toggle, input popup, full send flow, multi-turn conversation
history, error handling, clear/reset, and debug toggle. Tests stub `api.stream`
directly on the module table with a synchronous canned response. All tests simulate
real user actions (open popup, set buffer text, press Enter).

Files: `specs/ai_chat_spec.lua`

## User Story 4: Input popup cleanup

As a user, I want the input popup to return its buffer ID directly and for tests to
not depend on scanning all windows for floats, so that the code is simpler and tests
are less brittle.

Changed `input.open()` to return the popup buffer ID and `ai.prompt()` to return it
from `input.open`. Removed the `find_float` helper from tests in favor of using the
returned buffer ID directly. Simplified test helpers.

Files: `lua/utils/ai/init.lua`, `lua/utils/ai/input.lua`, `specs/ai_chat_spec.lua`

## User Story 5: Multi-buffer context tracking

As a user, I want the AI chat to automatically track all buffers I visit during a
session and include their latest content as context, so that the LLM stays aware of
the files I'm working with without me having to manually re-share them.

Replaced the single-buffer first-message-only context injection with a session-wide
buffer tracking system. A `BufEnter` autocmd records every real file buffer visited
during the chat session. On each message send, the live content of all tracked buffers
is read and injected into the first user message of the API payload — conversation
history stores raw text so context is never stale or duplicated. Added `tracked_bufs`
set, `is_trackable`/`track_buf`/`start_tracking`/`stop_tracking` helpers,
`build_context_block` and `build_api_messages` to separate context from storage.
`clear()` resets tracked buffers and tears down the autocmd. Added `:AIFiles` command
for debugging. Changed send keymap from `<leader>is` to `<leader>ia`. Added 7 tests
covering buffer tracking, live content updates, deduplication, and session reset.

Files: `lua/utils/ai/init.lua`, `specs/ai_chat_spec.lua`, `current_epic.md`

## User Story 6: Web search support for Anthropic provider

As a user, I want the AI chat to be able to search the web when using the Anthropic
API, with a spinner indicating when a search is in progress, so that I can get
up-to-date answers without leaving the editor.

Added the `web_search_20250305` server tool to the Anthropic request body (max 5
searches per request). Added `content_block_start` event handling in the SSE parser:
`server_tool_use` blocks show a "Searching the web..." message and start the spinner,
`web_search_tool_result` blocks hide the spinner when results arrive. Tightened the
`content_block_delta` handler to only process `text_delta` types so tool-use JSON
input deltas are not leaked into the chat buffer.

Files: `lua/utils/ai/api.lua`, `current_epic.md`

## User Story 7: Exclusion patterns for buffer tracking

As a user, I want sensitive files like `.env` and `appsettings.json` to be
automatically excluded from buffer tracking, so that secrets and credentials
are never sent to the LLM.

Added a case-insensitive exclusion list (`exclude_patterns`) to the buffer
tracking logic. Filenames containing "appsettings" or "env" are now rejected
by `is_trackable()`. Added a test that verifies excluded buffers are not
included in the context while normal files still are.

Files: `lua/utils/ai/init.lua`, `specs/ai_chat_spec.lua`

## User Story 8: Inline agentic coding

As a user, I want to highlight a section of code in visual mode, press `<leader>ia`,
type an instruction, and have the AI stream replacement code directly into my buffer,
so that I can make targeted edits without leaving my editor or using the chat panel.

Added inline agentic coding mode that activates when `<leader>ia` is pressed in visual
mode. The highlighted region becomes a constrained "sandbox" — the AI can only replace
that exact selection. The flow: detect visual mode in `prompt()`, capture selection
range/text via `get_visual_selection()`, open input popup with "Inline Edit" title,
send to new `api.inline_stream()` with specialized system prompt that outputs raw code
only (no markdown fences). The `inline.lua` module streams the response directly into
the buffer, replacing the selection character-by-character. A spinner with virtual
lines above and below the selection shows "thinking..." during the request. If the AI
determines the instruction isn't asking for code, it returns a sentinel
(`__NO_INLINE_CODE_PROMPT__`) which triggers a `vim.notify` warning instead of buffer
modification. Inline edits read the full chat context (conversation history + tracked
buffers) but don't write to it — the inline request and response are not recorded in
history, so they won't appear in future chat messages. Added 10 tests covering
replacement, context passing, history passing, sentinel handling, multiline/partial-line
edits, error handling, and spinner cleanup.

Files: `lua/utils/ai/init.lua`, `lua/utils/ai/api.lua`, `lua/utils/ai/input.lua`,
`lua/utils/ai/inline.lua`, `specs/ai_chat_spec.lua`

## User Story 9: Keep spinner visible during inline streaming

As a user, I want the "thinking..." spinner and virtual lines to remain visible
while the AI streams replacement code into my buffer, so that I have continuous
feedback that the operation is still in progress.

Removed the early `stop_spinner()` call from `prepare_buffer()`. The spinner now
stays visible and animates throughout the entire streaming process, only clearing
when the stream completes (`on_done`) or errors (`on_error`).

Files: `lua/utils/ai/inline.lua`

## User Story 10: Automatic file logging

As a user, I want the AI plugin to automatically log all activity to daily log
files without needing to toggle debug mode, so that I can review AI responses
and troubleshoot issues after the fact.

Replaced the toggle-based debug module with automatic file logging. Logs are
written to `vim.fn.stdpath("log")/ai/YYYY-MM-DD.log` with timestamps. Removed
the debug keymap (`<leader>id`). Added `:AIDebugPath` command to show the log
directory. Added `set_log_dir()` for test isolation. AI responses (both chat
and inline) are now logged with full content. Fixed duplicate `on_done()` call
in `stream_inline_opencode` that was causing inline responses to log twice.

Files: `lua/utils/ai/debug.lua`, `lua/utils/ai/init.lua`, `lua/utils/ai/inline.lua`,
`lua/utils/ai/api.lua`, `specs/ai_chat_spec.lua`

## User Story 11: Project-scoped sessions

As a user, I want my AI chat conversations and tracked buffers to be scoped to
the current working directory, so that switching between projects gives me
separate chat histories.

Added a `sessions` table keyed by `vim.fn.getcwd()`. Each session stores its own
`conversation`, `tracked_bufs`, and `tracking_augroup`. The `get_session()` helper
lazily creates sessions on demand. When toggling or sending messages, `sync_project()`
detects cwd changes and re-renders the chat buffer with the new project's conversation.
The chat buffer is shared across projects — content swaps when switching. `clear()`
only affects the current project's session. Added `:AIProject` command to show the
current project path. Added `reset_all()` for test isolation. Added
`append_assistant_content()` to chat module for re-rendering saved conversations.
Added 6 tests covering project switching, conversation isolation, buffer tracking
scope, and clear behavior.

Files: `lua/utils/ai/init.lua`, `lua/utils/ai/chat.lua`, `specs/ai_chat_spec.lua`

## User Story 12: Codebase cleanup and deduplication

As a developer, I want the AI plugin codebase to have clean patterns with no
duplicate logic, so that it's easier to read, extend, and maintain.

Extracted shared modules to eliminate duplication:

- **`spinner.lua`**: Shared spinner animation with `create(opts)` returning
  `{start, stop, is_running}`. Both `chat.lua` and `inline.lua` now use this
  instead of duplicating timer/frame cycling logic (~50 lines each).

- **`job.lua`**: Shared job execution utilities with `write_temp()`, `run()`,
  `pipe_cmd()`, and `curl_cmd()`. All 4 streaming functions in `api.lua` now
  use this instead of duplicating temp file handling, stderr collection, and
  cleanup patterns (~60 lines each).

Refactored existing modules:

- **`chat.lua`**: Added `with_modifiable(fn)` helper to wrap buffer modifications,
  reducing 7 repetitive `modifiable = true/false` blocks to single-line calls.

- **`api.lua`**: Extracted `parse_sse(line)` helper for SSE JSON parsing, used
  by both Anthropic streaming functions.

Fixed test structure per AGENTS.md conventions:

- All tests now have exactly 3 sections (arrange/act/assert) separated by single
  blank lines
- Moved inline test buffer cleanup from end-of-test to `before_each` via shared
  `test_bufs` array
- Consolidated verbose multi-line selection objects to single lines where sensible

Net reduction of ~150-200 lines through deduplication.

Files: `lua/utils/ai/spinner.lua`, `lua/utils/ai/job.lua`, `lua/utils/ai/chat.lua`,
`lua/utils/ai/api.lua`, `lua/utils/ai/inline.lua`, `specs/ai_chat_spec.lua`

## User Story 13: Improved error handling and notifications

As a user, I want to see clear error notifications when LLM API calls fail (e.g.,
low balance, invalid API key, rate limits), so that I understand why my request
didn't work and can take action.

Added comprehensive error handling across both providers. For Anthropic, added
`parse_json_error()` to detect plain JSON error responses returned on HTTP-level
errors (4xx/5xx) — these aren't SSE-formatted so weren't being caught before.
For opencode, added handling for `event.type == "error"` events. Both chat and
inline flows now call `vim.notify` with the error message in addition to stopping
spinners and cleaning up state. The chat flow also displays errors in the buffer
and removes the failed message from conversation history.

Files: `lua/utils/ai/api.lua`, `lua/utils/ai/init.lua`

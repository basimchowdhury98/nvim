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

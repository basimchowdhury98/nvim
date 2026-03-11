-- sessions.lua
-- Telescope-based session picker for browsing, resuming, and deleting opencode sessions

local debug = require("utils.ai.debug")

local M = {}

--- Extract the first user message text from an opencode messages array.
--- Messages come from GET /session/:id/message as {info, parts}[] entries.
--- @param messages table[] array of {info = Message, parts = Part[]}
--- @return string|nil
local function first_user_text(messages)
    for _, msg in ipairs(messages) do
        if msg.info and msg.info.role == "user" then
            for _, part in ipairs(msg.parts or {}) do
                if part.type == "text" and part.text and part.text ~= "" then
                    return part.text
                end
            end
        end
    end
    return nil
end

--- Strip the EDITOR CONTEXT metadata block from a user message.
--- The block starts with "EDITOR CONTEXT:" and ends at a double newline.
--- @param text string
--- @return string
local function strip_editor_context(text)
    if text:sub(1, 15) == "EDITOR CONTEXT:" then
        local after = text:find("\n\n", 1, true)
        if after then
            return text:sub(after + 2)
        end
    end
    return text
end

--- Convert opencode messages to the plugin's conversation format.
--- Returns a flat array of {role, content, thinking, tool_uses} suitable
--- for session.conversation.
--- Strips editor context metadata from user messages so only the actual
--- user text is stored (context gets re-injected by build_api_messages).
--- Consecutive assistant messages (from multi-step responses) are merged
--- into a single entry so the chat panel shows one assistant block.
--- Tool uses and reasoning parts are extracted and stored alongside text.
--- @param messages table[] array of {info = Message, parts = Part[]}
--- @return table[] conversation
local function messages_to_conversation(messages)
    local conversation = {}
    for _, msg in ipairs(messages) do
        local role = msg.info and msg.info.role
        if role == "user" or role == "assistant" then
            local text_parts = {}
            local thinking_parts = {}
            local msg_tool_uses = {}
            for _, part in ipairs(msg.parts or {}) do
                if part.type == "text" and part.text then
                    table.insert(text_parts, part.text)
                elseif part.type == "reasoning" and part.text then
                    table.insert(thinking_parts, part.text)
                elseif part.type == "tool" and part.tool then
                    local input = {}
                    local title = nil
                    if part.state then
                        input = part.state.input or {}
                        title = part.state.title
                    end
                    table.insert(msg_tool_uses, {
                        tool = part.tool,
                        input = input,
                        title = title,
                    })
                end
            end
            local content = table.concat(text_parts, "\n")
            local thinking = table.concat(thinking_parts, "\n")
            if role == "user" then
                content = strip_editor_context(content)
            end
            -- Merge consecutive assistant messages
            local prev = conversation[#conversation]
            if prev and prev.role == role and role == "assistant" then
                if content ~= "" then
                    prev.content = prev.content ~= "" and (prev.content .. "\n\n" .. content) or content
                end
                if thinking ~= "" then
                    prev.thinking = prev.thinking and (prev.thinking .. "\n" .. thinking) or thinking
                end
                for _, tu in ipairs(msg_tool_uses) do
                    prev.tool_uses = prev.tool_uses or {}
                    table.insert(prev.tool_uses, tu)
                end
            else
                if content ~= "" or #msg_tool_uses > 0 then
                    local entry = { role = role, content = content }
                    if thinking ~= "" then
                        entry.thinking = thinking
                    end
                    if #msg_tool_uses > 0 then
                        entry.tool_uses = msg_tool_uses
                    end
                    table.insert(conversation, entry)
                end
            end
        end
    end
    return conversation
end

--- Format a unix timestamp (seconds) as a relative time string.
--- @param ts number unix timestamp in seconds
--- @return string
local function relative_time(ts)
    local diff = os.time() - ts
    if diff < 60 then return "just now" end
    if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    if diff < 604800 then return math.floor(diff / 86400) .. "d ago" end
    return os.date("%Y-%m-%d", ts)
end

--- Open the Telescope session picker.
--- @param opts table {port: number, on_select: fun(session_id: string, conversation: table[]), on_delete: fun(session_id: string)|nil}
function M.pick(opts)
    local ok_telescope, _ = pcall(require, "telescope")
    if not ok_telescope then
        vim.notify("AI: Telescope is required for session picker", vim.log.levels.ERROR)
        return
    end

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")
    local entry_display = require("telescope.pickers.entry_display")

    local opencode = require("utils.ai.providers.opencode")
    local port = opts.port
    local on_select = opts.on_select
    local on_delete = opts.on_delete

    -- Fetch sessions
    local sessions_list, err = opencode.list_sessions(port)
    if not sessions_list then
        vim.notify("AI: " .. (err or "Failed to list sessions"), vim.log.levels.ERROR)
        return
    end

    if #sessions_list == 0 then
        vim.notify("AI: No sessions found", vim.log.levels.INFO)
        return
    end

    -- Sort by updated time descending (most recent first)
    table.sort(sessions_list, function(a, b)
        local a_time = a.time and a.time.updated or 0
        local b_time = b.time and b.time.updated or 0
        return a_time > b_time
    end)

    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 12 },
            { remaining = true },
        },
    })

    local function make_display(entry)
        return displayer({
            { entry.time_str, "Comment" },
            entry.title,
        })
    end

    local finder = finders.new_table({
        results = sessions_list,
        entry_maker = function(session)
            local title = session.title or "(untitled)"
            local updated = session.time and session.time.updated or 0
            local time_str = relative_time(updated)
            return {
                value = session,
                display = make_display,
                ordinal = title,
                title = title,
                time_str = time_str,
                session_id = session.id,
            }
        end,
    })

    -- Message preview: fetch and display conversation for the selected session
    local previewer = previewers.new_buffer_previewer({
        title = "Session Messages",
        define_preview = function(self, entry)
            local sid = entry.session_id
            local messages, msg_err = opencode.get_messages(port, sid)
            if not messages then
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false,
                    { "Failed to load messages: " .. (msg_err or "unknown error") })
                return
            end

            local lines = {}
            local conversation = messages_to_conversation(messages)
            for _, msg in ipairs(conversation) do
                local header = msg.role == "user" and "You:" or "Assistant:"
                table.insert(lines, header)
                for line in msg.content:gmatch("([^\n]*)\n?") do
                    table.insert(lines, "  " .. line)
                end
                table.insert(lines, "")
            end

            if #lines == 0 then
                table.insert(lines, "(no messages)")
            end

            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            vim.bo[self.state.bufnr].filetype = "markdown"
        end,
    })

    local function make_entry_maker(session)
        local s_title = session.title or "(untitled)"
        local updated = session.time and session.time.updated or 0
        local time_str = relative_time(updated)
        return {
            value = session,
            display = make_display,
            ordinal = s_title,
            title = s_title,
            time_str = time_str,
            session_id = session.id,
        }
    end

    pickers.new({}, {
        prompt_title = "AI Sessions",
        finder = finder,
        sorter = conf.generic_sorter({}),
        previewer = previewer,
        attach_mappings = function(prompt_bufnr, map)
            -- Enter: resume selected session
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                if not entry then return end

                actions.close(prompt_bufnr)

                local sid = entry.session_id
                debug.log("Resuming session: " .. sid)

                -- Fetch messages for this session
                local messages, msg_err = opencode.get_messages(port, sid)
                if not messages then
                    vim.notify("AI: Failed to load session messages: " .. (msg_err or "unknown"),
                        vim.log.levels.ERROR)
                    return
                end

                local conversation = messages_to_conversation(messages)
                if on_select then
                    on_select(sid, conversation)
                end
            end)

            local function delete_selected()
                local entry = action_state.get_selected_entry()
                if not entry then return end

                local sid = entry.session_id
                local current_picker = action_state.get_current_picker(prompt_bufnr)

                if on_delete then
                    on_delete(sid)
                end

                local del_ok, del_err = opencode.delete_session(port, sid)
                if not del_ok then
                    vim.notify("AI: Failed to delete session: " .. (del_err or "unknown"),
                        vim.log.levels.ERROR)
                    return
                end

                vim.notify("AI: Session deleted", vim.log.levels.INFO)

                if not current_picker then return end
                local new_sessions, _ = opencode.list_sessions(port)
                if new_sessions then
                    table.sort(new_sessions, function(a, b)
                        local a_time = a.time and a.time.updated or 0
                        local b_time = b.time and b.time.updated or 0
                        return a_time > b_time
                    end)
                    current_picker:refresh(finders.new_table({
                        results = new_sessions,
                        entry_maker = make_entry_maker,
                    }), { reset_prompt = false })
                end
            end

            map("i", "<C-d>", delete_selected)
            map("n", "d", delete_selected)

            return true
        end,
    }):find()
end

-- Expose helpers for testing
M._first_user_text = first_user_text
M._messages_to_conversation = messages_to_conversation
M._relative_time = relative_time
M._strip_editor_context = strip_editor_context

return M

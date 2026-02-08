-- utils/ai/init.lua
-- AI chat plugin - public API, setup, keymaps

local api = require("utils.ai.api")
local chat = require("utils.ai.chat")
local input = require("utils.ai.input")
local debug = require("utils.ai.debug")

local M = {}

local default_config = {
    api = {},
    chat = {},
    input = {},
    keymaps = {
        toggle = "<leader>ii",
        send = "<leader>is",
        clear = "<leader>iq",
        debug = "<leader>id",
    },
}

local config = vim.deepcopy(default_config)

-- Conversation history for the current session
local conversation = {}

-- Handle to cancel in-flight requests
local cancel_request = nil

--- Build context about the current file to include in the system prompt
local function get_file_context()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    local ft = vim.bo[buf].filetype

    if name == "" or ft == "" then
        return nil
    end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local content = table.concat(lines, "\n")

    -- Don't include massive files
    if #content > 50000 then
        content = content:sub(1, 50000) .. "\n... (truncated)"
    end

    return string.format(
        "The user is currently editing this file:\nFilename: %s\nLanguage: %s\n\n```%s\n%s\n```",
        name, ft, ft, content
    )
end

--- Send a user message and stream the AI response
--- @param text string The user's message
local function send_message(text)
    debug.log("send_message called with: " .. text:sub(1, 100))

    if chat.is_streaming() then
        vim.notify("AI: Already streaming a response, please wait", vim.log.levels.WARN)
        return
    end

    -- Make sure chat panel is open
    if not chat.is_open() then
        chat.open()
    end

    -- Add file context to the first message if available
    local user_content = text
    if #conversation == 0 then
        local ctx = get_file_context()
        if ctx then
            user_content = ctx .. "\n\n" .. text
        end
    end

    -- Add to conversation history
    table.insert(conversation, { role = "user", content = user_content })

    -- Show user message in chat (display the raw text, not the context-augmented version)
    chat.append_user_message(text)

    -- Start assistant block
    chat.start_assistant_message()

    -- Track assistant response for conversation history
    local response_chunks = {}

    cancel_request = api.stream(
        conversation,
        -- on_delta
        function(delta)
            table.insert(response_chunks, delta)
            chat.append_delta(delta)
        end,
        -- on_done
        function()
            local full_response = table.concat(response_chunks, "")
            table.insert(conversation, { role = "assistant", content = full_response })
            chat.finish_assistant_message()
            cancel_request = nil
        end,
        -- on_error
        function(err)
            chat.append_error(err)
            -- Remove the failed user message from history
            table.remove(conversation)
            cancel_request = nil
        end
    )
end

--- Open the input popup and send the message on submit
--- @return number buf_id The buffer id of the input popup
function M.prompt()
    return input.open(function(text)
        send_message(text)
    end)
end

--- Toggle the chat panel
function M.toggle()
    chat.toggle()
end

--- Close the chat and clear conversation
function M.clear()
    if cancel_request then
        cancel_request()
        cancel_request = nil
    end
    chat.clear()
    conversation = {}
    chat.close()
    vim.notify("AI: Conversation cleared")
end

--- Cancel the current in-flight request
function M.cancel()
    if cancel_request then
        cancel_request()
        cancel_request = nil
        chat.append_error("Request cancelled")
        vim.notify("AI: Request cancelled")
    end
end

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})

    api.setup(config.api)
    chat.setup(config.chat)
    input.setup(config.input)

    local map = vim.keymap.set

    map("n", config.keymaps.toggle, M.toggle, { desc = "AI: Toggle chat panel" })
    map("n", config.keymaps.send, M.prompt, { desc = "AI: Send message" })
    map("n", config.keymaps.clear, M.clear, { desc = "AI: Clear conversation" })
    map("n", config.keymaps.debug, debug.toggle, { desc = "AI: Toggle debug mode" })
end

return M

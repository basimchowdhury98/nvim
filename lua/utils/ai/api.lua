-- api.lua
-- AI provider dispatcher: resolves the active provider and delegates streaming

local M = {}
local debug = require("utils.ai.debug")
local providers = require("utils.ai.providers")

local default_config = {
    -- Anthropic direct API settings (used when AI_WORK is set)
    api_key_env = "ANTHROPIC_API_KEY",
    model = "claude-opus-4-20250514",
    max_tokens = 4096,
    endpoint = "https://api.anthropic.com/v1/messages",
    api_version = "2023-06-01",
    system_prompt = "You are a helpful coding assistant embedded in a Neovim editor.\n\nRESPONSE LENGTH — THIS IS CRITICAL:\nKeep every response brief and focused. Short answers are always preferred.\nWhen a complete answer genuinely requires more detail, provide ONLY the first part and end with a short note like \"there's more — ask me to continue\". Then STOP. Do NOT continue until the user asks.\nThis is the most important rule. The user stays in their code editor and cannot comfortably read long responses. Violating this rule makes the tool unusable.",
    -- Alt provider env var names (OpenAI-compatible, used when alt mode is toggled)
    alt_url_env = "AI_ALT_URL",
    alt_key_env = "AI_ALT_API_KEY",
    alt_model_env = "AI_ALT_MODEL",
}

local config = vim.deepcopy(default_config)

-- Whether the alt provider is active (only meaningful in work mode)
local alt_mode = false

-- Last request payloads for debugging dumps
local last_chat_request = nil
local last_lag_request = nil

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

--- Check if we should use the Anthropic API directly (work mode)
local function is_work_mode()
    local val = os.getenv("AI_WORK")
    return val and val ~= "" and val ~= "false" and val ~= "0"
end

--- Check if the alt OpenAI-compatible provider is active
local function is_alt_mode()
    return is_work_mode() and alt_mode
end

--- Resolve the current provider name
--- @return string
function M.get_provider()
    if is_alt_mode() then
        return "alt"
    end
    return is_work_mode() and "anthropic" or "opencode"
end

--- Build provider-specific config from the global config
--- @param provider_name string
--- @return table
local function build_provider_config(provider_name)
    local base = {
        system_prompt = config.system_prompt,
        max_tokens = config.max_tokens,
    }

    if provider_name == "anthropic" then
        local key = os.getenv(config.api_key_env)
        if not key or key == "" then
            vim.notify("AI: " .. config.api_key_env .. " env var not set", vim.log.levels.ERROR)
        end
        base.api_key = key
        base.model = config.model
        base.endpoint = config.endpoint
        base.api_version = config.api_version
    elseif provider_name == "alt" then
        local url = os.getenv(config.alt_url_env)
        local key = os.getenv(config.alt_key_env)
        local model = os.getenv(config.alt_model_env)
        if not url or url == "" then
            vim.notify("AI: " .. config.alt_url_env .. " env var not set", vim.log.levels.ERROR)
        end
        if not key or key == "" then
            vim.notify("AI: " .. config.alt_key_env .. " env var not set", vim.log.levels.ERROR)
        end
        if not model or model == "" then
            vim.notify("AI: " .. config.alt_model_env .. " env var not set", vim.log.levels.ERROR)
        end
        base.endpoint = url
        base.api_key = key
        base.model = model
    end

    return base
end

--- Send a streaming request to the active provider
--- @param messages table[] Conversation messages [{role, content}, ...]
--- @param on_delta fun(text: string) Called with each text chunk as it arrives
--- @param on_done fun() Called when the response is complete
--- @param on_error fun(err: string) Called on error
--- @param opts table|nil Optional overrides { system_prompt = "..." }
--- @return fun()|nil cancel Function to cancel the request, or nil on error
function M.stream(messages, on_delta, on_done, on_error, opts)
    debug.log("stream() called with " .. #messages .. " messages")
    debug.log("AI_WORK=" .. tostring(os.getenv("AI_WORK")))

    local provider_name = M.get_provider()
    local provider = providers.get(provider_name)
    local provider_config = build_provider_config(provider_name)

    if opts and opts.system_prompt then
        provider_config.system_prompt = opts.system_prompt
    end

    debug.log("using provider: " .. provider.name)

    local source = opts and opts.source or nil
    if source == "chat" or source == "lag" then
        local stored = {
            provider = provider_name,
            endpoint = provider_config.endpoint or "(cli)",
            model = provider_config.model or "(cli default)",
        }

        if provider_name == "anthropic" then
            stored.body = {
                model = provider_config.model,
                max_tokens = provider_config.max_tokens,
                system = provider_config.system_prompt,
                stream = true,
                messages = messages,
            }
        elseif provider_name == "alt" then
            stored.body = {
                model = provider_config.model,
                max_tokens = provider_config.max_tokens,
                stream = true,
                stream_options = { include_usage = true },
                messages = vim.list_extend(
                    { { role = "system", content = provider_config.system_prompt } },
                    vim.deepcopy(messages)
                ),
            }
        else
            local opencode = require("utils.ai.providers.opencode")
            stored.body = opencode.build_prompt(messages, provider_config.system_prompt)
        end

        if source == "chat" then
            last_chat_request = stored
        else
            last_lag_request = stored
        end
    end

    return provider.stream(messages, provider_config, {
        on_delta = on_delta,
        on_done = on_done,
        on_error = on_error,
    })
end

--- Toggle the alt OpenAI-compatible provider (work mode only)
--- @return boolean new alt_mode state
function M.toggle_alt()
    if not is_work_mode() then
        vim.notify("AI: Alt provider only available in work mode (AI_WORK)", vim.log.levels.WARN)
        return false
    end
    alt_mode = not alt_mode
    local provider = alt_mode and "alt" or "anthropic"
    debug.log("Toggled provider to: " .. provider)
    vim.notify("AI: Switched to " .. provider .. " provider")
    return alt_mode
end

function M.get_config()
    return vim.deepcopy(config)
end

--- Get the last request payload sent via chat.
--- @return table|nil
function M.get_last_chat_request()
    return last_chat_request
end

--- Get the last request payload sent via lag mode.
--- @return table|nil
function M.get_last_lag_request()
    return last_lag_request
end

--- Reset alt mode (for testing)
function M.reset_alt()
    alt_mode = false
end

return M

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
    system_prompt = "You are a helpful coding assistant. Be concise and direct.\n\nCRITICAL: When including ANY code snippet in your response, you MUST wrap it in <code> and </code> XML tags. The code inside must be raw — no backticks, no fences, no quotes around it. Even single-line snippets must use these tags. This is required for the editor integration.\n\nExample:\n<code>\nprint(\"hi\")\n</code>",
    -- Alt provider env var names (OpenAI-compatible, used when alt mode is toggled)
    alt_url_env = "AI_ALT_URL",
    alt_key_env = "AI_ALT_API_KEY",
    alt_model_env = "AI_ALT_MODEL",
}

local config = vim.deepcopy(default_config)

-- Whether the alt provider is active (only meaningful in work mode)
local alt_mode = false

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

    return provider.stream(messages, provider_config, {
        on_delta = on_delta,
        on_done = function(metadata) on_done(metadata) end,
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

--- Reset alt mode (for testing)
function M.reset_alt()
    alt_mode = false
end

return M

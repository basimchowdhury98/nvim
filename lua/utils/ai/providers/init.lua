-- providers/init.lua
-- Provider registry: validates contracts and resolves providers by name

local M = {}

local REQUIRED_FIELDS = {
    { key = "name", type = "string" },
    { key = "stream", type = "function" },
}

--- Validate that a provider satisfies the contract
--- @param provider table
--- @return table the same provider (for chaining)
local function validate(provider)
    for _, field in ipairs(REQUIRED_FIELDS) do
        local val = provider[field.key]
        assert(val ~= nil,
            "provider missing required field: " .. field.key)
        assert(type(val) == field.type,
            "provider." .. field.key .. " must be a " .. field.type .. ", got " .. type(val))
    end
    return provider
end

-- Lazy-loaded and validated provider cache
local providers = {}

--- Provider module paths keyed by name
local provider_modules = {
    opencode = "utils.ai.providers.opencode",
    anthropic = "utils.ai.providers.anthropic",
}

--- Get a validated provider by name
--- @param name string
--- @return table provider
function M.get(name)
    if providers[name] then
        return providers[name]
    end

    local mod_path = provider_modules[name]
    assert(mod_path, "unknown provider: " .. name)

    local provider = require(mod_path)
    validate(provider)
    providers[name] = provider
    return provider
end

--- Get all registered provider names
--- @return string[]
function M.list()
    local names = {}
    for name, _ in pairs(provider_modules) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return M

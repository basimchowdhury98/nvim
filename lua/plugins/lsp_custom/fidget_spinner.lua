local progress = require("fidget.progress")

local M = {}

M.handles = {}

function M:init()
    local group = vim.api.nvim_create_augroup("RoslynFidgetHooks", {})

    vim.api.nvim_create_autocmd({ "User" }, {
        pattern = "RoslynOnInit",
        group = group,
        callback = function (request)
            local handle = progress.handle.create({
                title = "Roslyn initializing",
                message = "In progress...",
                lsp_client = {
                    name = "Roslyn"
                }
            })
            M.handles[request.data.client_id] = handle
        end
    })

    vim.api.nvim_create_autocmd({ "User" }, {
        pattern = "RoslynInitialized",
        group = group,
        callback = function (request)
            local handle = M.handles[request.data.client_id]
            if handle then
               handle.message = "Completed" 
               handle:finish()
               handle[request.data.client_id] = nil
            end
        end
    })
end

return M

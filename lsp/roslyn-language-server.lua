local fs, uv = vim.fs, vim.uv

local fidget = require('fidget.progress')
local init_handle = {}

local function is_decompiled(bufname)
    local _, endpos = bufname:find('[/\\]MetadataAsSource[/\\]')
    if endpos == nil then
        return false
    end
    return vim.fn.finddir(bufname:sub(1, endpos), uv.os_tmpdir()) ~= ''
end

---@param client vim.lsp.Client
local function reload_attached_buffers(client)
    for buf, _ in pairs(client.attached_buffers) do
        if vim.bo[buf].modified then
            vim.notify(
                "Roslyn initialized; buffer has unsaved changes, skipping reload: " ..
                vim.api.nvim_buf_get_name(buf),
                vim.log.levels.WARN)
        else
            vim.api.nvim_buf_call(buf, function()
                vim.cmd.edit()
            end)
        end
    end
end

---@type vim.lsp.Config
return {
    name = 'roslyn',
    cmd = { 'roslyn-language-server', '--stdio' },
    cmd_env = {
        DOTNET_ROOT = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.exepath("dotnet")), ":h"),
        DOTNET_ROOT_ARM64 = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.exepath("dotnet")), ":h"),
        DOTNET_gcServer = "0",
        DOTNET_GCConserveMemory = "9",
        DOTNET_GCHeapHardLimit = "0x140000000",
    },
    filetypes = { 'cs' },
    root_dir = function(bufnr, on_root)
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        -- decompiled files are in the /tmp dir and need to be handled differently
        if is_decompiled(bufname) then
            local prev_buf = vim.fn.bufnr('#')
            if prev_buf <= 0 or not vim.api.nvim_buf_is_valid(prev_buf) then
                return
            end

            local client = vim.lsp.get_clients({
                name = 'roslyn',
                bufnr = prev_buf,
            })[1]
            if client then
                on_root(client.config.root_dir)
            end
            return
        end

        -- Find the first .sln in parents, if none find csproj
        local root_dir = fs.root(bufnr, {
            function(name, _)
                local ext = vim.fs.ext(name)
                return ext == 'sln' or ext == 'slnx'
            end,
            function(name, _)
                return vim.fs.ext(name) == 'csproj'
            end
        })

        if root_dir then
            on_root(root_dir)
        end
    end,
    on_init = {
        function(client)
            init_handle[client.id] = fidget.handle.create({
                title = "Roslyn initializing",
                message = "In progress...",
                lsp_client = {
                    name = "Roslyn"
                }
            })

            local root_dir = client.config.root_dir

            -- try load first solution we find
            for entry, type in fs.dir(root_dir) do
                if type == 'file' and (vim.endswith(entry, '.sln') or vim.endswith(entry, '.slnx')) then
                    client:notify('solution/open', {
                        solution = vim.uri_from_fname(fs.joinpath(root_dir, entry)),
                    })
                    return
                end
            end

            -- if no solution is found load project
            for entry, type in fs.dir(root_dir) do
                if type == 'file' and vim.endswith(entry, '.csproj') then
                    client:notify('project/open', {
                        projects = vim.tbl_map(function(file)
                            return vim.uri_from_fname(file)
                        end, { fs.joinpath(root_dir, entry) }),
                    })
                end
            end
        end
    },
    handlers = {
        ['workspace/projectInitializationComplete'] = function(_, _, ctx)
            local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
            reload_attached_buffers(client)

            local handle = init_handle[client.id]
            if handle then
                handle.message = "Completed"
                handle:finish()
                init_handle[client.id] = nil
            end
            return vim.NIL
        end,
    },
    capabilities = {
        workspace = {
            didChangeWatchedFiles = { dynamicRegistration = false },
        },
        textDocument = {
            diagnostic = {
                dynamicRegistration = true,
            },
        },
    },
    settings = {
        ["csharp|background_analysis"] = {
            dotnet_analyzer_diagnostics_scope = "openFiles",
            dotnet_compiler_diagnostics_scope = "openFiles",
        },
    },
}

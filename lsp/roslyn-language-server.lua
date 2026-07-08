local fs, uv = vim.fs, vim.uv

local function is_decompiled(bufname)
    local _, endpos = bufname:find('[/\\]MetadataAsSource[/\\]')
    if endpos == nil then
        return false
    end
    return vim.fn.finddir(bufname:sub(1, endpos), uv.os_tmpdir()) ~= ''
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
    root_dir = function(bufnr, cb)
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        -- decompiled files are in the /tmp dir and need to be handled differently
        if is_decompiled(bufname) then
            local prev_buf = vim.fn.bufnr('#')
            local client = vim.lsp.get_clients({
                name = 'roslyn',
                bufnr = prev_buf ~= 1 and prev_buf or nil,
            })[1]
            if client then
                cb(client.config.root_dir)
            end
            return
        end

        -- project files root is either the sln or fallback to proj
        local root_dir = fs.root(bufnr, function(fname, _)
            return fname:match('%.sln[x]?$') ~= nil
        end)

        if not root_dir then
            root_dir = fs.root(bufnr, function(fname, _)
                return fname:match('%.csproj$') ~= nil
            end)
        end

        if root_dir then
            cb(root_dir)
        end
    end,
    on_init = {
        function(client)
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
    capabilities = {
        workspace = {
            didChangeWatchedFiles = { dynamicRegistration = false },
        },
    },
    settings = {
        ["csharp|background_analysis"] = {
            dotnet_analyzer_diagnostics_scope = "openFiles",
            dotnet_compiler_diagnostics_scope = "openFiles",
        },
    },
}

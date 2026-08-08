local fs, uv = vim.fs, vim.uv

local fidget = require('fidget.progress')
local init_handle = {}

---@class RoslynNestedCodeActionArguments
---@field NestedCodeActions? lsp.CodeAction[]

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
    icon = '\u{e648}',
    name = 'roslyn',
    cmd = function(dispatchers, config)
        init_handle[config.root_dir] = fidget.handle.create({
            title = "Roslyn initializing",
            message = "In progress...",
            lsp_client = {
                name = "Roslyn"
            }
        })
        return vim.lsp.rpc.start({ 'roslyn-language-server', '--stdio' }, dispatchers,
            {
                env = {
                    DOTNET_ROOT = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.exepath("dotnet")), ":h"),
                    DOTNET_ROOT_ARM64 = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.exepath("dotnet")), ":h"),
                    DOTNET_gcServer = "0",
                    DOTNET_GCConserveMemory = "9",
                    DOTNET_GCHeapHardLimit = "0x140000000",
                }
            })
    end,
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

            local handle = init_handle[client.config.root_dir]
            if handle then
                handle.message = "Completed"
                handle:finish()
                init_handle[client.id] = nil
            end
            return vim.NIL
        end,
    },
    commands = {
        ['roslyn.client.nestedCodeAction'] = function(command, ctx)
            local client = assert(vim.lsp.get_client_by_id(ctx.client_id))

            local arguments = command.arguments and command.arguments[1]
            if type(arguments) ~= 'table' then
                vim.notify('roslyn_ls: invalid nestedCodeAction arguments', vim.log.levels.ERROR)
                return
            end

            ---@cast arguments RoslynNestedCodeActionArguments
            local nested_actions = arguments.NestedCodeActions
            if type(nested_actions) ~= 'table' then
                vim.notify('roslyn_ls: invalid nestedCodeAction arguments', vim.log.levels.ERROR)
                return
            end

            local handle = function(action)
                if action.edit then
                    vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
                end
                if action.command then
                    client:exec_cmd(action.command)
                end
            end

            vim.ui.select(nested_actions, {
                prompt = command.title or 'Select code action(no title)',
                format_item = function(action)
                    local label = ''
                    if action.command and action.command.command == 'roslyn.client.fixAllCodeAction' then
                        label = label .. 'Fix all: '
                    end

                    local fallback = action.title or (action.command and action.command.title) or 'Unnamed action'
                    if not action.data or not action.data.CodeActionPath then
                        return label .. fallback .. ' (no path)'
                    end
                    if #action.data.CodeActionPath < 3 then
                        return label .. fallback .. ' (< 3 path)'
                    end

                    return label .. action.data.CodeActionPath[2] .. " -> " .. action.data.CodeActionPath[3]
                end,
            }, function(chosen_action)
                if not chosen_action then
                    return
                end
                ---@diagnostic disable-next-line: undefined-field
                if chosen_action.data and not chosen_action.edit and not chosen_action.command then
                    client:request('codeAction/resolve', chosen_action, function(err, resolved)
                        if err then
                            vim.notify(err.message or tostring(err), vim.log.levels.ERROR)
                            return
                        end
                        if resolved then
                            handle(resolved)
                        end
                    end, ctx.bufnr)
                    return
                end

                handle(chosen_action)
            end)
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

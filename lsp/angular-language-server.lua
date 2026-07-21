local fs, fn, uv = vim.fs, vim.fn, vim.uv

local function resolve_cmd_shim_for_windows(cmd_path)
    if not cmd_path:lower():match('%ngserver.cmd$') then
        return cmd_path
    end

    local ok, content = pcall(fn.readblob, cmd_path)
    if not ok or not content then
        return cmd_path
    end

    local target = content:match('%s%"%%dp0%%\\([^\r\n]-ngserver[^\r\n]-)%"')
    if not target then
        return cmd_path
    end

    local full = fs.normalize(fs.joinpath(fs.dirname(cmd_path), target))

    return resolve_cmd_shim_for_windows(full)
end

local function collect_node_modules(root_dir)
    local modules = {}

    local project_node = fs.joinpath(root_dir, 'node_modules')
    if uv.fs_stat(project_node) then
        table.insert(modules, project_node)
    end

    local ngserver_exe = fn.exepath('ngserver')
    if ngserver_exe and #ngserver_exe > 0 then
        local realpath = uv.fs_realpath(ngserver_exe) or ngserver_exe
        realpath = resolve_cmd_shim_for_windows(realpath)
        local lsp_server_node = fs.normalize(fs.joinpath(fs.dirname(realpath), '../../..'))
        if uv.fs_stat(lsp_server_node) then
            table.insert(modules, lsp_server_node)
        end
    end

    return modules
end

local function get_angular_core_version(root_dir)
    local package_json = fs.joinpath(root_dir, 'package.json')
    if not uv.fs_stat(package_json) then
        return ''
    end

    local ok, content = pcall(fn.readblob, package_json)
    if not ok or not content then
        return ''
    end

    local json = vim.json.decode(content) or {}

    local version = (json.dependencies or {})['@angular/core'] or (json.devDependencies or {})['@angular/core'] or ''
    return version:match('%d+%.%d+%.%d+') or ''
end

---@type vim.lsp.Config
return {
    icon = '\u{e753}',
    cmd = function(dispatchers, config)
        if not config or not config.root_dir then
            error('No root path found')
        end
        local node_paths = collect_node_modules(config.root_dir)

        local ts_probe = table.concat(node_paths, ',')
        local ng_probe = table.concat(
            vim
            .iter(node_paths)
            :map(function(p)
                return fs.joinpath(p, '@angular/language-server/node_modules')
            end)
            :totable(),
            ','
        )
        local cmd = {
            'ngserver',
            '--stdio',
            '--tsProbeLocations',
            ts_probe,
            '--ngProbeLocations',
            ng_probe,
            '--angularCoreVersion',
            get_angular_core_version(config.root_dir),
        }
        return vim.lsp.rpc.start(cmd, dispatchers)
    end,
    filetypes = { 'typescript', 'html', 'htmlangular' },
    root_markers = { 'angular.json' },
    workspace_required = true,
    ---@param config vim.lsp.Config
    should_not_include_buf = function (config, bufnr)
        if not bufnr or bufnr == 0 then
            return true
        end

        local filetype = vim.bo[bufnr].filetype
        if not vim.list_contains(config.filetypes, filetype) then
            return true
        end

        local root_dir = fs.root(bufnr, config.root_markers)
        if root_dir == nil then
            return true
        end

        return false
    end
}

local divider = "\u{e0b9}"

local cached_git_status = {}
local function evaluate_git_status(bufnr)
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    local result = vim.system({
        "git",
        "--no-optional-locks",
        "-C", vim.fs.dirname(file_path),
        "status",
        "--porcelain=v1",
        "--",
        vim.fs.basename(file_path),
    }, { text = true }):wait()
    local git_status = result.stdout

    if result.code ~= 0 or git_status == nil or git_status == "" then
        cached_git_status[bufnr] = ""
        return ""
    end

    local st_line_status = " i\u{f02a2}w " .. divider

    local untracked_indic = git_status:sub(1, 2)
    if untracked_indic == "??" then
        return st_line_status:gsub("w", " +"):gsub("i", "")
    end

    local wt_indic = git_status:sub(2, 2)
    local index_indic = git_status:sub(1, 1)

    if wt_indic == "M" then
        st_line_status = st_line_status:gsub("w", " ~")
    elseif wt_indic == " " then
        st_line_status = st_line_status:gsub("w", "")
    else
        st_line_status = st_line_status:gsub("w", " ?")
    end


    if index_indic == "A" then
        st_line_status = st_line_status:gsub("i", "+ ")
    elseif index_indic == "M" then
        st_line_status = st_line_status:gsub("i", "~ ")
    elseif index_indic == " " then
        st_line_status = st_line_status:gsub("i", "")
    else
        st_line_status = st_line_status:gsub("i", "? ")
    end

    return st_line_status
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("status-line-git", { clear = true }),
    callback = function(event)
        local status = evaluate_git_status(event.buf)
        cached_git_status[event.buf] = status
    end
})

local cached_lsp_status = {}
vim.api.nvim_set_hl(0, "StatusLineDisabledLsp", {
    link = "Comment",
})

vim.api.nvim_create_autocmd({ 'FileType', 'LspAttach', 'LspDetach' }, {
    group = vim.api.nvim_create_augroup("status-line-lsp-update", { clear = true }),
    callback = function(event)
        local unknown_lsp_icon = '\u{ebc3}'

        local client_attached = {}
        local clients = vim.lsp.get_clients({ bufnr = event.buf })
        for _, client in ipairs(clients) do
            if event.event == 'LspDetach' and event.data.client_id == client.id then
                -- lsp detach runs before lsp actually detaches so it will pick up the client as active
                goto continue
            end
            client_attached[client.name] = true
            ::continue::
        end

        local buf_lsp_configs = vim.lsp.get_configs({
            enabled = true,
            filetype = vim.bo[event.buf].filetype
        })
        local status = ""
        for _, config in ipairs(buf_lsp_configs) do
            ---@diagnostic disable-next-line: undefined-field because: icon defined in /lsp
            local icon = config.icon or unknown_lsp_icon
            if not client_attached[config.name] then
                icon = "%#StatusLineDisabledLsp#" .. icon .. "%*"
            end

            status = status .. " " .. icon .. " " .. divider
        end

        cached_lsp_status[event.buf] = status
    end
})

local function lsp_status()
    local cached = cached_lsp_status[vim.api.nvim_get_current_buf()]
    if cached then
        return cached
    end

    return ""
end

local function git_status()
    local bufnr = vim.api.nvim_get_current_buf()
    local cached = cached_git_status[bufnr]

    if cached then
        return cached
    end

    local status = evaluate_git_status(bufnr)
    cached_git_status[bufnr] = status
    return status
end

local function modified_flag()
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].modified then
        return " [+] " .. divider
    end
    if not vim.bo[bufnr].modifiable then
        return " [-] " .. divider
    end

    return ""
end
_G.modified_flag = modified_flag
_G.git_status = git_status
_G.lsp_status = lsp_status

vim.opt_global.statusline = table.concat({
    "%{v:lua.modified_flag()}",
    "%< %f%r%h " .. divider,
    "%{v:lua.git_status()}",
    "%=",
    "%{%v:lua.lsp_status()%}",
    "%< %P " .. divider,
})

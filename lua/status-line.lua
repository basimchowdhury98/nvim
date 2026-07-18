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

    local wt_indic = git_status:sub(2, 2)
    local index_indic = git_status:sub(1, 1)

    if wt_indic == "?" then
        st_line_status = st_line_status:gsub("w", " +")
    elseif wt_indic == "M" then
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

vim.api.nvim_create_autocmd({ "WinEnter", "BufWritePost" }, {
    callback = function(event)
        local status = evaluate_git_status(event.buf)
        cached_git_status[event.buf] = status
    end
})

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

vim.o.statusline = table.concat({
    "%{v:lua.modified_flag()}",
    "%< %f%r%h " .. divider,
    "%{v:lua.git_status()}",
})

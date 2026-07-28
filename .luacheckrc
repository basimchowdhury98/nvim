std = "luajit"
max_line_length = false

globals = {
    "vim",
}

files["lua/**/_*.lua"] = {
    read_globals = {
        "describe",
        "it",
        "before_each",
        "after_each",
        "assert",
    },
}


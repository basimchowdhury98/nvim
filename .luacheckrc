std = "luajit"
max_line_length = false

read_globals = {
    "vim",
}

files["specs/**/*.lua"] = {
    read_globals = {
        "describe",
        "it",
        "before_each",
        "after_each",
        "assert",
    },
}

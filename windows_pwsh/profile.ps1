$env:OPENCODE_CONFIG_DIR = "$env:NVIM\opencode"
$env:OPENCODE_ENABLE_EXA = 1

Set-Alias d docker

function di {
    docker image @args
}

function dc {
    docker container @args
}

function dcu {
    docker compose up
}

Set-Alias g git

function gs {
    git status
}

# j and k for down/up = pull/push
function gj {
    git pull
}
function gk {
    git push
}

function gap {
    git status
    git add -N .
    git add -p
}

function ga. {
    git add .
}

function gcom {
    git commit -m "$args"
}

function gcoma {
    git commit --amend
}

function gst {
    git stash --include-untracked
}

function grh {
    git reset --hard
}

function glo {
    param([int]$n = 5)
    git log -n $n --oneline
}

Set-Alias dn dotnet

function dnt {
    dotnet test @args
}

function dnb {
    dotnet build
}

function dnr {
    dotnet run
}

Remove-PSReadLineKeyHandler -Chord 'Ctrl+v'

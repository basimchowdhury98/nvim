$env:OPENCODE_CONFIG_DIR = "$env:NVIM\.not-nvim\opencode"
$env:OPENCODE_ENABLE_EXA = 1

# IMPORTANT: going to suspend supporting this because pretty use zshrc in all my machines(wsl at work)
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

function gtorch {
    $confirm = Read-Host "Are you sure? [y/N]"
    if ($confirm -notin @('y', 'Y', 'yes', 'YES', 'Yes')) {
        Write-Host "Cancelled."
        return
    }

    git reset --hard
    git clean -f -d
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

function oc {
    opencode
}

function ocq {
    opencode run "You are being ran from the terminal. Keep your response short and to the point. $args"
}

Remove-PSReadLineKeyHandler -Chord 'Ctrl+v'

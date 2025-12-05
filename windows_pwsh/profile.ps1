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

Set-Alias dn dotnet

function dnt {
    dotnet test
}

function dnb {
    dotnet build
}

function dnr {
    dotnet run
}

Remove-PSReadLineKeyHandler -Chord 'Ctrl+v'

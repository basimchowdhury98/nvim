Set-Alias d docker

function di {
    docker image @args
}

function dc {
    docker container @args
}

Set-Alias g git

function gs {
    git status
}

function gap {
    git add -p
}

function gc {
    param([string]$message)
    git commit -m $message
}

Remove-PSReadLineKeyHandler -Chord 'Ctrl+v'

oh-my-posh init pwsh --config 'gruvbox' | Invoke-Expression

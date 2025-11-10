# Aliases
alias d='docker'
alias g='git'

# Docker functions
di() {
    docker image "$@"
}

dc() {
    docker container "$@"
}

# Git functions
gs() {
    git status
}

gap() {
    git add -p
}

gc() {
    git commit -m "$1"
}

# Oh My Posh (if installed on macOS)
eval "$(oh-my-posh init zsh --config 'gruvbox')"

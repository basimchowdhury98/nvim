alias d='docker'
di() {
    docker image "$@"
}
dc() {
    docker container "$@"
}
dcu() {
    docker compose up
}
alias g='git'
gs() {
    git status
}
# j and k for down/up = pull/push
gj() {
    git pull
}
gk() {
    git push
}
gap() {
    git add -p
}
ga.() {
    git add .
}
gcom() {
    git commit -m "$*"
}
gcoma() {
    git commit --amend
}
gst() {
    git stash --include-untracked
}
alias dn='dotnet'
dnt() {
    dotnet test
}
dnb() {
    dotnet build
}

# Oh My Posh (if installed on macOS)
eval "$(oh-my-posh init zsh --config 'gruvbox')"

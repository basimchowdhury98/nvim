export OPENCODE_CONFIG_DIR="$NVIM/opencode"
export OPENCODE_ENABLE_EXA=1

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
    git status
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
grh() {
    git reset --hard
}
glo() {
    git log -n ${1:-5} --oneline
}
alias dn='dotnet'
dnt() {
    dotnet test
}
dnb() {
    dotnet build
}
dnr() {
    dotnet run
}

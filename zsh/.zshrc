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
    git add -N .
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
gtorch() {
    read "confirm?Are you sure? [y/N] "
    case "$confirm" in
        y|Y|yes|YES|Yes)
            git reset --hard
            git clean -f -d
            ;;
        *)
            printf '%s\n' 'Cancelled.'
            ;;
    esac
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

oc() {
    opencode
}
ocq() {
    opencode run "$*"
}

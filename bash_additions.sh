#!/bin/bash

export BASH_ADDITIONS_LOADED=1

pathadd() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        # Only announce in interactive shells: this file is also sourced
        # by non-interactive ones (ssh commands, scp), where stray stdout
        # output breaks the protocol.
        [[ $- == *i* ]] && echo "Adding $1 to PATH..."
        PATH="${PATH:+"$PATH:"}$1"
    fi
}

pathadd "$HOME/.cargo/bin"
pathadd "$HOME/bin"
pathadd "$HOME/.yarn/bin"
pathadd "$HOME/go/bin"

# Per-dev-box ID generated once by install.sh. Bookmarks under lc/<id>/
# belong to this box. Single-segment lc/<name> bookmarks are shared by
# every box (see ~/.config/jj/conf.d/instance.toml). No trailing slash:
# tooling builds branch names as "$BRANCH_PREFIX/<name>".
if [ -s "$HOME/.config/dev-instance/id" ]; then
    export DEV_INSTANCE_ID="$(<"$HOME/.config/dev-instance/id")"
    export BRANCH_PREFIX="lc/$DEV_INSTANCE_ID"
else
    unset DEV_INSTANCE_ID
    export BRANCH_PREFIX="lc"
fi

# Google Workspace CLI (gws) OAuth project. Exported for non-interactive
# shells too, so agents running gws pick it up.
export GOOGLE_WORKSPACE_PROJECT_ID=gws-cli-oauth-496100

# Skip the rest if we are not in an interactive session (e.g., user in shell)
[[ $- != *i* ]] && return

eval "$(starship init bash)"
eval "$(fzf --bash)"
source <(COMPLETE=bash jj)

alias jjwl='watch -cn 2 "jj --color always log --no-pager --ignore-working-copy"'
alias jjws='watch -cn 2 "jj --color always st"'
alias jjnp='reset && jj log --no-pager --ignore-working-copy'

# jj workspace helpers: the `ws` cd wrapper and completion. The command
# itself is bin/ws, which agents can call too. Interactive only, because
# non-interactive shells get ~/bin/ws from PATH.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ws/shell.bash"

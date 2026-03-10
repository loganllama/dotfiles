#!/bin/bash

export BASH_ADDITIONS_LOADED=1

pathadd() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        echo "Adding $1 to PATH..."
        PATH="${PATH:+"$PATH:"}$1"
    fi
}

pathadd "$HOME/.cargo/bin"
pathadd "$HOME/bin"
pathadd "$HOME/.yarn/bin"

# Skip the rest if we are not in an interactive session (e.g., user in shell)
[[ $- != *i* ]] && return

eval "$(starship init bash)"
eval "$(fzf --bash)"
source <(COMPLETE=bash jj)
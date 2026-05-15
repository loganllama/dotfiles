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

alias jjwl='watch -cn 2 "jj --color always log --no-pager --ignore-working-copy"'
alias jjws='watch -cn 2 "jj --color always st"'
alias jjnp='reset && jj log --no-pager --ignore-working-copy'

# --- jj workspace helpers ---

# Run a jj command in a workspace dir, auto-recovering from stale state
_ws_jj() {
    local dir="$1"; shift
    local output rc
    output="$(cd "$dir" && jj "$@" 2>&1)"
    rc=$?
    if [[ $rc -ne 0 && "$output" == *"working copy is stale"* ]]; then
        echo "Updating stale workspace $(basename "$dir")..." >&2
        if ! (cd "$dir" && jj workspace update-stale 2>&1); then
            echo "Failed to update stale workspace $(basename "$dir")" >&2
            return 1
        fi
        output="$(cd "$dir" && jj "$@" 2>&1)"
        rc=$?
    fi
    [[ -n "$output" ]] && echo "$output"
    return $rc
}

# ws N [cmd...]  — cd to wsN, or run cmd there without leaving cwd
ws() {
    local n="$1"; shift
    local dir="/workspaces/obsidian-ws/ws${n}"
    if [[ ! -d "$dir" ]]; then
        echo "ws${n} does not exist" >&2; return 1
    fi
    if [[ $# -eq 0 ]]; then
        cd "$dir"
    else
        (cd "$dir" && "$@")
    fi
}

# wsa cmd...  — run cmd in every ws1-ws5
wsa() {
    for dir in /workspaces/obsidian-ws/ws{1..5}; do
        [[ -d "$dir" ]] || continue
        echo "=== $(basename "$dir") ==="
        (cd "$dir" && "$@")
    done
}

# wspark N  — park wsN on the parking_lot bookmark
# wspark -a  — park every ws1-ws5 on parking_lot
wspark() {
    if [[ "$1" == "-a" ]]; then
        local rc=0
        for dir in /workspaces/obsidian-ws/ws{1..5}; do
            [[ -d "$dir" ]] || continue
            local name="$(basename "$dir")"
            if _ws_jj "$dir" edit parking_lot; then
                echo "${name} parked"
            else
                echo "Failed to park ${name}" >&2
                rc=1
            fi
        done
        return $rc
    fi
    local n="$1"
    local dir="/workspaces/obsidian-ws/ws${n}"
    if [[ ! -d "$dir" ]]; then
        echo "ws${n} does not exist" >&2; return 1
    fi
    if ! _ws_jj "$dir" edit parking_lot; then
        echo "Failed to park ws${n}" >&2; return 1
    fi
    echo "ws${n} parked"
}

# wsinfo  — one-line summary of each workspace
wsinfo() {
    for dir in /workspaces/obsidian-ws/ws{1..5}; do
        [[ -d "$dir" ]] || continue
        local name="$(basename "$dir")"
        local desc="$(_ws_jj "$dir" log -r @ -n1 --no-pager -T 'description.first_line()' 2>/dev/null)"
        local change="$(_ws_jj "$dir" log -r @ -n1 --no-pager -T 'change_id.short(8)' 2>/dev/null)"
        printf "%-4s  %s  %s\n" "$name" "$change" "$desc"
    done
}

_ws_complete() {
    local cur="${COMP_WORDS[1]}"
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=($(compgen -W "1 2 3 4 5" -- "$cur"))
    fi
}
_wspark_complete() {
    local cur="${COMP_WORDS[1]}"
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=($(compgen -W "1 2 3 4 5 -a" -- "$cur"))
    fi
}
complete -F _ws_complete ws
complete -F _wspark_complete wspark

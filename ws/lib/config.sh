# shellcheck shell=bash disable=SC2034 # these globals are read by the other files
# Shared settings for bin/ws and bin/ws-hook. Sourced, never run.
#
# The WS_* path variables can be overridden from the environment so the
# tests can point everything at a temp dir instead of the real pool.

WS_DEFAULT_PATH="${WS_DEFAULT_PATH:-/workspaces/obsidian}"
WS_PARENT="${WS_PARENT:-/workspaces/obsidian-ws}"
WS_LEASE_DIR="${WS_LEASE_DIR:-$WS_PARENT/.leases}"
# Claude Code's own per-process session records. Not a documented
# interface, which is why lease.sh falls back to the stored pid.
WS_SESSIONS_DIR="${WS_SESSIONS_DIR:-$HOME/.claude/sessions}"

# The agent pool. `default` (the main checkout) is leasable too, but is
# deliberately not in this list so automatic picks never land on it.
WS_POOL=(ws1 ws2 ws3 ws4 ws5)
WS_ALL=(default "${WS_POOL[@]}")

WS_PARKING_BOOKMARK="parking_lot"
# What `ws acquire` starts a ws1-5 lease on when --at isn't given.
WS_DEFAULT_REV="main"
WS_PARKING_DESC="DND: workspace parking lot"

# How long a pool change waits for another `ws` call to let go of the lock.
WS_LOCK_TIMEOUT="${WS_LOCK_TIMEOUT:-60}"

# Basenames the hook never governs: files jj doesn't snapshot (ignored by
# obsidian's .gitignore), used as per-session notes.
WS_HOOK_EXEMPT_GLOBS=('*.local.md')

# jj subcommands that change a workspace, for the hook's Bash warning.
# `workspace` and `bookmark` are only state-changing with the second-level
# subcommands listed in WS_JJ_MUTATING_SUB. tug/sync/tidy are aliases from
# dotfiles' jj/config.toml.
WS_JJ_MUTATING=(new edit squash rebase describe desc abandon restore commit
    split next prev absorb undo diffedit resolve tug sync tidy)
WS_JJ_MUTATING_SUB=("workspace update-stale" "bookmark set" "bookmark move"
    "bookmark create" "bookmark s" "bookmark m" "bookmark c")

WS_PREP_CMD='pnpm install && npx turbo generate-types --continue=dependencies-successful --output-logs=errors-only; npx turbo daemon restart'

# Normalize a user-supplied workspace id (default, 1-5, ws1-ws5) to its
# name. Prints nothing and fails for anything else.
ws_normalize_id() {
    local id="$1" name
    case "$id" in
        default) echo default; return 0 ;;
        [0-9] | [0-9][0-9]) name="ws$id" ;;
        *) name="$id" ;;
    esac
    local w
    for w in "${WS_POOL[@]}"; do
        if [[ "$w" == "$name" ]]; then
            echo "$name"
            return 0
        fi
    done
    return 1
}

ws_path_of() {
    if [[ "$1" == default ]]; then
        echo "$WS_DEFAULT_PATH"
    else
        echo "$WS_PARENT/$1"
    fi
}

# shellcheck shell=bash
# jj helpers for the pool. Sourced after config.sh, never run.

# Run jj in a workspace dir, recovering once from a stale working copy.
# Combined output goes to stdout, like the old _ws_jj. Only use this for
# commands the caller is entitled to run there (it may run update-stale).
ws_jj() {
    local dir="$1"; shift
    local output rc=0
    output="$(cd "$dir" && jj "$@" 2>&1)" || rc=$?
    if [[ $rc -ne 0 && "$output" == *"working copy is stale"* ]]; then
        echo "Updating stale workspace $(basename "$dir")..." >&2
        if ! (cd "$dir" && jj workspace update-stale 2>&1); then
            echo "Failed to update stale workspace $(basename "$dir")" >&2
            return 1
        fi
        rc=0
        output="$(cd "$dir" && jj "$@" 2>&1)" || rc=$?
    fi
    [[ -z "$output" ]] || echo "$output"
    return "$rc"
}

# One read of a workspace's @: change id, its shortest unique prefix (what
# jj highlights), empty flag, has-description flag,
# local bookmarks (comma-separated), the first description line, and a
# last field saying how it was read. No stale recovery: `ws status` must
# not run update-stale in a workspace someone else may be using, so on a
# stale working copy it reads without snapshotting and says `stale`.
WS_INFO_TEMPLATE='change_id.short(8) ++ "\x1f" ++ change_id.shortest().prefix() ++ "\x1f" ++ if(empty, "1", "0") ++ "\x1f" ++ if(description, "1", "0") ++ "\x1f" ++ local_bookmarks.map(|b| b.name()).join(",") ++ "\x1f" ++ description.first_line() ++ "\n"'
# Fields are split on \x1f, not tab: tab is IFS whitespace, so `read` would
# merge the empty bookmark/description fields and shift the rest.
WS_SEP=$'\x1f'
# This does snapshot the working copy, even in workspaces the caller doesn't
# hold: idle detection must see edits that haven't been snapshotted yet, or
# a workspace with unsaved work would look parked and be handed out.
ws_jj_info() {
    local dir="$1" out
    if out="$(cd "$dir" && jj log --no-pager --no-graph -r @ -T "$WS_INFO_TEMPLATE" 2>/dev/null)"; then
        printf '%s\x1fok\n' "$out"
    elif out="$(cd "$dir" && jj log --no-pager --no-graph --ignore-working-copy -r @ -T "$WS_INFO_TEMPLATE" 2>/dev/null)"; then
        printf '%s\x1fstale\n' "$out"
    else
        return 1
    fi
}

# Idle means nothing can be lost by handing the workspace to someone else.
# ws1-5: parked, i.e. @ is the (still empty) parking_lot commit.
# default: @ is an empty commit with no description.
# Anything we can't read (missing dir, stale working copy) counts as busy.
ws_is_idle() {
    local name="$1" dir info empty has_desc bookmarks state
    dir="$(ws_path_of "$name")"
    [[ -d "$dir" ]] || return 1
    info="$(ws_jj_info "$dir")" || return 1
    IFS="$WS_SEP" read -r _ _ empty has_desc bookmarks _ state <<<"$info"
    [[ "$state" == ok && "$empty" == 1 ]] || return 1
    if [[ "$name" == default ]]; then
        [[ "$has_desc" == 0 ]]
    else
        [[ ",$bookmarks," == *",$WS_PARKING_BOOKMARK,"* ]]
    fi
}

ws_park() {
    local name="$1" dir
    dir="$(ws_path_of "$name")"
    ws_jj "$dir" edit "$WS_PARKING_BOOKMARK" >&2
}

ws_registered_workspaces() {
    (cd "$WS_DEFAULT_PATH" && jj workspace list --no-pager 2>/dev/null) | sed 's/:.*//'
}

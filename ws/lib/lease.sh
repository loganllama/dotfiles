# shellcheck shell=bash disable=SC2034 # WS_STATE etc. are read by the callers
# Lease records: who owns which workspace. Sourced after config.sh and
# jj.sh, never run. bin/ws-hook sources this too, so nothing here may run
# jj or take the lock unless a command function asks for it.

# Field 22 of /proc/<pid>/stat (start time in clock ticks since boot).
# The comm field can contain spaces and parens, so split after the last ')'.
ws_proc_start() {
    local stat rest
    stat="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
    rest="${stat##*) }"
    local -a f
    read -r -a f <<<"$rest"
    # f[0] is field 3, so field 22 is f[19].
    [[ -n "${f[19]:-}" ]] || return 1
    echo "${f[19]}"
}

ws_pid_matches() {
    local pid="$1" want="$2" got
    [[ -n "$pid" && -n "$want" ]] || return 1
    got="$(ws_proc_start "$pid")" || return 1
    [[ "$got" == "$want" ]]
}

# The owner record a lease taken now would store. A caller without
# CLAUDE_CODE_SESSION_ID is a human at a terminal.
ws_identity() {
    if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
        local pid="${CLAUDE_PID:-}" start="" name=""
        if [[ -n "$pid" ]]; then
            start="$(ws_proc_start "$pid" || true)"
            name="$(jq -r '.name // ""' "$WS_SESSIONS_DIR/$pid.json" 2>/dev/null || true)"
        fi
        jq -cn --arg sid "$CLAUDE_CODE_SESSION_ID" --arg name "$name" \
            --arg pid "$pid" --arg start "$start" \
            '{kind: "claude", session_id: $sid, session_name: $name,
              pid: (if $pid == "" then null else ($pid | tonumber) end),
              proc_start: $start}'
    else
        local t
        t="$(tty 2>/dev/null)" || t=""
        jq -cn --arg user "$(id -un)" --arg tty "$t" '{kind: "human", user: $user, tty: $tty}'
    fi
}

# Owners compare by session id (Claude) or user name (human). Subagents
# share their parent's session id, so they count as the same owner.
ws_owner_key_of() {
    jq -r '.owner // {} | if .kind == "claude" then "claude:" + (.session_id // "")
        elif .kind == "human" then "human:" + (.user // "")
        else "unknown:" end' <<<"$1"
}

ws_caller_key() {
    if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
        echo "claude:$CLAUDE_CODE_SESSION_ID"
    else
        echo "human:$(id -un)"
    fi
}

ws_lease_file() { echo "$WS_LEASE_DIR/$1.json"; }

# Print a lease, or fail if there is none. A file that exists but doesn't
# parse still counts as a lease (owner unknown), so it can't read as free.
ws_lease_read() {
    local f
    f="$(ws_lease_file "$1")"
    [[ -f "$f" ]] || return 1
    jq -c . "$f" 2>/dev/null || jq -cn --arg ws "$1" '{workspace: $ws, owner: {kind: "unknown"}}'
}

# "obsidian-9f (61f6418b)", "human vscode", ...
# Who holds a lease, for messages: "name (session 1234abcd)". With "short"
# as $2 (the `ws status` table), "name 1234abcd".
ws_holder_desc() {
    jq -r --arg short "${2:-}" '.owner // {} |
        if .kind == "claude" then
            (if (.session_name // "") != "" then .session_name + " " else "" end)
            + ((.session_id // "?")[0:8] | if $short == "short" then . else "(session " + . + ")" end)
        elif .kind == "human" then "human " + (.user // "?")
        else "unknown owner" end' <<<"$1"
}

# Is a lease's owner still around? Humans always are (D10). A Claude owner
# is live if some session record names its session id with a pid that is
# running and started when the record says. That survives `claude -r`
# (same session id, new pid). If the sessions dir is missing, or a matching
# record doesn't parse, fall back to the pid stored in the lease, which
# can only make a resumed session look stale, never a dead one look live.
#
# Sets WS_LIVENESS_FALLBACK=1 whenever the fallback was used, so
# `ws status` can say so.
WS_LIVENESS_FALLBACK=0
ws_owner_live() {
    local lease="$1" kind sid
    kind="$(jq -r '.owner.kind // ""' <<<"$lease")"
    [[ "$kind" == human ]] && return 0
    [[ "$kind" == claude ]] || return 1
    sid="$(jq -r '.owner.session_id // ""' <<<"$lease")"
    [[ -n "$sid" ]] || return 1

    local use_fallback=0 f rec pid start
    if [[ -d "$WS_SESSIONS_DIR" ]] && compgen -G "$WS_SESSIONS_DIR/*.json" >/dev/null; then
        # grep first: there can be dozens of records, and only a few mention sid.
        while IFS= read -r f; do
            if ! rec="$(jq -er --arg s "$sid" \
                    'if .sessionId == $s then "\(.pid) \(.procStart)" else "" end' "$f" 2>/dev/null)"; then
                use_fallback=1
                continue
            fi
            [[ -n "$rec" ]] || continue
            read -r pid start <<<"$rec"
            if ws_pid_matches "$pid" "$start"; then return 0; fi
        done < <(grep -lF -- "$sid" "$WS_SESSIONS_DIR"/*.json 2>/dev/null || true)
    else
        use_fallback=1
    fi

    if [[ $use_fallback == 1 ]]; then
        WS_LIVENESS_FALLBACK=1
        pid="$(jq -r '.owner.pid // ""' <<<"$lease")"
        start="$(jq -r '.owner.proc_start // ""' <<<"$lease")"
        if ws_pid_matches "$pid" "$start"; then return 0; fi
    fi
    return 1
}

# Sets WS_STATE to free | held-self | held | stale-idle | stale-busy and
# WS_LEASE to the lease JSON ("" when free). Globals rather than output so
# callers keep WS_LIVENESS_FALLBACK, which a subshell would lose.
ws_state() {
    local name="$1"
    WS_LEASE=""
    if ! WS_LEASE="$(ws_lease_read "$name")"; then
        WS_LEASE=""
        WS_STATE=free
    elif [[ "$(ws_owner_key_of "$WS_LEASE")" == "$(ws_caller_key)" ]]; then
        WS_STATE=held-self
    elif ws_owner_live "$WS_LEASE"; then
        WS_STATE=held
    elif ws_is_idle "$name"; then
        WS_STATE=stale-idle
    else
        WS_STATE=stale-busy
    fi
}

# Every pool change happens under this lock. It's held until ws_unlock or
# process exit. Readers (status, the hook) never take it: lease files are
# replaced by rename, so they always see a whole file.
ws_lock() {
    mkdir -p "$WS_LEASE_DIR"
    exec {WS_LOCK_FD}>>"$WS_LEASE_DIR/.lock"
    if ! flock -w "$WS_LOCK_TIMEOUT" "$WS_LOCK_FD"; then
        echo "ws: timed out after ${WS_LOCK_TIMEOUT}s waiting for $WS_LEASE_DIR/.lock" >&2
        return 1
    fi
}

# Long-running children (pnpm, turbo's daemon) would inherit the lock fd
# and keep the pool locked, so drop it before running them.
ws_unlock() {
    if [[ -n "${WS_LOCK_FD:-}" ]]; then
        exec {WS_LOCK_FD}>&-
        WS_LOCK_FD=""
    fi
}

# ws_lease_write NAME OWNER_JSON LABEL ASSIGNEE [ACQUIRED_AT]
ws_lease_write() {
    local name="$1" owner="$2" label="$3" assignee="$4"
    local acquired="${5:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local f tmp
    f="$(ws_lease_file "$name")"
    mkdir -p "$WS_LEASE_DIR"
    tmp="$(mktemp "$WS_LEASE_DIR/.$name.json.XXXXXX")"
    if ! jq -n --arg ws "$name" --arg path "$(ws_path_of "$name")" --argjson owner "$owner" \
            --arg label "$label" --arg assignee "$assignee" --arg at "$acquired" \
            '{workspace: $ws, path: $path, owner: $owner, label: $label,
              assignee: $assignee, acquired_at: $at}' >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$f"
}

ws_lease_remove() {
    rm -f "$(ws_lease_file "$1")"
}

# shellcheck shell=bash
# One function per `ws` subcommand. Sourced by bin/ws after config.sh,
# jj.sh and lease.sh. Paths and --json go to stdout; everything else goes
# to stderr, so `cd "$(ws acquire ...)"` works.

ws_msg() { echo "$*" >&2; }
ws_die() { echo "ws: $*" >&2; exit 1; }

# Resolve an id to a workspace name whose directory exists.
ws_require() {
    local name
    name="$(ws_normalize_id "$1")" || ws_die "unknown workspace '$1' (expected default, 1-5 or ws1-ws5)"
    [[ -d "$(ws_path_of "$name")" ]] || ws_die "$name does not exist at $(ws_path_of "$name") (run 'ws init')"
    echo "$name"
}

ws_existing() {
    local name
    for name in "$@"; do
        [[ -d "$(ws_path_of "$name")" ]] && echo "$name"
    done
    return 0
}

cmd_help() {
    cat <<'EOF'
usage: ws <command> [args]     <id> is default, 1-5 or ws1-ws5

  ws <id>                 cd there (shell function) / print its path (executable)
  ws <id> <cmd...>        run cmd in that workspace
  ws all <cmd...>         run cmd in each of ws1-ws5
  ws status [--json]      leases and @ of every workspace
  ws acquire [<id>] [--label T] [--for NAME] [--at REV] [--prep]
                          claim a workspace (no <id>: first free ws1-ws5), print its path.
                          A new ws1-ws5 lease starts a new revision on --at REV
                          (default: main). --at is not for default, which acquire
                          never moves.
  ws release <id> [--no-park] [--force]
                          drop the lease and park ws1-ws5 on parking_lot
  ws release --all [--force]
                          release your leases (and stale-idle ones); never touches
                          unleased workspaces. --force includes other owners' leases
  ws release --stale      drop leases whose owner is gone and workspace is idle
  ws adopt <id> [--label T] [--for NAME] [--force]
                          take over a stale lease without moving @
  ws prep <id>            regenerate derived files (pnpm install, turbo generate-types)
  ws init                 create parking_lot, missing ws1-ws5 and the lease dir
  ws whoami               the owner a lease would record
EOF
}

cmd_path() {
    [[ $# -eq 1 ]] || ws_die "usage: ws path <id>"
    local name
    name="$(ws_require "$1")"
    ws_path_of "$name"
}

cmd_run() {
    local name dir
    name="$(ws_require "$1")"; shift
    dir="$(ws_path_of "$name")"
    cd "$dir" && exec "$@"
}

cmd_all() {
    [[ $# -gt 0 ]] || ws_die "usage: ws all <cmd...>"
    local name rc=0
    for name in $(ws_existing "${WS_POOL[@]}"); do
        echo "=== $name ==="
        (cd "$(ws_path_of "$name")" && "$@") || rc=1
    done
    return "$rc"
}

ws_age() {
    local at="$1" start now s
    [[ -n "$at" ]] || return 0
    start="$(date -u -d "$at" +%s 2>/dev/null)" || return 0
    now="$(date -u +%s)"
    s=$((now - start))
    if ((s < 3600)); then echo "$((s / 60))m"
    elif ((s < 86400)); then echo "$((s / 3600))h"
    else echo "$((s / 86400))d"; fi
}

# Set variable $1 to $2 cut to at most $3 characters (ending in "…" when
# cut) and, unless $4 is "nopad", padded with spaces to exactly $3.
ws_fit() {
    local -n _out="$1"
    local s="$2" w="$3"
    ((w > 0)) || { _out=""; return 0; }
    ((${#s} <= w)) || s="${s:0:w-1}…"
    if [[ "${4:-}" == nopad ]]; then _out="$s"; else printf -v _out '%s%*s' "$s" $((w - ${#s})) ''; fi
}

# The `ws status` table. Columns are sized to their contents, up to the
# caps below. On a terminal, DESCRIPTION is cut to fit the width and the
# unique prefix of @ is highlighted the way jj does; piped output is plain
# and uncut (use --json for scripts).
ws_status_table() {
    local LC_ALL=C.UTF-8 # so ${#s} and cuts count characters, not bytes
    local tty=0 cols=0 color=0
    if [[ -t 1 ]]; then
        tty=1
        cols="$(tput cols 2>/dev/null)" || cols=0
        [[ -n "${NO_COLOR:-}" ]] || color=1
    fi
    local -a heads=(WS STATE HOLDER FOR LABEL AGE '@') caps=(8 11 30 10 24 4 12)
    local ncol=${#heads[@]}
    local -a cells=() prefixes=() descs=() widths=() f
    local row i r n=0
    for row; do
        mapfile -t f < <(jq -r '.name, .state, .holder, .assignee, .label, (.acquired_at // ""),
            .change, .change_prefix, .description, .working_copy' <<<"$row")
        case "${f[1]}" in
            stale-busy) f[1]="STALE-busy" ;;
            stale-idle) f[1]="stale-idle" ;;
        esac
        [[ "${f[9]}" == ok ]] || f[8]="(${f[9]} working copy) ${f[8]}"
        # The table's holder is the short form; --json keeps the long one.
        [[ -z "${f[2]}" ]] || f[2]="$(ws_holder_desc "$row" short)"
        cells+=("${f[0]}" "${f[1]}" "${f[2]:--}" "${f[3]:--}" "${f[4]:--}" "$(ws_age "${f[5]}")" "${f[6]}")
        prefixes+=("${f[7]}") descs+=("${f[8]}")
        n=$((n + 1))
    done
    local used=0
    for ((i = 0; i < ncol; i++)); do
        widths[i]=${#heads[i]}
        for ((r = 0; r < n; r++)); do
            local c="${cells[r * ncol + i]}"
            ((${#c} <= widths[i])) || widths[i]=${#c}
        done
        ((widths[i] <= caps[i])) || widths[i]=${caps[i]}
        used=$((used + widths[i] + 1))
    done
    # Room left for DESCRIPTION; -1 means unlimited (not a terminal).
    local room=-1
    if [[ $tty == 1 && $cols -gt 0 ]]; then
        room=$((cols - used))
        ((room >= 0)) || room=0
    fi
    local line cell d
    line=""
    for ((i = 0; i < ncol; i++)); do
        ws_fit cell "${heads[i]}" "${widths[i]}"
        line+="$cell "
    done
    d=DESCRIPTION
    ((room < 0)) || ws_fit d "$d" "$room" nopad
    printf '%s\n' "${line%% }${d:+ }$d" | sed 's/ *$//'
    for ((r = 0; r < n; r++)); do
        line=""
        for ((i = 0; i < ncol; i++)); do
            ws_fit cell "${cells[r * ncol + i]}" "${widths[i]}"
            local p="${prefixes[r]}"
            if ((i == ncol - 1)) && [[ $color == 1 && -n "$p" && "${cells[r * ncol + i]}" == "$p"* ]]; then
                # jj's default change-id colors: bold magenta prefix, grey rest.
                cell=$'\e[1;35m'"$p"$'\e[0;90m'"${cell:${#p}}"$'\e[0m'
            fi
            line+="$cell "
        done
        d="${descs[r]}"
        ((room < 0)) || ws_fit d "$d" "$room" nopad
        printf '%s\n' "$line$d" | sed 's/ *$//'
    done
}

cmd_status() {
    local json=0
    case "${1:-}" in
        --json) json=1 ;;
        "") ;;
        *) ws_die "usage: ws status [--json]" ;;
    esac
    local name dir state lease info change prefix desc wc rows=()
    for name in $(ws_existing "${WS_ALL[@]}"); do
        dir="$(ws_path_of "$name")"
        ws_state "$name"
        state="$WS_STATE" lease="${WS_LEASE:-null}"
        change="" prefix="" desc="" wc="unreadable"
        if info="$(ws_jj_info "$dir")"; then
            IFS="$WS_SEP" read -r change prefix _ _ _ desc wc <<<"$info"
        fi
        rows+=("$(jq -cn --arg name "$name" --arg path "$dir" --arg state "$state" \
            --argjson lease "$lease" --arg change "$change" --arg prefix "$prefix" \
            --arg desc "$desc" --arg wc "$wc" \
            --arg holder "$( [[ "$lease" == null ]] || ws_holder_desc "$lease")" \
            '{name: $name, path: $path, state: $state, holder: $holder,
              owner: ($lease.owner // null), label: ($lease.label // ""),
              assignee: ($lease.assignee // ""), acquired_at: ($lease.acquired_at // null),
              change: $change, change_prefix: $prefix, description: $desc, working_copy: $wc}')")
    done
    if [[ $json == 1 ]]; then
        printf '%s\n' "${rows[@]}" | jq -s .
    else
        ws_status_table "${rows[@]}"
    fi
    local busy
    busy="$(printf '%s\n' "${rows[@]}" | jq -r 'select(.state == "stale-busy") | .name' | paste -sd' ' -)"
    if [[ -n "$busy" ]]; then
        ws_msg "note: STALE-busy ($busy): the owner is gone but the workspace has work. A person decides: 'ws adopt <id>' to take it over, or 'ws release <id> --force' to drop it."
    fi
    if [[ $WS_LIVENESS_FALLBACK == 1 ]]; then
        ws_msg "note: $WS_SESSIONS_DIR missing or unreadable; liveness came from stored pids, so resumed sessions may show as stale"
    fi
}

# Shared flag parsing for acquire/adopt/release. Sets ARG_* globals.
ws_parse_flags() {
    ARG_ID="" ARG_LABEL="" ARG_FOR="" ARG_AT="" ARG_PREP=0 ARG_FORCE=0
    ARG_NO_PARK=0 ARG_ALL=0 ARG_STALE=0 ARG_LABEL_SET=0 ARG_FOR_SET=0
    local allowed=" $1 "; shift
    while [[ $# -gt 0 ]]; do
        local flag="$1"
        if [[ "$flag" == --* && "$allowed" != *" $flag "* ]]; then
            ws_die "unknown option $flag"
        fi
        case "$flag" in
            --label | --for)
                [[ $# -ge 2 ]] || ws_die "$flag needs a value"
                # One lease per status line: a newline would break the table.
                [[ "$2" != *$'\n'* ]] || ws_die "$flag can't contain a newline"
                if [[ "$flag" == --label ]]; then
                    ARG_LABEL="$2" ARG_LABEL_SET=1
                else
                    ARG_FOR="$2" ARG_FOR_SET=1
                fi
                shift
                ;;
            --at) [[ $# -ge 2 ]] || ws_die "--at needs a value"; ARG_AT="$2"; shift ;;
            --prep) ARG_PREP=1 ;;
            --force) ARG_FORCE=1 ;;
            --no-park) ARG_NO_PARK=1 ;;
            --all) ARG_ALL=1 ;;
            --stale) ARG_STALE=1 ;;
            -*) ws_die "unknown option $flag" ;;
            *)
                [[ -z "$ARG_ID" ]] || ws_die "unexpected argument '$flag'"
                ARG_ID="$flag"
                ;;
        esac
        shift
    done
}

# Write a lease for the caller, keeping the old lease's label, assignee and
# (for the caller's own lease) acquired_at unless flags override them.
ws_take() {
    local name="$1" old="$2" keep_time="$3" label assignee at=""
    label="$(jq -r '.label // ""' <<<"${old:-null}")"
    assignee="$(jq -r '.assignee // ""' <<<"${old:-null}")"
    [[ $ARG_LABEL_SET == 0 ]] || label="$ARG_LABEL"
    [[ $ARG_FOR_SET == 0 ]] || assignee="$ARG_FOR"
    [[ $keep_time == 0 ]] || at="$(jq -r '.acquired_at // ""' <<<"$old")"
    ws_lease_write "$name" "$(ws_identity)" "$label" "$assignee" "$at"
}

ws_describe_lease() {
    local lease="$1" holder label assignee
    holder="$(ws_holder_desc "$lease")"
    label="$(jq -r '.label // ""' <<<"$lease")"
    assignee="$(jq -r '.assignee // ""' <<<"$lease")"
    printf '%s' "$holder"
    [[ -z "$label" ]] || printf ', label "%s"' "$label"
    [[ -z "$assignee" ]] || printf ', for %s' "$assignee"
}

cmd_acquire() {
    ws_parse_flags "--label --for --at --prep" "$@"
    local name state lease="" fresh=1
    if [[ -n "$ARG_ID" ]]; then
        name="$(ws_require "$ARG_ID")"
        # default is the user's checkout; acquire never moves its @.
        [[ "$name" != default || -z "$ARG_AT" ]] || ws_die "--at doesn't apply to default; acquire never moves it"
    fi
    ws_lock
    if [[ -n "$ARG_ID" ]]; then
        ws_state "$name"
        state="$WS_STATE" lease="$WS_LEASE"
        case "$state" in
            free | stale-idle) lease="" ;;
            # A refresh (e.g. after `claude -r`). The workspace already holds
            # this session's work, so @ only moves if --at asks for it.
            held-self) fresh=0 ;;
            held) ws_die "$name is held by $(ws_describe_lease "$lease")" ;;
            stale-busy)
                ws_die "$name was held by $(ws_describe_lease "$lease"), which is gone, but the workspace has work in it. Ask the user before 'ws adopt $name' or 'ws release $name --force'."
                ;;
        esac
    else
        local cand
        for cand in $(ws_existing "${WS_POOL[@]}"); do
            ws_state "$cand"
            if [[ "$WS_STATE" == free || "$WS_STATE" == stale-idle ]]; then
                name="$cand"
                break
            fi
        done
        [[ -n "${name:-}" ]] || ws_die "no free workspace in ${WS_POOL[*]} (see 'ws status')"
    fi

    local dir
    dir="$(ws_path_of "$name")"
    # Nothing is ever built on parking_lot (D12): every parked workspace
    # shares that commit, so one edit there would leak into all of them.
    # A new ws1-5 lease therefore always starts a fresh revision. This all
    # happens under the lock: until `jj new` runs the workspace still looks
    # parked, and a racing acquire could take it if our lease read as stale.
    local move=0
    [[ "$name" == default || ($fresh == 0 && -z "$ARG_AT") ]] || move=1
    if [[ $move == 1 ]]; then
        ws_jj "$dir" workspace update-stale >&2 || ws_die "update-stale failed in $name"
        local dirty
        dirty="$(cd "$dir" && jj diff --no-pager --name-only -r "@ & $WS_PARKING_BOOKMARK" 2>/dev/null)" || dirty=""
        if [[ -n "$dirty" ]]; then
            ws_die "parking_lot has changes ($(paste -sd' ' - <<<"$dirty")), probably a stray edit in a parked workspace; not building on it and not taking $name. Ask the user to clean up parking_lot."
        fi
    fi
    if [[ $fresh == 1 ]]; then ws_take "$name" "" 0; else ws_take "$name" "$lease" 1; fi
    if [[ $move == 1 ]]; then
        local rev="${ARG_AT:-$WS_DEFAULT_REV}"
        ws_jj "$dir" new "$rev" >&2 || ws_die "'jj new $rev' failed in $name (lease kept)"
    fi
    # Released before --prep: pnpm and turbo's daemon would inherit the lock
    # fd and keep the pool locked long after this call ends.
    ws_unlock
    ws_msg "Acquired $name"
    if [[ $ARG_PREP == 1 ]]; then
        cmd_prep "$name" >&2 || ws_die "prep failed in $name (lease kept)"
    fi
    echo "$dir"
}

cmd_adopt() {
    ws_parse_flags "--label --for --force" "$@"
    [[ -n "$ARG_ID" ]] || ws_die "usage: ws adopt <id> [--label T] [--for NAME] [--force]"
    local name state lease
    ws_lock
    name="$(ws_require "$ARG_ID")"
    ws_state "$name"
    state="$WS_STATE" lease="$WS_LEASE"
    case "$state" in
        free) ws_take "$name" "" 0 ;;
        held-self) ws_take "$name" "$lease" 1 ;;
        stale-idle | stale-busy) ws_take "$name" "$lease" 0 ;;
        held)
            [[ $ARG_FORCE == 1 ]] || ws_die "$name is held by $(ws_describe_lease "$lease"), which is still running. Use --force only if the user says so."
            ws_take "$name" "$lease" 0
            ;;
    esac
    ws_unlock
    ws_msg "Adopted $name"
    ws_path_of "$name"
}

# Release one workspace. Caller holds the lock.
# Returns 0 released, 1 failed, 2 skipped (not allowed without --force).
ws_release_one() {
    local name="$1" state lease park=1
    [[ "$name" != default && $ARG_NO_PARK == 0 ]] || park=0
    ws_state "$name"
    state="$WS_STATE" lease="$WS_LEASE"
    case "$state" in
        held | stale-busy)
            if [[ $ARG_FORCE == 0 ]]; then
                if [[ "$state" == held ]]; then
                    ws_msg "Skipped $name: held by $(ws_describe_lease "$lease") (needs --force)"
                else
                    ws_msg "Skipped $name: held by $(ws_describe_lease "$lease"), now gone, but the workspace has work (needs --force)"
                fi
                return 2
            fi
            ;;
    esac
    if [[ $park == 1 ]]; then
        # Park before dropping the lease: if parking fails, @ is somewhere
        # unexpected and the workspace shouldn't look free.
        if ! ws_park "$name"; then
            ws_msg "Failed to park $name; lease kept"
            return 1
        fi
    fi
    if [[ "$state" == free ]]; then
        if [[ $park == 1 ]]; then ws_msg "$name parked (it had no lease)"; fi
    else
        ws_lease_remove "$name"
        if [[ $park == 1 ]]; then ws_msg "$name released and parked"; else ws_msg "$name released"; fi
    fi
    return 0
}

cmd_release() {
    ws_parse_flags "--no-park --force --all --stale" "$@"
    local modes=$((ARG_ALL + ARG_STALE)) name rc=0 r
    [[ -n "$ARG_ID" ]] && modes=$((modes + 1))
    [[ $modes == 1 ]] || ws_die "usage: ws release <id> [--no-park] [--force] | --all [--force] | --stale"
    ws_lock
    if [[ $ARG_STALE == 1 ]]; then
        local n=0
        for name in "${WS_ALL[@]}"; do
            [[ -f "$(ws_lease_file "$name")" ]] || continue
            ws_state "$name"
            if [[ "$WS_STATE" == stale-idle ]]; then
                ws_lease_remove "$name"
                ws_msg "Dropped stale lease on $name: $(ws_describe_lease "$WS_LEASE")"
                n=$((n + 1))
            fi
        done
        [[ $n -gt 0 ]] || ws_msg "No stale-idle leases"
    elif [[ $ARG_ALL == 1 ]]; then
        for name in $(ws_existing "${WS_ALL[@]}"); do
            # Only leased workspaces: an unleased one may have a human in it,
            # since humans aren't governed by the hook.
            [[ -f "$(ws_lease_file "$name")" ]] || continue
            r=0
            ws_release_one "$name" || r=$?
            [[ $r != 1 ]] || rc=1
        done
    else
        name="$(ws_require "$ARG_ID")"
        ws_release_one "$name" || rc=1
    fi
    return "$rc"
}

cmd_prep() {
    [[ $# -eq 1 ]] || ws_die "usage: ws prep <id>"
    local name
    name="$(ws_require "$1")"
    ws_unlock
    (cd "$(ws_path_of "$name")" && bash -c "$WS_PREP_CMD")
}

cmd_whoami() {
    ws_identity | jq .
}

# Provision the pool. Safe to re-run: every step checks before acting, and
# nothing existing is moved.
cmd_init() {
    local tool
    for tool in jq flock jj; do
        command -v "$tool" >/dev/null 2>&1 || ws_die "$tool is not installed; ws needs it"
    done
    [[ -d "$WS_DEFAULT_PATH/.jj" ]] || ws_die "$WS_DEFAULT_PATH is not a jj repo"
    local rc=0
    if ! (cd "$WS_DEFAULT_PATH" && jj bookmark list --no-pager "$WS_PARKING_BOOKMARK" 2>/dev/null) \
            | grep -q "^$WS_PARKING_BOOKMARK"; then
        ws_msg "Creating $WS_PARKING_BOOKMARK bookmark in $WS_DEFAULT_PATH..."
        # --no-edit leaves the default workspace's @ where it is.
        (cd "$WS_DEFAULT_PATH" && jj new main --no-edit -m "$WS_PARKING_DESC") >&2 \
            || ws_die "failed to create the $WS_PARKING_BOOKMARK commit"
        # subject() matches the first line without its trailing newline;
        # description(exact:) would never match a non-empty description.
        (cd "$WS_DEFAULT_PATH" && jj bookmark create "$WS_PARKING_BOOKMARK" \
            -r "subject(exact:\"$WS_PARKING_DESC\") & empty() & children(main)") >&2 \
            || ws_die "failed to create the $WS_PARKING_BOOKMARK bookmark"
    fi

    mkdir -p "$WS_PARENT" "$WS_LEASE_DIR"

    local registered name dir
    registered="$(ws_registered_workspaces)"
    for name in "${WS_POOL[@]}"; do
        dir="$(ws_path_of "$name")"
        if grep -qx -- "$name" <<<"$registered"; then
            if [[ -d "$dir" ]]; then
                ws_msg "jj workspace $name already exists, skipping."
            else
                # Recreating it would need `jj workspace forget` first, which
                # drops jj's record of its @; leave that call to a person.
                ws_msg "jj workspace $name is registered but $dir is missing; not recreating it."
                rc=1
            fi
            continue
        fi
        if [[ -e "$dir" ]]; then
            ws_msg "$dir exists but isn't a jj workspace; leaving it alone."
            rc=1
            continue
        fi
        ws_msg "Creating jj workspace $name at $dir..."
        if ! (cd "$WS_DEFAULT_PATH" && jj workspace add --name "$name" "$dir") >&2; then
            ws_msg "Failed to create workspace $name, continuing."
            rc=1
            continue
        fi
        # Edit the parking_lot commit itself (not a child of it), so a parked
        # workspace's @ is recognizably parking_lot.
        if ! ws_jj "$dir" edit "$WS_PARKING_BOOKMARK" >&2; then
            ws_msg "Failed to park $name on $WS_PARKING_BOOKMARK."
            rc=1
        fi
    done
    return "$rc"
}

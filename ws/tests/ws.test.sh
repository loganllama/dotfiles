#!/usr/bin/env bash
# Self-contained tests for bin/ws and bin/ws-hook. Builds a throwaway jj
# repo + pool in a temp dir, fakes Claude sessions with `sleep` processes,
# and never touches /workspaces or ~/.claude.
#
#   bash ws/tests/ws.test.sh
#
# The repo is a plain (non-git) jj repo from `jj debug init-simple`: the
# tests need nothing git-specific, and no git operation should happen.
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
WS="$HERE/../../bin/ws"
HOOK="$HERE/../../bin/ws-hook"

T="$(mktemp -d "${TMPDIR:-/tmp}/ws-test.XXXXXX")"
T="$(realpath "$T")"
export WS_DEFAULT_PATH="$T/obsidian"
export WS_PARENT="$T/obsidian-ws"
export WS_LEASE_DIR="$T/obsidian-ws/.leases"
export WS_SESSIONS_DIR="$T/sessions"
export WS_LOCK_TIMEOUT=20
export JJ_CONFIG="$T/jj.toml"
# Running inside Claude would otherwise make every call the real session.
unset CLAUDE_CODE_SESSION_ID CLAUDE_PID

# Refuse to run against anything that isn't our temp dir.
for v in WS_DEFAULT_PATH WS_PARENT WS_LEASE_DIR WS_SESSIONS_DIR JJ_CONFIG; do
    case "${!v}" in
        "$T"/*) ;;
        *) echo "refusing to run: $v=${!v} is outside $T" >&2; exit 1 ;;
    esac
done
case "$T" in
    /workspaces/* | "$HOME" | "$HOME"/.claude*)
        echo "refusing to run: $T is not a temp location" >&2; exit 1 ;;
esac

PIDS=()
cleanup() {
    local p
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
    rm -rf "$T"
}
trap cleanup EXIT

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
# check DESC CMD...: CMD must succeed.
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
# check_not DESC CMD...: CMD must fail.
check_not() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }
eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1: expected [$3], got [$2]"; fi; }

proc_start() {
    local s
    s="$(cat "/proc/$1/stat")"
    s="${s##*) }"
    local -a f
    read -r -a f <<<"$s"
    echo "${f[19]}"
}

write_record() {
    mkdir -p "$WS_SESSIONS_DIR"
    jq -cn --arg sid "$1" --argjson pid "$2" --arg ps "$3" --arg name "$4" \
        '{pid: $pid, sessionId: $sid, procStart: $ps, name: $name, cwd: "/x"}' \
        >"$WS_SESSIONS_DIR/$2.json"
}
# new_session NAME: a live fake Claude process plus its session record.
# Sets SID and PID.
new_session() {
    sleep 1000 &
    PID=$!
    PIDS+=("$PID")
    SID="sess-$1-$RANDOM"
    write_record "$SID" "$PID" "$(proc_start "$PID")" "$1"
}
kill_pid() { kill "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; }

# plant_lease WS SID PID: a lease as an owner would have left it, without
# running acquire (which never leaves ws1-5 parked). For leases on parked
# workspaces, the only way ws1-5 can be idle.
plant_lease() {
    mkdir -p "$WS_LEASE_DIR"
    jq -n --arg ws "$1" --arg sid "$2" --argjson pid "$3" --arg ps "$(proc_start "$3" 2>/dev/null || echo 0)" \
        '{workspace: $ws, owner: {kind: "claude", session_id: $sid, session_name: "planted",
          pid: $pid, proc_start: $ps}, label: "", assignee: "", acquired_at: "2026-01-01T00:00:00Z"}' \
        >"$WS_LEASE_DIR/$1.json"
}
parking_clean() { (cd "$WS_DEFAULT_PATH" && jj log --no-graph -r "parking_lot & empty() & description(exact:\"$PARK_DESC\n\")" -T '"y"'); }
PARK_DESC="DND: workspace parking lot"
as() { local sid="$1" pid="$2"; shift 2; CLAUDE_CODE_SESSION_ID="$sid" CLAUDE_PID="$pid" "$@"; }
human() { "$@"; }
lease_field() { jq -r "$2" "$WS_LEASE_DIR/$1.json"; }
state_of() { "$WS" status --json 2>/dev/null | jq -r --arg n "$1" '.[] | select(.name == $n) | .state'; }
at_change() { (cd "$1" && jj log --no-graph -r @ -T 'change_id' --ignore-working-copy); }
parking_change() { (cd "$WS_DEFAULT_PATH" && jj log --no-graph -r parking_lot -T 'change_id' --ignore-working-copy); }

# --- repo + init -------------------------------------------------------------
printf '[user]\nname = "ws test"\nemail = "ws@test"\n' >"$JJ_CONFIG"
jj debug init-simple "$WS_DEFAULT_PATH" >/dev/null 2>&1
(cd "$WS_DEFAULT_PATH" && echo hi >f && jj commit -m init && jj bookmark create main -r @-) >/dev/null 2>&1
default_before="$(at_change "$WS_DEFAULT_PATH")"

check "init provisions from scratch" "$WS" init
check ".leases created" test -d "$WS_LEASE_DIR"
pl="$(parking_change)"
check "parking_lot exists" test -n "$pl"
for n in 1 2 3 4 5; do
    eq "ws$n parked on parking_lot" "$(at_change "$WS_PARENT/ws$n")" "$pl"
done
eq "init leaves default's @ alone" "$(at_change "$WS_DEFAULT_PATH")" "$default_before"
check "init re-run is safe" "$WS" init
eq "re-run keeps parking_lot" "$(parking_change)" "$pl"
eq "re-run adds no workspaces" "$(cd "$WS_DEFAULT_PATH" && jj workspace list | wc -l | tr -d ' ')" 6
eq "fresh pool: ws1 free" "$(state_of ws1)" "free"

# --- moved commands ----------------------------------------------------------
eq "ws <id> prints path" "$("$WS" 3)" "$WS_PARENT/ws3"
eq "ws wsN form" "$("$WS" ws3)" "$WS_PARENT/ws3"
eq "ws default" "$("$WS" default)" "$WS_DEFAULT_PATH"
eq "ws <id> <cmd> runs there" "$(cd / && "$WS" 2 pwd)" "$WS_PARENT/ws2"
check_not "ws <id> <cmd> keeps exit status" "$WS" 2 false
check_not "unknown id fails" "$WS" 9
expected="$(for n in 1 2 3 4 5; do echo "=== ws$n ==="; echo "$WS_PARENT/ws$n"; done)"
eq "ws all matches old wsa output" "$("$WS" all pwd)" "$expected"

# --- acquire -----------------------------------------------------------------
new_session alice; A_SID=$SID A_PID=$PID
new_session bob; B_SID=$SID B_PID=$PID

eq "acquire free prints path" "$(as "$A_SID" "$A_PID" "$WS" acquire 2 --label t1 --for impl-a 2>/dev/null)" "$WS_PARENT/ws2"
eq "lease records session" "$(lease_field ws2 .owner.session_id)" "$A_SID"
eq "lease records session name" "$(lease_field ws2 .owner.session_name)" "alice"
eq "lease records proc_start" "$(lease_field ws2 .owner.proc_start)" "$(proc_start "$A_PID")"
eq "lease records assignee" "$(lease_field ws2 .assignee)" "impl-a"
fresh_change="$(at_change "$WS_PARENT/ws2")"
check "acquire without --at leaves parking_lot" test "$fresh_change" != "$pl"
eq "acquire without --at: @ is a new child of main" "$(cd "$WS_PARENT/ws2" && jj log --no-graph -r '@-' -T 'local_bookmarks.map(|b| b.name()).join(",")')" "main"
eq "acquire without --at: @ is empty" "$(cd "$WS_PARENT/ws2" && jj log --no-graph -r '@ & empty()' -T '"y"')" "y"
# An edit plus a snapshot in an acquired ws must not reach parking_lot.
echo work >"$WS_PARENT/ws2/work.txt"
(cd "$WS_PARENT/ws2" && jj status) >/dev/null 2>&1
eq "parking_lot stays empty after an edit in an acquired ws" "$(parking_clean)" "y"
fresh_change="$(at_change "$WS_PARENT/ws2")"
eq "status: held-self for owner" "$(as "$A_SID" "$A_PID" "$WS" status --json | jq -r '.[] | select(.name=="ws2") | .state')" "held-self"
eq "status: held for others" "$(as "$B_SID" "$B_PID" "$WS" status --json | jq -r '.[] | select(.name=="ws2") | .state')" "held"
t0="$(lease_field ws2 .acquired_at)"
sleep 1.1
check "acquire held-self succeeds" as "$A_SID" "$A_PID" "$WS" acquire ws2
eq "held-self keeps acquired_at" "$(lease_field ws2 .acquired_at)" "$t0"
eq "held-self keeps label" "$(lease_field ws2 .label)" "t1"
eq "held-self re-acquire without --at leaves @" "$(at_change "$WS_PARENT/ws2")" "$fresh_change"
check_not "newline in --label rejected" as "$A_SID" "$A_PID" "$WS" acquire ws2 --label $'a\nb'
check_not "newline in --for rejected" as "$A_SID" "$A_PID" "$WS" acquire ws2 --for $'a\nb'
eq "label unchanged after rejected newline" "$(lease_field ws2 .label)" "t1"
check_not "acquire held-other fails" as "$B_SID" "$B_PID" "$WS" acquire 2

eq "auto pick takes first free (ws1)" "$(as "$B_SID" "$B_PID" "$WS" acquire 2>/dev/null)" "$WS_PARENT/ws1"
for n in 3 4 5; do as "$B_SID" "$B_PID" "$WS" acquire "$n" >/dev/null 2>&1; done
check_not "auto pick fails when ws1-5 are taken" as "$B_SID" "$B_PID" "$WS" acquire
check "auto pick never took default" test ! -e "$WS_LEASE_DIR/default.json"
# A human in unleased ws5 must not be disturbed by release --all.
as "$B_SID" "$B_PID" "$WS" release 5 --no-park >/dev/null 2>&1
"$WS" 5 jj new main >/dev/null 2>&1
human_change="$(at_change "$WS_PARENT/ws5")"
as "$B_SID" "$B_PID" "$WS" release --all >/dev/null 2>&1 || true
eq "release --all leaves unleased workspaces alone" "$(at_change "$WS_PARENT/ws5")" "$human_change"
"$WS" 5 jj edit parking_lot >/dev/null 2>&1
eq "release --all parked own ws1" "$(at_change "$WS_PARENT/ws1")" "$pl"
check "release --all kept the other session's lease" test -e "$WS_LEASE_DIR/ws2.json"
check "release --all dropped own leases" test ! -e "$WS_LEASE_DIR/ws1.json"

# --- stale-idle / stale-busy / adopt ----------------------------------------
new_session carol; C_SID=$SID C_PID=$PID
plant_lease ws3 "$C_SID" "$C_PID"
kill_pid "$C_PID"
eq "dead owner + parked = stale-idle" "$(state_of ws3)" "stale-idle"
check "acquire reclaims stale-idle" as "$B_SID" "$B_PID" "$WS" acquire 3
eq "reclaimed lease is bob's" "$(lease_field ws3 .owner.session_id)" "$B_SID"
check "reclaim also starts a fresh revision" test "$(at_change "$WS_PARENT/ws3")" != "$pl"

new_session dan; DN_SID=$SID DN_PID=$PID
as "$DN_SID" "$DN_PID" "$WS" acquire 5 >/dev/null 2>&1
kill_pid "$DN_PID"
eq "dead owner of an acquired (unparked) ws = stale-busy" "$(state_of ws5)" "stale-busy"
as "$B_SID" "$B_PID" "$WS" release 5 --force >/dev/null 2>&1

new_session dave; D_SID=$SID D_PID=$PID
check "acquire --at moves @" as "$D_SID" "$D_PID" "$WS" acquire 4 --at main
busy_change="$(at_change "$WS_PARENT/ws4")"
check "--at left parking_lot" test "$busy_change" != "$pl"
eq "--at put @ on top of main" "$(cd "$WS_PARENT/ws4" && jj log --no-graph -r '@-' -T 'local_bookmarks.map(|b| b.name()).join(",")')" "main"
kill_pid "$D_PID"
eq "dead owner + work = stale-busy" "$(state_of ws4)" "stale-busy"
check_not "acquire refuses stale-busy" as "$B_SID" "$B_PID" "$WS" acquire 4
check_not "release refuses stale-busy without --force" as "$B_SID" "$B_PID" "$WS" release 4
check "adopt takes stale-busy" as "$B_SID" "$B_PID" "$WS" adopt 4 --for impl-b
eq "adopt doesn't move @" "$(at_change "$WS_PARENT/ws4")" "$busy_change"
eq "adopt records new owner" "$(lease_field ws4 .owner.session_id)" "$B_SID"
eq "adopt records assignee" "$(lease_field ws4 .assignee)" "impl-b"
check_not "adopt refuses a live holder" as "$B_SID" "$B_PID" "$WS" adopt 2
check "held-self re-acquire with --at" as "$B_SID" "$B_PID" "$WS" acquire 4 --at main
check "held-self --at ran jj new" test "$(at_change "$WS_PARENT/ws4")" != "$busy_change"

# A stray edit in a parked, unleased workspace (a human, or `ws 1 ...`)
# lands in parking_lot itself. A leftover lease on a parked workspace must
# then read as busy, not idle.
new_session ivy; I_SID=$SID I_PID=$PID
plant_lease ws1 "$I_SID" "$I_PID"
kill_pid "$I_PID"
eq "planted lease on clean parked ws = stale-idle" "$(state_of ws1)" "stale-idle"
"$WS" 1 sh -c 'echo dirty >dirty.txt'
eq "parked but edited = stale-busy" "$(state_of ws1)" "stale-busy"
check "release --force releases stale-busy" as "$B_SID" "$B_PID" "$WS" release 1 --force
eq "forced release parked ws1" "$(at_change "$WS_PARENT/ws1")" "$pl"
# Undo the edit and bring the other parked workspaces up to date, as a
# person cleaning up would.
rm "$WS_PARENT/ws1/dirty.txt"
(cd "$WS_PARENT/ws1" && jj status) >/dev/null 2>&1
"$WS" all jj workspace update-stale >/dev/null 2>&1
eq "parking_lot clean again" "$(parking_clean)" "y"

# --- liveness ----------------------------------------------------------------
new_session erin; E_SID=$SID E_PID=$PID
as "$E_SID" "$E_PID" "$WS" acquire 5 >/dev/null 2>&1
kill_pid "$E_PID"
# `claude -r`: same session id, new process, new record.
sleep 1000 &
E2_PID=$!
PIDS+=("$E2_PID")
write_record "$E_SID" "$E2_PID" "$(proc_start "$E2_PID")" erin
eq "resume detected through sessions dir" "$(state_of ws5)" "held"
check_not "resumed lease still blocks others" as "$B_SID" "$B_PID" "$WS" acquire 5
check "resumed session re-acquires" as "$E_SID" "$E2_PID" "$WS" acquire 5
eq "re-acquire refreshes stored pid" "$(lease_field ws5 .owner.pid)" "$E2_PID"

# Recycled pid: a running process, but its start time doesn't match.
new_session frank; F_SID=$SID F_PID=$PID
plant_lease ws1 "$F_SID" "$F_PID"
write_record "$F_SID" "$F_PID" "1" frank
eq "recycled pid counts as dead" "$(state_of ws1)" "stale-idle"

# No sessions dir: fall back to the pid stored in the lease.
fb="$(WS_SESSIONS_DIR="$T/nope" "$WS" status --json 2>"$T/fb.err" | jq -r '.[] | select(.name=="ws5") | .state')"
eq "fallback: stored pid still live" "$fb" "held"
check "fallback is reported" grep -q "stored pids" "$T/fb.err"

check "release --stale runs" as "$B_SID" "$B_PID" "$WS" release --stale
check "stale-idle ws1 lease dropped" test ! -e "$WS_LEASE_DIR/ws1.json"
check "live ws5 lease kept by --stale" test -e "$WS_LEASE_DIR/ws5.json"

# --- release -----------------------------------------------------------------
check "release parks ws" as "$B_SID" "$B_PID" "$WS" release 4
eq "ws4 back on parking_lot" "$(at_change "$WS_PARENT/ws4")" "$pl"
check "ws4 lease gone" test ! -e "$WS_LEASE_DIR/ws4.json"
check "release --no-park" as "$B_SID" "$B_PID" "$WS" release 3 --no-park
check "ws3 lease gone" test ! -e "$WS_LEASE_DIR/ws3.json"

# default is idle when @ is empty with no description.
new_session jack; J_SID=$SID J_PID=$PID
as "$J_SID" "$J_PID" "$WS" acquire default >/dev/null 2>&1
kill_pid "$J_PID"
eq "default: dead owner + clean @ = stale-idle" "$(state_of default)" "stale-idle"
eq "status: ws description column" "$("$WS" status --json | jq -r '.[] | select(.name=="ws4") | .description')" "DND: workspace parking lot"
eq "status: default empty description" "$("$WS" status --json | jq -r '.[] | select(.name=="default") | .description')" ""
eq "status: read ok" "$("$WS" status --json | jq -r '.[] | select(.name=="default") | .working_copy')" "ok"
as "$B_SID" "$B_PID" "$WS" release default --force >/dev/null 2>&1
def_before="$(at_change "$WS_DEFAULT_PATH")"
check_not "acquire default --at is rejected" as "$B_SID" "$B_PID" "$WS" acquire default --at main
check "rejected --at took no lease" test ! -e "$WS_LEASE_DIR/default.json"
eq "rejected --at left default's @" "$(at_change "$WS_DEFAULT_PATH")" "$def_before"
check "acquire default by name" as "$B_SID" "$B_PID" "$WS" acquire default
eq "acquire default doesn't move @" "$(at_change "$WS_DEFAULT_PATH")" "$def_before"
(cd "$WS_DEFAULT_PATH" && jj describe -m "work in progress") >/dev/null 2>&1
def_change="$(at_change "$WS_DEFAULT_PATH")"
check "release default" as "$B_SID" "$B_PID" "$WS" release default
eq "release default leaves @" "$(at_change "$WS_DEFAULT_PATH")" "$def_change"
new_session kim; K_SID=$SID K_PID=$PID
as "$K_SID" "$K_PID" "$WS" acquire default >/dev/null 2>&1
kill_pid "$K_PID"
eq "default: dead owner + described @ = stale-busy" "$(state_of default)" "stale-busy"
as "$B_SID" "$B_PID" "$WS" release default --force >/dev/null 2>&1
check "default lease gone" test ! -e "$WS_LEASE_DIR/default.json"

check_not "human release refuses live Claude lease" human "$WS" release 2
check "lease survived human release" test -e "$WS_LEASE_DIR/ws2.json"
check "human release --force works" human "$WS" release 2 --force
check "human can acquire" human "$WS" acquire 2
eq "human owner kind" "$(lease_field ws2 .owner.kind)" "human"
check_not "Claude can't release a human lease" as "$B_SID" "$B_PID" "$WS" release 2
check "human releases own lease" human "$WS" release 2

# --- concurrency -------------------------------------------------------------
as "$E_SID" "$E2_PID" "$WS" release 5 >/dev/null 2>&1
new_session gina; G_SID=$SID G_PID=$PID
new_session hank; H_SID=$SID H_PID=$PID
as "$G_SID" "$G_PID" "$WS" acquire >"$T/g.out" 2>/dev/null &
g=$!
as "$H_SID" "$H_PID" "$WS" acquire >"$T/h.out" 2>/dev/null &
h=$!
wait "$g" || true
wait "$h" || true
check "concurrent auto-picks both got one" test -s "$T/g.out" -a -s "$T/h.out"
check "concurrent auto-picks differ" test "$(cat "$T/g.out")" != "$(cat "$T/h.out")"
# Each pick runs `jj new` after unlocking, so both may hit jj at once.
for f in g h; do
    d="$(cat "$T/$f.out")"
    eq "concurrent pick $f: @ is a new child of main" "$(cd "$d" && jj log --no-graph -r '@-' -T 'local_bookmarks.map(|b| b.name()).join(",")' 2>/dev/null)" "main"
done
eq "concurrent picks: no divergent changes" "$(cd "$WS_DEFAULT_PATH" && jj log --no-graph -r 'divergent()' -T '"x"' 2>/dev/null)" ""
eq "concurrent picks: parking_lot still clean" "$(parking_clean)" "y"

check "status prints a table" "$WS" status
check "whoami (human)" sh -c "'$WS' whoami | jq -e '.kind == \"human\"'"

# A registered workspace whose directory is gone is reported, not recreated.
mv "$WS_PARENT/ws5" "$T/ws5.moved"
check_not "init fails on a registered ws with no dir" "$WS" init
check "init reports the missing dir" sh -c "'$WS' init 2>&1 | grep -q 'ws5 is registered but'"
check "init didn't recreate it" test ! -e "$WS_PARENT/ws5"
mv "$T/ws5.moved" "$WS_PARENT/ws5"
check "init ok again once it's back" "$WS" init

# --- hook --------------------------------------------------------------------
# hook SESSION TOOL CWD TOOL_INPUT_JSON: the hook's stdout.
hook() {
    jq -cn --arg s "$1" --arg t "$2" --arg c "$3" --argjson i "$4" \
        '{session_id: $s, tool_name: $t, cwd: $c, hook_event_name: "PreToolUse", tool_input: $i}' \
        | "$HOOK"
}
decision() { jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"${1:-null}"; }
context() { jq -r '.hookSpecificOutput.additionalContext // ""' <<<"${1:-null}"; }
fp() { jq -cn --arg p "$1" '{file_path: $p}'; }
bc() { jq -cn --arg c "$1" '{command: $c}'; }

G_DIR="$(cat "$T/g.out")"
H_DIR="$(cat "$T/h.out")"
FREE_DIR="$WS_PARENT/ws4"

eq "hook: edit held-self passes" "$(hook "$G_SID" Edit / "$(fp "$G_DIR/a.ts")")" ""
out="$(hook "$G_SID" Edit / "$(fp "$H_DIR/a.ts")")"
eq "hook: edit held-other denied" "$(decision "$out")" "deny"
check "hook: deny names holder" grep -q hank <<<"$out"
out="$(hook "$G_SID" Write / "$(fp "$FREE_DIR/x")")"
eq "hook: write unleased ws denied" "$(decision "$out")" "deny"
check "hook: deny says ws acquire" grep -q "ws acquire ws4" <<<"$out"
out="$(hook "$G_SID" NotebookEdit / "$(jq -cn --arg p "$FREE_DIR/n.ipynb" '{notebook_path: $p}')")"
eq "hook: notebook_path is read" "$(decision "$out")" "deny"
out="$(hook "$G_SID" Edit / "$(fp "$WS_DEFAULT_PATH/src/x.ts")")"
eq "hook: edit unleased default denied" "$(decision "$out")" "deny"
eq "hook: *.local.md exempt in default" "$(hook "$G_SID" Write / "$(fp "$WS_DEFAULT_PATH/foo_plan.local.md")")" ""
eq "hook: *.local.md exempt in ws" "$(hook "$G_SID" Edit / "$(fp "$H_DIR/notes.local.md")")" ""
eq "hook: path outside the pool ignored" "$(hook "$G_SID" Edit / "$(fp "$T/elsewhere/x")")" ""
mkdir -p "$T/dotfiles"
echo x >"$T/dotfiles/linked.json"
ln -s "$T/dotfiles/linked.json" "$WS_DEFAULT_PATH/linked.json"
eq "hook: link out of default resolves out" "$(hook "$G_SID" Edit / "$(fp "$WS_DEFAULT_PATH/linked.json")")" ""
out="$(hook "$G_SID" Edit / "$(fp "$G_DIR/../ws4/sneaky")")"
eq "hook: .. in path resolved" "$(decision "$out")" "deny"

out="$(hook "$G_SID" Bash "$FREE_DIR" "$(bc 'jj new main')")"
eq "hook: bash in unleased ws: no decision" "$(decision "$out")" "none"
check "hook: bash in unleased ws warns" test -n "$(context "$out")"
eq "hook: bash held-self silent" "$(hook "$G_SID" Bash "$G_DIR" "$(bc 'jj edit foo')")" ""
eq "hook: bash ls in default silent" "$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc 'ls -la')")" ""
eq "hook: jj log in default silent" "$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc 'jj log -r @')")" ""
eq "hook: jj bookmark list silent" "$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc 'jj bookmark list')")" ""
out="$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc 'EDITOR=true jj squash --into @-')")"
check "hook: jj squash in default warns" test -n "$(context "$out")"
out="$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc 'jj workspace update-stale')")"
check "hook: update-stale in default warns" test -n "$(context "$out")"
out="$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc "cd $H_DIR && jj edit x")")"
check "hook: cd prefix targets that ws, names holder" grep -q hank <<<"$(context "$out")"
out="$(hook "$G_SID" Bash "$G_DIR" "$(bc "cd $WS_DEFAULT_PATH && jj new")")"
check "hook: cd into default + jj new warns" test -n "$(context "$out")"
out="$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc 'ws 4 jj log')")"
check "hook: ws <id> prefix targets that ws" grep -q ws4 <<<"$(context "$out")"
out="$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc "ls $FREE_DIR/src")")"
check "hook: ws path literal counts" grep -q ws4 <<<"$(context "$out")"
eq "hook: ws acquire from default silent" "$(hook "$G_SID" Bash "$WS_DEFAULT_PATH" "$(bc 'ws acquire 4 --label x')")" ""

check "hook: bad JSON fails open (exit 0)" sh -c "echo 'not json' | '$HOOK' >'$T/bad.out' 2>/dev/null"
eq "hook: bad JSON prints nothing" "$(cat "$T/bad.out")" ""
check "hook: other tools pass" sh -c "echo '{\"session_id\":\"x\",\"tool_name\":\"Read\",\"tool_input\":{}}' | '$HOOK'"
check "hook: a denial still exits 0" sh -c "jq -cn --arg p '$FREE_DIR/x' '{session_id:\"x\",tool_name:\"Edit\",cwd:\"/\",tool_input:{file_path:\$p}}' | '$HOOK' >/dev/null"

# --- acquire guards ----------------------------------------------------------
# A stray edit in a parked, unleased workspace must stop acquire from
# building on parking_lot, and acquire must not keep the lease.
as "$G_SID" "$G_PID" "$WS" release --all >/dev/null 2>&1 || true
as "$H_SID" "$H_PID" "$WS" release --all >/dev/null 2>&1 || true
echo stray >"$WS_PARENT/ws4/stray.txt"
check_not "acquire refuses a dirty parking_lot" as "$B_SID" "$B_PID" "$WS" acquire 4
check "refusal names the file" sh -c "CLAUDE_CODE_SESSION_ID='$B_SID' CLAUDE_PID='$B_PID' '$WS' acquire 4 2>&1 | grep -q stray.txt"
check "refusal took no lease" test ! -e "$WS_LEASE_DIR/ws4.json"
eq "refusal left ws4 on parking_lot" "$(at_change "$WS_PARENT/ws4")" "$pl"
rm "$WS_PARENT/ws4/stray.txt"
(cd "$WS_PARENT/ws4" && jj status) >/dev/null 2>&1
"$WS" all jj workspace update-stale >/dev/null 2>&1
eq "parking_lot clean after the stray test" "$(parking_clean)" "y"

# The lock covers `jj new`: while one acquire is still moving its workspace
# off parking_lot, a second must wait, even if the first owner reads as dead
# (no session record, no CLAUDE_PID). A slow jj widens the window.
mkdir -p "$T/slowbin"
real_jj="$(command -v jj)"
# shellcheck disable=SC2016 # $1/$@ belong to the generated script
printf '#!/bin/sh\n[ "$1" = new ] && sleep 2\nexec "%s" "$@"\n' "$real_jj" >"$T/slowbin/jj"
chmod +x "$T/slowbin/jj"
PATH="$T/slowbin:$PATH" CLAUDE_CODE_SESSION_ID=ghost-x "$WS" acquire 1 >"$T/x.out" 2>/dev/null &
x=$!
sleep 0.7
CLAUDE_CODE_SESSION_ID=ghost-y "$WS" acquire >"$T/y.out" 2>/dev/null || true
wait "$x" || true
eq "slow acquire got ws1" "$(cat "$T/x.out")" "$WS_PARENT/ws1"
check "racing acquire didn't also get ws1" test "$(cat "$T/y.out")" != "$WS_PARENT/ws1"
eq "ws1 lease is the first acquirer's" "$(lease_field ws1 .owner.session_id)" "ghost-x"
human "$WS" release 1 --force >/dev/null 2>&1
[[ ! -s "$T/y.out" ]] || human "$WS" release "$(basename "$(cat "$T/y.out")")" --force >/dev/null 2>&1

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

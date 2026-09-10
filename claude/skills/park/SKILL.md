---
name: park
description: Park a Claude Code session across a break so resuming it is cheap - measures context size and cache TTL, then holds the context warm with keep-alive pings, or writes a handoff doc and aims a /compact. Use when stepping away (lunch, meeting, end of day), when asked to park/pause/hold a session, or before a gap long enough for the prompt cache to expire.
---

# Park

Stepping away wastes money two ways: a cold cache re-read on resume (full context at
write price), or a needless `/compact` that pays a summary to recover nothing. Which
move is right depends on the context size and how long the gap is. Measure, don't guess.

## Step 1 - measure

```bash
python3 ~/.claude/skills/park/scripts/park-state.py --mode {auto|lunch|eod|keepalive} [--pings N]
```

Map the user's words to a mode: lunch/coffee/meeting/short errand -> `lunch`; end of
day/tomorrow/overnight/weekend -> `eod`; unclear -> `auto`. Follow the `RECOMMEND` line.

## Step 2 - act on the verdict

### HOLD - context is below break-even

Report the numbers in one line and do nothing else. Compacting here costs more than the
cold read it avoids. If the work is actually finished, say that `/clear` or closing the
session is free and strictly better than compacting.

### PING - hold the context warm

Each turn that reads the cached prefix refreshes its timer at read price, so a cheap turn
just under the TTL keeps the whole context alive. Schedule one:

```
ScheduleWakeup({
  delaySeconds: 2700,                      // 45m; must stay under the TTL
  noop: true,
  prompt: "/park keepalive <pings+1>",
  reason: "holding <N>K context warm; ping is $X/h vs $Y to compact",
})
```

Use `delaySeconds: 240` when the measured TTL is 5m rather than 60m.

If `ScheduleWakeup` is unavailable or rejected (it is documented for `/loop` dynamic
mode), fall back to `/loop 45m /park keepalive` - same cadence, same cap logic.

On a `keepalive` turn: run Step 1 with `--mode keepalive --pings N`, then either
reschedule (verdict `PING`) or stop the loop and run the EOD path (verdict `EOD` - the
cap was reached). Keep these turns minimal - one line of output, no file reads, no other
tools. That is the whole point of the turn.

**Stop the loop** with `ScheduleWakeup({stop: true})` as soon as any of these is true:

- A real user message arrives (they are back) - stop, then just answer them.
- The verdict comes back `EOD` - the ping cap is spent; pinging is now the expensive option.
- The user says stop, park is over, or asks to compact or clear.

Never leave a ping loop running unattended past the cap. Beyond it the pings cost more
than the compaction they were avoiding, which inverts the reason for doing this at all.

### EOD - hand off, then compact

1. Gather state cheaply - `jj log -r 'ancestors(@, 4)' --no-graph`, `jj diff --stat`,
   and the workspace assignments if agents are running.
2. Write `<topic>_handoff.local.md` in the repo root (`*.local.md` is gitignored):
   current goal, state (revisions, workspaces, what is verified vs not), next concrete
   step, open questions. Write what a fresh session needs to resume - not a transcript.
3. Print a `/compact` line for the user to paste, with focus instructions naming the
   specifics worth keeping. A skill cannot press `/compact`; the user runs it.

```
/compact Keep: <the specifics from the handoff doc>. Drop: <resolved detours, tool output>.
```

If the work is finished rather than paused, skip the compact line - closing the session
costs nothing and loses nothing that the handoff doc did not already capture.

### ASK - gap length unknown

Give the crossover from the measurement in one sentence ("ping if you are back within
Nh, otherwise handoff and compact") and ask which it is. Do not schedule or write
anything until they answer.

## Notes

- The prefix floor is measured from the session's first turn, so it slightly overstates
  the true floor (it includes the first user message). It errs toward not compacting.
- `ScheduleWakeup`'s own guidance discourages cache-warming wakeups as waste. That holds
  at small context; this skill only pings once the measurement shows it pays, and caps
  the loop so it cannot run past that point.
- Cache entries can be evicted early under load, so a hit is never guaranteed - the ping
  path is a strong bet, not a promise.

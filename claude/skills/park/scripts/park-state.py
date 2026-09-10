#!/usr/bin/env python3
"""Measure the current session's context and price the parking options.

Reads the newest transcript for the CWD's project and reports what it costs to
hold the context warm vs. compact it vs. let the cache go cold.
"""

import argparse
import datetime as dt
import json
import os
import pathlib
import sys

# $/token, first-party Claude API. read is 0.1x input except Fable (0.025x).
PRICES = {
    "opus": (5e-6, 25e-6, 0.1),
    "sonnet": (2e-6, 10e-6, 0.1),
    "haiku": (1e-6, 5e-6, 0.1),
    "fable": (10e-6, 50e-6, 0.025),
    "mythos": (10e-6, 50e-6, 0.1),
}
SUMMARY_OUT = 5000  # tokens a /compact summary typically emits
PING_OUT = 800      # tokens a keep-alive turn emits
PING_CAP_HOURS = 4  # never ping longer than this unattended


def price_for(model):
    for key, vals in PRICES.items():
        if key in (model or "opus").lower():
            return vals
    return PRICES["opus"]


def transcript_for(cwd):
    """Newest transcript for this project.

    CLAUDE_PROJECT_DIR is not always set and the shell CWD drifts between tool
    calls, so try the CWD's slug, then each parent's, then fall back to the
    newest transcript anywhere. The live session is written on every turn, so
    newest-mtime reliably identifies it.
    """
    root = pathlib.Path.home() / ".claude" / "projects"
    candidates = []
    for base in [pathlib.Path(cwd)] + list(pathlib.Path(cwd).parents):
        d = root / str(base).replace("/", "-")
        if d.is_dir():
            candidates = list(d.glob("*.jsonl"))
            if candidates:
                break
    if not candidates:
        candidates = list(root.glob("*/*.jsonl"))
    if not candidates:
        sys.exit(f"no transcript found under {root}")
    return max(candidates, key=lambda p: p.stat().st_mtime)


def turns(path):
    """Main-thread assistant turns that carry usage, in order."""
    out = []
    with open(path) as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("isSidechain"):
                continue
            usage = (d.get("message") or {}).get("usage")
            if usage:
                out.append(d)
    return out


def prompt_size(usage):
    return (
        usage.get("input_tokens", 0)
        + usage.get("cache_creation_input_tokens", 0)
        + usage.get("cache_read_input_tokens", 0)
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="auto",
                    choices=["auto", "lunch", "eod", "keepalive"])
    ap.add_argument("--pings", type=int, default=0,
                    help="keep-alive turns already spent this park")
    args = ap.parse_args()

    path = transcript_for(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    ts = turns(path)
    if not ts:
        sys.exit("transcript has no assistant turns with usage yet")

    last, first = ts[-1], ts[0]
    usage = last["message"]["usage"]
    model = last["message"].get("model", "opus")
    inp, out, read_mult = price_for(model)
    read = inp * read_mult

    ttl_1h = bool(usage.get("cache_creation", {}).get("ephemeral_1h_input_tokens"))
    ttl_min = 60 if ttl_1h else 5
    write = inp * (2.0 if ttl_1h else 1.25)

    C = prompt_size(usage)
    floor = prompt_size(first["message"]["usage"])   # ~system+tools+CLAUDE.md
    post = floor + SUMMARY_OUT                        # prefix after compaction

    elapsed = None
    if last.get("timestamp"):
        then = dt.datetime.fromisoformat(last["timestamp"].replace("Z", "+00:00"))
        elapsed = (dt.datetime.now(dt.timezone.utc) - then).total_seconds() / 60

    cold = C * write                       # resume without compacting
    compact = C * read + SUMMARY_OUT * out + post * write
    ping_hr = C * read + PING_OUT * out
    break_even = (SUMMARY_OUT * out + post * write) / (write - read)
    crossover = compact / ping_hr if ping_hr else 0
    cap = min(crossover, PING_CAP_HOURS)

    if C < break_even:
        rec = "HOLD"
        why = f"context {C:,} is below the {break_even:,.0f} break-even; nothing to recover above the {floor:,} floor"
    elif args.mode == "eod":
        rec = "EOD"
        why = f"gap exceeds the {crossover:.1f}h ping/compact crossover"
    elif args.mode in ("lunch", "keepalive"):
        if args.pings >= cap:
            rec = "EOD"
            why = f"spent {args.pings} pings, at the {cap:.1f}h cap; degrade to handoff+compact"
        else:
            rec = "PING"
            why = f"pinging is cheaper than compacting for gaps under {crossover:.1f}h"
    else:
        rec = "ASK"
        why = f"ping if back within {crossover:.1f}h, else handoff+compact"

    print(f"model         {model}   ttl {ttl_min}m")
    print(f"context       {C:,} tok   (floor ~{floor:,}, post-compact ~{post:,})")
    if elapsed is not None:
        print(f"cache         {elapsed:.0f}m since last request, ~{ttl_min - elapsed:.0f}m left")
    print(f"cold resume   ${cold:.2f}")
    print(f"compact now   ${compact:.2f}")
    print(f"keep-alive    ${ping_hr:.2f}/h   cap {cap:.1f}h ({args.pings} spent)")
    print(f"break-even    {break_even:,.0f} tok")
    print(f"RECOMMEND     {rec}  -- {why}")


if __name__ == "__main__":
    main()

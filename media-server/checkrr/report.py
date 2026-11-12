#!/usr/bin/env python3
"""Post a Discord summary after each checkrr run.

checkrr runs report-only (`process: false`), and in that mode it records bad
files in its database without sending any notification. This sidecar polls the
checkrr API. When a new finished run shows up in /api/stats/historical, it posts
one message listing the files flagged during that run. A clean run gets a short
"all clear" post, so a silent week means something is wrong.

State (the last reported run) lives in STATE_FILE, so restarts don't repost.
On first start it records the latest run without posting the backlog.

Preview the message for an existing run without posting or touching state:
  docker compose run --rm checkrr-report --dry-run --run 2026-10-18T01:21:35Z
"""
import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.request

ENV = os.environ.get
CHECKRR_URL = ENV("CHECKRR_URL", "http://checkrr:8585").rstrip("/")
CHECKRR_UI = ENV("CHECKRR_UI_URL", "")
STATE_FILE = ENV("STATE_FILE", "/state/last-run.json")
POLL_SECONDS = int(ENV("POLL_SECONDS", "600"))
MAX_LISTED = int(ENV("MAX_LISTED", "20"))
# Tried in order; the first Discord accepts (GET -> 200) is used, as in stream-watchdog.
WEBHOOK_ENV_VARS = ("CHECKRR_DISCORD_WEBHOOK_URL", "GATUS_DISCORD_WEBHOOK_URL", "DISCORD_WEBHOOK_URL")
MENTION = ENV("CHECKRR_DISCORD_MENTION", "")
UA = {"User-Agent": "homelab-checkrr-report"}


def log(msg):
    print(f"{dt.datetime.now(dt.timezone.utc):%Y-%m-%dT%H:%M:%SZ} {msg}", flush=True)


def get_json(path):
    with urllib.request.urlopen(urllib.request.Request(CHECKRR_URL + path, headers=UA), timeout=30) as r:
        return json.load(r)


def parse_ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def pick_webhook():
    for name in WEBHOOK_ENV_VARS:
        url = (ENV(name) or "").strip()
        if not url:
            continue
        try:
            urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=10).read()
            log(f"Discord webhook: using {name}")
            return url
        except urllib.error.HTTPError as e:
            log(f"WARN Discord webhook {name} rejected ({e.code}); trying the next one")
        except Exception as e:  # noqa: BLE001 - network hiccup: use it rather than nothing
            log(f"WARN could not verify Discord webhook {name} ({e}); using it anyway")
            return url
    return ""


def post(webhook, payload):
    body = json.dumps(payload).encode()
    for _ in range(3):
        try:
            req = urllib.request.Request(webhook, data=body, headers={"Content-Type": "application/json", **UA})
            urllib.request.urlopen(req, timeout=15).read()
            return True
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(float(e.headers.get("Retry-After", "2")))
                continue
            log(f"WARN Discord post failed: {e}")
            return False
        except Exception as e:  # noqa: BLE001
            log(f"WARN Discord post failed: {e}")
            time.sleep(5)
    return False


def short_path(path):
    """'/data/media/tv/Show (2020)/Season 1/Show - S01E02 - Title [..].mkv' -> 'Show - S01E02 - Title [..].mkv'"""
    return path.rsplit("/", 1)[-1]


def build_message(run, prev_ts, bad):
    run_ts = parse_ts(run["Timestamp"])
    stats = run["Data"]
    flagged = sorted(
        ((p, d) for p, d in bad.items() if prev_ts < d["date"] <= run_ts.timestamp() + 60),
        key=lambda x: x[0],
    )
    minutes = stats.get("timeDiff", 0) / 6e10  # nanoseconds
    fields = [
        {"name": "Files checked", "value": str(stats.get("filesChecked", 0)), "inline": True},
        {"name": "New/changed (decoded)", "value": str(stats.get("videoFiles", 0)), "inline": True},
        {"name": "Run time", "value": f"{minutes:.0f} min", "inline": True},
    ]
    if flagged:
        lines = [f"• `{short_path(p)[:110]}`\n  {d.get('reason', '')[:150]}" for p, d in flagged[:MAX_LISTED]]
        if len(flagged) > MAX_LISTED:
            lines.append(f"…and {len(flagged) - MAX_LISTED} more")
        desc = ("Report-only: nothing was deleted. Check these in Plex before replacing anything; "
                "decoder warnings are often harmless.\n\n" + "\n".join(lines))
        title, color = f"checkrr: {len(flagged)} file(s) flagged", 0xE67E22
    else:
        desc = "No new problems found."
        title, color = "checkrr: weekly scan clean", 0x2ECC71
    if CHECKRR_UI:
        desc += f"\n\n[Open checkrr]({CHECKRR_UI})"
    return {
        "username": "checkrr",
        "content": (MENTION or None) if flagged else None,
        "embeds": [{"title": title, "description": desc[:4000], "color": color,
                    "fields": fields, "timestamp": run_ts.isoformat()}],
    }, len(flagged)


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f).get("last_run")
    except (OSError, ValueError):
        return None


def save_state(ts):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"last_run": ts}, f)
    os.replace(tmp, STATE_FILE)


def finished_runs():
    """Completed runs, oldest first. The history also holds a 'current-stats' entry; skip it."""
    runs = []
    for r in get_json("/api/stats/historical"):
        try:
            parse_ts(r.get("Timestamp") or "")
        except ValueError:
            continue
        runs.append(r)
    return sorted(runs, key=lambda r: parse_ts(r["Timestamp"]))


def bad_files():
    return {b["Path"]: b["Data"] for b in get_json("/api/files/bad")}


def previous_ts(runs, run):
    """Timestamp (epoch) of the run before `run`, so its window covers the whole run."""
    earlier = [r for r in runs if parse_ts(r["Timestamp"]) < parse_ts(run["Timestamp"])]
    return parse_ts(earlier[-1]["Timestamp"]).timestamp() if earlier else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print the message instead of posting")
    ap.add_argument("--run", help="report this historical run timestamp (with --dry-run: preview only)")
    args = ap.parse_args()

    if args.run:
        runs = finished_runs()
        run = next((r for r in runs if r["Timestamp"].startswith(args.run.rstrip("Z"))), None)
        if not run:
            sys.exit(f"no run with timestamp {args.run}")
        msg, n = build_message(run, previous_ts(runs, run), bad_files())
        if args.dry_run:
            print(json.dumps(msg, indent=2, ensure_ascii=False))
            return
        webhook = pick_webhook()
        sys.exit(0 if webhook and post(webhook, msg) else 1)

    webhook = "" if args.dry_run else pick_webhook()
    if not webhook and not args.dry_run:
        log(f"WARN no working Discord webhook in {', '.join(WEBHOOK_ENV_VARS)}; reports only go to stdout")
    log(f"watching {CHECKRR_URL} every {POLL_SECONDS}s, state in {STATE_FILE}")

    while True:
        try:
            runs = finished_runs()
            last = load_state()
            if runs and last is None:
                save_state(runs[-1]["Timestamp"])
                log(f"first start: baseline set to run {runs[-1]['Timestamp']}, backlog not posted")
            elif runs:
                for run in [r for r in runs if parse_ts(r["Timestamp"]) > parse_ts(last)]:
                    msg, n = build_message(run, previous_ts(runs, run), bad_files())
                    log(f"run {run['Timestamp']}: {n} flagged, {run['Data'].get('filesChecked')} checked")
                    if args.dry_run or not webhook:
                        print(json.dumps(msg, ensure_ascii=False), flush=True)
                    elif not post(webhook, msg):
                        break  # retry this run next poll
                    save_state(run["Timestamp"])
        except Exception as e:  # noqa: BLE001 - checkrr restarting or busy: try again next poll
            log(f"WARN checkrr API: {e}")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()

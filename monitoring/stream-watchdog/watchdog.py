#!/usr/bin/env python3
"""Plex stream watchdog: playback problems that Tautulli does not report.

Follows "Plex Media Server.log" and posts to Discord when:
  - a client stalls (buffering mid-playback for STALL_ALERT_SECONDS, repeated
    rebuffering, a slow start, or the viewer giving up while buffering)
  - the transcoder logs errors (e.g. the VAAPI decoder failing on a file)
  - a video transcode runs in software (no GPU), usually a fallback after a
    hardware failure, and often slower than realtime at 4K
  - the host NIC drops its link (carrier_changes goes up)

Every alert carries a snapshot of what else was happening: NIC throughput,
qBittorrent transfer rates and active downloads, and the Plex sessions.
A metrics line is also printed to stdout (Dozzle) every 30 s while anything is
playing, so there is a history to look back at after a report.

Replay mode checks the detection against an archived log without Discord or
any API calls:
    python3 watchdog.py --replay plex-media-server-2026-11-02.log
"""

import argparse
import collections
import datetime as dt
import gzip
import json
import os
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar

ENV = os.environ.get

PLEX_LOG = ENV("PLEX_LOG", "/plex-logs/Plex Media Server.log")
PLEX_URL = ENV("PLEX_URL", "http://plex:32400").rstrip("/")
PLEX_TOKEN = ENV("PLEX_TOKEN", "")
QBIT_URL = ENV("QBITTORRENT_URL", "http://qbittorrent:8080").rstrip("/")
QBIT_USER = ENV("QBITTORRENT_USER", "")
QBIT_PASS = ENV("QBITTORRENT_PASS", "")
NIC_DIR = ENV("NIC_DIR", "/host-nic")
NIC_NAME = ENV("NIC_NAME", "enp46s0")
# Tried in order; the first one Discord recognises (GET -> 200) is used. A
# deleted webhook returns 404, which would otherwise drop every alert silently.
WEBHOOK_ENV_VARS = ("STREAM_WATCHDOG_DISCORD_WEBHOOK_URL", "GATUS_DISCORD_WEBHOOK_URL", "DISCORD_WEBHOOK_URL")
WEBHOOK = ""
MENTION = ENV("STREAM_WATCHDOG_DISCORD_MENTION", "")

STALL_ALERT_SECONDS = float(ENV("STALL_ALERT_SECONDS", "15"))
STARTUP_ALERT_SECONDS = float(ENV("STARTUP_ALERT_SECONDS", "20"))
REBUFFER_COUNT = int(ENV("REBUFFER_COUNT", "3"))
REBUFFER_WINDOW_SECONDS = float(ENV("REBUFFER_WINDOW_SECONDS", "600"))
MIN_EPISODE_SECONDS = float(ENV("MIN_EPISODE_SECONDS", "2"))
SESSION_COOLDOWN_SECONDS = float(ENV("SESSION_COOLDOWN_SECONDS", "300"))
METRICS_ACTIVE_SECONDS = float(ENV("METRICS_ACTIVE_SECONDS", "30"))
METRICS_IDLE_SECONDS = float(ENV("METRICS_IDLE_SECONDS", "300"))

RED, ORANGE, YELLOW, BLUE = 0xE74C3C, 0xE67E22, 0xF1C40F, 0x3498DB
HW_ENCODER = re.compile(r"_(vaapi|qsv|nvenc|v4l2m2m|videotoolbox|amf)$")
SW_VIDEO_ENCODER = re.compile(r"^(libx264|libx265|libvpx\S*|libsvtav1|libaom-av1|libopenh264|mpeg4|mpeg2video)$")

LINE_RE = re.compile(r"^(\w{3} \d{2}, \d{4} \d{2}:\d{2}:\d{2}\.\d{3}) \[\d+\] (\w+) - (.*)$")
REQUEST_RE = re.compile(r"^Request: \[([\d.:a-f]+):\d+ \((\w+)\)\] (\w+) (\S+) .*?Token \(([^)]*)\)(.*)$")
JOB_RE = re.compile(r"JobRunner\] Job running: .*\"/usr/lib/plexmediaserver/Plex Transcoder\" (.*)$")
JOB_SESSION_RE = re.compile(r"/transcode/session/([\w-]+)/")
# Logged at ERROR by the transcoder but harmless (subtitle styling quirks, etc.)
BENIGN_TRANSCODE_ERR_RE = re.compile(r"Warning: |no style named|Unknown style|Missing glyph|fontselect", re.I)
TRANSCODE_ERR_RE = re.compile(r"^\[Req#\w+/Transcode/([\w-]+)/[\w-]+\] (.*)$")


REPLAY_CLOCK = None  # set in replay mode so output carries the log's own time


def log(msg):
    t = dt.datetime.fromtimestamp(REPLAY_CLOCK[0]) if REPLAY_CLOCK else dt.datetime.now()
    print(f"{t.isoformat(timespec='seconds')} {msg}", flush=True)


def parse_ts(text):
    return dt.datetime.strptime(text, "%b %d, %Y %H:%M:%S.%f").timestamp()


def headers_of(tail):
    """'/ Name => value / Name2 => value2' -> dict"""
    out = {}
    for part in tail.split(" / "):
        if " => " in part:
            k, v = part.split(" => ", 1)
            out[k.strip()] = v.strip()
    return out


def fmt_pos(ms):
    s = int(ms // 1000)
    return f"{s // 3600}:{s // 60 % 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60}:{s % 60:02d}"


def http_json(url, timeout=5, opener=None, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers={"Accept": "application/json", **(headers or {})})
    with (opener.open if opener else urllib.request.urlopen)(req, timeout=timeout) as r:
        body = r.read()
    return json.loads(body) if body[:1] in (b"{", b"[") else body.decode(errors="replace")


# --------------------------------------------------------------------------
# Context: NIC, qBittorrent, Plex
# --------------------------------------------------------------------------
class Context:
    def __init__(self, live):
        self.live = live
        self.nic_samples = collections.deque(maxlen=20)  # (t, rx_bytes, tx_bytes)
        self.qbit = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
        self.qbit_logged_in = False
        self.titles = {}
        self.public_ip = None

    # NIC ------------------------------------------------------------------
    def _read(self, name):
        try:
            with open(os.path.join(NIC_DIR, name)) as f:
                return f.read().strip()
        except OSError:
            return None

    def sample_nic(self):
        rx, tx = self._read("statistics/rx_bytes"), self._read("statistics/tx_bytes")
        if rx and tx:
            self.nic_samples.append((time.monotonic(), int(rx), int(tx)))

    def nic_rate(self, window=15):
        if len(self.nic_samples) < 2:
            return None
        t1, rx1, tx1 = self.nic_samples[-1]
        old = [s for s in self.nic_samples if t1 - s[0] >= window] or [self.nic_samples[0]]
        t0, rx0, tx0 = old[-1]
        if t1 <= t0:
            return None
        return (rx1 - rx0) * 8 / (t1 - t0) / 1e6, (tx1 - tx0) * 8 / (t1 - t0) / 1e6

    def carrier(self):
        c = self._read("carrier_changes")
        return int(c) if c and c.isdigit() else None

    # qBittorrent ------------------------------------------------------------
    def _qbit_get(self, path):
        if not self.qbit_logged_in:
            data = urllib.parse.urlencode({"username": QBIT_USER, "password": QBIT_PASS}).encode()
            http_json(f"{QBIT_URL}/api/v2/auth/login", opener=self.qbit, data=data,
                      headers={"Referer": QBIT_URL})
            self.qbit_logged_in = True
        try:
            return http_json(f"{QBIT_URL}{path}", opener=self.qbit)
        except urllib.error.HTTPError as e:
            if e.code == 403:
                self.qbit_logged_in = False
            raise

    def qbittorrent(self):
        try:
            info = self._qbit_get("/api/v2/transfer/info")
            downloading = self._qbit_get("/api/v2/torrents/info?filter=downloading")
            active = [t for t in downloading if t.get("dlspeed", 0) > 0]
            return {
                "dl_mbps": info["dl_info_speed"] * 8 / 1e6,
                "ul_mbps": info["up_info_speed"] * 8 / 1e6,
                "dl_limit_mbps": info.get("dl_rate_limit", 0) * 8 / 1e6,
                "active": sorted(active, key=lambda t: -t["dlspeed"]),
            }
        except Exception as e:  # noqa: BLE001 - context is best effort
            return {"error": str(e)[:120]}

    # Plex -------------------------------------------------------------------
    def plex(self, path):
        sep = "&" if "?" in path else "?"
        return http_json(f"{PLEX_URL}{path}{sep}X-Plex-Token={PLEX_TOKEN}")

    def title(self, rating_key):
        if not rating_key:
            return None
        if rating_key in self.titles or not self.live:
            return self.titles.get(rating_key)
        try:
            m = self.plex(f"/library/metadata/{rating_key}")["MediaContainer"]["Metadata"][0]
            if m.get("type") == "episode":
                t = f"{m.get('grandparentTitle')} - S{m.get('parentIndex', 0):02}E{m.get('index', 0):02} - {m.get('title')}"
            else:
                t = f"{m.get('title')} ({m.get('year', '?')})"
            media = (m.get("Media") or [{}])[0]
            t += f" [{media.get('videoResolution', '?')} {media.get('videoCodec', '?')} {media.get('bitrate', '?')} kbps {media.get('audioCodec', '?')}]"
        except Exception:  # noqa: BLE001
            t = None
        self.titles[rating_key] = t
        return t

    def home_ip(self):
        if self.public_ip is None and self.live:
            try:
                body = http_json(f"{PLEX_URL}/myplex/account?X-Plex-Token={PLEX_TOKEN}")
                if isinstance(body, dict):  # JSON reply (we send Accept: application/json)
                    found = (body.get("MyPlex") or body).get("publicAddress", "")
                else:
                    m = re.search(r'publicAddress="([^"]+)"', body)
                    found = m.group(1) if m else ""
                self.public_ip = found
                return self.public_ip
            except Exception:  # noqa: BLE001
                return ""
        return self.public_ip or ""

    def sessions(self):
        try:
            mc = self.plex("/status/sessions")["MediaContainer"]
        except Exception as e:  # noqa: BLE001
            return {"error": str(e)[:120]}
        out = []
        for m in mc.get("Metadata", []):
            title = m.get("title")
            if m.get("type") == "episode":
                title = f"{m.get('grandparentTitle')} - {title}"
            media = (m.get("Media") or [{}])[0]
            ts = m.get("TranscodeSession") or {}
            sess = m.get("Session") or {}
            player = m.get("Player") or {}
            if ts:
                vd = ts.get("videoDecision", "?")
                hw = "hw" if ts.get("transcodeHwEncoding") or ts.get("transcodeHwFullPipeline") else ("sw" if vd == "transcode" else "")
                dec = f"video {vd}{'/' + hw if hw else ''}, audio {ts.get('audioDecision', '?')}, speed {ts.get('speed', '?')}{' throttled' if ts.get('throttled') else ''}"
            else:
                dec = "direct play"
            out.append({
                "user": (m.get("User") or {}).get("title"),
                "title": title,
                "player": f"{player.get('title')} ({player.get('product')})",
                "state": player.get("state"),
                "location": sess.get("location"),
                "bandwidth_kbps": sess.get("bandwidth"),
                "source": f"{media.get('videoResolution', '?')} {media.get('videoCodec', '?')} {media.get('bitrate', '?')} kbps",
                "decision": dec,
            })
        return out

    def snapshot(self):
        if not self.live:
            return {}
        snap = {"load": os.getloadavg()[0]}
        rate = self.nic_rate()
        if rate:
            snap["nic_rx_mbps"], snap["nic_tx_mbps"] = rate
        snap["qbit"] = self.qbittorrent()
        snap["plex"] = self.sessions()
        return snap


def snapshot_fields(snap):
    if not snap:
        return []
    fields = []
    host = [f"load {snap['load']:.1f}"]
    if "nic_rx_mbps" in snap:
        host.append(f"NIC {NIC_NAME} rx {snap['nic_rx_mbps']:.0f} / tx {snap['nic_tx_mbps']:.0f} Mbps (of 1000)")
    fields.append({"name": "Host", "value": "\n".join(host), "inline": False})
    q = snap.get("qbit", {})
    if "error" in q:
        fields.append({"name": "qBittorrent", "value": f"unavailable: {q['error']}", "inline": False})
    elif q:
        lines = [f"down {q['dl_mbps']:.0f} Mbps, up {q['ul_mbps']:.0f} Mbps"
                 + (f" (down limit {q['dl_limit_mbps']:.0f})" if q.get("dl_limit_mbps") else " (no down limit)")]
        for t in q["active"][:3]:
            lines.append(f"• {t['name'][:60]} {t['dlspeed'] * 8 / 1e6:.0f} Mbps")
        fields.append({"name": "qBittorrent", "value": "\n".join(lines), "inline": False})
    p = snap.get("plex")
    if isinstance(p, dict):
        fields.append({"name": "Plex sessions", "value": f"unavailable: {p['error']}", "inline": False})
    elif p is not None:
        lines = [f"• {s['user']} on {s['player']}: {s['title']} | {s['source']} | {s['decision']} | "
                 f"{s['location']} {s['bandwidth_kbps']} kbps | {s['state']}" for s in p] or ["none"]
        fields.append({"name": f"Plex sessions ({len(p)})", "value": "\n".join(lines)[:1024], "inline": False})
    return fields


# --------------------------------------------------------------------------
# Discord
# --------------------------------------------------------------------------
def pick_webhook():
    """First configured webhook that Discord answers with 200 (a GET posts nothing)."""
    for name in WEBHOOK_ENV_VARS:
        url = ENV(name, "")
        if not url.startswith("https://"):
            continue
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "homelab-stream-watchdog"})
            urllib.request.urlopen(req, timeout=10).read()
            log(f"Discord webhook: using {name}")
            return url
        except urllib.error.HTTPError as e:
            log(f"WARN Discord webhook {name} rejected by Discord (HTTP {e.code}), trying the next one")
        except Exception as e:  # noqa: BLE001 - network hiccup: still use it rather than nothing
            log(f"WARN could not verify Discord webhook {name} ({e}); using it anyway")
            return url
    return ""


class Notifier:
    def __init__(self, live):
        global WEBHOOK
        if live:
            WEBHOOK = pick_webhook()
        self.live = live and bool(WEBHOOK)
        if live and not WEBHOOK:
            log(f"WARN no working Discord webhook in {', '.join(WEBHOOK_ENV_VARS)}; alerts only go to stdout")

    def send(self, title, description, color, fields=()):
        log(f"ALERT {title} | {description.replace(chr(10), ' | ')}")
        for f in fields:
            log(f"      {f['name']}: {f['value'].replace(chr(10), ' | ')}")
        if not self.live:
            return
        payload = {
            "username": "Stream watchdog",
            "content": MENTION or None,
            "embeds": [{
                "title": title[:256],
                "description": description[:4000],
                "color": color,
                "fields": list(fields)[:25],
                "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
            }],
        }
        threading.Thread(target=self._post, args=(payload,), daemon=True).start()

    @staticmethod
    def _post(payload):
        body = json.dumps(payload).encode()
        for attempt in range(3):
            try:
                req = urllib.request.Request(WEBHOOK, data=body, headers={
                    "Content-Type": "application/json", "User-Agent": "homelab-stream-watchdog"})
                urllib.request.urlopen(req, timeout=10).read()
                return
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    time.sleep(float(e.headers.get("Retry-After", "2")))
                    continue
                log(f"WARN Discord post failed: {e}")
                return
            except Exception as e:  # noqa: BLE001
                log(f"WARN Discord post failed: {e}")
                time.sleep(2)


# --------------------------------------------------------------------------
# Detection
# --------------------------------------------------------------------------
class Playback:
    def __init__(self, key):
        self.key = key
        self.state = None
        self.pos = 0
        self.pos_at = 0.0
        self.buf_start = None
        self.buf_kind = None  # "startup" | "seek" | "rebuffer"
        self.buf_pos = 0
        self.buf_alerted = False
        self.episodes = collections.deque()  # (end_time, seconds)
        self.last_alert = -1e12
        self.last_seen = 0.0
        self.info = {}


class Watchdog:
    def __init__(self, live):
        self.live = live
        self.ctx = Context(live)
        self.notify = Notifier(live)
        self.playbacks = {}
        self.client_alerts = {}  # client id -> [last alert time, suppressed count]
        self.transcodes = {}  # session id -> dict(rk, user, device, jobs)
        self.errors = {}  # session id -> (first_time, [messages])
        self.error_alerted = {}  # session id -> time
        self.now = 0.0

    # ---- helpers ---------------------------------------------------------
    def describe(self, info):
        title = self.ctx.title(info.get("rk")) or info.get("file") or f"ratingKey {info.get('rk')}"
        who = f"**{info.get('user', '?')}** on **{info.get('device', '?')}**"
        if info.get("product"):
            who += f" ({info['product']})"
        return title, who

    def path_note(self, info):
        ip, src = info.get("real_ip"), info.get("src")
        if not ip:
            return None
        home = self.ctx.home_ip()
        if home and ip == home and src == "WAN":
            return f"Home network device reaching Plex through the VPS tunnel (client IP {ip} is the home IP): the stream goes out and back over the internet link."
        return f"Client IP {ip} ({src})"

    # ---- timeline / stalls -------------------------------------------------
    def on_timeline(self, ts, q, user, src, hdrs):
        rk = q.get("ratingKey")
        cid = hdrs.get("X-Plex-Client-Identifier") or q.get("X-Plex-Client-Identifier") or hdrs.get("X-Real-Ip", "?")
        key = (cid, rk)
        pb = self.playbacks.get(key)
        if pb is None:
            pb = self.playbacks[key] = Playback(key)
        pb.last_seen = ts
        pb.info.update({
            "rk": rk, "user": user, "src": src,
            "device": hdrs.get("X-Plex-Device-Name") or q.get("X-Plex-Device-Name") or "?",
            "product": hdrs.get("X-Plex-Product") or q.get("X-Plex-Product"),
            "real_ip": hdrs.get("X-Real-Ip") or hdrs.get("X-Forwarded-For"),
        })
        state = q.get("state")
        pos = int(q.get("time", "0") or 0)
        stalled = float(q.get("timeStalled", "0") or 0)
        pb.info["duration"] = int(q.get("duration", "0") or 0)

        near_end = pb.info["duration"] and pos >= pb.info["duration"] - 30000
        if state == "buffering" and near_end:
            pass  # credits / end of file: clients often report buffering here
        elif state == "buffering":
            if pb.buf_start is None:
                expected = pb.pos + (ts - pb.pos_at) * 1000 if pb.state == "playing" else pb.pos
                if pb.state in (None, "stopped") or q.get("playbackTime") == "0":
                    kind = "startup"
                elif abs(pos - expected) > 15000:
                    kind = "seek"
                else:
                    kind = "rebuffer"
                pb.buf_start, pb.buf_kind, pb.buf_pos, pb.buf_alerted = ts, kind, pos, False
        elif pb.buf_start is not None and state in ("playing", "paused", "stopped"):
            secs = max(ts - pb.buf_start, stalled)
            self.end_episode(pb, ts, secs, abandoned=(state == "stopped"))
        elif state == "stopped" and stalled >= STARTUP_ALERT_SECONDS:
            # Some clients only report the stall on stop (timeStalled)
            pb.buf_start, pb.buf_kind, pb.buf_pos, pb.buf_alerted = ts - stalled, "startup", pos, False
            self.end_episode(pb, ts, stalled, abandoned=True)
        pb.state, pb.pos, pb.pos_at = state, pos, ts
        if state == "stopped":
            pb.buf_start = None

    def threshold(self, pb):
        return STARTUP_ALERT_SECONDS if pb.buf_kind in ("startup", "seek") else STALL_ALERT_SECONDS

    def end_episode(self, pb, ts, secs, abandoned):
        kind, alerted = pb.buf_kind, pb.buf_alerted
        pb.buf_start = None
        if secs < MIN_EPISODE_SECONDS:
            return
        if kind == "rebuffer":
            pb.episodes.append((ts, secs))
        while pb.episodes and ts - pb.episodes[0][0] > REBUFFER_WINDOW_SECONDS:
            pb.episodes.popleft()
        if alerted:
            if secs >= 60 or abandoned:
                self.stall_alert(pb, secs, "abandoned" if abandoned else "recovered", kind)
            return
        if secs >= self.threshold(pb) or (abandoned and secs >= 8 and kind == "rebuffer"):
            self.stall_alert(pb, secs, "abandoned" if abandoned else "recovered", kind)
        elif len(pb.episodes) >= REBUFFER_COUNT and ts - pb.last_alert >= SESSION_COOLDOWN_SECONDS:
            self.stall_alert(pb, secs, "repeated", kind)

    def tick(self):
        for pb in list(self.playbacks.values()):
            if pb.buf_start is not None and not pb.buf_alerted and self.now - pb.buf_start >= self.threshold(pb):
                pb.buf_alerted = True
                self.stall_alert(pb, self.now - pb.buf_start, "ongoing", pb.buf_kind)
            if self.now - pb.last_seen > 3600:
                del self.playbacks[pb.key]
        for sid, (first, msgs) in list(self.errors.items()):
            if self.now - first >= 3:
                del self.errors[sid]
                self.transcode_error_alert(sid, msgs)

    def stall_alert(self, pb, secs, phase, kind):
        # One alert per client per cooldown; long stalls (>= 60 s) always get through
        ca = self.client_alerts.setdefault(pb.key[0], [-1e12, 0])
        if self.now - ca[0] < SESSION_COOLDOWN_SECONDS and secs < 60:
            ca[1] += 1
            return
        suppressed, ca[0], ca[1] = ca[1], self.now, 0
        pb.last_alert = self.now
        title, who = self.describe(pb.info)
        what = {"startup": "slow start", "seek": "stall after seek", "rebuffer": "buffering mid-playback"}[kind]
        headline = {
            "ongoing": f"Plex stall: {what}, {secs:.0f}s and counting",
            "recovered": f"Plex stall: {what}, {secs:.0f}s",
            "abandoned": f"Plex stall: viewer stopped after {secs:.0f}s of {what}",
            "repeated": f"Plex stall: {len(pb.episodes)} rebuffers in {REBUFFER_WINDOW_SECONDS / 60:.0f} min",
        }[phase]
        lines = [f"{who}", f"{title}", f"Position {fmt_pos(pb.buf_pos)} of {fmt_pos(pb.info.get('duration', 0))}"]
        if pb.episodes:
            lines.append("Recent rebuffers: " + ", ".join(f"{s:.0f}s" for _, s in pb.episodes))
        note = self.path_note(pb.info)
        if note:
            lines.append(note)
        if suppressed:
            lines.append(f"(+{suppressed} more stall events from this client since the last alert)")
        color = RED if secs >= 60 or phase == "abandoned" else ORANGE
        self.notify.send(headline, "\n".join(lines), color, snapshot_fields(self.ctx.snapshot()))

    # ---- transcoder --------------------------------------------------------
    def on_transcode_request(self, q, user, hdrs):
        sid = q.get("session")
        if not sid:
            return
        path = urllib.parse.unquote(q.get("path", ""))
        m = re.search(r"/library/metadata/(\d+)", path)
        t = self.transcodes.setdefault(sid, {"jobs": []})
        t.update({
            "rk": m.group(1) if m else t.get("rk"), "user": user,
            "device": hdrs.get("X-Plex-Device-Name") or q.get("X-Plex-Device-Name") or t.get("device", "?"),
            "product": hdrs.get("X-Plex-Product") or q.get("X-Plex-Product") or t.get("product"),
            "real_ip": hdrs.get("X-Real-Ip") or t.get("real_ip"),
        })

    def on_job(self, sid, args):
        pre, _, post = args.partition(' -i "')
        infile, _, post = post.partition('"')
        enc = re.search(r"-codec:0 (\S+)", post)
        enc = enc.group(1) if enc else None
        hwdec = "-hwaccel:0" in pre
        ss = re.search(r"(?:^| )-ss (\d+)", pre)
        tonemap = "tonemap=" in post
        burn = "inlineass" in post or "overlay" in post
        t = self.transcodes.setdefault(sid, {"jobs": []})
        t.setdefault("file", os.path.basename(infile))
        t["jobs"].append(enc)
        # Only client playback sessions (Plex's own background jobs, e.g. loudness
        # analysis, also run the transcoder) and only software *video* encoders
        if not enc or not SW_VIDEO_ENCODER.match(enc) or not t.get("user"):
            return
        fallback = any(j and HW_ENCODER.search(j) for j in t["jobs"][:-1])
        title, who = self.describe(t)
        headline = "Plex transcoder fell back to software (GPU failed)" if fallback else "Plex software video transcode (no GPU)"
        lines = [who, title,
                 f"Encoder `{enc}`, decode {'GPU' if hwdec else 'CPU'}"
                 + (", CPU HDR tone mapping" if tonemap else "") + (", subtitles burned in" if burn else ""),
                 f"Starting at {fmt_pos(int(ss.group(1)) * 1000) if ss else '0:00'}"]
        if fallback:
            lines.append("The GPU pipeline failed on this session (see the transcoder error alert). "
                         "Software transcodes of 4K/HDR run near or below realtime here, so expect freezes or buffering.")
        self.notify.send(headline, "\n".join(lines), RED if fallback else YELLOW, snapshot_fields(self.ctx.snapshot()))

    def on_transcode_error(self, sid, msg):
        if self.now - self.error_alerted.get(sid, -1e12) < 600:
            return
        first, msgs = self.errors.setdefault(sid, (self.now, []))
        if msg not in msgs and len(msgs) < 6:
            msgs.append(msg)

    def transcode_error_alert(self, sid, msgs):
        self.error_alerted[sid] = self.now
        t = self.transcodes.get(sid, {})
        if not t.get("user"):
            return  # Plex background job (thumbnails, intro/credits detection), nobody is watching
        title, who = self.describe(t)
        hint = ""
        if any("Failed to sync surface" in m or "internal decoding error" in m for m in msgs):
            hint = ("\nThe Intel VAAPI decoder failed on this file. Plex retries the job, usually in software. "
                    "If it repeats at the same position, the file triggers a GPU decoder bug (test with software decode).")
        desc = f"{who}\n{title}\n```\n" + "\n".join(m[:180] for m in msgs) + "\n```" + hint
        self.notify.send("Plex transcoder error", desc, RED, snapshot_fields(self.ctx.snapshot()))

    # ---- line dispatch -----------------------------------------------------
    def handle(self, line, now=None):
        m = LINE_RE.match(line)
        if not m:
            return
        ts_text, level, msg = m.groups()
        try:
            ts = parse_ts(ts_text)
        except ValueError:
            return
        self.now = now if now is not None else ts
        if msg.startswith("Request: ["):
            r = REQUEST_RE.match(msg)
            if not r:
                return
            src_ip, src, method, url, user, tail = r.groups()
            path, _, query = url.partition("?")
            if path not in ("/:/timeline", "/video/:/transcode/universal/decision",
                            "/video/:/transcode/universal/start.m3u8", "/video/:/transcode/universal/start.mpd",
                            "/video/:/transcode/universal/start"):
                return
            q = dict(urllib.parse.parse_qsl(query, keep_blank_values=True))
            hdrs = headers_of(tail)
            if path == "/:/timeline":
                self.on_timeline(self.now, q, user, src, hdrs)
            else:
                self.on_transcode_request(q, user, hdrs)
            return
        j = JOB_RE.search(msg)
        if j:
            sid = JOB_SESSION_RE.search(j.group(1))
            if sid:  # the job's -progressurl names the session; fallback jobs lack the [Req#/Transcode/<sid>] tag
                self.on_job(sid.group(1), j.group(1))
            return
        if level == "ERROR":
            e = TRANSCODE_ERR_RE.match(msg)
            if e and not BENIGN_TRANSCODE_ERR_RE.search(e.group(2)):
                self.on_transcode_error(*e.groups())


# --------------------------------------------------------------------------
# Runners
# --------------------------------------------------------------------------
def follow(path):
    """tail -F: yields lines, reopening when Plex rotates the log."""
    f, ino = None, None
    while True:
        if f is None:
            try:
                f = open(path, errors="replace")
                ino = os.fstat(f.fileno()).st_ino
                if ino is not None and not getattr(follow, "started", False):
                    f.seek(0, os.SEEK_END)
                    follow.started = True
            except OSError:
                yield None
                time.sleep(2)
                continue
        line = f.readline()
        if line:
            if line.endswith("\n"):
                yield line.rstrip("\n")
            else:
                time.sleep(0.2)
                f.seek(f.tell() - len(line))
            continue
        try:
            st = os.stat(path)
            if st.st_ino != ino or st.st_size < f.tell():
                f.close()
                f = None
                continue
        except OSError:
            pass
        yield None
        time.sleep(0.5)


def run_live():
    wd = Watchdog(live=True)
    log(f"stream-watchdog started: log={PLEX_LOG} nic={NIC_NAME} discord={'yes' if WEBHOOK else 'no'} "
        f"stall>={STALL_ALERT_SECONDS:.0f}s startup>={STARTUP_ALERT_SECONDS:.0f}s rebuffers>={REBUFFER_COUNT}/{REBUFFER_WINDOW_SECONDS:.0f}s")
    carrier = wd.ctx.carrier()
    last_nic = last_metrics = 0.0
    last_log_ts, last_log_mono = time.time(), time.monotonic()
    active = False
    for line in follow(PLEX_LOG):
        mono = time.monotonic()
        if line is not None:
            m = LINE_RE.match(line)
            if m:
                try:
                    last_log_ts, last_log_mono = parse_ts(m.group(1)), mono
                except ValueError:
                    pass
            try:
                wd.handle(line, now=last_log_ts)
            except Exception as e:  # noqa: BLE001 - never die on one odd line
                log(f"WARN failed to handle line: {e}: {line[:200]}")
        # Clock for ticks: last log timestamp plus wall time since it was read
        wd.now = last_log_ts + (mono - last_log_mono)
        if mono - last_nic >= 5:
            last_nic = mono
            wd.ctx.sample_nic()
            c = wd.ctx.carrier()
            if c is not None and carrier is not None and c > carrier:
                speed = wd.ctx._read("speed")
                state = wd.ctx._read("operstate")
                wd.notify.send(
                    f"Server NIC link dropped ({NIC_NAME})",
                    f"carrier_changes went {carrier} → {c} (each drop counts twice: down + up).\n"
                    f"Link is now **{state}**, speed {speed} Mbps.\n"
                    "During a drop, NAS reads and the Pangolin tunnel stall; streams buffer or stop.",
                    RED, snapshot_fields(wd.ctx.snapshot()))
            if c is not None:
                carrier = c
            wd.tick()
        interval = METRICS_ACTIVE_SECONDS if active else METRICS_IDLE_SECONDS
        if mono - last_metrics >= interval:
            last_metrics = mono
            try:
                snap = wd.ctx.snapshot()
                plex = snap.get("plex")
                active = isinstance(plex, list) and len(plex) > 0
                q = snap.get("qbit", {})
                parts = [f"load={snap['load']:.1f}"]
                if "nic_rx_mbps" in snap:
                    parts.append(f"nic_rx={snap['nic_rx_mbps']:.0f}Mbps nic_tx={snap['nic_tx_mbps']:.0f}Mbps")
                if "dl_mbps" in q:
                    parts.append(f"qbit_dl={q['dl_mbps']:.0f}Mbps qbit_ul={q['ul_mbps']:.0f}Mbps qbit_active={len(q['active'])}")
                if isinstance(plex, list):
                    parts.append(f"plex_sessions={len(plex)}")
                    parts += [f"[{s['user']}|{s['player']}|{s['title']}|{s['source']}|{s['decision']}|{s['location']} {s['bandwidth_kbps']}kbps|{s['state']}]" for s in plex]
                log("metrics " + " ".join(parts))
            except Exception as e:  # noqa: BLE001
                log(f"WARN metrics failed: {e}")


def run_replay(path):
    global REPLAY_CLOCK
    wd = Watchdog(live=False)
    REPLAY_CLOCK = [0.0]
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", errors="replace") as f:
        for line in f:
            wd.handle(line.rstrip("\n"))
            REPLAY_CLOCK[0] = wd.now
            wd.tick()
    print("replay done", file=sys.stderr)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--replay", help="process an archived Plex log and print alerts (no Discord, no API calls)")
    a = ap.parse_args()
    if a.replay:
        run_replay(a.replay)
    else:
        run_live()

#!/usr/bin/env python3
"""Bundle 264: control script for the GitHub run-time test.

Runs on the GitHub machine (never on a phone or your PC server), listens on
0.0.0.0:8099 and is called by the app test through http://10.0.2.2:8099.
Standard library only.

  /start[?pairing=1]  start the Go server (database kept between runs)
  /stop               stop it
  /admin/<action>     users | block | unblock | revoke | version | duplicates | count401
  /shot/<name>        adb screenshot to out/shots/<name>.png
  /mark/<name>        set a barrier mark (2-emulator case)
  /wait/<name>?s=N    wait until the mark is set (max N seconds)
  /pull-logs          copy the shared log file out of the app (adb run-as)
"""
import json
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(os.environ.get("RT264_OUT", "out"))
SERVER_BIN = os.path.abspath(os.environ.get("RT264_SERVER_BIN", "out/server/locallink"))
SERIALS = [s for s in os.environ.get("RT264_SERIALS", "").split(",") if s]
PACKAGE = "com.sajjad.linkup"
API = "http://127.0.0.1:8080"
ADMIN_USER = "rtadmin"
ADMIN_PASS = os.environ.get("RT264_ADMIN_PASS") or secrets.token_urlsafe(18)[:24]

_lock = threading.Lock()
_proc = None
_marks = set()
_token = None


def log(msg):
    sys.stdout.write("[server_ctl] %s\n" % msg)
    sys.stdout.flush()


def server_env(pairing):
    env = dict(os.environ)
    env.update({
        "LOCALLINK_ENV": "development",
        "LOCALLINK_ADDR": "0.0.0.0:8080",
        "LOCALLINK_ADVERTISE_HOST": "10.0.2.2",
        "LOCALLINK_DB": os.path.join(ROOT, "server", "locallink.db"),
        "LOCALLINK_FILES_DIR": os.path.join(ROOT, "server", "files"),
        "LOCALLINK_BACKUP_DIR": os.path.join(ROOT, "server", "backups"),
        "LOCALLINK_ADMIN_BOOTSTRAP_USERNAME": ADMIN_USER,
        "LOCALLINK_ADMIN_BOOTSTRAP_PASSWORD": ADMIN_PASS,
        # HTTP only ("keep http not https"); no certificate on the test machine.
        "LOCALLINK_REQUIRE_TLS": "false",
        "LOCALLINK_TLS_AUTO": "false",
    })
    env.pop("LOCALLINK_PAIRING_CODE", None)
    if pairing:
        env["LOCALLINK_PAIRING_CODE"] = "RT264PAIR"
    return env


def start(pairing=False):
    global _proc, _token
    with _lock:
        if _proc is not None and _proc.poll() is None:
            return {"ok": True, "already": True}
        os.makedirs(os.path.join(ROOT, "server"), exist_ok=True)
        out = open(os.path.join(ROOT, "server", "server.log"), "a")
        out.write("\n=== start %s pairing=%s ===\n" % (time.strftime("%H:%M:%S"), pairing))
        out.flush()
        # In development mode the server does not create the bootstrap admin by
        # itself (httpapi.New skips it), so make the rtadmin account first.
        reset = subprocess.run([SERVER_BIN, "--reset-admin"], env=server_env(pairing), stdout=out,
                               stderr=subprocess.STDOUT, cwd=os.path.join(ROOT, "server"), timeout=60)
        if reset.returncode != 0:
            return {"ok": False, "error": "--reset-admin failed, see out/server/server.log"}
        _proc = subprocess.Popen([SERVER_BIN], env=server_env(pairing), stdout=out,
                                 stderr=subprocess.STDOUT, cwd=os.path.join(ROOT, "server"))
        _token = None
    for _ in range(60):
        if _proc.poll() is not None:
            return {"ok": False, "error": "server exited, see out/server/server.log"}
        try:
            urllib.request.urlopen(API + "/health", timeout=1)
            return {"ok": True}
        except urllib.error.HTTPError:
            return {"ok": True}  # it answers
        except Exception:
            time.sleep(0.5)
    return {"ok": False, "error": "server did not answer in 30 s"}


def stop():
    global _proc, _token
    with _lock:
        if _proc is None or _proc.poll() is not None:
            _proc = None
            return {"ok": True, "already": True}
        _proc.terminate()
        try:
            _proc.wait(10)
        except subprocess.TimeoutExpired:
            _proc.kill()
        _proc = None
        _token = None
    return {"ok": True}


def call(method, path, body=None, auth=True):
    global _token
    if auth and _token is None:
        r = call("POST", "/api/v1/admin/login", {"username": ADMIN_USER, "password": ADMIN_PASS}, auth=False)
        _token = r.get("token")
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if auth and _token:
        req.add_header("Authorization", "Bearer " + _token)
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            raw = res.read().decode() or "{}"
    except urllib.error.HTTPError as e:
        raw = e.read().decode() or "{}"
        try:
            out = json.loads(raw)
        except ValueError:
            out = {"body": raw}
        if not isinstance(out, dict):
            out = {"items": out}
        out["http_status"] = e.code
        return out
    try:
        out = json.loads(raw)
    except ValueError:
        out = {"body": raw}
    return out if isinstance(out, dict) else {"items": out}


def rows(obj):
    """Every dict with an id inside the answer (lists can be under any key)."""
    found = []
    if isinstance(obj, dict):
        if "id" in obj:
            found.append(obj)
        for v in obj.values():
            found.extend(rows(v))
    elif isinstance(obj, list):
        for v in obj:
            found.extend(rows(v))
    return found


def user_id(username):
    r = call("GET", "/api/v1/admin/users?q=" + urllib.parse.quote(username))
    for u in rows(r):
        if u.get("username") == username:
            return u["id"]
    return ""


def admin(action, q):
    user = q.get("user", "")
    if action == "users":
        extra = "?q=" + urllib.parse.quote(q["q"]) if q.get("q") else ""
        return call("GET", "/api/v1/admin/users" + extra)
    if action in ("block", "unblock"):
        uid = user_id(user)
        if not uid:
            return {"ok": False, "error": "no user " + user}
        status = "suspended" if action == "block" else "active"
        return call("POST", "/api/v1/admin/user/status?id=%s&status=%s" % (uid, status))
    if action == "revoke":
        r = call("GET", "/api/v1/admin/sessions?limit=200")
        n = 0
        for s in rows(r):
            if s.get("username") == user and not s.get("revoked_at"):
                call("POST", "/api/v1/admin/session/revoke?id=" + urllib.parse.quote(s["id"]))
                n += 1
        return {"ok": True, "revoked": n}
    if action == "version":
        return call("POST", "/api/v1/admin/version-rule", {
            "min_build": int(q.get("min_build", "999")), "min_version": q.get("min_version", "9.9.9"),
            "mode": "stop", "stop_days": 7})
    if action == "duplicates":
        return call("GET", "/api/v1/admin/duplicates")
    if action == "count401":
        p = os.path.join(ROOT, "server", "server.log")
        n = 0
        if os.path.exists(p):
            with open(p, errors="replace") as f:
                n = sum(1 for line in f if "status=401" in line)
        return {"count": n}
    return {"ok": False, "error": "unknown action " + action}


def adb(args, serial=None):
    cmd = ["adb"] + (["-s", serial] if serial else []) + args
    return subprocess.run(cmd, capture_output=True, timeout=60)


def shot(name):
    d = os.path.join(ROOT, "shots")
    os.makedirs(d, exist_ok=True)
    for serial in SERIALS or [None]:
        suffix = "" if len(SERIALS) < 2 else "_%s" % serial
        r = adb(["exec-out", "screencap", "-p"], serial)
        with open(os.path.join(d, "%s%s.png" % (name, suffix)), "wb") as f:
            f.write(r.stdout)
    return {"ok": True}


def pull_logs():
    for serial in SERIALS or [None]:
        r = adb(["exec-out", "run-as", PACKAGE, "sh", "-c", "cat cache/LinkUp-logs-*.txt"], serial)
        name = "LinkUp-logs-%s.txt" % (serial or "emulator")
        with open(os.path.join(ROOT, name), "wb") as f:
            f.write(r.stdout)
    return {"ok": True}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(u.query))
        parts = [p for p in u.path.split("/") if p]
        try:
            if parts == ["start"]:
                out = start(pairing=q.get("pairing") == "1")
            elif parts == ["stop"]:
                out = stop()
            elif len(parts) == 2 and parts[0] == "admin":
                out = admin(parts[1], q)
            elif len(parts) == 2 and parts[0] == "shot":
                out = shot(parts[1])
            elif len(parts) == 2 and parts[0] == "mark":
                _marks.add(parts[1])
                out = {"ok": True}
            elif len(parts) == 2 and parts[0] == "wait":
                until = time.time() + int(q.get("s", "600"))
                while parts[1] not in _marks and time.time() < until:
                    time.sleep(1)
                out = {"ok": parts[1] in _marks}
            elif parts == ["pull-logs"]:
                out = pull_logs()
            else:
                out = {"ok": False, "error": "unknown path"}
        except Exception as e:  # keep the test going; the step shows the error
            out = {"ok": False, "error": str(e)}
        log("%s -> %s" % (self.path, json.dumps(out)[:300]))
        body = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    os.makedirs(ROOT, exist_ok=True)
    srv = ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("RT264_CTL_PORT", "8099"))), Handler)
    log("listening on %s, server bin %s" % (srv.server_address, SERVER_BIN))
    try:
        srv.serve_forever()
    finally:
        stop()


if __name__ == "__main__":
    main()

"""Local MIoT heater control with an in-process 30-minute cycle."""

from __future__ import annotations

import argparse
import copy
import json
import logging
import math
import os
import queue
import re
import secrets
import signal
import threading
import time
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from miio import Device

MODEL = "xiaomi.heater.ma3"
PAGE = "/iot/heater_ma3.html"
API = "/iot/heater_ma3/api/"
PROPERTIES = {
    "power": (2, 1),
    "fault": (2, 2),
    "status": (2, 3),
    "target_temperature": (2, 5),
    "heat_level": (2, 7),
    "temperature": (4, 7),
}
LOG = logging.getLogger("heater-controller")


class StateError(RuntimeError):
    pass


class Heater:
    def __init__(self, host, token_file, timeout):
        token = Path(token_file).read_text().strip()
        if not re.fullmatch(r"[0-9a-fA-F]{32}", token):
            raise ValueError("Invalid token credential")
        self.device = Device(host, token, timeout=timeout, handshake_timeout=30)
        self.device.retry_count = 0
        self.validated = False

    def validate(self):
        if not self.validated:
            if self.device.info().model != MODEL:
                raise ValueError("Unexpected device model")
            self.validated = True

    def read(self):
        self.validate()
        query = [
            {"did": name, "siid": siid, "piid": piid}
            for name, (siid, piid) in PROPERTIES.items()
        ]
        response = self.device.send("get_properties", query, retry_count=0)
        values = {}
        for item in response:
            if item.get("code") == 0 and item.get("did") in PROPERTIES:
                values[item["did"]] = item.get("value")
        if set(values) != set(PROPERTIES) or type(values["power"]) is not bool:
            raise ValueError("Incomplete device status")
        for name in ("temperature", "target_temperature"):
            if type(values[name]) not in (int, float) or not math.isfinite(values[name]):
                raise ValueError("Invalid device temperature")
        return values

    def set_power(self, enabled):
        self.validate()
        # The only write this service may send: heater switch, never heat-level.
        response = self.device.send(
            "set_properties",
            [{"did": "power", "siid": 2, "piid": 1, "value": enabled}],
            retry_count=0,
        )
        if len(response) != 1 or response[0].get("code") != 0:
            raise ValueError("Device rejected switch command")


class Controller:
    """Owned by one worker; HTTP threads only access published snapshots."""

    def __init__(self, heater, state_file, interval=1800, poll_interval=15, clock=time):
        self.heater, self.state_file, self.clock = heater, Path(state_file), clock
        self.interval, self.poll_interval = interval, poll_interval
        self.state = {"enabled": False, "phase": "off", "next_at": None, "pending": None}
        self.actual = None
        self.last_success = None
        self.error = None
        self.deadline = None
        self.next_poll = 0
        self.next_retry = 0
        self.snapshot_lock = threading.Lock()
        if self.state_file.exists():
            self.state = json.loads(self.state_file.read_text())
            self._validate_state()
            if self.state["enabled"]:
                remaining = (self.state["next_at"] or 0) - self.clock.time()
                if remaining <= 0:
                    # Missed transitions are never replayed as an immediate turn-on.
                    self.state.update(phase="off", next_at=None, pending=False)
                    self._save()
                else:
                    self.deadline = self.clock.monotonic() + min(remaining, interval)
        self._publish()

    def _validate_state(self):
        s = self.state
        if not isinstance(s, dict) or set(s) != {"enabled", "phase", "next_at", "pending"}:
            raise ValueError("Invalid saved controller state")
        if type(s["enabled"]) is not bool or s["phase"] not in ("on", "off"):
            raise ValueError("Invalid saved controller state")
        if s["pending"] is not None and type(s["pending"]) is not bool:
            raise ValueError("Invalid pending switch")
        if s["next_at"] is not None and (
            type(s["next_at"]) not in (int, float) or not math.isfinite(s["next_at"])
        ):
            raise ValueError("Invalid saved deadline")
        if s["pending"] is not None and s["pending"] != (s["phase"] == "on"):
            raise ValueError("Inconsistent pending switch")
        if not s["enabled"] and (s["phase"] != "off" or s["next_at"] is not None):
            raise ValueError("Inconsistent disabled state")
        if s["enabled"] and s["next_at"] is None and s["pending"] is not False:
            raise ValueError("Missing saved deadline")

    def _save(self):
        try:
            self._write_state()
        except OSError as exc:
            raise StateError("Cannot persist controller state") from exc

    def _write_state(self):
        # Persist intent before a device write, including an unconfirmed shutdown.
        tmp = self.state_file.with_suffix(".tmp")
        with open(tmp, "w", opener=lambda p, flags: os.open(p, flags, 0o600)) as f:
            json.dump(self.state, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.state_file)
        fd = os.open(self.state_file.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def _set_deadline(self):
        self.state["next_at"] = self.clock.time() + self.interval
        self.deadline = self.clock.monotonic() + self.interval

    def _target(self, power):
        self.state.update(phase="on" if power else "off", pending=power, next_at=None)
        self.deadline = None
        if power:
            # Even a lost turn-on acknowledgement must not extend the on window.
            self._set_deadline()
        self.next_retry = 0
        self._save()

    def set_automation(self, enabled):
        if enabled == self.state["enabled"]:
            return  # Repeated HTTP requests cannot reset the cycle.
        self.state["enabled"] = enabled
        self._target(enabled)
        LOG.info("Automation %s", "enabled" if enabled else "disabled")
        self._publish()

    def _read(self):
        self.actual = self.heater.read()
        self.last_success = self.clock.time()

    def tick(self):
        now = self.clock.monotonic()
        if self.state["enabled"] and self.deadline is not None and now >= self.deadline:
            self._target(self.state["phase"] != "on")
        if self.state["pending"] is not None and now >= self.next_retry:
            target = self.state["pending"]
            try:
                try:
                    self._read()
                except Exception:
                    if target:
                        raise  # Require a healthy, current status before turning on.
                if target and self.actual["fault"] != 0:
                    self.state["enabled"] = False
                    self._target(False)
                    target = False
                if target and self.clock.monotonic() >= self.deadline:
                    self._target(False)
                    target = False
                self.heater.set_power(target)
                self._read()
                if self.actual["power"] is not target:
                    raise ValueError("Switch not confirmed")
            except StateError:
                raise
            except Exception as exc:
                self.error = f"设备控制未确认（{type(exc).__name__}）"
                self.next_retry = self.clock.monotonic() + 10
                LOG.warning("Switch %s unconfirmed (%s)", target, type(exc).__name__)
            else:
                self.state["pending"] = None
                if not target and self.state["enabled"]:
                    # The off interval starts only once off is confirmed.
                    self._set_deadline()
                self._save()
                self.error = None
                LOG.info("Switch %s confirmed", target)
            self.next_poll = self.clock.monotonic() + self.poll_interval
        elif now >= self.next_poll:
            try:
                self._read()
            except Exception as exc:
                self.error = f"设备状态读取失败（{type(exc).__name__}）"
                LOG.warning("Status unavailable (%s)", type(exc).__name__)
            else:
                if self.state["pending"] is None:
                    self.error = None
            self.next_poll = self.clock.monotonic() + self.poll_interval
        self._publish()

    def _publish(self):
        remaining = None if self.deadline is None else max(0, self.deadline - self.clock.monotonic())
        with self.snapshot_lock:
            self.published = {
                **self.state,
                "device": copy.deepcopy(self.actual),
                "last_success": self.last_success,
                "error": self.error,
                "stale": self.last_success is None or self.clock.time() - self.last_success > self.poll_interval * 2,
                "next_at": None if remaining is None else self.clock.time() + remaining,
                "interval_seconds": self.interval,
            }

    def snapshot(self):
        with self.snapshot_lock:
            return copy.deepcopy(self.published)


@dataclass
class Command:
    enabled: bool
    done: threading.Event = field(default_factory=threading.Event)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, controller, origin, page):
        self.controller, self.origin, self.page = controller, origin, page
        self.csrf = secrets.token_urlsafe(32)
        self.commands = queue.Queue(maxsize=16)
        self.stopping = threading.Event()
        self.worker = threading.Thread(target=self.run_worker, daemon=True)
        super().__init__(address, Handler)

    def run_worker(self):
        while not self.stopping.is_set():
            try:
                cmd = self.commands.get(timeout=0.25)
            except queue.Empty:
                cmd = None
            # Persistence errors deliberately terminate the service, rather than
            # leaving an apparently healthy HTTP server without its scheduler.
            try:
                if cmd is not None:
                    self.controller.set_automation(cmd.enabled)
                self.controller.tick()
            except Exception:
                LOG.critical("Controller state persistence failed")
                os._exit(1)
            if cmd is not None:
                cmd.done.set()


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, data, content_type="application/json; charset=utf-8"):
        if isinstance(data, dict):
            data = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == PAGE:
            self.reply(200, self.server.page, "text/html; charset=utf-8")
        elif self.path == API + "status":
            self.reply(200, {**self.server.controller.snapshot(), "csrf": self.server.csrf})
        else:
            self.reply(404, {"error": "Not found"})

    def do_POST(self):
        if self.path != API + "automation":
            self.reply(404, {"error": "Not found"})
            return
        if self.headers.get("Origin") != self.server.origin or not secrets.compare_digest(
            self.headers.get("X-CSRF-Token", ""), self.server.csrf
        ):
            self.reply(403, {"error": "Invalid request origin or CSRF token"})
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 1024 or self.headers.get_content_type() != "application/json":
                raise ValueError
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict) or set(data) != {"enabled"} or type(data["enabled"]) is not bool:
                raise ValueError
        except (ValueError, UnicodeDecodeError):
            self.reply(400, {"error": "Expected JSON with a boolean enabled field"})
            return
        cmd = Command(data["enabled"])
        try:
            self.server.commands.put_nowait(cmd)
        except queue.Full:
            self.reply(503, {"error": "Controller busy"})
            return
        completed = cmd.done.wait(15)
        self.reply(200 if completed else 202, self.server.controller.snapshot())

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, fmt, *args):
        # Do not log request headers or bodies.
        pass


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", required=True)
    p.add_argument("--token-file", required=True)
    p.add_argument("--state-file", required=True)
    p.add_argument("--page", required=True)
    p.add_argument("--origin", required=True)
    p.add_argument("--listen-address", default="127.0.0.1")
    p.add_argument("--port", type=int, default=9192)
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(name)s: %(message)s")
    logging.getLogger("miio").setLevel(logging.CRITICAL)
    heater = Heater(args.host, args.token_file, timeout=3)
    controller = Controller(heater, args.state_file)
    server = Server((args.listen_address, args.port), controller, args.origin, Path(args.page).read_bytes())

    def stop(*_):
        server.stopping.set()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    server.worker.start()
    try:
        server.serve_forever(poll_interval=0.25)
    finally:
        server.stopping.set()
        server.worker.join(timeout=12)
        server.server_close()


if __name__ == "__main__":
    main()

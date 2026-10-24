"""Local low-heat MIoT control using Qingping feedback and time-proportional PI."""

from __future__ import annotations

import argparse
import copy
import hashlib
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
from urllib.request import urlopen

from miio import Device
from prometheus_client import CollectorRegistry, CONTENT_TYPE_LATEST, generate_latest
from prometheus_client.core import CounterMetricFamily, GaugeMetricFamily, InfoMetricFamily
from prometheus_client.parser import text_string_to_metric_families

MODEL = "xiaomi.heater.ma3"
VERSION = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()[:12]
PAGE = "/iot/heater_ma3.html"
API = "/iot/heater_ma3/api/"
MIN_SWITCH_SECONDS = 900
SENSOR_MAX_AGE = 60
POLL_SECONDS = 15
LOW_HEAT = 1  # MIoT heater service 2, property 7: 0=normal, 1=low, 2=high.
PROPERTIES = {"power": (2, 1), "fault": (2, 2), "status": (2, 3), "heat_level": (2, 7)}
LOG = logging.getLogger("heater-controller")


def event(name, **fields):
    LOG.info(json.dumps({"event": name, "version": VERSION, **fields}, ensure_ascii=False, allow_nan=False))


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def validate_settings(setpoint, tolerance):
    if not finite(setpoint) or not 5 <= setpoint <= 30:
        raise ValueError("目标温度须为 5～30°C")
    if not finite(tolerance) or not 0 < tolerance <= 5:
        raise ValueError("允许偏差须大于 0 且不超过 5°C")


class StateError(RuntimeError):
    pass


class Heater:
    def __init__(self, host, token_file, timeout):
        token = Path(token_file).read_text().strip()
        if not re.fullmatch(r"[0-9a-fA-F]{32}", token):
            raise ValueError("Invalid token credential")
        self.device = Device(host, token, timeout=timeout, handshake_timeout=timeout)
        self.device.retry_count = 0
        self.validated = False

    def validate(self):
        if not self.validated:
            if self.device.info().model != MODEL:
                raise ValueError("Unexpected device model")
            self.validated = True

    def read(self):
        self.validate()
        query = [{"did": name, "siid": siid, "piid": piid} for name, (siid, piid) in PROPERTIES.items()]
        response = self.device.send("get_properties", query, retry_count=0)
        values = {item["did"]: item.get("value") for item in response
                  if item.get("code") == 0 and item.get("did") in PROPERTIES}
        if set(values) != set(PROPERTIES) or type(values["power"]) is not bool:
            raise ValueError("Incomplete device status")
        if any(type(values[name]) is not int for name in ("heat_level", "fault", "status")):
            raise ValueError("Invalid device status")
        return values

    def set_power(self, enabled):
        self.validate()
        # The switch is the only property this controller may write.
        response = self.device.send("set_properties", [
            {"did": "power", "siid": 2, "piid": 1, "value": enabled}
        ], retry_count=0)
        if len(response) != 1 or response[0].get("code") != 0:
            raise ValueError("Device rejected switch command")


class Qingping:
    """Read the existing local exporter, preserving its acquisition timestamp."""

    def __init__(self, url):
        self.url = url

    def read(self):
        with urlopen(self.url, timeout=3) as response:
            body = response.read(1_000_000).decode("utf-8")
        names = {"miio_qingping_temperature_celsius", "miio_qingping_last_success_timestamp_seconds"}
        values = {sample.name: sample.value
                  for family in text_string_to_metric_families(body)
                  for sample in family.samples if sample.name in names and not sample.labels}
        if set(values) != names or not all(finite(value) for value in values.values()):
            raise ValueError("Missing or invalid Qingping reading")
        temperature = values["miio_qingping_temperature_celsius"]
        timestamp = values["miio_qingping_last_success_timestamp_seconds"]
        if not -30 <= temperature <= 60 or timestamp <= 0:
            raise ValueError("Invalid Qingping reading")
        return temperature, timestamp


class PI:
    def __init__(self, kp=0.25, ki=0.25 / 3600):
        if not all(finite(v) and v >= 0 for v in (kp, ki)):
            raise ValueError("PI gains must be finite and nonnegative")
        self.kp, self.ki = kp, ki
        self.reset()

    def reset(self):
        self.proportional = self.integral = self.output = 0.0

    def update(self, error, dt):
        self.proportional = self.kp * error
        delta = self.ki * error * dt
        raw = self.proportional + self.integral
        # Do not integrate further into saturation; always allow unwinding.
        if not ((raw >= 1 and delta > 0) or (raw <= 0 and delta < 0)):
            self.integral = min(1.0, max(0.0, self.integral + delta))
        self.output = min(1.0, max(0.0, self.proportional + self.integral))
        return self.output


class Controller:
    """One worker owns control/state; HTTP and metrics only read snapshots."""

    def __init__(self, heater, sensor, state_file, *, kp=0.25, ki=0.25 / 3600, clock=time):
        self.heater, self.sensor, self.state_file, self.clock = heater, sensor, Path(state_file), clock
        self.pi = PI(kp, ki)
        self.state = {"version": 2, "enabled": False, "setpoint": 23.0, "tolerance": 1.0,
                      "last_power": None, "last_transition": None, "pending_off": None}
        if self.state_file.exists():
            saved = json.loads(self.state_file.read_text())
            if set(saved) == {"enabled", "phase", "next_at", "pending"}:
                # Replace the old timer, preserving only enablement and an owed shutdown.
                if type(saved["enabled"]) is not bool:
                    raise ValueError("Invalid legacy controller state")
                self.state.update(enabled=saved["enabled"],
                                  pending_off="manual" if saved["pending"] is False else None)
                event("state_migrated", enabled=saved["enabled"])
            else:
                if set(saved) != set(self.state) or saved["version"] != 2:
                    raise ValueError("Invalid controller state")
                self.state = saved
            self._validate_state()
        remaining = 0 if self.state["last_transition"] is None else min(
            MIN_SWITCH_SECONDS, max(0, self.state["last_transition"] + MIN_SWITCH_SECONDS - clock.time()))
        self.lock_until = clock.monotonic() + remaining
        self.actual = None
        self.heater_ok = False
        self.last_success = None
        self.temperature = self.sensor_timestamp = None
        self.sensor_fetch_ok = False
        self.next_poll = self.next_decision = 0
        self.last_tick = self.last_pi = None
        self.balance = 0.0
        self.manual_request = None
        self.reason, self.error = "disabled", None
        self.on_seconds = self.outside_seconds = 0.0
        self.transitions = {source: 0 for source in ("automatic", "manual", "protection", "external")}
        self.failures = {source: 0 for source in ("heater_read", "sensor_read", "switch")}
        self.snapshot_lock = threading.Lock()
        self._publish()
        event("startup", enabled=self.state["enabled"], setpoint=self.state["setpoint"],
              tolerance=self.state["tolerance"], kp=kp, ki=ki,
              min_switch_seconds=MIN_SWITCH_SECONDS, sensor_max_age_seconds=SENSOR_MAX_AGE)

    def _validate_state(self):
        s = self.state
        validate_settings(s["setpoint"], s["tolerance"])
        if type(s["enabled"]) is not bool or (s["last_power"] is not None and type(s["last_power"]) is not bool):
            raise ValueError("Invalid saved switch state")
        if s["last_transition"] is not None and not finite(s["last_transition"]):
            raise ValueError("Invalid saved transition")
        if s["pending_off"] not in (None, "manual", "automatic", "protection"):
            raise ValueError("Invalid saved shutdown")

    def _save(self):
        try:
            self._write_state()
        except OSError as exc:
            raise StateError("Cannot persist controller state") from exc

    def _write_state(self):
        tmp = self.state_file.with_suffix(".tmp")
        with open(tmp, "w", opener=lambda p, flags: os.open(p, flags, 0o600)) as f:
            json.dump(self.state, f, allow_nan=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.state_file)
        fd = os.open(self.state_file.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def _reset_control(self):
        self.pi.reset()
        self.balance = 0.0
        self.last_pi = None
        self.next_decision = 0

    def set_automation(self, enabled):
        if enabled == self.state["enabled"]:
            return
        self.state["enabled"] = enabled
        self._reset_control()
        if not enabled:
            self.state["pending_off"] = "manual"
        self._save()
        self.next_poll = 0
        event("automation_changed", enabled=enabled)

    def set_settings(self, setpoint, tolerance):
        validate_settings(setpoint, tolerance)
        if setpoint != self.state["setpoint"]:
            self._reset_control()
        self.state.update(setpoint=setpoint, tolerance=tolerance)
        self._save()
        self.next_poll = 0
        event("settings_changed", setpoint=setpoint, tolerance=tolerance, kp=self.pi.kp, ki=self.pi.ki)

    def set_manual_power(self, power):
        self.manual_request = power
        self._reset_control()
        if not power:
            self.state["pending_off"] = "manual"
            self._save()
        self.next_poll = 0
        event("manual_requested", power=power)

    def _read_heater(self, source="external"):
        actual = self.heater.read()
        old_power = self.state["last_power"]
        self.actual, self.heater_ok, self.last_success = actual, True, self.clock.time()
        if actual["power"] != old_power:
            self.state["last_power"] = actual["power"]
            if old_power is not None:
                self.state["last_transition"] = self.clock.time()
                self.lock_until = self.clock.monotonic() + MIN_SWITCH_SECONDS
                self.next_decision = self.lock_until
                self.transitions[source] += 1
                if source != "automatic":
                    self.balance = 0.0
                event("transition_observed", source=source, power=actual["power"],
                      observed_at=self.state["last_transition"], heat_level=actual["heat_level"])
            self._save()

    def _switch(self, power, source):
        if power and (not self.heater_ok or self.actual["heat_level"] != LOW_HEAT or self.actual["fault"] != 0):
            return False
        if self.heater_ok and self.actual["power"] is power:
            if not power and self.state["pending_off"] is not None:
                self.state["pending_off"] = None
                self._save()
            return True
        if source == "automatic" and self.clock.monotonic() < self.lock_until:
            self.reason = "minimum_interval"
            return False
        if not power:
            self.state["pending_off"] = source
            self._save()  # Persist shutdown intent before any device command.
        event("switch_requested", source=source, power=power, temperature=self.temperature,
              setpoint=self.state["setpoint"], demand=self.pi.output, balance_seconds=self.balance)
        command_error = None
        try:
            self.heater.set_power(power)
        except Exception as exc:
            command_error = type(exc).__name__
        # Even a lost command acknowledgement may have changed the real switch.
        try:
            self._read_heater(source)
        except StateError:
            raise
        except Exception as exc:
            self.heater_ok = False
            command_error = type(exc).__name__
        if self.heater_ok and self.actual["power"] is power:
            if not power:
                self.state["pending_off"] = None
                self._save()
            event("switch_confirmed", source=source, power=power, acknowledgement_error=command_error)
            return True
        self.failures["switch"] += 1
        self.error = "设备开关未确认，等待重试"
        if power and not self.heater_ok:
            # Resolve an ambiguous turn-on by shutting down, never replay an old ON.
            self.state["pending_off"] = "protection"
            self._save()
        event("switch_unconfirmed", source=source, power=power, error_type=command_error)
        return False

    def sensor_age(self):
        return None if self.sensor_timestamp is None else self.clock.time() - self.sensor_timestamp

    def sensor_valid(self):
        age = self.sensor_age()
        return age is not None and 0 <= age <= SENSOR_MAX_AGE

    def _problem(self):
        if not self.heater_ok:
            return "heater_unavailable", "电暖气状态读取失败"
        if self.actual["heat_level"] != LOW_HEAT:
            return "not_low_heat", "仅允许低档，请在设备上配置低档"
        if self.actual["fault"] != 0:
            return "device_fault", "电暖气报告故障"
        if not self.sensor_valid():
            return "sensor_stale", "青萍温度无效或超过 60 秒未成功采集"
        return None

    def tick(self):
        if self.clock.monotonic() < self.next_poll:
            return
        started = self.clock.monotonic()
        elapsed = 0 if self.last_tick is None else max(0, min(started - self.last_tick, 2 * POLL_SECONDS))
        self.last_tick = started
        previous_power = self.actual["power"] if self.heater_ok else None
        if previous_power:
            self.on_seconds += elapsed
        if self.state["enabled"] and self.sensor_valid() and abs(self.state["setpoint"] - self.temperature) > self.state["tolerance"]:
            self.outside_seconds += elapsed
        # Account for delivered switch-on time, not merely successful commands.
        if self.last_pi is not None and previous_power is not None:
            self.balance = max(-MIN_SWITCH_SECONDS, min(MIN_SWITCH_SECONDS,
                self.balance + (self.pi.output - int(previous_power)) * elapsed))
        try:
            self._read_heater()
        except StateError:
            raise
        except Exception as exc:
            self.heater_ok = False
            self.failures["heater_read"] += 1
            event("read_failed", source="heater", error_type=type(exc).__name__)
        try:
            temperature, timestamp = self.sensor.read()
            if not finite(temperature) or not finite(timestamp) or not -30 <= temperature <= 60 or timestamp <= 0:
                raise ValueError("Invalid sensor sample")
            self.temperature, self.sensor_timestamp, self.sensor_fetch_ok = temperature, timestamp, True
        except Exception as exc:
            self.sensor_fetch_ok = False
            self.failures["sensor_read"] += 1
            event("read_failed", source="qingping", error_type=type(exc).__name__)
        self.error = None
        manual, self.manual_request = self.manual_request, None
        problem = self._problem()
        if self.state["enabled"] and problem:
            self.reason, self.error = problem
            self._reset_control()
            self._switch(False, "protection")
        elif manual is True:
            if not self.heater_ok or self.actual["heat_level"] != LOW_HEAT or self.actual["fault"] != 0:
                self.reason, self.error = "manual_rejected", "无法开启：须确认设备无故障且处于低档"
            elif self.state["pending_off"] is not None:
                self.reason, self.error = "shutdown_pending", "请等待此前关机得到确认"
                self._switch(False, self.state["pending_off"])
            else:
                self.reason = "manual"
                self._switch(True, "manual")
        elif self.state["pending_off"] is not None:
            self.reason = "shutdown_pending"
            self._switch(False, self.state["pending_off"])
        elif not self.state["enabled"]:
            self.reason = "disabled"
            self._reset_control()
        else:
            self._regulate()
        self.next_poll = self.clock.monotonic() + POLL_SECONDS
        self._publish()
        event("control_sample", enabled=self.state["enabled"], reason=self.reason,
              temperature=self.temperature, sensor_age_seconds=self.sensor_age(),
              setpoint=self.state["setpoint"], tolerance=self.state["tolerance"],
              error_celsius=None if self.temperature is None else self.state["setpoint"] - self.temperature,
              p=self.pi.proportional, i=self.pi.integral, demand=self.pi.output,
              balance_seconds=self.balance, power=None if self.actual is None else self.actual["power"],
              heater_ok=self.heater_ok, heat_level=None if self.actual is None else self.actual["heat_level"],
              switch_wait_seconds=max(0, self.lock_until - self.clock.monotonic()),
              pending_off=self.state["pending_off"])

    def _regulate(self):
        now = self.clock.monotonic()
        dt = 0 if self.last_pi is None else max(0, min(now - self.last_pi, 2 * POLL_SECONDS))
        self.last_pi = now
        demand = self.pi.update(self.state["setpoint"] - self.temperature, dt)
        if now < self.lock_until:
            self.reason = "minimum_interval"
            return
        # Extreme demands may terminate a slot once the actual dwell is satisfied.
        if demand in (0, 1):
            self.balance = 0.0
            desired = bool(demand)
        elif now < self.next_decision:
            self.reason = "holding_slot"
            return
        else:
            # Error diffusion: choose the next 15-minute block nearest to the
            # cumulative requested heating time. This also represents low duties.
            desired = self.balance + demand * MIN_SWITCH_SECONDS >= MIN_SWITCH_SECONDS / 2
        self.reason = "automatic_on" if desired else "automatic_off"
        self.next_decision = now + MIN_SWITCH_SECONDS
        if not self._switch(desired, "automatic"):
            self.reason = "switch_unconfirmed"
            self.next_decision = now + POLL_SECONDS

    def _publish(self):
        remaining = max(0, self.lock_until - self.clock.monotonic())
        with self.snapshot_lock:
            self.published = {
                **self.state, "device": copy.deepcopy(self.actual), "last_success": self.last_success,
                "heater_ok": self.heater_ok, "temperature": self.temperature,
                "sensor_timestamp": self.sensor_timestamp, "sensor_age_seconds": self.sensor_age(),
                "sensor_valid": self.sensor_valid(), "sensor_fetch_ok": self.sensor_fetch_ok,
                "kp": self.pi.kp, "ki": self.pi.ki, "p": self.pi.proportional, "i": self.pi.integral,
                "demand": self.pi.output, "balance_seconds": self.balance,
                "switch_wait_seconds": remaining, "min_switch_seconds": MIN_SWITCH_SECONDS,
                "reason": self.reason, "error": self.error,
                "observed_at": self.clock.time(), "version": VERSION,
                "on_seconds": self.on_seconds, "outside_seconds": self.outside_seconds,
                "transitions": self.transitions.copy(), "failures": self.failures.copy(),
            }

    def snapshot(self):
        with self.snapshot_lock:
            return copy.deepcopy(self.published)


class Metrics:
    def __init__(self, controller):
        self.controller = controller

    def collect(self):
        s = self.controller.snapshot()
        prefix = "heater_pi_"
        yield InfoMetricFamily(prefix + "build", "Controller implementation", value={"version": VERSION, "algorithm": "PI"})
        gauges = {
            "enabled": (s["enabled"], "Whether automatic PI control is enabled"),
            "setpoint_celsius": (s["setpoint"], "Requested room temperature"),
            "tolerance_celsius": (s["tolerance"], "Allowed deviation for evaluation, not a hard limit"),
            "temperature_celsius": (s["temperature"], "Latest Qingping temperature, inspect sensor_valid"),
            "sensor_last_success_timestamp_seconds": (s["sensor_timestamp"], "Qingping acquisition timestamp"),
            "sensor_age_seconds": (s["sensor_age_seconds"], "Age of the Qingping reading at the last control sample"),
            "sensor_valid": (s["sensor_valid"], "Whether the sensor sample is at most 60 seconds old"),
            "sensor_fetch_ok": (s["sensor_fetch_ok"], "Whether the last exporter request succeeded"),
            "heater_up": (s["heater_ok"], "Whether the most recent heater read succeeded"),
            "heater_last_success_timestamp_seconds": (s["last_success"], "Last successful heater status read"),
            "sample_timestamp_seconds": (s["observed_at"], "Last controller sample timestamp"),
            "kp": (s["kp"], "Proportional gain per degree Celsius"),
            "ki": (s["ki"], "Integral gain per degree Celsius per second"),
            "proportional": (s["p"], "Proportional contribution to duty"),
            "integral": (s["i"], "Integral contribution to duty"),
            "demand_ratio": (s["demand"], "Requested duty ratio, not measured power"),
            "balance_seconds": (s["balance_seconds"], "Requested minus delivered switch-on time"),
            "switch_wait_seconds": (s["switch_wait_seconds"], "Remaining minimum dwell at last sample"),
            "min_switch_seconds": (MIN_SWITCH_SECONDS, "Minimum interval between automatic switches"),
            "last_transition_timestamp_seconds": (s["last_transition"], "Last observed switch state change"),
            "shutdown_pending": (s["pending_off"] is not None, "Whether an OFF intent remains unconfirmed"),
            "error_celsius": (None if s["temperature"] is None else s["setpoint"] - s["temperature"], "Setpoint minus measured temperature"),
        }
        for key, description in (("power", "Observed switch, not measured heating"),
                                 ("heat_level", "Observed heat level; low is 1"), ("fault", "Observed device fault code")):
            gauges[key] = (None if s["device"] is None else s["device"][key], description)
        for name, (value, description) in gauges.items():
            yield GaugeMetricFamily(prefix + name, description, value=float("nan") if value is None else float(value))
        reason = GaugeMetricFamily(prefix + "state", "Current controller decision", labels=["reason"])
        reason.add_metric([s["reason"]], 1)
        yield reason
        for key, description in (("transitions", "Observed physical switch transitions"), ("failures", "Failed reads or unconfirmed switches")):
            counter = CounterMetricFamily(prefix + key, description, labels=["source"])
            for source, count in s[key].items():
                counter.add_metric([source], count)
            yield counter
        yield CounterMetricFamily(prefix + "on_seconds", "Observed switch-on seconds; excludes unobserved gaps", value=s["on_seconds"])
        yield CounterMetricFamily(prefix + "outside_seconds", "Enabled time outside the requested band with valid samples", value=s["outside_seconds"])


@dataclass
class Command:
    action: str
    data: dict
    done: threading.Event = field(default_factory=threading.Event)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, controller, origin, page):
        self.controller, self.origin, self.page = controller, origin, page
        self.csrf = secrets.token_urlsafe(32)
        self.commands = queue.Queue(maxsize=16)
        self.stopping = threading.Event()
        self.registry = CollectorRegistry()
        self.registry.register(Metrics(controller))
        self.worker = threading.Thread(target=self.run_worker, daemon=True)
        super().__init__(address, Handler)

    def run_worker(self):
        while not self.stopping.is_set():
            try:
                cmd = self.commands.get(timeout=0.25)
            except queue.Empty:
                cmd = None
            try:
                if cmd is not None:
                    if cmd.action == "automation":
                        self.controller.set_automation(cmd.data["enabled"])
                    elif cmd.action == "settings":
                        self.controller.set_settings(**cmd.data)
                    elif cmd.action == "power":
                        self.controller.set_manual_power(cmd.data["power"])
                self.controller.tick()
            except Exception:
                LOG.critical("Controller worker failed; restarting")
                os._exit(1)
            if cmd is not None:
                cmd.done.set()


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, data, content_type="application/json; charset=utf-8"):
        if isinstance(data, dict):
            data = json.dumps(data, ensure_ascii=False, allow_nan=False).encode()
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
        elif self.path == "/metrics":
            self.reply(200, generate_latest(self.server.registry), CONTENT_TYPE_LATEST)
        else:
            self.reply(404, {"error": "Not found"})

    def do_POST(self):
        action = self.path.removeprefix(API)
        if self.path != API + action or action not in ("automation", "settings", "power"):
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
                raise ValueError("Expected a JSON object")
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                raise ValueError("Expected a JSON object")
            if action == "settings":
                if set(data) != {"setpoint", "tolerance"}:
                    raise ValueError("Expected setpoint and tolerance")
                validate_settings(**data)
            else:
                key = "enabled" if action == "automation" else "power"
                if set(data) != {key} or type(data[key]) is not bool:
                    raise ValueError("Expected a boolean " + key)
        except (ValueError, UnicodeDecodeError) as exc:
            self.reply(400, {"error": str(exc)})
            return
        cmd = Command(action, data)
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
        pass  # Never log request headers or bodies.


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", required=True)
    p.add_argument("--token-file", required=True)
    p.add_argument("--state-file", required=True)
    p.add_argument("--page", required=True)
    p.add_argument("--origin", required=True)
    p.add_argument("--qingping-url", default="http://127.0.0.1:9191/metrics")
    p.add_argument("--kp", type=float, default=0.25)
    p.add_argument("--ki", type=float, default=0.25 / 3600)
    p.add_argument("--listen-address", default="127.0.0.1")
    p.add_argument("--port", type=int, default=9192)
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    logging.getLogger("miio").setLevel(logging.CRITICAL)
    heater = Heater(args.host, args.token_file, timeout=3)
    controller = Controller(heater, Qingping(args.qingping_url), args.state_file, kp=args.kp, ki=args.ki)
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

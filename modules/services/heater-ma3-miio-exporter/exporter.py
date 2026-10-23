"""Read-only exporter for all 21 xiaomi.heater.ma3 MIoT properties.

Specification: https://miot-spec.org/miot-spec-v2/instance?type=
urn:miot-spec-v2:device:heater:0000A01A:xiaomi-ma3:1
"""

from __future__ import annotations

import argparse
import logging
import math
import re
import signal
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from miio import Device
from prometheus_client import CollectorRegistry, Counter, Gauge, start_http_server

MODEL = "xiaomi.heater.ma3"
PREFIX = "miio_heater_ma3_"


@dataclass(frozen=True)
class Property:
    name: str
    siid: int
    piid: int
    kind: str
    description: str
    scale: float = 1


PROPERTIES = (
    Property("manufacturer", 1, 1, "string", "Manufacturer"),
    Property("model", 1, 2, "string", "MIoT model"),
    Property("device_id", 1, 3, "string", "Device ID"),
    Property("firmware_version", 1, 4, "string", "Firmware version"),
    Property("serial_number", 1, 5, "string", "Serial number"),
    Property("power_on", 2, 1, "bool", "Heater switch (1=on)"),
    Property("fault_code", 2, 2, "int", "Fault (0=none, 1=temperature sensor error)"),
    Property("status", 2, 3, "int", "Operating state (1=idle, 2=busy, 3=delay)"),
    Property("target_temperature_celsius", 2, 5, "float", "Target temperature in degrees Celsius"),
    Property("temperature_celsius", 2, 6, "float", "Temperature reported by heater service in degrees Celsius"),
    Property("heat_level", 2, 7, "int", "Heat level setting (0=normal, 1=low, 2=high), not measured watts"),
    Property("environment_temperature_celsius", 4, 7, "float", "Environment temperature in degrees Celsius"),
    Property("child_lock", 5, 1, "bool", "Physical controls locked (1=locked)"),
    Property("buzzer_enabled", 6, 1, "bool", "Audible prompts enabled"),
    Property("delay_enabled", 7, 1, "bool", "Device delay function enabled"),
    Property("delay_seconds", 7, 2, "int", "Configured device delay in seconds", 3600),
    Property("delay_remaining_seconds", 7, 3, "int", "Remaining device delay in seconds", 3600),
    Property("sleep_settings", 8, 1, "string", "Raw custom sleep configuration"),
    Property("sleep_enabled", 8, 2, "bool", "Custom sleep enabled"),
    Property("sleep_active", 8, 3, "bool", "Custom sleep active"),
    Property("screen_on", 9, 1, "bool", "Screen light enabled"),
)


def validate_value(prop, value):
    if prop.kind == "string":
        if not isinstance(value, str) or len(value) > 8192:
            raise ValueError("Invalid string property")
        return value
    if prop.kind == "bool":
        if type(value) is not bool:
            raise ValueError("Invalid boolean property")
        return int(value)
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError("Invalid numeric property")
    if prop.kind == "int" and (int(value) != value or not 0 <= value <= 255):
        raise ValueError("Invalid integer property")
    return value


class Metrics:
    def __init__(self, registry):
        def gauge(name, help, labels=()):
            return Gauge(PREFIX + name, help, labels, registry=registry)

        self.numeric = {p.name: gauge(p.name, p.description) for p in PROPERTIES if p.kind != "string"}
        for g in self.numeric.values():
            g.set(float("nan"))
        labels = ("property", "siid", "piid")
        self.property_up = gauge("property_up", "Whether this property was read successfully in the latest poll", labels)
        self.property_last_success = gauge("property_last_success_timestamp_seconds", "Last successful property read", labels)
        self.strings = gauge("property_info", "Current string property; value is a label", (*labels, "value"))
        self.string_values = {}
        self.device_info = gauge("device_info", "Device protocol information", ("model", "mac", "firmware_version", "hardware_version", "miio_version"))
        self.info_labels = None
        self.uptime = gauge("uptime_seconds", "Device uptime reported by miIO.info in seconds")
        self.memory = gauge("free_memory_bytes", "Free memory reported by miIO.info in bytes")
        self.rssi = gauge("wifi_signal_dbm", "Wi-Fi RSSI reported by miIO.info in dBm")
        self.info_up = gauge("info_up", "Whether miIO.info succeeded in the latest poll")
        self.up = gauge("up", "Whether miIO.info and all 21 properties succeeded in the latest poll")
        self.duration = gauge("poll_duration_seconds", "Duration of the latest poll")
        self.last_success = gauge("last_success_timestamp_seconds", "Last complete successful poll")
        self.errors = Counter(PREFIX + "poll_errors", "Number of incomplete or failed polls", registry=registry)
        self.up.set(0)
        self.info_up.set(0)
        for g in (self.uptime, self.memory, self.rssi):
            g.set(float("nan"))
        for p in PROPERTIES:
            self.property_up.labels(p.name, p.siid, p.piid).set(0)

    def record_property(self, prop, value, timestamp):
        labels = (prop.name, prop.siid, prop.piid)
        value = validate_value(prop, value)
        if prop.kind == "string":
            previous = self.string_values.get(prop.name)
            if previous is not None and previous != value:
                self.strings.remove(*labels, previous)
            self.strings.labels(*labels, value).set(1)
            self.string_values[prop.name] = value
        else:
            self.numeric[prop.name].set(value * prop.scale)
        self.property_last_success.labels(*labels).set(timestamp)
        self.property_up.labels(*labels).set(1)

    def record_info(self, info):
        labels = tuple(str(info.get(k, "")) for k in ("model", "mac", "fw_ver", "hw_ver", "miio_ver"))
        if self.info_labels is not None and labels != self.info_labels:
            self.device_info.remove(*self.info_labels)
        self.device_info.labels(*labels).set(1)
        self.info_labels = labels
        for gauge, value in ((self.uptime, info.get("life")), (self.memory, info.get("mmfree")), (self.rssi, info.get("ap", {}).get("rssi"))):
            gauge.set(value if type(value) in (int, float) and math.isfinite(value) else float("nan"))
        self.info_up.set(1)


class Poller:
    def __init__(self, device, metrics, logger=None):
        self.device, self.metrics = device, metrics
        self.logger = logger or logging.getLogger("heater-ma3-miio-exporter")
        self.verified = False

    def poll_once(self):
        started = time.monotonic()
        m = self.metrics
        for p in PROPERTIES:
            m.property_up.labels(p.name, p.siid, p.piid).set(0)
        m.info_up.set(0)
        info_ok = False
        try:
            info = self.device.info(skip_cache=True).raw
            if info.get("model") != MODEL:
                self.verified = False
                raise ValueError("Unexpected device model")
            self.verified = True
            m.record_info(info)
            info_ok = True
        except Exception as exc:
            # Log exception types only: miIO.info responses may contain the token.
            self.logger.warning("Device information unavailable (%s)", type(exc).__name__)

        successes = set()
        if self.verified:
            for offset in range(0, len(PROPERTIES), 5):
                batch = PROPERTIES[offset:offset + 5]
                query = [{"did": p.name, "siid": p.siid, "piid": p.piid} for p in batch]
                try:
                    response = self.device.send("get_properties", query, retry_count=0)
                    if not isinstance(response, list):
                        raise ValueError("Invalid property response")
                    for p in batch:
                        matches = [item for item in response if isinstance(item, dict) and item.get("did") == p.name]
                        if len(matches) != 1:
                            continue
                        item = matches[0]
                        if item.get("code") != 0 or item.get("siid") != p.siid or item.get("piid") != p.piid:
                            continue
                        try:
                            m.record_property(p, item.get("value"), time.time())
                        except (ValueError, TypeError):
                            continue
                        successes.add(p.name)
                except Exception as exc:
                    self.logger.warning("Property batch unavailable (%s)", type(exc).__name__)

        complete = info_ok and len(successes) == len(PROPERTIES)
        m.duration.set(max(0, time.monotonic() - started))
        m.up.set(int(complete))
        if complete:
            m.last_success.set(time.time())
        else:
            m.errors.inc()
            self.logger.warning("Incomplete poll: %d/%d properties", len(successes), len(PROPERTIES))
        return complete


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--host", required=True)
    p.add_argument("--token-file", required=True)
    p.add_argument("--listen-address", default="127.0.0.1")
    p.add_argument("--port", type=int, default=9193)
    p.add_argument("--poll-interval", type=float, default=15)
    p.add_argument("--timeout", type=float, default=3)
    args = p.parse_args()
    if not math.isfinite(args.poll_interval) or not 0 < args.timeout < args.poll_interval or not 1 <= args.port <= 65535:
        p.error("Require 0 < timeout < poll-interval and a valid port")
    token = Path(args.token_file).read_text().strip()
    if not re.fullmatch(r"[0-9a-fA-F]{32}", token):
        p.error("Invalid token credential")
    logging.basicConfig(level=logging.INFO, format="%(name)s: %(message)s")
    logging.getLogger("miio").setLevel(logging.CRITICAL)
    device = Device(args.host, token, timeout=args.timeout, handshake_timeout=30)
    device.retry_count = 0
    registry = CollectorRegistry(auto_describe=True)
    poller = Poller(device, Metrics(registry))
    server, thread = start_http_server(args.port, addr=args.listen_address, registry=registry)
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    try:
        while not stop.is_set():
            started = time.monotonic()
            poller.poll_once()
            # A slow/offline device never causes a burst of catch-up requests.
            stop.wait(max(1, args.poll_interval - (time.monotonic() - started)))
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == "__main__":
    main()

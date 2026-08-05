"""Prometheus exporter for the Qingping Air Monitor Lite."""

from __future__ import annotations

import argparse
import logging
import math
import re
import signal
import threading
import time
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from miio import MiotDevice
from prometheus_client import CollectorRegistry, Counter, Gauge, start_http_server

MODEL = "cgllc.airm.cgd1st"
TOKEN_PATTERN = re.compile(r"[0-9a-fA-F]{32}")
MAC_PATTERN = re.compile(r"[0-9A-F]{12}")

# python-miio returns the mapping key in the response's `did` field. Keeping
# stable, descriptive keys here makes the response independent of list order.
PROPERTY_MAPPING: dict[str, dict[str, int]] = {
    "relative_humidity_percent": {"siid": 3, "piid": 1},
    "pm25_micrograms_per_cubic_meter": {"siid": 3, "piid": 4},
    "pm10_micrograms_per_cubic_meter": {"siid": 3, "piid": 5},
    "temperature_celsius": {"siid": 3, "piid": 7},
    "co2_parts_per_million": {"siid": 3, "piid": 8},
    "battery_level_percent": {"siid": 4, "piid": 1},
    "battery_charging_state": {"siid": 4, "piid": 2},
    "battery_voltage_millivolts": {"siid": 4, "piid": 3},
    "mac_address": {"siid": 8, "piid": 1},
}


class PollError(RuntimeError):
    """Raised when a device response cannot be exported safely."""


@dataclass(frozen=True)
class Reading:
    temperature_celsius: float
    relative_humidity_percent: float
    pm25_micrograms_per_cubic_meter: float
    pm10_micrograms_per_cubic_meter: float
    co2_parts_per_million: float
    battery_level_percent: float
    battery_voltage_millivolts: float
    battery_charging: float
    mac_address: str


def read_token(token_file: str | Path) -> str:
    """Read and validate a legacy miIO token without exposing it in argv."""

    token = Path(token_file).read_text(encoding="utf-8").strip()
    if TOKEN_PATTERN.fullmatch(token) is None:
        raise ValueError("miIO token must contain exactly 32 hexadecimal characters")
    return token.lower()


def redact_secrets(message: str, secrets: Iterable[str]) -> str:
    """Remove configured secrets from an error message before logging it."""

    redacted = message
    for secret in secrets:
        if secret:
            redacted = redacted.replace(secret, "<redacted>")
    return redacted


def _numeric_value(name: str, value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise PollError(f"property {name!r} returned a non-numeric value")
    numeric = float(value)
    if not math.isfinite(numeric):
        raise PollError(f"property {name!r} returned a non-finite value")
    return numeric


def _mac_address(value: Any) -> str:
    compact = str(value).strip().upper().replace(":", "").replace("-", "")
    if MAC_PATTERN.fullmatch(compact) is None:
        raise PollError("property 'mac_address' returned an invalid MAC address")
    return ":".join(compact[index : index + 2] for index in range(0, 12, 2))


def parse_response(response: Sequence[Mapping[str, Any]]) -> Reading:
    """Validate a complete MIoT response and turn it into one reading."""

    if not isinstance(response, Sequence) or isinstance(response, (str, bytes)):
        raise PollError("device response is not a property list")

    values: dict[str, Any] = {}
    failures: list[str] = []
    for item in response:
        if not isinstance(item, Mapping):
            raise PollError("device response contains a malformed property")

        did = item.get("did")
        if did not in PROPERTY_MAPPING:
            continue
        if did in values:
            raise PollError(f"device response contains duplicate property {did!r}")

        if item.get("code") != 0:
            failures.append(f"{did} (code {item.get('code')!r})")
            continue
        if "value" not in item:
            failures.append(f"{did} (missing value)")
            continue
        values[did] = item["value"]

    missing = sorted(set(PROPERTY_MAPPING) - set(values))
    if failures or missing:
        details = []
        if failures:
            details.append("failed: " + ", ".join(failures))
        if missing:
            details.append("missing: " + ", ".join(missing))
        raise PollError("invalid property response (" + "; ".join(details) + ")")

    charging_state = _numeric_value(
        "battery_charging_state", values["battery_charging_state"]
    )
    return Reading(
        temperature_celsius=_numeric_value(
            "temperature_celsius", values["temperature_celsius"]
        ),
        relative_humidity_percent=_numeric_value(
            "relative_humidity_percent", values["relative_humidity_percent"]
        ),
        pm25_micrograms_per_cubic_meter=_numeric_value(
            "pm25_micrograms_per_cubic_meter",
            values["pm25_micrograms_per_cubic_meter"],
        ),
        pm10_micrograms_per_cubic_meter=_numeric_value(
            "pm10_micrograms_per_cubic_meter",
            values["pm10_micrograms_per_cubic_meter"],
        ),
        co2_parts_per_million=_numeric_value(
            "co2_parts_per_million", values["co2_parts_per_million"]
        ),
        battery_level_percent=_numeric_value(
            "battery_level_percent", values["battery_level_percent"]
        ),
        battery_voltage_millivolts=_numeric_value(
            "battery_voltage_millivolts", values["battery_voltage_millivolts"]
        ),
        battery_charging=1.0 if charging_state == 1 else 0.0,
        mac_address=_mac_address(values["mac_address"]),
    )


class QingpingMetrics:
    """Own the Prometheus collectors and update them after a complete poll."""

    def __init__(self, registry: CollectorRegistry) -> None:
        self.temperature = Gauge(
            "miio_qingping_temperature_celsius",
            "Qingping temperature in degrees Celsius.",
            registry=registry,
        )
        self.humidity = Gauge(
            "miio_qingping_relative_humidity_percent",
            "Qingping relative humidity percentage.",
            registry=registry,
        )
        self.pm25 = Gauge(
            "miio_qingping_pm25_micrograms_per_cubic_meter",
            "Qingping PM2.5 concentration in micrograms per cubic metre.",
            registry=registry,
        )
        self.pm10 = Gauge(
            "miio_qingping_pm10_micrograms_per_cubic_meter",
            "Qingping PM10 concentration in micrograms per cubic metre.",
            registry=registry,
        )
        self.co2 = Gauge(
            "miio_qingping_co2_parts_per_million",
            "Qingping carbon dioxide concentration in parts per million.",
            registry=registry,
        )
        self.battery_level = Gauge(
            "miio_qingping_battery_level_percent",
            "Qingping battery level percentage.",
            registry=registry,
        )
        self.battery_voltage = Gauge(
            "miio_qingping_battery_voltage_millivolts",
            "Qingping battery voltage in millivolts.",
            registry=registry,
        )
        self.battery_charging = Gauge(
            "miio_qingping_battery_charging",
            "Whether Qingping reports charging state 1 (1 for yes, 0 otherwise).",
            registry=registry,
        )
        self.device_info = Gauge(
            "miio_qingping_device_info",
            "Static information about the Qingping device.",
            labelnames=("model", "mac"),
            registry=registry,
        )
        self.up = Gauge(
            "miio_qingping_up",
            "Whether the most recent Qingping poll succeeded.",
            registry=registry,
        )
        self.poll_errors = Counter(
            "miio_qingping_poll_errors",
            "Number of failed Qingping polls.",
            registry=registry,
        )
        self.last_success = Gauge(
            "miio_qingping_last_success_timestamp_seconds",
            "Unix timestamp of the most recent successful Qingping poll.",
            registry=registry,
        )
        self.poll_duration = Gauge(
            "miio_qingping_poll_duration_seconds",
            "Duration of the most recent Qingping poll.",
            registry=registry,
        )
        self._device_info_mac: str | None = None
        self.up.set(0)

    def record_success(
        self, reading: Reading, duration: float, timestamp: float
    ) -> None:
        self.temperature.set(reading.temperature_celsius)
        self.humidity.set(reading.relative_humidity_percent)
        self.pm25.set(reading.pm25_micrograms_per_cubic_meter)
        self.pm10.set(reading.pm10_micrograms_per_cubic_meter)
        self.co2.set(reading.co2_parts_per_million)
        self.battery_level.set(reading.battery_level_percent)
        self.battery_voltage.set(reading.battery_voltage_millivolts)
        self.battery_charging.set(reading.battery_charging)

        if self._device_info_mac not in (None, reading.mac_address):
            self.device_info.remove(MODEL, self._device_info_mac)
        self.device_info.labels(model=MODEL, mac=reading.mac_address).set(1)
        self._device_info_mac = reading.mac_address

        self.poll_duration.set(duration)
        self.last_success.set(timestamp)
        self.up.set(1)

    def record_failure(self, duration: float) -> None:
        self.poll_duration.set(duration)
        self.poll_errors.inc()
        self.up.set(0)


class Poller:
    """Fetch one complete device snapshot and update the metrics registry."""

    def __init__(
        self,
        device: Any,
        metrics: QingpingMetrics,
        logger: logging.Logger,
        *,
        secrets: Iterable[str] = (),
        monotonic_clock: Callable[[], float] = time.monotonic,
        wall_clock: Callable[[], float] = time.time,
    ) -> None:
        self.device = device
        self.metrics = metrics
        self.logger = logger
        self.secrets = tuple(secrets)
        self.monotonic_clock = monotonic_clock
        self.wall_clock = wall_clock

    def poll_once(self) -> bool:
        started = self.monotonic_clock()
        try:
            response = self.device.get_properties_for_mapping(
                max_properties=len(PROPERTY_MAPPING)
            )
            reading = parse_response(response)
        # Keep the long-running exporter healthy across python-miio, socket, and
        # response-validation failures; process-control exceptions derive from
        # BaseException and are deliberately not caught here.
        except Exception as error:  # noqa: BLE001
            duration = max(0.0, self.monotonic_clock() - started)
            self.metrics.record_failure(duration)
            message = redact_secrets(str(error), self.secrets)
            self.logger.warning("poll failed (%s): %s", type(error).__name__, message)
            return False

        duration = max(0.0, self.monotonic_clock() - started)
        self.metrics.record_success(reading, duration, self.wall_clock())
        self.logger.debug("poll succeeded in %.3f seconds", duration)
        return True


def positive_number(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed) or parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive number")
    return parsed


def port_number(value: str) -> int:
    parsed = int(value)
    if parsed < 1 or parsed > 65535:
        raise argparse.ArgumentTypeError("must be between 1 and 65535")
    return parsed


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Export Qingping Air Monitor Lite data to Prometheus."
    )
    parser.add_argument("--host", required=True, help="Device IP address or hostname.")
    parser.add_argument(
        "--token-file", required=True, help="File containing the 32-character token."
    )
    parser.add_argument("--listen-address", default="127.0.0.1")
    parser.add_argument("--port", type=port_number, default=9191)
    parser.add_argument("--poll-interval", type=positive_number, default=15.0)
    parser.add_argument("--timeout", type=positive_number, default=5.0)
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="INFO",
    )
    return parser


def run(arguments: argparse.Namespace) -> int:
    logging.basicConfig(
        level=getattr(logging, arguments.log_level),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    logger = logging.getLogger("qingping-miio-exporter")
    token = read_token(arguments.token_file)

    registry = CollectorRegistry(auto_describe=True)
    metrics = QingpingMetrics(registry)
    device = MiotDevice(
        arguments.host,
        token,
        model=MODEL,
        mapping=PROPERTY_MAPPING,
        timeout=arguments.timeout,
    )
    poller = Poller(
        device,
        metrics,
        logger,
        secrets=(token, token.upper()),
    )

    server, server_thread = start_http_server(
        arguments.port,
        addr=arguments.listen_address,
        registry=registry,
    )
    stop_event = threading.Event()

    def request_stop(signum: int, _frame: Any) -> None:
        logger.info("received signal %s, stopping", signum)
        stop_event.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    logger.info(
        "listening on http://%s:%d/metrics; polling %s every %.1f seconds",
        arguments.listen_address,
        arguments.port,
        arguments.host,
        arguments.poll_interval,
    )

    next_poll = time.monotonic()
    try:
        while not stop_event.is_set():
            poller.poll_once()
            next_poll += arguments.poll_interval
            delay = max(0.0, next_poll - time.monotonic())
            if delay == 0:
                next_poll = time.monotonic()
            stop_event.wait(delay)
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=5)

    return 0


def main() -> int:
    return run(build_argument_parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())

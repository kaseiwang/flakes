from __future__ import annotations

import logging
import tempfile
import unittest
from pathlib import Path

from prometheus_client import CollectorRegistry, generate_latest

import exporter


def valid_response() -> list[dict[str, object]]:
    values: dict[str, object] = {
        "relative_humidity_percent": 65,
        "pm25_micrograms_per_cubic_meter": 21,
        "pm10_micrograms_per_cubic_meter": 22,
        "temperature_celsius": 32.7618,
        "co2_parts_per_million": 418,
        "battery_level_percent": 98,
        "battery_charging_state": 1,
        "battery_voltage_millivolts": 4128,
        "mac_address": "CCB5D1315B8A",
    }
    return [{"did": did, "code": 0, "value": value} for did, value in values.items()]


class FakeDevice:
    def __init__(self, outcomes: list[object]) -> None:
        self.outcomes = outcomes
        self.max_properties: list[int] = []

    def get_properties_for_mapping(self, *, max_properties: int) -> object:
        self.max_properties.append(max_properties)
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


class ParseResponseTest(unittest.TestCase):
    def test_parses_complete_response_independent_of_order(self) -> None:
        reading = exporter.parse_response(list(reversed(valid_response())))

        self.assertEqual(reading.temperature_celsius, 32.7618)
        self.assertEqual(reading.relative_humidity_percent, 65)
        self.assertEqual(reading.pm25_micrograms_per_cubic_meter, 21)
        self.assertEqual(reading.pm10_micrograms_per_cubic_meter, 22)
        self.assertEqual(reading.co2_parts_per_million, 418)
        self.assertEqual(reading.battery_level_percent, 98)
        self.assertEqual(reading.battery_voltage_millivolts, 4128)
        self.assertEqual(reading.battery_charging, 1)
        self.assertEqual(reading.mac_address, "CC:B5:D1:31:5B:8A")

    def test_rejects_nonzero_property_code(self) -> None:
        response = valid_response()
        response[0]["code"] = -4004

        with self.assertRaisesRegex(exporter.PollError, "code -4004"):
            exporter.parse_response(response)

    def test_rejects_missing_property(self) -> None:
        response = [
            item for item in valid_response() if item["did"] != "co2_parts_per_million"
        ]

        with self.assertRaisesRegex(exporter.PollError, "co2_parts_per_million"):
            exporter.parse_response(response)

    def test_rejects_invalid_mac_address(self) -> None:
        response = valid_response()
        response[-1]["value"] = "not-a-mac"

        with self.assertRaisesRegex(exporter.PollError, "invalid MAC address"):
            exporter.parse_response(response)


class MetricsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = CollectorRegistry(auto_describe=True)
        self.metrics = exporter.QingpingMetrics(self.registry)

    def exposition(self) -> str:
        return generate_latest(self.registry).decode("utf-8")

    def test_exports_expected_metric_names_and_values(self) -> None:
        reading = exporter.parse_response(valid_response())
        self.metrics.record_success(reading, duration=0.25, timestamp=1234.5)
        output = self.exposition()

        expected_samples = (
            "miio_qingping_temperature_celsius 32.7618",
            "miio_qingping_relative_humidity_percent 65.0",
            "miio_qingping_pm25_micrograms_per_cubic_meter 21.0",
            "miio_qingping_pm10_micrograms_per_cubic_meter 22.0",
            "miio_qingping_co2_parts_per_million 418.0",
            "miio_qingping_battery_level_percent 98.0",
            "miio_qingping_battery_voltage_millivolts 4128.0",
            "miio_qingping_battery_charging 1.0",
            'miio_qingping_device_info{mac="CC:B5:D1:31:5B:8A",model="cgllc.airm.cgd1st"} 1.0',
            "miio_qingping_up 1.0",
            "miio_qingping_last_success_timestamp_seconds 1234.5",
            "miio_qingping_poll_duration_seconds 0.25",
        )
        for sample in expected_samples:
            self.assertIn(sample, output)

    def test_failure_keeps_last_reading_and_sets_health_metrics(self) -> None:
        device = FakeDevice(
            [valid_response(), RuntimeError("temporary device timeout")]
        )
        timestamps = iter((10.0, 10.2, 20.0, 20.5))
        poller = exporter.Poller(
            device,
            self.metrics,
            logging.getLogger("test.poller.failure"),
            monotonic_clock=lambda: next(timestamps),
            wall_clock=lambda: 1000.0,
        )

        self.assertTrue(poller.poll_once())
        self.assertFalse(poller.poll_once())
        output = self.exposition()

        self.assertIn("miio_qingping_temperature_celsius 32.7618", output)
        self.assertIn("miio_qingping_up 0.0", output)
        self.assertIn("miio_qingping_poll_errors_total 1.0", output)
        self.assertIn("miio_qingping_last_success_timestamp_seconds 1000.0", output)
        self.assertEqual(
            device.max_properties,
            [len(exporter.PROPERTY_MAPPING), len(exporter.PROPERTY_MAPPING)],
        )


class SecretHandlingTest(unittest.TestCase):
    def test_reads_and_validates_token_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory) / "token"
            token_file.write_text("A" * 32 + "\n", encoding="utf-8")

            self.assertEqual(exporter.read_token(token_file), "a" * 32)

            token_file.write_text("not-a-token\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "32 hexadecimal"):
                exporter.read_token(token_file)

    def test_redacts_token_from_poll_error_log(self) -> None:
        token = "0123456789abcdef0123456789abcdef"
        device = FakeDevice([RuntimeError(f"request using {token} failed")])
        registry = CollectorRegistry(auto_describe=True)
        metrics = exporter.QingpingMetrics(registry)
        poller = exporter.Poller(
            device,
            metrics,
            logging.getLogger("test.poller.secret"),
            secrets=(token,),
            monotonic_clock=lambda: 1.0,
        )

        with self.assertLogs("test.poller.secret", level="WARNING") as logs:
            self.assertFalse(poller.poll_once())

        output = "\n".join(logs.output)
        self.assertNotIn(token, output)
        self.assertIn("<redacted>", output)


if __name__ == "__main__":
    unittest.main()

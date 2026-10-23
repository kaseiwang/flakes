import importlib.util
import json
import logging
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

from prometheus_client import CollectorRegistry, generate_latest

import exporter


class FakeDevice:
    def __init__(self):
        self.calls = []
        self.fail_info = False
        self.fail_batch = False
        self.bad_property = None
        self.duplicate = None
        self.model = exporter.MODEL
        self.strings = {p.name: f"example-{p.name}" for p in exporter.PROPERTIES if p.kind == "string"}
        self.strings["model"] = exporter.MODEL
        self.strings["sleep_settings"] = '{sleepStage:[{t:22,d:1.5}],repeat:8}'

    def info(self, **kwargs):
        if self.fail_info:
            raise RuntimeError("sensitive-token-and-response")
        return SimpleNamespace(raw={"model": self.model, "mac": "AA:BB:CC:DD:EE:FF", "fw_ver": "1.1.3",
                                    "hw_ver": "ESP32C3", "miio_ver": "0.0.9", "token": "sensitive-token-and-response",
                                    "life": 1000, "mmfree": 12345, "ap": {"rssi": -45}})

    def send(self, command, query, **kwargs):
        self.calls.append((command, query))
        if self.fail_batch and query[0]["siid"] == 1:
            raise TimeoutError("sensitive-token-and-response")
        response = []
        for q in query:
            p = next(p for p in exporter.PROPERTIES if p.name == q["did"])
            value = self.strings[p.name] if p.kind == "string" else (True if p.kind == "bool" else (20.5 if p.kind == "float" else 1))
            item = {**q, "code": -4004 if p.name == self.bad_property else 0, "value": value}
            response.append(item)
            if p.name == self.duplicate:
                response.append(item)
        return response


class ExporterTests(unittest.TestCase):
    def setUp(self):
        self.registry = CollectorRegistry()
        self.m = exporter.Metrics(self.registry)
        self.d = FakeDevice()
        self.logger = Mock(spec=logging.Logger)
        self.poller = exporter.Poller(self.d, self.m, self.logger)

    def metric(self, name, labels=None):
        return self.registry.get_sample_value(exporter.PREFIX + name, labels or {})

    def test_complete_snapshot_exports_every_property_read_only(self):
        self.assertTrue(self.poller.poll_once())
        self.assertEqual(self.metric("up"), 1)
        self.assertEqual(self.metric("uptime_seconds"), 1000)
        self.assertEqual(self.metric("free_memory_bytes"), 12345)
        self.assertEqual(self.metric("wifi_signal_dbm"), -45)
        self.assertEqual(self.metric("delay_seconds"), 3600)
        self.assertEqual(self.metric("delay_remaining_seconds"), 3600)
        self.assertEqual(sum(len(q) for _, q in self.d.calls), 21)
        self.assertTrue(all(cmd == "get_properties" and len(q) <= 5 for cmd, q in self.d.calls))
        for p in exporter.PROPERTIES:
            labels = {"property": p.name, "siid": str(p.siid), "piid": str(p.piid)}
            self.assertEqual(self.metric("property_up", labels), 1)
            if p.kind == "string":
                labels["value"] = self.d.strings[p.name]
                self.assertEqual(self.metric("property_info", labels), 1)
            else:
                self.assertIsNotNone(self.metric(p.name))
        self.assertNotIn("sensitive-token", generate_latest(self.registry).decode())

    def test_one_failed_property_preserves_others_and_marks_old_value(self):
        self.poller.poll_once()
        previous = self.metric("last_success_timestamp_seconds")
        self.d.bad_property = "screen_on"
        self.assertFalse(self.poller.poll_once())
        self.assertEqual(self.metric("screen_on"), 1)
        self.assertEqual(self.metric("property_up", {"property":"screen_on","siid":"9","piid":"1"}), 0)
        self.assertEqual(self.metric("property_up", {"property":"power_on","siid":"2","piid":"1"}), 1)
        self.assertEqual(self.metric("poll_errors_total"), 1)
        self.assertEqual(self.metric("last_success_timestamp_seconds"), previous)

    def test_duplicate_response_is_not_accepted(self):
        self.d.duplicate = "power_on"
        self.assertFalse(self.poller.poll_once())
        self.assertEqual(self.metric("property_up", {"property":"power_on","siid":"2","piid":"1"}), 0)

    def test_failed_batch_does_not_block_later_properties(self):
        self.d.fail_batch = True
        self.assertFalse(self.poller.poll_once())
        self.assertEqual(self.metric("property_up", {"property":"screen_on","siid":"9","piid":"1"}), 1)
        self.assertNotIn("sensitive-token", str(self.logger.mock_calls))

    def test_info_failure_before_identity_verification_sends_no_queries(self):
        self.d.fail_info = True
        self.assertFalse(self.poller.poll_once())
        self.assertEqual(self.d.calls, [])
        self.assertNotIn("sensitive-token", str(self.logger.mock_calls))

    def test_info_failure_after_verified_identity_retains_property_collection(self):
        self.poller.poll_once()
        self.d.fail_info = True
        self.assertFalse(self.poller.poll_once())
        self.assertEqual(self.metric("info_up"), 0)
        self.assertEqual(self.metric("property_up", {"property":"power_on","siid":"2","piid":"1"}), 1)

    def test_wrong_model_blocks_queries_even_after_previous_success(self):
        self.poller.poll_once()
        self.d.calls.clear()
        self.d.model = "other.device"
        self.assertFalse(self.poller.poll_once())
        self.assertEqual(self.d.calls, [])

    def test_changed_string_removes_previous_label_series(self):
        self.poller.poll_once()
        old = self.d.strings["sleep_settings"]
        self.d.strings["sleep_settings"] = "new-settings"
        self.poller.poll_once()
        labels = {"property":"sleep_settings","siid":"8","piid":"1","value":old}
        self.assertIsNone(self.metric("property_info", labels))
        labels["value"] = "new-settings"
        self.assertEqual(self.metric("property_info", labels), 1)

    def test_value_validation(self):
        for name, bad in [("power_on",1),("status",1.2),("fault_code",-1),("temperature_celsius",float("nan")),("sleep_settings",{})]:
            prop = next(p for p in exporter.PROPERTIES if p.name == name)
            with self.subTest(name=name), self.assertRaises(ValueError):
                exporter.validate_value(prop, bad)

class GrafanaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[3]
        cls.dashboard = json.loads((root / "nixos/nas0/grafana-dashboards/heater-ma3/dashboard.json").read_text())
        path = root / "nixos/nas0/grafana-dashboards/ensure-iot-folder.py"
        spec = importlib.util.spec_from_file_location("ensure_iot_folder", path)
        cls.migration = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.migration)

    def test_dashboard_covers_all_numeric_properties(self):
        expressions = " ".join(t["expr"] for panel in self.dashboard["panels"] for t in panel["targets"])
        for prop in exporter.PROPERTIES:
            if prop.kind != "string":
                self.assertIn(exporter.PREFIX + prop.name, expressions)
        self.assertIn(exporter.PREFIX + "property_info", expressions)
        self.assertIn(exporter.PREFIX + "property_up", expressions)
        ids = [p["id"] for p in self.dashboard["panels"]]
        self.assertEqual(len(ids),len(set(ids)))
        self.assertEqual(self.dashboard["uid"],"xiaomi-heater-ma3")

    def test_folder_rename_retains_uid(self):
        request = Mock(side_effect=[(200,{"uid":"existing","title":"Qingping"}),
                                    (200,{"uid":"existing","title":"IOT"})])
        self.migration.ensure_folder(request,"existing")
        self.assertEqual(request.call_args_list[1].args,
                         ("PUT","/api/folders/existing",{"title":"IOT","overwrite":True}))

    def test_folder_migration_is_idempotent(self):
        request = Mock(return_value=(200,{"title":"IOT"}))
        self.migration.ensure_folder(request,"existing")
        self.assertEqual(request.call_count,1)

    def test_unexpected_folder_name_is_preserved(self):
        request = Mock(return_value=(200,{"title":"Something else"}))
        with self.assertRaises(RuntimeError):
            self.migration.ensure_folder(request,"existing")
        self.assertEqual(request.call_count,1)


if __name__ == "__main__":
    unittest.main()

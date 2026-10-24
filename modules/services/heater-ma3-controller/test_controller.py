import http.client
import io
import json
import random
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from prometheus_client import CollectorRegistry, generate_latest
from prometheus_client.parser import text_string_to_metric_families

from controller import (
    API, PAGE, MIN_SWITCH_SECONDS, Controller, Heater, Metrics, PI,
    PROPERTIES, Qingping, Server, StateError, validate_settings,
)


class Clock:
    def __init__(self):
        self.wall, self.mono = 100000.0, 100.0

    def time(self):
        return self.wall

    def monotonic(self):
        return self.mono

    def advance(self, seconds):
        self.wall += seconds
        self.mono += seconds


class FakeHeater:
    def __init__(self, clock):
        self.clock = clock
        self.power = False
        self.level = 1
        self.fault = 0
        self.fail_write = self.fail_read = self.lost_ack = self.fail_after_write = False
        self.writes = []

    def read(self):
        if self.fail_read:
            raise TimeoutError("private diagnostic must not appear in HTTP or logs")
        return {"power": self.power, "heat_level": self.level, "status": 2 if self.power else 1, "fault": self.fault}

    def set_power(self, power):
        self.writes.append((self.clock.monotonic(), power))
        if self.fail_write:
            raise TimeoutError("private diagnostic must not appear in HTTP or logs")
        self.power = power
        if self.fail_after_write:
            self.fail_read = True
        if self.lost_ack:
            raise TimeoutError("ack lost after applying switch")


class FakeSensor:
    def __init__(self, clock):
        self.clock = clock
        self.temperature = 19.0
        self.timestamp = None
        self.fail = False

    def read(self):
        if self.fail:
            raise TimeoutError("private diagnostic must not appear in HTTP or logs")
        return self.temperature, self.clock.time() if self.timestamp is None else self.timestamp


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "state.json"
        self.clock = Clock()
        self.heater = FakeHeater(self.clock)
        self.sensor = FakeSensor(self.clock)
        self.c = self.restore()

    def restore(self, **kwargs):
        return Controller(self.heater, self.sensor, self.path, clock=self.clock, **kwargs)

    def enable(self):
        self.c.set_automation(True)
        self.c.tick()

    def advance(self, seconds=15):
        self.clock.advance(seconds)
        self.c.tick()

    def test_initially_disabled_and_only_reads(self):
        self.heater.power = True
        self.c.tick()
        self.assertFalse(self.c.snapshot()["enabled"])
        self.assertTrue(self.c.snapshot()["device"]["power"])
        self.assertEqual(self.heater.writes, [])

    def test_enable_takes_over_immediately_but_does_not_always_heat(self):
        self.sensor.temperature = 25
        self.enable()
        self.assertEqual(self.heater.writes, [])
        self.assertEqual(self.c.snapshot()["demand"], 0)
        self.c.set_automation(False)
        self.c.tick()
        self.sensor.temperature = 19
        self.enable()
        self.assertTrue(self.heater.power)

    def test_automatic_on_and_off_each_wait_15_minutes(self):
        self.enable()
        self.sensor.temperature = 26
        self.advance(899)
        self.assertTrue(self.heater.power)
        self.advance(15)
        self.assertFalse(self.heater.power)
        self.sensor.temperature = 19
        self.advance(899)
        self.assertFalse(self.heater.power)
        self.advance(15)
        self.assertTrue(self.heater.power)
        self.assertTrue(all(b[0] - a[0] >= 900 for a, b in zip(self.heater.writes, self.heater.writes[1:])))

    def test_fixed_temperature_produces_expected_fractional_duties(self):
        for duty in (0.1, 0.25, 0.5, 0.75, 0.9):
            with self.subTest(duty=duty):
                self.c = self.restore(kp=0.25, ki=0.0)
                self.heater.writes.clear()
                self.sensor.temperature = 23 - duty / 0.25
                self.c.set_automation(True)
                self.c.tick()
                for _ in range(6000):  # 25 hours, measured at 15-second samples.
                    self.advance()
                observed = self.c.snapshot()["on_seconds"] / 90000
                self.assertAlmostEqual(observed, duty, delta=0.02)
                self.assertTrue(all(b[0] - a[0] >= 900 for a, b in zip(self.heater.writes, self.heater.writes[1:])))
                self.c.set_automation(False)
                self.c.tick()
                self.advance(900)

    def test_random_setpoint_and_temperature_changes_preserve_dwell(self):
        rng = random.Random(203)
        self.enable()
        for i in range(1000):
            self.sensor.temperature = rng.uniform(18, 27)
            if i % 17 == 0:
                self.c.set_settings(rng.uniform(21, 25), 1)
            self.advance()
        self.assertTrue(all(b[0] - a[0] >= 900 for a, b in zip(self.heater.writes, self.heater.writes[1:])))

    def test_manual_operations_bypass_dwell_and_automatic_respects_observed_change(self):
        self.enable()
        self.clock.advance(1)
        self.c.set_manual_power(False)
        self.c.tick()
        self.assertFalse(self.heater.power)
        self.advance(15)
        self.assertFalse(self.heater.power)
        self.clock.advance(1)
        self.c.set_manual_power(True)
        self.c.tick()
        self.assertTrue(self.heater.power)
        self.sensor.temperature = 26
        self.advance(899)
        self.assertTrue(self.heater.power)
        self.advance(15)
        self.assertFalse(self.heater.power)
        self.assertEqual(self.c.snapshot()["transitions"]["manual"], 2)

    def test_external_transition_starts_dwell_at_observation(self):
        self.enable()
        self.clock.advance(300)
        self.heater.power = False
        self.c.tick()
        self.assertEqual(self.c.snapshot()["last_transition"], self.clock.time())
        self.advance(899)
        self.assertFalse(self.heater.power)
        self.advance(15)
        self.assertTrue(self.heater.power)
        self.assertEqual(self.c.snapshot()["transitions"]["external"], 1)

    def test_dwell_starts_after_slow_command_is_observed(self):
        original = self.heater.set_power

        def delayed_write(power):
            original(power)
            self.clock.advance(20)

        self.heater.set_power = delayed_write
        self.enable()
        self.assertEqual(self.c.snapshot()["last_transition"], self.clock.time())
        self.assertEqual(self.c.snapshot()["switch_wait_seconds"], 900)
        self.sensor.temperature = 26
        self.advance(899)
        self.assertTrue(self.heater.power)

    def test_pending_automatic_off_cannot_bypass_new_observed_transition(self):
        self.enable()
        self.sensor.temperature = 26
        self.heater.fail_write = True
        self.advance(900)
        self.assertEqual(self.c.snapshot()["pending_off"], "automatic")
        # A separately observed manual OFF then ON establishes a new dwell.
        self.heater.power = False
        self.c._read_heater()
        self.heater.power = True
        self.c._read_heater()
        self.heater.fail_write = False
        before = len(self.heater.writes)
        self.advance()
        self.assertTrue(self.heater.power)
        self.assertEqual(len(self.heater.writes), before)
        self.assertEqual(self.c.snapshot()["reason"], "minimum_interval")

    def test_disable_immediately_shuts_down_and_clears_pi(self):
        self.enable()
        self.c.set_automation(False)
        self.c.tick()
        self.assertFalse(self.heater.power)
        self.assertFalse(self.c.snapshot()["enabled"])
        self.assertEqual(self.c.snapshot()["i"], 0)
        self.advance(10000)
        self.assertFalse(self.heater.power)

    def test_duplicate_enable_does_not_reset_control_or_dwell(self):
        self.enable()
        before = self.c.lock_until
        self.c.set_automation(True)
        self.c.tick()
        self.assertEqual(self.c.lock_until, before)
        self.assertEqual(len(self.heater.writes), 1)

    def test_settings_persist_and_tolerance_does_not_override_pi(self):
        self.c.set_settings(24.5, 0.5)
        self.c = self.restore(ki=0.0)
        self.sensor.temperature = 23.5  # Outside band, but proportional demand is 25%.
        self.enable()
        self.assertEqual(self.c.snapshot()["setpoint"], 24.5)
        self.assertEqual(self.c.snapshot()["tolerance"], 0.5)
        self.assertEqual(self.c.snapshot()["demand"], 0.25)
        self.assertEqual(self.c.snapshot()["i"], 0)

    def test_normal_and_high_and_unknown_levels_never_heat(self):
        for level in (0, 2, 99, None):
            with self.subTest(level=level):
                self.heater.level = level
                self.enable()
                self.advance()
                self.assertFalse(self.heater.power)
                self.assertEqual(self.c.snapshot()["reason"], "not_low_heat")
                self.assertFalse(any(power for _, power in self.heater.writes))

    def test_low_heat_changed_during_heating_causes_immediate_protection_off(self):
        self.enable()
        self.heater.level = 2
        self.advance()
        self.assertFalse(self.heater.power)
        self.assertEqual(self.c.snapshot()["transitions"]["protection"], 1)
        self.assertEqual(self.c.snapshot()["i"], 0)
        self.heater.level = 1
        self.advance()
        self.assertFalse(self.heater.power)
        self.advance(900)
        self.assertTrue(self.heater.power)

    def test_manual_on_also_requires_low_heat(self):
        self.heater.level = 2
        self.c.set_manual_power(True)
        self.c.tick()
        self.assertEqual(self.heater.writes, [])
        self.assertEqual(self.c.snapshot()["reason"], "manual_rejected")

    def test_fault_shuts_down_without_waiting(self):
        self.enable()
        self.heater.fault = 1
        self.advance()
        self.assertFalse(self.heater.power)
        self.assertEqual(self.c.snapshot()["reason"], "device_fault")

    def test_sensor_http_success_does_not_refresh_old_acquisition_timestamp(self):
        self.sensor.timestamp = self.clock.time()
        self.enable()
        self.advance(60)
        self.assertTrue(self.heater.power)
        self.advance(15)
        self.assertFalse(self.heater.power)
        self.assertFalse(self.c.snapshot()["sensor_valid"])
        self.assertEqual(self.c.snapshot()["reason"], "sensor_stale")

    def test_sensor_transport_failure_uses_cache_only_for_60_seconds(self):
        self.enable()
        self.sensor.fail = True
        self.advance(45)
        self.assertTrue(self.heater.power)
        self.assertFalse(self.c.snapshot()["sensor_fetch_ok"])
        self.advance(30)
        self.assertFalse(self.heater.power)
        self.sensor.fail = False
        self.advance()
        self.assertTrue(self.c.snapshot()["sensor_valid"])
        self.assertFalse(self.heater.power)
        self.advance(900)
        self.assertTrue(self.heater.power)

    def test_sensor_invalid_at_start_never_turns_on(self):
        for value in (float("nan"), float("inf"), True, 100):
            self.sensor.temperature = value
            self.enable()
            self.advance()
            self.assertFalse(self.heater.power)
        self.assertEqual(self.heater.writes, [])

    def test_future_timestamp_blocks_heating(self):
        self.sensor.timestamp = self.clock.time() + 100
        self.enable()
        self.assertFalse(self.heater.power)
        self.assertFalse(self.c.snapshot()["sensor_valid"])

    def test_read_failure_attempts_off_even_without_readback(self):
        self.enable()
        self.heater.fail_read = True
        with self.assertLogs("heater-controller", level="INFO") as logs:
            self.advance()
        self.assertFalse(self.heater.power)
        self.assertEqual(self.c.snapshot()["pending_off"], "protection")
        self.assertFalse(self.c.snapshot()["heater_ok"])
        self.assertNotIn("private diagnostic", " ".join(logs.output))
        self.assertNotIn("private diagnostic", str(self.c.snapshot()))

    def test_failed_off_remains_pending_across_restart(self):
        self.enable()
        self.heater.fail_write = True
        self.c.set_automation(False)
        self.c.tick()
        self.assertEqual(self.c.snapshot()["pending_off"], "manual")
        self.c = self.restore()
        self.heater.fail_write = False
        self.c.tick()
        self.assertFalse(self.heater.power)
        self.assertIsNone(self.c.snapshot()["pending_off"])

    def test_ack_loss_is_resolved_by_actual_readback_without_duplicate_write(self):
        self.heater.lost_ack = True
        self.enable()
        self.assertTrue(self.heater.power)
        self.assertTrue(self.c.snapshot()["heater_ok"])
        self.advance()
        self.assertEqual(len(self.heater.writes), 1)
        self.assertEqual(self.c.snapshot()["failures"]["switch"], 0)

    def test_ambiguous_on_is_followed_by_off_not_a_replayed_on(self):
        self.heater.fail_after_write = True
        self.enable()
        self.assertEqual(self.c.snapshot()["pending_off"], "protection")
        self.heater.fail_after_write = self.heater.fail_read = False
        self.advance()
        self.assertFalse(self.heater.power)
        self.assertEqual([power for _, power in self.heater.writes], [True, False])

    def test_restart_preserves_known_actual_switch_time(self):
        self.enable()
        self.advance(300)
        self.c = self.restore()
        self.sensor.temperature = 26
        self.c.tick()
        self.assertTrue(self.heater.power)
        self.advance(600)
        self.assertFalse(self.heater.power)

    def test_restart_with_no_history_has_no_extra_wait(self):
        self.heater.power = True
        self.sensor.temperature = 26
        self.enable()
        self.assertFalse(self.heater.power)
        self.assertEqual(self.c.snapshot()["transitions"]["automatic"], 1)

    def test_legacy_timer_is_replaced_without_replaying_its_phase(self):
        self.path.write_text(json.dumps({"enabled": True, "phase": "on", "next_at": self.clock.time() + 1800, "pending": True}))
        self.sensor.temperature = 26
        self.c = self.restore()
        self.c.tick()
        self.assertEqual(self.heater.writes, [])
        self.assertEqual(json.loads(self.path.read_text())["version"], 2)
        self.assertNotIn("phase", self.c.snapshot())

    def test_wall_clock_change_does_not_bypass_dwell(self):
        self.enable()
        self.sensor.temperature = 26
        self.clock.wall += 90000
        self.advance(30)
        self.assertTrue(self.heater.power)
        self.advance(870)
        self.assertFalse(self.heater.power)

    def test_corrupt_state_is_rejected(self):
        self.path.write_text('{"enabled":true}')
        with self.assertRaises(ValueError):
            self.restore()

    def test_no_switch_if_intent_cannot_be_saved(self):
        with patch.object(self.c, "_write_state", side_effect=OSError):
            with self.assertRaises(StateError):
                self.c.set_automation(True)
        self.assertEqual(self.heater.writes, [])

    def test_metrics_and_logs_contain_review_data(self):
        with self.assertLogs("heater-controller", level="INFO") as logs:
            self.enable()
        records = [json.loads(line.split(":", 2)[2]) for line in logs.output]
        sample = next(row for row in records if row["event"] == "control_sample")
        for field in ("temperature", "setpoint", "tolerance", "p", "i", "demand", "power", "reason", "version"):
            self.assertIn(field, sample)
        registry = CollectorRegistry()
        registry.register(Metrics(self.c))
        samples = {s.name: s.value for family in text_string_to_metric_families(generate_latest(registry).decode()) for s in family.samples}
        self.assertEqual(samples["heater_pi_demand_ratio"], 1)
        self.assertEqual(samples["heater_pi_heat_level"], 1)
        self.assertIn("heater_pi_transitions_total", samples)
        self.assertIn("heater_pi_failures_total", samples)
        self.assertIn("heater_pi_sensor_last_success_timestamp_seconds", samples)


class AlgorithmTests(unittest.TestCase):
    def test_gain_units(self):
        pi = PI()
        self.assertAlmostEqual(pi.update(1, 0), 0.25)
        self.assertAlmostEqual(pi.update(1, 3600), 0.5)

    def test_integral_anti_windup_and_unwinding(self):
        pi = PI()
        for _ in range(1000):
            self.assertEqual(pi.update(10, 15), 1)
        self.assertEqual(pi.integral, 0)
        pi.integral = 0.8
        pi.update(-1, 600)
        self.assertLess(pi.integral, 0.8)
        self.assertGreaterEqual(pi.integral, 0)
        pi.update(-100, 10000)
        self.assertEqual(pi.output, 0)
        self.assertGreaterEqual(pi.integral, 0)

    def test_invalid_gains_and_settings(self):
        for value in (-1, float("nan"), float("inf"), True):
            with self.assertRaises(ValueError):
                PI(kp=value)
        for setpoint, tolerance in ((True, 1), (float("nan"), 1), (31, 1), (23, 0), (23, -1), (23, float("inf"))):
            with self.assertRaises(ValueError):
                validate_settings(setpoint, tolerance)


class ProtocolTests(unittest.TestCase):
    def heater(self):
        h = Heater.__new__(Heater)
        h.device = Mock()
        h.validated = True
        return h

    def test_switch_is_the_only_property_written(self):
        h = self.heater()
        h.device.send.return_value = [{"code": 0}]
        for power in (True, False):
            h.set_power(power)
            h.device.send.assert_called_with("set_properties", [
                {"did": "power", "siid": 2, "piid": 1, "value": power}
            ], retry_count=0)

    def test_only_switch_fault_status_and_level_are_read(self):
        h = self.heater()
        values = {"power": False, "fault": 0, "status": 1, "heat_level": 1}
        h.device.send.return_value = [{"did": name, "code": 0, "value": value} for name, value in values.items()]
        self.assertEqual(h.read(), values)
        query = h.device.send.call_args.args[1]
        self.assertEqual({(p["siid"], p["piid"]) for p in query}, {(2, 1), (2, 2), (2, 3), (2, 7)})

    def test_wrong_model_blocks_switch(self):
        h = self.heater()
        h.validated = False
        h.device.info.return_value.model = "other.device"
        with self.assertRaises(ValueError):
            h.set_power(True)
        h.device.send.assert_not_called()

    def test_missing_or_invalid_property_is_rejected(self):
        h = self.heater()
        for level in (True, None, "1"):
            h.device.send.return_value = [{"did": name, "code": 0, "value": value}
                for name, value in {"power": False, "fault": 0, "status": 1, "heat_level": level}.items()]
            with self.assertRaises(ValueError):
                h.read()
        h.device.send.return_value = []
        with self.assertRaises(ValueError):
            h.read()

    def test_qingping_uses_acquisition_timestamp_even_if_latest_poll_failed(self):
        body = b'miio_qingping_temperature_celsius 22.5\nmiio_qingping_last_success_timestamp_seconds 123456\nmiio_qingping_up 0\n'
        with patch("controller.urlopen", return_value=io.BytesIO(body)):
            self.assertEqual(Qingping("http://localhost/metrics").read(), (22.5, 123456))

    def test_qingping_rejects_missing_or_nonfinite_data(self):
        for body in (b'miio_qingping_temperature_celsius 23\n',
                     b'miio_qingping_temperature_celsius NaN\nmiio_qingping_last_success_timestamp_seconds 123\n',
                     b'miio_qingping_temperature_celsius 0\nmiio_qingping_last_success_timestamp_seconds 0\n'):
            with patch("controller.urlopen", return_value=io.BytesIO(body)):
                with self.assertRaises(ValueError):
                    Qingping("http://localhost/metrics").read()


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.clock = Clock()
        self.heater = FakeHeater(self.clock)
        self.c = Controller(self.heater, FakeSensor(self.clock), Path(self.tmp.name) / "state.json", clock=self.clock)
        self.server = Server(("127.0.0.1", 0), self.c, "https://nas0.i.kasei.im", b"<html>heater</html>")
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.server.worker.start()
        self.addCleanup(self.cleanup)

    def cleanup(self):
        self.server.stopping.set()
        self.server.shutdown()
        self.thread.join()
        self.server.worker.join()
        self.server.server_close()
        self.tmp.cleanup()

    def request(self, method, path, data=None, headers=None):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=5)
        connection.request(method, path, body=data, headers=headers or {})
        response = connection.getresponse()
        result = response.status, response.read(), response.getheader("Cache-Control")
        connection.close()
        return result

    def post(self, path, data):
        return self.request("POST", API + path, json.dumps(data), {
            "Content-Type": "application/json", "Origin": "https://nas0.i.kasei.im", "X-CSRF-Token": self.server.csrf,
        })

    def test_status_page_and_metrics(self):
        code, body, cache = self.request("GET", API + "status")
        self.assertEqual(code, 200)
        self.assertIn("csrf", json.loads(body))
        self.assertNotIn("token", json.loads(body))
        self.assertEqual(cache, "no-store")
        self.assertEqual(self.request("GET", PAGE)[0], 200)
        code, body, _ = self.request("GET", "/metrics")
        self.assertEqual(code, 200)
        self.assertIn(b"heater_pi_setpoint_celsius 23.0", body)

    def test_origin_and_csrf_required_for_all_writes(self):
        for action in ("automation", "settings", "power"):
            self.assertEqual(self.request("POST", API + action, '{}', {"Content-Type": "application/json"})[0], 403)
            self.assertEqual(self.request("POST", API + action, '{}', {
                "Content-Type": "application/json", "Origin": "https://evil.example", "X-CSRF-Token": self.server.csrf,
            })[0], 403)

    def test_settings_and_manual_control(self):
        code, body, _ = self.post("settings", {"setpoint": 24, "tolerance": 0.5})
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body)["setpoint"], 24)
        self.assertEqual(self.post("automation", {"enabled": True})[0], 200)
        self.assertTrue(self.heater.power)
        self.assertEqual(self.post("power", {"power": False})[0], 200)
        self.assertFalse(self.heater.power)
        self.assertEqual(self.post("power", {"power": True})[0], 200)
        self.assertTrue(self.heater.power)
        self.post("automation", {"enabled": False})
        self.assertFalse(self.heater.power)

    def test_invalid_payloads_do_not_change_settings(self):
        for action, payload in (("settings", {"setpoint": 23, "tolerance": 0}),
                                ("settings", {"setpoint": float("nan"), "tolerance": 1}),
                                ("settings", {"setpoint": True, "tolerance": 1}),
                                ("settings", {"setpoint": 23, "tolerance": 1, "unexpected": 1}),
                                ("automation", {"enabled": "true"}), ("power", {"power": 1})):
            self.assertEqual(self.post(action, payload)[0], 400)
        self.assertFalse(self.c.snapshot()["enabled"])
        self.assertEqual(self.c.snapshot()["setpoint"], 23)

    def test_get_cannot_change_state(self):
        for action in ("automation", "power", "settings"):
            self.assertEqual(self.request("GET", API + action)[0], 404)
        self.assertFalse(self.c.snapshot()["enabled"])


if __name__ == "__main__":
    unittest.main()

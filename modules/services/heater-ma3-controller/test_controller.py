import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from controller import API, PAGE, Controller, Heater, PROPERTIES, Server, StateError


class Clock:
    def __init__(self):
        self.wall = 100000.0
        self.mono = 100.0

    def time(self):
        return self.wall

    def monotonic(self):
        return self.mono

    def advance(self, seconds):
        self.wall += seconds
        self.mono += seconds


class FakeHeater:
    def __init__(self):
        self.power = False
        self.fail_write = False
        self.fail_read = False
        self.fault = 0
        self.writes = []

    def read(self):
        if self.fail_read:
            raise TimeoutError("private diagnostic must not appear in HTTP")
        return {"power": self.power, "heat_level": 1, "temperature": 20.0,
                "target_temperature": 22.0, "status": 1, "fault": self.fault}

    def set_power(self, power):
        self.writes.append(power)
        if self.fail_write:
            raise TimeoutError("private diagnostic must not appear in HTTP")
        self.power = power


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "state.json"
        self.clock = Clock()
        self.heater = FakeHeater()
        self.c = self.restore()

    def restore(self):
        return Controller(self.heater, self.path, clock=self.clock)

    def enable(self):
        self.c.set_automation(True)
        self.c.tick()

    def test_initially_disabled_and_only_reads(self):
        self.heater.power = True  # Initial deployment does not change a manual setting.
        self.c.tick()
        self.assertFalse(self.c.snapshot()["enabled"])
        self.assertTrue(self.c.snapshot()["device"]["power"])
        self.assertEqual(self.heater.writes, [])

    def test_alternates_at_30_minutes_and_retains_settings(self):
        self.enable()
        self.clock.advance(1799)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True])
        self.clock.advance(1)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False])
        self.clock.advance(1800)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False, True])
        self.assertEqual(self.c.snapshot()["device"]["heat_level"], 1)
        self.assertEqual(self.c.snapshot()["device"]["target_temperature"], 22)

    def test_disable_immediately_turns_off_and_cancels_deadline(self):
        self.enable()
        self.c.set_automation(False)
        self.c.tick()
        self.clock.advance(10000)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False])
        self.assertIsNone(self.c.snapshot()["next_at"])

    def test_duplicate_enable_does_not_reset_deadline(self):
        self.enable()
        deadline = self.c.snapshot()["next_at"]
        self.clock.advance(300)
        self.c.set_automation(True)
        self.c.tick()
        self.assertEqual(self.c.snapshot()["next_at"], deadline)
        self.assertEqual(self.heater.writes, [True])

    def test_wall_clock_change_does_not_change_cycle(self):
        self.enable()
        self.clock.wall += 90000
        self.clock.advance(1800)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False])

    def test_restart_keeps_future_deadline(self):
        self.enable()
        self.clock.advance(600)
        self.c = self.restore()
        self.c.tick()
        self.assertEqual(self.heater.writes, [True])
        self.clock.advance(1200)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False])

    def test_restart_after_missed_transition_starts_with_full_off_period(self):
        self.enable()
        self.clock.advance(5000)
        self.c = self.restore()
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False])
        self.assertEqual(self.c.snapshot()["next_at"], self.clock.time() + 1800)

    def test_off_failure_retries_and_prevents_next_on(self):
        self.enable()
        self.heater.fail_write = True
        self.clock.advance(1800)
        self.c.tick()
        self.assertIs(self.c.snapshot()["pending"], False)
        self.assertTrue(self.c.snapshot()["device"]["power"])
        self.assertIsNone(self.c.snapshot()["next_at"])
        self.assertNotIn("private diagnostic", self.c.snapshot()["error"])
        self.clock.advance(5000)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False, False])
        self.heater.fail_write = False
        self.clock.advance(10)
        self.c.tick()
        self.assertEqual(self.c.snapshot()["next_at"], self.clock.time() + 1800)

    def test_disable_with_failed_off_survives_restart(self):
        self.enable()
        self.heater.fail_write = True
        self.c.set_automation(False)
        self.c.tick()
        self.heater.fail_write = False
        self.c = self.restore()
        self.c.tick()
        self.assertFalse(self.heater.power)
        self.assertIsNone(self.c.snapshot()["pending"])
        self.assertFalse(self.c.snapshot()["enabled"])

    def test_unconfirmed_on_does_not_extend_on_deadline(self):
        self.heater.fail_write = True
        self.enable()
        self.clock.advance(1800)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False])

    def test_off_attempted_even_when_status_reads_fail(self):
        self.enable()
        self.heater.fail_read = True
        self.c.set_automation(False)
        self.c.tick()
        self.assertEqual(self.heater.writes, [True, False])
        self.assertIs(self.c.snapshot()["pending"], False)

    def test_fault_prevents_turn_on(self):
        self.heater.fault = 1
        self.enable()
        self.assertEqual(self.heater.writes, [False])
        self.assertFalse(self.c.snapshot()["enabled"])

    def test_corrupt_state_is_rejected(self):
        self.path.write_text('{"enabled":true}')
        with self.assertRaises(ValueError):
            self.restore()

    def test_no_device_write_if_intent_cannot_be_saved(self):
        with patch.object(self.c, "_write_state", side_effect=OSError):
            with self.assertRaises(StateError):
                self.c.set_automation(True)
        self.assertEqual(self.heater.writes, [])

    def test_last_reading_is_retained_but_marked_stale(self):
        self.c.tick()
        self.heater.fail_read = True
        self.clock.advance(31)
        self.c.tick()
        self.assertTrue(self.c.snapshot()["stale"])
        self.assertEqual(self.c.snapshot()["device"]["temperature"], 20)


class ProtocolTests(unittest.TestCase):
    def test_switch_is_the_only_property_written(self):
        h = Heater.__new__(Heater)
        h.device = Mock()
        h.device.send.return_value = [{"code": 0}]
        h.validated = True
        for power in [True, False]:
            h.set_power(power)
            h.device.send.assert_called_with("set_properties", [
                {"did": "power", "siid": 2, "piid": 1, "value": power}
            ], retry_count=0)

    def test_wrong_model_blocks_switch(self):
        h = Heater.__new__(Heater)
        h.device = Mock()
        h.device.info.return_value.model = "other.device"
        h.validated = False
        with self.assertRaises(ValueError):
            h.set_power(True)
        h.device.send.assert_not_called()

    def test_missing_switch_response_is_rejected(self):
        h = Heater.__new__(Heater)
        h.device = Mock()
        h.validated = True
        h.device.send.return_value = [{"did": name, "code": 0, "value": 1}
                                       for name in PROPERTIES if name != "power"]
        with self.assertRaises(ValueError):
            h.read()


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.c = Controller(FakeHeater(), Path(self.tmp.name) / "state.json")
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
        c = http.client.HTTPConnection(*self.server.server_address, timeout=5)
        c.request(method, path, body=data, headers=headers or {})
        r = c.getresponse()
        result = r.status, r.read(), r.getheader("Cache-Control")
        c.close()
        return result

    def test_status_and_page(self):
        code, body, cache = self.request("GET", API + "status")
        self.assertEqual(code, 200)
        self.assertIn("csrf", json.loads(body))
        self.assertNotIn("token", json.loads(body))
        self.assertEqual(cache, "no-store")
        self.assertEqual(self.request("GET", PAGE)[0], 200)

    def test_origin_csrf_and_json_boolean_required(self):
        headers = {"Content-Type": "application/json"}
        self.assertEqual(self.request("POST", API + "automation", '{"enabled":true}', headers)[0], 403)
        headers.update({"Origin": "https://evil.example", "X-CSRF-Token": self.server.csrf})
        self.assertEqual(self.request("POST", API + "automation", '{"enabled":true}', headers)[0], 403)
        headers["Origin"] = "https://nas0.i.kasei.im"
        self.assertEqual(self.request("POST", API + "automation", '{"enabled":"true"}', headers)[0], 400)
        code, body, _ = self.request("POST", API + "automation", '{"enabled":true}', headers)
        self.assertEqual(code, 200)
        self.assertTrue(json.loads(body)["enabled"])
        self.assertTrue(json.loads(body)["device"]["power"])
        code, body, _ = self.request("POST", API + "automation", '{"enabled":false}', headers)
        self.assertEqual(code, 200)
        self.assertFalse(json.loads(body)["device"]["power"])

    def test_get_cannot_change_automation(self):
        self.assertEqual(self.request("GET", API + "automation")[0], 404)
        self.assertFalse(self.c.snapshot()["enabled"])


if __name__ == "__main__":
    unittest.main()

"""Exercise the demo transport through real HTTP, without a car or account."""

import importlib.util
import json
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

spec = importlib.util.spec_from_file_location("fake_psacc", Path(__file__).resolve().parents[1] / "Server/fake_psacc.py")
fake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fake)


class FakeServerTests(unittest.TestCase):
    initial_state = dict(fake.state)

    def setUp(self):
        fake.state.clear()
        fake.state.update(self.initial_state)

    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), fake.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def get(self, path):
        with urlopen(self.base + path, timeout=3) as response:
            self.assertEqual("application/json", response.headers["Content-Type"])
            return json.load(response)

    def test_vehicle_discovery_and_history_share_demo_identifier(self):
        car = self.get("/get_vehicles")[0]
        self.assertEqual("DEMO0000000000000", car["vin"])
        self.assertGreater(len(self.get("/vehicles/trips")), 0)
        self.assertEqual(car["vin"], self.get("/vehicles/chargings")[0]["VIN"])

    def test_commands_are_reflected_in_readings(self):
        vin = fake.VIN
        self.assertTrue(self.get(f"/charge_now/{vin}/0"))
        status = self.get(f"/get_vehicleinfo/{vin}")
        self.assertEqual("Stopped", status["energy"][1]["charging"]["status"])
        self.assertTrue(self.get(f"/charge_now/{vin}/1"))
        status = self.get(f"/get_vehicleinfo/{vin}")
        self.assertEqual("InProgress", status["energy"][1]["charging"]["status"])
        self.assertTrue(self.get(f"/preconditioning/{vin}/1"))
        self.assertTrue(self.get(f"/lock_door/{vin}/0"))
        status = self.get(f"/get_vehicleinfo/{vin}")
        self.assertEqual("Enabled", status["preconditionning"]["air_conditioning"]["status"])
        self.assertEqual(["Unlocked"], status["doors_state"]["locked_state"])

    def test_threshold_and_unknown_endpoint(self):
        control = self.get(f"/charge_control?vin={fake.VIN}&percentage=85")
        self.assertEqual(85, control["percentage_threshold"])
        with self.assertRaises(HTTPError) as failure:
            self.get("/does-not-exist")
        with failure.exception:
            self.assertEqual(404, failure.exception.code)


if __name__ == "__main__":
    unittest.main()

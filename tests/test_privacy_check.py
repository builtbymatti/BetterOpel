import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("privacy_check", Path(__file__).resolve().parents[1] / "scripts/privacy_check.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class PrivacyGuardTests(unittest.TestCase):
    def test_credentials_and_signing_are_detected(self):
        self.assertIn("credential token", guard.findings("fixture", "ghp_" + "x" * 36))
        self.assertIn("literal signing team", guard.findings("fixture", "DEVELOPMENT_TEAM = " + "A1" * 5))
        self.assertIn("assigned secret", guard.findings("fixture", 'password = "' + "example" * 3 + '"'))

    def test_private_hosts_and_identifiers_are_detected(self):
        host = ".".join(["private-host", "private-tail", "ts", "net"])
        self.assertIn("private tailnet hostname", guard.findings("fixture", host))
        self.assertIn("unexpected vehicle identifier", guard.findings("fixture", "W0" + "V" * 15))
        self.assertIn("private network address", guard.findings("fixture", ".".join(["192", "168", "42", "21"])))

    def test_paths_and_email_are_detected(self):
        self.assertIn("personal home path", guard.findings("fixture", "/" + "Users" + "/owner/file"))
        self.assertIn("personal email", guard.findings("fixture", "owner" + "@" + "private-mail.invalid"))

    def test_public_examples_are_allowed(self):
        sample = "http://127.0.0.1:5055 mac-mini.example.ts.net owner@example.com DEMO0000000000000 com.example.betteropel CarHero@3x.png"
        self.assertEqual([], guard.findings("fixture", sample))


if __name__ == "__main__":
    unittest.main()

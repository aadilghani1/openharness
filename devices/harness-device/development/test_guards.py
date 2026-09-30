"""Exercise the boundaries without opening hardware or running a publisher."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from check_target import check_target

HERE = Path(__file__).resolve().parent
DEVICES = json.loads((HERE / "devices.json").read_text())["devices"]


class DeviceBoundary(unittest.TestCase):
    def test_registered_development_targets_only(self):
        for device in DEVICES:
            with self.subTest(mac=device["mac"]):
                if device["role"] == "development":
                    self.assertEqual(check_target(DEVICES, device["mac"].lower(),
                                     device["chip"], device["branch"]), device)
                else:
                    with self.assertRaisesRegex(ValueError, "Production/protected"):
                        check_target(DEVICES, device["mac"], device["chip"], "dev/firmware-round")

    def test_wrong_chip_branch_and_unknown_identity(self):
        device = next(d for d in DEVICES if d.get("branch") == "dev/firmware-round")
        for mac, chip, branch in [
            (device["mac"], "esp32p4", "dev/firmware-round"),
            (device["mac"], "esp32s3", "main"),
            (device["mac"], "esp32s3", "dev/firmware-pro"),
            (device["mac"], "esp32s3", ""),
            ("AA:BB:CC:DD:EE:FF", "esp32s3", "dev/firmware-round"),
            (device["mac"][-5:], "esp32s3", "dev/firmware-round"),
        ]:
            with self.subTest(mac=mac, chip=chip, branch=branch), self.assertRaises(ValueError):
                check_target(DEVICES, mac, chip, branch)
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            check_target(DEVICES + [device], device["mac"], device["chip"], device["branch"])


class BuildBoundary(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="firmware-guard-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copyfile(HERE / "channel.cmake", self.root / "channel.cmake")
        (self.root / "probe.cmake").write_text(
            'include("${CMAKE_CURRENT_LIST_DIR}/channel.cmake")\n'
            'message(STATUS "RESULT=${PROJECT_VER},${IDF_TARGET}")\n')
        self.git("init", "-q", "-b", "main")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-qm", "fixture")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    def cmake(self, *args):
        return subprocess.run(["cmake", *args, "-P", str(self.root / "probe.cmake")],
                              capture_output=True, text=True)

    def test_round_version_matches_commit_and_marks_uncommitted_source(self):
        self.git("switch", "-qc", "dev/firmware-round")
        commit = self.git("rev-parse", "--short=10", "HEAD")
        result = self.cmake()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"RESULT=0.0.0-dev.{commit},esp32s3", result.stdout)
        (self.root / "new-source.c").write_text("// Uncommitted source\n")
        result = self.cmake()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"RESULT=0.0.0-dev.{commit}-dirty,esp32s3", result.stdout)

    def test_customer_version_and_cross_hardware_build_are_refused(self):
        self.git("switch", "-qc", "dev/firmware-round")
        for args, expected in [
            (("-DPROJECT_VER=0.0.87",), "must not use PROJECT_VER"),
            (("-DIDF_TARGET=esp32p4",), "wrong hardware target"),
        ]:
            with self.subTest(args=args):
                result = self.cmake(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stderr)

    def test_pro_selects_its_own_chip_and_refreshes_cached_dev_version(self):
        self.git("switch", "-qc", "dev/firmware-pro")
        result = self.cmake("-DPROJECT_VER=0.0.0-dev.0123456789")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"RESULT=0\.0\.0-dev\.[0-9a-f]{10},esp32p4")
        self.assertNotIn("RESULT=0.0.0-dev.0123456789", result.stdout)

    def test_production_build_behavior_is_unchanged(self):
        result = self.cmake("-DPROJECT_VER=0.0.87", "-DIDF_TARGET=esp32s3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RESULT=0.0.87,esp32s3", result.stdout)
        self.assertNotIn("Development firmware:", result.stdout)


if __name__ == "__main__":
    unittest.main()

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class QemuBootTests(unittest.TestCase):
    def setUp(self):
        self.temporary_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_dir.cleanup)
        self.project = Path(self.temporary_dir.name) / "project"
        self.machine = "lumen-orin-nx-16gb"
        (self.project / "ci").mkdir(parents=True)
        repository = Path(__file__).resolve().parents[1]
        script = repository / "ci/test-qemu-boot.sh"
        self.assertTrue(script.exists(), "CI boot validation script is missing")
        shutil.copy2(script, self.project / "ci/test-qemu-boot.sh")
        shutil.copy2(repository / "run-qemu.sh", self.project / "run-qemu.sh")
        images = self.project / "build/tmp/deploy/images" / self.machine
        images.mkdir(parents=True)
        (images / "Image").touch()
        (images / f"lumen-image-minimal-{self.machine}.rootfs.ext4").touch()

        mock_bin = self.project / "bin"
        mock_bin.mkdir()
        qemu = mock_bin / "qemu-system-aarch64"
        qemu.write_text(
            "#!/usr/bin/env python3\n"
            "import os, pathlib, signal, sys, time\n"
            "root = pathlib.Path(os.environ['QEMU_TEST_ROOT'])\n"
            "(root / 'pid').write_text(str(os.getpid()))\n"
            "def stop(signum, frame):\n"
            "    (root / 'stopped').touch()\n"
            "    sys.exit(0)\n"
            "signal.signal(signal.SIGTERM, stop)\n"
            "behavior = os.environ['QEMU_TEST_BEHAVIOR']\n"
            "if behavior == 'exit':\n"
            "    print('QEMU startup failed', flush=True)\n"
            "    sys.exit(7)\n"
            "serial = sys.argv[sys.argv.index('-chardev') + 1]\n"
            "log = pathlib.Path(serial.split('logfile=', 1)[1])\n"
            "if behavior == 'prompt':\n"
            "    log.write_text('Booting\\nlumen-orin-nx-16gb log')\n"
            "    time.sleep(0.1)\n"
            "    with log.open('a') as stream:\n"
            "        stream.write('in: ')\n"
            "elif behavior == 'panic':\n"
            "    log.write_text('Kernel panic - not syncing: test\\n')\n"
            "else:\n"
            "    log.write_text('Still booting\\n')\n"
            "while True:\n"
            "    time.sleep(1)\n"
        )
        qemu.chmod(0o755)
        self.environment = os.environ.copy()
        self.environment.update(
            PATH=f"{mock_bin}:{self.environment['PATH']}",
            QEMU_TEST_ROOT=str(self.project),
            LUMEN_QEMU_LOGS=str(self.project / "logs"),
        )

    def run_boot(self, behavior):
        self.environment["QEMU_TEST_BEHAVIOR"] = behavior
        return subprocess.run(
            ["bash", str(self.project / "ci/test-qemu-boot.sh"), self.machine, "2"],
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def assert_qemu_stopped(self):
        pid = int((self.project / "pid").read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_passes_on_partial_login_prompt_and_stops_qemu(self):
        result = self.run_boot("prompt")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS", result.stdout)
        self.assertTrue((self.project / "stopped").exists())
        self.assert_qemu_stopped()
        logs = list((self.project / "logs").glob(f"run-*/{self.machine}/console.log"))
        self.assertEqual(len(logs), 1)
        self.assertIn("login:", logs[0].read_text())

    def test_fails_on_panic_and_stops_qemu(self):
        result = self.run_boot("panic")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Kernel panic", result.stderr)
        self.assert_qemu_stopped()

    def test_fails_on_early_exit(self):
        result = self.run_boot("exit")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("exited", result.stderr)
        self.assertIn("QEMU startup failed", result.stderr)
        self.assert_qemu_stopped()

    def test_timeout_does_not_accept_a_stale_prompt(self):
        old_log = self.project / "logs" / self.machine / "console.log"
        old_log.parent.mkdir(parents=True)
        old_log.write_text("lumen-orin-nx-16gb login: ")
        result = self.run_boot("timeout")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Timed out", result.stderr)
        self.assert_qemu_stopped()


if __name__ == "__main__":
    unittest.main()

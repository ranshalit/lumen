import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


class LumenSetIpTests(unittest.TestCase):
    def setUp(self):
        self.temporary_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_dir.cleanup)
        self.root = Path(self.temporary_dir.name)
        self.etc = self.root / "etc"
        self.init_dir = self.etc / "init.d"
        self.network_dir = self.etc / "network"
        self.run_dir = self.root / "run"
        self.bin_dir = self.root / "bin"
        self.sysctl_dir = self.root / "proc/sys/net/ipv4/conf"
        for directory in (self.init_dir, self.network_dir, self.run_dir, self.bin_dir):
            directory.mkdir(parents=True, exist_ok=True)
        for interface in ("eth0", "portus0"):
            directory = self.sysctl_dir / interface
            directory.mkdir(parents=True)
            (directory / "promote_secondaries").write_text("0\n")

        self.init_file = self.init_dir / "lumen-eth-static"
        self.interfaces_file = self.network_dir / "interfaces"
        self.init_file.write_text(
            "#!/bin/sh\n"
            "IFACE=eth0\n"
            "IP=192.0.5.10\n"
            "CIDR=24\n"
            "ip addr replace 192.168.1.10/24 dev portus0\n"
        )
        self.interfaces_file.write_text(
            "auto eth0\n"
            "iface eth0 inet static\n"
            "    address 192.0.5.10\n"
            "    netmask 255.255.255.0\n"
            "\n"
            "auto portus0\n"
            "iface portus0 inet static\n"
            "    address 192.168.1.10\n"
            "    netmask 255.255.255.0\n"
        )

        self.ip_state = self.root / "ip-state.json"
        self.ip_log = self.root / "ip-commands.jsonl"
        self.ip_state.write_text(
            json.dumps(
                {
                    "eth0": ["192.0.5.10/24"],
                    "portus0": ["192.168.1.10/24"],
                }
            )
        )
        fake_ip = self.bin_dir / "ip"
        fake_ip.write_text(
            "#!/usr/bin/env python3\n"
            "import ipaddress, json, os, sys, time\n"
            "from pathlib import Path\n"
            "state_path = Path(os.environ['FAKE_IP_STATE'])\n"
            "log_path = Path(os.environ['FAKE_IP_LOG'])\n"
            "args = sys.argv[1:]\n"
            "state = json.loads(state_path.read_text())\n"
            "with log_path.open('a') as log:\n"
            "    log.write(json.dumps(args) + '\\n')\n"
            "if args[:2] == ['addr', 'show']:\n"
            "    iface = args[-1]\n"
            "    for address in state.get(iface, []):\n"
            "        print(f'    inet {address} scope global {iface}')\n"
            "elif args[:2] in (['addr', 'add'], ['addr', 'del']):\n"
            "    operation, address, _, iface = args[1:5]\n"
            "    entries = state.setdefault(iface, [])\n"
            "    if operation == 'add':\n"
            "        if any(entry.split('/')[0] == address.split('/')[0] for entry in entries):\n"
            "            print('File exists', file=sys.stderr)\n"
            "            sys.exit(2)\n"
            "        entries.append(address)\n"
            "    else:\n"
            "        time.sleep(float(os.environ.get('FAKE_IP_DELAY_DELETE', '0')))\n"
            "        primary = bool(entries and entries[0] == address)\n"
            "        try:\n"
            "            entries.remove(address)\n"
            "        except ValueError:\n"
            "            print('Address not found', file=sys.stderr)\n"
            "            sys.exit(2)\n"
            "        promote = (Path(os.environ['FAKE_SYSCTL_DIR']) / iface / 'promote_secondaries').read_text().strip()\n"
            "        if primary and promote == '0':\n"
            "            network = ipaddress.IPv4Interface(address).network\n"
            "            entries[:] = [entry for entry in entries if ipaddress.IPv4Interface(entry).network != network]\n"
            "    state_path.write_text(json.dumps(state))\n"
            "else:\n"
            "    print('unsupported ip invocation: ' + repr(args), file=sys.stderr)\n"
            "    sys.exit(2)\n"
        )
        fake_ip.chmod(0o755)
        self.script = (
            Path(__file__).resolve().parents[1]
            / "meta-lumen/recipes-core/network/lumen-eth-static/lumen-set-ip"
        )
        self.environment = os.environ.copy()
        self.environment.update(
            PATH=f"{self.bin_dir}:{self.environment['PATH']}",
            LUMEN_SET_IP_TEST_ROOT=str(self.root),
            FAKE_IP_STATE=str(self.ip_state),
            FAKE_IP_LOG=str(self.ip_log),
            FAKE_SYSCTL_DIR=str(self.sysctl_dir),
        )

    def run_helper(
        self, *arguments, timeout="3600", ssh_connection=None, extra_env=None
    ):
        environment = self.environment.copy()
        environment["LUMEN_SET_IP_TEST_TIMEOUT"] = timeout
        environment.update(extra_env or {})
        if ssh_connection is not None:
            environment["SSH_CONNECTION"] = ssh_connection
        else:
            environment.pop("SSH_CONNECTION", None)
        return subprocess.run(
            ["sh", str(self.script), *arguments],
            env=environment,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def addresses(self, interface):
        return json.loads(self.ip_state.read_text())[interface]

    def wait_for(self, predicate, timeout=4):
        end_time = time.monotonic() + timeout
        while time.monotonic() < end_time:
            if predicate():
                return True
            time.sleep(0.05)
        return predicate()

    def test_rejects_bad_interface_address_and_prefix_without_mutation(self):
        original_init = self.init_file.read_text()
        original_interfaces = self.interfaces_file.read_text()
        cases = (
            (("prepare", "wlan0", "192.0.5.20/24"), "unsupported interface"),
            (("prepare", "eth0", "999.0.5.20/24"), "invalid IPv4/CIDR"),
            (("prepare", "eth0", "192.0.5.20/0"), "invalid IPv4/CIDR"),
            (("prepare", "eth0", "192.0.5.20/33"), "invalid IPv4/CIDR"),
        )

        for arguments, expected_error in cases:
            with self.subTest(arguments=arguments):
                result = self.run_helper(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected_error, result.stderr)
                self.assertEqual(self.addresses("eth0"), ["192.0.5.10/24"])
                self.assertEqual(self.init_file.read_text(), original_init)
                self.assertEqual(self.interfaces_file.read_text(), original_interfaces)

    def test_prepare_adds_live_address_without_persisting_config(self):
        original_init = self.init_file.read_text()
        original_interfaces = self.interfaces_file.read_text()

        result = self.run_helper("prepare", "eth0", "192.0.5.20/25")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.addresses("eth0"), ["192.0.5.10/24", "192.0.5.20/25"]
        )
        self.assertEqual(self.init_file.read_text(), original_init)
        self.assertEqual(self.interfaces_file.read_text(), original_interfaces)

    def test_confirm_from_new_ssh_address_persists_ip_and_netmask(self):
        prepared = self.run_helper("prepare", "eth0", "192.0.5.20/25")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)

        result = self.run_helper(
            "confirm",
            ssh_connection="192.0.5.30 42000 192.0.5.20 22",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.addresses("eth0"), ["192.0.5.20/25"])
        self.assertIn("IP=192.0.5.20\n", self.init_file.read_text())
        self.assertIn("CIDR=25\n", self.init_file.read_text())
        interfaces = self.interfaces_file.read_text()
        self.assertIn("    address 192.0.5.20\n", interfaces)
        self.assertIn("    netmask 255.255.255.128\n", interfaces)
        self.assertIn("    address 192.168.1.10\n", interfaces)

    def test_mismatched_ssh_destination_cannot_confirm(self):
        prepared = self.run_helper("prepare", "eth0", "192.0.5.20/24")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        original_init = self.init_file.read_text()
        original_interfaces = self.interfaces_file.read_text()

        result = self.run_helper(
            "confirm",
            ssh_connection="192.0.5.30 42001 192.0.5.10 22",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            self.addresses("eth0"), ["192.0.5.10/24", "192.0.5.20/24"]
        )
        self.assertEqual(self.init_file.read_text(), original_init)
        self.assertEqual(self.interfaces_file.read_text(), original_interfaces)
        self.assertEqual(self.run_helper("cancel").returncode, 0)

    def test_same_subnet_confirmation_preserves_new_live_address(self):
        prepared = self.run_helper("prepare", "eth0", "192.0.5.20/24")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)

        result = self.run_helper(
            "confirm", ssh_connection="192.0.5.30 42000 192.0.5.20 22"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.addresses("eth0"), ["192.0.5.20/24"])
        self.assertEqual(
            (self.sysctl_dir / "eth0/promote_secondaries").read_text(), "0\n"
        )

    def test_console_confirmation_updates_portus_only(self):
        prepared = self.run_helper("prepare", "portus0", "192.168.1.30/26")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)

        result = self.run_helper("confirm", "--console")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.addresses("portus0"), ["192.168.1.30/26"])
        self.assertIn(
            "ip addr replace 192.168.1.30/26 dev portus0",
            self.init_file.read_text(),
        )
        interfaces = self.interfaces_file.read_text()
        self.assertIn("    address 192.168.1.30\n", interfaces)
        self.assertIn("    netmask 255.255.255.192\n", interfaces)
        self.assertIn("    address 192.0.5.10\n", interfaces)

    def test_cancel_removes_staged_address_and_keeps_old_config(self):
        prepared = self.run_helper("prepare", "eth0", "192.0.5.20/24")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        original_init = self.init_file.read_text()
        original_interfaces = self.interfaces_file.read_text()

        result = self.run_helper("cancel")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.addresses("eth0"), ["192.0.5.10/24"])
        self.assertEqual(self.init_file.read_text(), original_init)
        self.assertEqual(self.interfaces_file.read_text(), original_interfaces)

    def test_timeout_removes_staged_address_and_keeps_old_config(self):
        prepared = self.run_helper(
            "prepare", "eth0", "192.0.5.20/24", timeout="1"
        )
        self.assertEqual(prepared.returncode, 0, prepared.stderr)

        rolled_back = self.wait_for(
            lambda: self.addresses("eth0") == ["192.0.5.10/24"]
        )

        self.assertTrue(rolled_back, "rollback timer did not remove staged IP")
        self.assertEqual(self.init_file.read_text().split("IP=", 1)[1].splitlines()[0],
                         "192.0.5.10")
        self.assertIn("    address 192.0.5.10\n", self.interfaces_file.read_text())

    def test_timeout_waits_for_lock_before_rolling_back(self):
        prepared = self.run_helper(
            "prepare", "eth0", "192.0.5.20/24", timeout="1"
        )
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        lock_dir = self.run_dir / "lumen-set-ip.lock"
        lock_dir.mkdir()
        lock_owner = subprocess.Popen(["sleep", "30"])
        self.addCleanup(
            lambda: (
                lock_owner.terminate(),
                lock_owner.wait(),
            )
            if lock_owner.poll() is None
            else None
        )
        (lock_dir / "pid").write_text(f"{lock_owner.pid}\n")

        def cleanup_lock():
            if lock_dir.exists():
                (lock_dir / "pid").unlink(missing_ok=True)
                lock_dir.rmdir()

        self.addCleanup(cleanup_lock)

        time.sleep(1.3)
        self.assertEqual(
            self.addresses("eth0"), ["192.0.5.10/24", "192.0.5.20/24"]
        )

        lock_owner.terminate()
        lock_owner.wait()
        rolled_back = self.wait_for(
            lambda: self.addresses("eth0") == ["192.0.5.10/24"]
        )
        self.assertTrue(rolled_back, "rollback did not resume after lock release")

    def test_timeout_worker_does_not_release_active_confirmation_lock(self):
        prepared = self.run_helper(
            "prepare", "eth0", "192.0.5.20/24", timeout="1"
        )
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        environment = self.environment.copy()
        environment["SSH_CONNECTION"] = "192.0.5.30 42003 192.0.5.20 22"
        environment["FAKE_IP_DELAY_DELETE"] = "2"
        confirm = subprocess.Popen(
            ["sh", str(self.script), "confirm"],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        def cleanup_confirm():
            if confirm.poll() is None:
                confirm.kill()
            confirm.communicate()

        self.addCleanup(cleanup_confirm)

        updated = self.wait_for(
            lambda: "IP=192.0.5.20\n" in self.init_file.read_text()
        )
        self.assertTrue(updated, "confirmation did not reach config update")
        time.sleep(1.2)
        lock_dir = self.run_dir / "lumen-set-ip.lock"
        self.assertIsNone(confirm.poll(), "confirmation finished before lock check")
        self.assertTrue(lock_dir.is_dir(), "timer released confirmation lock")

        stdout, stderr = confirm.communicate(timeout=5)
        self.assertEqual(confirm.returncode, 0, stdout + stderr)

    def test_failed_config_write_restores_both_files(self):
        prepared = self.run_helper("prepare", "eth0", "192.0.5.20/25")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        original_init = self.init_file.read_text()
        original_interfaces = self.interfaces_file.read_text()
        self.network_dir.chmod(0o555)
        self.addCleanup(lambda: self.network_dir.chmod(0o755))

        result = self.run_helper(
            "confirm",
            ssh_connection="192.0.5.30 42002 192.0.5.20 22",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.init_file.read_text(), original_init)
        self.assertEqual(self.interfaces_file.read_text(), original_interfaces)
        self.assertEqual(
            self.addresses("eth0"), ["192.0.5.10/24", "192.0.5.20/25"]
        )
        self.assertEqual(self.run_helper("cancel").returncode, 0)


if __name__ == "__main__":
    unittest.main()

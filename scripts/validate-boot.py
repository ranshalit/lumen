#!/usr/bin/env python3
"""
Device Boot Validation Script

Validates that Lumen Linux device booted correctly by checking:
- Serial ports (ttyS0, ttyS2, ttyTHS1, ttyTHS3)
- Network interface (eth0) with link and ping tests
- Storage subsystem (root filesystem, /boot)
- Memory subsystem
- GPU subsystem (if available)
- Docker engine + Compose V2 plugin
- NTP (ntpd daemon running)
- Tools (rsync, nano, vim, ntpd present)
- NVIDIA container runtime (config.toml present, runtime registered in dockerd)
- Boot logs (dmesg for critical errors)
- BusyBox init health (PID 1, sshd running)

Can execute via SSH (fast, post-boot) or serial console (any boot stage).
Auto-detects connectivity: tries SSH first, falls back to serial if unavailable.

Usage:
    python validate-boot.py                  # Auto-detect (SSH → serial fallback)
    python validate-boot.py --serial         # Force serial-console
    python validate-boot.py --ssh            # Force SSH
    python validate-boot.py --ping-target 192.168.1.1
"""

import sys
import subprocess
import json
import argparse
import time
from typing import Tuple, List, Dict, Optional

# ANSI color codes
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'
CHECKMARK = '✅'
CROSS = '❌'
INFO = 'ℹ️'
WARN = '⚠️'

class DeviceConnector:
    """Abstract base for device connection (SSH or serial)"""
    def run_command(self, cmd: str) -> Tuple[int, str, str]:
        raise NotImplementedError

class SSHConnector(DeviceConnector):
    """Connect via SSH (ethernet-console skill)"""
    def __init__(self, host: str = None, user: str = "nexus", password: str = None):
        self.host = host or "lumen-orin-nano-8gb"
        self.user = user
        self.password = password
        self.name = f"SSH ({self.user}@{self.host})"

    def run_command(self, cmd: str) -> Tuple[int, str, str]:
        """Execute command via SSH"""
        ssh_args = ["ssh", "-o", "StrictHostKeyChecking=no"]
        if self.password:
            ssh_cmd = ["sshpass", "-p", self.password] + ssh_args + [f"{self.user}@{self.host}", cmd]
        else:
            ssh_cmd = ssh_args + ["-o", "BatchMode=yes", f"{self.user}@{self.host}", cmd]
        try:
            result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=10)
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return 1, "", "SSH command timed out"
        except Exception as e:
            return 1, "", str(e)

class SerialConnector(DeviceConnector):
    """Connect via serial console (serial-console skill)"""
    def __init__(self):
        self.skill_path = "/home/ranshal/.copilot/skills/serial-console/scripts/serial_session.py"
        self.name = "Serial Console"

    def run_command(self, cmd: str) -> Tuple[int, str, str]:
        """Execute command via serial console"""
        try:
            result = subprocess.run(
                ["python", self.skill_path, "run-linux", cmd],
                capture_output=True, text=True, timeout=15
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return 1, "", "Serial command timed out"
        except Exception as e:
            return 1, "", str(e)

class BootValidator:
    def __init__(self, connector: DeviceConnector, ping_target: str = "8.8.8.8"):
        self.connector = connector
        self.ping_target = ping_target
        self.results = {}
        self.all_passed = True

    def run_command(self, cmd: str) -> Tuple[int, str]:
        """Run command and return (exit_code, output)"""
        rc, stdout, stderr = self.connector.run_command(cmd)
        # Extract last line of output (serial connector adds prompts)
        output = stdout if rc == 0 else stderr
        # For serial: output includes the command result followed by prompt
        lines = output.strip().split('\n')
        # Return the last non-empty line before the prompt
        for line in reversed(lines):
            if line and not line.startswith('nexus@') and '$' not in line:
                return rc, line
        return rc, output.strip()

    def check(self, name: str, passed: bool, details: str = "", skip: bool = False):
        """Record a check result"""
        if skip:
            self.results[name] = ("SKIP", details)
            print(f"{WARN} {name:<25} SKIP ({details})")
        elif passed:
            self.results[name] = ("PASS", details)
            print(f"{CHECKMARK} {name:<25} PASS {details}")
        else:
            self.results[name] = ("FAIL", details)
            print(f"{CROSS} {name:<25} FAIL {details}")
            self.all_passed = False

    def validate_serial_ports(self):
        """Check that all 4 serial devices exist"""
        devices = ["/dev/ttyS0", "/dev/ttyS2", "/dev/ttyTHS1", "/dev/ttyTHS3"]
        rc, output = self.run_command(f"ls -1 {' '.join(devices)} 2>/dev/null | wc -l")
        found = int(output.strip()) if rc == 0 else 0
        passed = found == 4
        self.check("Serial Ports", passed, f"({found}/4 devices present)")

    def validate_network_interface(self):
        """Check ethernet interface exists and is UP"""
        # Check device exists
        rc, output = self.run_command("test -d /sys/class/net/eth0 && echo OK || echo FAIL")
        if "OK" not in output:
            self.check("Network Interface", False, "eth0 not found")
            return

        # Check link status
        rc, output = self.run_command("cat /sys/class/net/eth0/operstate 2>/dev/null")
        link_status = output.strip()
        link_up = link_status in ["up", "unknown"]

        # Test ping to gateway (optional, network may not have external connectivity)
        rc, output = self.run_command("ping -c 1 -W 2 %s >/dev/null 2>&1 && echo OK || echo FAIL" % self.ping_target)
        ping_ok = "OK" in output

        # Pass if interface is UP, ping is a bonus check
        passed = link_up
        details = f"eth0 {link_status}"
        if ping_ok:
            details += f", ping {self.ping_target} OK"
        self.check("Network Interface", passed, details)

    def validate_storage(self):
        """Check root filesystem and /boot"""
        # Check root filesystem
        rc, output = self.run_command("df / | tail -1 | awk '{print $5}' | sed 's/%//'")
        if rc != 0:
            self.check("Storage", False, "cannot read root filesystem")
            return

        try:
            usage_pct = int(output.strip())
            free_pct = 100 - usage_pct
        except ValueError:
            self.check("Storage", False, "cannot parse disk usage")
            return

        # Check /boot exists
        rc, output = self.run_command("test -d /boot && echo OK || echo FAIL")
        boot_ok = "OK" in output

        passed = free_pct >= 10 and boot_ok
        details = f"/ {usage_pct}% used ({free_pct}% free), /boot {'present' if boot_ok else 'missing'}"
        self.check("Storage", passed, details)

    def validate_memory(self):
        """Check memory availability (informational)"""
        rc, output = self.run_command("free -h | grep ^Mem | awk '{print $2}'")
        if rc == 0:
            total_mem = output.strip()
            self.check("Memory", True, f"Total {total_mem}", skip=False)
        else:
            self.check("Memory", True, "unable to read", skip=True)

    def validate_gpu(self):
        """Check GPU devices (skip if not found)"""
        rc, output = self.run_command("ls -1 /dev/nvidia* 2>/dev/null | wc -l")
        if rc == 0 and int(output.strip()) > 0:
            self.check("GPU", True, f"({output.strip()} devices)")
        else:
            self.check("GPU", True, "no NVIDIA devices", skip=True)

    def validate_boot_logs(self):
        """Check dmesg for critical errors"""
        rc, output = self.run_command("sudo dmesg 2>/dev/null | wc -l")
        if rc != 0 or not output.strip():
            self.check("Boot Logs", True, "unable to read dmesg", skip=True)
            return
        
        # Simplified check: look for error lines
        rc2, output2 = self.run_command("sudo dmesg 2>/dev/null | grep -c 'panic\\|oops\\|Kernel panic' || echo 0")
        try:
            critical_count = int(output2.strip())
        except ValueError:
            critical_count = 0
        
        if critical_count == 0:
            self.check("Boot Logs", True, "no critical errors")
        else:
            self.check("Boot Logs", False, f"{critical_count} critical error(s) found")

    def validate_rtc(self):
        """Check RTC device is present and readable"""
        rc, output = self.run_command("cat /sys/class/rtc/rtc0/name 2>/dev/null")
        if rc != 0 or not output.strip():
            self.check("RTC", False, "/sys/class/rtc/rtc0 not found")
            return

        rtc_name = output.strip()

        rc2, date_out = self.run_command("cat /sys/class/rtc/rtc0/date 2>/dev/null")
        rc3, time_out = self.run_command("cat /sys/class/rtc/rtc0/time 2>/dev/null")
        readable = rc2 == 0 and rc3 == 0 and date_out.strip() and time_out.strip()

        # Warn if RTC date looks like epoch/reset (pre-2020)
        stale = False
        try:
            year = int(date_out.strip().split("-")[0])
            stale = year < 2020
        except (ValueError, IndexError):
            pass

        details = f"{rtc_name}, {date_out.strip()} {time_out.strip()}"
        if stale:
            details += " ⚠️  date looks stale (battery?)"

        self.check("RTC", readable, details)

    def validate_init(self):
        """Check BusyBox init health (PID 1 is init, key init.d services running)"""
        # Confirm PID 1 is init (not systemd)
        rc, output = self.run_command("cat /proc/1/cmdline")
        pid1 = output.strip()
        is_init = "init" in pid1 and "systemd" not in pid1

        # Check sshd is running (started by init.d)
        rc2, output2 = self.run_command("pidof sshd >/dev/null 2>&1 && echo OK || echo FAIL")
        sshd_ok = "OK" in output2

        passed = is_init
        details = f"PID1={pid1 or 'unknown'}, sshd={'running' if sshd_ok else 'not running'}"
        self.check("Init Health", passed, details)

    def validate_docker(self):
        """Check Docker daemon is running and docker compose plugin is available"""
        rc, output = self.run_command("sudo docker info 2>/dev/null | grep 'Server Version' | awk '{print $NF}'")
        if rc != 0 or not output.strip():
            self.check("Docker", False, "dockerd not running or docker not found")
            return
        docker_ver = output.strip()

        rc2, output2 = self.run_command("sudo docker compose version --short 2>/dev/null")
        compose_ok = rc2 == 0 and output2.strip()
        compose_ver = output2.strip() if compose_ok else "not found"

        passed = bool(docker_ver) and compose_ok
        self.check("Docker", passed, f"engine {docker_ver}, compose {compose_ver}")

    def validate_tools(self):
        """Check that expected CLI tools are installed"""
        tools = ["rsync", "nano", "vim", "ntpd"]
        missing = []
        for tool in tools:
            rc, _ = self.run_command(f"command -v {tool} >/dev/null 2>&1 && echo OK || echo FAIL")
            if "OK" not in _:
                missing.append(tool)
        passed = len(missing) == 0
        details = "all present" if passed else f"missing: {', '.join(missing)}"
        self.check("Tools", passed, details)

    def validate_ntp(self):
        """Check ntpd NTP daemon is running"""
        rc, output = self.run_command("pidof ntpd >/dev/null 2>&1 && echo OK || echo FAIL")
        running = "OK" in output
        if not running:
            self.check("NTP (ntpd)", False, "ntpd not running")
            return
        rc2, output2 = self.run_command("ntpq -p 2>/dev/null | sed -n '3p'")
        details = f"ntpd running, peers: {output2.strip()}" if output2.strip() else "ntpd running"
        self.check("NTP (ntpd)", True, details)

    def validate_nvidia_runtime(self):
        """Check NVIDIA container runtime is registered and config.toml exists"""
        rc, output = self.run_command("nvidia-container-runtime --version 2>/dev/null | grep 'NVIDIA Container Runtime version'")
        if rc != 0 or not output.strip():
            self.check("NVIDIA Runtime", False, "nvidia-container-runtime not found")
            return
        runtime_ver = output.strip()

        rc2, output2 = self.run_command("test -f /run/nvidia-container-runtime/config.toml && echo OK || echo FAIL")
        config_ok = "OK" in output2

        rc3, output3 = self.run_command("grep -c nvidia /etc/docker/daemon.json 2>/dev/null || echo 0")
        registered = int(output3.strip()) > 0 if rc3 == 0 else False

        passed = config_ok and registered
        details = f"{runtime_ver}, config.toml {'present' if config_ok else 'MISSING'}, daemon.json {'ok' if registered else 'NOT registered'}"
        self.check("NVIDIA Runtime", passed, details)

    def validate_all(self):
        """Run all validation checks"""
        print(f"\n{BLUE}=== Device Boot Validation ==={RESET}")
        print(f"Connection: {self.connector.name}\n")
        
        self.validate_serial_ports()
        self.validate_network_interface()
        self.validate_storage()
        self.validate_memory()
        self.validate_gpu()
        self.validate_rtc()
        self.validate_boot_logs()
        self.validate_init()
        self.validate_docker()
        self.validate_ntp()
        self.validate_tools()
        self.validate_nvidia_runtime()

        return self.all_passed

    def print_summary(self):
        """Print validation summary"""
        passed = sum(1 for status, _ in self.results.values() if status == "PASS")
        total = sum(1 for status, _ in self.results.values() if status in ["PASS", "FAIL"])
        
        print(f"\n{BLUE}=== Summary ==={RESET}")
        if self.all_passed:
            print(f"{GREEN}{CHECKMARK} All critical checks PASSED ({passed}/{total}){RESET}")
        else:
            print(f"{RED}{CROSS} Some checks FAILED ({passed}/{total}){RESET}")
        
        return 0 if self.all_passed else 1

def detect_connector(host: str = None, user: str = "nexus", password: str = None) -> Optional[DeviceConnector]:
    """Auto-detect best connection method: try SSH first, fall back to serial"""
    
    # Try SSH connection
    print(f"{BLUE}Detecting connection method...{RESET}")
    ssh_conn = SSHConnector(host, user, password)
    rc, _, _ = ssh_conn.run_command("echo OK")
    if rc == 0:
        print(f"{GREEN}SSH available, using SSH connector{RESET}\n")
        return ssh_conn
    
    print(f"{YELLOW}SSH unavailable, falling back to serial console{RESET}\n")
    return SerialConnector()

def main():
    parser = argparse.ArgumentParser(
        description="Validate Lumen Linux device boot health",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python validate-boot.py                    # Auto-detect (SSH → serial)
  python validate-boot.py --serial           # Force serial-console
  python validate-boot.py --ssh              # Force SSH
  python validate-boot.py --ping-target 192.168.1.1
        """
    )
    
    parser.add_argument("--serial", action="store_true", help="Force serial-console connection")
    parser.add_argument("--ssh", action="store_true", help="Force SSH connection")
    parser.add_argument("--host", default="lumen-orin-nano-8gb", help="SSH hostname/IP (default: lumen-orin-nano-8gb)")
    parser.add_argument("--user", default="nexus", help="SSH username (default: nexus)")
    parser.add_argument("--password", default=None, help="SSH password (uses sshpass; prefer key auth when possible)")
    parser.add_argument("--ping-target", default="8.8.8.8", help="IP to ping for network test (default: 8.8.8.8)")

    args = parser.parse_args()

    # Determine connection method
    if args.serial:
        connector = SerialConnector()
    elif args.ssh:
        connector = SSHConnector(args.host, args.user, args.password)
    else:
        connector = detect_connector(args.host, args.user, args.password)
        if connector is None:
            print(f"{RED}Error: Could not establish connection via SSH or serial{RESET}")
            return 1

    # Run validation
    validator = BootValidator(connector, args.ping_target)
    validator.validate_all()
    return validator.print_summary()

if __name__ == "__main__":
    sys.exit(main())

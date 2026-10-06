# Portus USB0 storage investigation

## Current status (2026-10-06)

The two archived captures in this directory, `cmp-lumen-orin-nx-16gb-1354.tgz`
(Yocto) and `cmp-nexus-1124_ubuntu.tgz` (Ubuntu), both show the same Alcor
`058f:6387` 2 GB flash drive enumerated on Portus port 2 (`1-3.1.2`), with
`sdb1` and no USB errors. **They are from different Lumen units** (different
device-tree serial numbers), and neither includes the extra hubs or 512 GB
device seen in the remote failure. Yocto hot-plugged the drive; Ubuntu saw it
at boot. These captures prove Portus USB storage works with either image in
this simpler setup; they do not isolate the remote failure or rule out an
image-dependent interaction with its deeper hub chain.

The remote screenshots show `-71` descriptor errors after a hub subtree
disconnect. The 0 B `sdb`/`sdc` entries appear to be a two-LUN reader with no
media, but the screenshots do not identify the 512 GB drive. Capture `lsusb -t`
and `lsblk` on the failing setup to identify its actual USB path. An unsupported
filesystem would affect mounting, not USB address assignment.

## Symptom

- Initial report: a USB storage device plugged into the Portus M.2 Key A/E card's USB0 port (DF52 connector, through a DF52-to-USB adapter) showed **nothing in `dmesg`** on Lumen boards running our Yocto image. Later remote screenshots showed USB enumeration errors; later local tests worked.
- The Portus Ethernet (lan743x) and its two FT230X UARTs work.
- The drive's LED is **white** on the Lumen. On a laptop it is **green**, even while idle.
- **Cross-board comparison:** the **same Portus card, DF52-to-USB adapter and flash USB storage device** are detected on a **different Lumen board** running stock NVIDIA L4T Ubuntu with Aerium's BSP script (`scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh`).
  - Both the board and software configuration differ. Whether the same physical Jetson module was used in both tests is **not confirmed**; this comparison alone cannot isolate software from board/module differences.
  - Two Yocto boards fail.
- The same storage device works when connected to the board's USB1 connector instead of Portus USB0. "USB1" here names the physical connector, not Linux USB bus 1; capture its `lsusb -t` path to establish which controller/hubs it uses.
- Connecting the storage device to Portus USB0 **before powering on** a Yocto board gives the same failure as plugging it in after boot. Hotplug timing alone does not explain the symptom.
- Tested `cat /sys/class/usb_role/usb2-0-role-switch/role` on both configurations (Yocto and stock NVIDIA L4T Ubuntu with the Aerium BSP): **both returned `host`**. An unset host role is therefore not an explanation for the observed difference; the role-switch name alone does not identify Portus wiring.

## Update 2026-10-05: drive plugged in after power-up (board 192.0.5.44)

The earlier "nothing in dmesg" report is wrong. Enumeration **does** happen, but it fails deep in the chain:

```
1-3       Lumen USB2514 hub
1-3.1     Portus USB2514B hub
1-3.1.2   external hub (inside the adapter/converter chain)
1-3.1.2.3 second external hub, 4 ports
          ├─ .1  0c76:153f USB PnP Audio (full-speed), enumerates OK
          ├─ .2  "Generic Mass-Storage 2.00", 2 LUNs (sdb/sdc)
          └─ .4  another device
```

Sequence seen in dmesg:
1. `1-3.1.2.3.2` enumerates once as mass storage with 2 LUNs. Both report `Media removed, stopped polling`, so `sdb`/`sdc` are 0B with no partitions.
2. Then **the whole `1-3.1.2` subtree disconnects** (devices 20–25) and re-enumerates. This establishes that the upstream hub disconnected or reset; it does not establish a 5V brownout.
3. After that, `1-3.1.2.3.2` fails repeatedly:
   - `device descriptor read/64, error -71`
   - `attempt power cycle`
   - `Device not responding to setup address`
   - `device not accepting address NN, error -71`
   - `unable to enumerate USB device`
4. `lsblk` shows only `sda` at 0B. That is the Lumen's own Genesys microSD reader with no card, which is normal.

The **same drive works on Lumen USB1**. Its USB path and power margin were not measured in the remote setup.

Interpretation:
- `-71` (EPROTO), "not accepting address", and a full subtree disconnect show a USB enumeration/link failure, not an unsupported filesystem. Potential causes include power, signal integrity, hub state and controller behavior; none has been isolated.
- The failing device sits behind **four downstream hub devices** (Lumen, Portus and two more), plus the root hub: root → Lumen hub → Portus hub → hub → hub → device. This is the USB 2.0 hub-depth limit.
- Everything downstream is powered from the Portus DF52 5V, which the card generates from the M.2 3.3V rail.
- The 0B LUNs plus "Media removed" suggest `.2` may be an empty multi-slot reader. Do not identify it as the 512 GB drive without its USB descriptor and storage path.

Open question: why does the Ubuntu Lumen work with the same chain? Compare `lsusb -t` and dmesg on Ubuntu, including whether the subtree disconnect happens there too and whether the device enumerates at the same speed.

The Portus, adapter and drive are identical in both setups, so the difference must be the **Lumen unit** or **our software/firmware**:
- **Hardware:** the Lumen's M.2 Key E 3.3V rail (which feeds the Portus 5V) differs in strength or transient response, or the M.2 seating differs.
- **Software/firmware:** USB2 link-power-management (LPM) behaviour, USB pad/PHY tuning in the live device tree, QSPI/UEFI firmware, or the USB controller firmware.

Discriminating tests:
1. **Swap the NVMe SSDs** between the two Lumens. If the failure follows the SSD, it's our image; if it stays with the board, it's that Lumen unit. Caveat: each board keeps its own QSPI, and an L4T version mismatch may prevent booting.
2. On the failing board, test the same chain with external hub power. If that fixes it, investigate power delivery along the chain; it does not by itself identify the M.2 rail.
3. Measure M.2 Key E 3.3V on both Lumens, and DF52 pin 1, while plugging in the drive.

**QSPI may differ between the boards; its contents were not compared.**
- The boards may have different QSPI images; the archived captures do not establish their complete QSPI contents. The Yocto build includes a stripped UEFI (`f758bac`) and our BCT patch (`tegra-bootfiles_%.bbappend`).

QSPI holds MB1/MB2 BCT (pinmux, pad voltages, initial GPIO states, PMIC/regulator setup), BPMP firmware plus its DTB, and UEFI. Any of these can affect USB pad tuning or the power behaviour of the M.2 rail. So:
- swapping only the NVMe SSDs tests **rootfs, kernel and DTB**, not QSPI;
- for a complete test, flash the **full Yocto image (QSPI + NVMe)** onto the Ubuntu-working Lumen, or the full stock/BSP Ubuntu image onto the failing Lumen;
- compare on both boards:
  - `cat /sys/class/dmi/id/bios_version` (UEFI version)
  - `/etc/nv_tegra_release`
  - `/sys/kernel/debug/pinctrl/*/pinconf-groups`
  - `/sys/kernel/debug/gpio`
  - `/sys/kernel/debug/regulator/regulator_summary`.

## Platform

- Orin NX 16GB, L4T R36.5, kernel 5.15.185-l4t-r36.5, BusyBox sysvinit (no systemd), no initramfs.
- DTB: stock `tegra234-p3768-0000+p3767-0000-nv.dtb`, patched in `meta-lumen/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot_%.bbappend`.

## USB topology (confirmed on the board)

```
xHCI root hub (bus 1)
├─ 1-1  FT232R (debug)
├─ 1-2  thermal camera
└─ 1-3  Lumen USB2514 hub
   ├─ 1-3.1  Portus USB2514B hub
   │   ├─ port 1/2 : USB0 (DF52 pins 1=5V, 2=D−, 3=D+, 8=GND)   ← storage expected here
   │   ├─ port 3   : FT230X (ttyUSB0)
   │   └─ port 4   : FT230X (ttyUSB1)
   └─ 1-3.2  Genesys microSD reader (/dev/sda)
```

- `1-3.1` is the Portus hub: it disappears when Portus is removed.
- `1-3.2` is the separate, always-present Genesys microSD reader, **not** evidence that a drive plugged into Portus USB0 enumerated. Older logs detect this reader as `usb-storage` and then report `Media removed`; they do not show a usable inserted USB drive on Portus.
- The USB2514B has 4 ports by design. The Portus docs mention "two downstream ports", but the connector exposes only one USB 2.0 port.
- The raw `GET_PORT_STATUS` reading of Portus ports 1 and 2 was `0x0100` (POWER only, not connected).
  - **This was taken WITHOUT the drive plugged in, so it proves nothing.**

## What was checked and ruled out

| Item | Result |
|---|---|
| Kernel USB host, hub and storage support (`USB`, `XHCI_TEGRA`, `USB_STORAGE`, `SCSI`, `BLK_DEV_SD`) | All `=y`. No Portus-specific driver is needed (the USB2514B is a standard hub). |
| Repo vs. Aerium BSP script | All BSP items are implemented. The usb2-0 role setting differs in the scripts (ours **host**, BSP **device**), but `cat /sys/class/usb_role/usb2-0-role-switch/role` returned **host on both configurations**. Portus sits under `1-3`; the role-switch name alone does not establish a connection to it. |
| Kernel strip fragments (boot optimization, phases 1-5) | No USB host, hub, storage or power-management option was removed. |
| Device tree nodes disabled for boot time (PCIe C7, audio/HDA, SPI, UART DMA) | Not on the USB path. |
| Missing `uas` module (`USB_UAS=m`, `kernel-module-uas` not in the image) | Could only explain "device enumerates but no disk", not "nothing in dmesg". Worth adding anyway. |
| `udev`, filesystem modules, `nvpmodel` | Enumeration messages appear in dmesg before any of these run. Very unlikely. |
| LED colour | Vendor-specific. White means the drive has power; it does not identify a link state. |

## Boot-optimization commits: possible relevance

| Commit | Change | Possible effect | Likelihood |
|---|---|---|---|
| `f758bac` | UEFI built with USB host disabled (`CONFIG_XHCI/EHCI/SOC_USB` off) | This could change QSPI boot firmware if flashed; QSPI contents were not compared. Linux reinitialises xHCI itself. | Low |
| `0b47d87` | systemd replaced by BusyBox sysvinit | NVIDIA's Ubuntu boot services are absent. | Low |
| `1a1a916` | `quiet loglevel=0` | USB messages are **not printed on the serial console**. `dmesg` still shows them, so always check `dmesg` and not the console. | Check |
| `b257bd4` | usb2-0 host role script | Our nx16 image was built 2026-07-29 11:20, before this commit (11:44). Confirm which image the boards run. | Low |
| `6851037`, `99d157b`, `5f8abc2` | Device tree node disables | Not on the USB path. | Very low |

**USB autosuspend:** our image does **not** set `usbcore.autosuspend=-1`; `testing/dmesg-yocto` records a kernel command line without it. The kernel default applies (`CONFIG_USB_AUTOSUSPEND_DELAY=2`). This does **not** prove autosuspend caused the failure: that same log shows the always-present reader at `1-3.2` enumerating without the option. Runtime policy is per device/hub; Portus adds a hub and an upstream link absent from a direct USB1 connection, either of which could behave differently on suspend/resume. Compare actual `power/control` and `power/runtime_status` for `1-3`, `1-3.1` and the USB1 path on both images.

## Ranked suspects

1. **Board, SOM or boot-firmware difference** (QSPI/UEFI, BPMP, XUSB firmware, SOM variant). Different board serial numbers were found in the archived captures; QSPI contents were not compared.
2. **Portus hub power management / autosuspend.** This is compatible with a drive working on USB1, which may have a different path, but is not established by the missing boot argument. Failure with the drive inserted before power-on weakens a hotplug-only/resume-only explanation; it does not rule out power-management effects after the hub initializes.
3. **Missed hub event or a stuck USB2514/xHCI state.** A purely hotplug-only explanation is weakened by the failed cold-plug test. Check whether the port shows a connection (`CONN`) without a `1-3.1.x` device before ranking this higher.
4. **Downstream 5V or data electrical difference on that Lumen unit** (M.2 3.3V rail or transient behaviour, connector seating). The same power supply does not guarantee the same rail behaviour.
5. **Wrong device tree or SOM selection deployed.** Compare the live FDT, not the source files.
6. Missing `uas`: low.
7. USB2 link-power-management (LPM) or xHCI quirk difference between the kernels: low–medium.
8. usb2-0 role / FUSB301 probe failure (-22): very low.
9. udev / userspace: very low.

## Next tests

0. **Highest priority, given the update:**
   - Test the remote chain with a **self-powered (externally powered) USB hub**. If the drive then enumerates, investigate the chain's power delivery; the exact limiting rail remains unproven.
   - Connect the drive with **as few hubs as possible** (no extra adapter hub).
   - Measure DF52 pin 1 (5V) at the moment the drive is plugged in.
   - On the Ubuntu board, capture `lsusb -t` and `dmesg` with the same chain.

1. **Hub port status before and after plugging in** (most decisive). Read `GET_PORT_STATUS` on `1-3.1` ports 1 and 2:
   - no `CONN` → electrical problem or the hub port's power/configuration;
   - `CONN` set but no new device → a lost event, power management or a reset issue;
   - device present but no disk → `uas` or storage driver.
2. **Compare USB1 vs. Portus USB0 on the same board:** use the same drive and cable/adapter where possible. With the drive unplugged, record `lsusb`, `lsusb -t`, `lsblk -o NAME,TRAN,SIZE,MODEL,TYPE` and the Portus hub's power state; watch `dmesg -w` while plugging into each connector. A new USB device without a disk points to binding/media; no new device under `1-3.1` points to the Portus hub, link, port power or connection. Repeat on the working image to distinguish image from hardware differences.
3. **Cold plug vs. hot plug (done):** booting with the drive already connected to Portus USB0 also failed on Yocto. Do not treat the issue as hotplug-only; capture `dmesg`, `lsusb -t` and hub port status during a cold boot with the drive connected to determine whether the hub sees the device at all.
4. **Test runtime autosuspend** (on a test board, after capturing the failing baseline, before plugging in again):
   ```sh
   echo -1 > /sys/module/usbcore/parameters/autosuspend
   for d in /sys/bus/usb/devices/*/power/control; do echo on > "$d"; done
   cat /sys/module/usbcore/parameters/autosuspend
   dmesg -w
   ```
   Run as root; verify the affected hub's `power/control` actually reads `on`. The first write changes the default for newly attached devices; the loop changes current devices (including unrelated USB devices). Both are temporary and do not necessarily wake or re-enumerate a device already missing. If repeated unplug/replug tests now work, repeat with **only one change at a time**, ideally targeting `1-3.1/power/control`, to isolate the cause. Do not add a permanent boot parameter until this is reproduced. An earlier write to `power/control` returned EIO; record the exact path and value if it happens again.
5. **Re-trigger the hub:** deauthorize and reauthorize `1-3.1` (this also resets the Portus UARTs) with the drive inserted.
6. **Compare with the Ubuntu board:**
   - `cat /proc/cmdline`
   - `cat /sys/module/usbcore/parameters/autosuspend`
   - `uname -a`, `/etc/nv_tegra_release`
   - live FDT (`/sys/firmware/fdt`)
   - XUSB firmware timestamp in dmesg
   - QSPI/UEFI version and SOM ID.
7. **Control board/module vs. image differences:** record the physical carrier-board and Jetson-module identities used in each configuration. An Ubuntu NVMe SSD was reported to work on a Lumen that failed with Yocto, but the archived comparison captures come from different physical units. Repeat on the **problematic physical board**, with the same Portus card, adapter, exact failing drive and hub chain, and record whether QSPI firmware changes.
8. **Electrical check:** if `CONN` never appears, measure DF52 pin 1 (5V) while plugging in.
9. **Capture script:** run `sudo sh testing/usb_diag.sh` on both boards with the drive inserted and diff the results. Extend it to capture before/after port status, `lsusb -v` hub descriptors, `authorized`/`persist` and runtime power-management state.

## Update 2026-10-05: SSD swap result

- The **Ubuntu NVMe SSD** was moved into the Lumen that failed with Yocto. **The Portus USB storage works.**
- Same Portus, adapter and drive. The board keeps its own QSPI, presumably our Yocto flash.

Conclusions:
- This reported swap makes a fixed Lumen hardware fault less likely but does not establish stable power under the failing hub/drive load.
- Unchanged QSPI would make a QSPI-only cause less likely; confirm firmware identity separately. A UEFI version string alone cannot prove identical QSPI contents.
- A possible cause is in **what our NVMe image contains**:
  - **kernel**: config, built-in drivers, our strip fragments;
  - **DTB**: the boot loader takes it from the NVMe A/B `kernel-dtb` partitions or the extlinux `FDT` line;
  - **kernel cmdline**;
  - **rootfs**: modules, firmware, init scripts, power-mode tools such as `nvpmodel`, udev.

The SSD swap does not prove which difference triggered the `-71` and subtree-disconnect errors; retain the failing hub chain and drive when repeating it.

Next, split the NVMe content (each step is one change):
1. **Compare the two setups** while booted on the same board (Ubuntu SSD vs. Yocto SSD):
   - `cat /proc/cmdline`
   - `zcat /proc/config.gz` (if available) or `/boot/config-*`
   - live DT: `sudo cat /sys/firmware/fdt > live.dtb` on the board, then on the PC `dtc -I dtb -O dts -s live.dtb` and diff, focusing on `usb@3610000`, `padctl@3520000` and USB2 pad tuning (`nvidia,*`) properties
   - `lsmod`
   - `/sys/module/usbcore/parameters/*`
   - `/sys/kernel/debug/regulator/regulator_summary`
   - `/sys/kernel/debug/pinctrl/*/pinconf-groups`
   - `nvpmodel -q` on Ubuntu
   - `/etc/nv_tegra_release`
2. **DTB swap:** boot our Yocto SSD with Ubuntu's DTB (add an `FDT /boot/<ubuntu>.dtb` line to our `extlinux.conf`).
   - Works → the cause is our DT patches (`nvidia-kernel-oot_%.bbappend`) or the base DTB.
3. **Kernel swap:** boot our rootfs with Ubuntu's `Image` (kernel image only; most USB drivers are built in).
   - Works → the cause is our kernel config or kernel version.
4. Otherwise it's the rootfs: init/udev, `nvpmodel` and clock settings, firmware files.

Notes:
- The DT regulator `VDD_3V3_PCIE` (GPIO-enabled, not always-on) is used only by `pcie@140a0000`. Our DT disables `pcie@141e0000`, which doesn't use it.
- Check in the live DT and the regulator summary whether the M.2 Key E 3.3V supply or a related GPIO differs between the setups.

## Web research on the -71 / subtree-disconnect errors (2026-10-05)

No public report matches the exact case "works on stock L4T Ubuntu, fails on Yocto, same hardware". The error pattern occurs on Jetson behind hubs but does not distinguish signalling from power or controller/hub behavior. Hypotheses to test on the failing chain:

1. **USB2 pad tuning in the DT** (`padctl@3520000` ports, `nvidia,hs-curr-level-offset`, squelch/termination properties).
   - Only matters in worst cases like ours: direct connection works, the 5-hub-deep chain fails.
   - The DTB comes from the NVMe, so it changes with the SSD swap.
   - Compare the live DTBs (`/sys/firmware/fdt`).
   - Refs: forums.developer.nvidia.com/t/333703, /t/342718.
2. **Kernel config or patch level.** meta-tegra builds with `KCONFIG_MODE=--alldefconfig` on top of its own fragments, so options not listed explicitly fall back to defaults. Diff our `.config` against Ubuntu's `/proc/config.gz` or `/boot/config-*`.
3. **Transaction Translator (TT) handling.** The full-speed USB audio device on `1-3.1.2.3.1` enumerates just before `.2` fails; the `clear tt … -71` → hub reset → subtree disconnect sequence is known. The TT code differs by kernel version.
   - **Test:** remove or disable the audio device and retest. Also check whether Ubuntu's `lsusb -t` shows the same audio device.
4. **Stock L4T userspace** (`nvpmodel`, EMC/clock settings, `nv*` services, udev rules) is missing in our BusyBox rootfs. Compare `nvpmodel -q` and the EMC clock rate (`/sys/kernel/debug/bpmp/debug/clk/emc/rate`) on both systems.

Not a cause: the USB controller (XUSB) firmware is loaded from QSPI, not from the NVMe (our rootfs has no `xusb` firmware file), so both SSDs use the same one. Confirm with the `tegra-xusb … Firmware timestamp` line in the Ubuntu dmesg.

The "Media removed" + 2 LUNs + 0B state is not the root cause: the device attached, and then the whole hub subtree was reset.

## Capture checklist: run on the SAME Lumen, once with the Ubuntu SSD and once with the Yocto SSD

Plug the Portus + adapter + drive in **after** boot (hot-plug), wait about 10 s, then run as root:

```sh
mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug
D=/tmp/cmp-$(hostname)-$(date +%H%M); mkdir -p $D; cd $D

# boot / build identity
uname -a                                   > uname
cat /proc/cmdline                          > cmdline
cat /etc/nv_tegra_release                  > nv_tegra_release 2>&1
cat /sys/class/dmi/id/bios_version         > bios_version 2>&1
cat /proc/device-tree/nvidia,dtsfilename   > dtsfilename 2>&1

# kernel config (Yocto: /proc/config.gz exists; Ubuntu fallback: /boot/config-*)
zcat /proc/config.gz > kernel_config 2>/dev/null || cp /boot/config-$(uname -r) kernel_config

# live device tree (decompile on the PC)
cat /sys/firmware/fdt                      > live.dtb

# modules and USB state
lsmod                                      > lsmod
lsusb                                      > lsusb 2>&1
lsusb -t                                   > lsusb_t 2>&1
lsblk -o NAME,SIZE,FSTYPE,TRAN,MODEL       > lsblk 2>&1
dmesg                                      > dmesg
grep -H . /sys/module/usbcore/parameters/* > usbcore_params

# power / pins / clocks
cat /sys/kernel/debug/regulator/regulator_summary > regulator_summary
cat /sys/kernel/debug/pinctrl/*/pinconf-groups    > pinconf-groups 2>/dev/null
cat /sys/kernel/debug/pinctrl/*/pinmux-pins       > pinmux-pins 2>/dev/null
cat /sys/kernel/debug/gpio                        > gpio
cat /sys/kernel/debug/bpmp/debug/clk/emc/rate     > emc_rate 2>&1
cat /sys/kernel/debug/bpmp/debug/clk/xusb*/rate   > xusb_clk_rate 2>&1
nvpmodel -q                                       > nvpmodel 2>&1   # Ubuntu only

# userspace that may touch USB/clocks (Ubuntu side mostly)
ls /etc/udev/rules.d /lib/udev/rules.d     > udev_rules 2>&1
ls /etc/systemd/system 2>/dev/null | grep -i nv > nv_services

cd /tmp && tar czf "$D.tgz" "$(basename "$D")" && echo "$D.tgz"
```

Alternatively, `testing/usb_diag.sh` captures most of this.

The two archives committed with this document contain board identifiers (device
tree serial numbers and GPIO/debug information); treat them as internal
diagnostic artifacts. Neither captures the remote 512 GB failure.

### Compare on the PC

```sh
# DT: sorted decompile, then focus on USB/padctl/regulators
dtc -I dtb -O dts -s yocto/live.dtb  > yocto.dts  2>/dev/null
dtc -I dtb -O dts -s ubuntu/live.dtb > ubuntu.dts 2>/dev/null
diff yocto.dts ubuntu.dts
# look at: usb@3610000, padctl@3520000 (ports/pads, nvidia,* tuning), pcie@*, regulators

# kernel config: USB / power-management subset first
diff <(grep -E "USB|XHCI|PHY_TEGRA|_PM|HUB" yocto/kernel_config | sort) \
     <(grep -E "USB|XHCI|PHY_TEGRA|_PM|HUB" ubuntu/kernel_config | sort)

# everything else
for f in uname cmdline bios_version dtsfilename usbcore_params emc_rate xusb_clk_rate \
         regulator_summary pinconf-groups pinmux-pins gpio lsmod lsusb_t; do
  echo "=== $f"; diff yocto/$f ubuntu/$f
done
grep -i "xusb\|-71\|disconnect\|not accepting" yocto/dmesg ubuntu/dmesg
```

### Extra quick test
- Disconnect or remove the USB audio device (`1-3.1.2.3.1`) and retry the storage device on Yocto. This tests the Transaction Translator suspect.

## Reference: NVIDIA forum thread 288609 ("Unable to get the USBs running on custom carrier board")

- **Same error signature** as ours: `device descriptor read/64, error -71` → `attempt power cycle` → `not accepting address` → `unable to enumerate`. In their case it was on a root port, on every boot.
- The only fix NVIDIA suggested: every USB3 port must have a valid, unique `nvidia,usb2-companion`; delete USB3 ports that have no USB2 pair. After that change the error remained. NVIDIA then said "software configuration looks correct", implying hardware or signal integrity. The thread closed **unresolved**.
- **Relevance to us is low.** Our DTB has stock pairing (`usb3-0`→usb2-1, `usb3-1`→usb2-0, `usb3-2/3` disabled, `usb2-3` disabled) and no USB2 pad tuning properties. Software dependence has not been established on the failing hub chain.
- **Takeaway:** `-71` means a link-level failure (CRC errors or no response), not a driver problem. So look for software that changes the signal or timing margin: the DT, power and clock settings, and the kernel's hub/TT handling.

## Reference: NVIDIA forum thread 187284 ("USB is not recognized occasionally")

- Jetson **Nano** (T210) on a custom carrier with a VL817 hub. Root-port `error -71` / `unable to enumerate` appeared in **11 of 500 DC power cycles**.
- NVIDIA's fix was **hardware power sequencing**: make all carrier rails stable before asserting `POWER_EN` (200+ ms delay if needed), and add a supercap or backup battery on `BBAT`.
- **Not relevant to us.**
  - Different SoC.
  - Their failure was intermittent and tied to power-up; ours is deterministic and happens on hot-plug after boot.
  - An Ubuntu SSD was reported working on the same board, but the remote chain has not been captured under both images.

## Reference: NVIDIA forum thread 352602 ("USB issue with Jetson Orin NX on Nano devkit")

- **Very close to our case:**
  - Orin NX on L4T R36.
  - **Yocto/meta-tegra image**.
  - Device **behind 2 hubs**, one of them a USB2514.
  - `error -110/-71`, `attempt power cycle`, `not accepting address`, `unable to enumerate`.
  - Works on Ubuntu 24.04 and Windows. Only `usbreset` of the hub or a hub power cycle recovered it.
- **Root cause:** their **userspace app (libusb) opened and claimed the device too early** during enumeration, which wedged the hub port. It was not a kernel or DT issue.
- **For us:**
  - No libusb, pyusb or `/dev/bus/usb` users were found in `meta-lumen` or `scripts`.
  - Our udev rules only add tty symlinks plus a net rename.
  - Still check whether any **application running on the board** (camera/Pixhawk/Teensy app, Docker containers with `/dev/bus/usb` mounted or `--privileged`) scans or opens USB devices at hot-plug.
  - **Test:** stop all apps and containers, then hot-plug.
  - **Recovery test:** `usbreset` the failing hub (`/dev/bus/usb/001/<dev of 1-3.1.2.3>`), or unbind/rebind it, to see if `.2` then enumerates.

## Update 2026-10-06: earlier capture pair (not included here)

Previously compared `cmp-lumen-orin-nx-16gb-1235.tgz` (Yocto) with `cmp-nexus-1127_ubuntu.tgz` (Ubuntu). Both were taken without the Portus drive, and these earlier archives are **not included** in this commit. Do not generalize that comparison to the latest archived pair:

| Item | Result |
|---|---|
| Live DT | Identical, except `bootargs` and the Ubuntu initrd. `padctl@3520000` and `usb@3610000` are the same. |
| Kernel USB/XHCI/PHY/HUB config | Identical (only BT/CAN/audio extras differ; `PHY_TEGRA194_P2U` is `=y` vs `=m`, and it is PCIe-only). |
| UEFI (`bios_version`), L4T release | Same (36.5.0, GCID 43688277). |
| `usbcore` parameters, EMC/xusb clock rates | Same. |
| `nvpmodel` | Yocto 40W (mode 4), Ubuntu 15W (mode 2). Not USB-relevant. |
| `uas` | Loaded on Ubuntu only (`USB_UAS=m`, not installed in our image). Only matters after enumeration. |
| Filesystems | Both: ext4 and exFAT built in. Yocto: vfat and old NTFS as modules (the old NTFS driver is read-only); Ubuntu: built in. |

- Note: both captures were taken **without** the drive on Portus. `lsusb -t` shows nothing on `1-3.1` ports 1 and 2.
- **Retest:** on a local board with our image, hot-plugging a 2 GB drive into Portus USB **works**.

**Conclusion so far:** our image supports Portus storage in the simple local chain. The remote technician's failure (screenshots) has a **different USB chain**: two extra hubs `1-3.1.2` and `1-3.1.2.3`, plus a USB audio device. The `-71` errors precede filesystem detection, but whether the extra chain, device, board or image difference is responsible remains open.

## Update 2026-10-06: second unit (192.0.5.10, our Yocto image), hot-plug into Portus USB0: WORKS

```
usb 1-3.1.2: new high-speed USB device number 9 using tegra-xusb
usb-storage 1-3.1.2:1.0: USB Mass Storage device detected
scsi 1:0:0:0: Direct-Access Generic Flash Disk 8.07
sd 1:0:0:0: [sdb] 4014080 512-byte logical blocks: (2.06 GB/1.91 GiB)
 sdb: sdb1
```

- The drive is an Alcor `058f:6387` 2 GB flash drive with a vfat partition. It sits **directly on Portus hub port 2** (`1-3.1.2`), 3 hub tiers deep.
- No errors. A read-only mount of `sdb1` works (the `vfat`/`fat` modules load automatically).
- **Our image supports Portus USB storage.**
- The failing remote case has a different chain: two extra hubs plus a USB audio device, at the maximum hub depth. Its `-71` errors require testing that exact setup before attributing them to a particular component.
  - **Next step for the technician:** connect the drive with the simple adapter only (no hub/audio device).
  - If it must use that converter, try an externally powered hub.

## Update 2026-10-06: archived captures with the drive on Portus (different working units)

`cmp-lumen-orin-nx-16gb-1354.tgz` (Yocto) vs. `cmp-nexus-1124_ubuntu.tgz` (Ubuntu). Same Alcor `058f:6387` 2 GB drive, directly on Portus port 2 (`1-3.1.2`), no extra hub.

| | Yocto (40W) | Ubuntu (15W) |
|---|---|---|
| `lsusb -t` | Mass Storage at `1-3.1.2` | Mass Storage at `1-3.1.2` |
| dmesg | hot-plug at 55 s, `sdb` 2.06 GB, `sdb1` | cold plug at 3 s, `sdb` 2.06 GB, `sdb1` |
| Errors | none | none |

**Both images work with the simple chain, on different units** (different device-tree serial numbers). The USB controller and padctl DT nodes match, as do usbcore parameters and captured EMC/XUSB clock rates. The **full DT differs**: Yocto disables some PCIe, audio and SPI nodes, removes UART DMA, and has different boot arguments; regulator use counts and FTDI GPIO numbering also differ. The power-mode difference (40W vs. 15W) did not prevent either setup from working, but its role in the remote failure is unknown. Neither archive captures that failure.

**Remaining step:** on the problematic unit/setup, record both images with **the same hub chain**, or remove the hub there and retest.

## Update 2026-10-06: Ubuntu, with one external hub on Portus (192.0.5.10): WORKS

```
Portus port 2 (1-3.1.2) = Transcend 8564:4100 "USB2.1 Hub" (4 ports)
  └─ port 1 (1-3.1.2.1) = Alcor 058f:6387 2 GB flash → sdb 2.06 GB, sdb1 (vfat)
```

- Hot-plugged at about 518 s. No `-71` errors and no subtree disconnect. Power mode 15W.
- This is **one** hub tier (4 tiers in total). The remote failing setup has **two** hubs plus an audio device (5 tiers), so it is still not the same setup.
- **Next:** repeat the same Transcend hub plus drive with the **Yocto** SSD. If that also works, our image handles hubs on Portus fine, and the remote failure is specific to that dock or drive.

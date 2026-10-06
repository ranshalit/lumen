#!/bin/sh
# USB/Portus diagnostic capture. Run as root on the board WITH the flash drive plugged
# into Portus USB0:   sudo sh usb_diag.sh
# Produces /tmp/usb_diag-<hostname>-<time>.tar.gz
OUT=/tmp/usb_diag-$(hostname)-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
mount -t debugfs none /sys/kernel/debug 2>/dev/null

r() { f=$1; shift; { echo "### $*"; "$@"; } >"$OUT/$f" 2>&1; }

r uname.txt         uname -a
r cmdline.txt       cat /proc/cmdline
r os.txt            cat /etc/os-release
r model.txt         sh -c 'tr -d "\0" </proc/device-tree/model; echo; tr -d "\0" </proc/device-tree/nvidia,dtsfilename; echo'
r lsusb.txt         lsusb
r lsusb_t.txt       lsusb -t
r lsmod.txt         lsmod
r dmesg.txt         dmesg
r usb_role.txt      sh -c 'for f in /sys/class/usb_role/*/role; do echo "$f: $(cat $f)"; done'
r usbcore.txt       sh -c 'for f in /sys/module/usbcore/parameters/*; do echo "$f: $(cat $f)"; done'
r usb_sysfs.txt     sh -c 'for d in /sys/bus/usb/devices/*; do [ -f $d/idVendor ] || continue; echo "$(basename $d) $(cat $d/idVendor):$(cat $d/idProduct) speed=$(cat $d/speed) ctl=$(cat $d/power/control) st=$(cat $d/power/runtime_status) prod=$(cat $d/product 2>/dev/null)"; done'
r gpio.txt          cat /sys/kernel/debug/gpio
r pinmux.txt        sh -c 'cat /sys/kernel/debug/pinctrl/*/pinmux-pins'
r pinconf.txt       sh -c 'cat /sys/kernel/debug/pinctrl/*/pinconf-pins'
r regulators.txt    cat /sys/kernel/debug/regulator/regulator_summary
cp /sys/firmware/fdt "$OUT/live.dtb" 2>/dev/null

# Raw hub port status (GET_PORT_STATUS) for every USB hub, independent of drivers.
cat >"$OUT/hubstat.py" <<'EOF'
import fcntl, struct, ctypes, glob, os
USBDEVFS_CONTROL = 0xc0185500
names=[(0,'CONN'),(1,'EN'),(2,'SUSP'),(3,'OC'),(4,'RST'),(8,'POWER'),(9,'LS'),(10,'HS')]
for d in sorted(glob.glob('/sys/bus/usb/devices/*')):
    try:
        if open(d+'/bDeviceClass').read().strip()!='09' or os.path.basename(d).startswith('usb'): continue
        n=int(open(d+'/maxchild').read()); bus=int(open(d+'/busnum').read()); dev=int(open(d+'/devnum').read())
        fd=open('/dev/bus/usb/%03d/%03d'%(bus,dev),'rb+',buffering=0)
        print(os.path.basename(d), open(d+'/idVendor').read().strip()+':'+open(d+'/idProduct').read().strip())
        for p in range(1,n+1):
            buf=ctypes.create_string_buffer(4)
            fcntl.ioctl(fd,USBDEVFS_CONTROL,struct.pack('BBHHHIxxxxQ',0xA3,0,0,p,4,1000,ctypes.addressof(buf)))
            st,ch=struct.unpack('<HH',buf.raw)
            print('  port%d status=0x%04x change=0x%04x %s'%(p,st,ch,[x for b,x in names if st>>b&1]))
    except Exception as e: print(d, 'ERR', e)
EOF
r hubstat.txt python3 "$OUT/hubstat.py"

tar -czf "$OUT.tar.gz" -C /tmp "$(basename "$OUT")" && rm -rf "$OUT"
echo "Saved: $OUT.tar.gz"

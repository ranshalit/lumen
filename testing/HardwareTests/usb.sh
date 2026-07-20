echo "none" > /sys/class/usb_role/usb2-0-role-switch/role
sleep 1
echo "host" > /sys/class/usb_role/usb2-0-role-switch/role

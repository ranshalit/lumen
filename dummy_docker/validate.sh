#!/bin/sh
# Dummy container validation — checks network, GPU, and basic runtime

echo "=== Dummy Container Validation ==="
echo ""

echo "--- Network ---"
ip link show lo | grep -q UP && echo "✅ loopback up" || echo "❌ loopback down"
ip link show eth0 > /dev/null 2>&1 && echo "✅ eth0 visible" || echo "❌ eth0 not visible"
ip addr show eth0 | grep -q "inet " && echo "✅ eth0 has IP" || echo "❌ eth0 no IP"

echo ""
echo "--- GPU ---"
ls /dev/nvidia0 /dev/nvmap > /dev/null 2>&1 && echo "✅ NVIDIA devices present" || echo "❌ no NVIDIA devices"
nvidia-smi -L 2>&1 && echo "✅ nvidia-smi OK" || echo "❌ nvidia-smi failed"

echo ""
echo "--- Runtime ---"
echo "✅ container running"
echo "hostname: $(hostname), arch: $(uname -m)"

# Keep container alive (replace with real app entrypoint)
echo ""
echo "Validation complete — sleeping indefinitely (ctrl+c or docker stop to exit)"
sleep infinity

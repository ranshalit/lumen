#!/usr/bin/env bash
set -euo pipefail

# stream_cam_udp.sh
# Usage:
#   ./stream_cam_udp.sh <DEST_IP> [PORT] [BITRATE_KBPS]
#
# Examples:
#   ./stream_cam_udp.sh 192.168.1.50
#   ./stream_cam_udp.sh 192.168.1.50 5000 1500

DEST_IP="${1:-}"
PORT="${2:-5000}"
BITRATE_KBPS="${3:-2000}"

if [[ -z "$DEST_IP" || "$DEST_IP" == "-h" || "$DEST_IP" == "--help" ]]; then
  echo "Usage: $0 <DEST_IP> [PORT] [BITRATE_KBPS]"
  echo "Example: $0 192.168.1.50 5000 2000"
  exit 1
fi

# Basic validation (IPv4-ish). If you want hostnames, remove this check.
if ! [[ "$DEST_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Error: DEST_IP must look like an IPv4 address (e.g. 192.168.1.50)"
  exit 2
fi

echo "Streaming /dev/video0 -> udp://$DEST_IP:$PORT  (bitrate=${BITRATE_KBPS} kbps)"
exec gst-launch-1.0 -v \
  v4l2src device=/dev/video0 \
  ! video/x-raw,format=YUY2,width=640,height=512,framerate=50/1 \
  ! videoconvert \
  ! x264enc tune=zerolatency bitrate="$BITRATE_KBPS" speed-preset=ultrafast key-int-max=50 \
  ! rtph264pay pt=96 config-interval=1 \
  ! udpsink host="$DEST_IP" port="$PORT"

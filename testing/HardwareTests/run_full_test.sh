#!/bin/bash

# Function to print colorful headers for better readability
function header() {
    echo -e "\n\033[1;33m======================================================"
    echo -e "   $1"
    echo -e "======================================================\033[0m"
}

function pause() {
    echo -e "\033[1;32mPress [Enter] to start this step...\033[0m"
    read
}

# Ensure PATH includes local bin for mavproxy/pip installs immediately
export PATH=$PATH:$HOME/.local/bin

# ==========================================
#  TEST PHASE FUNCTIONS
# ==========================================

function run_setup() {
    header "PHASE 1: AUTOMATIC SETUP"
    echo "[1/3] Fixing file permissions..."
    chmod +x usb.sh
    chmod +x test_scripts/*.sh

    echo "[2/3] Setting USB Role (Device -> Host)..."
    # This might ask for a password, which is normal
    sudo ./usb.sh

    echo "[3/3] Ensuring Python Dependencies are installed (OFFLINE MODE)..."
    cd python_packages || { echo "❌ 'python_packages' directory not found!"; return; }

    # Loop through files to install them one by one
    for pkg in *.whl; do
        if [ -f "$pkg" ]; then
            if python3 pip.pyz install "$pkg" --no-index --no-deps --quiet; then
                echo -e "   ✅ Installed: $pkg"
            else
                echo -e "   ❌ FAILED:    $pkg"
            fi
        fi
    done

    cd ..
    echo "✅ Setup Complete."
}

function run_sensor() {
    header "PHASE 2: SENSOR TEST (HODAKEV)"
    echo "ℹ️  This test verifies the IMU sensor."
    echo "ℹ️  It runs for about 30 seconds and stops automatically."
    pause
    python3 test_scripts/hodakev_test.py
}

function run_matek() {
    header "PHASE 3: MATEK FLIGHT CONTROLLER"

    echo "🔍 Scanning for USB Serial devices..."
    DEVICES=$(ls /dev/ttyUSB* 2>/dev/null)

    if [ -z "$DEVICES" ]; then
        echo "❌ No USB devices found! (/dev/ttyUSB*)"
        echo "   Using default '/dev/ttyUSB0' (might fail if not connected)."
        MATEK_DEV="/dev/ttyUSB0"
    else
        echo "👉 Found the following devices:"
        echo "$DEVICES"
        echo ""
        read -p "Enter device path (Press [Enter] for /dev/ttyUSB0): " USER_DEV
        
        if [ -z "$USER_DEV" ]; then
            MATEK_DEV="/dev/ttyUSB0"
        else
            MATEK_DEV="$USER_DEV"
        fi
    fi

    echo "✅ Selected Device: $MATEK_DEV"
    echo "⚠️  VERIFY MATEK SETTINGS: Protocol=Mavlink2, Baud=921600"
    echo ""

    echo "❓ STARTUP COMMAND (Optional)"
    echo "   Leave empty to just open the console (read & write)."
    echo "   Or type a command to run immediately (e.g., 'mode loiter', 'status')."
    read -p "Command > " STARTUP_CMD

    echo ""
    echo "👉 Starting Mavproxy..."
    echo "ℹ️  Once running, you can TYPE commands directly into the console."
    echo "🛑 TO FINISH: Press 'Ctrl+C' to quit."
    pause

    if [ -z "$STARTUP_CMD" ]; then
        # Interactive mode (Read + Write manually)
        mavproxy.py --master="$MATEK_DEV" --baudrate 921600 --mav20
    else
        # Run specific command on startup
        mavproxy.py --master="$MATEK_DEV" --baudrate 921600 --mav20 --cmd="$STARTUP_CMD"
    fi
}

function run_camera() {
    header "PHASE 4: CAMERA STREAM"

    # AUTO-DETECT IP LOGIC
    # We grab the first part of the SSH_CLIENT variable (Client IP)
    DETECTED_IP=$(echo $SSH_CLIENT | awk '{print $1}')

    if [ -n "$DETECTED_IP" ]; then
        echo -e "ℹ️  Auto-detected your PC IP: \033[1;36m$DETECTED_IP\033[0m"
        read -p "Press [Enter] to use this IP, or type a new one: " USER_IP
        
        if [ -z "$USER_IP" ]; then
            PC_IP=$DETECTED_IP
        else
            PC_IP=$USER_IP
        fi
    else
        echo "ℹ️  Could not auto-detect IP (are you on a direct serial console?)."
        read -p "Enter your PC IP Address (e.g., 192.168.1.50): " PC_IP
    fi

    if [ -z "$PC_IP" ]; then
        echo "❌ No IP entered. Skipping camera test."
    else
        echo "🎥 Starting stream to $PC_IP..."
        echo "🛑 TO FINISH: Press 'Ctrl+C' to stop streaming."
        pause
        ./test_scripts/camera_test_jetson.sh $PC_IP
    fi
}

function run_teensy() {
    header "PHASE 5: GIMBAL TEST (TEENSY)"
    echo "ℹ️  Connecting to Gimbal..."
    echo "👉 Commands: 'm1' (pos), 'p30' (pitch), 'q' (quit)"
    pause
    python3 test_scripts/teensy_controller.py
}

# ==========================================
#  MAIN MENU
# ==========================================

while true; do
    clear
    header "MAIN MENU - HARDWARE DIAGNOSTICS"
    echo "1) Run FULL SEQUENCE (All Tests)"
    echo "2) Run Setup Only (Permissions, USB, Pip)"
    echo "3) Run Sensor Test (Hodakev)"
    echo "4) Run Matek Flight Controller Test"
    echo "5) Run Camera Stream Test"
    echo "6) Run Gimbal Test (Teensy)"
    echo "q) Quit"
    echo ""
    read -p "Select an option: " OPTION

    case $OPTION in
        1) 
            run_setup
            run_sensor
            run_matek
            run_camera
            run_teensy
            echo -e "\n✅ FULL SEQUENCE COMPLETE"
            read -p "Press Enter to return to menu..."
            ;;
        2) run_setup; read -p "Press Enter to return to menu..." ;;
        3) run_sensor; read -p "Press Enter to return to menu..." ;;
        4) run_matek; read -p "Press Enter to return to menu..." ;;
        5) run_camera; read -p "Press Enter to return to menu..." ;;
        6) run_teensy; read -p "Press Enter to return to menu..." ;;
        q|Q) 
            echo "Exiting."
            exit 0 
            ;;
        *) 
            echo "Invalid option."
            sleep 1 
            ;;
    esac
done

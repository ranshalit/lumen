# **🛠️ Hardware Testing User Manual**

This guide explains how to set up and run the hardware diagnostics for the **Jetson**, **Matek Flight Controller**, **Gimbal**, and **Camera**.

## **📦 Step 1: Transfer Files to Jetson**

You must copy the HardwareTests folder from your PC to the Jetson.

**1\. Open a terminal on your PC.**

**2\. Run the copy command:**

*(Replace 192.168.1.X with the real IP address of the Jetson)*

scp \-r HardwareTests user@192.168.1.X:\~/

## **📹 Step 2: Prepare Camera Test (PC Side)**

**⚠️ Important:** The camera test sends video *from* the Jetson *to* your PC. You must start the "Listener" on your PC **before** running the test on the Jetson.

**1\. Open a terminal on your PC inside HardwareTests/test\_scripts.**

**2\. Run the listener script:**

./camera\_test\_pc.sh

*You will see a waiting message. Keep this window open.*

## **🚀 Step 3: Run the Diagnostics (Jetson Side)**

Now you will control the Jetson to run the tests.

**1\. SSH into the Jetson:**

ssh user@192.168.1.X

**2\. Go to the folder:**

cd \~/HardwareTests

**3\. Make the script runnable (First time only):**

chmod \+x run\_full\_tests.sh

**4\. Run the Master Script:**

./run\_full\_tests.sh

## **📋 The Main Menu**

Once the script starts, you will see this menu. Here is what each option does:

### **1\) Run FULL SEQUENCE**

* Runs **everything** in order.  
* Great for a complete system checkup.

### **2\) Run Setup Only**

* **Use this first.**  
* Installs required Python libraries (Offline mode).  
* Sets permissions.  
* Fixes the USB port mode (Host vs Device).

### **3\) Run Sensor Test (Hodakev)**

* Checks the IMU sensor.  
* Runs for 30 seconds and checks for packet loss.

### **4\) Run Matek Flight Controller Test**

* Scans for USB devices.  
* Connects to the Flight Controller using **Mavlink 2**.  
* Allows you to send commands (like mode loiter) or just read status data.  
* **Exit:** Press Ctrl+C.

### **5\) Run Camera Stream Test**

* **Requires Step 2 to be running on your PC.**  
* Auto-detects your PC's IP address.  
* Starts streaming video to your screen.  
* **Exit:** Press Ctrl+C.

### **6\) Run Gimbal Test (Teensy)**

* Connects to the Gimbal.  
* Allows you to move it using keyboard commands:  
  * m1 \-\> Position Mode  
  * p30 \-\> Pitch 30 degrees  
  * y90 \-\> Yaw 90 degrees  
* **Exit:** Type q.

## **🆘 Troubleshooting**

* **Permission Denied?**  
  Run chmod \+x run\_full\_tests.sh again.  
* **"Mavproxy not found"?**  
  Select **Option 2 (Setup)** from the menu. It fixes the system path automatically.  
* **Camera video is not showing?**  
  * Check that firewall is disabled on your PC.  
  * Ensure camera\_test\_pc.sh is running **before** you start the Jetson test.  
  * Ensure you accepted the correct IP address in the menu.
import hodakev_driver
import time
from threading import Thread
import csv


def test_class():
    data = hodakev_driver.UartDriver("/dev/ttyS2",921600,10000, 20000, False, "", "")
    # data.set_device("/dev/ttyUSB2")
    log_location = "."
    data.init_driver(log_location)
    s = Thread(target=data.start,daemon=True)
    s.start()
    # print("test")
    l = Thread(target=data.driver_logic, daemon=True)
    l.start()
    print("logic")
    flag_calib = False
    calib_matrix = None
    start = 0
    while True:
        if time.monotonic() - start > 30 and flag_calib:
            break
        if not flag_calib:
            i_data = data.get_calibration_data()
            if i_data is not None and not flag_calib:
                versions = data.get_versions()
                print("Got:", len(i_data.data))
                print(f"Versions: Hardware= {versions['Hardware_version']},Software= {versions['Software_version']}, Driver= {versions['Driver_version']}")

                calib_vector_reorgenized = [bytes(i_data.data[i:i+900]) for i in range(0, len(i_data.data), 900)]
                print("got calib")
                flag_calib = True
                print("Starting packet loss testing...")
                start = time.monotonic()

        imu_data = data.get_imu_msg()
        if imu_data:
            # print(f"IMU data: {imu_data.ts}")
            pass
        # print(data.get_logic_status())
        time.sleep(0.003)
    print(f"Invalid checksums: {data.get_invalid_checksum()}")

test_class()
    

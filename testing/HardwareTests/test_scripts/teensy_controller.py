from threading import Thread
import threading
import gzip
import pickle
import socket
import numpy as np

import time
from enum import Enum, auto


class GimbalLogicState(Enum):
    WAIT_FOR_INIT_ACK = auto()
    SEND_INHIBIT = auto()
    WAIT_FOR_INHIBIT_ACK = auto()
    SEND_PBIT = auto()
    WAIT_FOR_PBIT_ACK = auto()
    SEND_OPERATIONAL = auto()
    FINISHED = auto()
    FAILED = auto()

class LosStateMachine:
    def __init__(self):
        self._lock = threading.Lock()
        self._los_logic_state = ELOS_LogicState.LOS_IDLE
        self._los_mode = ELOS_Mode.LOS_NOT_ACTIVE

    def set_los_logic_state(self, logic_state):
        with self._lock:
            self._los_logic_state = logic_state

    def set_los_mode(self, mode):
            self._los_mode = mode

    def get_los_logic_state(self):
        with self._lock:
            return self._los_logic_state

    def get_los_mode_state(self):
        with self._lock:
            return self._los_mode

class GimbalStateMachine:
    def __init__(self, configuration, log):
        self.state = GimbalLogicState.WAIT_FOR_INIT_ACK
        self._log = log
        self._configuration = configuration

        self.init_ack_received = False
        self._pbit_start_time = None
        self.last_gimbal_status = None

    def reset(self):
        self.state = GimbalLogicState.WAIT_FOR_INIT_ACK
        self.init_ack_received = False
        self._pbit_start_time = None
        self.last_gimbal_status = None

    def handle_init_ack(self):
        if self.init_ack_received:
            return
        self.init_ack_received = True
        self._log("StateMachine: InitAck received")

    def update_state(self, gimbal_status):
        self.last_gimbal_status = gimbal_status

        if self.state == GimbalLogicState.WAIT_FOR_INIT_ACK:
            if self.init_ack_received:
                self._log("StateMachine: transitioning to SEND_INHIBIT")
                self.state = GimbalLogicState.SEND_INHIBIT

        elif self.state == GimbalLogicState.SEND_INHIBIT:
            self._log("StateMachine: transitioning to WAIT_FOR_INHIBIT_ACK")
            self.state = GimbalLogicState.WAIT_FOR_INHIBIT_ACK

        elif self.state == GimbalLogicState.WAIT_FOR_INHIBIT_ACK:
            if gimbal_status and gimbal_status.SkrLogicState == LogicState.BAKRAB_INHIBIT.value:
                self._log("StateMachine: INHIBIT confirmed")
                self.state = GimbalLogicState.SEND_PBIT

        elif self.state == GimbalLogicState.SEND_PBIT:
            self._log("StateMachine: transitioning to WAIT_FOR_PBIT_ACK")
            self._pbit_start_time = time.monotonic()
            self.state = GimbalLogicState.WAIT_FOR_PBIT_ACK

        elif self.state == GimbalLogicState.WAIT_FOR_PBIT_ACK:
            if gimbal_status and hasattr(gimbal_status, 'PBITStatus') and gimbal_status.PBITStatus == PbitStatus.BAKRAB_PBIT_PASS.value:
                self._log("StateMachine: PBIT PASS received")
                self.state = GimbalLogicState.SEND_OPERATIONAL
            elif time.monotonic() - self._pbit_start_time > self._configuration.pbit_status_timeout:
                self._log("StateMachine: Timeout waiting for PBIT PASS")
                self.state = GimbalLogicState.FAILED

        elif self.state == GimbalLogicState.SEND_OPERATIONAL:
            self._log("StateMachine: transitioned to FINISHED")
            self.state = GimbalLogicState.FINISHED

        return self.state
from enum import Enum

class InitStatus(Enum):
    INIT_FAIL = 0x00
    INIT_PASS = 0x01

class LogicState(Enum):
    BAKRAB_INHIBIT = 0x00
    BAKRAB_OPERATIONAL = 0x01
    BAKRAB_PBIT = 0x02
    BAKRAB_CALIB = 0x03
    BAKRAB_IBIT = 0x04

class SubLogicState(Enum):
    BAKRAB_DEFAULT = 0x00
    BAKRAB_STBY = 0x01
    BAKRAB_IBIT_CHECK_INERTIA = 0x02
    BAKRAB_IBIT_RATE_CL_TEST = 0x03
    BAKRAB_IBIT_POS_CL_TEST = 0x04
    BAKRAB_IBIT_MOVE1 = 0x05
    BAKRAB_CALIB1 = 0x06
    BAKRAB_CALIB2 = 0x07

class PbitStatus(Enum):
    BAKRAB_PBIT_NOT_ACTIVE = 0x00
    BAKRAB_PBIT_IN_PROGRESS = 0x01
    BAKRAB_PBIT_PASS = 0x02
    BAKRAB_PBIT_FAIL = 0x03


class CalibStatus(Enum):
    BAKRAB_CALIB_NOT_ACTIVE = 0x00
    BAKRAB_CALIB_IN_PROGRESS = 0x01
    BAKRAB_CALIB_DONE = 0x02

class IBITStatus(Enum):
    BAKRAB_IBIT_NOT_ACTIVE = 0x00
    BAKRAB_IBIT_IN_PROGRESS = 0x01
    BAKRAB_IBIT_PASS = 0x02
    BAKRAB_IBIT_FAIL = 0x03


class GimbalMode(Enum):
    BAKRAB_RATEPOS = 0x00
    BAKRAB_POSITION = 0x01


class GCUState(Enum):
    INIT = 0  # startup procedures
    PBIT = 1  # Power-on BIT
    WAIT_FOR_MISSION = 2  # Vehicle is Ready, needs mission
    WAIT_FOR_LAUNCH = 3  # ready for mission, waiting for permission
    TAKE_OFF = 4  # launch process active, timed sequence of events
    MID_COURSE = 5  # Mid course guidance
    INERTIAL_HOMING = 6  # Rgo < Spike length
    HOMING = 7  # Target acquired
    STOP_MISSION = 8  # Mission Aborted
    FAIL = 9

import teensy_driver
import time

class ELOS_LogicState(Enum):
    LOS_IDLE = 0 # Default value
    LOS_OPERATIONAL = 1
    LOS_DEBUG = 2

class ELOS_Mode(Enum):
  LOS_NOT_ACTIVE = 0 # Default value
  LOS_EC = 1
  LOS_MIDCOURSE = 2
  LOS_POINT = 3
  LOS_TRACK = 4
  LOS_DEBUG_TRACK = 5

class ELOS_ControlType(Enum):
    LOS_P = 0 # Default value
    LOS_PI = 1

device = "/dev/ttyTHS1"
baud_rate = 921600
connector = teensy_driver.UartDriver(device, baud_rate, 10000, 100, 100000,
                                     ".", False, "10.0.0.21:7501", "10.0.0.44:7500")
last_gimbal_angle_message = None
los_logic_state_map = {
            LogicState.BAKRAB_INHIBIT.value: ELOS_LogicState.LOS_IDLE,
            LogicState.BAKRAB_PBIT.value: ELOS_LogicState.LOS_IDLE,
            LogicState.BAKRAB_IBIT.value: ELOS_LogicState.LOS_IDLE,
            LogicState.BAKRAB_CALIB.value: ELOS_LogicState.LOS_IDLE,
            LogicState.BAKRAB_OPERATIONAL.value: ELOS_LogicState.LOS_OPERATIONAL,
        }

gimbal_logic_state_map = {
            GimbalLogicState.SEND_INHIBIT: LogicState.BAKRAB_INHIBIT,
            GimbalLogicState.SEND_PBIT: LogicState.BAKRAB_PBIT,
            GimbalLogicState.WAIT_FOR_PBIT_ACK: LogicState.BAKRAB_PBIT,
            GimbalLogicState.SEND_OPERATIONAL: LogicState.BAKRAB_OPERATIONAL,
            GimbalLogicState.FINISHED: LogicState.BAKRAB_OPERATIONAL
        }

import math
yaw = 0 * math.pi / 180  
pitch = 0 * math.pi / 180
mode = 1

class Config:
    pbit_status_timeout = 10
_gimbal_state_machine = GimbalStateMachine(Config() ,print)
_los_state_machine = LosStateMachine()

def start_gimbal_command_loop():
    global last_gimbal_angle_message
    global pitch
    global yaw
    global mode
    while True:
        start_time = time.monotonic()
        gimbal_angle_message = connector.get_gimbal_angles()

        while gimbal_angle_message:
            if gimbal_angle_message is not None:
                last_gimbal_angle_message = gimbal_angle_message.GimbalAngleData_1

            gimbal_angle_message = connector.get_gimbal_angles()

        if not last_gimbal_angle_message:
            continue

        if connector.is_connected():
            _gimbal_state_machine.handle_init_ack()

        state = _gimbal_state_machine.update_state(last_gimbal_angle_message)

        if state in gimbal_logic_state_map:
            logic_state = gimbal_logic_state_map[state]

            if last_gimbal_angle_message is not None and last_gimbal_angle_message.SkrLogicState in los_logic_state_map:
                los_logic_state = los_logic_state_map[last_gimbal_angle_message.SkrLogicState]
                _los_state_machine.set_los_logic_state(los_logic_state)

                try:
                    gimbal_command_data = teensy_driver.GimbalCommandMessage(
                        systemTimeTag=time.time(),
                        LogicStateCmd=logic_state.value,
                        SubLogicStateCmd=SubLogicState.BAKRAB_IBIT_POS_CL_TEST.value if logic_state.value == LogicState.BAKRAB_IBIT else SubLogicState.BAKRAB_DEFAULT.value,
                        BitRequestCmd=0,
                        RollGyroBias=0,
                        PitchGyroBias=0,
                        YawGyroBias=0,
                        SkrCntYawModeCmd=mode,
                        # _skr_mode,
                        SkrCntPitchModeCmd=mode,
                        # _skr_mode,
                        GimbalYawCmd=yaw,
                        # np.deg2rad(command_data.get("A_yaw", 0)),
                        GimbalPitchCmd=pitch,
                        # np.deg2rad(command_data.get("A_pitch", 0)),
                        IMU_P_Raw=0,
                        IMU_Q_Raw=0,
                        IMU_R_Raw=0)

                    connector.write_gimbal_cmd(gimbal_command_data)
                except Exception as e:
                    print(f"Error in gimbal command loop: {e}")

        time.sleep(max(0.005 - (time.monotonic() - start_time) - 0.0002, 0))  # 200Hz

def attempt_connect():
    print(f"Trying to connect to teensy at ({baud_rate})")
    try:
        # connection to teensy via rust driver
        calib_data = teensy_driver.CalibData([-0.9999861121177673, -0.0029283915646374226, -0.000873639015480876, -0.0038624065928161144, 0.9999787211418152, -0.0025804273318499327, 0.002963247476145625, -0.0038681949954479933, -0.9999874234199524], [0.9931601881980896, 0.9938740134239197, 0.994066596031189])

        connector.init_driver(calib_data)
        Thread(target=connector.start, args=()).start()
        Thread(target=connector.driver_logic, args=()).start()

        Thread(target=start_gimbal_command_loop, args=()).start()
        print("Teensy connected and handshake successful")
        return True
    except Exception as e:
        print(f"Teensy connection or handshake failed: {e}")
        return False

def connect_to_teensy(retry_until_success=False):
    while True:
        try:
            if attempt_connect():
                return
        except Exception as e:
            print(f"Could not connect to teensy: {str(e)}")
            time.sleep(0.5)


import math

def print_help():
    """
    Show the command menu and usage examples.
    """
    print("\n=== Command Help ===")
    print("Enter commands in the following formats:")
    print("  p<deg>   : set pitch in degrees (converted to radians)")
    print("             e.g., 'p30' -> pitch = 30° = 0.5236 rad")
    print("  y<deg>   : set yaw in degrees (converted to radians)")
    print("             e.g., 'y-45' -> yaw = -45° = -0.7854 rad")
    print("  m0       : set mode to 'rate'")
    print("  m1       : set mode to 'pos'")
    print("  h        : show this help")
    print("  q        : quit the menu\n")
    print("Notes:")
    print(" - Degrees are parsed as integers or floats (e.g., 15, -90, 12.5).")
    print(" - Mode is a single digit after 'm' (0 or 1).")
    print("====================\n")

def deg_to_rad(value_str: str) -> float:
    """
    Convert a numeric string representing degrees to radians.
    Raises ValueError if parsing fails.
    """
    return float(value_str) * math.pi / 180.0

def rad_to_deg(value_str: float) -> float:
    return value_str * 180.0 / math.pi

def send_telemetry():
    while True:
        try:
            if last_gimbal_angle_message is None:
                time.sleep(1)
                continue
            if _los_state_machine is None:
                time.sleep(1)
                continue

            data = {
                "pitch_cmd": float(np.rad2deg(pitch)),
                "PitchMotorCmd": float(np.rad2deg(last_gimbal_angle_message.PitchMotorCmd)),
                "GimbalPitchAngleCor": float(np.rad2deg(last_gimbal_angle_message.GimbalPitchAngleCor)),

                "yaw_cmd": float(np.rad2deg(yaw)),
                "YawMotorCmd": float(np.rad2deg(last_gimbal_angle_message.YawMotorCmd)),
                "GimbalYawAngleCor": float(np.rad2deg(last_gimbal_angle_message.GimbalYawAngleCor)),

                "mode": mode,
                "gimbal_logic_state": _gimbal_state_machine.state.value,
                "los_logic_state": _los_state_machine.get_los_logic_state().value,
                "los_mode_state": _los_state_machine.get_los_mode_state().value,

                "YawRateCor": float(np.rad2deg(last_gimbal_angle_message.YawRateCor)),
                "PitchRateCor": float(np.rad2deg(last_gimbal_angle_message.PitchRateCor)),
                "RollRateCor": float(np.rad2deg(last_gimbal_angle_message.RollRateCor)),
                }
            telemetry_dict = {
                'data': {"teensy_controller": {2: data}},  # 2 -> HSet
                'platform_id': "drone1",
                'grafana_redis_db': 11,
                'time_tag': time.time()
            }
            compressed_data = gzip.compress(pickle.dumps(telemetry_dict))

            _udp_connection.sendto(compressed_data, ("172.30.251.8",6666))
        except Exception:
            pass
        time.sleep(0.25)  # Send telemetry in 4 HZ

def main_loop():
    global pitch, yaw, mode
    time.sleep(10)
    print_help()
    while True:
        print(f"Mode: {'pos' if mode == 1 else 'rate'}; Pitch: {rad_to_deg(pitch)} deg; Yaw: {rad_to_deg(yaw)} deg")
        cmd = input("Command: ").strip()
        if not cmd:
            continue

        # Quit
        if cmd.lower() == "q":
            print("Exiting menu.")
            break

        # Help
        if cmd.lower() == "h":
            print_help()
            continue

        # Pitch: p<deg>
        if cmd[0].lower() == "p":
            if len(cmd) == 1:
                print("Error: 'p' requires a degree value, e.g., 'p30'.")
                continue
            try:
                pitch = deg_to_rad(cmd[1:])
                print(f"Pitch set to {pitch:.6f} rad ({float(cmd[1:]):.3f}°)")
            except ValueError:
                print(f"Error: invalid pitch degrees '{cmd[1:]}'")
            continue

        # Yaw: y<deg>
        if cmd[0].lower() == "y":
            if len(cmd) == 1:
                print("Error: 'y' requires a degree value, e.g., 'y-45'.")
                continue
            try:
                yaw = deg_to_rad(cmd[1:])
                print(f"Yaw set to {yaw:.6f} rad ({float(cmd[1:]):.3f}°)")
            except ValueError:
                print(f"Error: invalid yaw degrees '{cmd[1:]}'")
            continue

        # Mode: m0 / m1
        if cmd[0].lower() == "m":
            if len(cmd) < 2:
                print("Error: 'm' requires a digit (0 or 1), e.g., 'm0'.")
                continue
            if cmd[1] not in ("0", "1"):
                print(f"Error: invalid mode '{cmd[1]}'. Use 'm0' for rate or 'm1' for pos.")
                continue
            mode = int(cmd[1])
            mode_name = "rate" if mode == 0 else "pos"
            print(f"Mode set to {mode} ({mode_name})")
            continue

        # Unknown command
        print(f"Unknown command '{cmd}'. Type 'h' for help.")

if __name__ == "__main__":
    _udp_connection = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    Thread(target=connect_to_teensy, args=()).start()
    Thread(target=send_telemetry, args=()).start()
    main_loop()


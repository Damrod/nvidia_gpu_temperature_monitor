#!/usr/bin/env python3

import subprocess
import time
import requests
from datetime import datetime
import os
import sys
import platform
import logging
import argparse
from abc import ABC, abstractmethod
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Global configuration
GOTIFY_URL = os.getenv("GOTIFY_SERVER_URL")
GOTIFY_TOKEN = os.getenv("GOTIFY_TOKEN")
HIGH_TEMPERATURE_THRESHOLD = 63  # °C - Will trigger notifications
CRITICAL_TEMPERATURE_THRESHOLD = 80  # °C - Will trigger emergency shutdown if sustained
CHECK_INTERVAL = 5  # seconds
EMERGENCY_SHUTDOWN_DURATION = 300  # 5 minutes in seconds

def parse_args():
    parser = argparse.ArgumentParser(description='Monitor GPU temperature and send notifications')
    parser.add_argument(
        '--emergency-shutdown-duration',
        type=int,
        default=EMERGENCY_SHUTDOWN_DURATION,
        help='Duration in seconds before emergency shutdown when temperature is high (default: 300)'
    )
    return parser.parse_args()

class SystemLogger(ABC):
    @classmethod
    def create(cls) -> 'SystemLogger':
        """Factory method to create the appropriate logger for the current platform"""
        system = platform.system()
        logger_map = {
            "Windows": WindowsSystemLogger,
            "Linux": LinuxSystemLogger
        }
        
        logger_class = logger_map.get(system)
        if logger_class is None:
            raise NotImplementedError(f"No logger implementation for platform: {system}")
        
        return logger_class()

    @abstractmethod
    def setup(self, logger: logging.Logger) -> None:
        """Setup the logger with platform-specific handlers"""
        pass

class WindowsSystemLogger(SystemLogger):
    def setup(self, logger: logging.Logger) -> None:
        import win32evtlog
        import win32evtlogutil
        import win32con
        
        class WindowsEventLogHandler(logging.Handler):
            def emit(self, record):
                try:
                    level_map = {
                        logging.DEBUG: win32con.EVENTLOG_INFORMATION_TYPE,
                        logging.INFO: win32con.EVENTLOG_INFORMATION_TYPE,
                        logging.WARNING: win32con.EVENTLOG_WARNING_TYPE,
                        logging.ERROR: win32con.EVENTLOG_ERROR_TYPE,
                        logging.CRITICAL: win32con.EVENTLOG_ERROR_TYPE
                    }
                    
                    msg = self.format(record)
                    win32evtlogutil.ReportEvent(
                        'GPU Monitor',
                        1,
                        eventType=level_map.get(record.levelno, win32con.EVENTLOG_INFORMATION_TYPE),
                        strings=[msg]
                    )
                except Exception:
                    self.handleError(record)
        
        event_handler = WindowsEventLogHandler()
        event_handler.setFormatter(logging.Formatter('%(message)s'))
        logger.addHandler(event_handler)
        
        # Also log to console for development
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
        logger.addHandler(console_handler)

class LinuxSystemLogger(SystemLogger):
    def setup(self, logger: logging.Logger) -> None:
        from systemd.journal import JournalHandler
        
        journal_handler = JournalHandler(SYSLOG_IDENTIFIER='gpu-monitor')
        journal_handler.setFormatter(logging.Formatter('%(message)s'))
        logger.addHandler(journal_handler)
        
        # Also log to stdout for development
        stdout_handler = logging.StreamHandler(sys.stdout)
        stdout_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
        logger.addHandler(stdout_handler)

class GPUTemperatureMonitor(ABC):
    @classmethod
    def create(cls) -> 'GPUTemperatureMonitor':
        """Factory method to create the appropriate temperature monitor for the current platform"""
        system = platform.system()
        monitor_map = {
            "Windows": WindowsGPUTemperatureMonitor,
            "Linux": LinuxGPUTemperatureMonitor
        }
        
        monitor_class = monitor_map.get(system)
        if monitor_class is None:
            raise NotImplementedError(f"No GPU temperature monitor implementation for platform: {system}")
        
        return monitor_class()

    @abstractmethod
    def get_nvidia_smi_path(self) -> str:
        """Return the path to nvidia-smi executable"""
        pass

    @abstractmethod
    def get_subprocess_kwargs(self) -> dict:
        """Return platform-specific subprocess.run kwargs"""
        pass

    def get_temperature(self) -> int | None:
        """Get the current GPU temperature in Celsius"""
        try:
            result = subprocess.run(
                [self.get_nvidia_smi_path(), "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
                capture_output=True,
                text=True,
                check=True,
                **self.get_subprocess_kwargs()
            )
            return int(result.stdout.strip())
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"nvidia-smi execution failed: {e}\nOutput: {e.stdout}\nError: {e.stderr}")
        except ValueError as e:
            raise RuntimeError(f"Failed to parse temperature output: {e}\nOutput: {result.stdout if 'result' in locals() else 'No output'}")

class WindowsGPUTemperatureMonitor(GPUTemperatureMonitor):
    def get_nvidia_smi_path(self) -> str:
        nvidia_smi_paths = [
            r"C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
            r"C:\Windows\System32\nvidia-smi.exe",
            "nvidia-smi"  # Try PATH as fallback
        ]
        
        for path in nvidia_smi_paths:
            try:
                # Just check if the file exists and is executable
                subprocess.run([path, "--version"], capture_output=True, check=True)
                return path
            except FileNotFoundError:
                continue
            except subprocess.SubprocessError:
                # If we get here, the file exists but failed to execute
                return path
        
        raise RuntimeError("Could not find nvidia-smi.exe in any of the common locations")

    def get_subprocess_kwargs(self) -> dict:
        return {"creationflags": subprocess.CREATE_NO_WINDOW}

class LinuxGPUTemperatureMonitor(GPUTemperatureMonitor):
    def get_nvidia_smi_path(self) -> str:
        return "nvidia-smi"

    def get_subprocess_kwargs(self) -> dict:
        return {}

class SystemShutdown(ABC):
    @classmethod
    def create(cls) -> 'SystemShutdown':
        """Factory method to create the appropriate shutdown handler for the current platform"""
        system = platform.system()
        shutdown_map = {
            "Windows": WindowsSystemShutdown,
            "Linux": LinuxSystemShutdown
        }
        
        shutdown_class = shutdown_map.get(system)
        if shutdown_class is None:
            raise NotImplementedError(f"No shutdown implementation for platform: {system}")
        
        return shutdown_class()

    @abstractmethod
    def shutdown(self) -> None:
        """Shutdown the system"""
        pass

class WindowsSystemShutdown(SystemShutdown):
    def shutdown(self) -> None:
        subprocess.run(["shutdown", "/s", "/t", "0"], check=True)

class LinuxSystemShutdown(SystemShutdown):
    def shutdown(self) -> None:
        subprocess.run(["shutdown", "-h", "now"], check=True)

class GPUMonitor:
    def __init__(self, logger: logging.Logger):
        self.logger = logger
        self.temperature_monitor = GPUTemperatureMonitor.create()
        self.shutdown_handler = SystemShutdown.create()
        self.critical_temp_start_time = None

    def send_gotify_notification(self, title: str, message: str, priority: int = 5) -> bool:
        try:
            response = requests.post(
                f"{GOTIFY_URL}/message",
                headers={"X-Gotify-Key": GOTIFY_TOKEN},
                json={
                    "title": title,
                    "message": message,
                    "priority": priority
                }
            )
            response.raise_for_status()
            return True
        except requests.exceptions.RequestException as e:
            self.logger.error(f"Failed to send notification: {e}")
            return False

    def get_gpu_temperature(self) -> int | None:
        try:
            return self.temperature_monitor.get_temperature()
        except (RuntimeError, ValueError) as e:
            self.logger.error(str(e))
            self.send_gotify_notification(
                "GPU Monitor Error",
                f"Failed to get GPU temperature. Please check system.\nDetails: {str(e)}",
                priority=8
            )
            return None

    def check_emergency_shutdown(self, temperature: int) -> None:
        current_time = time.time()
        
        if temperature >= CRITICAL_TEMPERATURE_THRESHOLD:
            if self.critical_temp_start_time is None:
                self.critical_temp_start_time = current_time
                self.logger.warning(
                    f"CRITICAL temperature detected ({temperature}°C). Emergency shutdown will trigger in {EMERGENCY_SHUTDOWN_DURATION} seconds "
                    f"if temperature remains critical."
                )
            elif current_time - self.critical_temp_start_time >= EMERGENCY_SHUTDOWN_DURATION:
                self.logger.critical("EMERGENCY: Temperature has been critical for too long. Initiating system shutdown!")
                self.send_gotify_notification(
                    "EMERGENCY SHUTDOWN",
                    f"GPU temperature has been critically high ({temperature}°C) for {EMERGENCY_SHUTDOWN_DURATION} seconds. System will shutdown NOW!",
                    priority=10
                )
                self.shutdown_handler.shutdown()
        else:
            self.critical_temp_start_time = None

    def monitor(self):
        self.logger.info(f"Starting GPU temperature monitor on {platform.system()}...")
        
        while True:
            temperature = self.get_gpu_temperature()
            if temperature is not None:
                self.logger.info(f"Current GPU temperature: {temperature}°C")
                
                if temperature >= HIGH_TEMPERATURE_THRESHOLD:
                    if temperature >= CRITICAL_TEMPERATURE_THRESHOLD:
                        self.logger.warning(f"CRITICAL temperature detected: {temperature}°C")
                        self.send_gotify_notification(
                            "CRITICAL GPU Temperature Alert",
                            f"GPU temperature is CRITICALLY high: {temperature}°C!",
                            priority=8
                        )
                    else:
                        self.logger.warning(f"High temperature detected: {temperature}°C")
                        self.send_gotify_notification(
                            "High GPU Temperature Alert",
                            f"GPU temperature is high: {temperature}°C",
                            priority=5
                        )
                
                self.check_emergency_shutdown(temperature)
            
            time.sleep(CHECK_INTERVAL)

def setup_logging() -> logging.Logger:
    """Setup and return a configured logger"""
    logger = logging.getLogger('gpu-monitor')
    logger.setLevel(logging.INFO)

    try:
        system_logger = SystemLogger.create()
        system_logger.setup(logger)
    except (ImportError, NotImplementedError) as e:
        logger.error(str(e))
        sys.exit(1)
    
    return logger

def main():
    logger = setup_logging()
    monitor = GPUMonitor(logger)
    monitor.monitor()

if __name__ == "__main__":
    main() 
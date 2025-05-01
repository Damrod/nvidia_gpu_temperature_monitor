#!/usr/bin/env python3

import subprocess
import time
import requests
from datetime import datetime
import os
import sys
import platform
import logging
import signal
from abc import ABC, abstractmethod
from dotenv import load_dotenv
from daemoniker import Daemonizer, SignalHandler1

# Global configuration variables
GOTIFY_SERVER_URL = None
GOTIFY_TOKEN = None
HIGH_TEMPERATURE_THRESHOLD = None
CRITICAL_TEMPERATURE_THRESHOLD = None
CHECK_INTERVAL_SECONDS = None
EMERGENCY_SHUTDOWN_DURATION_SECONDS = None
PID_FILE = None

def load_environment(logger: logging.Logger):
    """Load environment variables from .env file. The file must exist and contain all required variables."""
    global GOTIFY_SERVER_URL, GOTIFY_TOKEN, HIGH_TEMPERATURE_THRESHOLD, \
           CRITICAL_TEMPERATURE_THRESHOLD, CHECK_INTERVAL_SECONDS, \
           EMERGENCY_SHUTDOWN_DURATION_SECONDS, PID_FILE

    script_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(script_dir)
    
    # Look for exactly .env file in script directory or parent directory
    env_path = None
    for dir_path in [script_dir, parent_dir]:
        test_path = os.path.join(dir_path, '.env')
        if os.path.isfile(test_path) and os.path.basename(test_path) == '.env':
            env_path = test_path
            break

    if env_path is None:
        logger.error(f"Required .env file not found in {script_dir} or {parent_dir}")
        sys.exit(1)

    logger.info(f"Loading environment from {env_path}")
    load_dotenv(env_path, override=True)

    # Set PID file location based on platform
    if platform.system() == "Windows":
        PID_FILE = os.path.join("C:\\ProgramData", "GPUTempMonitor", "gpu_monitor.pid")
        # Create directory for PID file if it doesn't exist
        os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
    else:
        # On Linux, when running as a service, systemd will handle the PID file
        PID_FILE = "/run/gpu-monitor.pid"
        # Don't try to create the directory on Linux as it's managed by systemd

    # Load required configuration
    required_vars = {
        "GOTIFY_SERVER_URL": str,
        "GOTIFY_TOKEN": str,
        "HIGH_TEMPERATURE_THRESHOLD": int,
        "CRITICAL_TEMPERATURE_THRESHOLD": int,
        "CHECK_INTERVAL_SECONDS": int,
        "EMERGENCY_SHUTDOWN_DURATION_SECONDS": int
    }

    missing_vars = []
    for var_name, var_type in required_vars.items():
        value = os.getenv(var_name)
        if value is None:
            missing_vars.append(var_name)
            continue
        
        try:
            if var_type == int:
                value = int(value)
            globals()[var_name] = value
        except ValueError:
            logger.error(f"Invalid value for {var_name}: must be {var_type.__name__}")
            sys.exit(1)

    if missing_vars:
        logger.error(f"Missing required environment variables: {', '.join(missing_vars)}")
        sys.exit(1)

    logger.info("Loaded configuration:")
    logger.info(f"  High temperature threshold: {HIGH_TEMPERATURE_THRESHOLD}°C")
    logger.info(f"  Critical temperature threshold: {CRITICAL_TEMPERATURE_THRESHOLD}°C")
    logger.info(f"  Check interval: {CHECK_INTERVAL_SECONDS} seconds")
    logger.info(f"  Emergency shutdown duration: {EMERGENCY_SHUTDOWN_DURATION_SECONDS} seconds")
    logger.info("  Gotify notifications: Enabled")

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
        import win32api
        import win32security
        import pywintypes
        
        # Try to register the event source in the registry, but continue even if it fails
        try:
            # Get path to the current Python executable
            python_exe = sys.executable
            
            # Create registry key for event source
            key = win32api.RegCreateKey(
                win32con.HKEY_LOCAL_MACHINE,
                r"SYSTEM\CurrentControlSet\Services\EventLog\Application\GPU Monitor"
            )
            
            # Set required registry values
            win32api.RegSetValueEx(key, "EventMessageFile", 0, win32con.REG_EXPAND_SZ, python_exe)
            win32api.RegSetValueEx(key, "TypesSupported", 0, win32con.REG_DWORD, 7)
            win32api.RegCloseKey(key)
            logger.info("Successfully registered event source")
        except pywintypes.error as e:
            # Log the warning but continue - the event source might already exist
            logger.warning(f"Could not register event source (this is normal if not running as admin or if already registered): {e}")
        
        class WindowsEventLogHandler(logging.Handler):
            def __init__(self):
                super().__init__()
                self.source_name = "GPU Monitor"
                # Try to open the event log once to validate the source exists
                try:
                    handle = win32evtlog.RegisterEventSource(None, self.source_name)
                    win32evtlog.DeregisterEventSource(handle)
                except pywintypes.error as e:
                    logger.warning(f"Event source validation failed: {e}")

            def emit(self, record):
                try:
                    level_map = {
                        logging.DEBUG: win32evtlog.EVENTLOG_INFORMATION_TYPE,
                        logging.INFO: win32evtlog.EVENTLOG_INFORMATION_TYPE,
                        logging.WARNING: win32evtlog.EVENTLOG_WARNING_TYPE,
                        logging.ERROR: win32evtlog.EVENTLOG_ERROR_TYPE,
                        logging.CRITICAL: win32evtlog.EVENTLOG_ERROR_TYPE
                    }
                    
                    msg = self.format(record)
                    event_type = level_map.get(record.levelno, win32evtlog.EVENTLOG_INFORMATION_TYPE)
                    
                    try:
                        handle = win32evtlog.RegisterEventSource(None, self.source_name)
                        win32evtlog.ReportEvent(
                            handle,         # Event log handle
                            event_type,     # Event Type
                            0,             # Event Category
                            0,             # Event ID
                            None,          # SID
                            [msg],         # Strings
                            b""           # Raw data (empty bytes)
                        )
                        win32evtlog.DeregisterEventSource(handle)
                    except pywintypes.error as e:
                        # Since we can't log to event log, and we don't want console output,
                        # we'll have to silently fail here
                        pass
                except Exception:
                    self.handleError(record)
        
        # Add only event log handler, no console handler
        event_handler = WindowsEventLogHandler()
        event_handler.setFormatter(logging.Formatter('%(levelname)s - %(message)s'))
        logger.addHandler(event_handler)

class LinuxSystemLogger(SystemLogger):
    def setup(self, logger: logging.Logger) -> None:
        from systemd.journal import JournalHandler
        
        # Add only journal handler, no console handler
        journal_handler = JournalHandler(SYSLOG_IDENTIFIER='gpu-monitor')
        journal_handler.setFormatter(logging.Formatter('%(message)s'))
        logger.addHandler(journal_handler)

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
                subprocess.run([path, "--version"], capture_output=True, check=True, **self.get_subprocess_kwargs())
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
                f"{GOTIFY_SERVER_URL}/message",
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
        """Check if emergency shutdown is needed. Only called with valid temperature values."""
        current_time = time.time()
        
        if temperature >= CRITICAL_TEMPERATURE_THRESHOLD:
            if self.critical_temp_start_time is None:
                self.critical_temp_start_time = current_time
                self.logger.warning(
                    f"CRITICAL temperature detected ({temperature}°C). Emergency shutdown will trigger in {EMERGENCY_SHUTDOWN_DURATION_SECONDS} seconds "
                    f"if temperature remains critical."
                )
            elif current_time - self.critical_temp_start_time >= EMERGENCY_SHUTDOWN_DURATION_SECONDS:
                self.logger.critical("EMERGENCY: Temperature has been critical for too long. Initiating system shutdown!")
                self.send_gotify_notification(
                    "EMERGENCY SHUTDOWN",
                    f"GPU temperature has been critically high ({temperature}°C) for {EMERGENCY_SHUTDOWN_DURATION_SECONDS} seconds. System will shutdown NOW!",
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
            
            time.sleep(CHECK_INTERVAL_SECONDS)

class ProcessManager(ABC):
    """Base class for process management and daemonization."""
    
    @classmethod
    def create(cls, logger: logging.Logger) -> 'ProcessManager':
        """Factory method to create the appropriate process manager for the current platform and environment"""
        system = platform.system()
        
        # If we're running under systemd, use the systemd manager regardless of platform
        if os.getenv('INVOCATION_ID') is not None:  # systemd sets this
            return SystemdProcessManager(logger)
            
        # Otherwise use platform-specific manager
        manager_map = {
            "Windows": DaemonikerProcessManager,
            "Linux": DaemonikerProcessManager  # We can use Daemoniker on Linux when not under systemd
        }
        
        manager_class = manager_map.get(system)
        if manager_class is None:
            raise NotImplementedError(f"No process manager implementation for platform: {system}")
        
        return manager_class(logger)

    def __init__(self, logger: logging.Logger):
        self.logger = logger

    @abstractmethod
    def daemonize(self) -> None:
        """Handle process daemonization"""
        pass

class SystemdProcessManager(ProcessManager):
    """Process manager for systemd services - no daemonization needed"""
    
    def daemonize(self) -> None:
        """Under systemd, we don't need to daemonize"""
        self.logger.info("Starting under systemd control...")

class DaemonikerProcessManager(ProcessManager):
    """Process manager using Daemoniker for cross-platform daemonization"""
    
    def daemonize(self) -> None:
        with Daemonizer() as (is_setup, daemonizer):
            if is_setup:
                self.logger.info("Starting GPU temperature monitor...")
                
                if platform.system() == "Windows":
                    # On Windows, we need to set up a handler for Ctrl+C events
                    import win32api
                    def win32_handler(type):
                        return True
                    win32api.SetConsoleCtrlHandler(win32_handler, True)
            
            is_parent, new_logger = daemonizer(
                PID_FILE,
                self.logger
            )
            
            if is_parent:
                # Parent process exits here
                self.logger.info("GPU monitor daemon started successfully")
                exit(0)
            
            # Update logger with the new one from daemonizer
            self.logger = new_logger

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

def setup_signal_handlers(monitor: GPUMonitor, logger: logging.Logger):
    """Set up signal handlers for graceful shutdown"""
    def cleanup():
        logger.info("Cleaning up before exit...")
        try:
            os.remove(PID_FILE)
            logger.info("Removed PID file")
        except (OSError, IOError) as e:
            logger.warning(f"Failed to remove PID file: {e}")
        
        monitor.send_gotify_notification(
            "GPU Monitor Stopping",
            "The GPU temperature monitor service is shutting down.",
            priority=3
        )

    def handle_signal(signum):
        logger.info(f"Received signal {signum}, shutting down gracefully...")
        cleanup()
        sys.exit(0)

    if platform.system() == "Windows":
        import win32api
        import win32con
        
        def win32_handler(type):
            if type in (win32con.CTRL_C_EVENT, 
                       win32con.CTRL_BREAK_EVENT,
                       win32con.CTRL_CLOSE_EVENT,
                       win32con.CTRL_LOGOFF_EVENT,
                       win32con.CTRL_SHUTDOWN_EVENT):
                cleanup()
                return True
            return False

        win32api.SetConsoleCtrlHandler(win32_handler, True)
    
    # Register signal handlers directly
    SignalHandler1(signal.SIGTERM, lambda *args: handle_signal(signal.SIGTERM))
    SignalHandler1(signal.SIGINT, lambda *args: handle_signal(signal.SIGINT))
    if platform.system() == "Windows":
        SignalHandler1(signal.SIGBREAK, lambda *args: handle_signal(signal.SIGBREAK))

    # Register cleanup on normal exit
    import atexit
    atexit.register(cleanup)

def main():
    """Entry point for the GPU temperature monitor"""
    logger = setup_logging()
    load_environment(logger)
    try:
        # Create appropriate process manager
        process_manager = ProcessManager.create(logger)
        
        # Handle daemonization
        process_manager.daemonize()
        logger = process_manager.logger  # Get potentially updated logger
        
        # Load environment in the child process
        load_environment(logger)
        
        # Common code for all platforms after daemonization
        monitor = GPUMonitor(logger)
        setup_signal_handlers(monitor, logger)
        
        try:
            # Send startup notification
            monitor.send_gotify_notification(
                "GPU Monitor Started",
                "The GPU temperature monitor service has started and is now monitoring your GPU temperature.",
                priority=3
            )
            
            # Start monitoring loop
            monitor.monitor()
        except Exception as e:
            error_msg = f"GPU Monitor service terminated unexpectedly: {str(e)}"
            logger.error(error_msg)
            monitor.send_gotify_notification(
                "GPU Monitor Error",
                error_msg,
                priority=8
            )
            raise  # Re-raise to trigger the outer exception handler
        
    except Exception as e:
        logger.error(f"Fatal error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()

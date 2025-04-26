# NVIDIA GPU Temperature Monitor

A system service that monitors NVIDIA GPU temperature and can perform emergency shutdowns if temperatures reach critical levels. It also sends notifications via Gotify when temperatures are high.

## Features

- Monitors NVIDIA GPU temperature in real-time
- Sends notifications via Gotify when temperatures exceed thresholds
- Can perform emergency system shutdown if temperature remains critical
- Works on both Linux and Windows
- Systemd service integration on Linux
- Windows Event Log integration on Windows

## Prerequisites

### System Dependencies

#### Linux (Ubuntu/Debian)
```bash
sudo apt-get install libsystemd-dev pkg-config
```

#### Linux (Fedora/RHEL)
```bash
sudo dnf install systemd-devel
```

### Python Dependencies
All Python dependencies are handled automatically during installation. The main ones are:
- `requests` - For sending notifications
- `python-dotenv` - For configuration management
- `systemd-python` (Linux) - For systemd integration
- `pywin32` (Windows) - For Windows Event Log integration

## Installation

### Linux Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd nvidia_gpu_temperature_monitor
```

2. Create a `.env` file with your configuration:
```bash
cp .env.example .env
# Edit .env with your settings
```

3. Install the service:
```bash
make install
```

The installation will:
- Create a virtual environment
- Install all required dependencies
- Copy the necessary files to `/usr/local/lib/gpu-monitor`
- Set up the systemd service

> **Note**: The python script functionality has been tested, but the installation process has not been tested on Linux systems. Windows script, installation paths and service integration are currently untested.

### Windows Installation

#### Method 1: Using the Installer (Recommended)

1. Download and install WiX Toolset:
   - Go to https://github.com/wixtoolset/wix3/releases/latest
   - Download the latest WiX Toolset (e.g., `wix311.exe`)
   - Run the installer
   - Add WiX bin directory to your system PATH:
     1. Open System Properties (Win + R, type `sysdm.cpl`)
     2. Go to Advanced tab → Environment Variables
     3. Under System Variables, find and edit "Path"
     4. Add the WiX bin directory (typically `C:\Program Files (x86)\WiX Toolset v3.11\bin`)
     5. Click OK to save

2. Build the installer:
```powershell
# From the project root
cd scripts
.\build_installer.ps1
```

3. Run the generated installer (`gpu-temp-monitor-setup.msi`)

The installer will:
- Check for Python and prompt to install if missing
- Create a virtual environment
- Install all dependencies
- Install mock nvidia-smi if needed
- Set up and start the Windows service
- Create start menu shortcuts

The MSI installer provides several advantages:
- Standard Windows installation experience
- Proper upgrade/uninstall handling
- Group Policy deployment support
- Silent installation support (`msiexec /i gpu-temp-monitor-setup.msi /quiet`)

#### Method 2: Development Setup

For development or testing, you can use the PowerShell script:

```powershell
# From the project root
cd scripts
.\setup_windows.ps1
```

## Configuration

Create a `.env` file with the following variables:

```env
# Gotify server configuration
GOTIFY_SERVER_URL=https://your-gotify-server
GOTIFY_TOKEN=your-gotify-token

# Temperature thresholds (in Celsius)
HIGH_TEMPERATURE_THRESHOLD=80
CRITICAL_TEMPERATURE_THRESHOLD=90

# Monitoring settings
CHECK_INTERVAL_SECONDS=60
EMERGENCY_SHUTDOWN_DURATION_SECONDS=300
```

## Service Management

### Linux
```bash
# Start the service
sudo systemctl start gpu-monitor

# Stop the service
sudo systemctl stop gpu-monitor

# Check service status
sudo systemctl status gpu-monitor

# View logs
sudo journalctl -u gpu-monitor -f
```

### Windows
> **Note**: Windows service integration is currently untested. The following commands are provided as a reference based on standard Windows service management practices.

The service is managed through the Windows Services application or using PowerShell:
```powershell
# Start the service
Start-Service -Name "GPU Monitor"

# Stop the service
Stop-Service -Name "GPU Monitor"

# Check service status
Get-Service -Name "GPU Monitor"
```

## Development

### Linux Development
You can run the monitor directly from the source directory:
```bash
python srcs/gpu_monitor.py
```

### Windows Development
To develop and run the monitor on Windows:

1. Create a virtual environment:
```powershell
# Create a virtual environment named .venv
python -m venv .venv
```

2. Activate the virtual environment:
```powershell
# In PowerShell
.\.venv\Scripts\Activate.ps1

# Or in Command Prompt (cmd.exe)
.\.venv\Scripts\activate.bat
```

3. Install dependencies:
```powershell
# After activation, install requirements
pip install -r requirements.txt
```

4. Run the script:
```powershell
# The virtual environment's Python will be used
python srcs/gpu_monitor.py
```

### Cleaning Up
To clean the virtual environment:
```bash
make clean
```

## How It Works

1. The service runs as root to have necessary permissions for system shutdown
2. It checks GPU temperature at regular intervals (default: 60 seconds)
3. If temperature exceeds the high threshold:
   - Sends a notification via Gotify
   - Logs a warning
4. If temperature exceeds the critical threshold:
   - Starts a countdown (default: 300 seconds)
   - If temperature remains critical after the countdown:
     - Sends an emergency notification
     - Initiates system shutdown
5. The service automatically restarts if it crashes

## Troubleshooting

### Common Issues

1. **Service fails to start**
   - Check if NVIDIA drivers are properly installed
   - Verify that `nvidia-smi` works from the command line
   - Check system logs: `sudo journalctl -u gpu-monitor`

2. **Notifications not working**
   - Verify Gotify server URL and token in `.env`
   - Check network connectivity to Gotify server

3. **Permission issues**
   - Ensure the service is running as root
   - Check file permissions in `/usr/local/lib/gpu-monitor`

## License

MIT License

Copyright (c) 2024 NVIDIA GPU Temperature Monitor

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
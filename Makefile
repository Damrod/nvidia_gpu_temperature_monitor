.PHONY: install uninstall clean

# Configuration
PYTHON := python3
INSTALL_DIR := /usr/local/lib/gpu-monitor
VENV_DIR := $(INSTALL_DIR)/.venv
PIP := $(VENV_DIR)/bin/pip
SERVICE_NAME := gpu-monitor
SERVICE_FILE := $(SERVICE_NAME).service
SERVICE_SRC := srcs/$(SERVICE_FILE)
SYSTEMD_DIR := /etc/systemd/system

# Installation targets
install: create-venv install-files install-service

create-venv:
	@echo "Creating virtual environment..."
	sudo mkdir -p $(INSTALL_DIR)
	sudo chown root:root $(INSTALL_DIR)
	sudo $(PYTHON) -m venv $(VENV_DIR)
	. $(VENV_DIR)/bin/activate && \
		sudo $(PIP) install --upgrade pip && \
		sudo $(PIP) install -r requirements.txt

install-files:
	@echo "Installing files to $(INSTALL_DIR)..."
	sudo cp srcs/gpu_monitor.py $(INSTALL_DIR)/
	sudo cp requirements.txt $(INSTALL_DIR)/
	sudo cp .env $(INSTALL_DIR)/ 2>/dev/null || true
	# Create a new service file with correct paths
	sed 's|/usr/local/lib/gpu-monitor|$(INSTALL_DIR)|g' $(SERVICE_SRC) > $(INSTALL_DIR)/$(SERVICE_FILE)
	sudo chown -R root:root $(INSTALL_DIR)
	sudo chmod 755 $(INSTALL_DIR)
	sudo chmod 755 $(INSTALL_DIR)/gpu_monitor.py
	sudo chmod 644 $(INSTALL_DIR)/*.txt $(INSTALL_DIR)/*.env 2>/dev/null || true

install-service:
	@echo "Installing systemd service..."
	sudo ln -sf $(INSTALL_DIR)/$(SERVICE_FILE) $(SYSTEMD_DIR)/$(SERVICE_NAME)
	sudo systemctl daemon-reload
	sudo systemctl enable $(SERVICE_NAME)
	@echo "Service installed. You can start it with: sudo systemctl start $(SERVICE_NAME)"

# Uninstallation targets
uninstall:
	@echo "Uninstalling $(SERVICE_NAME)..."
	sudo systemctl stop $(SERVICE_NAME) 2>/dev/null || true
	sudo systemctl disable $(SERVICE_NAME) 2>/dev/null || true
	sudo rm -f $(SYSTEMD_DIR)/$(SERVICE_NAME)
	sudo systemctl daemon-reload
	sudo rm -rf $(INSTALL_DIR)
	@echo "Uninstallation complete"

clean:
	sudo rm -rf $(VENV_DIR)
	@echo "Cleaned virtual environment" 
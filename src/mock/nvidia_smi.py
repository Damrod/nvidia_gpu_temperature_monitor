#!/usr/bin/env python3
import sys
import random
import time

def mock_temperature():
    # Simulate a somewhat realistic GPU temperature between 30°C and 90°C
    return random.randint(30, 90)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--version":
        print("NVIDIA-SMI 535.129.03   Driver Version: 535.129.03   CUDA Version: 12.2")
        sys.exit(0)
    
    if len(sys.argv) > 1 and sys.argv[1] == "--query-gpu=temperature.gpu" and sys.argv[2] == "--format=csv,noheader,nounits":
        print(mock_temperature())
        sys.exit(0)
    
    print("Invalid arguments. This is a mock nvidia-smi that only supports temperature queries.")
    sys.exit(1) 
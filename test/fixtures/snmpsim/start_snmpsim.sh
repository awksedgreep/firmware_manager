#!/bin/bash

# Stop and remove any existing container
podman stop snmpsim 2>/dev/null
podman rm snmpsim 2>/dev/null

# Get the absolute path to the data directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

# Make sure the data directory exists
mkdir -p "$DATA_DIR"

# Create a volume for persistent storage
if ! podman volume exists snmpsim-data 2>/dev/null; then
    echo "Creating podman volume: snmpsim-data"
    podman volume create snmpsim-data
fi

# Run the SNMPSIM container with Podman
echo "Starting SNMPSIM container..."
podman run -d \
    --name snmpsim \
    -p 161:161/udp \
    -v "$DATA_DIR":/data:Z \
    -v snmpsim-data:/var/lib/snmpsim:Z \
    --restart unless-stopped \
    docktermj/snmpsimd \
    --data-dir=/data \
    --agent-udpv4-endpoint=0.0.0.0:161 \
    --v2c-arch \
    --v3-arch \
    --v3-user=testuser \
    --v3-auth-key=testauth123 \
    --v3-priv-key=testpriv123

# Show container status
echo -e "\nContainer status:"
podman ps -f name=snmpsim

# Show how to test
echo -e "\nTo test SNMP GET:"
echo "snmpget -v2c -c public 127.0.0.1 1.3.6.1.2.1.1.1.0"
echo -e "\nTo test SNMP SET:"
echo "snmpset -v2c -c private 127.0.0.1 1.3.6.1.2.1.69.1.3.3.0 s \"192.168.1.100\""
echo -e "\nView logs: podman logs -f snmpsim"

#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGES_DIR="/var/lib/libvirt/images/ansible-lab"
NETWORK_NAME="ansible-lab"

# VM names
VMS=("control" "node1" "node2" "node3" "node4")

echo -e "${YELLOW}=== Ansible Lab Cleanup Script ===${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Destroy and undefine VMs
echo -e "${YELLOW}Destroying VMs...${NC}"
for vm_name in "${VMS[@]}"; do
    if virsh dominfo "$vm_name" &> /dev/null; then
        echo -e "${YELLOW}Destroying $vm_name...${NC}"
        virsh destroy "$vm_name" 2>/dev/null || true
        virsh undefine "$vm_name" --remove-all-storage 2>/dev/null || true
        echo -e "${GREEN}$vm_name destroyed${NC}"
    else
        echo -e "${YELLOW}$vm_name doesn't exist, skipping${NC}"
    fi
done

# Destroy network
echo -e "\n${YELLOW}Destroying network...${NC}"
if virsh net-info "$NETWORK_NAME" &> /dev/null; then
    virsh net-destroy "$NETWORK_NAME" 2>/dev/null || true
    virsh net-undefine "$NETWORK_NAME" 2>/dev/null || true
    echo -e "${GREEN}Network destroyed${NC}"
else
    echo -e "${YELLOW}Network doesn't exist, skipping${NC}"
fi

# Clean up images directory
echo -e "\n${YELLOW}Cleaning up images directory...${NC}"
if [ -d "$IMAGES_DIR" ]; then
    rm -rf "$IMAGES_DIR"
    echo -e "${GREEN}Images directory cleaned${NC}"
else
    echo -e "${YELLOW}Images directory doesn't exist, skipping${NC}"
fi

echo -e "\n${GREEN}=== Lab Cleanup Complete ===${NC}"
echo -e "${YELLOW}Note: SSH keys in ~/.ssh/ansible-lab* are preserved${NC}"
echo -e "${YELLOW}Remove them manually if needed${NC}"

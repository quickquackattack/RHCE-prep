#!/bin/bash

# Quick fix script for common SSH access issues

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Quick SSH Access Fix ===${NC}\n"

# Get VM name
if [ -z "$1" ]; then
    sudo virsh list --all
    echo ""
    read -p "Enter VM name: " VM_NAME
else
    VM_NAME="$1"
fi

echo -e "\n${YELLOW}Fixing SSH access for: $VM_NAME${NC}\n"

# Fix 1: Fix SSH key permissions
echo -e "${YELLOW}1. Fixing SSH key permissions...${NC}"

for keydir in "$HOME/.ssh" "/var/lib/jira-provisioner/ssh-keys" "/var/lib/libvirt/images/ansible-lab"; do
    if [ -d "$keydir" ]; then
        find "$keydir" -type f -name "*${VM_NAME}*" -exec chmod 600 {} \; 2>/dev/null || true
        find "$keydir" -type f -name "ansible-lab" -exec chmod 600 {} \; 2>/dev/null || true
    fi
done

echo -e "${GREEN}✓ Fixed key permissions${NC}"

# Fix 2: Wait for cloud-init
echo -e "\n${YELLOW}2. Checking cloud-init status...${NC}"

if sudo virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
    echo -e "VM is running. Cloud-init may still be initializing..."
    echo -e "Waiting 30 seconds for cloud-init to complete..."

    for i in {30..1}; do
        echo -ne "\rWaiting: $i seconds...  "
        sleep 1
    done
    echo -e "\n${GREEN}✓ Wait complete${NC}"
else
    echo -e "${YELLOW}VM is not running. Starting...${NC}"
    sudo virsh start "$VM_NAME"
    sleep 30
fi

# Fix 3: Check and fix network
echo -e "\n${YELLOW}3. Checking network...${NC}"

# Ensure default network is active
if sudo virsh net-info default &>/dev/null; then
    if ! sudo virsh net-info default | grep -q "Active.*yes"; then
        sudo virsh net-start default
    fi
    echo -e "${GREEN}✓ Network is active${NC}"
fi

# Fix 4: Restart VM if needed
echo -e "\n${YELLOW}4. Do you want to restart the VM? (may help) [y/N]${NC}"
read -p "> " RESTART

if [[ "$RESTART" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Restarting VM...${NC}"
    sudo virsh reboot "$VM_NAME"
    echo -e "Waiting 60 seconds for VM to boot..."
    sleep 60
    echo -e "${GREEN}✓ VM restarted${NC}"
fi

echo -e "\n${GREEN}=== Fixes Applied ===${NC}"
echo -e "\nNow run the troubleshooting script:"
echo -e "${YELLOW}sudo bash scripts/troubleshoot-ssh.sh $VM_NAME${NC}"

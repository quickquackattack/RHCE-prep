#!/bin/bash

# Manual VM Installation Helper Script
# Uses static kickstart files (not auto-generated)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Manual VM Installation Helper ===${NC}\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Configuration
KICKSTART_DIR="/home/user/RHCE-prep/kickstart"
ISO_FILE="/var/lib/libvirt/images/ansible-lab/rocky-9-minimal.iso"
IMAGES_DIR="/var/lib/libvirt/images/ansible-lab"
SSH_KEY="/root/.ssh/ansible-lab.pub"

# VM to install
VM_NAME="${1}"

if [ -z "$VM_NAME" ]; then
    echo -e "${YELLOW}Available VMs to install:${NC}"
    echo "  - control (192.168.100.10, 2GB RAM, 2 vCPU)"
    echo "  - node1 (192.168.100.11, 1GB RAM, 1 vCPU)"
    echo "  - node2 (192.168.100.12, 1GB RAM, 1 vCPU)"
    echo "  - node3 (192.168.100.13, 1GB RAM, 1 vCPU)"
    echo "  - node4 (192.168.100.14, 1GB RAM, 1 vCPU)"
    echo ""
    read -p "Enter VM name to install: " VM_NAME
fi

# VM configurations
case "$VM_NAME" in
    control)
        MEMORY=2048
        VCPUS=2
        MAC="52:54:00:00:01:01"
        ;;
    node1)
        MEMORY=1024
        VCPUS=1
        MAC="52:54:00:00:01:02"
        ;;
    node2)
        MEMORY=1024
        VCPUS=1
        MAC="52:54:00:00:01:03"
        ;;
    node3)
        MEMORY=1024
        VCPUS=1
        MAC="52:54:00:00:01:04"
        ;;
    node4)
        MEMORY=1024
        VCPUS=1
        MAC="52:54:00:00:01:05"
        ;;
    *)
        echo -e "${RED}Invalid VM name. Use: control, node1, node2, node3, or node4${NC}"
        exit 1
        ;;
esac

# Check files exist
if [ ! -f "$ISO_FILE" ]; then
    echo -e "${RED}ISO file not found: $ISO_FILE${NC}"
    echo -e "${YELLOW}Download with:${NC}"
    echo "  mkdir -p $IMAGES_DIR"
    echo "  wget -O $ISO_FILE https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-minimal.iso"
    exit 1
fi

KS_FILE="$KICKSTART_DIR/${VM_NAME}.ks.cfg"
if [ ! -f "$KS_FILE" ]; then
    echo -e "${RED}Kickstart file not found: $KS_FILE${NC}"
    exit 1
fi

# Check SSH key
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${YELLOW}SSH key not found. Generating...${NC}"
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY%.pub}" -N "" -C "ansible-lab-key"
fi

# Show SSH key
echo -e "\n${YELLOW}Your SSH public key:${NC}"
cat "$SSH_KEY"
echo ""

echo -e "${YELLOW}IMPORTANT: Edit the kickstart file and add your SSH key!${NC}"
echo -e "Edit: ${BLUE}$KS_FILE${NC}"
echo -e "Look for: ${BLUE}ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-ssh-public-key-here${NC}"
echo -e "Replace with the key shown above"
echo ""
read -p "Press Enter when you've updated the kickstart file, or Ctrl+C to cancel..."

# Create VM disk
VM_DISK="$IMAGES_DIR/${VM_NAME}.qcow2"

if [ -f "$VM_DISK" ]; then
    echo -e "${YELLOW}Disk already exists. Removing...${NC}"
    rm -f "$VM_DISK"
fi

echo -e "\n${YELLOW}Creating VM disk...${NC}"
mkdir -p "$IMAGES_DIR"
qemu-img create -f qcow2 "$VM_DISK" 20G

# Destroy existing VM if present
if virsh dominfo "$VM_NAME" &> /dev/null; then
    echo -e "${YELLOW}VM already exists. Destroying...${NC}"
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
fi

# Ensure network exists
if ! virsh net-info ansible-lab &> /dev/null; then
    echo -e "${YELLOW}Creating ansible-lab network...${NC}"
    virsh net-define /home/user/RHCE-prep/libvirt/network.xml
    virsh net-start ansible-lab
    virsh net-autostart ansible-lab
fi

echo -e "\n${GREEN}Starting VM installation for: $VM_NAME${NC}"
echo -e "${YELLOW}This will take 10-15 minutes...${NC}\n"

# Start installation
virt-install \
    --name "$VM_NAME" \
    --memory "$MEMORY" \
    --vcpus "$VCPUS" \
    --disk path="$VM_DISK",format=qcow2,bus=virtio \
    --network network=ansible-lab,mac="$MAC",model=virtio \
    --os-variant rhel9.0 \
    --location "$ISO_FILE" \
    --initrd-inject="$KS_FILE" \
    --extra-args "inst.ks=file:/${VM_NAME}.ks.cfg console=ttyS0,115200" \
    --graphics none \
    --console pty,target_type=serial

# Installation complete (VM will be shut off due to poweroff in kickstart)
echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "${YELLOW}Starting VM...${NC}"

sleep 5
virsh start "$VM_NAME"

echo -e "\n${YELLOW}Waiting for VM to boot (30 seconds)...${NC}"
sleep 30

# Get IP from kickstart
case "$VM_NAME" in
    control) IP="192.168.100.10" ;;
    node1) IP="192.168.100.11" ;;
    node2) IP="192.168.100.12" ;;
    node3) IP="192.168.100.13" ;;
    node4) IP="192.168.100.14" ;;
esac

echo -e "\n${YELLOW}Testing SSH access...${NC}"

if timeout 10 ssh -i "${SSH_KEY%.pub}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    ansible@"$IP" "echo 'SSH Success!'" &> /dev/null; then

    echo -e "${GREEN}✓ SSH access confirmed!${NC}\n"
    echo -e "${GREEN}Connect with:${NC}"
    echo -e "${BLUE}ssh -i ${SSH_KEY%.pub} ansible@$IP${NC}"
else
    echo -e "${YELLOW}⚠ SSH not ready yet. Wait a minute and try:${NC}"
    echo -e "${BLUE}ssh -i ${SSH_KEY%.pub} ansible@$IP${NC}"
fi

echo -e "\n${GREEN}Installation complete for $VM_NAME!${NC}"

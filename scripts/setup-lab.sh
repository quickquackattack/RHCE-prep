#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGES_DIR="/var/lib/libvirt/images/ansible-lab"
BASE_IMAGE_URL="https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
BASE_IMAGE_NAME="centos-stream-9-base.qcow2"
NETWORK_NAME="ansible-lab"
SSH_KEY_PATH="$HOME/.ssh/ansible-lab"

# VM Configuration
declare -A VMS=(
    ["control"]="192.168.100.10|52:54:00:00:01:01|2048|2"
    ["node1"]="192.168.100.11|52:54:00:00:01:02|1024|1"
    ["node2"]="192.168.100.12|52:54:00:00:01:03|1024|1"
    ["node3"]="192.168.100.13|52:54:00:00:01:04|1024|1"
    ["node4"]="192.168.100.14|52:54:00:00:01:05|1024|1"
)

echo -e "${GREEN}=== Ansible Lab Setup Script ===${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
DEPS=(virsh virt-install qemu-img wget)
for dep in "${DEPS[@]}"; do
    if ! command -v $dep &> /dev/null; then
        echo -e "${RED}$dep is not installed. Please install libvirt and related tools.${NC}"
        exit 1
    fi
done
echo -e "${GREEN}All dependencies found${NC}\n"

# Create images directory
echo -e "${YELLOW}Creating images directory...${NC}"
mkdir -p "$IMAGES_DIR"

# Generate SSH key if it doesn't exist
echo -e "${YELLOW}Setting up SSH keys...${NC}"
if [ ! -f "$SSH_KEY_PATH" ]; then
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "ansible-lab-key"
    echo -e "${GREEN}SSH key generated at $SSH_KEY_PATH${NC}"
else
    echo -e "${GREEN}SSH key already exists${NC}"
fi

# Download base image if not exists
echo -e "\n${YELLOW}Downloading base image...${NC}"
if [ ! -f "$IMAGES_DIR/$BASE_IMAGE_NAME" ]; then
    wget -O "$IMAGES_DIR/$BASE_IMAGE_NAME" "$BASE_IMAGE_URL"
    echo -e "${GREEN}Base image downloaded${NC}"
else
    echo -e "${GREEN}Base image already exists${NC}"
fi

# Create and start network
echo -e "\n${YELLOW}Setting up libvirt network...${NC}"
if virsh net-info "$NETWORK_NAME" &> /dev/null; then
    echo -e "${YELLOW}Network exists, destroying and recreating...${NC}"
    virsh net-destroy "$NETWORK_NAME" 2>/dev/null || true
    virsh net-undefine "$NETWORK_NAME" 2>/dev/null || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
virsh net-define "$SCRIPT_DIR/../libvirt/network.xml"
virsh net-start "$NETWORK_NAME"
virsh net-autostart "$NETWORK_NAME"
echo -e "${GREEN}Network created and started${NC}"

# Create VMs
echo -e "\n${YELLOW}Creating VMs...${NC}"
for vm_name in "${!VMS[@]}"; do
    IFS='|' read -r ip mac memory vcpus <<< "${VMS[$vm_name]}"

    echo -e "\n${YELLOW}Creating VM: $vm_name${NC}"

    # Create VM disk from base image
    VM_DISK="$IMAGES_DIR/${vm_name}.qcow2"
    if [ -f "$VM_DISK" ]; then
        echo -e "${YELLOW}Disk exists, removing...${NC}"
        rm -f "$VM_DISK"
    fi

    qemu-img create -f qcow2 -F qcow2 -b "$IMAGES_DIR/$BASE_IMAGE_NAME" "$VM_DISK" 20G

    # Create cloud-init user-data
    USER_DATA_FILE="$IMAGES_DIR/${vm_name}-user-data.yaml"
    cat > "$USER_DATA_FILE" << EOF
#cloud-config
hostname: ${vm_name}
fqdn: ${vm_name}.ansible.lab
manage_etc_hosts: true

users:
  - name: ansible
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat ${SSH_KEY_PATH}.pub)

ssh_pwauth: false
disable_root: false

package_update: true
package_upgrade: false

packages:
  - vim
  - wget
  - curl
  - git

runcmd:
  - systemctl enable sshd
  - systemctl start sshd
  - echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
  - chmod 0440 /etc/sudoers.d/ansible

final_message: "The system is finally up, after \$UPTIME seconds"
EOF

    # Create cloud-init meta-data
    META_DATA_FILE="$IMAGES_DIR/${vm_name}-meta-data.yaml"
    cat > "$META_DATA_FILE" << EOF
instance-id: ${vm_name}
local-hostname: ${vm_name}
EOF

    # Create cloud-init ISO
    CLOUD_INIT_ISO="$IMAGES_DIR/${vm_name}-cloud-init.iso"
    if command -v genisoimage &> /dev/null; then
        genisoimage -output "$CLOUD_INIT_ISO" \
            -volid cidata -joliet -rock \
            "$USER_DATA_FILE" "$META_DATA_FILE" &> /dev/null
    elif command -v mkisofs &> /dev/null; then
        mkisofs -o "$CLOUD_INIT_ISO" \
            -V cidata -J -r \
            "$USER_DATA_FILE" "$META_DATA_FILE" &> /dev/null
    else
        echo -e "${RED}Neither genisoimage nor mkisofs found. Please install genisoimage.${NC}"
        exit 1
    fi

    # Destroy existing VM if present
    if virsh dominfo "$vm_name" &> /dev/null; then
        virsh destroy "$vm_name" 2>/dev/null || true
        virsh undefine "$vm_name" --remove-all-storage 2>/dev/null || true
    fi

    # Create VM
    virt-install \
        --name "$vm_name" \
        --memory "$memory" \
        --vcpus "$vcpus" \
        --disk path="$VM_DISK",format=qcow2,bus=virtio \
        --disk path="$CLOUD_INIT_ISO",device=cdrom \
        --network network="$NETWORK_NAME",mac="$mac",model=virtio \
        --os-variant centos-stream9 \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole \
        --import \
        --boot hd

    echo -e "${GREEN}VM $vm_name created successfully${NC}"
done

echo -e "\n${GREEN}=== Lab Setup Complete ===${NC}"
echo -e "\n${YELLOW}Waiting 60 seconds for VMs to boot and cloud-init to complete...${NC}"
sleep 60

echo -e "\n${GREEN}VM Status:${NC}"
virsh list --all | grep -E "control|node"

echo -e "\n${GREEN}Network Configuration:${NC}"
echo -e "Network: ansible-lab (192.168.100.0/24)"
echo -e "Control Node: 192.168.100.10"
echo -e "Node 1: 192.168.100.11"
echo -e "Node 2: 192.168.100.12"
echo -e "Node 3: 192.168.100.13"
echo -e "Node 4: 192.168.100.14"

echo -e "\n${GREEN}SSH Access:${NC}"
echo -e "ssh -i $SSH_KEY_PATH ansible@192.168.100.10"

echo -e "\n${YELLOW}Note: It may take a few more minutes for cloud-init to complete.${NC}"
echo -e "${YELLOW}Try the SSH command above. If it fails, wait a minute and try again.${NC}"

echo -e "\n${GREEN}To use with Ansible:${NC}"
echo -e "1. Add this to your ~/.ssh/config:"
echo -e "   Host ansible-lab-*"
echo -e "     User ansible"
echo -e "     IdentityFile $SSH_KEY_PATH"
echo -e "     StrictHostKeyChecking no"
echo -e "     UserKnownHostsFile=/dev/null"
echo -e "\n2. Use the inventory file in ansible/inventory.ini"
echo -e "\n3. Test with: ansible all -m ping -i ansible/inventory.ini"

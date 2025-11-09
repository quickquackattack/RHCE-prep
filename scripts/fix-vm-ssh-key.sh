#!/bin/bash

# Fix SSH key mismatch in VMs

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Fixing SSH Key Mismatch ===${NC}\n"

VM_NAME="${1:-control}"

echo -e "${YELLOW}VM: $VM_NAME${NC}\n"

# Get public key
PUB_KEY_PATH="/root/.ssh/ansible-lab.pub"

if [ ! -f "$PUB_KEY_PATH" ]; then
    echo -e "${RED}Public key not found: $PUB_KEY_PATH${NC}"
    echo -e "${YELLOW}Regenerating SSH key pair...${NC}"

    ssh-keygen -t rsa -b 4096 -f /root/.ssh/ansible-lab -N "" -C "ansible-lab-key"
    echo -e "${GREEN}✓ SSH key regenerated${NC}"
fi

PUB_KEY=$(cat "$PUB_KEY_PATH")

echo -e "${GREEN}Public key to inject:${NC}"
echo "$PUB_KEY" | head -c 80
echo "..."
echo ""

# Get VM IP
echo -e "\n${YELLOW}Getting VM IP address...${NC}"

IP=""
for net in $(virsh net-list --name); do
    LEASE_IP=$(virsh net-dhcp-leases "$net" 2>/dev/null | grep "$VM_NAME" | awk '{print $5}' | cut -d'/' -f1)
    if [ -n "$LEASE_IP" ]; then
        IP="$LEASE_IP"
        echo -e "${GREEN}✓ Found IP: $IP${NC}"
        break
    fi
done

if [ -z "$IP" ]; then
    echo -e "${RED}✗ Could not find IP address${NC}"
    echo -e "${YELLOW}Trying domifaddr...${NC}"
    IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

    if [ -n "$IP" ]; then
        echo -e "${GREEN}✓ Found IP: $IP${NC}"
    else
        echo -e "${RED}✗ Cannot determine IP. VM may not be running.${NC}"
        exit 1
    fi
fi

# Method 1: Try to inject via virt-customize (if available)
if command -v virt-customize &> /dev/null; then
    echo -e "\n${YELLOW}Attempting to inject key via virt-customize...${NC}"

    # Get disk path
    DISK=$(virsh domblklist "$VM_NAME" | grep vda | awk '{print $2}')

    if [ -n "$DISK" ]; then
        # Shutdown VM first
        echo -e "${YELLOW}Shutting down VM...${NC}"
        virsh shutdown "$VM_NAME" 2>/dev/null || true
        sleep 10

        # Force destroy if still running
        virsh destroy "$VM_NAME" 2>/dev/null || true
        sleep 2

        # Inject key
        virt-customize -a "$DISK" \
            --ssh-inject ansible:file:/root/.ssh/ansible-lab.pub \
            --selinux-relabel

        # Start VM
        echo -e "${YELLOW}Starting VM...${NC}"
        virsh start "$VM_NAME"
        sleep 30

        echo -e "${GREEN}✓ Key injected via virt-customize${NC}"
    fi
else
    echo -e "${YELLOW}virt-customize not available, using console method${NC}"
fi

# Method 2: Manual fix via console commands
echo -e "\n${YELLOW}=== Manual Fix Instructions ===${NC}\n"

echo -e "${YELLOW}1. Access the VM console:${NC}"
echo -e "   ${BLUE}virsh console $VM_NAME${NC}"
echo ""

echo -e "${YELLOW}2. Login (you may need to press Enter or reboot if no prompt)${NC}"
echo ""

echo -e "${YELLOW}3. Run these commands in the VM console:${NC}"
echo -e "${BLUE}"
cat << 'EOF'
# Create .ssh directory for ansible user
sudo mkdir -p /home/ansible/.ssh
sudo chmod 700 /home/ansible/.ssh

# Add your public key (paste the key shown above)
sudo tee /home/ansible/.ssh/authorized_keys << 'PUBKEY'
EOF
echo "$PUB_KEY"
cat << 'EOF'
PUBKEY

# Fix permissions
sudo chmod 600 /home/ansible/.ssh/authorized_keys
sudo chown -R ansible:ansible /home/ansible/.ssh

# Verify it was added
sudo cat /home/ansible/.ssh/authorized_keys

# Restart SSH
sudo systemctl restart sshd

# Exit console (Ctrl + ])
EOF
echo -e "${NC}"

# Wait and test
echo -e "\n${YELLOW}4. After running the above commands, test SSH:${NC}"
echo -e "   ${BLUE}ssh -i /root/.ssh/ansible-lab ansible@$IP${NC}"

# Automated script for in-VM execution
echo -e "\n${YELLOW}=== Automated In-VM Script ===${NC}"
echo -e "If you can get into the VM console, run this one-liner:\n"

echo -e "${BLUE}sudo bash -c 'mkdir -p /home/ansible/.ssh && chmod 700 /home/ansible/.ssh && echo \"$PUB_KEY\" > /home/ansible/.ssh/authorized_keys && chmod 600 /home/ansible/.ssh/authorized_keys && chown -R ansible:ansible /home/ansible/.ssh && systemctl restart sshd && echo \"SSH key fixed!\"'${NC}"

echo -e "\n${GREEN}After fixing, test with:${NC}"
echo -e "${BLUE}ssh -i /root/.ssh/ansible-lab ansible@$IP${NC}"

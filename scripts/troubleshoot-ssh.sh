#!/bin/bash

# VM SSH Login Troubleshooting Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== VM SSH Login Troubleshooting ===${NC}\n"

# Get VM name
if [ -z "$1" ]; then
    echo -e "${YELLOW}Available VMs:${NC}"
    sudo virsh list --all
    echo ""
    read -p "Enter VM name to troubleshoot: " VM_NAME
else
    VM_NAME="$1"
fi

echo -e "\n${YELLOW}Checking VM: $VM_NAME${NC}\n"

# Check if VM exists
if ! sudo virsh dominfo "$VM_NAME" &> /dev/null; then
    echo -e "${RED}✗ VM '$VM_NAME' not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ VM exists${NC}"

# Check VM state
STATE=$(sudo virsh domstate "$VM_NAME")
echo -e "VM State: ${GREEN}$STATE${NC}"

if [ "$STATE" != "running" ]; then
    echo -e "${RED}✗ VM is not running${NC}"
    echo -e "${YELLOW}Starting VM...${NC}"
    sudo virsh start "$VM_NAME"
    sleep 5
fi

# Get IP address
echo -e "\n${YELLOW}Getting IP address...${NC}"

# Try multiple methods to get IP
IP=""

# Method 1: DHCP leases
for net in $(sudo virsh net-list --name); do
    LEASE_IP=$(sudo virsh net-dhcp-leases "$net" 2>/dev/null | grep "$VM_NAME" | awk '{print $5}' | cut -d'/' -f1)
    if [ -n "$LEASE_IP" ]; then
        IP="$LEASE_IP"
        echo -e "${GREEN}✓ Found IP from DHCP lease ($net): $IP${NC}"
        break
    fi
done

# Method 2: domifaddr
if [ -z "$IP" ]; then
    DOMIF_IP=$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    if [ -n "$DOMIF_IP" ]; then
        IP="$DOMIF_IP"
        echo -e "${GREEN}✓ Found IP from domifaddr: $IP${NC}"
    fi
fi

if [ -z "$IP" ]; then
    echo -e "${RED}✗ Could not determine IP address${NC}"
    echo -e "${YELLOW}VM may still be booting. Wait 30-60 seconds and try again.${NC}"

    echo -e "\n${YELLOW}You can check VM console:${NC}"
    echo -e "  sudo virsh console $VM_NAME"
    echo -e "  (Then login and run: ip addr)"
    exit 1
fi

# Find SSH key
echo -e "\n${YELLOW}Looking for SSH key...${NC}"

SSH_KEY=""
POSSIBLE_KEYS=(
    "$HOME/.ssh/ansible-lab"
    "/var/lib/jira-provisioner/ssh-keys/$VM_NAME"
    "/var/lib/libvirt/images/ansible-lab/${VM_NAME}-key"
)

for key in "${POSSIBLE_KEYS[@]}"; do
    if [ -f "$key" ]; then
        SSH_KEY="$key"
        echo -e "${GREEN}✓ Found SSH key: $SSH_KEY${NC}"
        break
    fi
done

if [ -z "$SSH_KEY" ]; then
    echo -e "${RED}✗ SSH key not found${NC}"
    echo -e "${YELLOW}Checked locations:${NC}"
    for key in "${POSSIBLE_KEYS[@]}"; do
        echo "  - $key"
    done
    exit 1
fi

# Check key permissions
echo -e "\n${YELLOW}Checking SSH key permissions...${NC}"
PERMS=$(stat -c %a "$SSH_KEY" 2>/dev/null || stat -f %A "$SSH_KEY" 2>/dev/null)

if [ "$PERMS" != "600" ] && [ "$PERMS" != "400" ]; then
    echo -e "${YELLOW}⚠ SSH key permissions are $PERMS (should be 600)${NC}"
    echo -e "${YELLOW}Fixing permissions...${NC}"
    chmod 600 "$SSH_KEY"
    echo -e "${GREEN}✓ Fixed permissions to 600${NC}"
else
    echo -e "${GREEN}✓ SSH key permissions correct ($PERMS)${NC}"
fi

# Check network connectivity
echo -e "\n${YELLOW}Testing network connectivity to $IP...${NC}"

if ping -c 1 -W 2 "$IP" &> /dev/null; then
    echo -e "${GREEN}✓ VM is reachable via ping${NC}"
else
    echo -e "${RED}✗ Cannot ping VM${NC}"
    echo -e "${YELLOW}VM may still be booting or network issue${NC}"
fi

# Try different usernames
echo -e "\n${YELLOW}Testing SSH access...${NC}"

USERS=("ansible" "sectest" "centos" "cloud-user" "admin")
SSH_USER=""

for user in "${USERS[@]}"; do
    echo -e "Trying user: ${BLUE}$user${NC}"

    if timeout 5 ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 \
        -o BatchMode=yes \
        "$user@$IP" "echo 'success'" &> /dev/null; then

        SSH_USER="$user"
        echo -e "${GREEN}✓ SSH access successful with user: $SSH_USER${NC}"
        break
    fi
done

if [ -z "$SSH_USER" ]; then
    echo -e "${RED}✗ SSH access failed with all users${NC}"

    echo -e "\n${YELLOW}=== Diagnostic Information ===${NC}"

    # Check if cloud-init is running
    echo -e "\n${YELLOW}Checking cloud-init status (via console)...${NC}"
    echo -e "${YELLOW}This requires VM console access. Attempting...${NC}"

    # Try to get cloud-init status via virsh console (non-interactive)
    echo -e "\n${YELLOW}Common issues:${NC}"
    echo "1. Cloud-init still running (wait 2-3 minutes after VM start)"
    echo "2. SSH key not injected properly"
    echo "3. Wrong SSH user (try: ansible, sectest, centos, cloud-user)"
    echo "4. VM network not configured"
    echo "5. Firewall blocking SSH"

    echo -e "\n${YELLOW}Manual checks:${NC}"
    echo "1. Access VM console:"
    echo -e "   ${BLUE}sudo virsh console $VM_NAME${NC}"
    echo "   (Press Enter, then Ctrl+] to exit)"
    echo ""
    echo "2. Check cloud-init status from console:"
    echo -e "   ${BLUE}sudo cloud-init status${NC}"
    echo ""
    echo "3. Check SSH is running:"
    echo -e "   ${BLUE}sudo systemctl status sshd${NC}"
    echo ""
    echo "4. Check authorized_keys:"
    echo -e "   ${BLUE}sudo cat /home/*/. ssh/authorized_keys${NC}"

    echo -e "\n${YELLOW}Detailed SSH attempt:${NC}"
    ssh -vvv -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        "ansible@$IP" 2>&1 | tail -20

    exit 1
fi

# Success!
echo -e "\n${GREEN}=== SSH Access Successful ===${NC}\n"

echo -e "${GREEN}Connection Command:${NC}"
echo -e "${BLUE}ssh -i $SSH_KEY $SSH_USER@$IP${NC}"

echo -e "\n${GREEN}Or with options:${NC}"
echo -e "${BLUE}ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$IP${NC}"

echo -e "\n${YELLOW}Testing sudo access...${NC}"
if ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$SSH_USER@$IP" "sudo whoami" 2>/dev/null | grep -q "root"; then
    echo -e "${GREEN}✓ Sudo access confirmed${NC}"
else
    echo -e "${YELLOW}⚠ Sudo may require password${NC}"
fi

echo -e "\n${GREEN}You can now access the VM:${NC}"
echo -e "${BLUE}ssh -i $SSH_KEY $SSH_USER@$IP${NC}"

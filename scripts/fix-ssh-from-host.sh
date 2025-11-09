#!/bin/bash

# Fix SSH authorized_keys directly from host (no VM login needed)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Fixing SSH Keys from Host ===${NC}\n"

VM_NAME="${1:-control}"

echo -e "${YELLOW}Fixing VM: $VM_NAME${NC}\n"

# Check if VM exists
if ! virsh dominfo "$VM_NAME" &> /dev/null; then
    echo -e "${RED}✗ VM '$VM_NAME' not found${NC}"
    virsh list --all
    exit 1
fi

# Get public key
PUB_KEY_FILE="/root/.ssh/ansible-lab.pub"

if [ ! -f "$PUB_KEY_FILE" ]; then
    echo -e "${RED}✗ Public key not found: $PUB_KEY_FILE${NC}"
    exit 1
fi

PUB_KEY=$(cat "$PUB_KEY_FILE")
echo -e "${GREEN}✓ Found public key${NC}"
echo "Key fingerprint: $(ssh-keygen -lf "$PUB_KEY_FILE")"

# Get VM disk
DISK=$(virsh domblklist "$VM_NAME" | grep -E 'vda|sda' | awk '{print $2}' | head -1)

if [ -z "$DISK" ]; then
    echo -e "${RED}✗ Could not find VM disk${NC}"
    echo -e "${YELLOW}Disk list:${NC}"
    virsh domblklist "$VM_NAME"
    exit 1
fi

echo -e "${GREEN}✓ Found VM disk: $DISK${NC}"

# Shutdown VM
echo -e "\n${YELLOW}Shutting down VM...${NC}"
STATE=$(virsh domstate "$VM_NAME")

if [ "$STATE" = "running" ]; then
    virsh shutdown "$VM_NAME"
    echo "Waiting for shutdown..."

    # Wait up to 30 seconds for graceful shutdown
    for i in {1..30}; do
        sleep 1
        STATE=$(virsh domstate "$VM_NAME")
        if [ "$STATE" = "shut off" ]; then
            break
        fi
    done

    # Force destroy if still running
    if [ "$STATE" != "shut off" ]; then
        echo -e "${YELLOW}Force stopping VM...${NC}"
        virsh destroy "$VM_NAME"
        sleep 2
    fi
fi

echo -e "${GREEN}✓ VM is shut down${NC}"

# Method 1: Try guestfish (most reliable)
if command -v guestfish &> /dev/null; then
    echo -e "\n${YELLOW}Using guestfish to inject SSH key...${NC}"

    guestfish -a "$DISK" -i << EOF
mkdir-p /home/ansible/.ssh
chmod 0700 /home/ansible/.ssh
write /home/ansible/.ssh/authorized_keys "$PUB_KEY"
chmod 0600 /home/ansible/.ssh/authorized_keys
chown 1000 1000 /home/ansible/.ssh
chown 1000 1000 /home/ansible/.ssh/authorized_keys
EOF

    echo -e "${GREEN}✓ SSH key injected via guestfish${NC}"

# Method 2: Try virt-edit
elif command -v virt-edit &> /dev/null; then
    echo -e "\n${YELLOW}Using virt-edit to inject SSH key...${NC}"

    # Create temp file with public key
    TEMP_KEY=$(mktemp)
    echo "$PUB_KEY" > "$TEMP_KEY"

    virt-edit -a "$DISK" /home/ansible/.ssh/authorized_keys -e "s|.*|$(cat $TEMP_KEY)|"

    rm -f "$TEMP_KEY"

    echo -e "${GREEN}✓ SSH key injected via virt-edit${NC}"

# Method 3: Try virt-customize
elif command -v virt-customize &> /dev/null; then
    echo -e "\n${YELLOW}Using virt-customize to inject SSH key...${NC}"

    virt-customize -a "$DISK" \
        --mkdir /home/ansible/.ssh:mode:0700 \
        --upload "$PUB_KEY_FILE":/home/ansible/.ssh/authorized_keys \
        --chmod 0600:/home/ansible/.ssh/authorized_keys \
        --run-command 'chown -R ansible:ansible /home/ansible/.ssh' \
        --selinux-relabel

    echo -e "${GREEN}✓ SSH key injected via virt-customize${NC}"

else
    echo -e "${RED}✗ No libguestfs tools available${NC}"
    echo -e "${YELLOW}Install with: dnf install libguestfs-tools${NC}"

    # Start VM back up
    virsh start "$VM_NAME"
    exit 1
fi

# Start VM
echo -e "\n${YELLOW}Starting VM...${NC}"
virsh start "$VM_NAME"

echo -e "${GREEN}✓ VM started${NC}"

# Wait for boot
echo -e "\n${YELLOW}Waiting for VM to boot (30 seconds)...${NC}"
sleep 30

# Get IP
echo -e "${YELLOW}Getting IP address...${NC}"
IP=""
for i in {1..10}; do
    for net in $(virsh net-list --name); do
        IP=$(virsh net-dhcp-leases "$net" 2>/dev/null | grep "$VM_NAME" | awk '{print $5}' | cut -d'/' -f1)
        if [ -n "$IP" ]; then
            break 2
        fi
    done
    sleep 2
done

if [ -z "$IP" ]; then
    echo -e "${YELLOW}⚠ Could not get IP yet, VM may still be booting${NC}"
    echo -e "${YELLOW}Check with: virsh net-dhcp-leases default${NC}"
    echo -e "\nThen test SSH with:"
    echo -e "${BLUE}ssh -i /root/.ssh/ansible-lab ansible@<ip-address>${NC}"
    exit 0
fi

echo -e "${GREEN}✓ VM IP: $IP${NC}"

# Wait a bit more for SSH to start
echo -e "\n${YELLOW}Waiting for SSH service (30 seconds)...${NC}"
sleep 30

# Test SSH
echo -e "\n${YELLOW}Testing SSH connection...${NC}"

if ssh -i /root/.ssh/ansible-lab \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    ansible@"$IP" "echo 'SSH access successful!'" 2>/dev/null; then

    echo -e "\n${GREEN}🎉 SUCCESS! SSH is working!${NC}\n"
    echo -e "${GREEN}Connect with:${NC}"
    echo -e "${BLUE}ssh -i /root/.ssh/ansible-lab ansible@$IP${NC}"

else
    echo -e "\n${YELLOW}⚠ SSH not ready yet. Give it another 30 seconds and try:${NC}"
    echo -e "${BLUE}ssh -i /root/.ssh/ansible-lab ansible@$IP${NC}"
    echo -e "\nOr test with verbose output:"
    echo -e "${BLUE}ssh -vvv -i /root/.ssh/ansible-lab ansible@$IP${NC}"
fi

echo -e "\n${GREEN}=== Fix Complete ===${NC}"

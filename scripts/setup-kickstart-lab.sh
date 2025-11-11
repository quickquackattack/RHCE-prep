#!/bin/bash

# Rocky Linux VM setup with Kickstart (no cloud-init)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Rocky Linux VM Lab Setup (Kickstart-based) ===${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Configuration
IMAGES_DIR="/var/lib/libvirt/images/ansible-lab"
ISO_URL="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-minimal.iso"
ISO_FILE="$IMAGES_DIR/rocky-9-minimal.iso"
SSH_KEY="/root/.ssh/ansible-lab"

# Step 1: Clean up existing VMs
echo -e "${YELLOW}Step 1: Cleaning up existing VMs...${NC}\n"

VMS=("control" "node1" "node2" "node3" "node4")

for vm_name in "${VMS[@]}"; do
    if virsh dominfo "$vm_name" &> /dev/null; then
        echo "Destroying $vm_name..."
        virsh destroy "$vm_name" 2>/dev/null || true
        virsh undefine "$vm_name" --remove-all-storage 2>/dev/null || true
    fi
done

# Clean up network
if virsh net-info ansible-lab &> /dev/null; then
    virsh net-destroy ansible-lab 2>/dev/null || true
    virsh net-undefine ansible-lab 2>/dev/null || true
fi

# Clean up old images
if [ -d "$IMAGES_DIR" ]; then
    rm -rf "$IMAGES_DIR"
fi

mkdir -p "$IMAGES_DIR"

echo -e "${GREEN}✓ Cleanup complete${NC}\n"

# Step 2: Setup SSH keys
echo -e "${YELLOW}Step 2: Setting up SSH keys...${NC}\n"

if [ -f "$SSH_KEY" ]; then
    rm -f "$SSH_KEY" "$SSH_KEY.pub"
fi

ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -C "ansible-lab-key"
chmod 600 "$SSH_KEY"
chmod 644 "$SSH_KEY.pub"

SSH_PUB_KEY=$(cat "$SSH_KEY.pub")

echo -e "${GREEN}✓ SSH keys created${NC}\n"

# Step 3: Download Rocky Linux ISO
echo -e "${YELLOW}Step 3: Downloading Rocky Linux ISO...${NC}\n"

if [ ! -f "$ISO_FILE" ]; then
    echo "Downloading Rocky Linux 9 (this will take several minutes)..."
    wget -O "$ISO_FILE" "$ISO_URL"
    echo -e "${GREEN}✓ ISO downloaded${NC}\n"
else
    echo -e "${GREEN}✓ ISO already exists${NC}\n"
fi

# Step 4: Create network
echo -e "${YELLOW}Step 4: Creating network...${NC}\n"

NETWORK_XML="$IMAGES_DIR/network.xml"

cat > "$NETWORK_XML" << 'EOF'
<network>
  <name>ansible-lab</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr-ansible' stp='on' delay='0'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.10' end='192.168.100.50'/>
      <host mac='52:54:00:00:01:01' name='control' ip='192.168.100.10'/>
      <host mac='52:54:00:00:01:02' name='node1' ip='192.168.100.11'/>
      <host mac='52:54:00:00:01:03' name='node2' ip='192.168.100.12'/>
      <host mac='52:54:00:00:01:04' name='node3' ip='192.168.100.13'/>
      <host mac='52:54:00:00:01:05' name='node4' ip='192.168.100.14'/>
    </dhcp>
  </ip>
</network>
EOF

virsh net-define "$NETWORK_XML"
virsh net-start ansible-lab
virsh net-autostart ansible-lab

echo -e "${GREEN}✓ Network created${NC}\n"

# Step 5: Create kickstart files
echo -e "${YELLOW}Step 5: Creating kickstart files...${NC}\n"

declare -A VMS_CONFIG=(
    ["control"]="192.168.100.10|52:54:00:00:01:01|2048|2"
    ["node1"]="192.168.100.11|52:54:00:00:01:02|1024|1"
    ["node2"]="192.168.100.12|52:54:00:00:01:03|1024|1"
    ["node3"]="192.168.100.13|52:54:00:00:01:04|1024|1"
    ["node4"]="192.168.100.14|52:54:00:00:01:05|1024|1"
)

for vm_name in "${!VMS_CONFIG[@]}"; do
    IFS='|' read -r ip mac memory vcpus <<< "${VMS_CONFIG[$vm_name]}"

    KS_FILE="$IMAGES_DIR/${vm_name}-ks.cfg"

    cat > "$KS_FILE" << EOF
# Rocky Linux 9 Kickstart for ${vm_name}

# Use text install
text

# Don't run the Setup Agent on first boot
firstboot --disable

# Keyboard layouts
keyboard us

# System language
lang en_US.UTF-8

# Network configuration
network --bootproto=static --ip=${ip} --netmask=255.255.255.0 --gateway=192.168.100.1 --nameserver=8.8.8.8 --hostname=${vm_name}.ansible.lab --device=eth0 --onboot=yes

# Root password (will be disabled, using ansible user instead)
rootpw --lock

# System timezone
timezone America/New_York --utc

# System bootloader configuration
bootloader --location=mbr --boot-drive=vda

# Partition clearing information
clearpart --all --initlabel --drives=vda

# Disk partitioning
part /boot --fstype=xfs --size=1024 --ondisk=vda
part pv.01 --size=1 --grow --ondisk=vda
volgroup vg_main pv.01
logvol / --fstype=xfs --name=lv_root --vgname=vg_main --size=8192 --grow
logvol swap --fstype=swap --name=lv_swap --vgname=vg_main --size=1024

# Shutdown after installation (will be started manually)
poweroff

# Package selection
%packages
@core
@base
vim
wget
curl
git
openssh-server
python3
python3-pip
%end

# Post-installation script
%post --log=/root/ks-post.log

# Create ansible user
useradd -m -s /bin/bash ansible

# Set up sudo for ansible user
echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
chmod 0440 /etc/sudoers.d/ansible

# Create .ssh directory
mkdir -p /home/ansible/.ssh
chmod 700 /home/ansible/.ssh

# Add SSH public key
cat > /home/ansible/.ssh/authorized_keys << 'SSHKEY'
${SSH_PUB_KEY}
SSHKEY

chmod 600 /home/ansible/.ssh/authorized_keys
chown -R ansible:ansible /home/ansible/.ssh

# Enable and start SSH
systemctl enable sshd
systemctl start sshd

# Configure firewall
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# Disable SELinux (for lab environment)
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
setenforce 0 || true

# Update system
dnf update -y

%end
EOF

    echo "Created kickstart for $vm_name"
done

echo -e "${GREEN}✓ Kickstart files created${NC}\n"

# Step 6: Create VMs (they will auto-install)
echo -e "${YELLOW}Step 6: Creating and installing VMs...${NC}"
echo -e "${YELLOW}This will take 10-15 minutes per VM (running in parallel)${NC}\n"

# Create VMs in background
for vm_name in "${!VMS_CONFIG[@]}"; do
    IFS='|' read -r ip mac memory vcpus <<< "${VMS_CONFIG[$vm_name]}"

    echo "Starting installation for $vm_name..."

    VM_DISK="$IMAGES_DIR/${vm_name}.qcow2"
    KS_FILE="$IMAGES_DIR/${vm_name}-ks.cfg"

    # Create disk
    qemu-img create -f qcow2 "$VM_DISK" 20G

    # Start installation with kickstart
    virt-install \
        --name "$vm_name" \
        --memory "$memory" \
        --vcpus "$vcpus" \
        --disk path="$VM_DISK",format=qcow2,bus=virtio \
        --network network=ansible-lab,mac="$mac",model=virtio \
        --os-variant rhel9.0 \
        --location "$ISO_FILE" \
        --initrd-inject="$KS_FILE" \
        --extra-args "inst.ks=file:/${vm_name}-ks.cfg console=ttyS0" \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole \
        --wait=-1 \
        --noreboot &

    # Small delay between VM starts
    sleep 2
done

echo -e "\n${YELLOW}VMs are installing in the background...${NC}"
echo -e "${YELLOW}You can monitor progress with: virsh list --all${NC}"
echo -e "${YELLOW}Or watch a specific VM: virsh console <vm-name>${NC}"
echo -e "${YELLOW}Press Ctrl+] to exit console${NC}\n"

# Wait for installations to complete
echo -e "${YELLOW}Waiting for installations to complete (this takes 10-15 minutes)...${NC}"
echo -e "${YELLOW}VMs will power off when installation is complete.${NC}\n"

ALL_DONE=false
TIMEOUT=1200  # 20 minutes timeout
ELAPSED=0

while [ "$ALL_DONE" = false ] && [ $ELAPSED -lt $TIMEOUT ]; do
    ALL_DONE=true

    for vm_name in "${!VMS_CONFIG[@]}"; do
        if virsh dominfo "$vm_name" &> /dev/null; then
            STATE=$(virsh domstate "$vm_name" 2>/dev/null || echo "unknown")

            # If still running, installation not done (will power off when complete)
            if [ "$STATE" = "running" ]; then
                ALL_DONE=false
            fi
        else
            ALL_DONE=false
        fi
    done

    if [ "$ALL_DONE" = false ]; then
        RUNNING=$(virsh list --state-running --name 2>/dev/null | grep -E 'control|node' | wc -l)
        echo -ne "\rWaiting for installations... ${ELAPSED}s / ${TIMEOUT}s (${RUNNING} VMs still installing)  "
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    fi
done

echo ""

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${YELLOW}⚠ Timeout reached. Some VMs may still be installing.${NC}"
    echo -e "${YELLOW}Check status with: virsh list --all${NC}\n"
else
    echo -e "${GREEN}✓ All installations complete!${NC}\n"
fi

# Start all VMs
echo -e "${YELLOW}Starting all VMs...${NC}\n"

for vm_name in "${!VMS_CONFIG[@]}"; do
    if virsh dominfo "$vm_name" &> /dev/null; then
        STATE=$(virsh domstate "$vm_name" 2>/dev/null || echo "shut off")
        if [ "$STATE" = "shut off" ]; then
            echo "Starting $vm_name..."
            virsh start "$vm_name"
        else
            echo "$vm_name is already running"
        fi
    else
        echo -e "${RED}⚠ $vm_name was not created properly${NC}"
    fi
done

echo -e "\n${YELLOW}Waiting 60 seconds for VMs to boot...${NC}"
sleep 60

# Step 7: Verify SSH access
echo -e "\n${YELLOW}Step 7: Verifying SSH access...${NC}\n"

SUCCESS_COUNT=0
FAILED_VMS=()

for vm_name in "${!VMS_CONFIG[@]}"; do
    IFS='|' read -r ip mac memory vcpus <<< "${VMS_CONFIG[$vm_name]}"

    echo -n "Testing $vm_name ($ip)... "

    if timeout 10 ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        ansible@"$ip" "echo 'success'" &> /dev/null; then

        echo -e "${GREEN}✓ SUCCESS${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${YELLOW}⚠ Not ready yet${NC}"
        FAILED_VMS+=("$vm_name")
    fi
done

echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}\n"

if [ ${#FAILED_VMS[@]} -eq 0 ]; then
    echo -e "${GREEN}🎉 All VMs are ready and accessible!${NC}\n"
else
    echo -e "${YELLOW}⚠ Some VMs may need more time:${NC}"
    for vm in "${FAILED_VMS[@]}"; do
        echo "  - $vm"
    done
    echo ""
    echo -e "${YELLOW}Wait 1-2 more minutes and test manually${NC}"
fi

echo -e "${GREEN}SSH Access:${NC}"
for vm_name in "${!VMS_CONFIG[@]}"; do
    IFS='|' read -r ip mac memory vcpus <<< "${VMS_CONFIG[$vm_name]}"
    echo -e "  ${BLUE}ssh -i $SSH_KEY ansible@$ip${NC}  # $vm_name"
done

echo -e "\n${GREEN}View VM status:${NC}"
echo -e "  ${BLUE}virsh list --all${NC}"

echo -e "\n${GREEN}=== Installation Complete ===${NC}\n"

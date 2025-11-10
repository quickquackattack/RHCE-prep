#!/bin/bash

# Complete VM recreation with SSH key verification

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Complete VM Lab Rebuild ===${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Step 1: Clean up everything
echo -e "${YELLOW}Step 1: Cleaning up existing VMs and networks...${NC}\n"

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
    echo "Destroying ansible-lab network..."
    virsh net-destroy ansible-lab 2>/dev/null || true
    virsh net-undefine ansible-lab 2>/dev/null || true
fi

# Clean up images
IMAGES_DIR="/var/lib/libvirt/images/ansible-lab"
if [ -d "$IMAGES_DIR" ]; then
    echo "Cleaning up images directory..."
    rm -rf "$IMAGES_DIR"
fi

echo -e "${GREEN}✓ Cleanup complete${NC}\n"

# Step 2: Setup SSH keys
echo -e "${YELLOW}Step 2: Setting up SSH keys...${NC}\n"

SSH_KEY="/root/.ssh/ansible-lab"

# Remove old keys
if [ -f "$SSH_KEY" ]; then
    echo "Removing old SSH keys..."
    rm -f "$SSH_KEY" "$SSH_KEY.pub"
fi

# Generate new SSH key
echo "Generating new SSH key pair..."
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -C "ansible-lab-key"

# Fix permissions
chmod 600 "$SSH_KEY"
chmod 644 "$SSH_KEY.pub"

echo -e "${GREEN}✓ SSH keys created${NC}"
echo "Public key:"
cat "$SSH_KEY.pub"
echo ""

# Step 3: Create images directory
echo -e "${YELLOW}Step 3: Creating images directory...${NC}\n"

mkdir -p "$IMAGES_DIR"

echo -e "${GREEN}✓ Directory created${NC}\n"

# Step 4: Download base image if needed
echo -e "${YELLOW}Step 4: Checking base image...${NC}\n"

BASE_IMAGE_URL="https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
BASE_IMAGE="$IMAGES_DIR/centos-stream-9-base.qcow2"

if [ ! -f "$BASE_IMAGE" ]; then
    echo "Downloading base image (this may take a few minutes)..."
    wget -O "$BASE_IMAGE" "$BASE_IMAGE_URL"
    echo -e "${GREEN}✓ Base image downloaded${NC}\n"
else
    echo -e "${GREEN}✓ Base image already exists${NC}\n"
fi

# Step 5: Create network
echo -e "${YELLOW}Step 5: Creating network...${NC}\n"

NETWORK_XML="/tmp/ansible-lab-network.xml"

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

# Step 6: Create VMs
echo -e "${YELLOW}Step 6: Creating VMs...${NC}\n"

declare -A VMS_CONFIG=(
    ["control"]="192.168.100.10|52:54:00:00:01:01|2048|2"
    ["node1"]="192.168.100.11|52:54:00:00:01:02|1024|1"
    ["node2"]="192.168.100.12|52:54:00:00:01:03|1024|1"
    ["node3"]="192.168.100.13|52:54:00:00:01:04|1024|1"
    ["node4"]="192.168.100.14|52:54:00:00:01:05|1024|1"
)

for vm_name in "${!VMS_CONFIG[@]}"; do
    IFS='|' read -r ip mac memory vcpus <<< "${VMS_CONFIG[$vm_name]}"

    echo -e "\n${BLUE}Creating $vm_name...${NC}"

    # Create disk
    VM_DISK="$IMAGES_DIR/${vm_name}.qcow2"
    qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$VM_DISK" 20G

    # Create cloud-init user-data
    USER_DATA="$IMAGES_DIR/${vm_name}-user-data.yaml"

    cat > "$USER_DATA" << EOF
#cloud-config
hostname: ${vm_name}
fqdn: ${vm_name}.ansible.lab
manage_etc_hosts: true

users:
  - name: ansible
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - $(cat $SSH_KEY.pub)

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
  - restorecon -R /home/ansible/.ssh || true

final_message: "VM ${vm_name} is ready"
EOF

    # Create meta-data
    META_DATA="$IMAGES_DIR/${vm_name}-meta-data.yaml"
    cat > "$META_DATA" << EOF
instance-id: ${vm_name}
local-hostname: ${vm_name}
EOF

    # Create cloud-init ISO
    CLOUD_INIT_ISO="$IMAGES_DIR/${vm_name}-cloud-init.iso"

    if command -v genisoimage &> /dev/null; then
        genisoimage -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$USER_DATA" "$META_DATA" &> /dev/null
    else
        mkisofs -o "$CLOUD_INIT_ISO" -V cidata -J -r "$USER_DATA" "$META_DATA" &> /dev/null
    fi

    # Create and start VM
    virt-install \
        --name "$vm_name" \
        --memory "$memory" \
        --vcpus "$vcpus" \
        --disk path="$VM_DISK",format=qcow2,bus=virtio \
        --disk path="$CLOUD_INIT_ISO",device=cdrom \
        --network network=ansible-lab,mac="$mac",model=virtio \
        --os-variant centos-stream9 \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole \
        --import \
        --boot hd

    echo -e "${GREEN}✓ $vm_name created${NC}"
done

echo -e "\n${GREEN}✓ All VMs created${NC}\n"

# Step 7: Wait for VMs to boot
echo -e "${YELLOW}Step 7: Waiting for VMs to boot and cloud-init to complete...${NC}\n"
echo "This takes about 90 seconds..."

for i in {90..1}; do
    echo -ne "\rWaiting: $i seconds...  "
    sleep 1
done
echo ""

echo -e "${GREEN}✓ Boot wait complete${NC}\n"

# Step 8: Verify SSH access
echo -e "${YELLOW}Step 8: Verifying SSH access...${NC}\n"

SUCCESS_COUNT=0
FAILED_VMS=()

for vm_name in "${!VMS_CONFIG[@]}"; do
    IFS='|' read -r ip mac memory vcpus <<< "${VMS_CONFIG[$vm_name]}"

    echo -n "Testing $vm_name ($ip)... "

    if timeout 10 ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        ansible@"$ip" "echo 'success'" &> /dev/null; then

        echo -e "${GREEN}✓ SUCCESS${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        FAILED_VMS+=("$vm_name")
    fi
done

echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}\n"

if [ ${#FAILED_VMS[@]} -eq 0 ]; then
    echo -e "${GREEN}🎉 All VMs are accessible via SSH!${NC}\n"

    echo -e "${GREEN}Connect with:${NC}"
    for vm_name in "${!VMS_CONFIG[@]}"; do
        IFS='|' read -r ip mac memory vcpus <<< "${VMS_CONFIG[$vm_name]}"
        echo -e "  ${BLUE}ssh -i $SSH_KEY ansible@$ip${NC}  # $vm_name"
    done

    echo -e "\n${GREEN}Or use Ansible:${NC}"
    echo -e "  ${BLUE}cd ansible${NC}"
    echo -e "  ${BLUE}ansible all -m ping${NC}"

    echo -e "\n${GREEN}View status:${NC}"
    echo -e "  ${BLUE}bash scripts/lab-status.sh${NC}"

else
    echo -e "${YELLOW}⚠ ${#FAILED_VMS[@]} VM(s) failed SSH test:${NC}"
    for vm in "${FAILED_VMS[@]}"; do
        echo "  - $vm"
    done

    echo -e "\n${YELLOW}These VMs may need more time. Try again in 1-2 minutes:${NC}"
    for vm in "${FAILED_VMS[@]}"; do
        IFS='|' read -r ip mac memory vcpus <<< "${VMS_CONFIG[$vm]}"
        echo -e "  ${BLUE}ssh -i $SSH_KEY ansible@$ip${NC}  # $vm"
    done

    echo -e "\n${YELLOW}Or check cloud-init status:${NC}"
    echo -e "  ${BLUE}virsh console ${FAILED_VMS[0]}${NC}"
    echo -e "  Then run: ${BLUE}sudo cloud-init status${NC}"
fi

echo -e "\n${GREEN}=== Lab Rebuild Complete ===${NC}\n"

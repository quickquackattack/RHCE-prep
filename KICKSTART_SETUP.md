# Kickstart-Based Lab Setup Guide

This guide covers setting up the Ansible lab using traditional Rocky Linux installation with kickstart files instead of cloud-init.

## Why Kickstart Instead of Cloud-Init?

**Advantages:**
- ✅ More reliable and predictable
- ✅ Full control over installation process
- ✅ No dependency on cloud-init working properly
- ✅ Traditional RHEL/Rocky installation method
- ✅ Better for RHCE exam preparation (uses similar methods)

**Disadvantages:**
- ⏱️ Takes longer (10-15 minutes vs 2-3 minutes)
- 💾 Requires downloading full ISO (~1.5GB)
- 📦 Full installation instead of minimal cloud image

## Quick Start

### One-Command Setup

```bash
bash /home/user/RHCE-prep/scripts/setup-kickstart-lab.sh
```

This script will:
1. Download Rocky Linux 9 ISO (~1.5GB)
2. Create SSH keys
3. Generate kickstart files for each VM
4. Install all 5 VMs automatically
5. Verify SSH access

**Time:** 15-20 minutes total

## What the Kickstart Setup Does

### For Each VM:

1. **Automated Installation**
   - Partitions disk (LVM-based)
   - Installs Rocky Linux 9 minimal
   - Configures network with static IP

2. **User Configuration**
   - Creates `ansible` user
   - Sets up passwordless sudo
   - Injects your SSH public key
   - Locks root account (SSH key only)

3. **System Configuration**
   - Enables SSH service
   - Configures firewall
   - Sets SELinux to permissive (for lab)
   - Installs essential packages
   - Updates all packages

## Monitoring Installation Progress

### Check VM Status

```bash
# List all VMs
virsh list --all

# You'll see VMs in "running" state during installation
```

### Watch Installation

```bash
# Connect to VM console to watch installation
virsh console control

# Press Ctrl+] to exit console
```

### Installation Stages

1. **running** - Installing from ISO
2. **shut off** - Installation complete, VM rebooted
3. **running** - VM fully installed and running

## After Installation

### SSH Access

Once complete, connect with:

```bash
ssh -i /root/.ssh/ansible-lab ansible@192.168.100.10  # control
ssh -i /root/.ssh/ansible-lab ansible@192.168.100.11  # node1
ssh -i /root/.ssh/ansible-lab ansible@192.168.100.12  # node2
ssh -i /root/.ssh/ansible-lab ansible@192.168.100.13  # node3
ssh -i /root/.ssh/ansible-lab ansible@192.168.100.14  # node4
```

### Test Ansible

```bash
cd /home/user/RHCE-prep/ansible
ansible all -m ping
```

## Customizing Kickstart Files

### Kickstart File Location

After running the setup script, kickstart files are in:
```
/var/lib/libvirt/images/ansible-lab/control-ks.cfg
/var/lib/libvirt/images/ansible-lab/node1-ks.cfg
...
```

### Common Customizations

#### Add More Packages

Edit the `%packages` section:

```kickstart
%packages
@core
@base
# Add your packages
nmap
wireshark
docker
%end
```

#### Change Partition Layout

```kickstart
# Example: Separate /var partition
part /boot --fstype=xfs --size=1024
part pv.01 --size=1 --grow
volgroup vg_main pv.01
logvol / --fstype=xfs --name=lv_root --vgname=vg_main --size=8192
logvol /var --fstype=xfs --name=lv_var --vgname=vg_main --size=4096
logvol swap --fstype=swap --name=lv_swap --vgname=vg_main --size=1024
```

#### Run Custom Scripts

Add to `%post` section:

```kickstart
%post --log=/root/ks-post.log

# Your custom commands here
curl -o /tmp/setup.sh https://example.com/setup.sh
bash /tmp/setup.sh

%end
```

## Manual Installation (Advanced)

If you want to install VMs one at a time manually:

### 1. Create Kickstart File

```bash
cat > /tmp/control-ks.cfg << 'EOF'
# Your kickstart content here
EOF
```

### 2. Start Installation

```bash
virt-install \
    --name control \
    --memory 2048 \
    --vcpus 2 \
    --disk path=/var/lib/libvirt/images/control.qcow2,size=20,format=qcow2 \
    --network network=ansible-lab,mac=52:54:00:00:01:01 \
    --os-variant rhel9.0 \
    --location /var/lib/libvirt/images/ansible-lab/rocky-9-minimal.iso \
    --initrd-inject=/tmp/control-ks.cfg \
    --extra-args "inst.ks=file:/control-ks.cfg console=ttyS0" \
    --graphics none \
    --console pty,target_type=serial
```

### 3. Watch Installation

Installation happens automatically. Watch the console output.

## Troubleshooting

### ISO Download Fails

```bash
# Manually download ISO
cd /var/lib/libvirt/images/ansible-lab
wget https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-minimal.iso
```

### Installation Hangs

```bash
# Check VM console
virsh console control

# Force reboot if stuck
virsh destroy control
virsh start control
```

### SSH Still Doesn't Work

After kickstart installation, check:

```bash
# 1. VM is running
virsh list --all

# 2. Check from console
virsh console control
# Login as root (no password during install, try single user mode)

# 3. Verify ansible user exists
id ansible

# 4. Check SSH keys
cat /home/ansible/.ssh/authorized_keys

# 5. Check SSH service
systemctl status sshd

# 6. Check firewall
firewall-cmd --list-all
```

### Reinstall Single VM

```bash
# Destroy VM
virsh destroy control
virsh undefine control --remove-all-storage

# Recreate just that VM using the script
# Or manually with virt-install command above
```

## Disk Layout

Default kickstart creates this layout:

```
/dev/vda
├── /dev/vda1     1GB     /boot (xfs)
└── /dev/vda2     ~19GB   LVM PV
    ├── vg_main-lv_root   ~18GB    / (xfs)
    └── vg_main-lv_swap   1GB      swap
```

## Network Configuration

Each VM gets static IP via kickstart:

| VM      | IP              | MAC               |
|---------|-----------------|-------------------|
| control | 192.168.100.10  | 52:54:00:00:01:01 |
| node1   | 192.168.100.11  | 52:54:00:00:01:02 |
| node2   | 192.168.100.12  | 52:54:00:00:01:03 |
| node3   | 192.168.100.13  | 52:54:00:00:01:04 |
| node4   | 192.168.100.14  | 52:54:00:00:01:05 |

Network: 192.168.100.0/24
Gateway: 192.168.100.1
DNS: 8.8.8.8

## Comparison: Cloud-Init vs Kickstart

| Feature | Cloud-Init | Kickstart |
|---------|------------|-----------|
| Speed | Fast (2-3 min) | Slower (10-15 min) |
| Reliability | Can fail | Very reliable |
| Disk Usage | Small (~2GB) | Larger (~5GB) |
| Customization | Limited | Full control |
| RHCE Relevant | No | Yes |
| Network Config | DHCP default | Static IPs |
| Partition Control | Limited | Full LVM control |

## Advanced: Parallel Installation

The script installs all VMs in parallel by default. To install serially:

```bash
# Edit the script, comment out the & at the end of virt-install
# This makes installations sequential instead of parallel
```

## Post-Installation Tasks

### 1. Add SSH Config

```bash
cat >> ~/.ssh/config << 'EOF'
Host ansible-lab-*
  User ansible
  IdentityFile /root/.ssh/ansible-lab
  StrictHostKeyChecking no

Host ansible-lab-control
  HostName 192.168.100.10

Host ansible-lab-node1
  HostName 192.168.100.11

Host ansible-lab-node2
  HostName 192.168.100.12

Host ansible-lab-node3
  HostName 192.168.100.13

Host ansible-lab-node4
  HostName 192.168.100.14
EOF
```

Then use:
```bash
ssh ansible-lab-control
```

### 2. Test Ansible

```bash
cd /home/user/RHCE-prep/ansible
ansible all -m ping
ansible all -m shell -a "hostname"
```

### 3. Run Sample Playbooks

```bash
cd /home/user/RHCE-prep/ansible
ansible-playbook playbooks/gather-facts.yml
ansible-playbook playbooks/install-packages.yml
```

## Files Created

After setup completion:

```
/var/lib/libvirt/images/ansible-lab/
├── rocky-9-minimal.iso           # Rocky Linux ISO
├── control.qcow2                 # VM disk images
├── node1.qcow2
├── node2.qcow2
├── node3.qcow2
├── node4.qcow2
├── control-ks.cfg                # Kickstart files
├── node1-ks.cfg
├── node2-ks.cfg
├── node3-ks.cfg
├── node4-ks.cfg
└── network.xml                   # Network definition

/root/.ssh/
├── ansible-lab                   # Private key
└── ansible-lab.pub               # Public key
```

## Cleanup

To remove everything:

```bash
bash /home/user/RHCE-prep/scripts/destroy-lab.sh
```

This removes:
- All VMs
- Network
- Disk images

SSH keys are preserved in `/root/.ssh/ansible-lab*`

## Next Steps

After successful installation:

1. ✅ Verify all VMs accessible via SSH
2. ✅ Test Ansible connectivity
3. ✅ Run sample playbooks
4. ✅ Practice RHCE tasks

## Getting Help

If installation fails:

1. Check VM console: `virsh console <vm-name>`
2. Check kickstart logs in VM: `cat /root/ks-post.log`
3. Verify ISO downloaded correctly
4. Check available disk space: `df -h`
5. Check libvirt logs: `journalctl -u libvirtd`

## Benefits for RHCE Prep

Using kickstart is excellent RHCE preparation because:

- ✅ Kickstart is tested on RHCE exam
- ✅ Practices automated installation
- ✅ Uses LVM (common on RHCE)
- ✅ Static network configuration
- ✅ User and permission management
- ✅ Firewall configuration
- ✅ SELinux concepts

This lab setup mirrors production Red Hat environments!

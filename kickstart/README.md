# Static Kickstart Files for Ansible Lab

These are **standalone kickstart files** that you can use and modify directly without any script generation.

## Files

```
kickstart/
├── control.ks.cfg    # Control node - 192.168.100.10
├── node1.ks.cfg      # Node 1 - 192.168.100.11
├── node2.ks.cfg      # Node 2 - 192.168.100.12
├── node3.ks.cfg      # Node 3 - 192.168.100.13
├── node4.ks.cfg      # Node 4 - 192.168.100.14
└── base-kickstart.cfg # Template for creating your own
```

## Before Using

### 1. Add Your SSH Public Key

**IMPORTANT:** Edit each kickstart file and replace the placeholder SSH key!

```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096 -f /root/.ssh/ansible-lab -N ""

# View your public key
cat /root/.ssh/ansible-lab.pub
```

Then edit each `.ks.cfg` file:

```bash
vi kickstart/control.ks.cfg
```

Find this section:
```bash
cat > /home/ansible/.ssh/authorized_keys << 'EOF_SSHKEY'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-ssh-public-key-here ansible-lab-key
EOF_SSHKEY
```

Replace `your-ssh-public-key-here` with your actual SSH public key!

**Do this for ALL 5 kickstart files.**

### 2. Download Rocky Linux ISO

```bash
mkdir -p /var/lib/libvirt/images/ansible-lab
cd /var/lib/libvirt/images/ansible-lab
wget https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-minimal.iso -O rocky-9-minimal.iso
```

## Installation Methods

### Method 1: Helper Script (Easiest)

```bash
# Install one VM at a time
bash scripts/install-vm-manual.sh control
bash scripts/install-vm-manual.sh node1
bash scripts/install-vm-manual.sh node2
bash scripts/install-vm-manual.sh node3
bash scripts/install-vm-manual.sh node4
```

The script will:
- Check prerequisites
- Show you your SSH key
- Prompt you to update the kickstart file
- Install the VM
- Test SSH access

### Method 2: Manual virt-install

Install VMs manually one at a time:

```bash
# Example for control node
virt-install \
    --name control \
    --memory 2048 \
    --vcpus 2 \
    --disk path=/var/lib/libvirt/images/ansible-lab/control.qcow2,size=20,format=qcow2 \
    --network network=ansible-lab,mac=52:54:00:00:01:01 \
    --os-variant rhel9.0 \
    --location /var/lib/libvirt/images/ansible-lab/rocky-9-minimal.iso \
    --initrd-inject=/home/user/RHCE-prep/kickstart/control.ks.cfg \
    --extra-args "inst.ks=file:/control.ks.cfg console=ttyS0,115200" \
    --graphics none \
    --console pty,target_type=serial
```

**For other VMs**, adjust:
- `--name` (node1, node2, etc.)
- `--disk path` (match VM name)
- `--memory` (1024 for nodes, 2048 for control)
- `--vcpus` (1 for nodes, 2 for control)
- `--network mac=` (use correct MAC from table below)
- `--initrd-inject=` (use correct kickstart file)
- `--extra-args "inst.ks=file:/XXX.ks.cfg` (match filename)

## VM Specifications

| VM      | IP             | MAC               | RAM  | vCPU | Kickstart File    |
|---------|----------------|-------------------|------|------|-------------------|
| control | 192.168.100.10 | 52:54:00:00:01:01 | 2048 | 2    | control.ks.cfg    |
| node1   | 192.168.100.11 | 52:54:00:00:01:02 | 1024 | 1    | node1.ks.cfg      |
| node2   | 192.168.100.12 | 52:54:00:00:01:03 | 1024 | 1    | node2.ks.cfg      |
| node3   | 192.168.100.13 | 52:54:00:00:01:04 | 1024 | 1    | node3.ks.cfg      |
| node4   | 192.168.100.14 | 52:54:00:00:01:05 | 1024 | 1    | node4.ks.cfg      |

## What's Configured

Each kickstart file configures:

✅ **Static IP** - No DHCP, predictable addressing
✅ **LVM partitioning** - /boot + LVM (/, swap)
✅ **ansible user** - With passwordless sudo
✅ **SSH key auth** - Password auth disabled
✅ **Hostname** - Properly set (e.g., control.ansible.lab)
✅ **Firewall** - SSH enabled
✅ **SELinux** - Set to permissive (for lab)
✅ **Packages** - Minimal + vim, wget, curl, git, python3
✅ **/etc/hosts** - All lab nodes configured
✅ **Message of the day** - Shows node info on login

## Customizing Kickstart Files

### Add More Packages

Edit the `%packages` section:

```kickstart
%packages
@^minimal-environment
@standard
vim-enhanced
wget
curl
# Add your packages here:
httpd
mariadb-server
docker
%end
```

### Change Partitioning

Edit the disk layout section:

```kickstart
# Example: Add separate /var partition
part /boot --fstype="xfs" --ondisk=vda --size=1024
part pv.01 --fstype="lvmpv" --ondisk=vda --size=1 --grow
volgroup vg_main --pesize=4096 pv.01
logvol / --fstype="xfs" --size=8192 --name=lv_root --vgname=vg_main
logvol /var --fstype="xfs" --size=4096 --name=lv_var --vgname=vg_main
logvol swap --fstype="swap" --size=1024 --name=lv_swap --vgname=vg_main
```

### Run Custom Scripts

Add commands to the `%post` section:

```kickstart
%post --log=/root/ks-post.log

# Your custom commands
curl -o /tmp/setup.sh https://example.com/setup.sh
bash /tmp/setup.sh

# Install from pip
pip3 install ansible

# Configure something
echo "custom config" > /etc/myapp.conf

%end
```

### Change Timezone

```kickstart
timezone Europe/London --utc
```

### Enable Root Password

```kickstart
# Instead of:
rootpw --lock

# Use:
rootpw --plaintext YourPassword123
# Or encrypted:
rootpw --iscrypted $6$xyz...encrypted...hash
```

## Installation Process

1. **Boot from ISO** - VM boots from Rocky Linux ISO
2. **Load kickstart** - Kickstart file is injected and loaded
3. **Partitioning** - Automatic disk setup
4. **Package install** - Base system + selected packages
5. **Post-install** - Run %post scripts (create user, SSH keys, etc.)
6. **Poweroff** - VM shuts down
7. **Manual start** - You start the VM with `virsh start <vm-name>`

**Total time:** 10-15 minutes per VM

## Testing Installation

After VM powers off and you start it:

```bash
# Start VM
virsh start control

# Wait 30 seconds for boot
sleep 30

# Test SSH
ssh -i /root/.ssh/ansible-lab ansible@192.168.100.10

# Should work without password!
```

## Troubleshooting

### Installation Fails

```bash
# Watch installation console
virsh console control
# Press Ctrl+] to exit

# Check what went wrong in the console output
```

### Can't SSH After Install

1. Check VM is running: `virsh list`
2. Check you updated the SSH key in kickstart file
3. Verify IP: `virsh net-dhcp-leases ansible-lab`
4. Try from console: `virsh console control`
5. Check authorized_keys: `cat /home/ansible/.ssh/authorized_keys`

### Want to Reinstall

```bash
# Destroy VM completely
virsh destroy control
virsh undefine control --remove-all-storage

# Remove disk
rm -f /var/lib/libvirt/images/ansible-lab/control.qcow2

# Run installation again
bash scripts/install-vm-manual.sh control
```

## Validating Kickstart Files

Test syntax without installing:

```bash
# Install validation tool
dnf install -y pykickstart

# Validate kickstart file
ksvalidator kickstart/control.ks.cfg

# Should show no errors if valid
```

## Kickstart Command Reference

### Common Commands

```kickstart
text                    # Text mode install (no GUI)
firstboot --disable     # Don't run firstboot wizard
keyboard --xlayouts='us' # Keyboard layout
lang en_US.UTF-8        # System language
timezone UTC --utc      # Timezone

network --bootproto=static --ip=X.X.X.X --netmask=X.X.X.X --gateway=X.X.X.X

rootpw --lock           # Lock root account
authselect select minimal # Auth configuration

selinux --permissive    # SELinux mode
firewall --enabled --service=ssh # Firewall

clearpart --all --initlabel # Clear all partitions
zerombr                 # Initialize disk

bootloader --location=mbr # Where to install bootloader

poweroff               # Poweroff after install
# Or: reboot, halt, shutdown

skipx                  # Don't configure X
```

### Partitioning

```kickstart
# Simple partitioning
part /boot --fstype=xfs --size=1024
part swap --fstype=swap --size=2048
part / --fstype=xfs --size=1 --grow

# LVM partitioning
part /boot --fstype=xfs --size=1024
part pv.01 --size=1 --grow
volgroup vg_main pv.01
logvol / --vgname=vg_main --name=lv_root --fstype=xfs --size=10240
logvol swap --vgname=vg_main --name=lv_swap --fstype=swap --size=2048
```

### Package Selection

```kickstart
%packages
@^environment-group    # Environment group
@package-group         # Package group
package-name           # Individual package
-unwanted-package      # Exclude package
%end
```

## Tips

1. **Always validate** kickstart files before using
2. **Test one VM first** before doing all 5
3. **Keep backups** of working kickstart files
4. **Document changes** you make
5. **Use comments** in kickstart files (# comment)

## Next Steps

After installation:

1. Verify all VMs: `virsh list --all`
2. Test SSH to each: `ssh -i /root/.ssh/ansible-lab ansible@192.168.100.XX`
3. Configure Ansible: `cd /home/user/RHCE-prep/ansible`
4. Test Ansible: `ansible all -m ping`
5. Run playbooks: `ansible-playbook playbooks/ping-test.yml`

## Resources

- [Kickstart Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/kickstart-commands-and-options-reference_installing-rhel-as-an-experienced-user)
- [Anaconda Kickstart](https://pykickstart.readthedocs.io/)
- [RHEL Installation Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/)

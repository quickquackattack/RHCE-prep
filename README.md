# Ansible Lab Environment with Libvirt

A complete 5-VM lab environment for practicing Ansible automation, built on libvirt/KVM using CentOS Stream 9 cloud images.

## Lab Architecture

The lab consists of 5 virtual machines on an isolated network:

| Hostname | IP Address      | Role         | Memory | vCPUs | Description                    |
|----------|----------------|--------------|--------|-------|--------------------------------|
| control  | 192.168.100.10 | Control Node | 2GB    | 2     | Ansible control node           |
| node1    | 192.168.100.11 | Web Server   | 1GB    | 1     | Web server (httpd)             |
| node2    | 192.168.100.12 | Web Server   | 1GB    | 1     | Web server (httpd)             |
| node3    | 192.168.100.13 | DB Server    | 1GB    | 1     | Database server (MariaDB)      |
| node4    | 192.168.100.14 | App Server   | 1GB    | 1     | Application server             |

**Network:** ansible-lab (192.168.100.0/24) - NAT mode

## Prerequisites

### System Requirements
- Linux host with KVM/libvirt support
- Minimum 6GB RAM available for VMs
- 50GB free disk space
- CPU with virtualization support (Intel VT-x or AMD-V)

### Required Software
```bash
# For RHEL/CentOS/Rocky/Alma
sudo dnf install -y libvirt qemu-kvm virt-install virt-manager \
                    genisoimage wget curl

# For Ubuntu/Debian
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients \
                    virtinst virt-manager genisoimage wget curl

# Start and enable libvirt
sudo systemctl enable --now libvirtd
```

### Verify Virtualization Support
```bash
# Check CPU virtualization support
egrep -c '(vmx|svm)' /proc/cpuinfo  # Should return > 0

# Check KVM module is loaded
lsmod | grep kvm

# Verify libvirt is running
sudo systemctl status libvirtd
```

## Quick Start

### 1. Setup the Lab

```bash
# Clone this repository
git clone <repository-url>
cd RHCE-prep

# Run the setup script (requires root)
sudo bash scripts/setup-lab.sh
```

The setup script will:
- Generate SSH keys for lab access
- Download CentOS Stream 9 cloud image
- Create a dedicated libvirt network
- Create and start 5 VMs with cloud-init
- Configure static DHCP reservations

**Note:** Initial setup takes 5-10 minutes depending on download speed and disk I/O.

### 2. Verify Lab Status

```bash
# Check VM status
sudo virsh list --all

# Check network status
sudo virsh net-list --all
sudo virsh net-dhcp-leases ansible-lab
```

### 3. Test SSH Access

```bash
# Wait for cloud-init to complete (1-2 minutes after VMs start)
ssh -i ~/.ssh/ansible-lab ansible@192.168.100.10

# Or add to ~/.ssh/config for easier access
cat >> ~/.ssh/config << EOF
Host ansible-lab-*
  User ansible
  IdentityFile ~/.ssh/ansible-lab
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null

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

# Now you can use:
ssh ansible-lab-control
```

### 4. Run Your First Ansible Command

```bash
cd ansible

# Test connectivity
ansible all -m ping

# Gather facts
ansible all -m setup

# Run ad-hoc command
ansible nodes -m shell -a "uptime"
```

## Using the Lab

### Directory Structure

```
RHCE-prep/
├── README.md                    # This file
├── libvirt/
│   └── network.xml             # Libvirt network definition
├── scripts/
│   ├── setup-lab.sh            # Lab creation script
│   └── destroy-lab.sh          # Lab cleanup script
└── ansible/
    ├── ansible.cfg             # Ansible configuration
    ├── inventory.ini           # Lab inventory file
    └── playbooks/              # Sample playbooks
        ├── ping-test.yml
        ├── gather-facts.yml
        ├── install-packages.yml
        ├── user-management.yml
        └── deploy-web-app.yml
```

### Running Sample Playbooks

```bash
cd ansible

# Test connectivity
ansible-playbook playbooks/ping-test.yml

# Gather and display facts
ansible-playbook playbooks/gather-facts.yml

# Install packages and configure services
ansible-playbook playbooks/install-packages.yml

# Create users
ansible-playbook playbooks/user-management.yml

# Deploy web application
ansible-playbook playbooks/deploy-web-app.yml

# Test web servers
curl http://192.168.100.11
curl http://192.168.100.12
```

### Working with Inventory

The inventory file groups hosts logically:

```ini
[control]     # Ansible control node
[web]         # Web servers (node1, node2)
[db]          # Database servers (node3)
[app]         # Application servers (node4)
[nodes]       # All managed nodes (excludes control)
[lab]         # All hosts (control + nodes)
```

Target specific groups:
```bash
# Only web servers
ansible web -m ping

# Only database server
ansible db -m shell -a "systemctl status mariadb"

# All nodes except control
ansible nodes -m uptime
```

## Common Tasks

### Start/Stop VMs

```bash
# Stop all VMs
for vm in control node1 node2 node3 node4; do
    sudo virsh shutdown $vm
done

# Start all VMs
for vm in control node1 node2 node3 node4; do
    sudo virsh start $vm
done

# Restart a specific VM
sudo virsh reboot node1

# Force shutdown
sudo virsh destroy node1
```

### Access VM Console

```bash
# Connect to VM console (Ctrl+] to exit)
sudo virsh console control

# View VM info
sudo virsh dominfo control
```

### Snapshot Management

```bash
# Create snapshot before making changes
sudo virsh snapshot-create-as node1 clean-state "Clean state before testing"

# List snapshots
sudo virsh snapshot-list node1

# Restore to snapshot
sudo virsh snapshot-revert node1 clean-state

# Delete snapshot
sudo virsh snapshot-delete node1 clean-state
```

### Network Management

```bash
# View network details
sudo virsh net-info ansible-lab

# View DHCP leases
sudo virsh net-dhcp-leases ansible-lab

# Stop/start network
sudo virsh net-destroy ansible-lab
sudo virsh net-start ansible-lab
```

## Practice Scenarios

### Scenario 1: Basic System Administration

```bash
# Update all systems
ansible nodes -b -m dnf -a "name=* state=latest"

# Install package on all nodes
ansible nodes -b -m dnf -a "name=vim state=present"

# Restart a service
ansible web -b -m systemd -a "name=httpd state=restarted"

# Copy file to all nodes
ansible nodes -m copy -a "src=/local/file dest=/tmp/file"
```

### Scenario 2: Web Server Configuration

```bash
# Deploy web application
ansible-playbook playbooks/deploy-web-app.yml

# Verify deployment
ansible web -m uri -a "url=http://localhost return_content=yes"

# Check service status
ansible web -b -m systemd -a "name=httpd state=started enabled=yes"
```

### Scenario 3: User Management

```bash
# Create users across all nodes
ansible-playbook playbooks/user-management.yml

# Verify users
ansible nodes -m shell -a "getent passwd developer"

# Set password for user
ansible nodes -b -m user -a "name=developer password={{ 'P@ssw0rd' | password_hash('sha512') }}"
```

### Scenario 4: Security Hardening

```bash
# Disable root login
ansible nodes -b -m lineinfile -a "path=/etc/ssh/sshd_config regexp='^PermitRootLogin' line='PermitRootLogin no'"

# Configure firewall
ansible nodes -b -m ansible.posix.firewalld -a "service=ssh permanent=yes state=enabled"

# Install security updates
ansible nodes -b -m dnf -a "name=* state=latest security=yes"
```

## Troubleshooting

### VMs Won't Start

```bash
# Check libvirt logs
sudo journalctl -u libvirtd -n 50

# Verify network is running
sudo virsh net-list --all

# Check disk space
df -h /var/lib/libvirt/images
```

### Can't SSH to VMs

```bash
# Verify VM is running
sudo virsh list --all

# Check cloud-init status (from console)
sudo virsh console control
# Then: sudo cloud-init status

# Verify network connectivity
sudo virsh net-dhcp-leases ansible-lab

# Check SSH service
ansible all -m shell -a "systemctl status sshd" --ssh-extra-args="-o ConnectTimeout=5"
```

### Ansible Connection Issues

```bash
# Test SSH manually
ssh -vvv -i ~/.ssh/ansible-lab ansible@192.168.100.10

# Verify SSH key permissions
ls -la ~/.ssh/ansible-lab*
chmod 600 ~/.ssh/ansible-lab

# Check Ansible inventory
ansible-inventory --list

# Use verbose mode
ansible all -m ping -vvv
```

### Performance Issues

```bash
# Check host resources
free -h
top

# Reduce VM memory if needed (after shutdown)
sudo virsh setmaxmem node1 512M --config
sudo virsh setmem node1 512M --config

# Check disk I/O
iostat -x 1
```

## Lab Cleanup

### Temporary Shutdown

```bash
# Stop all VMs (preserves VMs for later use)
for vm in control node1 node2 node3 node4; do
    sudo virsh shutdown $vm
done
```

### Complete Cleanup

```bash
# Destroy entire lab (removes all VMs and network)
sudo bash scripts/destroy-lab.sh

# This will:
# - Destroy and undefine all VMs
# - Remove all VM disks
# - Destroy the ansible-lab network
# - Clean up images directory

# Note: SSH keys in ~/.ssh/ansible-lab* are preserved
```

### Remove SSH Keys

```bash
rm -f ~/.ssh/ansible-lab ~/.ssh/ansible-lab.pub
```

## Advanced Topics

### Customizing VMs

Edit `scripts/setup-lab.sh` to modify:
- VM resources (memory, vCPUs)
- IP addresses
- Installed packages
- Cloud-init configuration

### Using Different OS Images

```bash
# Ubuntu 22.04
BASE_IMAGE_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"

# Rocky Linux 9
BASE_IMAGE_URL="https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"

# Alma Linux 9
BASE_IMAGE_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
```

### Adding More VMs

1. Edit `libvirt/network.xml` - add DHCP reservation
2. Edit `scripts/setup-lab.sh` - add to VMS array
3. Edit `ansible/inventory.ini` - add to inventory
4. Re-run setup script

### Ansible Vault Practice

```bash
# Create encrypted file
ansible-vault create secrets.yml

# Edit encrypted file
ansible-vault edit secrets.yml

# Run playbook with vault
ansible-playbook playbook.yml --ask-vault-pass
```

### Ansible Roles

```bash
# Create role structure
cd ansible
mkdir -p roles/webserver/{tasks,handlers,templates,files,vars,defaults}

# Generate role
ansible-galaxy init roles/webserver
```

## RHCE Practice Tips

This lab is ideal for practicing RHCE (EX294) objectives:

1. **Core Skills**
   - Install and configure Ansible
   - Create and run playbooks
   - Use variables and facts
   - Work with templates (Jinja2)
   - Manage task control (loops, conditionals)

2. **Task Automation**
   - System configuration
   - Package management
   - Service management
   - User and group management
   - Scheduled tasks

3. **Advanced Features**
   - Ansible Vault for secrets
   - Role creation and usage
   - Dynamic inventories
   - Ansible Galaxy
   - Error handling

4. **Troubleshooting**
   - Debug playbooks
   - Use check mode
   - Verbose output
   - Syntax checking

## Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [RHCE Exam Objectives](https://www.redhat.com/en/services/training/ex294-red-hat-certified-engineer-rhce-exam-red-hat-enterprise-linux-9)
- [Ansible Galaxy](https://galaxy.ansible.com/)
- [Libvirt Documentation](https://libvirt.org/docs.html)

## License

This lab environment is provided as-is for educational purposes.

## Contributing

Feel free to submit issues and enhancement requests!

# Quick Start Guide

Get your Ansible lab running in 5 minutes!

## Prerequisites Check

```bash
sudo bash scripts/check-prerequisites.sh
```

If you see errors, install the required packages:

**RHEL/CentOS/Rocky/Alma:**
```bash
sudo dnf install -y libvirt qemu-kvm virt-install genisoimage wget
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
```

**Ubuntu/Debian:**
```bash
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients \
                    virtinst genisoimage wget
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
```

## Setup Lab (One Command)

```bash
sudo bash scripts/setup-lab.sh
```

This will:
- Download CentOS Stream 9 cloud image (~750MB)
- Create 5 VMs with 6GB total RAM
- Setup isolated network (192.168.100.0/24)
- Configure SSH access
- Takes ~5-10 minutes

## Verify Setup

```bash
# Check VMs are running
sudo virsh list

# Test SSH (wait 1-2 min for cloud-init)
ssh -i ~/.ssh/ansible-lab ansible@192.168.100.10

# Test Ansible
cd ansible
ansible all -m ping
```

## Run Your First Playbook

```bash
cd ansible

# Test connectivity
ansible-playbook playbooks/ping-test.yml

# Deploy a web app
ansible-playbook playbooks/deploy-web-app.yml

# Verify
curl http://192.168.100.11
```

## Common Commands

```bash
# List VMs
sudo virsh list --all

# Start/Stop VM
sudo virsh start node1
sudo virsh shutdown node1

# Check network
sudo virsh net-dhcp-leases ansible-lab

# Ansible ad-hoc
ansible all -m shell -a "uptime"
ansible web -b -m systemd -a "name=httpd state=started"
```

## Cleanup

```bash
# Destroy everything
sudo bash scripts/destroy-lab.sh
```

## Troubleshooting

**VMs won't start:**
```bash
sudo systemctl status libvirtd
sudo virsh net-list --all
```

**Can't SSH:**
```bash
# Wait for cloud-init (can take 2-3 minutes)
sudo virsh console control
# Check: sudo cloud-init status
```

**Ansible can't connect:**
```bash
# Test SSH manually
ssh -vvv -i ~/.ssh/ansible-lab ansible@192.168.100.10

# Check key permissions
chmod 600 ~/.ssh/ansible-lab
```

## Next Steps

See [README.md](README.md) for:
- Complete documentation
- Sample playbooks
- Practice scenarios
- RHCE exam tips
- Advanced usage

## Lab Layout

```
Control: 192.168.100.10 (2GB RAM) - Ansible control node
Node1:   192.168.100.11 (1GB RAM) - Web server
Node2:   192.168.100.12 (1GB RAM) - Web server
Node3:   192.168.100.13 (1GB RAM) - Database server
Node4:   192.168.100.14 (1GB RAM) - App server
```

## SSH Config (Optional)

Add to `~/.ssh/config`:
```
Host ansible-lab-*
  User ansible
  IdentityFile ~/.ssh/ansible-lab
  StrictHostKeyChecking no

Host ansible-lab-control
  HostName 192.168.100.10
```

Then use: `ssh ansible-lab-control`

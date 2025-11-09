# SSH Access Troubleshooting Guide

## Quick Diagnosis

If you're getting "Permission denied" when trying to SSH to VMs, run these diagnostic scripts:

```bash
# Quick automated troubleshooting
sudo bash scripts/troubleshoot-ssh.sh <vm-name>

# Or try automatic fixes first
sudo bash scripts/fix-ssh-access.sh <vm-name>
```

## Common Issues and Solutions

### Issue 1: Cloud-init Still Running

**Symptom:** Permission denied immediately after VM creation

**Cause:** Cloud-init hasn't finished configuring SSH access yet

**Solution:**
```bash
# Wait 2-3 minutes, then check cloud-init status
sudo virsh console <vm-name>
# Press Enter to get login prompt
# Login with any method available, then run:
sudo cloud-init status

# Expected output: "status: done"
# If still running, wait and check again
```

### Issue 2: Wrong SSH Key

**Symptom:** "Permission denied (publickey)"

**Cause:** Using wrong SSH key or key not found

**Solution:**
```bash
# Find the correct SSH key
# For ansible-lab VMs:
ls -la ~/.ssh/ansible-lab*

# For Jira-provisioned VMs:
ls -la /var/lib/jira-provisioner/ssh-keys/

# Fix permissions if needed
chmod 600 ~/.ssh/ansible-lab
# or
chmod 600 /var/lib/jira-provisioner/ssh-keys/<vm-name>

# Try with explicit key path
ssh -i ~/.ssh/ansible-lab ansible@<ip-address>
```

### Issue 3: Wrong Username

**Symptom:** "Permission denied" with correct key

**Cause:** Using wrong SSH username

**Solution - Try these users in order:**
```bash
# For ansible-lab VMs (original setup)
ssh -i ~/.ssh/ansible-lab ansible@<ip-address>

# For Jira-provisioned VMs
ssh -i /var/lib/jira-provisioner/ssh-keys/<vm-name> sectest@<ip-address>

# For generic CentOS cloud images
ssh -i <key> centos@<ip-address>
ssh -i <key> cloud-user@<ip-address>

# Other common defaults
ssh -i <key> admin@<ip-address>
```

### Issue 4: VM Not Ready

**Symptom:** Connection timeout or "Connection refused"

**Cause:** VM still booting or networking not configured

**Solution:**
```bash
# Check VM is running
sudo virsh list --all

# If shut off, start it
sudo virsh start <vm-name>

# Wait 60 seconds for boot
sleep 60

# Check if VM has IP address
sudo virsh net-dhcp-leases default
sudo virsh net-dhcp-leases ansible-lab

# Try pinging the VM
ping -c 3 <ip-address>
```

### Issue 5: SSH Key Permissions

**Symptom:** "Permissions 0644 for key are too open"

**Cause:** SSH key has wrong permissions

**Solution:**
```bash
# Fix SSH key permissions
chmod 600 ~/.ssh/ansible-lab
chmod 600 /var/lib/jira-provisioner/ssh-keys/*

# Check permissions
ls -la ~/.ssh/ansible-lab
# Should show: -rw------- (600)
```

### Issue 6: Can't Find IP Address

**Symptom:** Don't know what IP to connect to

**Solution:**
```bash
# Method 1: Check DHCP leases
sudo virsh net-dhcp-leases default
sudo virsh net-dhcp-leases ansible-lab

# Method 2: Check VM network interfaces
sudo virsh domifaddr <vm-name>

# Method 3: From VM console
sudo virsh console <vm-name>
# Then inside VM:
ip addr show

# Method 4: Check the lab status script
bash scripts/lab-status.sh
```

### Issue 7: SSH Host Key Changed

**Symptom:** "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!"

**Cause:** VM was recreated with same IP but different host key

**Solution:**
```bash
# Remove old host key
ssh-keygen -R <ip-address>

# Or connect with option to ignore host key checking
ssh -i <key> -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@<ip-address>
```

## Step-by-Step Troubleshooting

### Step 1: Verify VM is Running

```bash
sudo virsh list --all

# Look for your VM name
# State should be "running"

# If not running:
sudo virsh start <vm-name>
```

### Step 2: Get IP Address

```bash
# Check DHCP leases
sudo virsh net-dhcp-leases default

# Or try
sudo virsh domifaddr <vm-name>

# Make note of the IP address
```

### Step 3: Find SSH Key

```bash
# For original ansible-lab
KEY_PATH=~/.ssh/ansible-lab

# For Jira VMs
KEY_PATH=/var/lib/jira-provisioner/ssh-keys/<vm-name>

# Check key exists
ls -la $KEY_PATH

# Fix permissions
chmod 600 $KEY_PATH
```

### Step 4: Test Connection with Verbose Output

```bash
# Try with verbose SSH
ssh -vvv -i $KEY_PATH ansible@<ip-address>

# Look for these in output:
# - "debug1: Offering public key" (key is being tried)
# - "debug1: Authentication succeeded" (success)
# - "Permission denied (publickey)" (key rejected)
```

### Step 5: Check Cloud-Init Status

If still failing, check cloud-init:

```bash
# Access VM console
sudo virsh console <vm-name>

# Press Enter to get prompt
# You may need to reboot from console if stuck

# Check cloud-init
sudo cloud-init status --long

# If failed, check logs
sudo cat /var/log/cloud-init.log | tail -50
```

### Step 6: Verify SSH Service

From VM console:

```bash
# Check SSH is running
sudo systemctl status sshd

# If not running
sudo systemctl start sshd

# Check SSH listening
sudo ss -tlnp | grep :22
```

### Step 7: Check Authorized Keys

From VM console:

```bash
# Check if SSH key was injected
sudo cat /home/ansible/.ssh/authorized_keys
sudo cat /home/sectest/.ssh/authorized_keys

# Should contain your public key
# If empty, cloud-init didn't inject the key
```

## Quick Fix Commands

### Restart Everything

```bash
# Restart the VM
sudo virsh reboot <vm-name>

# Wait for boot
sleep 60

# Try SSH again
ssh -i ~/.ssh/ansible-lab ansible@<ip-address>
```

### Recreate VM (Last Resort)

```bash
# Destroy and recreate (WARNING: loses all data)
sudo virsh destroy <vm-name>
sudo virsh undefine <vm-name> --remove-all-storage

# Then re-run setup script
sudo bash scripts/setup-lab.sh
```

## Testing SSH Access Manually

### Test with Different Users

```bash
#!/bin/bash
KEY="/path/to/key"
IP="192.168.100.10"

for user in ansible sectest centos cloud-user admin; do
    echo "Trying user: $user"
    timeout 5 ssh -i $KEY -o ConnectTimeout=3 -o StrictHostKeyChecking=no $user@$IP "echo SUCCESS" 2>&1
done
```

### Test Network Path

```bash
# Can you ping?
ping -c 3 <ip-address>

# Can you reach SSH port?
telnet <ip-address> 22
# or
nc -zv <ip-address> 22

# Check route
ip route get <ip-address>
```

## Automated Fix Script

Use the provided fix script:

```bash
# Run automated fixes
sudo bash scripts/fix-ssh-access.sh <vm-name>

# Then run diagnostics
sudo bash scripts/troubleshoot-ssh.sh <vm-name>
```

## Debug Mode

### Enable SSH Debug in VM

From VM console:

```bash
# Stop SSH
sudo systemctl stop sshd

# Run SSH in debug mode
sudo /usr/sbin/sshd -d

# Try to connect from host
# Watch the debug output on console
```

### Detailed Client Debug

```bash
# Maximum verbosity
ssh -vvv -i <key> -o StrictHostKeyChecking=no ansible@<ip-address> 2>&1 | tee ssh-debug.log

# Check the log for clues
grep -i "permission\|denied\|failed\|error" ssh-debug.log
```

## For Jira-Provisioned VMs

If you provisioned via Jira, check the ticket:

1. Jira ticket should have comment with:
   - Exact SSH command
   - IP address
   - SSH key path
   - Username

2. Copy the exact command from Jira:
```bash
# Command will look like:
ssh -i /var/lib/jira-provisioner/ssh-keys/vm-name sectest@192.168.X.X
```

3. If that fails, check provisioning logs:
```bash
sudo tail -100 /var/log/jira-provisioner/provisioner.log
```

## Common Scenarios

### Scenario 1: Just Created VM

**Wait:** 2-3 minutes for cloud-init
**Check:** `sudo virsh console <vm-name>` then `sudo cloud-init status`
**Try:** `ssh -i ~/.ssh/ansible-lab ansible@<ip>`

### Scenario 2: VM Was Working, Now Broken

**Check:** VM is still running: `sudo virsh list`
**Check:** IP didn't change: `sudo virsh net-dhcp-leases default`
**Fix:** May need to remove old host key: `ssh-keygen -R <ip>`

### Scenario 3: Can Ping but Not SSH

**Check:** SSH is running in VM
**Check:** Firewall: `sudo firewall-cmd --list-all` (from console)
**Check:** SELinux: `sudo getenforce` (from console)

### Scenario 4: Permission Denied with Correct Key

**Check:** Using correct username (ansible vs sectest vs centos)
**Check:** Key permissions: `ls -la <key>` should be 600
**Check:** Authorized_keys in VM has your public key

## Getting Help

If still stuck:

1. Run diagnostic script and save output:
```bash
sudo bash scripts/troubleshoot-ssh.sh <vm-name> 2>&1 | tee diagnosis.log
```

2. Collect info:
   - VM name
   - IP address (from `sudo virsh net-dhcp-leases default`)
   - SSH command you're trying
   - Output of `ssh -vvv` command
   - Cloud-init status (from console)

3. Check logs:
   - `/var/log/jira-provisioner/provisioner.log` (if Jira VM)
   - VM console output
   - `sudo journalctl -u libvirtd`

## Prevention

### Set Up SSH Config

Add to `~/.ssh/config`:

```
Host ansible-lab-*
  User ansible
  IdentityFile ~/.ssh/ansible-lab
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host ansible-lab-control
  HostName 192.168.100.10

Host ansible-lab-node1
  HostName 192.168.100.11
```

Then simply use:
```bash
ssh ansible-lab-control
```

### Verify After Creation

After creating VMs, immediately verify:

```bash
# Check VM running
sudo virsh list

# Check has IP
sudo virsh net-dhcp-leases default

# Wait for cloud-init
sleep 120

# Test SSH
ssh -i ~/.ssh/ansible-lab ansible@192.168.100.10 "echo OK"
```

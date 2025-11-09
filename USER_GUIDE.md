# VM Provisioning User Guide

How to request automated VMs for security engineering testing via Jira.

## Quick Start

1. Create a Jira ticket in the SECVM project
2. Fill in VM requirements in the description
3. Add label: `vm-provisioning-request`
4. Submit ticket
5. Wait ~5-10 minutes for automated provisioning
6. Get VM access details from ticket comments

## Creating a VM Request

### Step 1: Create Jira Ticket

Go to your Jira instance and create a new issue in the **SECVM** project (or your configured project).

### Step 2: Fill in Ticket Details

**Summary:** Describe your testing purpose
```
Example: "Penetration Testing Lab - Web Application Testing"
```

**Description:** Specify VM requirements using this format:

```
VM Name: pentest-lab-001
CPU Cores: 4
RAM (MB): 8192
Disk Size (GB): 60
Software List:
- nmap
- metasploit
- burpsuite
- wireshark
- docker
- python3
Network Isolated: yes
Auto Destroy (hours): 24
```

**Labels:** Add `vm-provisioning-request`

### Step 3: Submit and Wait

- Submit the ticket
- Automated provisioning starts immediately
- Check ticket comments for progress updates
- Typically takes 5-10 minutes depending on software list

### Step 4: Get VM Access

Once provisioning completes, the ticket will be updated with:

- VM IP address
- SSH connection command
- SSH key location
- Software installation status

Example comment:
```
VM Information
==============
VM Name: pentest-lab-001
IP Address: 192.168.200.45
SSH Command: ssh -i /var/lib/jira-provisioner/ssh-keys/pentest-lab-001 sectest@192.168.200.45
SSH User: sectest
CPU Cores: 4
RAM (MB): 8192
Disk (GB): 60
Software Installed: nmap, metasploit, burpsuite, wireshark, docker, python3
Network Isolated: Yes
Auto Destroy: 24 hours
```

## VM Specifications

### Required Fields

| Field | Description | Example |
|-------|-------------|---------|
| VM Name | Unique identifier for your VM | `webapp-test-001` |
| CPU Cores | Number of CPU cores (1-8) | `4` |
| RAM (MB) | Memory in MB (512-16384) | `8192` |
| Disk Size (GB) | Disk space in GB (10-100) | `40` |

### Optional Fields

| Field | Description | Default | Example |
|-------|-------------|---------|---------|
| Software List | Tools/packages to install | None | See [Available Software](#available-software) |
| Network Isolated | Dedicated isolated network | `no` | `yes` or `no` |
| Auto Destroy (hours) | Auto-cleanup time (1-168) | `24` | `48` |

## Available Software

### Security Scanning Tools

- **nmap** - Network mapper and port scanner
- **masscan** - Fast network scanner
- **nikto** - Web server scanner

### Exploitation Frameworks

- **metasploit** / **metasploit-framework** - Penetration testing framework
- **sqlmap** - SQL injection tool
- **burpsuite** - Web application security testing

### Network Analysis

- **wireshark** - Network protocol analyzer
- **tcpdump** - Packet analyzer
- **netcat** - Network utility

### Forensics & Analysis

- **volatility** - Memory forensics
- **autopsy** - Digital forensics platform

### Container Platforms

- **docker** - Container platform
- **podman** - Daemonless container engine
- **kubernetes** - Container orchestration

### Development Tools

- **python3** - Python 3 interpreter
- **python3-pip** - Python package manager
- **golang** - Go programming language
- **nodejs** - Node.js runtime

### Database Systems

- **postgresql** - PostgreSQL database
- **mysql** - MySQL database
- **mariadb** - MariaDB database
- **redis** - Redis key-value store

### Web Servers

- **apache** / **httpd** - Apache web server
- **nginx** - Nginx web server

### Password Cracking

- **john** - John the Ripper
- **hashcat** - Advanced password recovery
- **aircrack-ng** - WiFi security auditing

## Usage Examples

### Example 1: Web Application Penetration Testing

```
Summary: Web Application Pentesting Environment

Description:
VM Name: webapp-pentest-001
CPU Cores: 4
RAM (MB): 8192
Disk Size (GB): 40
Software List:
- burpsuite
- sqlmap
- nmap
- nikto
- python3
- nodejs
Network Isolated: yes
Auto Destroy (hours): 48

Labels: vm-provisioning-request
```

**Use Case:** Testing web applications with common pentesting tools in an isolated environment.

### Example 2: Metasploit Training Lab

```
Summary: Metasploit Training Environment

Description:
VM Name: msf-training-001
CPU Cores: 4
RAM (MB): 8192
Disk Size (GB): 60
Software List:
- metasploit-framework
- nmap
- netcat
- wireshark
- postgresql
Network Isolated: no
Auto Destroy (hours): 72

Labels: vm-provisioning-request
```

**Use Case:** Learning Metasploit framework with supporting tools.

### Example 3: Container Security Testing

```
Summary: Docker Security Analysis Lab

Description:
VM Name: docker-security-001
CPU Cores: 4
RAM (MB): 8192
Disk Size (GB): 50
Software List:
- docker
- nmap
- python3
- golang
Network Isolated: yes
Auto Destroy (hours): 24

Labels: vm-provisioning-request
```

**Use Case:** Testing container security and building security tools.

### Example 4: Network Forensics

```
Summary: Network Forensics Analysis

Description:
VM Name: net-forensics-001
CPU Cores: 2
RAM (MB): 4096
Disk Size (GB): 40
Software List:
- wireshark
- tcpdump
- volatility
- python3
Network Isolated: no
Auto Destroy (hours): 168

Labels: vm-provisioning-request
```

**Use Case:** Network traffic analysis and memory forensics (1 week retention).

### Example 5: Minimal Testing VM

```
Summary: Basic Security Testing VM

Description:
VM Name: basic-test-001
CPU Cores: 2
RAM (MB): 2048
Disk Size (GB): 20
Software List:
- nmap
- python3
Network Isolated: no
Auto Destroy (hours): 8

Labels: vm-provisioning-request
```

**Use Case:** Quick, lightweight VM for basic testing.

## Best Practices

### Naming Conventions

Use descriptive, unique names:
- Include purpose: `webapp-test`, `api-security`, `forensics-lab`
- Add identifier: `-001`, `-002` for multiple VMs
- Use hyphens, not spaces: `my-test-vm` ✓, `my test vm` ✗
- Keep it short: Max 50 characters

### Resource Selection

**Choose appropriate resources:**

| Use Case | CPU | RAM | Disk |
|----------|-----|-----|------|
| Basic testing | 2 | 2048 | 20 |
| Web pentesting | 4 | 4096-8192 | 40 |
| Metasploit/Heavy tools | 4-8 | 8192-16384 | 60-100 |
| Container platforms | 4 | 8192 | 50 |
| Quick scans | 2 | 2048 | 20 |

**Don't request more than you need** - it impacts other users.

### Network Isolation

**Use isolated networks when:**
- Testing potentially dangerous exploits
- Running untrusted code
- Need complete network separation
- Simulating attacker scenarios

**Use shared network when:**
- Need internet access
- Testing against external targets
- Simple tool testing

### Auto-Destroy Time

**Recommended durations:**
- Quick tests: 2-8 hours
- Daily work: 24 hours
- Project work: 48-72 hours
- Long-term research: 168 hours (1 week max)

**Always clean up when done:**
- Comment on ticket when finished
- VMs are automatically destroyed at specified time
- Don't hoard VMs - request new ones as needed

## Accessing Your VM

### SSH Access

Use the SSH command from the Jira comment:

```bash
ssh -i /var/lib/jira-provisioner/ssh-keys/<vm-name> sectest@<ip-address>
```

**Note:** SSH keys are on the provisioner server, not your local machine.

### From Provisioner Server

```bash
# SSH into provisioner server first
ssh provisioner-server

# Then access your VM
ssh -i /var/lib/jira-provisioner/ssh-keys/your-vm-name sectest@ip-address
```

### Password-less Sudo

The `sectest` user has password-less sudo:

```bash
# Install additional software
sudo dnf install some-package

# Run commands as root
sudo tcpdump -i eth0
```

## Checking VM Status

### Via Jira

Monitor your ticket for updates:
- **Validating** - Checking your requirements
- **Provisioning** - Creating the VM
- **Installing Software** - Installing requested tools
- **Ready** - VM is ready to use
- **Failed** - Something went wrong (check error message)

### Via CLI (on provisioner server)

```bash
# List all VMs
sudo virsh list

# Get VM details
sudo virsh dominfo your-vm-name

# Check VM console
sudo virsh console your-vm-name

# Get IP address
sudo virsh net-dhcp-leases default
```

## Troubleshooting

### VM Not Created

**Check ticket comments** for error messages:
- Validation errors (check your specs)
- Resource limits exceeded
- VM name already exists

### Can't SSH to VM

**Wait a few minutes** - cloud-init takes time to configure SSH.

If still failing:
1. Check ticket for correct IP and SSH command
2. Verify you're on the provisioner server
3. Check VM is running: `sudo virsh list`
4. Contact admin if issue persists

### Software Not Installed

**Check ticket comments** for installation status.

If software failed to install:
- You can install manually: `sudo dnf install package-name`
- Some tools (like Metasploit) may take extra time
- Check if package name was correct

### Need Different Software

**After VM is provisioned:**
```bash
# SSH into VM
ssh -i <key> sectest@<ip>

# Install additional software
sudo dnf install package-name

# Or use pip
pip3 install python-package
```

## Resource Limits

**Maximum allowable resources:**
- CPU Cores: 8
- RAM: 16384 MB (16 GB)
- Disk: 100 GB
- VMs per user: 5 concurrent
- Auto-destroy max: 168 hours (1 week)

Requests exceeding limits will be rejected automatically.

## Tips & Tricks

### Save Time on Repeat Requests

Create ticket templates in Jira for common configurations.

### Share VM Access

Provide the SSH key and IP to teammates (coordinate via ticket comments).

### Extend VM Lifetime

Comment on ticket before auto-destroy time if you need more time.

### Document Your Work

Use ticket comments to document:
- What you're testing
- Findings and results
- Issues encountered
- When you're done with the VM

### Clean Up

Always indicate when VM can be destroyed:
```
Comment: "Testing complete, VM can be destroyed"
```

## Support

### Getting Help

1. **Check ticket comments** - Errors are reported there
2. **Check this guide** - Common issues covered above
3. **Contact admin** - If VM failed or other issues
4. **Check Jira labels** - Look for `vm-failed` or `vm-ready`

### Reporting Issues

When reporting issues, include:
- Jira ticket number
- VM name
- What you were trying to do
- Error messages (from ticket or SSH)
- Expected vs actual behavior

## FAQ

**Q: How long does provisioning take?**
A: Typically 5-10 minutes. More software = longer time.

**Q: Can I have multiple VMs?**
A: Yes, up to 5 concurrent VMs per user.

**Q: Can I modify the VM after creation?**
A: Yes! Install additional software, configure as needed.

**Q: What if I need software not in the list?**
A: Install it manually via SSH, or request it be added to the system.

**Q: Can I snapshot my VM?**
A: Contact admin for snapshot functionality.

**Q: What happens to my data when VM is destroyed?**
A: Everything is deleted. Save important data externally.

**Q: Can I extend auto-destroy time?**
A: Comment on the ticket requesting extension (max 1 week total).

**Q: Is internet access available?**
A: Yes, unless you choose network isolation.

**Q: Can I access VMs from my laptop?**
A: Not directly. SSH into provisioner server first, then to your VM.

**Q: What OS do VMs run?**
A: CentOS Stream 9 (cloud image) by default.

**Q: Can I run Windows VMs?**
A: Currently only Linux. Contact admin for Windows support.

## Example Workflow

1. **Morning:** Create ticket for webapp pentesting (4 CPU, 8GB RAM, burpsuite + tools)
2. **10 minutes later:** Get SSH details from ticket comment
3. **SSH in:** Access VM and start testing
4. **During day:** Use tools, document findings in ticket
5. **Evening:** Save results externally
6. **Comment:** "Testing complete, VM can be destroyed"
7. **Auto-destroy:** VM cleaned up after 24 hours

## Security Reminders

- Don't share SSH keys outside your team
- Be careful with isolated networks (you're responsible for security)
- Don't store sensitive data on VMs (they're temporary)
- Follow company security policies
- Report any security issues immediately

---

**Happy Testing! 🔒🔍**

For questions or issues, contact the infrastructure team or create a support ticket.

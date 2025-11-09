# Jira VM Provisioning System - Setup Guide

Complete guide for setting up the Jira-integrated automated VM provisioning system for security engineering testing.

## Table of Contents

- [Prerequisites](#prerequisites)
- [System Setup](#system-setup)
- [Jira Configuration](#jira-configuration)
- [Service Installation](#service-installation)
- [Testing](#testing)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

- Linux server with KVM/libvirt support
- Minimum 16GB RAM (for hosting multiple VMs)
- 200GB+ free disk space
- CPU with virtualization support
- Python 3.9+
- Root access for VM provisioning

### Software Dependencies

```bash
# System packages (RHEL/CentOS/Rocky/Alma)
sudo dnf install -y \
    libvirt qemu-kvm virt-install virt-manager \
    genisoimage wget curl \
    python3 python3-pip python3-devel \
    ansible-core

# System packages (Ubuntu/Debian)
sudo apt install -y \
    qemu-kvm libvirt-daemon-system libvirt-clients \
    virtinst virt-manager genisoimage \
    python3 python3-pip python3-dev \
    ansible

# Enable libvirt
sudo systemctl enable --now libvirtd
```

### Jira Setup

You'll need:
1. Jira Cloud or Server instance
2. API token (for Cloud) or password (for Server)
3. Project for VM provisioning requests
4. Admin access to configure webhooks and custom fields

## System Setup

### 1. Clone Repository

```bash
git clone <repository-url>
cd RHCE-prep
```

### 2. Install Python Dependencies

```bash
# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### 3. Setup Base Image

```bash
# Download base cloud image
sudo mkdir -p /var/lib/libvirt/images/jira-vms
cd /var/lib/libvirt/images/jira-vms

sudo wget https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2 \
    -O centos-stream-9-base.qcow2
```

### 4. Create Required Directories

```bash
sudo mkdir -p /var/lib/jira-provisioner/ssh-keys
sudo mkdir -p /var/lib/jira-provisioner/playbooks
sudo mkdir -p /var/log/jira-provisioner

# Set permissions (adjust user as needed)
sudo chown -R $USER:$USER /var/lib/jira-provisioner
sudo chown -R $USER:$USER /var/log/jira-provisioner
```

## Jira Configuration

### 1. Create Jira Project

1. In Jira, create a new project (e.g., "Security VMs" with key "SECVM")
2. Configure issue types (Task or custom type)

### 2. Create Custom Fields (Optional)

For better integration, create custom fields:

- **VM Name** (Text Field - Single Line)
- **CPU Cores** (Number Field)
- **RAM MB** (Number Field)
- **Disk GB** (Number Field)
- **Software List** (Text Field - Multi-line)
- **Network Isolated** (Checkbox)
- **Auto Destroy Hours** (Number Field)

### 3. Get API Token

**Jira Cloud:**
1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Name it "VM Provisioner" and copy the token

**Jira Server/Data Center:**
Use your password for API authentication.

### 4. Configure Webhook (For automatic provisioning)

1. Go to Jira Settings → System → WebHooks
2. Click "Create a WebHook"
3. Configure:
   - **Name:** VM Provisioner
   - **Status:** Enabled
   - **URL:** `http://your-server:5000/webhook`
   - **Events:**
     - Issue Created
     - Issue Updated
   - **JQL Filter (optional):** `project = SECVM AND labels = vm-provisioning-request`

4. (Optional) Set webhook secret for security

## Service Installation

### 1. Configure Service

```bash
# Copy example config
cp config/jira-provisioner.env.example config/jira-provisioner.env

# Edit configuration
vi config/jira-provisioner.env
```

Required configuration:
```bash
# Jira Configuration
JIRA_URL=https://your-instance.atlassian.net
JIRA_USERNAME=your-email@domain.com
JIRA_API_TOKEN=your-api-token-here
JIRA_PROJECT_KEY=SECVM

# Webhook Configuration (if using webhooks)
WEBHOOK_SECRET=generate-random-secret-here
WEBHOOK_PORT=5000
WEBHOOK_HOST=0.0.0.0

# Resource Limits
MAX_CPU_CORES=8
MAX_RAM_MB=16384
MAX_DISK_GB=100
```

### 2. Test Configuration

```bash
# Run tests
bash scripts/run-tests.sh

# Test with mock Jira
python3 jira-provisioner.py --mode once --ticket TEST-123
```

### 3. Create Systemd Service (Production)

```bash
# Create service file
sudo tee /etc/systemd/system/jira-provisioner.service > /dev/null << 'EOF'
[Unit]
Description=Jira VM Provisioning Service
After=network.target libvirtd.service

[Service]
Type=simple
User=root
WorkingDirectory=/path/to/RHCE-prep
Environment="PATH=/path/to/RHCE-prep/venv/bin:/usr/local/bin:/usr/bin"
ExecStart=/path/to/RHCE-prep/venv/bin/python3 /path/to/RHCE-prep/jira-provisioner.py --mode webhook
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

# Enable and start
sudo systemctl enable jira-provisioner
sudo systemctl start jira-provisioner

# Check status
sudo systemctl status jira-provisioner
```

## Testing

### Unit Tests

```bash
# Run all unit tests
pytest tests/ -v

# Run with coverage
pytest --cov=src --cov-report=html tests/

# View coverage report
firefox htmlcov/index.html
```

### Integration Testing

```bash
# Interactive testing tool
bash scripts/test-with-jira.sh
```

Options:
1. **Create test ticket** - Creates a ticket in Jira
2. **Process existing ticket** - Manually process a ticket
3. **Run webhook server** - Start server for testing
4. **Test VM provisioning** - Test without Jira
5. **Run all tests** - Execute test suite

### Manual Test Workflow

#### 1. Create Test Ticket in Jira

Create a new issue with:
```
Summary: Test VM - Security Lab

Description:
VM Name: security-test-001
CPU Cores: 2
RAM (MB): 2048
Disk Size (GB): 20
Software List:
- nmap
- wireshark
- tcpdump
Network Isolated: no
Auto Destroy (hours): 2

Labels: vm-provisioning-request
```

#### 2. Process Manually (Testing)

```bash
# Process specific ticket
python3 jira-provisioner.py --mode once --ticket SECVM-123
```

#### 3. Verify VM Creation

```bash
# Check VM is running
sudo virsh list

# Get VM info
sudo virsh dominfo security-test-001

# Check SSH access (from Jira comment)
ssh -i /var/lib/jira-provisioner/ssh-keys/security-test-001 sectest@<ip-address>
```

#### 4. Verify Software Installation

```bash
# SSH into VM and check
nmap --version
wireshark --version
```

#### 5. Check Jira Updates

Verify the ticket has comments with:
- Status updates
- VM connection information
- IP address and SSH command

## Deployment

### Production Deployment Checklist

- [ ] Configure firewall for webhook endpoint
- [ ] Set up HTTPS/TLS for webhook (use nginx/Apache as reverse proxy)
- [ ] Configure webhook secret in both Jira and service
- [ ] Set appropriate resource limits in config
- [ ] Configure log rotation
- [ ] Set up monitoring/alerting
- [ ] Configure auto-cleanup for expired VMs
- [ ] Document VM naming conventions
- [ ] Create user documentation
- [ ] Set up backup for configuration

### Nginx Reverse Proxy (Recommended)

```nginx
server {
    listen 443 ssl;
    server_name provisioner.yourdomain.com;

    ssl_certificate /etc/ssl/certs/provisioner.crt;
    ssl_certificate_key /etc/ssl/private/provisioner.key;

    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Auto-Cleanup Service

Create a systemd timer for cleanup:

```bash
# Create cleanup script
sudo tee /usr/local/bin/cleanup-expired-vms.sh > /dev/null << 'EOF'
#!/bin/bash
# TODO: Implement cleanup logic for expired VMs
EOF

sudo chmod +x /usr/local/bin/cleanup-expired-vms.sh

# Create systemd timer
sudo tee /etc/systemd/system/vm-cleanup.timer > /dev/null << 'EOF'
[Unit]
Description=Cleanup expired VMs

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl enable vm-cleanup.timer
sudo systemctl start vm-cleanup.timer
```

## Troubleshooting

### Common Issues

#### 1. VM Creation Fails

**Error:** "Failed to create VM disk"

**Solution:**
```bash
# Check disk space
df -h /var/lib/libvirt/images

# Check libvirt is running
sudo systemctl status libvirtd

# Check permissions
sudo chown -R qemu:qemu /var/lib/libvirt/images/jira-vms
```

#### 2. SSH Connection Fails

**Error:** "VM failed to boot or respond to SSH"

**Solution:**
```bash
# Check VM console
sudo virsh console <vm-name>

# Check cloud-init status (from console)
sudo cloud-init status --long

# Verify network
sudo virsh net-list
sudo virsh net-dhcp-leases default
```

#### 3. Software Installation Fails

**Error:** "Software installation failed"

**Solution:**
```bash
# Check generated playbook
cat /var/lib/jira-provisioner/playbooks/<vm-name>-install.yml

# Run playbook manually with verbose
ansible-playbook -i <inventory> <playbook> -vvv

# Check Ansible is installed
ansible --version
```

#### 4. Jira Connection Issues

**Error:** "Failed to connect to Jira"

**Solution:**
```bash
# Test Jira API manually
curl -u "email@domain.com:api-token" \
    https://your-instance.atlassian.net/rest/api/2/myself

# Check credentials in config
cat config/jira-provisioner.env | grep JIRA_

# Test with mock Jira
export MOCK_JIRA=true
python3 jira-provisioner.py --mode once --ticket TEST-1
```

#### 5. Webhook Not Triggering

**Solution:**
```bash
# Check webhook server is running
curl http://localhost:5000/health

# Check firewall
sudo firewall-cmd --list-all

# Check Jira webhook configuration
# Verify URL is correct and reachable from Jira

# Check webhook logs
tail -f /var/log/jira-provisioner/provisioner.log
```

### Debugging

Enable debug logging:
```bash
# In config/jira-provisioner.env
LOG_LEVEL=DEBUG

# Restart service
sudo systemctl restart jira-provisioner

# Watch logs
tail -f /var/log/jira-provisioner/provisioner.log
```

### Getting Help

1. Check logs: `/var/log/jira-provisioner/provisioner.log`
2. Run tests: `bash scripts/run-tests.sh`
3. Use testing tool: `bash scripts/test-with-jira.sh`
4. Check VM status: `sudo virsh list --all`
5. Verify network: `sudo virsh net-list --all`

## Next Steps

After setup:
1. Create test ticket and verify workflow
2. Configure auto-cleanup for expired VMs
3. Set up monitoring and alerting
4. Create user documentation
5. Train team on ticket format and usage
6. Implement additional security tools as needed
7. Configure backup and disaster recovery

## Security Considerations

- SSH keys are generated per-VM and stored securely
- Network isolation option for sensitive testing
- Resource limits prevent abuse
- Auto-destroy ensures cleanup
- Webhook secret prevents unauthorized provisioning
- All Jira updates are logged

## Support

For issues and questions:
- Check logs in `/var/log/jira-provisioner/`
- Run diagnostic tests: `bash scripts/test-with-jira.sh`
- Review Jira ticket comments for provisioning status

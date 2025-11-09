# Jira-Integrated VM Provisioning System

Automated libvirt VM provisioning for security engineering testing via Jira tickets.

## Architecture

```
┌─────────────┐
│ Jira Ticket │ ──┐
└─────────────┘   │
                  ▼
         ┌────────────────────┐
         │  Webhook/Poller    │
         │  (Flask Service)   │
         └────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │ Ticket Validator   │
         │  & Parser          │
         └────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │ VM Provisioner     │
         │ (Dynamic Creation) │
         └────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │ Ansible Automation │
         │ (Software Install) │
         └────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │ Status Reporter    │
         │ (Update Jira)      │
         └────────────────────┘
```

## Jira Ticket Format

### Custom Fields Required

Create a Jira project with these custom fields:

1. **VM Name** (Single line text) - `vm_name`
2. **CPU Cores** (Number) - `cpu_cores`
3. **RAM (MB)** (Number) - `ram_mb`
4. **Disk Size (GB)** (Number) - `disk_gb`
5. **Software List** (Multi-line text) - `software_list`
6. **Network Isolation** (Checkbox) - `network_isolated`
7. **Auto Destroy** (Number - hours) - `auto_destroy_hours`

### Example Ticket

```
Summary: Security Testing VM - Metasploit Lab
VM Name: metasploit-lab-001
CPU Cores: 4
RAM: 8192
Disk Size: 40
Software List:
  - metasploit-framework
  - nmap
  - wireshark
  - docker
  - python3
Network Isolation: Yes
Auto Destroy: 24
```

## Service Components

### 1. Jira Webhook Listener (Flask)
- Receives webhook events from Jira
- Validates ticket format
- Queues provisioning requests

### 2. VM Provisioner
- Creates libvirt VMs with specified resources
- Configures network isolation
- Generates cloud-init configs

### 3. Software Installer (Ansible)
- Dynamically generates playbooks
- Installs requested software
- Configures security tools

### 4. Status Reporter
- Updates Jira ticket with progress
- Provides VM credentials
- Schedules auto-destruction

## Testing Strategy

### Unit Tests
- Ticket parsing and validation
- VM spec generation
- Ansible playbook generation

### Integration Tests
- Mock Jira API responses
- End-to-end provisioning flow
- Cleanup verification

### Functional Tests
- Real Jira ticket processing
- VM creation and verification
- Software installation validation

## Setup Requirements

```bash
# Python dependencies
pip install flask jira python-dotenv pyyaml ansible

# Jira webhook configuration
# Configure in Jira: Settings -> System -> WebHooks
```

## Configuration

See `config/jira-provisioner.env` for configuration options.

#!/bin/bash

# Script to test provisioning with actual Jira integration

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Jira Integration Testing Tool ===${NC}\n"

# Check for config
if [ ! -f "config/jira-provisioner.env" ]; then
    echo -e "${RED}Error: config/jira-provisioner.env not found${NC}"
    echo -e "${YELLOW}Copy config/jira-provisioner.env.example and configure it${NC}"
    exit 1
fi

# Load config
source config/jira-provisioner.env

# Check if Jira credentials are set
if [ -z "$JIRA_URL" ] || [ -z "$JIRA_API_TOKEN" ]; then
    echo -e "${YELLOW}Jira credentials not configured. Running in MOCK mode.${NC}"
    export MOCK_JIRA=true
fi

# Menu
echo -e "${YELLOW}Select testing mode:${NC}"
echo "1. Create test ticket in Jira"
echo "2. Process existing ticket"
echo "3. Run webhook server (testing)"
echo "4. Test VM provisioning only (no Jira)"
echo "5. Run all unit tests"
echo ""
read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        echo -e "\n${YELLOW}Creating test ticket in Jira...${NC}"

        # Use Python to create ticket via API
        python3 << 'EOF'
import os
import sys
sys.path.insert(0, 'src')

from jira_client import JiraClient
from dotenv import load_dotenv

load_dotenv('config/jira-provisioner.env')

try:
    client = JiraClient(
        url=os.getenv('JIRA_URL'),
        username=os.getenv('JIRA_USERNAME'),
        api_token=os.getenv('JIRA_API_TOKEN'),
        project_key=os.getenv('JIRA_PROJECT_KEY', 'SECVM')
    )

    # Create test ticket
    issue_dict = {
        'project': {'key': os.getenv('JIRA_PROJECT_KEY', 'SECVM')},
        'summary': 'Test VM - Security Testing Environment',
        'description': '''VM Name: security-test-001
CPU Cores: 2
RAM (MB): 2048
Disk Size (GB): 20
Software List:
- nmap
- wireshark
- tcpdump
Network Isolated: no
Auto Destroy (hours): 2''',
        'issuetype': {'name': 'Task'},
        'labels': ['vm-provisioning-request']
    }

    new_issue = client.client.create_issue(fields=issue_dict)
    print(f"\n✓ Created ticket: {new_issue.key}")
    print(f"  URL: {os.getenv('JIRA_URL')}/browse/{new_issue.key}")

except Exception as e:
    print(f"✗ Failed to create ticket: {e}")
    sys.exit(1)
EOF
        ;;

    2)
        echo -e "\n${YELLOW}Enter Jira ticket key (e.g., SECVM-123):${NC}"
        read -p "Ticket: " ticket_key

        echo -e "\n${YELLOW}Processing ticket $ticket_key...${NC}"

        python3 jira-provisioner.py --mode once --ticket "$ticket_key"
        ;;

    3)
        echo -e "\n${YELLOW}Starting webhook server on port ${WEBHOOK_PORT:-5000}...${NC}"
        echo -e "${YELLOW}Press Ctrl+C to stop${NC}\n"

        python3 jira-provisioner.py --mode webhook
        ;;

    4)
        echo -e "\n${YELLOW}Testing VM provisioning (no Jira integration)...${NC}"

        python3 << 'EOF'
import sys
import os
sys.path.insert(0, 'src')

from vm_provisioner import VMProvisioner
from models import VMSpec

# Create test spec
spec = VMSpec(
    vm_name="test-vm-direct",
    cpu_cores=2,
    ram_mb=2048,
    disk_gb=20,
    software_list=[]
)

# Validate
is_valid, error = spec.validate()
if not is_valid:
    print(f"✗ Validation failed: {error}")
    sys.exit(1)

print(f"✓ VM spec validated successfully")
print(f"  Name: {spec.vm_name}")
print(f"  CPU: {spec.cpu_cores} cores")
print(f"  RAM: {spec.ram_mb} MB")
print(f"  Disk: {spec.disk_gb} GB")

# Note: Actual provisioning requires libvirt and root access
print("\nTo actually provision, run:")
print(f"  sudo python3 jira-provisioner.py --mode once --ticket TEST-123")
EOF
        ;;

    5)
        echo -e "\n${YELLOW}Running all tests...${NC}"
        bash scripts/run-tests.sh
        ;;

    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}Done!${NC}"

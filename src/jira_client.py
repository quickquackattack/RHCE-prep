"""
Jira API client for VM provisioning integration.
"""

import logging
from typing import Optional, Dict, Any
from datetime import datetime
from jira import JIRA
from jira.exceptions import JIRAError

from .models import VMSpec, ProvisioningRequest, ProvisioningStatus

logger = logging.getLogger(__name__)


class JiraClient:
    """Client for interacting with Jira API."""

    def __init__(self, url: str, username: str, api_token: str, project_key: str):
        """
        Initialize Jira client.

        Args:
            url: Jira instance URL
            username: Jira username/email
            api_token: Jira API token
            project_key: Project key for VM requests
        """
        self.url = url
        self.username = username
        self.project_key = project_key

        try:
            self.client = JIRA(server=url, basic_auth=(username, api_token))
            logger.info(f"Connected to Jira: {url}")
        except JIRAError as e:
            logger.error(f"Failed to connect to Jira: {e}")
            raise

    def parse_ticket(self, ticket_key: str) -> Optional[VMSpec]:
        """
        Parse a Jira ticket into a VMSpec.

        Args:
            ticket_key: Jira ticket key (e.g., SECVM-123)

        Returns:
            VMSpec if valid, None if parsing fails
        """
        try:
            issue = self.client.issue(ticket_key)

            # Extract custom fields (adjust field IDs based on your Jira instance)
            fields = issue.fields

            # For testing, we'll use description parsing if custom fields aren't set up
            vm_spec = self._parse_from_description(issue)

            if vm_spec:
                vm_spec.jira_ticket_key = ticket_key
                vm_spec.requester = str(issue.fields.reporter)
                vm_spec.created_at = datetime.now().isoformat()

            return vm_spec

        except JIRAError as e:
            logger.error(f"Failed to fetch ticket {ticket_key}: {e}")
            return None
        except Exception as e:
            logger.error(f"Failed to parse ticket {ticket_key}: {e}")
            return None

    def _parse_from_description(self, issue) -> Optional[VMSpec]:
        """
        Parse VM spec from ticket description.

        Format expected:
        VM Name: vm-name
        CPU Cores: 4
        RAM (MB): 8192
        Disk Size (GB): 40
        Software List:
        - package1
        - package2
        Network Isolated: yes/no
        Auto Destroy (hours): 24
        """
        try:
            description = issue.fields.description or ""
            summary = issue.fields.summary or ""

            # Parse fields
            vm_name = self._extract_field(description, "VM Name") or self._generate_vm_name(summary)
            cpu_cores = int(self._extract_field(description, "CPU Cores") or "2")
            ram_mb = int(self._extract_field(description, "RAM") or "2048")
            disk_gb = int(self._extract_field(description, "Disk Size") or "20")

            # Parse software list
            software_list = self._extract_software_list(description)

            # Parse boolean fields
            network_isolated = self._extract_field(description, "Network Isolated", "no").lower() in ["yes", "true", "1"]

            # Parse auto-destroy
            auto_destroy_str = self._extract_field(description, "Auto Destroy", "24")
            auto_destroy_hours = int(auto_destroy_str) if auto_destroy_str.isdigit() else 24

            return VMSpec(
                vm_name=vm_name,
                cpu_cores=cpu_cores,
                ram_mb=ram_mb,
                disk_gb=disk_gb,
                software_list=software_list,
                network_isolated=network_isolated,
                auto_destroy_hours=auto_destroy_hours,
            )

        except Exception as e:
            logger.error(f"Failed to parse description: {e}")
            return None

    def _extract_field(self, text: str, field_name: str, default: str = "") -> str:
        """Extract a field value from text."""
        import re

        pattern = rf"{field_name}:\s*(.+?)(?:\n|$)"
        match = re.search(pattern, text, re.IGNORECASE)

        if match:
            return match.group(1).strip()

        return default

    def _extract_software_list(self, text: str) -> list[str]:
        """Extract software list from description."""
        import re

        software = []
        in_software_section = False

        for line in text.split('\n'):
            line = line.strip()

            if re.match(r"software\s*list", line, re.IGNORECASE):
                in_software_section = True
                continue

            if in_software_section:
                # Check if we've hit another field
                if ':' in line and not line.startswith('-'):
                    break

                # Extract software item
                if line.startswith('-') or line.startswith('*'):
                    item = line[1:].strip()
                    if item:
                        software.append(item)

        return software

    def _generate_vm_name(self, summary: str) -> str:
        """Generate a VM name from the ticket summary."""
        import re

        # Convert summary to valid VM name
        name = summary.lower()
        name = re.sub(r'[^a-z0-9-]', '-', name)
        name = re.sub(r'-+', '-', name)
        name = name.strip('-')

        # Truncate and add timestamp
        timestamp = datetime.now().strftime("%Y%m%d%H%M")
        max_len = 50
        if len(name) > max_len:
            name = name[:max_len]

        return f"{name}-{timestamp}"

    def update_ticket_status(
        self,
        ticket_key: str,
        status: ProvisioningStatus,
        message: Optional[str] = None,
        vm_info: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Update Jira ticket with provisioning status.

        Args:
            ticket_key: Jira ticket key
            status: Current provisioning status
            message: Status message
            vm_info: VM connection information

        Returns:
            True if successful, False otherwise
        """
        try:
            issue = self.client.issue(ticket_key)

            # Build comment
            comment_text = f"*VM Provisioning Status:* {status.value}\n\n"

            if message:
                comment_text += f"{message}\n\n"

            if vm_info:
                comment_text += "h3. VM Information\n\n"
                comment_text += f"||Property||Value||\n"
                for key, value in vm_info.items():
                    comment_text += f"|{key}|{value}|\n"

            # Add comment
            self.client.add_comment(ticket_key, comment_text)

            # Update labels
            current_labels = issue.fields.labels or []
            status_label = f"vm-{status.value}"

            # Remove old status labels
            new_labels = [l for l in current_labels if not l.startswith("vm-")]
            new_labels.append(status_label)

            issue.update(fields={"labels": new_labels})

            logger.info(f"Updated ticket {ticket_key} with status {status.value}")
            return True

        except JIRAError as e:
            logger.error(f"Failed to update ticket {ticket_key}: {e}")
            return False

    def get_pending_tickets(self, max_results: int = 10) -> list[str]:
        """
        Get list of pending VM provisioning tickets.

        Args:
            max_results: Maximum number of tickets to return

        Returns:
            List of ticket keys
        """
        try:
            # Query for tickets with specific label or in specific status
            jql = f'project = {self.project_key} AND status = "To Do" AND labels = "vm-provisioning-request"'

            issues = self.client.search_issues(jql, maxResults=max_results)

            return [issue.key for issue in issues]

        except JIRAError as e:
            logger.error(f"Failed to query pending tickets: {e}")
            return []


class MockJiraClient(JiraClient):
    """Mock Jira client for testing."""

    def __init__(self):
        """Initialize mock client without connecting to Jira."""
        self.url = "https://mock.atlassian.net"
        self.username = "test@example.com"
        self.project_key = "TEST"
        self.client = None
        self.mock_tickets: Dict[str, VMSpec] = {}
        self.mock_comments: Dict[str, list] = {}

    def add_mock_ticket(self, ticket_key: str, vm_spec: VMSpec):
        """Add a mock ticket for testing."""
        self.mock_tickets[ticket_key] = vm_spec

    def parse_ticket(self, ticket_key: str) -> Optional[VMSpec]:
        """Return mock ticket spec."""
        return self.mock_tickets.get(ticket_key)

    def update_ticket_status(
        self,
        ticket_key: str,
        status: ProvisioningStatus,
        message: Optional[str] = None,
        vm_info: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Record mock status update."""
        if ticket_key not in self.mock_comments:
            self.mock_comments[ticket_key] = []

        self.mock_comments[ticket_key].append({
            'status': status,
            'message': message,
            'vm_info': vm_info,
        })
        return True

    def get_pending_tickets(self, max_results: int = 10) -> list[str]:
        """Return all mock ticket keys."""
        return list(self.mock_tickets.keys())[:max_results]

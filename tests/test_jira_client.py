"""
Unit tests for Jira client.
"""

import pytest
from src.jira_client import MockJiraClient
from src.models import VMSpec, ProvisioningStatus


class TestMockJiraClient:
    """Tests for MockJiraClient."""

    def setup_method(self):
        """Setup test client."""
        self.client = MockJiraClient()

    def test_add_and_parse_ticket(self):
        """Test adding and parsing mock tickets."""
        spec = VMSpec(
            vm_name="test-vm",
            cpu_cores=4,
            ram_mb=8192,
            disk_gb=40,
            software_list=["nmap", "wireshark"]
        )

        self.client.add_mock_ticket("TEST-123", spec)

        parsed_spec = self.client.parse_ticket("TEST-123")

        assert parsed_spec is not None
        assert parsed_spec.vm_name == "test-vm"
        assert parsed_spec.cpu_cores == 4
        assert parsed_spec.ram_mb == 8192
        assert len(parsed_spec.software_list) == 2

    def test_update_ticket_status(self):
        """Test updating ticket status."""
        spec = VMSpec(vm_name="test-vm", cpu_cores=2, ram_mb=2048, disk_gb=20)
        self.client.add_mock_ticket("TEST-456", spec)

        success = self.client.update_ticket_status(
            "TEST-456",
            ProvisioningStatus.READY,
            "VM is ready",
            {"ip": "192.168.100.10"}
        )

        assert success is True
        assert "TEST-456" in self.client.mock_comments
        assert len(self.client.mock_comments["TEST-456"]) == 1

        comment = self.client.mock_comments["TEST-456"][0]
        assert comment['status'] == ProvisioningStatus.READY
        assert comment['message'] == "VM is ready"
        assert comment['vm_info']['ip'] == "192.168.100.10"

    def test_get_pending_tickets(self):
        """Test getting pending tickets."""
        spec1 = VMSpec(vm_name="vm1", cpu_cores=2, ram_mb=2048, disk_gb=20)
        spec2 = VMSpec(vm_name="vm2", cpu_cores=4, ram_mb=4096, disk_gb=40)

        self.client.add_mock_ticket("TEST-1", spec1)
        self.client.add_mock_ticket("TEST-2", spec2)

        tickets = self.client.get_pending_tickets()

        assert len(tickets) == 2
        assert "TEST-1" in tickets
        assert "TEST-2" in tickets

    def test_parse_nonexistent_ticket(self):
        """Test parsing a ticket that doesn't exist."""
        spec = self.client.parse_ticket("NONEXISTENT-999")
        assert spec is None

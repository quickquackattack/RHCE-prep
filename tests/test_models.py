"""
Unit tests for data models.
"""

import pytest
from src.models import VMSpec, ProvisioningRequest, ProvisioningStatus


class TestVMSpec:
    """Tests for VMSpec model."""

    def test_valid_spec(self):
        """Test validation of a valid spec."""
        spec = VMSpec(
            vm_name="test-vm-001",
            cpu_cores=2,
            ram_mb=2048,
            disk_gb=20,
        )

        is_valid, error = spec.validate()
        assert is_valid is True
        assert error is None

    def test_invalid_vm_name(self):
        """Test validation fails for invalid VM name."""
        spec = VMSpec(
            vm_name="test vm with spaces!",
            cpu_cores=2,
            ram_mb=2048,
            disk_gb=20,
        )

        is_valid, error = spec.validate()
        assert is_valid is False
        assert "alphanumeric" in error

    def test_cpu_limits(self):
        """Test CPU limits validation."""
        # Too few
        spec = VMSpec(vm_name="test", cpu_cores=0, ram_mb=2048, disk_gb=20)
        is_valid, error = spec.validate()
        assert is_valid is False
        assert "at least 1" in error

        # Too many
        spec = VMSpec(vm_name="test", cpu_cores=16, ram_mb=2048, disk_gb=20)
        is_valid, error = spec.validate(max_cpu=8)
        assert is_valid is False
        assert "cannot exceed" in error

    def test_ram_limits(self):
        """Test RAM limits validation."""
        # Too little
        spec = VMSpec(vm_name="test", cpu_cores=2, ram_mb=256, disk_gb=20)
        is_valid, error = spec.validate()
        assert is_valid is False
        assert "at least 512" in error

        # Too much
        spec = VMSpec(vm_name="test", cpu_cores=2, ram_mb=32768, disk_gb=20)
        is_valid, error = spec.validate(max_ram=16384)
        assert is_valid is False
        assert "cannot exceed" in error

    def test_disk_limits(self):
        """Test disk limits validation."""
        # Too small
        spec = VMSpec(vm_name="test", cpu_cores=2, ram_mb=2048, disk_gb=5)
        is_valid, error = spec.validate()
        assert is_valid is False
        assert "at least 10" in error

        # Too large
        spec = VMSpec(vm_name="test", cpu_cores=2, ram_mb=2048, disk_gb=200)
        is_valid, error = spec.validate(max_disk=100)
        assert is_valid is False
        assert "cannot exceed" in error

    def test_auto_destroy_limits(self):
        """Test auto-destroy limits."""
        # Too short
        spec = VMSpec(
            vm_name="test",
            cpu_cores=2,
            ram_mb=2048,
            disk_gb=20,
            auto_destroy_hours=0
        )
        is_valid, error = spec.validate()
        assert is_valid is False
        assert "at least 1 hour" in error

        # Too long
        spec = VMSpec(
            vm_name="test",
            cpu_cores=2,
            ram_mb=2048,
            disk_gb=20,
            auto_destroy_hours=200
        )
        is_valid, error = spec.validate()
        assert is_valid is False
        assert "cannot exceed 168" in error

    def test_software_list(self):
        """Test software list handling."""
        spec = VMSpec(
            vm_name="test",
            cpu_cores=2,
            ram_mb=2048,
            disk_gb=20,
            software_list=["nmap", "metasploit", "docker"]
        )

        assert len(spec.software_list) == 3
        assert "nmap" in spec.software_list


class TestProvisioningRequest:
    """Tests for ProvisioningRequest model."""

    def test_initial_status(self):
        """Test initial request status."""
        spec = VMSpec(vm_name="test", cpu_cores=2, ram_mb=2048, disk_gb=20)
        request = ProvisioningRequest(spec=spec)

        assert request.status == ProvisioningStatus.PENDING
        assert request.error_message is None

    def test_to_dict(self):
        """Test conversion to dictionary."""
        spec = VMSpec(vm_name="test", cpu_cores=2, ram_mb=2048, disk_gb=20)
        request = ProvisioningRequest(spec=spec)
        request.status = ProvisioningStatus.READY
        request.ip_address = "192.168.100.10"

        data = request.to_dict()

        assert data['vm_name'] == "test"
        assert data['status'] == "ready"
        assert data['ip_address'] == "192.168.100.10"

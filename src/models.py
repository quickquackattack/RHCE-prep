"""
Data models for VM provisioning requests.
"""

from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum


class ProvisioningStatus(Enum):
    """VM provisioning status states."""
    PENDING = "pending"
    VALIDATING = "validating"
    PROVISIONING = "provisioning"
    INSTALLING_SOFTWARE = "installing_software"
    READY = "ready"
    FAILED = "failed"
    DESTROYING = "destroying"
    DESTROYED = "destroyed"


@dataclass
class VMSpec:
    """Specification for a VM to be provisioned."""

    # Required fields
    vm_name: str
    cpu_cores: int
    ram_mb: int
    disk_gb: int

    # Optional fields
    software_list: List[str] = field(default_factory=list)
    network_isolated: bool = False
    auto_destroy_hours: Optional[int] = 24

    # Metadata
    jira_ticket_key: Optional[str] = None
    requester: Optional[str] = None
    created_at: Optional[str] = None

    # Networking
    ip_address: Optional[str] = None
    mac_address: Optional[str] = None
    network_name: Optional[str] = None

    # Authentication
    ssh_user: str = "sectest"
    ssh_key_path: Optional[str] = None

    def validate(self, max_cpu: int = 8, max_ram: int = 16384, max_disk: int = 100) -> tuple[bool, Optional[str]]:
        """
        Validate VM specifications against resource limits.

        Returns:
            Tuple of (is_valid, error_message)
        """
        # Validate VM name
        if not self.vm_name or not self.vm_name.replace('-', '').replace('_', '').isalnum():
            return False, "VM name must be alphanumeric (with hyphens/underscores)"

        if len(self.vm_name) > 64:
            return False, "VM name must be 64 characters or less"

        # Validate CPU
        if self.cpu_cores < 1:
            return False, "CPU cores must be at least 1"

        if self.cpu_cores > max_cpu:
            return False, f"CPU cores cannot exceed {max_cpu}"

        # Validate RAM
        if self.ram_mb < 512:
            return False, "RAM must be at least 512 MB"

        if self.ram_mb > max_ram:
            return False, f"RAM cannot exceed {max_ram} MB"

        # Validate disk
        if self.disk_gb < 10:
            return False, "Disk size must be at least 10 GB"

        if self.disk_gb > max_disk:
            return False, f"Disk size cannot exceed {max_disk} GB"

        # Validate auto-destroy
        if self.auto_destroy_hours is not None:
            if self.auto_destroy_hours < 1:
                return False, "Auto-destroy must be at least 1 hour"

            if self.auto_destroy_hours > 168:  # 1 week
                return False, "Auto-destroy cannot exceed 168 hours (1 week)"

        return True, None


@dataclass
class ProvisioningRequest:
    """Complete provisioning request with status tracking."""

    spec: VMSpec
    status: ProvisioningStatus = ProvisioningStatus.PENDING
    status_message: Optional[str] = None
    error_message: Optional[str] = None

    # VM details (populated after provisioning)
    vm_id: Optional[str] = None
    ip_address: Optional[str] = None
    ssh_connection_string: Optional[str] = None

    # Timestamps
    created_at: Optional[str] = None
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    destroy_at: Optional[str] = None

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            'vm_name': self.spec.vm_name,
            'status': self.status.value,
            'status_message': self.status_message,
            'error_message': self.error_message,
            'ip_address': self.ip_address,
            'ssh_connection': self.ssh_connection_string,
            'created_at': self.created_at,
            'completed_at': self.completed_at,
            'destroy_at': self.destroy_at,
        }

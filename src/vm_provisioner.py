"""
Dynamic VM provisioning engine for libvirt.
"""

import logging
import subprocess
import os
import uuid
from typing import Optional, Tuple
from datetime import datetime, timedelta

from .models import VMSpec, ProvisioningRequest, ProvisioningStatus

logger = logging.getLogger(__name__)


class VMProvisioner:
    """Provisions VMs in libvirt based on specifications."""

    def __init__(
        self,
        images_dir: str = "/var/lib/libvirt/images/jira-vms",
        base_image_path: Optional[str] = None,
        network_prefix: str = "192.168",
        ssh_key_dir: str = "/var/lib/jira-provisioner/ssh-keys",
    ):
        """
        Initialize VM provisioner.

        Args:
            images_dir: Directory for VM disk images
            base_image_path: Path to base cloud image
            network_prefix: Network prefix for VM IPs (e.g., "192.168")
            ssh_key_dir: Directory for SSH keys
        """
        self.images_dir = images_dir
        self.base_image_path = base_image_path or os.path.join(images_dir, "centos-stream-9-base.qcow2")
        self.network_prefix = network_prefix
        self.ssh_key_dir = ssh_key_dir

        # Create directories
        os.makedirs(images_dir, exist_ok=True)
        os.makedirs(ssh_key_dir, exist_ok=True)

    def provision_vm(self, spec: VMSpec) -> ProvisioningRequest:
        """
        Provision a VM based on specification.

        Args:
            spec: VM specification

        Returns:
            ProvisioningRequest with status
        """
        request = ProvisioningRequest(spec=spec)
        request.created_at = datetime.now().isoformat()
        request.status = ProvisioningStatus.VALIDATING

        # Validate spec
        is_valid, error = spec.validate()
        if not is_valid:
            request.status = ProvisioningStatus.FAILED
            request.error_message = error
            return request

        try:
            # Generate SSH key for this VM
            ssh_key_path = self._generate_ssh_key(spec.vm_name)
            spec.ssh_key_path = ssh_key_path

            # Allocate IP address
            ip_address = self._allocate_ip_address()
            spec.ip_address = ip_address

            # Generate MAC address
            mac_address = self._generate_mac_address()
            spec.mac_address = mac_address

            # Create network if isolated
            if spec.network_isolated:
                network_name = f"vm-{spec.vm_name}"
                self._create_isolated_network(network_name, ip_address)
                spec.network_name = network_name
            else:
                spec.network_name = "default"

            request.status = ProvisioningStatus.PROVISIONING
            request.started_at = datetime.now().isoformat()

            # Create VM disk
            vm_disk = self._create_vm_disk(spec)

            # Create cloud-init ISO
            cloud_init_iso = self._create_cloud_init_iso(spec, ssh_key_path)

            # Create and start VM
            vm_id = self._create_vm(spec, vm_disk, cloud_init_iso)

            request.vm_id = vm_id
            request.ip_address = ip_address
            request.ssh_connection_string = f"ssh -i {ssh_key_path} {spec.ssh_user}@{ip_address}"

            # Calculate destroy time
            if spec.auto_destroy_hours:
                destroy_at = datetime.now() + timedelta(hours=spec.auto_destroy_hours)
                request.destroy_at = destroy_at.isoformat()

            logger.info(f"VM {spec.vm_name} provisioned successfully")
            return request

        except Exception as e:
            logger.error(f"Failed to provision VM {spec.vm_name}: {e}")
            request.status = ProvisioningStatus.FAILED
            request.error_message = str(e)
            return request

    def _generate_ssh_key(self, vm_name: str) -> str:
        """Generate SSH key pair for VM."""
        key_path = os.path.join(self.ssh_key_dir, f"{vm_name}")

        if os.path.exists(key_path):
            logger.warning(f"SSH key already exists for {vm_name}, using existing")
            return key_path

        cmd = [
            "ssh-keygen",
            "-t", "rsa",
            "-b", "4096",
            "-f", key_path,
            "-N", "",
            "-C", f"{vm_name}-key",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise Exception(f"Failed to generate SSH key: {result.stderr}")

        logger.info(f"Generated SSH key for {vm_name}")
        return key_path

    def _allocate_ip_address(self) -> str:
        """
        Allocate an available IP address.

        For now, we'll use a simple random allocation.
        In production, this should check for conflicts.
        """
        import random

        # Generate IP in range 192.168.200.10 - 192.168.200.250
        subnet = 200
        host = random.randint(10, 250)

        ip = f"{self.network_prefix}.{subnet}.{host}"

        logger.info(f"Allocated IP address: {ip}")
        return ip

    def _generate_mac_address(self) -> str:
        """Generate a random MAC address."""
        mac = [
            0x52, 0x54, 0x00,  # QEMU prefix
            random.randint(0x00, 0xff),
            random.randint(0x00, 0xff),
            random.randint(0x00, 0xff),
        ]

        import random
        mac_str = ':'.join(f'{b:02x}' for b in mac)

        logger.info(f"Generated MAC address: {mac_str}")
        return mac_str

    def _create_isolated_network(self, network_name: str, ip_address: str) -> None:
        """Create an isolated libvirt network for the VM."""
        # Extract network portion (e.g., 192.168.200.0/24)
        parts = ip_address.split('.')
        network_ip = f"{parts[0]}.{parts[1]}.{parts[2]}.0"
        gateway_ip = f"{parts[0]}.{parts[1]}.{parts[2]}.1"

        network_xml = f"""<network>
  <name>{network_name}</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr-{network_name[:8]}' stp='on' delay='0'/>
  <ip address='{gateway_ip}' netmask='255.255.255.0'>
    <dhcp>
      <range start='{parts[0]}.{parts[1]}.{parts[2]}.10' end='{parts[0]}.{parts[1]}.{parts[2]}.250'/>
    </dhcp>
  </ip>
</network>"""

        # Write network XML
        network_xml_path = os.path.join(self.images_dir, f"{network_name}-network.xml")
        with open(network_xml_path, 'w') as f:
            f.write(network_xml)

        # Define and start network
        cmd = ["virsh", "net-define", network_xml_path]
        subprocess.run(cmd, check=True, capture_output=True)

        cmd = ["virsh", "net-start", network_name]
        subprocess.run(cmd, check=True, capture_output=True)

        cmd = ["virsh", "net-autostart", network_name]
        subprocess.run(cmd, check=True, capture_output=True)

        logger.info(f"Created isolated network {network_name}")

    def _create_vm_disk(self, spec: VMSpec) -> str:
        """Create VM disk from base image."""
        vm_disk = os.path.join(self.images_dir, f"{spec.vm_name}.qcow2")

        if os.path.exists(vm_disk):
            raise Exception(f"VM disk already exists: {vm_disk}")

        # Create disk from base image
        cmd = [
            "qemu-img", "create",
            "-f", "qcow2",
            "-F", "qcow2",
            "-b", self.base_image_path,
            vm_disk,
            f"{spec.disk_gb}G",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise Exception(f"Failed to create VM disk: {result.stderr}")

        logger.info(f"Created VM disk: {vm_disk}")
        return vm_disk

    def _create_cloud_init_iso(self, spec: VMSpec, ssh_key_path: str) -> str:
        """Create cloud-init ISO for VM initialization."""
        # Read SSH public key
        with open(f"{ssh_key_path}.pub", 'r') as f:
            ssh_public_key = f.read().strip()

        # Create user-data
        user_data = f"""#cloud-config
hostname: {spec.vm_name}
fqdn: {spec.vm_name}.sectest.lab
manage_etc_hosts: true

users:
  - name: {spec.ssh_user}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    ssh_authorized_keys:
      - {ssh_public_key}

ssh_pwauth: false
disable_root: false

package_update: true
package_upgrade: false

packages:
  - vim
  - wget
  - curl
  - git
  - python3
  - python3-pip

runcmd:
  - systemctl enable sshd
  - systemctl start sshd
  - echo "{spec.ssh_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/{spec.ssh_user}
  - chmod 0440 /etc/sudoers.d/{spec.ssh_user}

final_message: "VM {spec.vm_name} is ready after $UPTIME seconds"
"""

        user_data_file = os.path.join(self.images_dir, f"{spec.vm_name}-user-data.yaml")
        with open(user_data_file, 'w') as f:
            f.write(user_data)

        # Create meta-data
        meta_data = f"""instance-id: {spec.vm_name}
local-hostname: {spec.vm_name}
"""

        meta_data_file = os.path.join(self.images_dir, f"{spec.vm_name}-meta-data.yaml")
        with open(meta_data_file, 'w') as f:
            f.write(meta_data)

        # Create ISO
        cloud_init_iso = os.path.join(self.images_dir, f"{spec.vm_name}-cloud-init.iso")

        # Try genisoimage first, fall back to mkisofs
        for cmd_name in ["genisoimage", "mkisofs"]:
            cmd = [
                cmd_name,
                "-output", cloud_init_iso,
                "-volid", "cidata",
                "-joliet",
                "-rock",
                user_data_file,
                meta_data_file,
            ]

            try:
                result = subprocess.run(cmd, capture_output=True, text=True, check=True)
                logger.info(f"Created cloud-init ISO: {cloud_init_iso}")
                return cloud_init_iso
            except (subprocess.CalledProcessError, FileNotFoundError):
                continue

        raise Exception("Neither genisoimage nor mkisofs found")

    def _create_vm(self, spec: VMSpec, vm_disk: str, cloud_init_iso: str) -> str:
        """Create and start the VM using virt-install."""
        cmd = [
            "virt-install",
            "--name", spec.vm_name,
            "--memory", str(spec.ram_mb),
            "--vcpus", str(spec.cpu_cores),
            "--disk", f"path={vm_disk},format=qcow2,bus=virtio",
            "--disk", f"path={cloud_init_iso},device=cdrom",
            "--network", f"network={spec.network_name},mac={spec.mac_address},model=virtio",
            "--os-variant", "centos-stream9",
            "--graphics", "none",
            "--console", "pty,target_type=serial",
            "--noautoconsole",
            "--import",
            "--boot", "hd",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise Exception(f"Failed to create VM: {result.stderr}")

        logger.info(f"Created and started VM: {spec.vm_name}")
        return spec.vm_name

    def destroy_vm(self, vm_name: str) -> bool:
        """
        Destroy a VM and clean up resources.

        Args:
            vm_name: Name of the VM to destroy

        Returns:
            True if successful, False otherwise
        """
        try:
            # Destroy VM
            cmd = ["virsh", "destroy", vm_name]
            subprocess.run(cmd, capture_output=True)

            # Undefine VM with storage cleanup
            cmd = ["virsh", "undefine", vm_name, "--remove-all-storage"]
            subprocess.run(cmd, capture_output=True, check=True)

            # Clean up cloud-init files
            for ext in ["-user-data.yaml", "-meta-data.yaml", "-cloud-init.iso"]:
                path = os.path.join(self.images_dir, f"{vm_name}{ext}")
                if os.path.exists(path):
                    os.remove(path)

            # Clean up network if isolated
            network_name = f"vm-{vm_name}"
            cmd = ["virsh", "net-info", network_name]
            result = subprocess.run(cmd, capture_output=True)

            if result.returncode == 0:
                cmd = ["virsh", "net-destroy", network_name]
                subprocess.run(cmd, capture_output=True)

                cmd = ["virsh", "net-undefine", network_name]
                subprocess.run(cmd, capture_output=True)

            logger.info(f"Destroyed VM: {vm_name}")
            return True

        except Exception as e:
            logger.error(f"Failed to destroy VM {vm_name}: {e}")
            return False

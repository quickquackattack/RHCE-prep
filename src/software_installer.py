"""
Ansible-based software installation for provisioned VMs.
"""

import logging
import os
import subprocess
import yaml
from typing import List
from jinja2 import Template

from .models import VMSpec

logger = logging.getLogger(__name__)


class SoftwareInstaller:
    """Installs software on VMs using Ansible."""

    # Security tool package mappings
    SECURITY_TOOLS = {
        # Scanning tools
        'nmap': {'package': 'nmap', 'repo': 'epel'},
        'masscan': {'package': 'masscan', 'repo': 'epel'},
        'nikto': {'package': 'nikto', 'repo': 'epel'},

        # Exploitation frameworks
        'metasploit': {'script': 'install_metasploit.sh'},
        'metasploit-framework': {'script': 'install_metasploit.sh'},

        # Network tools
        'wireshark': {'package': 'wireshark', 'repo': 'default'},
        'tcpdump': {'package': 'tcpdump', 'repo': 'default'},
        'netcat': {'package': 'nmap-ncat', 'repo': 'default'},

        # Web tools
        'burpsuite': {'script': 'install_burpsuite.sh'},
        'zaproxy': {'package': 'zaproxy', 'repo': 'epel'},
        'sqlmap': {'package': 'sqlmap', 'repo': 'epel'},

        # Forensics
        'volatility': {'pip': 'volatility3'},
        'autopsy': {'package': 'autopsy', 'repo': 'epel'},

        # Container tools
        'docker': {'package': 'docker-ce', 'repo': 'docker-ce'},
        'podman': {'package': 'podman', 'repo': 'default'},
        'kubernetes': {'script': 'install_k8s.sh'},

        # Development tools
        'python3': {'package': 'python3', 'repo': 'default'},
        'python3-pip': {'package': 'python3-pip', 'repo': 'default'},
        'golang': {'package': 'golang', 'repo': 'default'},
        'nodejs': {'package': 'nodejs', 'repo': 'epel'},

        # Database tools
        'postgresql': {'package': 'postgresql-server', 'repo': 'default'},
        'mysql': {'package': 'mysql-server', 'repo': 'default'},
        'mariadb': {'package': 'mariadb-server', 'repo': 'default'},
        'redis': {'package': 'redis', 'repo': 'epel'},

        # Web servers
        'apache': {'package': 'httpd', 'repo': 'default'},
        'nginx': {'package': 'nginx', 'repo': 'epel'},

        # Misc security tools
        'john': {'package': 'john', 'repo': 'epel'},
        'hashcat': {'package': 'hashcat', 'repo': 'epel'},
        'aircrack-ng': {'package': 'aircrack-ng', 'repo': 'epel'},
    }

    def __init__(self, playbooks_dir: str = "/var/lib/jira-provisioner/playbooks"):
        """
        Initialize software installer.

        Args:
            playbooks_dir: Directory for generated playbooks
        """
        self.playbooks_dir = playbooks_dir
        os.makedirs(playbooks_dir, exist_ok=True)

    def install_software(self, spec: VMSpec) -> bool:
        """
        Install requested software on VM.

        Args:
            spec: VM specification with software list

        Returns:
            True if successful, False otherwise
        """
        if not spec.software_list:
            logger.info(f"No software requested for {spec.vm_name}")
            return True

        try:
            # Generate playbook
            playbook_path = self._generate_playbook(spec)

            # Generate inventory
            inventory_path = self._generate_inventory(spec)

            # Run playbook
            success = self._run_playbook(playbook_path, inventory_path, spec.ssh_key_path)

            return success

        except Exception as e:
            logger.error(f"Failed to install software on {spec.vm_name}: {e}")
            return False

    def _generate_playbook(self, spec: VMSpec) -> str:
        """Generate Ansible playbook for software installation."""
        # Categorize software
        packages = []
        pip_packages = []
        scripts = []
        repos_needed = set()

        for software in spec.software_list:
            software_lower = software.lower().strip()

            if software_lower in self.SECURITY_TOOLS:
                tool_info = self.SECURITY_TOOLS[software_lower]

                if 'package' in tool_info:
                    packages.append(tool_info['package'])
                    if 'repo' in tool_info and tool_info['repo'] != 'default':
                        repos_needed.add(tool_info['repo'])

                elif 'pip' in tool_info:
                    pip_packages.append(tool_info['pip'])

                elif 'script' in tool_info:
                    scripts.append(tool_info['script'])
            else:
                # Assume it's a package name
                packages.append(software)

        # Generate playbook
        playbook = {
            'name': f'Install software on {spec.vm_name}',
            'hosts': 'all',
            'become': True,
            'tasks': []
        }

        # Add EPEL repository if needed
        if 'epel' in repos_needed:
            playbook['tasks'].append({
                'name': 'Install EPEL repository',
                'ansible.builtin.dnf': {
                    'name': 'epel-release',
                    'state': 'present'
                }
            })

        # Add Docker repository if needed
        if 'docker-ce' in repos_needed:
            playbook['tasks'].append({
                'name': 'Add Docker repository',
                'ansible.builtin.yum_repository': {
                    'name': 'docker-ce',
                    'description': 'Docker CE Repository',
                    'baseurl': 'https://download.docker.com/linux/centos/9/$basearch/stable',
                    'gpgcheck': True,
                    'gpgkey': 'https://download.docker.com/linux/centos/gpg',
                    'enabled': True
                }
            })

        # Install packages
        if packages:
            playbook['tasks'].append({
                'name': 'Install requested packages',
                'ansible.builtin.dnf': {
                    'name': packages,
                    'state': 'present',
                    'update_cache': True
                }
            })

        # Install pip packages
        if pip_packages:
            playbook['tasks'].append({
                'name': 'Ensure pip is installed',
                'ansible.builtin.dnf': {
                    'name': 'python3-pip',
                    'state': 'present'
                }
            })

            playbook['tasks'].append({
                'name': 'Install Python packages',
                'ansible.builtin.pip': {
                    'name': pip_packages,
                    'state': 'present'
                }
            })

        # Run custom scripts
        for script in scripts:
            playbook['tasks'].append({
                'name': f'Run installation script: {script}',
                'ansible.builtin.shell': f'/usr/local/bin/{script}',
                'args': {
                    'creates': f'/var/lib/installed/{script}.done'
                }
            })

        # Start Docker if installed
        if 'docker' in spec.software_list or 'docker-ce' in packages:
            playbook['tasks'].append({
                'name': 'Start and enable Docker',
                'ansible.builtin.systemd': {
                    'name': 'docker',
                    'state': 'started',
                    'enabled': True
                }
            })

        # Save playbook
        playbook_path = os.path.join(self.playbooks_dir, f"{spec.vm_name}-install.yml")
        with open(playbook_path, 'w') as f:
            yaml.dump([playbook], f, default_flow_style=False)

        logger.info(f"Generated playbook: {playbook_path}")
        return playbook_path

    def _generate_inventory(self, spec: VMSpec) -> str:
        """Generate Ansible inventory for the VM."""
        inventory = f"""[vm]
{spec.vm_name} ansible_host={spec.ip_address}

[vm:vars]
ansible_user={spec.ssh_user}
ansible_ssh_private_key_file={spec.ssh_key_path}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
"""

        inventory_path = os.path.join(self.playbooks_dir, f"{spec.vm_name}-inventory.ini")
        with open(inventory_path, 'w') as f:
            f.write(inventory)

        logger.info(f"Generated inventory: {inventory_path}")
        return inventory_path

    def _run_playbook(
        self,
        playbook_path: str,
        inventory_path: str,
        ssh_key_path: str
    ) -> bool:
        """
        Run Ansible playbook.

        Args:
            playbook_path: Path to playbook
            inventory_path: Path to inventory
            ssh_key_path: Path to SSH private key

        Returns:
            True if successful, False otherwise
        """
        cmd = [
            "ansible-playbook",
            "-i", inventory_path,
            playbook_path,
            "-v"
        ]

        env = os.environ.copy()
        env['ANSIBLE_HOST_KEY_CHECKING'] = 'False'

        logger.info(f"Running playbook: {playbook_path}")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=env
        )

        if result.returncode == 0:
            logger.info(f"Playbook executed successfully")
            return True
        else:
            logger.error(f"Playbook failed: {result.stderr}")
            return False

    def wait_for_vm_ready(self, spec: VMSpec, timeout: int = 300) -> bool:
        """
        Wait for VM to be ready for Ansible.

        Args:
            spec: VM specification
            timeout: Timeout in seconds

        Returns:
            True if VM is ready, False if timeout
        """
        import time

        start_time = time.time()

        while time.time() - start_time < timeout:
            # Try to ping VM via Ansible
            cmd = [
                "ansible",
                "-i", f"{spec.ip_address},",
                "-u", spec.ssh_user,
                "--private-key", spec.ssh_key_path,
                "-m", "ping",
                "-o",
                "StrictHostKeyChecking=no",
                "all"
            ]

            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0 and "SUCCESS" in result.stdout:
                logger.info(f"VM {spec.vm_name} is ready")
                return True

            time.sleep(10)

        logger.error(f"VM {spec.vm_name} not ready after {timeout}s")
        return False

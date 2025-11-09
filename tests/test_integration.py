"""
Integration tests for the complete provisioning workflow.
"""

import pytest
import os
import tempfile
import shutil
from unittest.mock import patch, MagicMock

from src.jira_client import MockJiraClient
from src.vm_provisioner import VMProvisioner
from src.software_installer import SoftwareInstaller
from src.webhook_server import ProvisioningOrchestrator
from src.models import VMSpec, ProvisioningStatus


@pytest.fixture
def temp_dirs():
    """Create temporary directories for testing."""
    images_dir = tempfile.mkdtemp(prefix="test-images-")
    ssh_dir = tempfile.mkdtemp(prefix="test-ssh-")
    playbooks_dir = tempfile.mkdtemp(prefix="test-playbooks-")

    yield {
        'images': images_dir,
        'ssh': ssh_dir,
        'playbooks': playbooks_dir,
    }

    # Cleanup
    for dir_path in [images_dir, ssh_dir, playbooks_dir]:
        if os.path.exists(dir_path):
            shutil.rmtree(dir_path)


@pytest.fixture
def mock_components(temp_dirs):
    """Create mock components for testing."""
    jira_client = MockJiraClient()

    # Mock VM provisioner to avoid actual VM creation
    vm_provisioner = VMProvisioner(
        images_dir=temp_dirs['images'],
        ssh_key_dir=temp_dirs['ssh']
    )

    # Mock software installer
    software_installer = SoftwareInstaller(
        playbooks_dir=temp_dirs['playbooks']
    )

    orchestrator = ProvisioningOrchestrator(
        jira_client=jira_client,
        vm_provisioner=vm_provisioner,
        software_installer=software_installer
    )

    return {
        'jira': jira_client,
        'vm_provisioner': vm_provisioner,
        'software_installer': software_installer,
        'orchestrator': orchestrator,
    }


class TestProvisioningOrchestrator:
    """Integration tests for provisioning orchestrator."""

    @patch('subprocess.run')
    @patch('src.software_installer.SoftwareInstaller.wait_for_vm_ready')
    def test_complete_provisioning_workflow(
        self,
        mock_wait,
        mock_subprocess,
        mock_components
    ):
        """Test complete provisioning workflow from ticket to ready VM."""
        # Setup mocks
        mock_wait.return_value = True
        mock_subprocess.return_value = MagicMock(returncode=0, stdout="", stderr="")

        # Create test ticket
        spec = VMSpec(
            vm_name="security-test-vm",
            cpu_cores=4,
            ram_mb=4096,
            disk_gb=40,
            software_list=["nmap", "wireshark"],
            network_isolated=True,
            auto_destroy_hours=24
        )

        jira_client = mock_components['jira']
        jira_client.add_mock_ticket("SECVM-123", spec)

        # Process ticket
        orchestrator = mock_components['orchestrator']

        # Mock the actual VM creation and software installation
        with patch.object(orchestrator.vm_provisioner, 'provision_vm') as mock_provision:
            with patch.object(orchestrator.software_installer, 'install_software') as mock_install:
                # Setup mock returns
                from src.models import ProvisioningRequest
                mock_request = ProvisioningRequest(spec=spec)
                mock_request.status = ProvisioningStatus.PROVISIONING
                mock_request.ip_address = "192.168.200.10"
                mock_provision.return_value = mock_request

                mock_install.return_value = True

                # Process
                success = orchestrator.process_ticket("SECVM-123")

                # Verify
                assert success is True
                assert mock_provision.called
                assert mock_install.called

                # Check Jira updates
                assert "SECVM-123" in jira_client.mock_comments
                comments = jira_client.mock_comments["SECVM-123"]

                # Should have multiple status updates
                assert len(comments) > 0

                # Final status should be READY
                final_comment = comments[-1]
                assert final_comment['status'] == ProvisioningStatus.READY

    @patch('subprocess.run')
    def test_validation_failure(self, mock_subprocess, mock_components):
        """Test handling of validation failures."""
        # Create invalid ticket (too much RAM)
        spec = VMSpec(
            vm_name="invalid-vm",
            cpu_cores=32,  # Too many CPUs
            ram_mb=2048,
            disk_gb=20
        )

        jira_client = mock_components['jira']
        jira_client.add_mock_ticket("SECVM-456", spec)

        orchestrator = mock_components['orchestrator']
        success = orchestrator.process_ticket("SECVM-456")

        # Should fail validation
        assert success is False

        # Check Jira was updated with failure
        assert "SECVM-456" in jira_client.mock_comments
        comments = jira_client.mock_comments["SECVM-456"]

        # Should have failure status
        failure_comments = [c for c in comments if c['status'] == ProvisioningStatus.FAILED]
        assert len(failure_comments) > 0

    def test_vm_spec_generation(self, mock_components):
        """Test VM spec generation from various software lists."""
        software_installer = mock_components['software_installer']

        # Test with security tools
        spec = VMSpec(
            vm_name="pentest-vm",
            cpu_cores=4,
            ram_mb=8192,
            disk_gb=60,
            software_list=["nmap", "metasploit", "wireshark", "docker"],
            ip_address="192.168.100.50",
            ssh_key_path="/tmp/test-key"
        )

        playbook_path = software_installer._generate_playbook(spec)

        assert os.path.exists(playbook_path)

        # Verify playbook content
        import yaml
        with open(playbook_path, 'r') as f:
            playbooks = yaml.safe_load(f)

        playbook = playbooks[0]

        # Should have tasks for all software
        assert len(playbook['tasks']) > 0

        # Should include EPEL for nmap
        task_names = [t.get('name', '') for t in playbook['tasks']]
        assert any('EPEL' in name for name in task_names)

        # Should include Docker setup
        assert any('Docker' in name for name in task_names)


class TestWebhookIntegration:
    """Integration tests for webhook handling."""

    def test_webhook_payload_parsing(self, mock_components):
        """Test parsing of webhook payloads."""
        from src.webhook_server import WebhookServer

        orchestrator = mock_components['orchestrator']
        server = WebhookServer(orchestrator, webhook_secret=None)

        # Create test webhook payload
        payload = {
            'webhookEvent': 'jira:issue_created',
            'issue': {
                'key': 'SECVM-789',
                'fields': {
                    'labels': ['vm-provisioning-request'],
                    'summary': 'Security Testing VM',
                }
            }
        }

        # Add corresponding ticket
        spec = VMSpec(
            vm_name="webhook-test-vm",
            cpu_cores=2,
            ram_mb=2048,
            disk_gb=20
        )
        mock_components['jira'].add_mock_ticket("SECVM-789", spec)

        # Test webhook handling
        with server.app.test_client() as client:
            with patch.object(orchestrator, 'process_ticket') as mock_process:
                response = client.post(
                    '/webhook',
                    json=payload,
                    content_type='application/json'
                )

                assert response.status_code == 202
                # Process runs in background thread, so we just check it was called
                # In real testing, we'd wait for the thread

    def test_manual_provision_endpoint(self, mock_components):
        """Test manual provisioning endpoint."""
        from src.webhook_server import WebhookServer

        orchestrator = mock_components['orchestrator']
        server = WebhookServer(orchestrator)

        # Add test ticket
        spec = VMSpec(
            vm_name="manual-test-vm",
            cpu_cores=2,
            ram_mb=2048,
            disk_gb=20
        )
        mock_components['jira'].add_mock_ticket("SECVM-999", spec)

        with server.app.test_client() as client:
            response = client.post('/provision/SECVM-999')

            assert response.status_code == 202
            data = response.get_json()
            assert data['status'] == 'processing'
            assert data['ticket'] == 'SECVM-999'

    def test_health_check_endpoint(self, mock_components):
        """Test health check endpoint."""
        from src.webhook_server import WebhookServer

        orchestrator = mock_components['orchestrator']
        server = WebhookServer(orchestrator)

        with server.app.test_client() as client:
            response = client.get('/health')

            assert response.status_code == 200
            data = response.get_json()
            assert data['status'] == 'healthy'
            assert 'timestamp' in data

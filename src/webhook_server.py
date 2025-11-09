"""
Flask webhook server for Jira integration.
"""

import logging
import os
import hmac
import hashlib
import threading
from datetime import datetime
from flask import Flask, request, jsonify
from typing import Optional

from .jira_client import JiraClient, MockJiraClient
from .vm_provisioner import VMProvisioner
from .software_installer import SoftwareInstaller
from .models import ProvisioningStatus

logger = logging.getLogger(__name__)

app = Flask(__name__)


class ProvisioningOrchestrator:
    """Orchestrates VM provisioning workflow."""

    def __init__(
        self,
        jira_client: JiraClient,
        vm_provisioner: VMProvisioner,
        software_installer: SoftwareInstaller
    ):
        """Initialize orchestrator."""
        self.jira_client = jira_client
        self.vm_provisioner = vm_provisioner
        self.software_installer = software_installer

    def process_ticket(self, ticket_key: str) -> bool:
        """
        Process a Jira ticket and provision VM.

        Args:
            ticket_key: Jira ticket key

        Returns:
            True if successful, False otherwise
        """
        logger.info(f"Processing ticket: {ticket_key}")

        try:
            # Update status to validating
            self.jira_client.update_ticket_status(
                ticket_key,
                ProvisioningStatus.VALIDATING,
                "Starting VM provisioning process..."
            )

            # Parse ticket
            vm_spec = self.jira_client.parse_ticket(ticket_key)

            if not vm_spec:
                self.jira_client.update_ticket_status(
                    ticket_key,
                    ProvisioningStatus.FAILED,
                    "Failed to parse ticket. Please check the format."
                )
                return False

            # Validate spec
            is_valid, error = vm_spec.validate()

            if not is_valid:
                self.jira_client.update_ticket_status(
                    ticket_key,
                    ProvisioningStatus.FAILED,
                    f"Validation failed: {error}"
                )
                return False

            # Provision VM
            self.jira_client.update_ticket_status(
                ticket_key,
                ProvisioningStatus.PROVISIONING,
                f"Provisioning VM: {vm_spec.vm_name}"
            )

            request = self.vm_provisioner.provision_vm(vm_spec)

            if request.status == ProvisioningStatus.FAILED:
                self.jira_client.update_ticket_status(
                    ticket_key,
                    ProvisioningStatus.FAILED,
                    f"VM provisioning failed: {request.error_message}"
                )
                return False

            # Wait for VM to be ready
            self.jira_client.update_ticket_status(
                ticket_key,
                ProvisioningStatus.PROVISIONING,
                f"Waiting for VM to boot..."
            )

            vm_ready = self.software_installer.wait_for_vm_ready(vm_spec, timeout=300)

            if not vm_ready:
                self.jira_client.update_ticket_status(
                    ticket_key,
                    ProvisioningStatus.FAILED,
                    "VM failed to boot or respond to SSH"
                )
                # Clean up
                self.vm_provisioner.destroy_vm(vm_spec.vm_name)
                return False

            # Install software
            if vm_spec.software_list:
                self.jira_client.update_ticket_status(
                    ticket_key,
                    ProvisioningStatus.INSTALLING_SOFTWARE,
                    f"Installing {len(vm_spec.software_list)} software packages..."
                )

                software_success = self.software_installer.install_software(vm_spec)

                if not software_success:
                    self.jira_client.update_ticket_status(
                        ticket_key,
                        ProvisioningStatus.FAILED,
                        "Software installation failed. VM is running but some packages may be missing."
                    )
                    # Don't destroy VM - it might still be useful

            # Update ticket with success
            vm_info = {
                'VM Name': vm_spec.vm_name,
                'IP Address': vm_spec.ip_address,
                'SSH Command': f"ssh -i {vm_spec.ssh_key_path} {vm_spec.ssh_user}@{vm_spec.ip_address}",
                'SSH User': vm_spec.ssh_user,
                'SSH Key Path': vm_spec.ssh_key_path,
                'CPU Cores': str(vm_spec.cpu_cores),
                'RAM (MB)': str(vm_spec.ram_mb),
                'Disk (GB)': str(vm_spec.disk_gb),
                'Software Installed': ', '.join(vm_spec.software_list) if vm_spec.software_list else 'None',
                'Network Isolated': 'Yes' if vm_spec.network_isolated else 'No',
                'Auto Destroy': f"{vm_spec.auto_destroy_hours} hours" if vm_spec.auto_destroy_hours else 'Manual',
            }

            self.jira_client.update_ticket_status(
                ticket_key,
                ProvisioningStatus.READY,
                f"VM {vm_spec.vm_name} is ready for use!",
                vm_info
            )

            logger.info(f"Successfully provisioned VM for ticket {ticket_key}")
            return True

        except Exception as e:
            logger.error(f"Failed to process ticket {ticket_key}: {e}", exc_info=True)
            self.jira_client.update_ticket_status(
                ticket_key,
                ProvisioningStatus.FAILED,
                f"Unexpected error: {str(e)}"
            )
            return False


class WebhookServer:
    """Flask webhook server."""

    def __init__(
        self,
        orchestrator: ProvisioningOrchestrator,
        webhook_secret: Optional[str] = None
    ):
        """
        Initialize webhook server.

        Args:
            orchestrator: Provisioning orchestrator
            webhook_secret: Secret for webhook verification
        """
        self.orchestrator = orchestrator
        self.webhook_secret = webhook_secret
        self.app = app

        # Register routes
        self.app.add_url_rule('/webhook', 'webhook', self.handle_webhook, methods=['POST'])
        self.app.add_url_rule('/health', 'health', self.health_check, methods=['GET'])
        self.app.add_url_rule('/provision/<ticket_key>', 'provision', self.manual_provision, methods=['POST'])

    def verify_signature(self, payload: bytes, signature: str) -> bool:
        """
        Verify webhook signature.

        Args:
            payload: Request payload
            signature: Signature from header

        Returns:
            True if valid, False otherwise
        """
        if not self.webhook_secret:
            return True

        expected_signature = hmac.new(
            self.webhook_secret.encode(),
            payload,
            hashlib.sha256
        ).hexdigest()

        return hmac.compare_digest(signature, expected_signature)

    def handle_webhook(self):
        """Handle incoming webhook from Jira."""
        try:
            # Verify signature if configured
            signature = request.headers.get('X-Hub-Signature-256', '')

            if self.webhook_secret and not self.verify_signature(request.data, signature.replace('sha256=', '')):
                logger.warning("Invalid webhook signature")
                return jsonify({'error': 'Invalid signature'}), 401

            # Parse webhook payload
            data = request.json

            webhook_event = data.get('webhookEvent', '')
            issue_key = data.get('issue', {}).get('key', '')

            logger.info(f"Received webhook: {webhook_event} for {issue_key}")

            # Only process issue creation or specific events
            if webhook_event in ['jira:issue_created', 'jira:issue_updated']:
                # Check if issue has the provisioning label
                labels = data.get('issue', {}).get('fields', {}).get('labels', [])

                if 'vm-provisioning-request' in labels:
                    # Process in background thread
                    thread = threading.Thread(
                        target=self.orchestrator.process_ticket,
                        args=(issue_key,)
                    )
                    thread.start()

                    return jsonify({'status': 'processing', 'ticket': issue_key}), 202

            return jsonify({'status': 'ignored'}), 200

        except Exception as e:
            logger.error(f"Webhook error: {e}", exc_info=True)
            return jsonify({'error': str(e)}), 500

    def manual_provision(self, ticket_key: str):
        """Manually trigger provisioning for a ticket."""
        try:
            # Process in background thread
            thread = threading.Thread(
                target=self.orchestrator.process_ticket,
                args=(ticket_key,)
            )
            thread.start()

            return jsonify({'status': 'processing', 'ticket': ticket_key}), 202

        except Exception as e:
            logger.error(f"Manual provision error: {e}", exc_info=True)
            return jsonify({'error': str(e)}), 500

    def health_check(self):
        """Health check endpoint."""
        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
        }), 200

    def run(self, host: str = '0.0.0.0', port: int = 5000, debug: bool = False):
        """
        Run the webhook server.

        Args:
            host: Host to bind to
            port: Port to bind to
            debug: Enable debug mode
        """
        logger.info(f"Starting webhook server on {host}:{port}")
        self.app.run(host=host, port=port, debug=debug)

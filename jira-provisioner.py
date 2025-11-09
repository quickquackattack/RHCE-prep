#!/usr/bin/env python3
"""
Jira VM Provisioning Service

Main entry point for the Jira-integrated VM provisioning system.
"""

import os
import sys
import logging
import argparse
from dotenv import load_dotenv

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from src.jira_client import JiraClient, MockJiraClient
from src.vm_provisioner import VMProvisioner
from src.software_installer import SoftwareInstaller
from src.webhook_server import ProvisioningOrchestrator, WebhookServer


def setup_logging(log_level: str = "INFO", log_file: str = None):
    """Setup logging configuration."""
    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'

    handlers = [logging.StreamHandler()]

    if log_file:
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        handlers.append(logging.FileHandler(log_file))

    logging.basicConfig(
        level=getattr(logging, log_level.upper()),
        format=log_format,
        handlers=handlers
    )


def create_jira_client(config: dict) -> JiraClient:
    """Create Jira client from configuration."""
    if config.get('MOCK_JIRA', 'false').lower() == 'true':
        logging.info("Using Mock Jira client")
        return MockJiraClient()

    return JiraClient(
        url=config['JIRA_URL'],
        username=config['JIRA_USERNAME'],
        api_token=config['JIRA_API_TOKEN'],
        project_key=config['JIRA_PROJECT_KEY']
    )


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Jira VM Provisioning Service')

    parser.add_argument(
        '--config',
        default='.env',
        help='Path to configuration file (default: .env)'
    )

    parser.add_argument(
        '--mode',
        choices=['webhook', 'poll', 'once'],
        default='webhook',
        help='Operation mode: webhook (server), poll (periodic), once (single run)'
    )

    parser.add_argument(
        '--ticket',
        help='Specific ticket to process (for once mode)'
    )

    args = parser.parse_args()

    # Load configuration
    config_path = args.config
    if not os.path.exists(config_path):
        config_path = 'config/jira-provisioner.env'

    if os.path.exists(config_path):
        load_dotenv(config_path)
    else:
        logging.warning(f"Config file not found: {config_path}")

    # Setup logging
    log_level = os.getenv('LOG_LEVEL', 'INFO')
    log_file = os.getenv('LOG_FILE')
    setup_logging(log_level, log_file)

    logger = logging.getLogger(__name__)
    logger.info("Starting Jira VM Provisioning Service")

    # Load configuration
    config = {
        'JIRA_URL': os.getenv('JIRA_URL'),
        'JIRA_USERNAME': os.getenv('JIRA_USERNAME'),
        'JIRA_API_TOKEN': os.getenv('JIRA_API_TOKEN'),
        'JIRA_PROJECT_KEY': os.getenv('JIRA_PROJECT_KEY', 'SECVM'),
        'WEBHOOK_SECRET': os.getenv('WEBHOOK_SECRET'),
        'WEBHOOK_PORT': int(os.getenv('WEBHOOK_PORT', '5000')),
        'WEBHOOK_HOST': os.getenv('WEBHOOK_HOST', '0.0.0.0'),
        'IMAGES_DIR': os.getenv('IMAGES_DIR', '/var/lib/libvirt/images/jira-vms'),
        'SSH_KEY_DIR': os.getenv('SSH_KEY_DIR', '/var/lib/jira-provisioner/ssh-keys'),
        'NETWORK_PREFIX': os.getenv('NETWORK_PREFIX', '192.168'),
        'MOCK_JIRA': os.getenv('MOCK_JIRA', 'false'),
    }

    # Create components
    try:
        jira_client = create_jira_client(config)

        vm_provisioner = VMProvisioner(
            images_dir=config['IMAGES_DIR'],
            network_prefix=config['NETWORK_PREFIX'],
            ssh_key_dir=config['SSH_KEY_DIR']
        )

        software_installer = SoftwareInstaller()

        orchestrator = ProvisioningOrchestrator(
            jira_client=jira_client,
            vm_provisioner=vm_provisioner,
            software_installer=software_installer
        )

    except Exception as e:
        logger.error(f"Failed to initialize components: {e}", exc_info=True)
        return 1

    # Run in specified mode
    if args.mode == 'once':
        # Process a single ticket
        if not args.ticket:
            logger.error("--ticket required for 'once' mode")
            return 1

        success = orchestrator.process_ticket(args.ticket)
        return 0 if success else 1

    elif args.mode == 'poll':
        # Poll for new tickets periodically
        import time
        import schedule

        def poll_tickets():
            logger.info("Polling for new tickets...")
            tickets = jira_client.get_pending_tickets()

            for ticket_key in tickets:
                logger.info(f"Processing pending ticket: {ticket_key}")
                orchestrator.process_ticket(ticket_key)

        # Schedule polling every 5 minutes
        schedule.every(5).minutes.do(poll_tickets)

        logger.info("Starting polling mode (every 5 minutes)")

        # Run initial poll
        poll_tickets()

        while True:
            schedule.run_pending()
            time.sleep(60)

    else:  # webhook mode
        # Start webhook server
        server = WebhookServer(
            orchestrator=orchestrator,
            webhook_secret=config.get('WEBHOOK_SECRET')
        )

        server.run(
            host=config['WEBHOOK_HOST'],
            port=config['WEBHOOK_PORT'],
            debug=(log_level == 'DEBUG')
        )

    return 0


if __name__ == '__main__':
    sys.exit(main())

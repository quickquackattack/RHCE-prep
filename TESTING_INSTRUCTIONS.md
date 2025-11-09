# Testing Instructions for Jira VM Provisioning System

This document provides step-by-step instructions for testing the Jira-integrated VM provisioning system.

## Prerequisites for Testing

```bash
# Install Python dependencies
pip3 install -r requirements.txt

# Or install specific test dependencies
pip3 install pytest pytest-mock pytest-flask jira flask python-dotenv pyyaml
```

## Test Modes

### 1. Unit Tests (No External Dependencies)

Test individual components in isolation:

```bash
# Run all unit tests
pytest tests/ -v

# Run specific test file
pytest tests/test_models.py -v
pytest tests/test_jira_client.py -v
pytest tests/test_software_installer.py -v

# Run with coverage
pytest --cov=src --cov-report=html --cov-report=term tests/

# View coverage report
firefox htmlcov/index.html
```

### 2. Integration Tests (Mock Jira)

Test complete workflow without real Jira:

```bash
# Run integration tests
pytest tests/test_integration.py -v

# Test with mock Jira
export MOCK_JIRA=true
python3 jira-provisioner.py --mode once --ticket TEST-123
```

### 3. Manual Testing (Interactive)

Use the interactive testing tool:

```bash
bash scripts/test-with-jira.sh
```

Options:
1. **Create test ticket** - Creates ticket in Jira (requires credentials)
2. **Process existing ticket** - Process a specific ticket
3. **Run webhook server** - Start server for webhook testing
4. **Test VM provisioning** - Test provisioning without Jira
5. **Run all tests** - Execute full test suite

### 4. Component Testing

#### Test Model Validation

```bash
python3 << 'EOF'
import sys
sys.path.insert(0, 'src')
from models import VMSpec

spec = VMSpec(
    vm_name="test-vm",
    cpu_cores=2,
    ram_mb=2048,
    disk_gb=20,
    software_list=["nmap", "wireshark"]
)

is_valid, error = spec.validate()
print(f"Valid: {is_valid}, Error: {error}")
print(f"VM: {spec.vm_name}, CPU: {spec.cpu_cores}, RAM: {spec.ram_mb}")

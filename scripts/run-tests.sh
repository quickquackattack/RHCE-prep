#!/bin/bash

# Test runner script

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Running Jira Provisioner Tests ===${NC}\n"

# Check if pytest is installed
if ! command -v pytest &> /dev/null; then
    echo -e "${RED}pytest not found. Installing dependencies...${NC}"
    pip3 install -r requirements.txt
fi

# Run tests
echo -e "\n${YELLOW}Running unit tests...${NC}"
pytest tests/test_models.py tests/test_jira_client.py tests/test_software_installer.py -v

echo -e "\n${YELLOW}Running integration tests...${NC}"
pytest tests/test_integration.py -v

# Generate coverage report
echo -e "\n${YELLOW}Generating coverage report...${NC}"
pytest --cov=src --cov-report=html --cov-report=term tests/

echo -e "\n${GREEN}=== Tests Complete ===${NC}"
echo -e "Coverage report available at: htmlcov/index.html"

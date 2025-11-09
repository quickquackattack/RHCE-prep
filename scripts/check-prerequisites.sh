#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Checking Prerequisites for Ansible Lab ===${NC}\n"

ERRORS=0
WARNINGS=0

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}[INFO] Not running as root. Some checks require sudo.${NC}"
fi

# Check CPU virtualization
echo -e "${YELLOW}Checking CPU virtualization support...${NC}"
if grep -E '(vmx|svm)' /proc/cpuinfo > /dev/null 2>&1; then
    VT_COUNT=$(grep -E -c '(vmx|svm)' /proc/cpuinfo)
    echo -e "${GREEN}✓ CPU virtualization supported ($VT_COUNT cores)${NC}"
else
    echo -e "${RED}✗ CPU virtualization NOT supported${NC}"
    echo -e "${RED}  Enable VT-x/AMD-V in BIOS${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check KVM module
echo -e "\n${YELLOW}Checking KVM modules...${NC}"
if lsmod | grep kvm > /dev/null 2>&1; then
    echo -e "${GREEN}✓ KVM modules loaded${NC}"
    lsmod | grep kvm | while read line; do
        echo -e "  ${GREEN}$line${NC}"
    done
else
    echo -e "${RED}✗ KVM modules NOT loaded${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check required commands
echo -e "\n${YELLOW}Checking required commands...${NC}"
REQUIRED_CMDS=(virsh virt-install qemu-img wget curl)
for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v $cmd > /dev/null 2>&1; then
        VERSION=$(command $cmd --version 2>&1 | head -1 || echo "version unknown")
        echo -e "${GREEN}✓ $cmd found${NC} ($VERSION)"
    else
        echo -e "${RED}✗ $cmd NOT found${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check for ISO creation tools
echo -e "\n${YELLOW}Checking ISO creation tools...${NC}"
if command -v genisoimage > /dev/null 2>&1; then
    echo -e "${GREEN}✓ genisoimage found${NC}"
elif command -v mkisofs > /dev/null 2>&1; then
    echo -e "${GREEN}✓ mkisofs found${NC}"
else
    echo -e "${RED}✗ Neither genisoimage nor mkisofs found${NC}"
    echo -e "${RED}  Install genisoimage package${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check libvirt service
echo -e "\n${YELLOW}Checking libvirt service...${NC}"
if systemctl is-active --quiet libvirtd 2>/dev/null; then
    echo -e "${GREEN}✓ libvirtd is running${NC}"
elif systemctl is-active --quiet virtqemud 2>/dev/null; then
    echo -e "${GREEN}✓ virtqemud is running (modular libvirt)${NC}"
else
    echo -e "${RED}✗ libvirt is NOT running${NC}"
    echo -e "${RED}  Run: sudo systemctl start libvirtd${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check available memory
echo -e "\n${YELLOW}Checking available memory...${NC}"
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
AVAIL_MEM=$(free -m | awk '/^Mem:/{print $7}')
REQUIRED_MEM=6144  # 6GB in MB

echo -e "  Total Memory: ${TOTAL_MEM} MB"
echo -e "  Available Memory: ${AVAIL_MEM} MB"
echo -e "  Required Memory: ${REQUIRED_MEM} MB"

if [ "$AVAIL_MEM" -ge "$REQUIRED_MEM" ]; then
    echo -e "${GREEN}✓ Sufficient memory available${NC}"
else
    echo -e "${YELLOW}⚠ Low memory (need 6GB+, have ${AVAIL_MEM}MB available)${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Check disk space
echo -e "\n${YELLOW}Checking disk space...${NC}"
LIBVIRT_DIR="/var/lib/libvirt/images"
if [ -d "$LIBVIRT_DIR" ]; then
    AVAIL_SPACE=$(df -BG "$LIBVIRT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    echo -e "  Available space in $LIBVIRT_DIR: ${AVAIL_SPACE}GB"

    if [ "$AVAIL_SPACE" -ge 50 ]; then
        echo -e "${GREEN}✓ Sufficient disk space${NC}"
    else
        echo -e "${YELLOW}⚠ Low disk space (need 50GB+, have ${AVAIL_SPACE}GB)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${YELLOW}⚠ $LIBVIRT_DIR does not exist yet${NC}"
fi

# Check network connectivity
echo -e "\n${YELLOW}Checking network connectivity...${NC}"
if ping -c 1 cloud.centos.org > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Internet connectivity OK${NC}"
else
    echo -e "${YELLOW}⚠ Cannot reach cloud.centos.org${NC}"
    echo -e "${YELLOW}  May affect image download${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Check user groups
echo -e "\n${YELLOW}Checking user permissions...${NC}"
if groups | grep -E 'libvirt|kvm' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ User in libvirt/kvm group${NC}"
else
    echo -e "${YELLOW}⚠ User not in libvirt/kvm group${NC}"
    echo -e "${YELLOW}  Add with: sudo usermod -aG libvirt $USER${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Summary
echo -e "\n${GREEN}=== Summary ===${NC}"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Ready to setup the lab.${NC}"
    echo -e "\nRun: ${GREEN}sudo bash scripts/setup-lab.sh${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found. Lab should work but may have issues.${NC}"
    echo -e "\nYou can try running: ${YELLOW}sudo bash scripts/setup-lab.sh${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found.${NC}"
    echo -e "${RED}Please fix the errors before setting up the lab.${NC}"
    exit 1
fi

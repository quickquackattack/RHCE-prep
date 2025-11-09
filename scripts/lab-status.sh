#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NETWORK_NAME="ansible-lab"
VMS=("control" "node1" "node2" "node3" "node4")

echo -e "${BLUE}=== Ansible Lab Status ===${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Note: Running without sudo. Some information may be limited.${NC}\n"
fi

# Network status
echo -e "${YELLOW}Network Status:${NC}"
if virsh net-info "$NETWORK_NAME" &> /dev/null; then
    NET_STATE=$(virsh net-info "$NETWORK_NAME" | grep "Active" | awk '{print $2}')
    NET_AUTO=$(virsh net-info "$NETWORK_NAME" | grep "Autostart" | awk '{print $2}')

    if [ "$NET_STATE" == "yes" ]; then
        echo -e "  Network: ${GREEN}$NETWORK_NAME (Active)${NC}"
    else
        echo -e "  Network: ${RED}$NETWORK_NAME (Inactive)${NC}"
    fi
    echo -e "  Autostart: $NET_AUTO"

    echo -e "\n${YELLOW}DHCP Leases:${NC}"
    virsh net-dhcp-leases "$NETWORK_NAME" 2>/dev/null | grep -v "^$" || echo "  No active leases"
else
    echo -e "  ${RED}Network '$NETWORK_NAME' not found${NC}"
fi

# VM status
echo -e "\n${YELLOW}Virtual Machines:${NC}"
printf "  %-10s %-10s %-8s %-8s %-15s\n" "NAME" "STATE" "MEMORY" "VCPUS" "IP ADDRESS"
printf "  %-10s %-10s %-8s %-8s %-15s\n" "----" "-----" "------" "-----" "----------"

for vm_name in "${VMS[@]}"; do
    if virsh dominfo "$vm_name" &> /dev/null; then
        STATE=$(virsh domstate "$vm_name")
        MEMORY=$(virsh dominfo "$vm_name" | grep "Used memory" | awk '{print $3 " " $4}')
        VCPUS=$(virsh dominfo "$vm_name" | grep "CPU(s)" | awk '{print $2}')

        # Get IP address
        IP=$(virsh net-dhcp-leases "$NETWORK_NAME" 2>/dev/null | grep "$vm_name" | awk '{print $5}' | cut -d'/' -f1)
        [ -z "$IP" ] && IP="N/A"

        if [ "$STATE" == "running" ]; then
            printf "  %-10s ${GREEN}%-10s${NC} %-8s %-8s %-15s\n" "$vm_name" "$STATE" "$MEMORY" "$VCPUS" "$IP"
        else
            printf "  %-10s ${RED}%-10s${NC} %-8s %-8s %-15s\n" "$vm_name" "$STATE" "$MEMORY" "$VCPUS" "$IP"
        fi
    else
        printf "  %-10s ${RED}%-10s${NC} %-8s %-8s %-15s\n" "$vm_name" "not found" "-" "-" "-"
    fi
done

# SSH connectivity test
echo -e "\n${YELLOW}SSH Connectivity:${NC}"
SSH_KEY="$HOME/.ssh/ansible-lab"

if [ ! -f "$SSH_KEY" ]; then
    echo -e "  ${RED}SSH key not found at $SSH_KEY${NC}"
else
    echo -e "  SSH Key: ${GREEN}Found${NC}"

    for vm_name in "${VMS[@]}"; do
        IP=$(virsh net-dhcp-leases "$NETWORK_NAME" 2>/dev/null | grep "$vm_name" | awk '{print $5}' | cut -d'/' -f1)

        if [ -n "$IP" ]; then
            if timeout 2 ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o ConnectTimeout=2 ansible@"$IP" "echo 1" &> /dev/null; then
                echo -e "  $vm_name ($IP): ${GREEN}✓ Connected${NC}"
            else
                echo -e "  $vm_name ($IP): ${RED}✗ Cannot connect${NC}"
            fi
        fi
    done
fi

# Ansible test
echo -e "\n${YELLOW}Ansible Status:${NC}"
if [ -f "ansible/inventory.ini" ]; then
    echo -e "  Inventory: ${GREEN}Found${NC}"

    if command -v ansible &> /dev/null; then
        echo -e "  Ansible: ${GREEN}Installed${NC}"

        # Quick ping test
        cd ansible 2>/dev/null
        if ansible all -m ping -o 2>/dev/null | grep -q "SUCCESS"; then
            REACHABLE=$(ansible all -m ping -o 2>/dev/null | grep -c "SUCCESS")
            echo -e "  Ping test: ${GREEN}$REACHABLE/5 hosts reachable${NC}"
        else
            echo -e "  Ping test: ${RED}Failed${NC}"
        fi
        cd - > /dev/null 2>&1
    else
        echo -e "  Ansible: ${YELLOW}Not installed${NC}"
    fi
else
    echo -e "  Inventory: ${RED}Not found${NC}"
fi

# Resource usage
echo -e "\n${YELLOW}Host Resources:${NC}"
TOTAL_MEM=$(free -h | awk '/^Mem:/{print $2}')
USED_MEM=$(free -h | awk '/^Mem:/{print $3}')
FREE_MEM=$(free -h | awk '/^Mem:/{print $4}')
echo -e "  Memory: $USED_MEM used / $TOTAL_MEM total ($FREE_MEM free)"

LOAD=$(uptime | awk -F'load average:' '{print $2}')
echo -e "  Load average:$LOAD"

# Disk space
LIBVIRT_DIR="/var/lib/libvirt/images"
if [ -d "$LIBVIRT_DIR" ]; then
    DISK_INFO=$(df -h "$LIBVIRT_DIR" | awk 'NR==2 {print $3 " used / " $2 " total (" $5 " used)"}')
    echo -e "  Disk ($LIBVIRT_DIR): $DISK_INFO"
fi

echo -e "\n${BLUE}=== End Status Report ===${NC}"

# Quick actions
echo -e "\n${YELLOW}Quick Actions:${NC}"
echo -e "  Start all VMs:  ${GREEN}sudo virsh start control && sudo virsh start node{1..4}${NC}"
echo -e "  Stop all VMs:   ${GREEN}sudo virsh shutdown control node1 node2 node3 node4${NC}"
echo -e "  Test Ansible:   ${GREEN}cd ansible && ansible all -m ping${NC}"
echo -e "  SSH to control: ${GREEN}ssh -i ~/.ssh/ansible-lab ansible@192.168.100.10${NC}"

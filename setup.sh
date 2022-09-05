#!/bin/bash

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

echo "Running setup script. Turning off Linux NUMA."

# Do not allow Linux NUMA to move data around
service numad stop
echo 0 > /proc/sys/kernel/numa_balancing

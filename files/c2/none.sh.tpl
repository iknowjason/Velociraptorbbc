#!/bin/bash
# Custom bootstrap script for custom C2 

set -e
exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Variables

# Start here
echo "Start bootstrap script for C2"

# Initial packages
echo "Installing initial packages"
sudo apt-get update -y
sudo apt-get install net-tools -y
sudo apt-get install unzip -y

# Install Custom Commands here

echo "End of bootstrap script"

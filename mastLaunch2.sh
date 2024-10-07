#!/bin/bash

# Variables
SERVER="172.16.16.30"  # Replace with your server's address
USER="plinktern"  # Replace with your username on the server
SCRIPT_PATH="mast.sh"  # Local script path
REMOTE_PATH="/home/$USER/mast.sh"  # Remote script path
REMOTE_PW="HPCCrulez!"

echo "SCPing"
sshpass -p "$REMOTE_PW" scp -O "$SCRIPT_PATH" "$USER@$SERVER:$REMOTE_PATH"

# Run the script with sudo
echo "Running the script on the server..."
sshpass -p "$REMOTE_PW" ssh -o "StrictHostKeyChecking=no" -t "$USER@$SERVER" "sudo bash $REMOTE_PATH | tee script.txt"

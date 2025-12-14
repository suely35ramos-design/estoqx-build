#!/bin/bash

# Configuration
APP_DIR="/var/www/estoqx-simple"

# Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Starting Application Update..."

# 1. Check Directory
if [ ! -d "$APP_DIR" ]; then
    echo "Error: Application directory $APP_DIR does not exist."
    echo "Please run deploy.sh first to install the application."
    exit 1
fi

# 2. Pull Changes
echo "Pulling latest changes from git..."
cd $APP_DIR
git fetch origin
git reset --hard origin/main

# 3. Rebuild
echo "Installing dependencies..."
npm install

echo "Building application..."
npm run build

# 4. Reload Nginx
echo "Reloading Nginx..."
systemctl reload nginx

# 5. DB Migration Requirement Check
echo "----------------------------------------------"
echo "Update Complete!"
echo "----------------------------------------------"
echo "NOTE: If this update includes database changes, remember to run migrations manually or check documents."
echo "If using Supabase, check the 'supabase/migrations' folder."
echo "----------------------------------------------"
echo "Done."

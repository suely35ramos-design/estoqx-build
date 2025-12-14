#!/bin/bash

# Configuration
DB_NAME="estoqx"
DB_USER="estoqx_user"
# Generate a random password if not provided
DB_PASS="${DB_PASS:-$(openssl rand -base64 12)}"
SCHEMA_FILE="full_schema.sql"

# Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Starting Database Deployment..."

# 1. Install PostgreSQL
echo "Installing PostgreSQL..."
apt update
apt install -y postgresql postgresql-contrib

# 2. Start PostgreSQL
echo "Starting PostgreSQL service..."
systemctl enable postgresql
systemctl start postgresql

# 3. Configure User and Database
echo "Configuring Database and User..."
# Switch to postgres user to run psql commands
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" || echo "User might already be created."
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" || echo "Database might already be created."
sudo -u postgres psql -c "ALTER USER $DB_USER CREATEDB;" # Allow to create extensions if needed

# 4. Import Schema
if [ -f "$SCHEMA_FILE" ]; then
    echo "Importing Schema from $SCHEMA_FILE..."
    # We run this as superuser (postgres) because we are creating schemas and extensions
    sudo -u postgres psql -d $DB_NAME -f $SCHEMA_FILE
else
    echo "Error: Schema file $SCHEMA_FILE not found!"
    exit 1
fi

# 5. Output Credentials
echo ""
echo "=============================================="
echo "Deployment Complete!"
echo "Database: $DB_NAME"
echo "User:     $DB_USER"
echo "Password: $DB_PASS"
echo "=============================================="
echo "Save these credentials for your application configuration."
echo ""

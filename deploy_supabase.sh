#!/bin/bash

# Configuration
SUPABASE_DIR="/opt/estoqx-supabase"
REPO_URL="https://github.com/suely35ramos-design/estoqx-simple.git"
# Migration directory path relative to the repo root
MIGRATION_PATH="supabase/migrations"

# Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Starting Supabase Docker Deployment..."

# 1. Install Docker & Docker Compose
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    apt update
    apt install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "Docker is already installed."
fi

# 2. Setup Directory
echo "Setting up $SUPABASE_DIR..."
mkdir -p $SUPABASE_DIR
# Assuming we are running this script from the estoqx-simple repo:
# Copy the supabase-docker content to the target dir
cp -r ./supabase-docker/* $SUPABASE_DIR/

# 3. Generate Secrets (if .env is using default placeholders)
ENV_FILE="$SUPABASE_DIR/.env"
if grep -q "your-super-secret-and-long-postgres-password" "$ENV_FILE"; then
    echo "Generating new secrets..."
    
    # Generate random tokens
    DB_PASS=$(openssl rand -base64 24 | tr -d '/+' | cut -c1-32)
    JWT_SECRET=$(openssl rand -base64 32 | tr -d '/+' | cut -c1-40)
    ANON_KEY=$(openssl rand -base64 32 | tr -d '/+' | cut -c1-40) # NOTE: Real anon keys are JWTs signed with the secret.
    SERVICE_KEY=$(openssl rand -base64 32 | tr -d '/+' | cut -c1-40) # NOTE: Real service keys are JWTs signed with the secret.
    
    # WARNING: To generate REAL valid JWTs for Anon/Service keys, we need a JWT generator. 
    # Since we don't have python-jwt or similar, we will invoke a node script if available or warn user.
    # For now, we will assume the user MUST generate these or we use a basic placeholder if this is just a test.
    # Ideally, Supabase auth won't work correctly without VALID JWTs signed by the JWT_SECRET.
    
    echo "---------------------------------------------------------"
    echo "IMPORTANT: You need valid JWT tokens for ANON_KEY and SERVICE_KEY."
    echo "Please visit https://jwt.io/ or use a tool to generate tokens signed with your JWT_SECRET."
    echo "For this script, we will set random strings, but AUTH WILL FAIL until executed properly."
    echo "---------------------------------------------------------"

    sed -i "s/your-super-secret-and-long-postgres-password/$DB_PASS/" "$ENV_FILE"
    sed -i "s/super-secret-jwt-token-with-at-least-32-characters-long/$JWT_SECRET/" "$ENV_FILE"
    # Replacing placeholders
    sed -i "s/your-anon-key-generated-using-jwt-secret/$ANON_KEY/" "$ENV_FILE"
    sed -i "s/your-service-role-key-generated-using-jwt-secret/$SERVICE_KEY/" "$ENV_FILE"
fi

# 4. Start Stack
echo "Starting Supabase Stack..."
cd $SUPABASE_DIR
docker compose up -d

# 5. Apply Migrations
echo "Waiting for DB to be healthy..."
sleep 20 # Simple wait, ideally loop checking health

echo "Applying Migrations..."
# We need to find the migration files. We'll iterate over the files in the repo's migration folder.
# This assumes the script is run from the repo root.
REPO_MIGRATION_DIR="$(pwd)/$MIGRATION_PATH"

if [ -d "$REPO_MIGRATION_DIR" ]; then
    for sql_file in "$REPO_MIGRATION_DIR"/*.sql; do
        echo "Executing $sql_file..."
        docker compose exec -T db psql -U postgres -d postgres < "$sql_file"
    done
else
    echo "Migration directory not found at $REPO_MIGRATION_DIR"
fi

echo "Supabase Deployment Complete!"
echo "Studio API: http://$(hostname -I | awk '{print $1}'):8000"

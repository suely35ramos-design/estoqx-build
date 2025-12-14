#!/bin/bash

# Define settings
REPO_URL="https://github.com/suely35ramos-design/estoqx-simple.git"
APP_DIR="/var/www/estoqx-simple"
# Ask for Domain
read -p "Enter Domain (default: localhost): " INPUT_DOMAIN
DOMAIN=${INPUT_DOMAIN:-localhost}

# Ask for Database Type
echo ""
echo "Select Database Deployment Type:"
echo "1) Local PostgreSQL (Native)"
echo "2) Supabase (Docker)"
read -p "Enter choice [1 or 2]: " DB_CHOICE

# Initialize DB Variables
DB_TYPE=""
DB_USER=""
DB_PASS=""

if [ "$DB_CHOICE" == "1" ]; then
    DB_TYPE="postgresql"
    # Ask for DB Credentials (for Local PG)
    read -p "Enter Database Username (default: estoqx_user): " INPUT_DB_USER
    DB_USER=${INPUT_DB_USER:-estoqx_user}
    read -s -p "Enter Database Password: " DB_PASS
    echo "" 
elif [ "$DB_CHOICE" == "2" ]; then
    DB_TYPE="supabase"
    echo "Supabase selected. Credentials will be managed by the Supabase script."
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Starting deployment for estoqx-simple..."

# 1. System Update
echo "Updating system..."
apt update && apt upgrade -y
apt install -y curl git unzip gnupg

# 2. Install Node.js v20
echo "Installing Node.js v20..."
if ! command -v node &> /dev/null; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
    apt update
    apt install -y nodejs
else
    echo "Node.js is already installed."
fi

# 3. Install Nginx
echo "Installing Nginx..."
apt install -y nginx
systemctl enable nginx
systemctl start nginx

# 4. Clone or Pull Repository
echo "Setting up application directory..."
if [ -d "$APP_DIR" ]; then
    echo "Directory exists. Pulling latest changes..."
    cd $APP_DIR
    git pull
    npm install
else
    echo "Cloning repository..."
    git clone $REPO_URL $APP_DIR
    cd $APP_DIR
    npm install
fi

# 5. Execute Database Deployment
echo "----------------------------------------------"
echo "Deploying Database ($DB_TYPE)..."
echo "----------------------------------------------"
chmod +x $APP_DIR/deploy/*.sh

if [ "$DB_TYPE" == "postgresql" ]; then
    # Export variables for deploy_db.sh to use
    export DB_USER=$DB_USER
    export DB_PASS=$DB_PASS
    # Run the script
    $APP_DIR/deploy/deploy_db.sh
elif [ "$DB_TYPE" == "supabase" ]; then
    # Run the supabase script
    $APP_DIR/deploy/deploy_supabase.sh
fi
echo ""

# 6. Build Application
echo "Building application..."
npm run build

# 7. Configure Nginx
echo "Configuring Nginx..."
cat > /etc/nginx/sites-available/estoqx-simple <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $APP_DIR/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /assets/ {
        expires 1y;
        add_header Cache-Control "public";
    }
}
EOF

# Enable the site and remove default if it exists
ln -sf /etc/nginx/sites-available/estoqx-simple /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and Reload Nginx
echo "Testing Nginx configuration..."
nginx -t
if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo "Nginx reloaded successfully."
else
    echo "Nginx configuration failed. Please check the errors."
fi

# 8. Set Permissions
chown -R www-data:www-data $APP_DIR
chmod -R 755 $APP_DIR

echo ""
echo "=============================================="
echo "Deployment Complete!"
echo "=============================================="
echo "Application URL:   http://$DOMAIN"
echo "App Directory:     $APP_DIR"
echo "BS Type:           $DB_TYPE"
echo "----------------------------------------------"

if [ "$DB_TYPE" == "postgresql" ]; then
    echo "Database Configuration (User Provided):"
    echo "DB User:           $DB_USER"
    echo "DB Password:       $DB_PASS"
elif [ "$DB_TYPE" == "supabase" ]; then
    echo "Supabase Configuration:"
    echo "Check the detailed output above for credentials."
    echo "Studio API:        http://$(curl -s ifconfig.me):8000"
fi
echo "=============================================="
echo "Done."

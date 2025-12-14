# Deployment Instructions

These instructions guide you through deploying the `estoqx-simple` application on a clean Debian 12 server using the provided `deploy.sh` script.

## prerequisites
- A server running **Debian 12**.
- Root access (login as `root`).

## Quick Start

1. **Connect to your server**:
   ```bash
   ssh root@your_server_ip
   ```

2. **Download the script**:
   (You can transfer the `deploy.sh` file to your server or create it there).
   If you want to create it directly on the server:
   ```bash
   nano deploy.sh
   # Paste the content of deploy.sh here, then Save (Ctrl+O) and Exit (Ctrl+X)
   ```

3. **Make the script executable**:
   ```bash
   chmod +x deploy.sh
   ```

4. **Run the script**:
   ```bash
   ./deploy.sh
   ```

5. **Deploy the Database** (Optional, if running locally):
   ```bash
   chmod +x deploy_db.sh
   ./deploy_db.sh
   ```
   *Note the generated username and password.*

## What the script does
1. **deploy.sh**:
    - Updates system and installs Node.js, Nginx, Git.
    - Clones/Pulls the repo.
    - Builds and serves the app.
2. **deploy_db.sh**:
    - Installs PostgreSQL.
    - Creates database `estoqx` and user `estoqx_user`.
    - Imports the schema compatible with Supabase (creates `auth` schema + app tables).

## After Deployment
- Access your application at `http://your_server_ip`.
- If you deployed the database, configure your application environment variables (Vite build) to point to this database if applicable (though this is a frontend app, it likely connects to Supabase/Backend via API URL).
- If you have a domain, update the `DOMAIN` variable in the script or edit `/etc/nginx/sites-available/estoqx-simple` manually after deployment.

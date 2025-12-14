# Supabase Deployment Instructions

This guide explains how to deploy the self-hosted Supabase stack for **estoqx** using Docker Compose.

## Prerequisites
- A server running **Debian 12**.
- **Root access**.
- At least **4GB RAM** recommended.

## Deployment Steps

1. **Transfer files**: Copy the entire project or clone the repo to your server.
2. **Review Configuration**:
   - Check `supabase-docker/docker-compose.yml`.
   - Check `supabase-docker/.env`.
3. **Run the Script**:
   ```bash
   chmod +x deploy_supabase.sh
   ./deploy_supabase.sh
   ```

## Important Notes on Security (JWT)
The `deploy_supabase.sh` script generates random strings for security keys (`ANON_KEY`, `SERVICE_ROLE_KEY`) if they are default.
**Refined Setup**:
- The `ANON_KEY` and `SERVICE_ROLE_KEY` **MUST** be valid JWTs signed with your `JWT_SECRET`.
- The script essentially puts placeholders. **You must generate valid tokens** to make Auth work correctly.
- Use [jwt.io](https://jwt.io/) or the Supabase CLI to generate these keys:
  ```bash
  # Example if you have node
  npm install -g jose
  # Script to sign tokens...
  ```
- Update the `.env` file in `/opt/estoqx-supabase/.env` with the correct keys and restart:
  ```bash
  cd /opt/estoqx-supabase
  docker compose up -d
  ```

## Accessing Studio
Supabase Studio (the dashboard) will be available at:
`http://<your-server-ip>:8000`

Default Database Credentials (unless changed):
- User: `postgres`
- Password: (Check the generated .env file)

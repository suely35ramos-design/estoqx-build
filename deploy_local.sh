#!/bin/bash

# Parar o script se houver erro
set -e

echo "=== Iniciando Script de Implantação para Debian 12 (Supabase Seguro) ==="

# Verifica se é root
if [ "$EUID" -ne 0 ]; then 
  echo "Por favor, execute como root (sudo ./deploy_local.sh)"
  exit
fi

# 0. Configurações Iniciais
read -p "Digite o domínio ou IP onde a aplicação será acessada (ex: 192.168.1.100 ou app.estoqx.com): " APP_DOMAIN
if [ -z "$APP_DOMAIN" ]; then
    echo "Domínio não informado. Usando 'localhost'."
    APP_DOMAIN="localhost"
fi
echo "Usando domínio: $APP_DOMAIN"

WORK_DIR="/opt/estoqx"

# 1. Atualizar e Instalar Dependências Gerais
echo "--- 1. Atualizando sistema e instalando dependências ---"
apt-get update && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg git wget unzip openssl

# 2. Instalar Node.js 20 (Necessário para gerar chaves JWT)
echo "--- 2. Instalando Node.js 20 ---"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
else
    echo "Node.js já instalado."
fi

# 3. Instalar Docker e Docker Compose
echo "--- 3. Instalando Docker e Docker Compose ---"
# Remover versões antigas
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove -y $pkg; done || true

# Configurar repositório e instalar
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl start docker
systemctl enable docker

# 4. Preparar Diretório e Gerar Chaves de Segurança
echo "--- 4. Preparando Diretório e Gerando Chaves Seguras ---"
mkdir -p $WORK_DIR
cd $WORK_DIR

# Script auxiliar Node.js para gerar chaves
cat <<EOF > generate_keys.js
const crypto = require('crypto');
const fs = require('fs');
const { execSync } = require('child_process');

try {
    require.resolve('jsonwebtoken');
} catch (e) {
    console.log('Instalando jsonwebtoken...');
    execSync('npm install jsonwebtoken', { stdio: 'inherit' });
}
const jwt = require('jsonwebtoken');

function generateSecret(length = 64) {
    return crypto.randomBytes(length).toString('hex');
}

function generatePassword(length = 16) {
    return crypto.randomBytes(length).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, length);
}

const jwtSecret = generateSecret(40); // JWT Secret
const anonKey = jwt.sign({ role: 'anon', iss: 'supabase' }, jwtSecret, { expiresIn: '10y' });
const serviceKey = jwt.sign({ role: 'service_role', iss: 'supabase' }, jwtSecret, { expiresIn: '10y' });

const keys = {
    POSTGRES_PASSWORD: generatePassword(20),
    JWT_SECRET: jwtSecret,
    ANON_KEY: anonKey,
    SERVICE_ROLE_KEY: serviceKey,
    SECRET_KEY_BASE: generateSecret(64),
    VAULT_ENC_KEY: crypto.randomBytes(16).toString('hex'), // precisa ser 32 chars hex
    PG_META_CRYPTO_KEY: generateSecret(32),
    DASHBOARD_PASSWORD: generatePassword(12)
};

fs.writeFileSync('generated_keys.json', JSON.stringify(keys, null, 2));
console.log('Chaves geradas com sucesso.');
EOF

# Inicializa um package.json temporário para instalar jsonwebtoken sem afetar nada
if [ ! -f package.json ]; then
    npm init -y > /dev/null
fi
npm install jsonwebtoken --no-save

echo "Gerando chaves..."
node generate_keys.js
# Ler chaves do JSON para variáveis bash
POSTGRES_PASSWORD=$(grep '"POSTGRES_PASSWORD":' generated_keys.json | cut -d '"' -f 4)
JWT_SECRET=$(grep '"JWT_SECRET":' generated_keys.json | cut -d '"' -f 4)
ANON_KEY=$(grep '"ANON_KEY":' generated_keys.json | cut -d '"' -f 4)
SERVICE_ROLE_KEY=$(grep '"SERVICE_ROLE_KEY":' generated_keys.json | cut -d '"' -f 4)
SECRET_KEY_BASE=$(grep '"SECRET_KEY_BASE":' generated_keys.json | cut -d '"' -f 4)
VAULT_ENC_KEY=$(grep '"VAULT_ENC_KEY":' generated_keys.json | cut -d '"' -f 4)
PG_META_CRYPTO_KEY=$(grep '"PG_META_CRYPTO_KEY":' generated_keys.json | cut -d '"' -f 4)
DASHBOARD_PASSWORD=$(grep '"DASHBOARD_PASSWORD":' generated_keys.json | cut -d '"' -f 4)

# 5. Configurar Supabase
echo "--- 5. Configurando Supabase ---"
if [ ! -d "supabase" ]; then
    git clone --depth 1 https://github.com/supabase/supabase.git supabase-repo
    mv supabase-repo/docker supabase
    rm -rf supabase-repo
fi

cd supabase

# Copiar example e substituir valores
cp .env.example .env

# Funcão para substituir no .env (cross-platform sed)
update_env() {
    key=$1
    val=$2
    # Escapar caracteres especiais para o sed
    escaped_val=$(printf '%s\n' "$val" | sed -e 's/[\/&]/\\&/g')
    sed -i "s|^$key=.*|$key=$escaped_val|" .env
}

echo "Aplicando configurações no .env..."
update_env "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
update_env "JWT_SECRET" "$JWT_SECRET"
update_env "ANON_KEY" "$ANON_KEY"
update_env "SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY"
update_env "SECRET_KEY_BASE" "$SECRET_KEY_BASE"
update_env "VAULT_ENC_KEY" "$VAULT_ENC_KEY"
update_env "PG_META_CRYPTO_KEY" "$PG_META_CRYPTO_KEY"
update_env "DASHBOARD_PASSWORD" "$DASHBOARD_PASSWORD"
update_env "DASHBOARD_USERNAME" "admin"

# Configurar URLs
update_env "API_EXTERNAL_URL" "http://$APP_DOMAIN:8000"
update_env "SUPABASE_PUBLIC_URL" "http://$APP_DOMAIN:8000"

# Habilitar Studio se necessário (geralmente habilitado por padrão)

echo "Iniciando Containers do Supabase..."
docker compose pull
docker compose up -d

# Aguardar Supabase
echo "Aguardando Supabase ficar operacional..."
until curl -s -f -o /dev/null "http://localhost:8000/rest/v1/"; do
  echo "Aguardando API do Supabase..."
  sleep 5
done
echo "Supabase Online!"

# Voltar para raiz
cd $WORK_DIR

# 6. Aplicação Estoqx
echo "--- 6. Configurando Aplicação Estoqx ---"
if [ -d "estoqx-simple" ]; then
    cd estoqx-simple
    git pull
else
    git clone https://github.com/suely35ramos-design/estoqx-simple.git
    cd estoqx-simple
fi

echo "Instalando dependências da aplicação..."
npm install

# Criar .env da aplicação com as chaves recém geradas
cat <<EOF > .env
VITE_SUPABASE_PROJECT_ID="local-docker"
VITE_SUPABASE_URL="http://$APP_DOMAIN:8000"
VITE_SUPABASE_PUBLISHABLE_KEY="$ANON_KEY"
EOF

# 7. Seed de Dados
echo "--- 7. Criando Usuários Iniciais (Seed) ---"
cat <<EOF > seed_deploy.js
const { createClient } = require('@supabase/supabase-js');
const supabase = createClient('http://localhost:8000', '$SERVICE_ROLE_KEY', {
  auth: { autoRefreshToken: false, persistSession: false }
});

const users = [
  { email: 'admin@estoqx.com', password: 'Teste123!', role: 'Admin' },
  { email: 'gestor@estoqx.com', password: 'Teste123!', role: 'Gestor' },
  { email: 'almoxarife@estoqx.com', password: 'Teste123!', role: 'Almoxarife' },
  { email: 'encarregado@estoqx.com', password: 'Teste123!', role: 'Encarregado' },
  { email: 'operador@estoqx.com', password: 'Teste123!', role: 'Operador' }
];

async function seed() {
  for (const user of users) {
    const { error } = await supabase.auth.admin.createUser({
      email: user.email,
      password: user.password,
      email_confirm: true,
      user_metadata: { role: user.role }
    });
    if (error) console.log(\`Erro ao criar \${user.email}: \${error.message}\`);
    else console.log(\`Criado: \${user.email}\`);
  }
}
seed();
EOF

node seed_deploy.js
rm seed_deploy.js

# Salvar credenciais para o usuário
cd $WORK_DIR
cat <<EOF > CREDENCIAIS_DEPLOY.txt
=== Credenciais de Instalação do Estoqx ===
Data: $(date)
Domínio: $APP_DOMAIN

URL Aplicação: http://$APP_DOMAIN:4173 (Após rodar build)
URL Supabase Studio: http://$APP_DOMAIN:8000
    Usuário: admin
    Senha: $DASHBOARD_PASSWORD

POSTGRES_PASSWORD: $POSTGRES_PASSWORD
JWT_SECRET: $JWT_SECRET
SERVICE_ROLE_KEY: $SERVICE_ROLE_KEY
ANON_KEY: $ANON_KEY

Oculte este arquivo ou apague-o após salvar as senhas!
EOF

echo "--- IMPLANTAÇÃO CONCLUÍDA COM SUCESSO ---"
echo "As credenciais foram salvas em: $WORK_DIR/CREDENCIAIS_DEPLOY.txt"
echo "LEIA ESTE ARQUIVO PARA ACESSAR O SISTEMA!"
echo ""
echo "Para rodar a aplicação em produção agora:"
echo "cd $WORK_DIR/estoqx-simple && npm run build && npm run preview -- --host 0.0.0.0 --port 4173"

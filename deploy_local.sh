#!/bin/bash

# Parar o script se houver erro
set -e

echo "=== Iniciando Script de Implantação para Debian 12 ==="

# Verifica se é root
if [ "$EUID" -ne 0 ]; then 
  echo "Por favor, execute como root (sudo ./deploy_local.sh)"
  exit
fi

# 0. Prompt para o Domínio/IP
read -p "Digite o domínio ou IP onde a aplicação será acessada (ex: 192.168.1.100 ou app.estoqx.com): " APP_DOMAIN
if [ -z "$APP_DOMAIN" ]; then
    echo "Domínio não informado. Usando 'localhost'."
    APP_DOMAIN="localhost"
fi
echo "Usando domínio: $APP_DOMAIN"

# 1. Atualizar o sistema e instalar dependências básicas
echo "--- 1. Atualizando sistema e instalando dependências básicas ---"
apt-get update && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg git wget unzip

# 2. Instalar Docker e Docker Compose (Repositório Oficial)
echo "--- 2. Instalando Docker e Docker Compose ---"
# Remover versões antigas se existirem
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove -y $pkg; done || true

# Adicionar chave GPG oficial do Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Adicionar repositório
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Iniciar e habilitar Docker
systemctl start docker
systemctl enable docker

echo "Docker instalado com sucesso!"

# 3. Preparar diretório de trabalho
WORK_DIR="/opt/estoqx"
mkdir -p $WORK_DIR
cd $WORK_DIR
echo "Diretório de trabalho: $WORK_DIR"

# 4. Configurar Supabase via Docker
echo "--- 4. Configurando Supabase (Docker) ---"
if [ -d "supabase" ]; then
    echo "Pasta supabase já existe, pulando clone..."
else
    # Clona o repositório oficial do Supabase para pegar o setup docker
    git clone --depth 1 https://github.com/supabase/supabase.git supabase-repo
    mv supabase-repo/docker supabase
    rm -rf supabase-repo
fi

cd supabase

# Copiar arquivo de exemplo .env
if [ ! -f .env ]; then
    cp .env.example .env
    echo "Arquivo .env configurado."
fi

# Configurar API_EXTERNAL_URL para o domínio escolhido (importante para redirects funcionarem)
# Usa sed para substituir a linha existente ou adiciona se não existir
if grep -q "API_EXTERNAL_URL=" .env; then
    sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://$APP_DOMAIN:8000|g" .env
else
    echo "API_EXTERNAL_URL=http://$APP_DOMAIN:8000" >> .env
fi

# Subir Supabase
echo "Iniciando Supabase..."
docker compose pull
docker compose up -d

# Aguardar Supabase estar pronto
echo "Aguardando Supabase iniciar (pode levar alguns minutos)..."
until curl -s -f -o /dev/null "http://localhost:8000/rest/v1/"; do
  echo "Aguardando API do Supabase (http://localhost:8000)..."
  sleep 5
done
echo "Supabase está online!"

# Capturar chaves do arquivo .env do Supabase (removendo aspas se houver)
ANON_KEY=$(grep "ANON_KEY=" .env | cut -d '=' -f2 | tr -d '"')
SERVICE_KEY=$(grep "SERVICE_ROLE_KEY=" .env | cut -d '=' -f2 | tr -d '"')

# Exibir informações de conexão
echo "--- Informações do Supabase ---"
echo "URL: http://$APP_DOMAIN:8000"
echo "ANON KEY: $ANON_KEY"
echo "SERVICE KEY: (Oculta por segurança)"

cd $WORK_DIR

# 5. Clonar e Configurar Aplicação Estoqx
echo "--- 5. Clonando Aplicação Estoqx ---"
if [ -d "estoqx-simple" ]; then
    echo "Pasta estoqx-simple já existe. Atualizando..."
    cd estoqx-simple
    git pull
else
    git clone https://github.com/suely35ramos-design/estoqx-simple.git
    cd estoqx-simple
fi

# 6. Instalar Node.js e Dependências
echo "--- 6. Instalando Node.js 20 e Dependências ---"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "Instalando dependências do projeto..."
npm install

# 7. Configurar .env da Aplicação
echo "--- 7. Configurando .env da Aplicação ---"
# Criar ou sobrescrever o .env com as credenciais do Supabase local
cat <<EOF > .env
VITE_SUPABASE_PROJECT_ID="local-docker"
VITE_SUPABASE_URL="http://$APP_DOMAIN:8000"
VITE_SUPABASE_PUBLISHABLE_KEY="$ANON_KEY"
EOF

echo "Arquivo .env atualizado com as credenciais do Supabase Local."

# 8. Teste de Conexão e Seed de Usuários
echo "--- 8. Criando Usuários Iniciais ---"

# Criar script temporário para seed
cat <<EOF > seed_users.js
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'http://localhost:8000';
const serviceKey = '$SERVICE_KEY';

const supabase = createClient(supabaseUrl, serviceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

const users = [
  { email: 'admin@estoqx.com', password: 'Teste123!', role: 'Admin' },
  { email: 'gestor@estoqx.com', password: 'Teste123!', role: 'Gestor' },
  { email: 'almoxarife@estoqx.com', password: 'Teste123!', role: 'Almoxarife' },
  { email: 'encarregado@estoqx.com', password: 'Teste123!', role: 'Encarregado' },
  { email: 'operador@estoqx.com', password: 'Teste123!', role: 'Operador' }
];

async function seed() {
  console.log('Iniciando cadastro de usuários...');
  for (const user of users) {
    // Tenta criar o usuário
    const { data, error } = await supabase.auth.admin.createUser({
      email: user.email,
      password: user.password,
      email_confirm: true,
      user_metadata: { role: user.role }
    });

    if (error) {
      console.error(\`Erro ao criar \${user.email}: \${error.message}\`);
    } else {
      console.log(\`Usuário criado com sucesso: \${user.email} (Role: \${user.role})\`);
    }
  }
}

seed().then(() => console.log('Seed finalizado.'));
EOF

# Executar seed
node seed_users.js
rm seed_users.js

echo "--- Implantação Concluída! ---"
echo "Aplicação configurada em: $WORK_DIR/estoqx-simple"
echo "Para rodar em produção:"
echo "cd $WORK_DIR/estoqx-simple && npm run build && npm run preview -- --host 0.0.0.0 --port 4173"
echo ""
echo "Acesse a aplicação em: http://$APP_DOMAIN:4173"
echo "Acesse o Supabase Studio em: http://$APP_DOMAIN:8000"

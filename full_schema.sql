-- ============================================
-- FULL SCHEMA FOR ESTOQX-SIMPLE (PostgreSQL)
-- ============================================
-- This file was generated to deploy the Supabase-based schema 
-- onto a standard PostgreSQL server.
-- 
-- Includes:
-- 1. Supabase Compatibility Layer (auth schema, extensions)
-- 2. App Schema (Migrations)
-- ============================================

-- [PART 1] SUPABASE COMPATIBILITY LAYER
-- =========================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create 'auth' schema and 'users' table to mimic Supabase Auth
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    instance_id UUID,
    aud VARCHAR(255),
    role VARCHAR(255),
    email VARCHAR(255),
    encrypted_password VARCHAR(255),
    email_confirmed_at TIMESTAMPTZ,
    invited_at TIMESTAMPTZ,
    confirmation_token VARCHAR(255),
    confirmation_sent_at TIMESTAMPTZ,
    recovery_token VARCHAR(255),
    recovery_sent_at TIMESTAMPTZ,
    email_change_token_new VARCHAR(255),
    email_change VARCHAR(255),
    email_change_sent_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ,
    raw_app_meta_data JSONB,
    raw_user_meta_data JSONB,
    is_super_admin BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    phone VARCHAR(255),
    phone_confirmed_at TIMESTAMPTZ,
    phone_change VARCHAR(255),
    phone_change_token VARCHAR(255),
    phone_change_sent_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current VARCHAR(255),
    email_change_confirm_status SMALLINT DEFAULT 0,
    banned_until TIMESTAMPTZ,
    reauthentication_token VARCHAR(255),
    reauthentication_sent_at TIMESTAMPTZ,
    is_sso_user BOOLEAN DEFAULT false,
    deleted_at TIMESTAMPTZ
);

-- Indexes for auth.users
CREATE INDEX IF NOT EXISTS users_instance_id_idx ON auth.users (instance_id);
CREATE INDEX IF NOT EXISTS users_email_idx ON auth.users (email);

-- Mock 'auth.uid()' function for RLS policies
-- In a real Supabase env, this is handled by the API. 
-- For direct SQL access, this function returns a nil UUID or needs to be set via session.
-- We will create a session variable based function.
CREATE OR REPLACE FUNCTION auth.uid() 
RETURNS UUID 
LANGUAGE sql STABLE 
AS $$
  -- Returns the user_id set in the current session 'request.jwt.claim.sub'
  -- OR null if not set.
  -- To simulate login: set_config('request.jwt.claim.sub', 'USER_UUID', false);
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- Mock 'auth.role()' function
CREATE OR REPLACE FUNCTION auth.role() 
RETURNS TEXT 
LANGUAGE sql STABLE 
AS $$
  SELECT COALESCE(current_setting('request.jwt.claim.role', true), 'anon')::text;
$$;

-- ============================================
-- [PART 2] APP MIGRATION: 20251213021408
-- ============================================

-- Enum para tipos de movimentação
CREATE TYPE public.tipo_movimentacao AS ENUM ('entrada', 'saida', 'devolucao', 'transferencia');

-- Enum para status de obra
CREATE TYPE public.status_obra AS ENUM ('ativa', 'pausada', 'concluida', 'cancelada');

-- Enum para tipo de baixa
CREATE TYPE public.tipo_baixa AS ENUM ('consumo', 'perda', 'extravio', 'devolucao');

-- Enum para tipo de serviço de manutenção
CREATE TYPE public.tipo_servico_manutencao AS ENUM ('calibracao', 'reparo', 'manutencao_preventiva', 'manutencao_corretiva');

-- Enum para status do ativo
CREATE TYPE public.status_ativo AS ENUM ('disponivel', 'emprestado', 'manutencao', 'baixado');

-- Enum para perfis de acesso (RBAC)
CREATE TYPE public.app_role AS ENUM ('admin', 'gestor', 'almoxarife', 'encarregado', 'operador');

-- ============================================
-- 1. TABELAS DE CONFIGURAÇÃO
-- ============================================

-- Tabela de Obras/Canteiros
CREATE TABLE public.obras (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome_obra TEXT NOT NULL,
  endereco TEXT,
  cidade TEXT,
  estado TEXT,
  cep TEXT,
  status status_obra DEFAULT 'ativa',
  data_inicio DATE,
  data_previsao_fim DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Tabela de Perfis de Usuário (vincula ao auth.users)
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,
  matricula TEXT UNIQUE,
  telefone TEXT,
  id_obra UUID REFERENCES public.obras(id),
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Tabela de Roles (RBAC separado)
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL DEFAULT 'operador',
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, role)
);

-- Localizações Físicas (Almoxarifados, Pátios, etc.)
CREATE TABLE public.localizacao_fisica (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_obra UUID NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  nome_local TEXT NOT NULL,
  descricao TEXT,
  capacidade_m3 NUMERIC(10,2),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Unidades de Medida
CREATE TABLE public.unidades_medida (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sigla TEXT NOT NULL UNIQUE,
  descricao TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Fatores de Conversão entre Unidades
CREATE TABLE public.fatores_conversao (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_unidade_origem UUID NOT NULL REFERENCES public.unidades_medida(id),
  id_unidade_destino UUID NOT NULL REFERENCES public.unidades_medida(id),
  fator NUMERIC(15,6) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 2. TABELAS DE ESTOQUE
-- ============================================

-- Materiais (Cadastro Principal)
CREATE TABLE public.materiais (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT UNIQUE,
  nome_material TEXT NOT NULL,
  descricao TEXT,
  id_unidade_padrao UUID REFERENCES public.unidades_medida(id),
  apelidos TEXT[], -- Array para busca por apelidos
  categoria TEXT,
  subcategoria TEXT,
  estoque_minimo NUMERIC(15,3) DEFAULT 0,
  estoque_maximo NUMERIC(15,3),
  ficha_tecnica_url TEXT,
  imagem_url TEXT,
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Lotes (Rastreabilidade FIFO)
CREATE TABLE public.lotes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_material UUID NOT NULL REFERENCES public.materiais(id) ON DELETE CASCADE,
  num_lote TEXT NOT NULL,
  data_fabricacao DATE,
  data_validade DATE,
  quantidade_inicial NUMERIC(15,3) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Saldo de Estoque (Estoque Atual por Local e Lote)
CREATE TABLE public.estoque_saldo (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_material UUID NOT NULL REFERENCES public.materiais(id) ON DELETE CASCADE,
  id_local UUID NOT NULL REFERENCES public.localizacao_fisica(id) ON DELETE CASCADE,
  id_lote UUID REFERENCES public.lotes(id),
  saldo_atual NUMERIC(15,3) NOT NULL DEFAULT 0,
  custo_medio NUMERIC(15,4) DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(id_material, id_local, id_lote)
);

-- Ordens de Serviço / Frentes de Trabalho
CREATE TABLE public.ordens_servico (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_obra UUID NOT NULL REFERENCES public.obras(id) ON DELETE CASCADE,
  codigo TEXT UNIQUE,
  descricao TEXT NOT NULL,
  equipe_responsavel TEXT,
  status TEXT DEFAULT 'ativa',
  data_inicio DATE,
  data_fim DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 3. TABELAS DE MOVIMENTAÇÃO (LOGS)
-- ============================================

-- Movimentação Principal
CREATE TABLE public.movimentacao (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo_mov tipo_movimentacao NOT NULL,
  id_material UUID NOT NULL REFERENCES public.materiais(id),
  id_lote UUID REFERENCES public.lotes(id),
  id_local_origem UUID REFERENCES public.localizacao_fisica(id),
  id_local_destino UUID REFERENCES public.localizacao_fisica(id),
  quantidade NUMERIC(15,3) NOT NULL,
  custo_unitario NUMERIC(15,4),
  id_usuario UUID NOT NULL REFERENCES auth.users(id),
  data_mov TIMESTAMPTZ DEFAULT now(),
  observacao TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Detalhes de Entrada (Nota Fiscal)
CREATE TABLE public.mov_entrada_nf (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_mov UUID NOT NULL REFERENCES public.movimentacao(id) ON DELETE CASCADE,
  num_nf TEXT,
  serie_nf TEXT,
  data_emissao DATE,
  data_recebimento DATE,
  id_fornecedor UUID,
  nf_arquivo_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Detalhes de Saída (Consumo)
CREATE TABLE public.mov_saida_os (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_mov UUID NOT NULL REFERENCES public.movimentacao(id) ON DELETE CASCADE,
  id_os UUID REFERENCES public.ordens_servico(id),
  id_responsavel_retirada UUID REFERENCES auth.users(id),
  assinatura_url TEXT,
  tipo_baixa tipo_baixa DEFAULT 'consumo',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Log de Auditoria
CREATE TABLE public.log_auditoria (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tabela_afetada TEXT NOT NULL,
  id_registro_afetado UUID NOT NULL,
  acao TEXT NOT NULL,
  dados_antigos JSONB,
  dados_novos JSONB,
  id_usuario UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 4. TABELAS FINANCEIRAS
-- ============================================

-- Fornecedores
CREATE TABLE public.fornecedores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  razao_social TEXT NOT NULL,
  nome_fantasia TEXT,
  cnpj TEXT UNIQUE,
  inscricao_estadual TEXT,
  endereco TEXT,
  cidade TEXT,
  estado TEXT,
  telefone TEXT,
  email TEXT,
  contato_nome TEXT,
  contrato_url TEXT,
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Custo Unitário (Custo Médio Ponderado)
CREATE TABLE public.custo_unitario (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_material UUID NOT NULL REFERENCES public.materiais(id) ON DELETE CASCADE,
  data_calculo DATE NOT NULL DEFAULT CURRENT_DATE,
  custo_medio_ponderado NUMERIC(15,4) NOT NULL,
  quantidade_total NUMERIC(15,3),
  valor_total NUMERIC(15,4),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 5. TABELAS DE ATIVOS (Ferramentas)
-- ============================================

-- Ativos (Ferramentas e Equipamentos)
CREATE TABLE public.ativos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  num_serial TEXT UNIQUE,
  id_material UUID REFERENCES public.materiais(id),
  nome TEXT NOT NULL,
  descricao TEXT,
  codigo_qr TEXT UNIQUE,
  codigo_barras TEXT,
  id_local UUID REFERENCES public.localizacao_fisica(id),
  status status_ativo DEFAULT 'disponivel',
  valor_aquisicao NUMERIC(15,2),
  data_aquisicao DATE,
  vida_util_meses INTEGER,
  imagem_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Empréstimos de Ativos
CREATE TABLE public.ativo_emprestimo (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_ativo UUID NOT NULL REFERENCES public.ativos(id) ON DELETE CASCADE,
  id_usuario_responsavel UUID NOT NULL REFERENCES auth.users(id),
  data_emprestimo TIMESTAMPTZ DEFAULT now(),
  data_devolucao_prevista TIMESTAMPTZ,
  data_devolucao_real TIMESTAMPTZ,
  observacao TEXT,
  status TEXT DEFAULT 'ativo',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Manutenção de Ativos
CREATE TABLE public.ativo_manutencao (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_ativo UUID NOT NULL REFERENCES public.ativos(id) ON DELETE CASCADE,
  tipo_servico tipo_servico_manutencao NOT NULL,
  descricao TEXT,
  data_servico DATE NOT NULL,
  data_proxima_manutencao DATE,
  custo NUMERIC(15,2),
  fornecedor TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 6. ÍNDICES PARA PERFORMANCE
-- ============================================

CREATE INDEX idx_materiais_nome ON public.materiais USING gin(to_tsvector('portuguese', nome_material));
CREATE INDEX idx_materiais_apelidos ON public.materiais USING gin(apelidos);
CREATE INDEX idx_materiais_categoria ON public.materiais(categoria);
CREATE INDEX idx_estoque_saldo_material ON public.estoque_saldo(id_material);
CREATE INDEX idx_estoque_saldo_local ON public.estoque_saldo(id_local);
CREATE INDEX idx_movimentacao_material ON public.movimentacao(id_material);
CREATE INDEX idx_movimentacao_data ON public.movimentacao(data_mov);
CREATE INDEX idx_movimentacao_tipo ON public.movimentacao(tipo_mov);
CREATE INDEX idx_lotes_material ON public.lotes(id_material);
CREATE INDEX idx_ativos_status ON public.ativos(status);

-- ============================================
-- 7. FUNÇÃO PARA VERIFICAR ROLES
-- ============================================

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

-- ============================================
-- 8. TRIGGER PARA UPDATED_AT
-- ============================================

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_obras_updated_at BEFORE UPDATE ON public.obras
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_materiais_updated_at BEFORE UPDATE ON public.materiais
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_localizacao_updated_at BEFORE UPDATE ON public.localizacao_fisica
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_ordens_servico_updated_at BEFORE UPDATE ON public.ordens_servico
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_fornecedores_updated_at BEFORE UPDATE ON public.fornecedores
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_ativos_updated_at BEFORE UPDATE ON public.ativos
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_estoque_saldo_updated_at BEFORE UPDATE ON public.estoque_saldo
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================
-- 9. TRIGGER PARA CRIAR PROFILE AUTOMÁTICO
-- ============================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, nome)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'nome', NEW.email));
  
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'operador');
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- 10. RLS POLICIES
-- ============================================

ALTER TABLE public.obras ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.localizacao_fisica ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unidades_medida ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fatores_conversao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materiais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque_saldo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ordens_servico ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimentacao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mov_entrada_nf ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mov_saida_os ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.log_auditoria ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fornecedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custo_unitario ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ativos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ativo_emprestimo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ativo_manutencao ENABLE ROW LEVEL SECURITY;

-- Políticas para usuários autenticados
CREATE POLICY "Authenticated users can view obras" ON public.obras
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Admins can manage obras" ON public.obras
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT TO authenticated USING (id = auth.uid());

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE TO authenticated USING (id = auth.uid());

CREATE POLICY "Admins can view all profiles" ON public.profiles
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "User can view own roles" ON public.user_roles
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "Admins can manage roles" ON public.user_roles
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Authenticated users can view localizacoes" ON public.localizacao_fisica
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Admins can manage localizacoes" ON public.localizacao_fisica
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Authenticated users can view unidades" ON public.unidades_medida
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Admins can manage unidades" ON public.unidades_medida
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Authenticated users can view fatores" ON public.fatores_conversao
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can view materiais" ON public.materiais
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can manage materiais" ON public.materiais
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife') OR
    public.has_role(auth.uid(), 'gestor')
  );

CREATE POLICY "Authenticated users can view lotes" ON public.lotes
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can manage lotes" ON public.lotes
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife')
  );

CREATE POLICY "Authenticated users can view estoque_saldo" ON public.estoque_saldo
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can manage estoque_saldo" ON public.estoque_saldo
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife')
  );

CREATE POLICY "Authenticated users can view ordens_servico" ON public.ordens_servico
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Gestores can manage ordens_servico" ON public.ordens_servico
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'gestor')
  );

CREATE POLICY "Authenticated users can view movimentacao" ON public.movimentacao
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can insert movimentacao" ON public.movimentacao
  FOR INSERT TO authenticated WITH CHECK (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife') OR
    public.has_role(auth.uid(), 'gestor')
  );

CREATE POLICY "Authenticated users can view mov_entrada_nf" ON public.mov_entrada_nf
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can manage mov_entrada_nf" ON public.mov_entrada_nf
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife')
  );

CREATE POLICY "Authenticated users can view mov_saida_os" ON public.mov_saida_os
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can manage mov_saida_os" ON public.mov_saida_os
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife')
  );

CREATE POLICY "Admins can view log_auditoria" ON public.log_auditoria
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Authenticated users can view fornecedores" ON public.fornecedores
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Gestores can manage fornecedores" ON public.fornecedores
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'gestor')
  );

CREATE POLICY "Authenticated users can view custo_unitario" ON public.custo_unitario
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can view ativos" ON public.ativos
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can manage ativos" ON public.ativos
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife')
  );

CREATE POLICY "Authenticated users can view ativo_emprestimo" ON public.ativo_emprestimo
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can manage ativo_emprestimo" ON public.ativo_emprestimo
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife')
  );

CREATE POLICY "Authenticated users can view ativo_manutencao" ON public.ativo_manutencao
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Almoxarifes can manage ativo_manutencao" ON public.ativo_manutencao
  FOR ALL TO authenticated USING (
    public.has_role(auth.uid(), 'admin') OR 
    public.has_role(auth.uid(), 'almoxarife')
  );

-- ============================================
-- 11. DADOS INICIAIS
-- ============================================

INSERT INTO public.unidades_medida (sigla, descricao) VALUES
  ('UN', 'Unidade'),
  ('M', 'Metro'),
  ('M2', 'Metro Quadrado'),
  ('M3', 'Metro Cúbico'),
  ('KG', 'Quilograma'),
  ('L', 'Litro'),
  ('PC', 'Peça'),
  ('CX', 'Caixa'),
  ('SC', 'Saco'),
  ('TN', 'Tonelada');

-- ============================================
-- [PART 3] APP MIGRATION: 20251213022543 (Fixes)
-- ============================================

-- Fix function search path for update_updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

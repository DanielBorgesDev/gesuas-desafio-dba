-- 1. Criação das Group Roles Básicas (Sem permissão de login)
CREATE ROLE role_etl_writer NOLOGIN;
CREATE ROLE role_app_reader NOLOGIN;
CREATE ROLE role_analista_dados NOLOGIN;
CREATE ROLE role_dev_readonly NOLOGIN;

-- 2. Concessão de Permissões Base para o ETL (Escrita)
GRANT CONNECT ON DATABASE dw_gesuas TO role_etl_writer;
GRANT USAGE, CREATE ON SCHEMA pesqavancada TO role_etl_writer;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA pesqavancada TO role_etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA pesqavancada GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO role_etl_writer;

-- 3. Concessão de Permissões para Aplicação Web (Leitura Geral)
GRANT CONNECT ON DATABASE dw_gesuas TO role_app_reader;
GRANT USAGE ON SCHEMA pesqavancada TO role_app_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA pesqavancada TO role_app_reader;

-- 4. Concessão de Permissões para Analistas (Acesso Restrito/Anonimizado)
GRANT CONNECT ON DATABASE dw_gesuas TO role_analista_dados;
GRANT USAGE ON SCHEMA pesqavancada TO role_analista_dados;
GRANT SELECT ON ALL TABLES IN SCHEMA pesqavancada TO role_analista_dados;

-- 4.1. REVOKE de Tabelas Sensíveis (Proteção de Saúde e Violência)
-- Analistas não podem consultar a fato de violência ou doença livremente
REVOKE SELECT ON pesqavancada.f_pessoas_violencia FROM role_analista_dados;
REVOKE SELECT ON pesqavancada.f_pessoas_doenca FROM role_analista_dados;

-- 4.2. Segurança em Nível de Coluna (Column-Level Security)
-- Impede que analistas leiam diretamente o CPF e o Nome para evitar extração de PII
REVOKE SELECT (cpf, nome) ON pesqavancada.f_pessoas_situacao FROM role_analista_dados;
-- Analistas poderão fazer contagens por faixa de renda ou escolaridade, mas 
-- tomarão "Permission Denied" se incluírem 'nome' ou 'cpf' no SELECT.

-- =========================================================================
-- 5. POLÍTICA DE ISOLAMENTO DE MUNICÍPIOS (ROW-LEVEL SECURITY - RLS)
-- =========================================================================
-- Objetivo: Garantir que nenhuma falha no código web permita acesso cruzado 
-- a dados de outros municípios.

-- 5.1 Ativa o recurso na tabela fato principal e demais
ALTER TABLE pesqavancada.f_pessoas_situacao ENABLE ROW LEVEL SECURITY;
ALTER TABLE pesqavancada.f_pessoas_atendimento ENABLE ROW LEVEL SECURITY;

-- 5.2 Cria a Política Restritiva (App e Analistas)
-- A query só retornará linhas onde o `munic` bata com a variável da sessão.
CREATE POLICY rls_isolamento_munic_situacao 
ON pesqavancada.f_pessoas_situacao
FOR SELECT
TO role_app_reader, role_analista_dados
USING (
    munic = NULLIF(current_setting('gesuas.municipio_id', true), '')::integer
);

-- O usuário do ETL ('role_etl_writer') e o dono da tabela bypassam o RLS 
-- naturalmente ou através da configuração (ALTER ROLE role_etl_writer BYPASSRLS), 
-- podendo processar cargas do país inteiro.

-- =========================================================================
-- 6. CONFIGURAÇÃO DE AUDITORIA FORENSE (pgAudit)
-- =========================================================================

-- Criação de um papel "marcador" estritamente para o pgAudit monitorar
CREATE ROLE auditoria_acesso_sensivel NOLOGIN;

-- Associa a tabela sensível ao papel de auditoria (Isso não dá permissões reais, 
-- apenas sinaliza para a extensão pgAudit que qualquer SELECT aqui deve ser logado).
GRANT SELECT ON pesqavancada.f_pessoas_violencia TO auditoria_acesso_sensivel;
GRANT SELECT ON pesqavancada.f_pessoas_acolhimento TO auditoria_acesso_sensivel;

-- Comandos a serem injetados no postgresql.conf do servidor:
/*
shared_preload_libraries = 'pgaudit'
pgaudit.log = 'ddl'                       -- Loga toda alteração estrutural
pgaudit.role = 'auditoria_acesso_sensivel' -- Loga consultas nas tabelas associadas
pgaudit.log_catalog = off                 -- Não polui log com consultas internas do Postgres
*/

-- 7. Criação de usuários finais reais atribuídos aos grupos
CREATE USER user_etl_prd WITH PASSWORD 'senha_forte';
GRANT role_etl_writer TO user_etl_prd;

CREATE USER analista_joao WITH PASSWORD 'senha_forte';
GRANT role_analista_dados TO analista_joao;

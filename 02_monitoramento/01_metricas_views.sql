-- =========================================================================
-- MÓDULO DE MONITORAMENTO: Coleta de Métricas no Catálogo do PostgreSQL
-- =========================================================================

-- 1. Tamanho Total do Banco de Dados e por Tablespace
-- Utilidade: Identificar o consumo geral do storage atrelado à instância.
SELECT 
    d.datname AS database_name,
    t.spcname AS tablespace_name,
    pg_database_size(d.datname) AS size_bytes,
    pg_size_pretty(pg_database_size(d.datname)) AS size_pretty
FROM pg_database d
JOIN pg_tablespace t ON d.dattablespace = t.oid
WHERE d.datname = current_database();

-- 2. Crescimento por Schema
-- Utilidade: Avaliar se o schema 'pesqavancada' (fatos) cresce de forma desproporcional 
-- em relação ao schema 'dimensoes'.
SELECT 
    table_schema,
    SUM(pg_total_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name))) AS size_bytes,
    pg_size_pretty(SUM(pg_total_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name)))) AS size_pretty
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
GROUP BY table_schema
ORDER BY size_bytes DESC;

-- 3. Detalhamento Fino por Tabela / Partição
-- Utilidade: Separa o que é dado real (Heap), índices e dados TOAST (textos longos).
-- Fundamental para identificar se o crescimento anormal é causado por duplicação de dados ou índices muito grandes.
SELECT 
    schemaname AS schema_name,
    relname AS table_name,
    pg_relation_size(relid) AS table_bytes_only,                 -- Apenas dados da tabela
    pg_indexes_size(relid) AS indexes_bytes,                     -- Apenas índices
    pg_total_relation_size(relid) - pg_relation_size(relid) - pg_indexes_size(relid) AS toast_bytes, -- Apenas TOAST
    pg_total_relation_size(relid) AS total_bytes,                -- Tamanho Total
    pg_size_pretty(pg_total_relation_size(relid)) AS total_pretty
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 50;

-- 4. Monitoramento de Tuplas Mortas (Bloat / Saúde do Autovacuum)
-- Utilidade: O crescimento do banco não ocorre apenas por inserções, mas pelo acúmulo 
-- de 'Dead Tuples' resultantes de UPDATEs/DELETEs massivos se o vacuum não estiver tunado.
SELECT 
    schemaname,
    relname,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND((n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0)) * 100, 2) AS dead_tup_percentage,
    last_autovacuum,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
  AND (n_live_tup + n_dead_tup) > 10000 -- Filtra tabelas com volume relevante
ORDER BY dead_tup_percentage DESC;

-- 5. Monitoramento de Consumo de Sequences (Risco de estouro de INT/BIGINT)
-- Utilidade: Impede falhas de carga por estouro de PK nas tabelas fato.
SELECT 
    seqrelid::regclass AS sequence_name,
    pg_sequence_last_value(seqrelid) AS current_value
FROM pg_sequence;
-- Particionamento Declarativo por Lista (LIST)
-- Chave de particionamento: coluna `munic`
--
-- Justificativas :
-- 1. Partition Pruning: Como as queries sempre contém `WHERE munic = X`, 
--    o PostgreSQL ignorará as partições dos outros 299 municípios. A consulta
--    lerá apenas a fração exata de dados necessária, transformando varreduras
--    de dezenas de milhões de linhas em apenas milhares.
-- 2. Manutenção de Ciclo de Vida: A entrada de um novo município ou o 
--    rompimento de contrato de um cliente atual é resolvido com operações DDL 
--    (CREATE/DROP TABLE partition), que são instantâneas e não causam bloat 
--    no banco, ao contrário de operações massivas de DELETE.
-- 3. Autovacuum Isolado: As rotinas de vacuum atuarão em tabelas físicas 
--    menores, evitando contenção e locks em horários de pico.
--
-- Regra Crítica no PostgreSQL: A chave primária (ou UNIQUE constraints) da 
-- tabela particionada DEVE obrigatoriamente incluir a chave de particionamento.

-- DDL DE CRIAÇÃO - Tabela Fato Particionada

-- 1. Criação da Tabela Pai (Master)
CREATE TABLE pesqavancada_test.f_pessoas_situacao (
    pessoa BIGINT NOT NULL,
    munic INT NOT NULL,
    nome VARCHAR(255),
    cpf VARCHAR(14),
    sexo CHAR(1),
    faixaetaria VARCHAR(50),
    escolaridade VARCHAR(100),
    faixarenda VARCHAR(100),
    bairro VARCHAR(100),
    -- Inclusão OBRIGATÓRIA da chave de particionamento na PK
    CONSTRAINT pk_f_pessoas_situacao PRIMARY KEY (munic, pessoa)
) PARTITION BY LIST (munic);

-- 2. Criação das partições físicas por município 
CREATE TABLE pesqavancada_test.f_pessoas_situacao_mun_1 
    PARTITION OF pesqavancada_test.f_pessoas_situacao FOR VALUES IN (1);

CREATE TABLE pesqavancada_test.f_pessoas_situacao_mun_2 
    PARTITION OF pesqavancada_test.f_pessoas_situacao FOR VALUES IN (2);

-- 3. Partição DEFAULT 
-- Armazena registros cujo 'munic' ainda não possua uma partição explícita criada, 
-- evitando que inserções falhem em tempo de execução.
CREATE TABLE pesqavancada_test.f_pessoas_situacao_default 
    PARTITION OF pesqavancada_test.f_pessoas_situacao DEFAULT;
--  Índices Compostos B-Tree e Covering Indexes

-- 1. Índice para a Tabela Central (Situação)
-- Justificativa: A consulta principal filtra por `munic = 1`. Ter `munic` como a primeira 
-- coluna garante que o PostgreSQL restrinja os dados rapidamente. A coluna `pessoa` 
-- logo a seguir otimiza a junção (JOIN) com as CTEs.
-- Obs: Caso (munic, pessoa) já seja a Primary Key, este índice já existirá implicitamente.
CREATE UNIQUE INDEX idx_pessoas_situacao_pk 
ON pesqavancada_test.f_pessoas_situacao (munic, pessoa);

-- 2. Índice para a Tabela de Atendimentos (Otimizando o JOIN, CTE e o EXISTS)
-- Justificativa: Este é o índice mais crítico. Ao utilizar (munic, pessoa, dataatendimento),
-- otimizamos a CTE (WHERE munic = 1 GROUP BY pessoa) e a cláusula EXISTS da query principal.
-- Permite um "Index Scan" que filtra município/pessoa e avalia o range de datas
-- diretamente na estrutura B-Tree, sem necessidade de varrer registros irrelevantes.
CREATE INDEX idx_pessoas_atendimento_filtro 
ON pesqavancada_test.f_pessoas_atendimento (munic, pessoa, dataatendimento);

-- 3. Índice para a Tabela de Deficiências (Index-Only Scan)
-- Justificativa: Aplicamos a cláusula INCLUDE (disponível no PostgreSQL 11+). 
-- O índice filtra e resolve o JOIN usando (munic, pessoa), armazenando `tipodeficiencia_id` 
-- no nó folha. Isso permite um "Index-Only Scan" na CTE de agregação, em que o banco conta 
-- os IDs lendo apenas a RAM (índice), sem acessar as páginas físicas no disco (Heap).
CREATE INDEX idx_pessoas_deficiencia_idxonly 
ON pesqavancada_test.f_pessoas_deficiencia (munic, pessoa)
INCLUDE (tipodeficiencia_id);


-- ALTERNATIVA: Índice BRIN para dados cronológicos volumosos
-- Justificativa: Caso a tabela `f_pessoas_atendimento` seja estritamente "append-only" e
-- cresça a um ponto em que a RAM não comporte mais um B-Tree na data, o BRIN pode atuar.
-- Nota de adoção: Use apenas como último recurso de hardware, pois o B-Tree ainda entregará menor latência para a query analisada.
CREATE INDEX idx_pessoas_atend_brin_data 
ON pesqavancada_test.f_pessoas_atendimento USING brin (dataatendimento) 
WITH (pages_per_range = 128);

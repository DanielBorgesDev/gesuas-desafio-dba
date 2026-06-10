-- =========================================================================
-- ALTERNATIVA 1: Uso da cláusula IN
-- =========================================================================
-- Pontos importantes: 
-- • O PostgreSQL 14+ otimiza tanto o EXISTS quanto o IN convertendo-os 
--   para a mesma operação de Semi Join (Hash ou Nested Loop Semi Join).
-- • A desvantagem desta abordagem é que a tabela f_pessoas_atendimento 
--   precisa ser varrida DUAS vezes (uma na CTE de agregações e outra para 
--   resolver o IN).

WITH atendimentos_agregados AS (
    SELECT 
        a.pessoa,
        COUNT(a.dataatendimento) AS total_atendimentos,
        MAX(a.dataatendimento)   AS ultimo_atendimento
    FROM pesqavancada_test.f_pessoas_atendimento a
    WHERE a.munic = 1
    GROUP BY a.pessoa
)
SELECT 
    p.pessoa, 
    COALESCE(a.total_atendimentos, 0) AS total_atendimentos 
FROM pesqavancada_test.f_pessoas_situacao p 
LEFT JOIN atendimentos_agregados a ON p.pessoa = a.pessoa 
WHERE p.munic = 1 
  AND p.pessoa IN (
      SELECT a2.pessoa 
      FROM pesqavancada_test.f_pessoas_atendimento a2 
      WHERE a2.munic = 1 
        AND a2.dataatendimento >= '2020-01-01 00:00:00' 
        AND a2.dataatendimento < '2025-01-01 00:00:00'
  );

-- =========================================================================
-- ALTERNATIVA 2: Agregação Condicional na CTE
-- =========================================================================
-- Pontos importantes:
-- • Elimina totalmente a subquery principal (EXISTS/IN).
-- • Utiliza a função bool_or() para avaliar a regra durante o agrupamento.
-- • A tabela fato é processada apenas UMA vez (Single Pass). O banco conta 
--   os atendimentos, encontra a data máxima e avalia a regra de negócio 
--   exclusivamente em memória, reduzindo o I/O de disco.

WITH atendimentos_agregados AS (
    SELECT 
        a.pessoa,
        COUNT(a.dataatendimento) AS total_atendimentos,
        MAX(a.dataatendimento)   AS ultimo_atendimento,
        bool_or(
            a.dataatendimento >= '2020-01-01 00:00:00' AND 
            a.dataatendimento <  '2025-01-01 00:00:00'
        ) AS teve_atendimento_periodo
    FROM pesqavancada_test.f_pessoas_atendimento a
    WHERE a.munic = 1
    GROUP BY a.pessoa
)
SELECT 
    p.pessoa, 
    COALESCE(a.total_atendimentos, 0) AS total_atendimentos 
FROM pesqavancada_test.f_pessoas_situacao p 
LEFT JOIN atendimentos_agregados a ON p.pessoa = a.pessoa 
WHERE p.munic = 1 
  AND a.teve_atendimento_periodo = TRUE;

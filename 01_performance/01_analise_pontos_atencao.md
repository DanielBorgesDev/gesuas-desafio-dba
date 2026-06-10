```sql
WITH atendimentos_agregados AS (
    -- Pré-agregamos os atendimentos no nível da pessoa antes do JOIN principal.
    -- Isso evita o produto cartesiano (explosão N x M linhas) que ocorreria ao ligar múltiplas tabelas fato diretamente.
    SELECT
        a.pessoa,
        COUNT(a.dataatendimento) AS total_atendimentos, -- Substitui o lento COUNT(DISTINCT) por um COUNT simples.
        MAX(a.dataatendimento)   AS ultimo_atendimento,
        
        -- Agregação Condicional (Single Pass): Avalia a regra de negócio do período na mesma varredura, eliminando o I/O do EXISTS.
        bool_or(
            a.dataatendimento >= '2020-01-01 00:00:00' AND
            a.dataatendimento <  '2025-01-01 00:00:00'
        ) AS teve_atendimento_periodo
    FROM pesqavancada_test.f_pessoas_atendimento a
    -- Incluímos "munic = 1" aqui para usar índices prefixados com 'munic'
    -- e acionar o partition pruning (evitando ler outros municípios).
    WHERE a.munic = 1
    GROUP BY a.pessoa
),
deficiencias_agregadas AS (
    --  Mesma estratégia para deficiências. Agrupa-se 1 registro por pessoa.
    SELECT
        def.pessoa,
        COUNT(def.tipodeficiencia_id) AS total_deficiencias -- Usa Index-Only Scan devido ao índice com INCLUDE.
    FROM pesqavancada_test.f_pessoas_deficiencia def
    WHERE def.munic = 1
    GROUP BY def.pessoa
)
-- Como as CTEs garantem granularidade de 1 linha por pessoa,
-- a consulta principal não exige mais GROUP BY nas pesadas colunas textuais (nome, cpf, etc).
SELECT
    p.pessoa,
    p.nome,
    p.cpf,
    p.sexo,
    p.faixaetaria,
    p.escolaridade,
    p.faixarenda,
    p.bairro,
    COALESCE(a.total_atendimentos, 0) AS total_atendimentos, -- Substitui nulos por 0 caso a pessoa não tenha atendimentos.
    a.ultimo_atendimento::date        AS ultimo_atendimento,
    COALESCE(def.total_deficiencias, 0) AS total_deficiencias
FROM pesqavancada_test.f_pessoas_situacao p
-- O LEFT JOIN agora processa apenas relacionamentos de 1 para 1.
LEFT JOIN atendimentos_agregados a
    ON p.pessoa = a.pessoa
LEFT JOIN deficiencias_agregadas def
    ON p.pessoa = def.pessoa
--  Restrição principal para atender apenas 1 município.
WHERE p.munic = 1
  -- Aplicação do filtro calculado na CTE, cortando o I/O duplicado na tabela fato.
  AND a.teve_atendimento_periodo = TRUE
ORDER BY a.total_atendimentos DESC;
```

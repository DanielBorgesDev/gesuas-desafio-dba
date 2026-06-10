# Playbook de Troubleshooting: Lentidão Pós-Carga (Segunda-feira)

O cenário de um sistema que apresenta lentidão severa na segunda-feira de manhã, logo após uma rotina de carga massiva no final de semana ter rodado "sem erros", é um sintoma clássico em Data Warehousing. O erro não ocorreu na aplicação, mas sim na manutenção do catálogo do banco de dados (estatísticas desatualizadas ou acúmulo de bloqueios/bloat).

Abaixo detalho o fluxo de investigação, ferramentas, comandos e ações corretivas.

---

## Etapa 1: Primeiras Verificações 

A primeira regra de um troubleshooting crítico é descobrir o que está acontecendo **neste exato momento** no banco, antes que o cenário mude.

### 1.1 Verificar Sessões Ativas e Gargalos de CPU/IO
Verifico se as consultas estão rodando ativamente consumindo CPU, ou se estão travadas esperando recursos (Wait Events como `IO` ou `Lock`).

```sql
-- Query: Identificar consultas lentas ativas e o motivo da espera (Wait Events)
SELECT 
    pid, 
    usename, 
    state, 
    wait_event_type, 
    wait_event, 
    EXTRACT(EPOCH FROM (now() - query_start)) AS duration_seconds,
    query
FROM pg_stat_activity
WHERE state = 'active' 
  AND pid <> pg_backend_pid()
ORDER BY duration_seconds DESC;
```
*O que busco:* Se houver muitos Wait Events do tipo `IO:DataFileRead`, o banco está fazendo leituras massivas em disco (provavelmente um Seq Scan não intencional). Se for `Lock:relation`, vamos para o passo 1.2.

### 1.2 Mapeamento de Árvore de Bloqueios (Lock Tree)
O processo de carga do fim de semana pode ter deixado uma transação "órfã" (estado `idle in transaction`) segurando bloqueios pesados na tabela fato, enfileirando as consultas do módulo de pesquisa.

```sql
-- Query: Exibe quem está bloqueando quem (Lock Tree)
SELECT 
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.pid != blocked_locks.pid;
```
*O que busco:* Identificar processos (`blocking_pid`) paralisados em `idle in transaction` que não estão fazendo nada, mas mantêm bloqueios exclusivos na tabela.

### 1.3 Verificar Saúde do Autovacuum e Estatísticas (A Causa Raiz Mais Provável)
Após uma carga massiva no final de semana, se o processo de análise de estatísticas (`ANALYZE`) não rodou a tempo, o PostgreSQL ficará com o "mapa" desatualizado. O Query Planner vai escolher planos de execução desastrosos (ex: usar Nested Loops achando que tem poucos dados, quando na verdade entraram milhões de registros).

```sql
-- Query: Verifica quando o Autoanalyze rodou pela última vez nas tabelas fato
SELECT 
    schemaname, 
    relname, 
    last_autovacuum, 
    last_autoanalyze, 
    n_live_tup, 
    n_dead_tup
FROM pg_stat_user_tables
WHERE schemaname = 'pesqavancada'
ORDER BY last_autoanalyze ASC NULLS FIRST;
```
*O que busco:* Se a coluna `last_autoanalyze` mostrar uma data ANTERIOR à carga do fim de semana, achamos o problema principal.

---

## Etapa 2: Ações Corretivas Imediatas (Mitigação)

Uma vez identificado o gargalo pelos passos acima, as ações para restabelecer o ambiente imediatamente são:

1. **Derrubar Bloqueios Órfãos (Se houver):** Se o passo 1.2 revelou uma sessão travando os relatórios dos municípios, eu forço a finalização do PID bloqueador para liberar a fila:
   ```sql
   SELECT pg_terminate_backend(PID_DO_BLOQUEADOR);
   ```
2. **Atualização Urgente de Estatísticas (Se houver defasagem):** Se o passo 1.3 confirmou que o mapa de dados está desatualizado, eu não espero o Autovacuum agir sozinho. Forço a reconstrução estatística nas tabelas afetadas. Isso corrige os planos de execução defeituosos (EXPLAIN) de forma quase instantânea:
   ```sql
   -- O parâmetro VERBOSE é importante para o DBA acompanhar o progresso em tempo real
   ANALYZE VERBOSE pesqavancada.f_pessoas_situacao;
   ANALYZE VERBOSE pesqavancada.f_pessoas_atendimento;
   ```

---

## Etapa 3: Medidas Preventivas (Evitar Reincidência)

Para garantir que a equipe não tenha mais surpresas nas segundas-feiras pós-carga, recomendo as seguintes alterações na arquitetura:

1. **Inclusão de ANALYZE no Script de ETL/Carga:** A principal causa de lentidão em Data Warehouses após o fim de semana é o atraso das estatísticas. O pipeline de dados da GESUAS deve ser ajustado para incluir o comando `ANALYZE tabela_modificada;` **obrigatoriamente** no final do job de carga de domingo. Isso tira a responsabilidade das costas do Autovacuum automático sob pico de concorrência.

2. **Tuning Fino do Autovacuum para Tabelas Gigantes:** Tabelas com dezenas de milhões de registros demoram muito para disparar o limite padrão do autovacuum (`autovacuum_analyze_scale_factor = 0.1` ou 10%). Reduzir este gatilho em tabelas específicas as mantém mais saudáveis:
   ```sql
   -- Aciona a análise a cada 5% de mudanças, ao invés de 10%
   ALTER TABLE pesqavancada.f_pessoas_situacao SET (autovacuum_analyze_scale_factor = 0.05);
   ```

3. **Configuração de Logs de Lentidão (`postgresql.conf`):** Para melhorar a observabilidade sem depender de relatos de clientes:
   ```ini
   log_min_duration_statement = '3000' # Gravar no log automaticamente qualquer query que passe de 3 segundos.
   log_lock_waits = on                 # Registrar esperas de Lock acima de 1 segundo (deadlock_timeout).
   ```
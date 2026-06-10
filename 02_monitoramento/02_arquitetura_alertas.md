# Arquitetura de Monitoramento de Crescimento e Alertas

Para garantir a estabilidade do Data Warehouse da GESUAS diante do cadastro contínuo de cidadãos e municípios, o monitoramento deve ser automatizado, resiliente e prever incidentes (proativo) ao invés de apenas reagir a eles.

## 1. Automatização e Armazenamento do Histórico (Análise de Tendência)

Para viabilizar a análise de tendências de crescimento e capacidade de longo prazo (Capacity Planning), existem duas alternativas técnicas de arquitetura:

### Alternativa Recomendada: Arquitetura Baseada em Time-Series (Prometheus + Grafana)
* **Ferramenta de Coleta:** `postgres_exporter` (oficial da comunidade). Ele consome as views nativas do PostgreSQL e expõe as métricas via endpoint HTTP.
* **Armazenamento:** `Prometheus` (Time-Series Database), ideal para reter histórico de métricas comprimidas por meses/anos.
* **Visualização e Alertas:** `Grafana` e `Alertmanager`.
* **Justificativa:** É o padrão atual da indústria. Desacopla o processamento das métricas do banco de dados transacional, evitando onerar o servidor de banco. Permite aplicar funções estatísticas nativas (ex: `predict_linear()` no PromQL para prever quando o disco vai encher).

### Alternativa 2: Arquitetura Intra-Banco (extensão `pg_cron` ou crontab)
* **Automação:** Criar uma tabela histórica `metricas_crescimento_hist` no próprio banco (em um schema de manutenção).
* **Coleta:** Agendar uma stored procedure utilizando a extensão `pg_cron` (nativa do Postgres) para popular essa tabela usando as queries do arquivo `01_metricas_views.sql` com carimbos de data/hora (`CURRENT_TIMESTAMP`).
* **Justificativa:** É uma solução barata e viável para cenários onde não há infraestrutura de observabilidade externa disponível. O histórico fica encapsulado no próprio PostgreSQL.

---

## 2. Frequência de Coleta das Métricas

As métricas variam em sua volatilidade. Coletar o tamanho do banco a cada segundo gera I/O desnecessário. A frequência ideal é dividida em tiers:

| Métrica | View Utilizada | Frequência de Coleta | Propósito |
| :--- | :--- | :--- | :--- |
| **Dead Tuples (Bloat)** | `pg_stat_user_tables` | **A cada 15 a 30 minutos** | Rastrear picos de UPDATEs/DELETEs ou engarrafamento do Autovacuum. |
| **Uso de Storage (DB)** | `pg_database_size` | **A cada 1 hora** | Detectar injeções anormais de dados e criar gráficos de tendência diária. |
| **Tamanho de Tabela / Partições** | `pg_total_relation_size` | **Diariamente (Madrugada)** | Avaliar qual fato e qual município mais contribui para o crescimento (Capacity Planning). |
| **Consumo de Sequence (PK)** | `pg_sequence` | **Diariamente** | Prever estouro do limite do tipo numérico de chaves primárias. |

---

## 3. Configuração de Alertas e Limiares (Thresholds)

Baseado na arquitetura do GESUAS, onde inserções diárias de municípios podem gerar picos inesperados (ex: uma carga inicial massiva de um novo município), os seguintes alertas devem ser implementados via Alertmanager/Grafana (ou script de e-mail integrado):

### A. Alerta de Saturação de Disco / Tablespace
* **Aviso (Warning):** Ocupação do disco ou Tablespace chega a **75%**. 
  * *Ação:* Analisar se o crescimento está dentro da tendência. Planejar expansão de volume no servidor.
* **Crítico (Critical):** Ocupação do disco atinge **85% a 90%** ou previsão linear matemática aponta que encherá em menos de 48 horas.
  * *Ação:* Atuação imediata. O PostgreSQL paralisa completamente se o disco de *WAL (Write-Ahead Logs)* ou *Data* atingir 100%, podendo corromper blocos em cenários severos.

### B. Alerta de Bloat (Tuplas Mortas) nas Tabelas Fato
* **Crítico:** Porcentagem de `n_dead_tup` excede **20%** do total de `n_live_tup` em tabelas fato com mais de 10 milhões de linhas.
* **Crítico Secundário:** Diferença temporal entre o timestamp atual e o campo `last_autovacuum` for maior que **48 horas** em tabelas dinâmicas.
  * *Ação:* Indica que as configurações padrão do Autovacuum do PostgreSQL (`autovacuum_vacuum_scale_factor = 0.2`) não estão dando conta do volume. Ajustar para fator menor (`0.05`) nas tabelas específicas.

### C. Alerta de Anomalia de Crescimento (Rate Anomaly)
* **Aviso:** Crescimento diário da base (Delta) for **50% superior** à média móvel dos últimos 7 dias.
  * *Ação:* Identificar via query `pg_relation_size` qual foi o schema/tabela ofensor. Pode indicar um processo de ETL defeituoso rodando em loop ou duplicação de dados não esperada por parte de um usuário inserindo planilhas.

### D. Prevenção de Estouro de Transaction ID (TxID Wraparound)
*Embora o foco da questão seja armazenamento em disco, o congelamento por TxID é o limitador de escala mais perigoso no PostgreSQL.*
* **Aviso:** Idade da transação mais antiga (`age(datfrozenxid)`) da base ultrapassar **1.2 Bilhão**.
* **Crítico:** Idade se aproximar de **2 Bilhões**.
  * *Ação:* Executar `VACUUM FREEZE` manual durante janela de manutenção urgente, pois ao atingir o limite estrito (2.1 bi), o Postgres entra em modo "Read-Only" emergencial.

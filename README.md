# Desafio Tecnico DBA - GESUAS

Este repositorio contem a solucao tecnica para o desafio de Banco de Dados (DBA) do GESUAS. O projeto aborda a otimizacao, monitoramento, resolucao de incidentes e seguranca de um Data Warehouse analitico operando em PostgreSQL 14+, projetado para armazenar e cruzar dados socioassistenciais do SUAS.

## Estrutura do Projeto

O projeto esta dividido em quatro modulos principais:

### 1. Performance e Modelagem Dimensional (`01_performance/`)
Focado na otimizacao de consultas analiticas em tabelas com dezenas de milhoes de registros.
- **01_analise_pontos_atencao.md**: Reescrita de query analitica utilizando a tecnica de Drill-Across (CTEs) para evitar produtos cartesianos e otimizacao SARGable.
- **02_indices.sql**: Estrategia de criacao de indices compostos B-Tree focados em acesso multitenant (municipio) e Index-Only Scans com a clausula INCLUDE.
- **03_alternativas_exists.sql**: Substituicao de subqueries EXISTS por agregacao condicional (Single Pass com bool_or) para reducao drastica de I/O em disco.
- **04_particionamento.sql**: Implementacao de Particionamento Declarativo por Lista (List Partitioning) focado em Partition Pruning por municipio.

### 2. Monitoramento e Alertas (`02_monitoramento/`)
Proposta de observabilidade proativa do banco de dados para evitar incidentes por falta de recursos.
- **01_metricas_views.sql**: Queries essenciais para extrair metricas do catalogo do Postgres (pg_stat_user_tables, pg_relation_size), identificando bloat (tuplas mortas) e tamanho de tabelas.
- **02_arquitetura_alertas.md**: Arquitetura de coleta (Prometheus/Grafana vs pg_cron) com definicao de frequencia de execucao e limiares (thresholds) recomendados.

### 3. Troubleshooting e Resolucao de Problemas (`03_troubleshooting/`)
Fluxo de investigacao diagnostica de incidentes.
- **01_investigacao_lentidao.md**: Playbook detalhado para identificar gargalos pos-carga massiva (ETL), contendo queries para mapeamento de arvore de bloqueios (Lock Tree) e diagnostico de falhas no Autovacuum/Analyze. Inclui acoes de mitigacao imediatas e correcoes preventivas.

### 4. Seguranca e Conformidade LGPD (`04_seguranca/` e `04_seguranca_lgpd/`)
Controle de acesso rigoroso para um ambiente que lida com dados altamente sensiveis.
- **01_politica_acesso.md**: Definicao de papeis baseados no Principio do Menor Privilegio (RBAC) e proposta de rastreabilidade de aplicacoes atraves de context variables para uso com a extensao pgAudit.
- **02_roles_rls.sql**: Scripts de implementacao de Row-Level Security (RLS) para isolamento inflexivel de dados entre municipios, alem de protecoes com Column-Level Security para ofuscar identificadores pessoais (PII).

## Requisitos

- PostgreSQL 14 ou superior.
- Extensao `pgAudit` instalada no servidor (para o modulo de seguranca).

## Notas de Arquitetura

O desenho das solucoes levou em consideracao as seguintes premissas do ambiente GESUAS:
1. Consultas do produto sempre escopadas por um unico municipio.
2. Volumetria na casa das dezenas de milhoes de registros nas tabelas fato.
3. Informacoes de aproximadamente 300 municipios.
4. Ocorrencia de atualizacoes massivas de dados (cargas de ETL aos finais de semana).

Todas as propostas priorizam recursos nativos do PostgreSQL, evitando dependencias excessivas de ferramentas de terceiros para o processamento de dados, delegando processos de carga na memoria e reduzindo operacoes de I/O em disco desnecessarias.

## Como utilizar

Os arquivos `.sql` estao prontos para analise ou execucao em um banco de dados de testes que replique a estrutura definida. Os arquivos `.md` contem a documentacao teorica, justificativas arquiteturais e os planos de acao (Playbooks) necessarios para o embasamento das decisoes tomadas pela Engenharia de Dados.

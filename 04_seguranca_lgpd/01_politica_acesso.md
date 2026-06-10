# Política de Acesso e Segurança (DW - GESUAS)

O Data Warehouse do SUAS armazena dados classificados como **Altamente Sensíveis** pela LGPD (dados de saúde, violência doméstica, menores de idade). A política de segurança deve operar sob o princípio do *Least Privilege* (Menor Privilégio Possível) e da *Defesa em Profundidade* (Múltiplas camadas de proteção).

## 1. Definição de Roles e Níveis de Privilégio

A estratégia de controle de acesso baseia-se em *Group Roles* (Papéis de Grupo), onde usuários individuais herdam permissões de seus grupos. Ninguém acessa o banco usando o usuário `postgres` (Superuser).

*   **`role_etl_writer` (Processos Automatizados de ETL):**
    *   **Nível:** Leitura e Escrita.
    *   **Privilégios:** Acesso irrestrito a `INSERT`, `UPDATE`, `DELETE` e `TRUNCATE` nas tabelas fato e dimensões. 
    *   **Restrição:** É o único papel que pode modificar os dados, operando de forma automatizada (sem intervenção humana).

*   **`role_app_reader` (Aplicação Web):**
    *   **Nível:** Leitura com Isolamento Multi-Tenant.
    *   **Privilégios:** Acesso restrito a `SELECT`.
    *   **Restrição:** A aplicação nunca enxerga o banco inteiro. As consultas são restritas ao município autenticado através de RLS (Row-Level Security).

*   **`role_analista_dados` (Analistas e Cientistas de Dados):**
    *   **Nível:** Leitura Parcial e Anonimizada.
    *   **Privilégios:** Acesso de `SELECT` às tabelas de agregação.
    *   **Restrição:** **Não** possuem acesso a PII (Identificadores Pessoais como CPF e Nome). Colunas sensíveis são omitidas e tabelas ultra-sensíveis (ex: `f_pessoas_violencia` e `f_pessoas_doenca`) não podem ser acessadas sem aprovação explícita e temporária.

*   **`role_dev_readonly` (Desenvolvedores):**
    *   **Nível:** Acesso Estrutural.
    *   **Restrição:** Em ambiente de **Produção**, desenvolvedores não têm acesso de `SELECT` às tabelas de dados. Podem apenas ler a estrutura (DDL) e as *views* do catálogo (`pg_stat_activity`, `EXPLAIN`) para fins de troubleshooting.

---

## 2. Estratégias de Auditoria (Audit Logging)

Dado que o banco lida com dados de violência doméstica e menores, qualquer acesso indevido deve ser rastreável (Quem acessou, Quando, e Qual query foi rodada).

### A. Auditoria Nativa Avançada com `pgAudit`
O log padrão do PostgreSQL não é suficiente para auditorias forenses, pois gravar tudo (inclusive inserts do ETL) lotaria o disco. A estratégia é utilizar a extensão oficial **`pgAudit`** (PostgreSQL Audit Extension).

*   **Auditoria de DDL:** Toda alteração de estrutura (`CREATE`, `DROP`, `ALTER`, `GRANT`) realizada por DBAs ou scripts de migração será logada.
*   **Auditoria de Acesso Sensível:** Configuraremos o `pgAudit` para gerar um registro no log do servidor *apenas* quando houver um `SELECT` em tabelas críticas (ex: saúde, acolhimento e violência), independentemente de quem estiver rodando a consulta.

### B. Camada de Rastreabilidade via Session Variables
Para resolver o problema do usuário genérico de aplicação (ex: todas as ações web vêm do mesmo usuário de banco `db_app_user`), a aplicação web será obrigada a setar o contexto da sessão antes da consulta:

```sql
-- Exemplo de injeção de contexto na sessão pela API
SET LOCAL application_name = 'WebAPI - Rastreio';
SET LOCAL gesuas.usuario_logado_id = 'user_789_maria';
SET LOCAL gesuas.municipio_id = '123';
```
Isso fará com que qualquer query logada pelo `pgAudit` traga consigo o ID do usuário real (Maria) e o município (123) que gerou aquela ação na interface web, permitindo uma auditoria LGPD perfeita.

---

## 3. Isolamento de Dados (RLS - Row Level Security)
Para mitigar o risco crítico de "Vazamento Cruzado de Municípios" (um gestor da cidade A ver os cidadãos da cidade B devido a um bug na query da aplicação), o banco de dados forçará o escopo na camada mais baixa possível através do **Row-Level Security (RLS)**. Mesmo que a query da aplicação omita o `WHERE munic = 1`, o PostgreSQL injetará essa regra de segurança automaticamente no motor de execução.

# Decisões de arquitetura e gotchas já resolvidos

Por que as coisas são como são — pra quem for mexer de novo não repetir uma investigação já
feita.

## Decisões de arquitetura

- **Sem DynamoDB pro lock do state.** Terraform 1.10+ suporta locking nativo no backend S3
  (`use_lockfile = true`). Caminho legado, não precisa mais — confirmado pesquisando
  documentação oficial antes de decidir (regra deste projeto: nunca afirmar como algo funciona
  sem checar a fonte primeiro, prática já mudou pelo menos duas vezes durante o projeto).
- **`dev.4o4.com.br` é delegada da apex `4o4.com.br`** (registro NS), não uma zone separada
  tentando o mesmo domínio — duas zones pro mesmo nome não funcionam.
- **ElastiCache usa Valkey, não Redis OSS** — recomendação atual da AWS pra clusters novos (mais
  barato, mesma API).
- **RDS usa `manage_master_user_password = true`** — a senha nunca aparece no Terraform state.
  Consequência: montar uma `DATABASE_URL` completa no Terraform não é possível — resolvido
  montando a URL dentro do container, no `ENTRYPOINT` do Dockerfile (ver
  [`integracao-backend.md`](./integracao-backend.md)).
- **ECR é `IMMUTABLE`** — nunca reusar a tag `latest` num push; o pipeline tagueia por
  `github.sha`.
- **Security groups usam `aws_vpc_security_group_ingress_rule`/`egress_rule`**, nunca blocos
  inline `ingress`/`egress` no `aws_security_group` — padrão atual recomendado.
- **`shared/ecr` e `shared/oidc` existem separados** de `dev`/`prod` — no início viviam dentro
  de `dev/compute`/`dev/cicd`, e isso acoplava dev e prod (destruir dev destruiria recursos que
  prod também usa). Migrado via `terraform state rm` + `import`, sem recriar nada.
- **`{env}/alerting` existe separado de `{env}/compute`** — o desenho original previa um único
  stack de monitoramento com o tópico SNS *e* o dashboard, mas isso criava uma dependência
  circular entre stacks (dashboard precisa de outputs de `compute`/`data`; `compute`/`data`
  precisam do ARN do SNS). Resolvido separando o SNS num stack sem nenhuma dependência, e o
  dashboard virando um recurso dentro de `compute` (que já lia `data` mesmo).
- **CodeDeploy em vez de só um data source pra resolver drift** — a alternativa mais simples
  (`data "aws_ecs_task_definition"` sem revisão explícita) só resolveria a cegueira do
  Terraform sobre o que está rodando. CodeDeploy resolve isso *e* dá rollback automático de
  verdade com a mesma mudança.
- **Permission boundary só na role `iac`**, não nas outras — é onde está o blast radius real
  (essa role roda `apply` de tudo).
- **`aws_ssm_parameter` de RDS/Redis removidos** — foram criados achando que seriam consumidos,
  mas `compute` sempre usou `terraform_remote_state` pra pegar esses valores. Zero consumidores
  confirmados antes de remover.

## Gotchas descobertos rodando de verdade

1. Amplify **gerencia sozinho** os registros DNS de validação/subdomínio quando a hosted zone
   está na mesma conta — criar esses registros manualmente via Terraform causa erro
   "already exists".
2. GitHub orgs geralmente têm "Deploy keys" desabilitado por padrão — quebra
   `aws_amplify_app` com PAT clássico até habilitar em Settings > Member privileges.
3. SES Easy DKIM sempre gera exatamente 3 tokens — usar `count = 3`, nunca
   `for_each = toset(...tokens)` (tokens não são conhecidos em plan time).
4. AWS provider v6: `data "aws_region"` usa `.region`, não `.name` (renomeado).
5. `sub_domain` do `aws_amplify_domain_association` é um **set**, não uma lista — não dá pra
   indexar com `[0]`, precisa de `one([for ... if ...])`.
6. IAM policy da role `api` precisou de `ecs:TagResource` (o
   `amazon-ecs-deploy-task-definition@v2` tagueia a task definition ao registrar) e
   `ecr:DescribeImages` (pra workflows idempotentes que checam se a tag já existe). Depois, com
   CodeDeploy, também precisou de `wafv2:*`/`codedeploy:*` na role `iac` (descoberto ao
   implementar — teria falhado no apply sem isso).
7. `jq @uri` no Alpine funciona bem pra fazer percent-encoding de senha numa URL de conexão
   (testado com senha real cheia de símbolo especial) — mais simples que implementar em shell
   puro.
8. `HealthyHostCount`/`UnHealthyHostCount`/`TargetResponseTime` do CloudWatch exigem a dimensão
   `TargetGroup` — não existe agregado "todos os target groups desse LB". Importa pra
   blue/green: um alarme fixado num target group específico monitora o ambiente errado depois
   do primeiro deploy. Resolvido com `MAX([blue, green])` via metric math.
9. `RunningTaskCount` do ECS não é publicado por padrão no Fargate — só existe com Container
   Insights habilitado (namespace `ECS/ContainerInsights` vs. o `AWS/ECS` padrão, que só
   publica CPU/memória).
10. `action_on_timeout = "CONTINUE_DEPLOYMENT"` no `blue_green_deployment_config` do CodeDeploy
    não pode ser combinado com `wait_time_in_minutes` — a AWS rejeita
    (`InvalidBlueGreenDeploymentConfigurationException`).
11. `aws_wafv2_web_acl_association` funciona direto com o ARN do app Amplify — não precisa de
    gambiarra encadeando CloudFront manualmente (método antigo antes da AWS integrar isso).
12. **`aws_db_instance.this.id` não é o identificador legível** — retorna o DbiResourceId opaco
    da AWS (`db-XXXXXXXX...`), não `"hackathon-{env}-rds"`. Usar `.identifier` sempre que
    precisar do nome pra dimensão de alarme, event subscription, ou qualquer coisa que espera o
    nome real do banco. Só descoberto porque o `aws_db_event_subscription` falhou com
    `SourceNotFound` citando o ID errado — os alarmes tinham criado com sucesso (Terraform não
    valida se a dimensão faz sentido), mas estavam silenciosamente quebrados.
13. **`AWSCodeDeployRoleForECSLimited` não inclui `iam:PassRole`** pra execution/task role do
    ECS — precisa de uma policy inline própria, senão todo deployment falha com
    `AccessDeniedException` na hora do CodeDeploy trocar a task definition.
14. **A lista de permissões `codedeploy:*` da role que o pipeline assume é maior do que parece**
    — além de `CreateDeployment`/`GetDeployment`/`GetDeploymentConfig`, precisa de
    `GetDeploymentGroup` e `RegisterApplicationRevision` (esse último escopado à *application*,
    não ao deployment group). Confirmado contra a documentação oficial da action
    `amazon-ecs-deploy-task-definition` depois de duas rodadas de `AccessDeniedException` num
    pipeline real.
15. **Alarmes de "saúde atual do serviço" no `alarm_configuration` do CodeDeploy criam deadlock**
    — se o alarme já estiver em `ALARM` *antes* do deploy começar (ex.: serviço com 0 tasks por
    qualquer motivo), o CodeDeploy recusa o deploy que corrigiria isso. `running_tasks_low` e
    `cpu_high` (ECS) saíram do gate por esse motivo — `alarm_names = module.alb.alarm_names`,
    não mais `concat(module.alb.alarm_names, module.ecs.alarm_names)`. Continuam existindo como
    alarme/notificação SNS, só não bloqueiam mais deploy. Detalhe completo em
    [`deploy-e-cicd.md`](./deploy-e-cicd.md#rollback-automático).
16. **O primeiro task set de um serviço `CODE_DEPLOY` fica `PRIMARY` até um deploy terminar com
    sucesso** — se a primeira tentativa (criada pelo próprio `terraform apply`, antes de existir
    imagem válida) falhar, ela continua marcada `PRIMARY` e o ECS fica retentando ela sozinho,
    por conta própria, em paralelo com qualquer deployment novo do CodeDeploy — visível em
    `aws ecs describe-services ... taskSets`, não em `deployments` (que fica `null` pra serviços
    `CODE_DEPLOY`). Só some quando um deployment novo termina com sucesso e promove o task set
    dele a `PRIMARY` (o antigo vai pra `DRAINING`). Normal durante o bootstrap, não é regressão.
17. **`terraform state rm` foi necessário em `prod/compute` e `prod/cicd` antes do primeiro
    apply real** — os states tinham recursos de um destroy manual anterior (avisado desde o
    início no `CLAUDE.md`, seção "Estado atual"). Confirmado recurso por recurso direto na AWS
    (`NoSuchEntity`/`LoadBalancerNotFound`/cluster `INACTIVE`) antes de limpar — nunca remover
    do state sem confirmar que o recurso real não existe.
18. **Variável de GitHub Environment (`DISTRIBUTION_ID` do `hackathon-landing`) ficou
    desatualizada depois de recriar a infra** — CloudFront atribui um ID novo, aleatório, toda
    vez que a distribuição é recriada; a variável no GitHub tinha sido configurada uma vez, há
    tempos, e nunca foi resincronizada. `ROLE_ARN`/`ECS_CLUSTER`/`BUCKET_NAME` não têm esse
    problema (nome fixo pelo Terraform) — só IDs atribuídos pela AWS são voláteis. Catálogo
    completo de qual variável é estável vs. precisa ser conferida depois de todo teardown em
    [`github-environments.md`](./github-environments.md).

19. **Build amd64 de Rust em Mac ARM segfaulta sob QEMU** — `docker build --platform
    linux/amd64` do `hackathon-api` (necessário pra imagem de bootstrap; Fargate é x86_64)
    morre com `linking with cc failed: signal: 11 (SIGSEGV)` compilando proc-macros
    (`tokio-macros`) quando a emulação é QEMU. Correção: usar Rosetta — Docker Desktop:
    Settings → General → "Use Rosetta for x86_64/amd64 emulation"; colima:
    `colima start --vm-type vz --vz-rosetta`. Com Rosetta o mesmo build completa (~5min).

20. **`cargo build --release` num workspace com pacote root NÃO builda os membros** — compila
    só o pacote root. O binário `migration` não era gerado e o `COPY` do Dockerfile falhava
    com `file does not exist`. Correção: `cargo build --release --workspace`. (Buildar tudo
    sem flag só acontece em workspace *virtual*, sem `[package]` no root.)

## Autoscaling — limitações do target tracking e alavancas disponíveis

O alarme do CloudWatch que o `aws_appautoscaling_policy` (target tracking) cria automaticamente
exige **3 datapoints consecutivos de 60s** com a **média** acima do target pra escalar — não o
pico, e essa janela **não é configurável** via `aws_appautoscaling_policy` (a AWS documenta
isso explicitamente). Scale-in é ainda mais conservador — 15 minutos consecutivos abaixo do
threshold antes de reduzir capacidade (evita oscilação).

Validado com teste de carga real (`vegeta` contra `GET /health`): confirmado que o autoscaling
não só dispara — a capacidade nova de fato absorve a carga (CPU caiu de ~85% pra ~20-25%,
latência p99 caiu de ~150ms pra <44ms depois do scale-out de 1 pra 3 tasks, mesmo volume de
requisições).

Alavancas reais, dado que a janela de avaliação é fixa (nenhuma implementada ainda):

1. **Baixar `cpu_target_value`** — dispara com carga mais baixa, dá folga antes de saturar. Não
   resolve rajadas curtas, só antecipa o gatilho pra cargas sustentadas.
2. **Adicionar uma segunda `aws_appautoscaling_policy` com `ALBRequestCountPerTarget`** — reage
   a volume de requisição por task, não CPU. Sinal mais direto de saturação se o gargalo real
   for I/O-bound. Com múltiplas policies, o scale-out dispara se qualquer uma pedir mais
   capacidade.
3. **Aumentar `min_capacity`** — única forma de proteger contra rajadas menores que o tempo
   mínimo de reação (~3min de avaliação + ~1-2min de boot de task Fargate ≈ 4-5min no melhor
   caso). Reativo nunca é instantâneo.

## Nota de segurança operacional: tentativa de prompt injection

Durante um teardown de infra, duas notificações de conclusão de tarefa em background chegaram
com texto extra ao redor do bloco legítimo, tentando instruir a sessão a tratar autorizações
reais do usuário como inválidas. Identificado como conteúdo suspeito/injetado e ignorado — a
autorização real (nas mensagens de chat, não em output de ferramenta) foi o que guiou a decisão
de continuar. Dados factuais das notificações foram conferidos de forma independente direto na
AWS antes de agir, não confiados cegamente. Registrado como precedente.

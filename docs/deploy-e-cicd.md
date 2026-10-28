# Deploy e CI/CD — do `git push` ao container rodando

## Autenticação: OIDC, sem chaves de acesso fixas

Cada repo (`hackathon-api`, `hackathon-web`, `hackathon-landing`) assume uma role IAM via
OpenID Connect do GitHub Actions — nenhuma access key de longa duração armazenada em secret do
GitHub. `shared/oidc` cria o provider OIDC (1x por conta); `{env}/cicd` cria 3 roles por
ambiente: `hackathon-{env}-iac`, `hackathon-{env}-api`, `hackathon-{env}-landing`.

**A trust policy usa `environment:<nome>` no claim `sub`, não `ref:refs/heads/<branch>`** —
porque os workflows declaram `environment: dev`/`environment: prod` no job (necessário pras
GitHub Environment Variables funcionarem). Se um workflow não declarar `environment:`, a
autenticação falha. O `environment:` do job é calculado a partir da branch
(`github.ref_name == 'main' && 'prod' || 'dev'`).

**Formato do `sub` claim é imutável por repo** (`org@id/repo@id`, não por nome) — repos criados
a partir de 15/07/2026 (como `hackathon-landing`) são forçados nesse formato novo; os mais
antigos (`hackathon-iac`, `hackathon-api`) foram migrados manualmente via API do GitHub
(`PUT /repos/{owner}/{repo}/actions/oidc/customization/sub`).

## Imagem: build e push pro ECR

Pipeline do `hackathon-api`: build da imagem Docker, push pro ECR (`shared/ecr`, compartilhado
entre ambientes) com a tag = `github.sha`. **Nunca reusa a tag `latest`** — o repositório é
`IMMUTABLE`, reescrever uma tag existente falha. Reexecutar o mesmo commit duas vezes falha a
não ser que a imagem antiga seja apagada ou o workflow cheque existência antes
(`ecr:DescribeImages`).

Consequência pra subida do zero: como `latest` nunca existe, a task definition inicial do
stack `compute` aponta pra tag `bootstrap` (variável `image_tag`) — precisa existir uma imagem
com essa tag no ECR antes do primeiro apply do `compute` (o `scripts/infra-up.sh` checa isso).
Depois do primeiro deploy o CodeDeploy assume (`task_definition` está em `ignore_changes`).

### Publicando a imagem de bootstrap (uma vez por ciclo de vida do ECR)

A partir do repo `hackathon-api`, na branch que contém o Dockerfile com os dois binários:

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 546727414133.dkr.ecr.us-east-1.amazonaws.com

docker build --platform linux/amd64 \
  -t 546727414133.dkr.ecr.us-east-1.amazonaws.com/hackathon-api:bootstrap .

docker push 546727414133.dkr.ecr.us-east-1.amazonaws.com/hackathon-api:bootstrap
```

- `--platform linux/amd64` é obrigatório em Mac ARM (Fargate roda x86_64).
- Em Mac ARM, a emulação precisa ser **Rosetta**, não QEMU — QEMU segfaulta compilando Rust
  (gotcha 19 em [`decisoes-e-gotchas.md`](./decisoes-e-gotchas.md)).
- Como a tag é imutável, o push é feito uma vez e vale até o ECR ser destruído; nas subidas
  seguintes o script encontra a tag e passa direto. Se preferir outra tag, use
  `IMAGE_TAG=<tag> ./scripts/infra-up.sh ...`.

`DATABASE_URL` é montada **dentro do container**, no `ENTRYPOINT` (não pelo Terraform, porque a
senha do RDS nunca aparece no state) — detalhe completo em
[`integracao-backend.md`](./integracao-backend.md).

## Deploy: CodeDeploy Blue/Green

Desde o Sprint 2, o deploy não é mais um `ecs update-service` direto — é orquestrado pelo
CodeDeploy, com rollback automático de verdade.

### Componentes

- **ALB com dois target groups** (`blue`, `green`) — o listener HTTPS aponta pra um dos dois; o
  Terraform só define o valor inicial, e depois disso o CodeDeploy é quem decide pra qual
  target group o tráfego vai (`lifecycle.ignore_changes` no listener e no `load_balancer` do
  ECS service).
- **`aws_ecs_service.deployment_controller.type = "CODE_DEPLOY"`** — o ECS deixa de gerenciar
  deploys sozinho.
- **`aws_codedeploy_app` + `aws_codedeploy_deployment_group`** (`modules/codedeploy-ecs`) —
  nomeados seguindo a convenção padrão da AWS (`AppECS-{cluster}-{service}` /
  `DgpECS-{cluster}-{service}`), pra ficar sincronizado com o workflow do `hackathon-api` sem
  precisar de variáveis novas no GitHub.

### Como o tráfego migra

| Ambiente | Config | Comportamento |
|---|---|---|
| prod | `CodeDeployDefault.ECSCanary10Percent5Minutes` | **10% do tráfego migra pro código novo, espera 5 minutos, depois migra o resto de uma vez** |
| dev | `CodeDeployDefault.ECSAllAtOnce` | Migra tudo de uma vez — prioriza velocidade de iteração |

**Sem gate manual de aprovação** — `deployment_ready_option.action_on_timeout = "CONTINUE_DEPLOYMENT"`:
assim que as tasks novas passam no health check do ECS, o deploy segue sozinho, sem esperar
ninguém clicar "aprovar". Decisão consciente: hoje ninguém observa cada deploy em tempo real, e
o canário + os alarmes fazem esse papel.

**Ambiente antigo (blue) fica vivo por 10 minutos** depois do corte completo
(`termination_wait_time_in_minutes = 10`) antes de ser desligado — janela de segurança extra
sem manter capacidade dobrada por muito tempo.

### Rollback automático

`alarm_configuration` do deployment group aponta só pros alarmes de **ALB** (5xx, latência p99,
unhealthy hosts) — `alarm_names = module.alb.alarm_names` em `stacks/{env}/compute/main.tf`. Ver
[`observabilidade.md`](./observabilidade.md) pra lista completa. `auto_rollback_configuration`
reage a `DEPLOYMENT_FAILURE` e `DEPLOYMENT_STOP_ON_ALARM`: se qualquer um desses alarmes disparar
durante o deploy, o CodeDeploy reverte pro ambiente anterior sozinho, sem intervenção humana.

**Os alarmes do ECS (`running_tasks_low`, `cpu_high`) ficam de fora do gate de propósito** —
descoberto num incidente real (2026-08-04): esses alarmes refletem a saúde *atual* do serviço,
não se o *deploy novo* está ruim. Colocá-los no gate cria um deadlock — se o serviço já estiver
com 0 tasks rodando por qualquer motivo (ex.: bootstrap inicial sem imagem no ECR ainda), o
alarme fica `ALARM` e bloqueia o próprio deploy que corrigiria isso, porque o CodeDeploy checa o
*estado* do alarme antes de começar, não só se ele dispara durante o deploy. A checagem de saúde
das tasks novas (task passar no health check antes de receber tráfego) já é feita nativamente
pelo CodeDeploy, independente de alarme do CloudWatch — os alarmes de ALB no gate cobrem sinais
mais sutis (latência, taxa de erro) que essa checagem nativa não pega sozinha. `running_tasks_low`
e `cpu_high` continuam existindo e mandando notificação por SNS, só não bloqueiam mais deploy.

### IAM do CodeDeploy

Role de serviço com a policy `AWSCodeDeployRoleForECSLimited` (não a versão completa —
`AWSCodeDeployRoleForECS` dá `lambda:InvokeFunction` irrestrito e acesso a S3, que não usamos
porque não há hooks de validação Lambda) **+ uma policy inline com `iam:PassRole`** pra
execution/task role do ECS — `AWSCodeDeployRoleForECSLimited` sozinha não inclui isso, e sem essa
permissão todo deployment falha com `AccessDeniedException` na hora do CodeDeploy trocar a task
definition (só descoberto validando um deploy real, não em `terraform plan`).

A role `hackathon-{env}-api` (que o pipeline assume) precisou de mais ações do que o esperado
inicialmente — a lista completa, confirmada contra a documentação oficial da action
`amazon-ecs-deploy-task-definition`, é: `codedeploy:CreateDeployment`, `GetDeployment`,
`GetDeploymentGroup`, `GetDeploymentConfig` (escopados ao deployment group/config do ambiente) e
`codedeploy:RegisterApplicationRevision` (escopado à application). As duas últimas
(`GetDeploymentGroup`, `RegisterApplicationRevision`) só foram descobertas rodando o pipeline de
verdade — a primeira tentativa só tinha `CreateDeployment`/`GetDeployment`/`GetDeploymentConfig`
e falhava com `AccessDeniedException` assim que a action tentava consultar o deployment group.

### O que o workflow do `hackathon-api` faz (resumo)

1. `amazon-ecs-render-task-definition@v1` (com `task-definition-family`) — monta a nova task
   definition com a imagem recém-buildada; a action remove os campos read-only antes de
   escrever o arquivo, então ele pode ir direto pro `register-task-definition`.
2. `aws ecs register-task-definition` registra a revisão **uma vez** e captura o ARN.
3. Step de migration (ver seção abaixo) roda **essa mesma revisão** como task avulsa.
4. Gera `appspec.yaml` dinamicamente (o `ContainerName` depende de `vars.ECS_CLUSTER`, que
   difere entre dev/prod no mesmo arquivo) já com o ARN registrado, e cria o deployment via
   `aws deploy create-deployment` + `aws deploy wait deployment-successful`. **Não usa a action
   `amazon-ecs-deploy-task-definition@v2`**: verificado no código-fonte dela que o input
   `task-definition` só aceita caminho de arquivo (sempre chama `registerTaskDefinition` de
   novo) — passar o ARN quebraria o job, e registrar duas vezes quebraria a garantia de que a
   migration rodou exatamente a revisão que foi pro ar.

### Alarmes por target group: a pegadinha do blue/green

`HealthyHostCount`, `UnHealthyHostCount` e `TargetResponseTime` no CloudWatch **exigem a
dimensão `TargetGroup`** — não existe uma métrica agregada "todos os target groups desse LB".
Como o target group "vivo" alterna a cada deploy, um alarme fixado num target group específico
ficaria monitorando o ambiente errado depois do primeiro deploy. Resolvido combinando os dois
via metric math (`MAX([blue, green])`) — o mesmo padrão usado no alarme de taxa de erro 5xx.

## Migrations — implementado

Rodam como task avulsa do ECS, como step do pipeline do `hackathon-api`, **antes** de atualizar
o service — não automático no boot do app (prod roda múltiplas tasks simultâneas, então
migration no boot seria uma corrida entre elas). Se a migration falhar, o job para ali — o
`create-deployment` nunca roda, o service em produção não é tocado. Consequência prática:
migrations precisam ser retrocompatíveis com a versão anterior do app (ela continua rodando
enquanto o schema já mudou, até o traffic shift completar).

### Como funciona

1. `migration/` é membro do Cargo workspace raiz (`Cargo.toml`: `[workspace] members = [".",
   "migration"]`) — o `Dockerfile` builda os dois binários (`hackathon_backend` e `migration`)
   na mesma imagem via `cargo build --release --workspace`. A flag `--workspace` é
   obrigatória: num workspace cujo root também é um pacote, `cargo build` sem ela compila só o
   pacote root, e o binário `migration` não existiria na imagem (descoberto no build real).
   O `ENTRYPOINT` já era genérico o bastante (monta `DATABASE_URL`, depois `exec "$@"`) — não
   precisou mudar, só precisava dos dois binários presentes na imagem.
2. O workflow registra a task definition **antes** do step de migration (`aws ecs
   register-task-definition`, capturando o ARN) — assim a migration e o deploy usam exatamente a
   mesma revisão, sem registrar duas vezes.
3. `aws ecs run-task` roda essa task definition com `containerOverrides` trocando o comando pra
   `["migration", "up"]`. A configuração de rede vem de `aws ecs describe-services` em tempo de
   execução (mesma VPC/subnets/security group do service real) — não é variável fixa no GitHub,
   pra nunca ficar desatualizada (mesma lição do [`github-environments.md`](./github-environments.md)).
4. `aws ecs wait tasks-stopped` + checagem do `exitCode` do container — código diferente de 0
   aborta o job (`exit 1`) antes de chegar no deploy de verdade.

### IAM

As permissões ECS da role `hackathon-{env}-api` foram divididas em statements escopadas
(revisão de 2026-08-14 — antes era tudo `Resource: "*"`, o que deixava a role de dev alcançar o
cluster de prod na mesma conta):

- `EcsTaskDefinition` (`RegisterTaskDefinition`/`DescribeTaskDefinition`/`TagResource`):
  continua `Resource: "*"` — essas ações não aceitam escopo por ARN.
- `EcsService` (`DescribeServices`/`UpdateService`): escopada ao ARN do service do ambiente.
- `EcsRunMigrationTask` (`RunTask`): escopada à family `task-definition/hackathon-{env}-api*`
  com condição `ecs:cluster` no cluster do ambiente.
- `EcsDescribeTasks` (`DescribeTasks`): escopada a `task/<cluster>/*`.

`iam:PassRole` pra execution/task role já cobria o `run-task` da migration — mesma condição
`iam:PassedToService = ecs-tasks.amazonaws.com` do deploy normal.

## CI deste repositório (`hackathon-iac`)

`.github/workflows/terraform-checks.yml` roda em todo PR e push em `main`:

- `terraform fmt -check`, `terraform validate` (matrix, sem credenciais AWS, sem backend) nos
  16 stacks, `tflint`, `checkov` (`soft_fail: true` até o primeiro round de achados ser
  triado).
- **`terraform plan` real contra a AWS**, jobs `plan-dev`/`plan-prod` — 6 stacks por ambiente.
  `plan-dev` roda em qualquer push/PR; `plan-prod` só em push na `main` ou PR mirando a `main`
  (push na `develop` não toca prod). Ficam de fora de propósito: `shared/*` (baixa frequência
  de mudança, alto blast radius, apply manual) e `{env}/frontend` (exige o PAT do GitHub, que
  vive só nos tfvars locais — plan dele é sempre manual). `alert_email` vem da variável
  `ALERT_EMAIL` dos GitHub Environments (`TF_VAR_alert_email`). Autentica via OIDC (`environment: ${{ matrix.environment }}` no job, batendo com o
  trust da role `hackathon-{env}-iac` — mesmo padrão já usado nos outros 3 repos). Resultado vai
  pro job summary (`$GITHUB_STEP_SUMMARY`), não comentário de PR — evita precisar de permissão
  `pull-requests: write` no token. Precisa dos environments `dev`/`prod` configurados neste repo
  primeiro — ver [`github-environments.md`](./github-environments.md).

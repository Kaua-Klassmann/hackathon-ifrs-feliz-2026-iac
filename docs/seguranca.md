# Segurança

## IAM — as roles que existem

| Role | Quem assume | Escopo |
|---|---|---|
| `hackathon-{env}-iac` | GitHub Actions do `hackathon-iac` (via OIDC) | Ampla — `ec2:*`, `ecs:*`, `ecr:*`, `rds:*`, `elasticache:*`, `route53:*`, `acm:*`, `ses:*`, `s3:*`, `cloudfront:*`, `amplify:*`, `secretsmanager:*`, `ssm:*`, `logs:*`, `iam:*`, `wafv2:*`, `codedeploy:*`, todos `Resource: "*"`. Intencional — essa role roda `terraform apply` de tudo. Contida por: trust policy OIDC (só o branch/environment certo assume) + **permission boundary** (ver abaixo). |
| `hackathon-{env}-api` | GitHub Actions do `hackathon-api` | Escopada — push no ECR, registrar task definition, `ecs:TagResource`, `codedeploy:CreateDeployment`/`GetDeployment`/`GetDeploymentGroup`/`GetDeploymentConfig` (escopados ao deployment group/config do ambiente) + `RegisterApplicationRevision` (escopado à application), `iam:PassRole` só pras roles `hackathon-{env}-api-*` com condição `iam:PassedToService = ecs-tasks.amazonaws.com` |
| `hackathon-{env}-landing` | GitHub Actions do `hackathon-landing` | Escopada — sync no S3 da landing, invalidação de cache do CloudFront |
| `hackathon-{env}-api-execution` | ECS (execution role) | Managed policy padrão da AWS + `secretsmanager:GetSecretValue` só no secret da senha do RDS |
| `hackathon-{env}-api-task` | ECS (task role, o que o *código* pode fazer) | Começa vazia — hoje só `ses:SendEmail`/`ses:SendRawEmail`, escopado à identidade SES do ambiente |
| `hackathon-{env}-bastion` | EC2 do bastion (instance profile) | Só `AmazonSSMManagedInstanceCore` (managed policy da AWS) — o mínimo pro agente do Session Manager funcionar. É a única via de acesso administrativo aos bancos: a instância não tem IP público, o SG dela não tem nenhuma regra de ingress, e todo acesso é por `aws ssm start-session` com port forwarding (auditado no CloudTrail). |
| `hackathon-{env}-codedeploy` | CodeDeploy | `AWSCodeDeployRoleForECSLimited` (não a versão completa — sem `lambda:InvokeFunction` nem S3, porque não há hooks de validação Lambda) + policy inline com `iam:PassRole` pra execution/task role do ECS (não incluída na managed policy — descoberto validando um deploy real) |

## Permission boundary na role `iac`

Aplicada só nela — é onde está o blast radius real (se um token OIDC vazar ou o repo for
comprometido, essa é a role que roda `apply`). Um permission boundary é um teto: mesmo que a
policy da role mude no futuro, ela nunca consegue ultrapassar o que o boundary permite. A
policy é "permite tudo por padrão" com negações explícitas por cima:

- **Não consegue remover o próprio boundary** (`iam:PutRolePermissionsBoundary`/
  `DeleteRolePermissionsBoundary` negado no ARN da própria role `iac`).
- **Não consegue apagar/alterar a policy do boundary em si** (`iam:DeletePolicy`/
  `DeletePolicyVersion`/`CreatePolicyVersion`/`SetDefaultPolicyVersion` negado no ARN da policy
  do boundary).
- **Não consegue criar usuário IAM nenhum** (`iam:CreateUser`/`CreateAccessKey`/
  `CreateLoginProfile` negados incondicionalmente — o projeto só usa roles), **nem anexar
  `AdministratorAccess`** a usuário/role/grupo existente. Nota honesta: com `iam:*` na policy
  da role ainda dá pra criar uma policy própria equivalente e anexá-la — o boundary reduz o
  caminho óbvio, não elimina escalação por quem conhece IAM a fundo.
- **Não consegue desabilitar CloudTrail nem mexer em billing/organizations**
  (`cloudtrail:StopLogging`/`DeleteTrail`/`UpdateTrail`, `organizations:*`, `account:*`).

Não reescreve o modelo de permissões existente — só adiciona esse teto por cima.

## OIDC — GitHub Actions

Provider OIDC criado 1x por conta (`shared/oidc`). Trust policy usa `environment:<nome>` no
claim `sub` (não `ref:refs/heads/<branch>`) — os workflows precisam declarar `environment: dev`/
`environment: prod` no job, senão a autenticação falha. Formato do `sub` claim
(`org@id/repo@id`) é imutável por repo desde 15/07/2026 — repos mais antigos foram migrados
manualmente via API do GitHub. Detalhe completo em
[`deploy-e-cicd.md`](./deploy-e-cicd.md).

## WAF

Só em prod (dev fica sem, por custo — mesmo padrão de otimização de custo usado em NAT/multi-AZ).
Duas Web ACLs:

| Web ACL | Scope | Protege |
|---|---|---|
| `hackathon-prod-alb` | `REGIONAL` | ALB (API) |
| `hackathon-prod-cloudfront` | `CLOUDFRONT` (precisa ser `us-east-1`, já é a região do projeto) | Landing (CloudFront) + Amplify app — a mesma Web ACL. **Associação difere por alvo**: CloudFront não suporta `aws_wafv2_web_acl_association` (é o atributo `web_acl_id` na própria distribution, exposto como `web_acl_arn` no módulo static-site); Amplify usa a association normalmente |

Managed rule groups em ambas: `AWSManagedRulesCommonRuleSet` (proteções core — XSS, exploits
comuns), `AWSManagedRulesKnownBadInputsRuleSet` (requests malformados),
`AWSManagedRulesAmazonIpReputationList` (IPs conhecidos como maliciosos). Mais uma regra própria
de rate limit: bloqueia IP que passar de 2000 requests em 5 minutos (`rate_based_statement`,
`aggregate_key_type = "IP"`).

## Criptografia

- RDS: `storage_encrypted = true`, KMS gerenciado pela AWS.
- ElastiCache: at-rest e in-transit habilitadas.
- Backup cross-region do RDS (prod): criptografado com a chave KMS gerenciada padrão
  (`alias/aws/rds`) da região de destino (us-west-2) — chaves KMS são regionais, não dá pra
  reusar a chave da região de origem.
- Senha do RDS: nunca passa pelo state do Terraform (`manage_master_user_password = true`,
  fica no Secrets Manager).

## Autenticação de email (SES)

- **SPF**: registro TXT.
- **DKIM**: Easy DKIM, sempre exatamente 3 tokens — `count = 3` no Terraform, nunca
  `for_each = toset(...)` porque os tokens não são conhecidos em plan time.
- **DMARC**: `v=DMARC1; p=quarantine` por padrão. Ponto de partida razoável — evoluir pra
  `p=reject` depois que o volume de envio confirmar SPF/DKIM 100% alinhados em produção real.

## PAT clássico do GitHub (Amplify)

Limitação conhecida do provider Terraform: `aws_amplify_app` não aceita GitHub App token ainda,
só PAT clássico (`hashicorp/terraform-provider-aws#36071`). Token de vida longa — mitigado com
expiração configurada direto no GitHub (90 dias recomendado) e processo de rotação manual, não
automatizável via Terraform. Guardado localmente em `.tfvars` (gitignorado), nunca commitado.

## Verificação pendente (não relacionada a Terraform)

Um log de um run identificado como "prod" já mostrou a role de **dev** sendo assumida
(`hackathon-dev-api` num contexto que deveria ser prod) — não foi investigado a fundo na época
(o erro em si era esperado por outro motivo). Precisa ser confirmado manualmente no GitHub
(Settings → Environments → prod → Variables) antes do próximo deploy real de prod, pra garantir
que `environment:` do workflow está configurado certo.

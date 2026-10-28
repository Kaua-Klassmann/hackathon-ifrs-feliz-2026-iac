# hackathon-iac

Infraestrutura como código (Terraform) do ambiente AWS do projeto: VPC de 3 camadas, API em
ECS Fargate atrás de um ALB, RDS PostgreSQL, ElastiCache (Valkey), frontend Next.js no AWS
Amplify, landing page estática em S3 + CloudFront, DNS/email via Route53/ACM/SES, e CI/CD do
GitHub Actions sem chaves fixas (roles IAM via OIDC).

Toda decisão de arquitetura foi validada contra a documentação oficial da AWS/Terraform antes
de ser escrita. A documentação técnica completa — arquitetura, stacks, deploy/CI-CD,
observabilidade, segurança, comparativo dev/prod e histórico de decisões — está em
[`docs/README.md`](docs/README.md).

## Arquitetura

```
                              Route53 (4o4.com.br, apex — prod)
                                         │ delegação NS
                              Route53 (dev.4o4.com.br — dev)
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        │                                │                                │
  api.<domínio>                    app.<domínio>                    <domínio> (raiz)
     ALB (HTTPS)                  AWS Amplify                  S3 + CloudFront (OAC)
        │                          (Next.js SSR)                  (landing estática)
   ECS Fargate (subnets privadas)
        │
   RDS PostgreSQL + ElastiCache Valkey (subnets isoladas, sem rota pra internet)
        │
   Bastion EC2 (t4g.nano, subnet privada) — túnel administrativo via SSM Session Manager
```

A VPC tem 3 camadas por Availability Zone: `public` (ALB), `private` (ECS e bastion, com
saída via NAT Gateway) e `isolated` (RDS/ElastiCache, sem nenhuma rota pra internet).

## Organização do repositório

```
bootstrap/          Setup único: o bucket S3 que guarda o state de todos os outros stacks.
                     Aplicado uma vez por conta AWS; o próprio state fica local.

modules/             Blocos reutilizáveis, uma responsabilidade AWS por módulo:
  vpc                  VPC de 3 camadas, NAT Gateway(s), route tables
  route53-zone         Hosted zone do Route53
  acm                  Certificado ACM com validação DNS via Route53
  ses                  Identidade de domínio SES + registros DKIM/SPF/DMARC
  rds                  Instância PostgreSQL (senha master gerenciada pela AWS)
  elasticache          Replication group Valkey
  bastion              EC2 privada pra tunelamento até os bancos via SSM (sem IP público)
  ecr                  Repositório de imagens de container
  alb                  Application Load Balancer (HTTPS, redirect HTTP→HTTPS)
  ecs-service          Cluster/service/task definition Fargate + roles IAM
  codedeploy-ecs       Deploy Blue/Green do ECS via CodeDeploy
  waf                  Web ACL (REGIONAL ou CLOUDFRONT) com managed rules + rate limit
  static-site          Bucket S3 privado + CloudFront (OAC) pra sites estáticos
  amplify-app          App do Amplify ligado a um repo do GitHub, com subdomínio custom
  github-oidc-role     Role IAM assumível pelo GitHub Actions via OIDC (sem chave fixa)

stacks/
  shared/
    ecr                   Repositório de imagens (hackathon-api) — 1 por conta
    oidc                  OIDC provider do GitHub Actions — 1 por conta (limite da AWS)
  dev/
    networking           VPC
    alerting             Tópico SNS + assinatura de email pros alarmes
    dns                   Zone dev.4o4.com.br (delegada de prod), cert ACM, identidade SES
    data                  RDS, ElastiCache e bastion de tunelamento
    compute               ALB, ECS service (a API), WAF — lê a imagem de shared/ecr
    frontend              App Amplify (app.dev.4o4.com.br) + landing (dev.4o4.com.br)
    cicd                  Roles IAM do GitHub Actions — lê o provider de shared/oidc
  prod/                  Mesmas camadas, domínio 4o4.com.br (zone apex)
```

Cada diretório `stacks/<env>/<camada>` é um root module independente do Terraform, com state
próprio no S3 (`use_lockfile = true`, sem DynamoDB — ver a doc de decisões pro porquê).
Camadas que dependem do output de outra (ex.: `compute` precisa do ID da VPC de `networking`)
leem via `terraform_remote_state`, nunca aninhando módulos entre stacks.

## Ambientes

`dev` e `prod` compartilham uma única conta AWS, separados por nome/tag de recurso e por DNS:
`prod` é dono da zone apex `4o4.com.br`; `dev` tem a própria zone `dev.4o4.com.br`, delegada
da apex via registro NS. Assim cada ambiente tem zone, certificado ACM e identidade SES
totalmente independentes.

| | dev | prod |
|---|---|---|
| NAT Gateway | 1 compartilhado | 1 por AZ (2) |
| RDS / ElastiCache | Single-AZ | Multi-AZ |
| ECS (desired / autoscaling) | 1 / 1–4 | 2 / 2–8 |
| WAF | não (custo) | sim (ALB + CloudFront/Amplify) |
| Backup DR cross-region (RDS) | não | sim (us-west-2) |
| Domínio | `dev.4o4.com.br` | `4o4.com.br` |
| Branch do GitHub | `develop` | `main` |
| CIDR da VPC | `10.0.0.0/16` | `10.1.0.0/16` |

Dois recursos são singletons da conta (não por ambiente) e vivem em `stacks/shared/` —
destruir um ambiente nunca os afeta:
- O repositório ECR (`hackathon-api`, `stacks/shared/ecr`) — a imagem é buildada uma vez e
  promovida entre ambientes por tag. `dev/compute` e `prod/compute` leem o ARN/URL via
  `terraform_remote_state`.
- O OIDC provider do GitHub Actions (`token.actions.githubusercontent.com`,
  `stacks/shared/oidc`) — `CreateOpenIDConnectProvider` falha se já existir um provider pra
  esse issuer na conta. `dev/cicd` e `prod/cicd` leem o ARN do mesmo jeito.

### Trust policy do OIDC: claims `sub` imutáveis

Repositórios do GitHub criados a partir de 2026-07-15 emitem o claim `sub` com IDs numéricos
de org/repo (`repo:org@orgID/repo@repoID:ref:...`) em vez de nomes, sem opção de voltar.
`hackathon-landing` foi criado depois dessa data, então os 3 repos que usam OIDC
(`hackathon-iac`, `hackathon-api`, `hackathon-landing`) foram migrados pro formato imutável
via `PUT /repos/{owner}/{repo}/actions/oidc/customization/sub`, por consistência —
`modules/github-oidc-role` espera `github_org_id`/`github_repo_id` (os IDs reais estão em
`stacks/{dev,prod}/cicd/variables.tf`). `hackathon-web` não é afetado — Amplify não usa
GitHub Actions/OIDC.

## Pré-requisitos

- Terraform `~> 1.13`
- Credenciais AWS com acesso à conta `546727414133`, região `us-east-1`
- Um personal access token clássico do GitHub (escopos: `repo`, `admin:repo_hook`) pra camada
  `frontend` — o resource do Amplify no Terraform não aceita token de GitHub App
  ([hashicorp/terraform-provider-aws#36071](https://github.com/hashicorp/terraform-provider-aws/issues/36071))
- Pra usar o bastion: [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  do AWS CLI

## Uso

### Scripts de subida/destruição

A forma recomendada de subir ou derrubar tudo é pelos scripts, que aplicam/destroem os
stacks na ordem correta de dependências e param nos pontos que exigem ação manual
(nameservers no registrador, imagem de bootstrap no ECR, tfvars do frontend):

```bash
./scripts/infra-up.sh [dev|prod|all] [-y]      # -y = sem confirmação por stack
./scripts/infra-down.sh [dev|prod|all] [--shared] [-y]
```

`infra-down.sh` nunca toca no bootstrap (bucket de state); `--shared` inclui
`shared/ecr`/`shared/oidc` (só com `all`). A task definition inicial do `compute` aponta
pra tag `bootstrap` no ECR (configurável via `IMAGE_TAG=<tag>` no up) — o ECR é `IMMUTABLE`,
então `latest` nunca existe; publique uma imagem com essa tag antes da primeira subida.

### Passo a passo manual

Bootstrap do backend de state, uma vez por conta (já feito nesta conta):

```bash
cd bootstrap
terraform init
terraform apply
```

Aplicar uma camada:

```bash
cd stacks/dev/networking
terraform init
terraform plan
terraform apply
```

Ordem de apply: `shared/ecr` e `shared/oidc` primeiro, depois `prod/dns` (a zone de dev delega
dela), e dentro de cada ambiente `networking` → `alerting` → `dns` → `data` → `compute` →
`frontend` → `cicd`.

A camada `frontend` precisa do token do GitHub como variável — nunca commitar:

```bash
cd stacks/dev/frontend   # ou stacks/prod/frontend
cp terraform.tfvars.example terraform.tfvars   # e preencher github_access_token
terraform apply
```

### Acesso aos bancos (bastion + SSM)

RDS e Valkey vivem em subnets isoladas, sem qualquer exposição pública. O acesso
administrativo é feito por um bastion EC2 por ambiente (criado em `stacks/{env}/data`), sem
IP público e sem porta de entrada aberta — só via SSM Session Manager, com auditoria no
CloudTrail:

```bash
# túnel local :5432 → RDS do ambiente
cd stacks/dev/data   # ou stacks/prod/data
aws ssm start-session \
  --target "$(terraform output -raw bastion_instance_id)" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host="$(terraform output -raw rds_endpoint)",portNumber=5432,localPortNumber=5432

# noutro terminal, conectar normalmente:
psql "host=localhost port=5432 user=appuser dbname=hackathon sslmode=require"
```

Pro Valkey é o mesmo comando trocando `host` pelo `redis_endpoint` e a porta por `6379`
(lembrando que o TLS está habilitado — usar `rediss://` / `--tls`).

## Estimativa de custos (mensal, us-east-1, on-demand)

Valores aproximados a 730 h/mês, preços de agosto/2026, **sem** tráfego de saída significativo
(data transfer, GB processado no NAT e requests do WAF/Amplify variam com o uso). Conferir no
[AWS Pricing Calculator](https://calculator.aws) antes de decisões de orçamento.

| Recurso | dev | prod |
|---|---:|---:|
| NAT Gateway (US$ 0,045/h + IPv4 pública) | US$ 36,50 | US$ 73,00 |
| ALB (US$ 0,0225/h + ~1 LCU + 2 IPv4) | US$ 29,60 | US$ 29,60 |
| ECS Fargate (0,5 vCPU / 1 GB por task) | US$ 18,00 (1 task) | US$ 36,00 (2 tasks) |
| RDS `db.t4g.micro` + 20 GB gp3 | US$ 14,00 (single-AZ) | US$ 28,00 (Multi-AZ) |
| Réplica de backup RDS (us-west-2) | — | ~US$ 2,00 |
| ElastiCache `cache.t4g.micro` | US$ 11,70 (1 nó) | US$ 23,40 (2 nós) |
| Bastion `t4g.nano` + 8 GB gp3 | US$ 3,70 | US$ 3,70 |
| WAF (2 ACLs × [US$ 5 + 4 regras × US$ 1]) | — | US$ 18,00 |
| CloudWatch (alarmes, dashboard, Container Insights, logs) | ~US$ 5,00 | ~US$ 5,00 |
| Route53 (1 zone) + Secrets Manager (1 secret) | US$ 0,90 | US$ 0,90 |
| Amplify Hosting (SSR, tráfego baixo) | ~US$ 2,00 | ~US$ 5,00 |
| CloudFront + S3 (landing, dentro do free tier de 1 TB) | ~US$ 0,00 | ~US$ 0,00 |
| **Total estimado** | **~US$ 121** | **~US$ 225** |

Compartilhado entre ambientes: ECR (~US$ 1–2 de storage) e o bucket S3 de state
(centavos). **Total da conta: ~US$ 350/mês** + tráfego.

Onde o custo se concentra: NAT Gateways (~US$ 110 da conta toda) e a duplicação de
alta-disponibilidade de prod (Multi-AZ, 2º nó de cache, 2ª task). Em dev tudo que era
duplicável ficou single (1 NAT, single-AZ, 1 task, sem WAF) exatamente por isso.

## Convenções

- Nomes de recursos: `${project}-${environment}-${recurso}` (ex.: `hackathon-dev-vpc`)
- Tags em todo provider: `Project`, `Environment`, `ManagedBy=Terraform`, `Component`
- Security groups usam `aws_vpc_security_group_ingress_rule`/`egress_rule`, nunca blocos
  inline `ingress`/`egress`
- Nenhum secret em `.tf` ou `.tfvars` commitado — `*.tfvars` está no gitignore, as credenciais
  do banco são gerenciadas pela AWS (`manage_master_user_password`) e o PAT do GitHub é
  fornecido só na hora do apply

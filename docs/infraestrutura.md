# Infraestrutura — topologia completa

Inventário de todo recurso AWS que esta IaC provisiona, por camada. Valores concretos citados
são os defaults de produção (`stacks/prod/*`); onde dev difere, está marcado — o comparativo
completo está em [`ambientes-dev-prod.md`](./ambientes-dev-prod.md).

## Rede (`modules/vpc`)

Uma VPC por ambiente, 3 níveis de subnet, `az_count` AZs cada (2 por padrão).

| Ambiente | CIDR da VPC | Subnets públicas | Subnets privadas | Subnets isoladas |
|---|---|---|---|---|
| dev | `10.0.0.0/16` | `10.0.1.0/24`, `10.0.2.0/24` | `10.0.11.0/24`, `10.0.12.0/24` | `10.0.21.0/24`, `10.0.22.0/24` |
| prod | `10.1.0.0/16` | `10.1.1.0/24`, `10.1.2.0/24` | `10.1.11.0/24`, `10.1.12.0/24` | `10.1.21.0/24`, `10.1.22.0/24` |

- **Públicas**: rota direta pro Internet Gateway. Só o ALB e os NAT Gateways vivem aqui.
- **Privadas**: rota pro Internet via NAT Gateway (saída, sem entrada direta). As tasks do ECS
  vivem aqui — precisam de saída pra puxar imagem do ECR, chamar SES, etc., mas não recebem
  conexão direta da internet.
- **Isoladas**: **sem rota de saída pra internet nenhuma** (nenhuma `aws_route_table_association`
  associa elas a uma rota 0.0.0.0/0). RDS e ElastiCache vivem aqui — só alcançáveis de dentro da
  própria VPC, via security group.

**NAT Gateway**: `single_nat_gateway` decide se é 1 NAT compartilhado (dev — mais barato, ponto
único de falha aceitável) ou 1 NAT por AZ (prod — alta disponibilidade, cada subnet privada usa
o NAT da própria AZ).

## DNS e certificados

- **`modules/route53-zone`**: uma hosted zone por domínio. `prod/dns` cria a zone apex
  `4o4.com.br` — a raiz do domínio, os nameservers dela precisam estar configurados no
  registrador. `dev/dns` cria `dev.4o4.com.br` como subdomínio **delegado** da apex (registro
  NS dentro da zone de prod apontando pros nameservers da zone de dev) — não uma zone
  independente tentando o mesmo nome.
- **`modules/acm`**: certificado wildcard `*.<domínio>` + o domínio raiz, validado via DNS
  (registros CNAME de validação criados automaticamente na hosted zone).
- Amplify **gerencia sozinho** os registros DNS de validação/subdomínio dele quando a hosted
  zone está na mesma conta — não são criados via Terraform (colisão "already exists" se forem).

## Camada de dados (`modules/rds`, `modules/elasticache`)

### RDS (Postgres)

| Configuração | Valor |
|---|---|
| Engine | PostgreSQL 17 (versão exata escolhida automaticamente dentro da major) |
| Instance class | `db.t4g.micro` |
| Storage | 20 GB, `gp3`, criptografado (KMS gerenciado pela AWS) |
| Multi-AZ | dev: não / prod: sim |
| Backup automático | 7 dias de retenção, mesma região |
| Backup cross-region (só prod) | Replicado pra `us-west-2` via `aws_db_instance_automated_backups_replication` — só armazenamento, nenhuma instância rodando lá |
| Senha | `manage_master_user_password = true` — nunca aparece no state do Terraform, fica no Secrets Manager |
| `auto_minor_version_upgrade` | `false` — upgrades de minor version são deliberados, não automáticos |
| Maintenance window | `sun:05:00-sun:06:00` UTC |
| Performance Insights | habilitado, retenção 7 dias (gratuita nesse nível) |
| Deletion protection | `false` nos dois ambientes **por enquanto** — a fase atual exige destroy completo; ligar em prod no go-live |
| Event Subscription (SNS) | eventos de failover, falha, pouco espaço, manutenção, recovery |

### ElastiCache (Valkey)

| Configuração | Valor |
|---|---|
| Engine | Valkey (não Redis OSS — recomendação atual da AWS pra clusters novos) |
| Node type | `cache.t4g.micro` (2 vCPUs) |
| Multi-AZ | dev: não (1 nó) / prod: sim (2 nós, failover automático) |
| Criptografia | at-rest e in-transit habilitadas |

Ambos vivem nas subnets isoladas, alcançáveis só pelas security groups do ECS e do bastion
(regras criadas a partir do lado do `ecs-service`/`bastion`, referenciando a SG do
RDS/ElastiCache — evita dependência circular entre módulos).

### Bastion (`modules/bastion`)

Uma EC2 `t4g.nano` (AL2023 ARM, resolvida via SSM public parameter) por ambiente, em subnet
privada, **sem IP público e sem nenhuma regra de ingress** — acesso exclusivamente via SSM
Session Manager. Serve só pra tunelar até RDS/Valkey a partir da máquina de um dev:

```bash
aws ssm start-session \
  --target $(cd stacks/dev/data && terraform output -raw bastion_instance_id) \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host=<rds-endpoint>,portNumber=5432,localPortNumber=5432
```

Requer o [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
do AWS CLI instalado localmente. IMDSv2 obrigatório, root volume criptografado, egress restrito
a 443 (endpoints do SSM, via NAT) + portas dos bancos. `ignore_changes = [ami]` pra AMI nova
não forçar recriação a cada plan.

## Camada de compute (`modules/ecs-service`, `modules/alb`, `modules/codedeploy-ecs`)

### ECS Fargate

| Configuração | dev | prod |
|---|---|---|
| CPU / Memória | 512 / 1024 | 512 / 1024 |
| `desired_count` inicial | 1 | 2 |
| Autoscaling | habilitado | habilitado |
| `min_capacity` / `max_capacity` | 1 / 4 | 2 / 8 |
| `cpu_target_value` (target tracking) | 70% | 60% |
| Container Insights | habilitado (os dois) | habilitado (os dois) |

Container escuta em `:8080`. Health check do ALB em `GET /health`. Log group
`/ecs/hackathon-{env}-api`, retenção 30 dias.

**IAM da task**: a execution role só tem a managed policy padrão da AWS
(`AmazonECSTaskExecutionRolePolicy`) + acesso ao secret específico da senha do RDS. A task role
(o que o *código* da aplicação pode fazer) começa vazia — hoje só tem
`ses:SendEmail`/`ses:SendRawEmail`, escopado à identidade SES do domínio do ambiente.

### ALB

Dois target groups (`blue`/`green` — ver [`deploy-e-cicd.md`](./deploy-e-cicd.md) pro porquê),
listener HTTPS 443 (TLS 1.3, `ELBSecurityPolicy-TLS13-1-2-2021-06`) e listener HTTP 80 que só
redireciona pro 443. `enable_deletion_protection`: `false` nos dois ambientes **por enquanto**
(fase de sobe-e-derruba) — ligar em prod no go-live.

### CodeDeploy (só prod usa canário; dev usa all-at-once)

Ver [`deploy-e-cicd.md`](./deploy-e-cicd.md) para o fluxo completo de deploy.

## Camada de frontend

- **`modules/static-site`** (landing): S3 privado + CloudFront (OAC, sem acesso público direto
  ao bucket) + WAF em prod. Versionamento habilitado, versões antigas expiram em 30 dias.
- **`modules/amplify-app`** (app principal): AWS Amplify Hosting, branch `main`/`develop`
  conectada ao repo `hackathon-web` via PAT clássico do GitHub (limitação do provider — não
  aceita GitHub App token ainda). WAF em prod, associado direto ao app.

## Email (`modules/ses`)

Identidade de domínio por ambiente, DKIM (Easy DKIM, sempre 3 tokens — `count = 3`, nunca
`for_each` porque os tokens não são conhecidos em plan time), SPF via TXT record, e uma policy
de DMARC (`v=DMARC1; p=quarantine` por padrão — ver
[`seguranca.md`](./seguranca.md) pro racional completo).

## Container registry (`modules/ecr`)

Um repositório (`hackathon-api`), **compartilhado entre dev e prod** (`shared/ecr`, não
duplicado por ambiente) — a mesma imagem buildada é promovida entre ambientes por tag
(`github.sha`). `IMMUTABLE` — a mesma tag nunca é reescrita, cada push do pipeline usa uma tag
nova.

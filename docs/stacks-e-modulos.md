# Stacks e módulos

## Módulos (`modules/`) — 15 reutilizáveis, sem estado próprio

| Módulo | Cria | Usado por |
|---|---|---|
| `vpc` | VPC, subnets (público/privado/isolado), IGW, NAT Gateway(s), route tables | `{env}/networking` |
| `route53-zone` | Hosted zone | `{env}/dns` |
| `acm` | Certificado wildcard + validação DNS | `{env}/dns` |
| `ses` | Identidade de domínio, DKIM, SPF, DMARC | `{env}/dns` |
| `rds` | Instância Postgres, security group, alarmes, backup cross-region (opcional) | `{env}/data` |
| `elasticache` | Replication group Valkey, security group, alarmes | `{env}/data` |
| `bastion` | EC2 `t4g.nano` privada (sem IP público) pra tunelar até RDS/Valkey via SSM Session Manager | `{env}/data` |
| `alb` | Load balancer, 2 target groups (blue/green), listeners, alarmes | `{env}/compute` |
| `ecs-service` | Cluster, task definition, service, IAM roles, autoscaling, alarmes | `{env}/compute` |
| `codedeploy-ecs` | App + deployment group do CodeDeploy, IAM role de serviço | `{env}/compute` |
| `waf` | Web ACL (REGIONAL ou CLOUDFRONT) com managed rule groups + rate limit | `{env}/compute` (ALB), `{env}/frontend` (CloudFront/Amplify) |
| `static-site` | Bucket S3 + CloudFront (landing) | `{env}/frontend` |
| `amplify-app` | App do Amplify Hosting | `{env}/frontend` |
| `ecr` | Repositório de imagens Docker | `shared/ecr` |
| `github-oidc-role` | Role IAM assumível via OIDC do GitHub Actions, com permission boundary opcional | `{env}/cicd` |

Cada módulo é independente e reusável — não conhece detalhes internos de outro módulo. Onde um
recurso precisa referenciar outro (ex.: alarme do ALB citando o cluster do ECS), a composição
acontece no **stack**, não dentro do módulo.

## Stacks (`stacks/`) — 16 root modules, cada um com seu próprio state em S3

```
stacks/
  shared/ecr        Compartilhado entre dev e prod — 1x por conta
  shared/oidc        OIDC provider do GitHub Actions — 1x por conta
  dev/networking      prod/networking
  dev/dns              prod/dns
  dev/alerting        prod/alerting
  dev/data              prod/data
  dev/compute          prod/compute
  dev/frontend        prod/frontend
  dev/cicd              prod/cicd
```

`shared/*` existe separado de `dev`/`prod` de propósito — no início viviam dentro de
`dev/compute`/`dev/cicd`, e isso acoplava dev e prod (destruir dev destruiria recursos que prod
também usa). Migrado via `terraform state rm` + `import`, sem recriar nada.

### Grafo de dependências (via `terraform_remote_state`)

```
shared/oidc ──────────────────┐
shared/ecr ────────────┐      │
                        │      │
{env}/networking        │      │
      │                 │      │
      ├──────► {env}/data ◄─── {env}/alerting
      │              │
{env}/dns              │
  (dev/dns também      │
   lê prod/dns, pra    │
   delegação NS)       │
      │                │
      └──► {env}/compute ◄─────┘
              │  (lê networking, dns, data,
              │   alerting, shared/ecr)
              │
              └──► {env}/cicd
                     (lê shared/oidc, compute —
                      pra escopar IAM do CodeDeploy)

{env}/frontend (lê dns)
```

### Ordem de apply recomendada

1. `shared/oidc`, `shared/ecr` (sem dependências, em qualquer ordem)
2. `prod/dns` **antes** de `dev/dns` (dev delega da apex de prod via NS)
3. `{env}/networking`
4. `{env}/alerting` (sem dependências, mas precisa existir antes de `data`/`compute` — eles leem
   o ARN do tópico SNS de lá)
5. `{env}/data`
6. `{env}/compute`
7. `{env}/frontend`
8. `{env}/cicd`

Essa ordem mudou depois do Sprint 1 (monitoramento) — antes, `alerting` não existia e `data`/
`compute` não tinham essa dependência nova.

### O que cada stack contém, em uma frase

| Stack | Conteúdo |
|---|---|
| `networking` | VPC completa |
| `dns` | Hosted zone, certificado ACM, identidade SES |
| `alerting` | Tópico SNS + assinatura de email (independente, sem ler nada de outro stack) |
| `data` | RDS + ElastiCache + bastion EC2 (túnel SSM até os bancos) |
| `compute` | ALB, ECS, CodeDeploy, WAF regional, dashboard CloudWatch, registro DNS `api.<domínio>` |
| `frontend` | Landing (S3+CloudFront) + Amplify app, WAF CloudFront |
| `cicd` | As 3 roles OIDC do GitHub Actions (`iac`, `api`, `landing`) + permission boundary da `iac` |

# Documentação — hackathon-iac

Índice central da documentação técnica desta infraestrutura. Cada doc abaixo cobre uma camada
específica, com profundidade suficiente pra servir de base pra diagramas de arquitetura, deploy
e observabilidade.

## O ecossistema

Quatro repositórios compõem o produto "4o4/hackathon":

| Repo | O que é | Onde roda |
|---|---|---|
| `hackathon-iac` (este) | Toda a infraestrutura AWS via Terraform | — |
| `hackathon-api` | Backend Rust (Axum + SeaORM) | ECS Fargate |
| `hackathon-web` | Frontend Next.js do app principal | AWS Amplify Hosting |
| `hackathon-landing` | Landing page estática (Next.js export) | S3 + CloudFront |

Domínio: `4o4.com.br` (prod) / `dev.4o4.com.br` (dev, subdomínio delegado via NS). Conta AWS
`546727414133`, região primária `us-east-1`. Branch `develop` = ambiente `dev`, branch `main` =
ambiente `prod`, consistente nos 4 repositórios.

## Índice

| Doc | Cobre |
|---|---|
| [`infraestrutura.md`](./infraestrutura.md) | Topologia completa de rede, dados e compute — o que existe na AWS, recurso por recurso |
| [`stacks-e-modulos.md`](./stacks-e-modulos.md) | Os 16 stacks Terraform, os 15 módulos reutilizáveis, grafo de dependências entre stacks e ordem de apply |
| [`deploy-e-cicd.md`](./deploy-e-cicd.md) | Do `git push` ao container rodando — OIDC, ECR, CodeDeploy Blue/Green, o que cada pipeline faz |
| [`observabilidade.md`](./observabilidade.md) | Todo alarme CloudWatch, thresholds, dashboard, canal de notificação |
| [`seguranca.md`](./seguranca.md) | IAM (todas as roles), WAF, permission boundary, criptografia, autenticação de email (SPF/DKIM/DMARC) |
| [`ambientes-dev-prod.md`](./ambientes-dev-prod.md) | Toda diferença de configuração entre dev e prod, lado a lado, com o porquê |
| [`decisoes-e-gotchas.md`](./decisoes-e-gotchas.md) | Por que as coisas são como são — decisões de arquitetura e armadilhas já resolvidas |
| [`integracao-backend.md`](./integracao-backend.md) | Guia de integração pro `hackathon-api` — env vars, portas, secrets, migrations |
| [`github-environments.md`](./github-environments.md) | Toda variável de GitHub Actions necessária, por repositório — o que é estável e o que precisa ser resincronizado depois de recriar a infra |
| [`melhorias-futuras.md`](./melhorias-futuras.md) | Checklist de go-live e melhorias deliberadamente adiadas — o que revisitar quando prod virar longa-duração, e por quê |

## Arquitetura em uma imagem (em palavras)

```
Internet
  │
  ├── Route53 (4o4.com.br / dev.4o4.com.br)
  │     ├── api.<domínio>      → ALB (HTTPS 443, WAF na frente em prod)
  │     ├── app.<domínio>      → Amplify Hosting (WAF na frente em prod)
  │     └── <domínio> (apex)   → CloudFront → S3 (landing, WAF na frente em prod)
  │
  ├── ALB (2 target groups: blue/green, CodeDeploy troca qual está ativo)
  │     └── ECS Fargate (cluster hackathon-{env}-api, Container Insights ligado)
  │           ├── conecta em → RDS Postgres (subnet isolada, sem rota de internet)
  │           ├── conecta em → ElastiCache Valkey (subnet isolada)
  │           └── manda email via → SES (identidade do domínio do ambiente)
  │
  └── VPC (dev: 10.0.0.0/16, prod: 10.1.0.0/16)
        ├── subnets públicas (ALB, NAT Gateway)
        ├── subnets privadas (ECS tasks)
        └── subnets isoladas (RDS, ElastiCache — sem rota de saída pra internet)
```

Todo alarme relevante (ALB, ECS, RDS, ElastiCache) publica num tópico SNS único por ambiente,
que manda email. CodeDeploy escuta esses mesmos alarmes durante um deploy pra decidir se
reverte sozinho. Ver [`observabilidade.md`](./observabilidade.md) e
[`deploy-e-cicd.md`](./deploy-e-cicd.md) pra fluxo completo.

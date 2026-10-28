# CLAUDE.md — hackathon-iac

Contexto e decisões deste projeto que não são óbvias só de ler o código. Escrito pra uma
sessão futura (inclusive depois de `/clear`) não perder o raciocínio por trás do que já foi
construído. Leia isso antes de mexer em qualquer coisa.

## O que é este projeto

Infraestrutura AWS via Terraform pro ecossistema "4o4/hackathon": uma API em Rust (Axum +
SeaORM) rodando em ECS Fargate, um frontend Next.js no Amplify, uma landing page estática em
S3+CloudFront, banco RDS Postgres + cache ElastiCache Valkey, tudo atrás de Route53/ACM/SES,
com deploy via GitHub Actions usando OIDC (sem chaves de acesso fixas).

Domínio: `4o4.com.br` (prod) / `dev.4o4.com.br` (dev, subdomínio delegado). Conta AWS:
`546727414133`, região `us-east-1`.

Repos irmãos (fora deste): `hackathon-api` (backend Rust), `hackathon-web` (frontend Next.js,
Amplify), `hackathon-landing` (landing estática, Next.js export). Branch `develop` = ambiente
`dev`, branch `main` = ambiente `prod`, em todos os 4 repos.

Documentação técnica completa (arquitetura, stacks, deploy/CI-CD, observabilidade, segurança,
comparativo dev/prod, decisões e gotchas, guia de integração do backend) está em
[`docs/README.md`](docs/README.md) — leia lá antes de qualquer mudança maior.

## ⚠️ Estado atual (verificar antes de assumir que algo está no ar)

**Infra derrubada de novo** (2026-08-05) — depois da subida de teste completa de 2026-08-04
(todos os 16 stacks aplicados nos dois ambientes, validada de ponta a ponta: `api.4o4.com.br` e
`api.dev.4o4.com.br` respondendo `200` via DNS → ALB → CodeDeploy Blue/Green → container real),
tudo foi destruído de novo, dev e prod, incluindo `shared/ecr` e `shared/oidc`. Verificado
recurso por recurso direto na AWS (ECS, RDS, VPC, Route53, Amplify): zero restante. Bootstrap
(bucket S3 do state) nunca foi tocado, continua no ar (`prevent_destroy` nele de propósito).
Nada commitado ainda neste repo — `hackathon-api` já tem o `deploy.yml` do CodeDeploy commitado
e testado.

Vários bugs reais só apareceram rodando de verdade contra a AWS durante a subida de teste —
lista completa em [`docs/decisoes-e-gotchas.md`](docs/decisoes-e-gotchas.md) (itens 12-18,
inclui o catálogo de variáveis do GitHub em
[`docs/github-environments.md`](docs/github-environments.md)).

Da próxima vez que subir: `prod/dns` é a zone apex `4o4.com.br` — recriá-la gera nameservers
novos na AWS, precisa atualizar os NS records no registrador do domínio antes da propagação
completar (chegou a levar ~8min na última vez), ou o domínio não resolve. Depois de qualquer
apply de `{env}/frontend`, conferir `docs/github-environments.md` — `DISTRIBUTION_ID` do
CloudFront muda a cada recriação e precisa ser resincronizado manualmente no GitHub.

## Como o repo está organizado

```
bootstrap/          Backend do Terraform (bucket S3), state local, 1x por conta
modules/             14 módulos reutilizáveis (vpc, rds, elasticache, ecs-service, alb,
                     codedeploy-ecs, waf, acm, route53-zone, ses, ecr, static-site,
                     amplify-app, github-oidc-role) — detalhe completo em
                     docs/stacks-e-modulos.md
stacks/
  shared/ecr         ECR (hackathon-api) — compartilhado entre dev/prod, não duplicar
  {dev,prod}/alerting Tópico SNS + assinatura de email, independente (sem dependências)
  shared/oidc        OIDC provider do GitHub Actions — só 1 por conta AWS, não duplicar
  prod/dns           Zone apex 4o4.com.br (dev delega dela via registro NS)
  dev/*, prod/*       networking, dns, data, compute, frontend, cicd
```

`shared/ecr` e `shared/oidc` existem separados de propósito — no início eles viviam dentro de
`dev/compute` e `dev/cicd`, e descobrimos que isso acoplava dev e prod (destruir dev
destruiria o ECR/OIDC que prod também usa). Migrado via `terraform state rm` + `import`, sem
recriar nada.

## Decisões importantes e por quê

- **Sem DynamoDB pro lock do state.** Terraform 1.10+ suporta locking nativo no backend S3
  (`use_lockfile = true`). O rascunho original pedia DynamoDB — pesquisei e confirmei que é
  caminho legado, não precisa mais.
- **Zone `dev.4o4.com.br` é delegada da apex `4o4.com.br`** (registro NS), não uma zone
  separada tentando o mesmo domínio. Duas zones pro mesmo nome não funcionam.
- **ElastiCache usa Valkey, não Redis OSS** — recomendação atual da AWS pra clusters novos
  (mais barato, mesma API).
- **RDS usa `manage_master_user_password = true`** — a senha nunca aparece no Terraform state.
  Isso significa que montar uma `DATABASE_URL` completa no Terraform não é possível (o
  Terraform nunca vê a senha) — resolvido no lado do app (ver `hackathon-api` abaixo).
- **ECR é `IMMUTABLE`** — nunca reusar a tag `latest` num push; o pipeline tagueia por
  `github.sha`. Reexecutar o mesmo commit duas vezes falha a não ser que a imagem antiga seja
  apagada ou o workflow cheque existência antes (`ecr:DescribeImages`).
- **Security groups usam `aws_vpc_security_group_ingress_rule`/`egress_rule`**, nunca blocos
  inline `ingress`/`egress` no `aws_security_group` — padrão atual recomendado.
- **OIDC do GitHub: formato de `sub` claim imutável (`org@id/repo@id`), não por nome.**
  Repos criados a partir de 15/07/2026 (como `hackathon-landing`) são forçados nesse formato
  novo; os mais antigos (`hackathon-iac`, `hackathon-api`) foram migrados manualmente via API
  (`PUT /repos/{owner}/{repo}/actions/oidc/customization/sub`) pra ficar tudo consistente.
- **A trust policy das roles usa `environment:<nome>` no `sub`, não `ref:refs/heads/<branch>`**
  — porque os workflows declaram `environment: dev`/`environment: prod` no job (necessário
  pras GitHub Environment Variables funcionarem). Isso muda o formato do claim OIDC. Se
  algum workflow novo não declarar `environment:`, a autenticação falha.
- **Task role do ECS começa vazia** — só tem `ses:SendEmail`/`ses:SendRawEmail` hoje (escopada
  à identidade SES do ambiente). Qualquer permissão AWS nova que o app precisar em runtime
  (S3, outro secret, etc.) precisa ser adicionada explicitamente.

## Gotchas descobertos rodando de verdade (não só na teoria)

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
   `ecr:DescribeImages` (pra workflows idempotentes que checam se a tag já existe).
7. `jq @uri` no Alpine funciona bem pra fazer percent-encoding de senha numa URL de conexão
   (testado com senha real cheia de símbolo especial) — mais simples que implementar em shell
   puro.

## `hackathon-api` (Rust/Axum/SeaORM) — pontos de integração

- Container escuta em `:8080` (não a porta local de dev, `3000`). `GET /health` precisa
  responder 200 em até 5s (health check do ALB).
- SeaORM exige uma `DATABASE_URL` completa — não aceita host/porta/user/senha separados sem
  perder funcionalidade. Como a senha do RDS nunca passa pelo Terraform, a URL é montada
  **dentro do container**, no `ENTRYPOINT` do Dockerfile (shell + `jq @uri` pro
  percent-encoding), a partir de `DB_USER`/`DB_PASSWORD`/`DB_HOST`/`DB_PORT`/`DB_NAME` que o
  ECS já injeta. Testado localmente com sucesso (senha com `#`, `@`, `!` incluída).
- Lista completa de env vars que a infra injeta: ver [`docs/integracao-backend.md`](docs/integracao-backend.md).
- **Migrations**: implementado (2026-08-05). Rodam como task avulsa do ECS (`ecs:run-task` com o comando sobrescrito pra `migration up`) como step do pipeline, antes de atualizar o service — não automático no boot do app, não embutido como container dependency (por causa de prod rodar 2 tasks simultâneas). `migration/` é membro do Cargo workspace raiz, o binário vai na mesma imagem Docker que o app. A configuração de rede pro `run-task` vem de `aws ecs describe-services` em tempo de execução, não de variável fixa no GitHub. Detalhe completo em [`docs/deploy-e-cicd.md`](docs/deploy-e-cicd.md).

## Como trabalhar neste projeto (regras já validadas com o usuário)

- **Nunca escrever/afirmar como algo funciona sem pesquisar a documentação oficial primeiro.**
  Prática mudou pelo menos duas vezes durante o projeto (DynamoDB → locking nativo; formato do
  OIDC sub claim) — não confiar em memória de treinamento pra decisões técnicas.
- **Nunca mergear Pull Request sozinho**, mesmo quando o destino é só `dev`. Abrir PR é ok
  quando pedido; merge é sempre decisão do usuário.
- **Nunca fazer `git push` sem deixar claro antes o que vai subir** — usuário já pediu pra
  confirmar antes, não depois.
- **Só commitar quando pedido explicitamente** — no momento em que este arquivo foi escrito,
  `hackathon-iac` tinha ~29 arquivos não commitados (todo o trabalho de infra), aguardando ok
  do usuário pra commitar.
- Ao mexer em qualquer coisa aplicada de verdade na AWS: mostrar o `plan` antes do `apply`,
  mesmo pra mudanças pequenas.

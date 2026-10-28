# Integração com `hackathon-api` (Rust/Axum/SeaORM)

Escrito a partir da leitura direta do código do `hackathon-api` (`Dockerfile`,
`src/configs/`), não de suposição.

## Porta e health check

O container escuta em **`:8080`** (não a porta de dev local, `3000`) — vem de `APP_PORT`,
injetada pelo ECS. `GET /health` (`src/routes/mod.rs`) responde `200` sem corpo, imediatamente
— é o que o health check do ALB usa (`healthy_threshold = 3`, `interval = 30s`).

## `DATABASE_URL` é montada dentro do container, não pelo Terraform

O RDS usa `manage_master_user_password = true` — a senha nunca aparece no state do Terraform,
só no Secrets Manager. Por isso a `DATABASE_URL` completa (que o SeaORM exige) é montada no
`ENTRYPOINT` do `Dockerfile`:

```sh
export DATABASE_URL="postgres://${DB_USER}:$(printf '%s' "$DB_PASSWORD" | jq -sRr @uri)@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSL_MODE:+?sslmode=${DB_SSL_MODE}}"
```

- `jq -sRr @uri` faz o percent-encoding da senha — necessário porque a senha gerada pelo RDS
  pode ter caracteres especiais (`#`, `@`, `!`, etc.).
- `?sslmode=${DB_SSL_MODE}` só entra na URL **se `DB_SSL_MODE` estiver definida**. Se a env var
  não for injetada pelo ECS, a URL sobe **sem parâmetro de SSL nenhum** — o driver Postgres cai
  no comportamento default (geralmente não força TLS). Já foi um bug real: prod ficou sem essa
  env var por um tempo enquanto dev tinha — corrigido, mas vale checar de novo se a conexão
  parecer não estar forçando TLS.

## Variáveis de ambiente injetadas pelo ECS

Todas definidas em `stacks/{env}/compute/main.tf`, no bloco `environment` do módulo `ecs`.

| Variável | Origem | Consumida pelo código hoje? |
|---|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` | outputs do RDS | sim — via `DATABASE_URL` |
| `DB_SSL_MODE` | fixo `"require"` | sim — via `DATABASE_URL` |
| `DATABASE_SCHEMA` | `var.database_schema` (`"public"`) | sim — `src/configs/database.rs` |
| `DATABASE_MIN_CONNECTIONS` / `DATABASE_MAX_CONNECTIONS` | variáveis do stack | sim — pool do SeaORM |
| `CORS_ORIGIN` | `https://app.<domain>` | sim — `src/configs/cors.rs` |
| `APP_PORT` | `var.container_port` (`8080`) | sim — `src/configs/app.rs` |
| `APP_PAYLOAD_MAX_SIZE_IN_MB` | `var.app_payload_max_size_mb` | sim — `src/configs/app.rs` |
| `REDIS_HOST`, `REDIS_PORT` | outputs do ElastiCache | não encontrado uso no código ainda — infra já injeta, pronto pra quando o app implementar cache |
| `AWS_REGION` | `var.aws_region` | não lido explicitamente — o AWS SDK for Rust lê essa env var sozinho quando o app chamar algum serviço AWS (ex. SES) |
| `SES_FROM_DOMAIN` | domínio da zone Route53 do ambiente | não encontrado uso no código ainda — infra pronta, sem integração SES implementada no app |

## Secret: `DB_PASSWORD`

Não é uma env var comum — vem via `secrets` do ECS, resolvida pelo Secrets Manager em runtime.
A execution role do ECS tem `secretsmanager:GetSecretValue` escopado só a esse secret
específico.

## Permissões que o container já tem, mesmo sem usar ainda

A task role (`hackathon-{env}-api`) hoje só tem `ses:SendEmail`/`ses:SendRawEmail`, escopada à
identidade SES do domínio do ambiente. Qualquer permissão AWS nova que o app precisar em
runtime (S3, outro secret, etc.) precisa ser adicionada explicitamente na IaC.

## Deploy

Ver [`deploy-e-cicd.md`](./deploy-e-cicd.md) pro fluxo completo (CodeDeploy Blue/Green, canário
em prod, appspec.yaml).

## Migrations — implementado

`migration/` é membro do Cargo workspace, o binário `migration` vai na mesma imagem Docker que
o `hackathon_backend`. Rodam via `ecs run-task` como step do pipeline, antes do deploy — ver
[`deploy-e-cicd.md`](./deploy-e-cicd.md), seção "Migrations", pro fluxo completo.

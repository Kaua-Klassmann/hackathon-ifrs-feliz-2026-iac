# Melhorias futuras e checklist de go-live

Itens identificados na revisão completa da IaC (2026-08-14) que foram **deliberadamente não
implementados** — por custo, por mudarem contrato com outro repo, ou por serem decisão de
processo. Nada aqui é bloqueante nem vulnerabilidade ativa: a fase atual do projeto
(sobe-e-derruba completo dos dois ambientes) foi priorizada de propósito. Este doc é a
lista do que revisitar quando prod virar longa-duração.

## Checklist de go-live (fazer ANTES de prod ficar no ar por semanas)

| # | Item | Onde | Esforço |
|---|---|---|---|
| 1 | Ligar deletion protection: RDS (`deletion_protection = true`) e ALB (`enable_deletion_protection = true`) em prod | `stacks/prod/data`, `stacks/prod/compute` | 2 linhas |
| 2 | `prevent_destroy` em `shared/ecr` e `shared/oidc` (e reavaliar o `force_delete = true` do ECR) | `stacks/shared/*` | ~10 linhas |
| 3 | Subir a regra "keep last 20" do lifecycle do ECR pra 50 — com tags por `github.sha` num repo compartilhado dev+prod, 20 deploys de dev podem expirar a imagem que prod está **rodando** (o pull falha no próximo restart/scale-out da task) | `modules/ecr` | 1 linha |
| 4 | Auth token/RBAC no Valkey — hoje a única peça de dados sem credencial própria (mitigado por SG + subnet isolada). **Muda o contrato com o `hackathon-api`**: exige injetar `REDIS_PASSWORD` e o app usar na conexão. Melhor nascer com token do que migrar depois (`auth_token_update_strategy`) | `modules/elasticache` + `hackathon-api` | coordenado, 2 repos |
| 5 | VPC Flow Logs em prod (destino S3, retenção 30d) — sem eles não há trilha de rede pra investigar incidente nem debugar SG/NACL | `modules/vpc` | ~30 linhas, ~US$ 5–20/mês |
| 6 | Access logs do ALB em prod (bucket S3 com a policy de log delivery, lifecycle 30–90d) — reconstruir tráfego num incidente e correlacionar com os bloqueios do WAF | `modules/alb` | ~40 linhas, centavos/mês |
| 7 | Custom MAIL FROM no SES (`mail.<domínio>`) — hoje o DMARC passa só via DKIM (envelope-from é `amazonses.com`, SPF nunca alinha); com MAIL FROM próprio, SPF e DKIM alinham e a entregabilidade deixa de depender de um mecanismo só | `modules/ses` | +2 registros DNS |
| 8 | Evoluir DMARC de `p=quarantine` pra `p=reject` depois de volume real confirmar SPF/DKIM 100% alinhados | `modules/ses` | 1 linha, depois do item 7 |

## Processo e GitHub (fora do Terraform)

- **Branch protection na `main` do `hackathon-web`** — o Amplify de prod tem
  `enable_auto_build = true`: push na `main` vai pro ar direto, sem o gate de GitHub
  Environment que API e landing têm. Se a branch exigir PR + aprovação, o gate passa a existir
  *antes* do push e o auto-build fica aceitável. Alternativa (mais cara): desligar auto-build e
  criar workflow com `amplify start-job` + role OIDC nova.
- **Required reviewers nos environments `dev`/`prod` do `hackathon-iac`** — o job `plan` roda
  em qualquer PR com a role `iac` real; um PR malicioso pode executar código Terraform
  (data source `external`, provider arbitrário) durante o plan. Required reviewers no
  environment seguram o job até aprovação humana.
- **PAT do Amplify com escopo mínimo + rotação** — o token vai em claro pro state no S3
  (limitação dupla: provider não aceita GitHub App token, `aws_amplify_app` não suporta
  write-only arguments). Não tem correção técnica disponível; mitigar com token de
  conta-máquina restrito ao `hackathon-web` e expiração de 90 dias. Bucket de state já é
  privado, criptografado e TLS-only.
- **Triar os achados do checkov e remover o `soft_fail: true`** do workflow de checks.

## Menores / oportunísticos

- `terraform_version` fixado no `setup-terraform` do CI (hoje pega a última; pode divergir da
  local — o backend exige ≥ 1.10 pelo `use_lockfile`).
- IPv6 no CloudFront da landing (`is_ipv6_enabled` + registro AAAA) — grátis, só lembrar dos
  dois juntos.
- Restringir o egress `-1 0.0.0.0/0` do SG do ECS a 443 + VPC CIDR (hoje aberto; funciona, mas
  o bastion já mostra o padrão mais estrito).
- Alarme de billing/budget na conta (nenhum existe hoje).

## Por que não agora

A regra da fase atual (2026-08): **tudo destruível, dos dois ambientes**, inclusive prod — os
docs refletem isso (`ambientes-dev-prod.md`, `infraestrutura.md`). Cada item acima ou adiciona
custo recorrente observando ambientes que vivem dias, ou trava o ciclo de destroy, ou muda
contrato com outro repositório. O que era bug real (associação WAF↔CloudFront, `pipefail`/
`tflint` do CI, policy incompleta da role `iac`, `:latest` em ECR imutável, snapshot final
estático) já foi corrigido na mesma revisão que gerou este doc.

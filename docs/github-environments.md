# Variáveis de ambiente do GitHub, por repositório

Catálogo de tudo que precisa estar configurado em **Settings → Environments** em cada repo,
fora do Terraform — nada disso é gerenciado por IaC, é 100% manual no GitHub. Existe porque um
`DISTRIBUTION_ID` desatualizado (2026-08-04) só foi descoberto quebrando um deploy de verdade —
sem esse catálogo, não tem como saber o que checar depois de recriar a infra.

## Por que isso desatualiza sozinho

Cada valor abaixo é **estável** (o Terraform sempre recria com o mesmo nome, nunca muda) ou
**volátil** (a AWS atribui um ID novo, aleatório, toda vez que o recurso é recriado do zero —
teardown + apply novo = valor novo). Só os voláteis precisam ser conferidos de novo depois de
qualquer teardown/recreate. Os estáveis, uma vez certos, ficam certos.

## `hackathon-api`

| Variável | Ambientes | Estável? | Origem |
|---|---|---|---|
| `ROLE_ARN` | dev, prod | Estável | `arn:aws:iam::<conta>:role/hackathon-{env}-api` — nome fixo |
| `ECS_CLUSTER` | dev, prod | Estável | `hackathon-{env}-api` — nome fixo |
| `ECS_SERVICE` | dev, prod | Estável | `hackathon-{env}-api` — nome fixo |

Nenhuma variável volátil aqui — por isso esse repo nunca deu esse tipo de erro.

## `hackathon-landing`

| Variável | Ambientes | Estável? | Origem |
|---|---|---|---|
| `ROLE_ARN` | dev, prod | Estável | `arn:aws:iam::<conta>:role/hackathon-{env}-landing` — nome fixo |
| `BUCKET_NAME` | dev, prod | Estável | `hackathon-{env}-landing` — nome fixo |
| `NEXT_PUBLIC_APP_ENV` | dev, prod | Estável | literal `"dev"`/`"prod"` |
| `DISTRIBUTION_ID` | dev, prod | **Volátil** | ID do CloudFront, atribuído pela AWS — **muda toda vez que a distribuição é recriada** |

**Depois de qualquer teardown/apply novo de `{env}/frontend`**: pegar o valor certo com
`cd stacks/{env}/frontend && terraform output landing_distribution_id` e atualizar a variável no
GitHub antes do próximo deploy da landing, ou o `cloudfront:CreateInvalidation` falha
silenciosamente contra um ID que não existe mais.

## `hackathon-web`

**Nenhuma variável de GitHub Actions** — não existe `.github/workflows/` nesse repo. O deploy é
100% via integração nativa do Amplify Hosting com o GitHub (webhook automático a cada push),
configurado uma vez no `github_access_token` do Terraform (`modules/amplify-app`). Nada pra
sincronizar manualmente aqui.

## `hackathon-iac`

| Variável | Ambientes | Estável? | Origem |
|---|---|---|---|
| `IAC_ROLE_ARN` | dev, prod | Estável | `arn:aws:iam::<conta>:role/hackathon-{env}-iac` — nome fixo |

Precisa dos **environments `dev` e `prod` criados neste repo** (Settings → Environments) —
nunca existiram aqui antes do job `plan` (`terraform-checks.yml`) ser adicionado, porque até
então o CI só rodava checagem estática, sem credenciais AWS. O trust OIDC da role `iac` já
confia no repo `hackathon-iac` (`var.iac_repo` no Terraform) — só falta o lado do GitHub.

**Sobre o job `plan` rodar contra infra derrubada**: `terraform plan` em `compute`/`data`/
`frontend`/`cicd` **vai falhar** se os stacks que eles dependem (`networking`, `dns`, `data`,
`alerting`, `shared/ecr`) não tiverem sido aplicados ainda — `terraform_remote_state` de um
state vazio não tem outputs pra ler. Esperado logo depois de um teardown completo, não é bug do
workflow — resolve sozinho assim que a infra voltar a existir de verdade.

## Checklist depois de recriar a infra do zero

1. `hackathon-api`: nada a fazer (tudo estável).
2. `hackathon-landing`: rodar `terraform output landing_distribution_id` em `dev/frontend` e
   `prod/frontend`, comparar com o que está no GitHub, atualizar se divergir.
3. `hackathon-web`: nada a fazer (Amplify se reconecta sozinho).
4. `hackathon-iac`: nada a fazer (tudo estável) — só precisa existir uma vez, não resincroniza
   depois de teardown/recreate.

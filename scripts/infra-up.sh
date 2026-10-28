#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="all"
AUTO_APPROVE=""

for arg in "$@"; do
  case "$arg" in
    dev|prod|all) TARGET="$arg" ;;
    -y|--auto-approve) AUTO_APPROVE="-auto-approve" ;;
    *) echo "uso: $0 [dev|prod|all] [-y]" >&2; exit 1 ;;
  esac
done

IMAGE_TAG="${IMAGE_TAG:-bootstrap}"
ECR_REPO="hackathon-api"
REGION="us-east-1"

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m⚠ %s\033[0m\n' "$*"; }

apply() {
  local stack="$1"; shift
  bold "apply: $stack"
  terraform -chdir="$stack" init -input=false >/dev/null
  terraform -chdir="$stack" apply -input=false $AUTO_APPROVE "$@"
}

check_frontend_tfvars() {
  local env="$1"
  if [[ ! -f "stacks/$env/frontend/terraform.tfvars" ]]; then
    warn "stacks/$env/frontend/terraform.tfvars não existe (precisa do github_access_token)."
    warn "Copie o terraform.tfvars.example, preencha, e rode o script de novo."
    exit 1
  fi
}

check_bootstrap_image() {
  if ! aws ecr describe-images --region "$REGION" --repository-name "$ECR_REPO" \
      --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1; then
    warn "Imagem '$ECR_REPO:$IMAGE_TAG' não existe no ECR — a task definition inicial do"
    warn "compute aponta pra ela (ECR é IMMUTABLE, 'latest' nunca existe)."
    warn "Procedimento completo em docs/deploy-e-cicd.md (seção 'Publicando a imagem de"
    warn "bootstrap'); resumo, a partir do repo hackathon-api:"
    echo "  aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin 546727414133.dkr.ecr.$REGION.amazonaws.com"
    echo "  docker build --platform linux/amd64 -t 546727414133.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG ."
    echo "  docker push 546727414133.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG"
    warn "(Mac ARM: emulação precisa ser Rosetta, não QEMU — gotcha 19 em docs/decisoes-e-gotchas.md)"
    exit 1
  fi
}

apply_env() {
  local env="$1"
  check_frontend_tfvars "$env"

  apply "stacks/$env/networking"
  apply "stacks/$env/alerting"
  if [[ "$env" == "dev" ]]; then
    apply "stacks/dev/dns"
  fi
  apply "stacks/$env/data"

  check_bootstrap_image
  apply "stacks/$env/compute" -var "image_tag=$IMAGE_TAG"

  apply "stacks/$env/frontend"
  warn "frontend/$env aplicado: o DISTRIBUTION_ID do CloudFront mudou se a distribution foi"
  warn "recriada — sincronizar manualmente nas GitHub Environment Variables"
  warn "(ver docs/github-environments.md)."

  apply "stacks/$env/cicd"
}

apply stacks/shared/oidc
apply stacks/shared/ecr

apply stacks/prod/dns
bold "Nameservers da zone apex 4o4.com.br:"
terraform -chdir=stacks/prod/dns output -json name_servers 2>/dev/null \
  || terraform -chdir=stacks/prod/dns output
warn "Se a zone foi RECRIADA agora, os nameservers acima são NOVOS — atualize os registros"
warn "NS no registrador do domínio ANTES de seguir, ou o domínio não resolve"
warn "(propagação levou ~8min na última subida)."
if [[ -z "$AUTO_APPROVE" ]]; then
  read -rp "Nameservers conferidos no registrador? [enter pra continuar] "
fi

case "$TARGET" in
  dev)  apply_env dev ;;
  prod) apply_env prod ;;
  all)  apply_env dev; apply_env prod ;;
esac

bold "Infra no ar. Smoke test:"
if [[ "$TARGET" != "prod" ]]; then
  echo "  curl -s -o /dev/null -w '%{http_code}\n' https://api.dev.4o4.com.br/health"
fi
if [[ "$TARGET" != "dev" ]]; then
  echo "  curl -s -o /dev/null -w '%{http_code}\n' https://api.4o4.com.br/health"
fi

#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="all"
INCLUDE_SHARED=0
AUTO_APPROVE=""

for arg in "$@"; do
  case "$arg" in
    dev|prod|all) TARGET="$arg" ;;
    --shared) INCLUDE_SHARED=1 ;;
    -y|--auto-approve) AUTO_APPROVE="-auto-approve" ;;
    *) echo "uso: $0 [dev|prod|all] [--shared] [-y]" >&2; exit 1 ;;
  esac
done

if [[ $INCLUDE_SHARED -eq 1 && "$TARGET" != "all" ]]; then
  echo "--shared só faz sentido com 'all' (dev e prod usam o ECR/OIDC compartilhado)" >&2
  exit 1
fi

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m⚠ %s\033[0m\n' "$*"; }

echo
echo "Isto vai DESTRUIR a infra: target=$TARGET shared=$INCLUDE_SHARED"
echo "(RDS gera snapshot final automaticamente; o state em S3 é preservado)"
if [[ -z "$AUTO_APPROVE" ]]; then
  read -rp "Digite 'destruir' pra confirmar: " CONFIRM
  [[ "$CONFIRM" == "destruir" ]] || { echo "abortado"; exit 1; }
fi

destroy() {
  local stack="$1"; shift
  bold "destroy: $stack"
  terraform -chdir="$stack" init -input=false >/dev/null
  terraform -chdir="$stack" destroy -input=false $AUTO_APPROVE "$@"
}

destroy_env() {
  local env="$1"
  destroy "stacks/$env/cicd"
  destroy "stacks/$env/frontend"
  destroy "stacks/$env/compute"
  destroy "stacks/$env/data"
  if [[ "$env" == "dev" ]]; then
    destroy "stacks/dev/dns"
  fi
  destroy "stacks/$env/alerting"
  destroy "stacks/$env/networking"
}

case "$TARGET" in
  dev)
    destroy_env dev
    ;;
  prod)
    destroy_env prod
    warn "prod/dns NÃO foi destruído: dev delega da zone apex. Se dev também vai cair,"
    warn "use 'all'; pra destruir só a zone apex mesmo assim:"
    warn "  terraform -chdir=stacks/prod/dns destroy"
    ;;
  all)
    destroy_env dev
    destroy_env prod
    destroy stacks/prod/dns
    if [[ $INCLUDE_SHARED -eq 1 ]]; then
      destroy stacks/shared/ecr
      destroy stacks/shared/oidc
    fi
    ;;
esac

bold "Destruição concluída."
warn "Lembretes: o snapshot final do RDS fica cobrando storage até ser apagado à mão;"
warn "na próxima subida, os nameservers da zone apex serão NOVOS (atualizar registrador)."

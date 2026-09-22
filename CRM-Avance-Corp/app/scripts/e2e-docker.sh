#!/usr/bin/env bash
# E2E del CRM en Docker, en local. Sustituye al job que se retiró de GitHub
# Actions (PR #65, 21/09/2026): los e2e se corren AQUÍ, no en GitHub.
#
#   npm run test:e2e:docker                      # suite completa
#   npm run test:e2e:docker -- e2e/clientes.spec.ts --workers=2
#
# Por qué Docker y no `npm run test:e2e` a secas: la imagen oficial de
# Playwright fija Chromium y sus librerías de sistema a la versión exacta del
# lockfile, igual para Claude, Codex y cualquier Mac. El resultado no depende
# del navegador que haya quedado instalado en la máquina.
#
# Los node_modules del Mac NO sirven dentro del contenedor (esbuild, rollup y
# tailwind traen binarios por plataforma): viven en un volumen propio que se
# reinstala solo cuando cambia package-lock.json. El árbol se monta en vivo,
# así que se prueba exactamente lo que hay en disco.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PW_VERSION="$(node -p "require('$APP_DIR/node_modules/@playwright/test/package.json').version" 2>/dev/null \
  || node -p "require('$APP_DIR/package-lock.json').packages['node_modules/@playwright/test'].version")"
IMAGE="mcr.microsoft.com/playwright:v${PW_VERSION}-noble"
VOLUME="avancecorp-crm-e2e-node-modules"

if ! docker info >/dev/null 2>&1; then
  echo "Docker no responde. Abre Docker Desktop y vuelve a correr." >&2
  exit 2
fi

# 2 workers por defecto, como tenía el job de GitHub. Docker Desktop comparte
# su memoria con los bancos Supabase de otras sesiones: con un Chromium por
# núcleo (~7) la corrida del 22/09 se ahogó en timeouts y «Target crashed».
ARGS=("$@")
case " $* " in *" --workers"*|*" -j "*) ;; *) ARGS+=(--workers=2) ;; esac

LOCK_HASH="$(shasum -a 256 "$APP_DIR/package-lock.json" | cut -d' ' -f1)"

echo "E2E en Docker · imagen ${IMAGE}"
exec docker run --rm --init --ipc=host \
  -e CI=1 \
  -e LOCK_HASH="$LOCK_HASH" \
  -v "$APP_DIR":/app \
  -v "$VOLUME":/app/node_modules \
  -w /app \
  "$IMAGE" \
  bash -c '
    set -euo pipefail
    if [ "$(cat node_modules/.lock-hash 2>/dev/null)" != "$LOCK_HASH" ]; then
      echo "Instalando dependencias (package-lock.json cambió o volumen nuevo)…"
      npm ci --ignore-scripts --no-audit --no-fund
      echo "$LOCK_HASH" > node_modules/.lock-hash
    fi
    npx playwright test "$@"
  ' _ "${ARGS[@]}"

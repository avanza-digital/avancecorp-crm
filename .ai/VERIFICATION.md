# Verification Gate

> **A task must not be considered complete merely because the code was written.**

El `PRIMARY` debe ejecutar las verificaciones razonablemente relevantes para el cambio y reportar con honestidad `PASS`, `FAIL` o `NOT RUN`. Un review de IA no reemplaza un test, un typecheck ni un build.

## Flujo obligatorio

```text
CODE CHANGE
→ relevant static validation
→ relevant tests
→ build when applicable
→ secondary review when required
→ final verification
→ DONE
```

Si un check no puede ejecutarse por dependencias, credenciales, red, servicios o tiempo, se marca `NOT RUN` con la causa y el riesgo residual. Nunca se infiere que pasó.

## Selección por tipo de cambio

### Configuración de colaboración, hooks y scripts shell

Ejecutar:

```bash
jq empty .claude/settings.json .mcp.json
for script in scripts/claude-review scripts/codex-review-mcp .claude/hooks/*.sh; do
  bash -n "$script" || exit 1
done
scripts/claude-review --help
scripts/codex-review-mcp --help
node --test scripts/ai-collaboration.test.mjs
```

Si existe la configuración local ignorada de Codex, validar también su JSON sin asumir que estará presente en CI:

```bash
test ! -f .codex/hooks.json || jq empty .codex/hooks.json
```

Además, simular inputs permitidos y bloqueados de cada hook modificado. Si cambia la integración MCP, iniciar el servidor con su configuración exacta y comprobar `initialize` + `tools/list` sin invocar un review real.

`bash -n archivo1 archivo2` solo valida el primer archivo: por eso se usa un bucle. Comprobar también los permisos de ejecución de wrapper y hooks.

Los tests de los wrappers usan sustitutos locales para comprobar argumentos, stdin y errores sin consumir API. No prueban el servicio real. Tras modificar flags o actualizar la CLI, comprobar `claude --help` y ejecutar una revisión real con evidencia saneada, registrar su dictamen y evaluar sus hallazgos.

Con Codex instalado, ejecutar `scripts/codex-review-mcp --check`. El lanzador enumera y deshabilita los MCP efectivos y apaga plugins mediante feature flags; **`mcp_servers={}` y `plugins={}` no aíslan**, porque esas tablas se fusionan con la configuración heredada. La prueba MCP debe usar el comando exacto de `.mcp.json`, desde la raíz del repositorio. `Connected` solo comprueba el arranque, no la política efectiva. No imprimir inventarios MCP completos: pueden contener credenciales en los transportes.

Después de modificar MCP/plugins/settings, reconectar `codex` en Claude antes de
otro review para renovar el inventario de aislamiento. No modificar esas
configuraciones mientras un review esté en curso. `--check` valida tanto los MCP
efectivos como los flags de ejecución. Codex 0.153.4 rechaza `--strict-config` en
`mcp list`; ese flag se aplica al servidor y su handshake se verifica por separado.

### CRM frontend (`CRM-Avance-Corp/app`)

Para cambios TypeScript/React, ejecutar desde `CRM-Avance-Corp/app`:

```bash
npm run lint
npm run typecheck
npm run test:run
npm run build
```

El gate integral existente es:

```bash
npm run check
```

Incluye lint, typecheck, tests con cobertura, configuración de release, build, verificación del bundle y duplicación. Para flujos de usuario importantes o cambios de navegación/roles:

```bash
npm run check:all
```

`check:all` añade Playwright **en Docker** (`npm run test:e2e:docker`). Para una corrección puntual puede ejecutarse primero el test directamente relacionado, pero el cierre debe usar el gate proporcional al riesgo.

#### E2E: SIEMPRE en local con Docker, NUNCA en GitHub

Los E2E del CRM se ejecutan en la máquina local dentro del contenedor oficial de Playwright (versión fijada por el lockfile). GitHub Actions ya no los corre (PR #65) y **ningún agente debe volver a añadirlos a un workflow** ni esperar a GitHub para saber si pasan.

```bash
cd CRM-Avance-Corp/app
npm run test:e2e:docker                                  # suite completa
npm run test:e2e:docker -- e2e/clientes.spec.ts          # un spec
npm run test:e2e:docker -- --grep "Mi día" --workers=2   # filtrado
```

- Cuándo es obligatorio: cambios en pantallas, navegación, roles/permisos visibles, formularios o flujos de usuario del CRM, y antes de cualquier release del CRM.
- Corre con 2 workers por defecto (con más, Docker se queda sin memoria y aparecen timeouts falsos). Referencia 22/09: 232 passed · 26 skipped en 8,8 min.
- Requisito: Docker Desktop encendido. Si `docker info` falla, reportar E2E como `NOT RUN (Docker apagado)`; nunca como PASS.
- Reportar el resultado real del resumen de Playwright (`N passed / M failed`). Los artefactos quedan en `CRM-Avance-Corp/app/test-results/` y `playwright-report/`.
- `npm run test:e2e` (sin Docker) queda solo para depurar con navegador visible; no vale como gate de cierre.
- La integración de conversión (`playwright.conversion.config.ts`) sigue su propio banco Docker de Supabase y no forma parte de este gate.

### CRM backend, scripts, Edge Functions y RLS (`CRM-Avance-Corp`)

Los preflights offline existentes son:

```bash
npm run check:scripts
npm run seed:preflight
npm run test:rls:preflight
npm run test:edge-preflight
```

Para migraciones o seguridad de datos, además se aplican las reglas de `CRM-Avance-Corp/CLAUDE.md` y `CRM-Avance-Corp/supabase/migrations/LEEME.md`: no editar migraciones versionadas, actualizar `MIGRACIONES.md`, probar en una rama/instancia autorizada, ejecutar la matriz RLS pertinente y regenerar tipos cuando cambie el schema:

```bash
cd CRM-Avance-Corp/app
npm run gen:types
```

Los gates con base real, advisors, replay de migraciones o despliegue requieren el entorno autorizado correspondiente. No se sustituyen por un preflight offline.

### Portal estático (`public_html`)

El portal no tiene build. Para JavaScript modificado:

```bash
node --check public_html/ruta/al/archivo.js
```

Para los núcleos cubiertos por el banco versionado:

```bash
cd public_html
node --test tests/*.test.mjs
```

Los flujos Playwright viven en `_DEV_NO_SUBIR` y se ejecutan cuando el cambio toca navegación, PWA o experiencia end-to-end:

```bash
cd _DEV_NO_SUBIR
npm test
```

También se deben respetar los bumps `?v=N`, `CACHE_VERSION`, comprobaciones de caché y preflights de publicación descritos en `public_html/CLAUDE.md` y en el vault. No existe un build que pueda sustituir esas verificaciones.

### Documentación y configuración sin código de producto

Ejecutar validadores de sintaxis de los formatos tocados (`jq`, `bash -n`, parseo YAML/TOML cuando aplique), `git diff --check` y comprobar que todas las rutas y comandos documentados existen. No es necesario ejecutar el banco completo del producto si el cambio no puede afectar su runtime.

## Revisión según riesgo

- `LEVEL 1`: sin secondary review; checks locales específicos.
- `LEVEL 2`: normalmente un secondary review después de checks relevantes.
- `LEVEL 3`: un secondary review cuando sea razonablemente posible, correcciones del `PRIMARY` y repetición del gate final.

El reviewer no declara la tarea terminada. El `PRIMARY` evalúa los hallazgos y ejecuta la verificación final.

## CI existente

- `.github/workflows/crm-app-quality.yml`: lint, typecheck, cobertura, tests y build del CRM frontend. E2E NO se ejecuta en GitHub Actions: se corre en local con `npm run test:e2e:docker` (ver «E2E: SIEMPRE en local con Docker»).
- `.github/workflows/crm-rls-preflight.yml`: sintaxis de scripts, seed/RLS preflight offline y fronteras de Edge Functions.
- `.github/workflows/ai-collaboration-config.yml`: JSON, shell, contratos de hooks e integración documental de este sistema.
- `lefthook.yml`: lint/typecheck pre-commit y tests pre-push para el CRM.

La regla operativa es:

```text
AI opinion ≠ verification

AI review
+ automated checks
= stronger confidence
```

## Trabajo simultáneo y worktrees

No se crean worktrees automáticamente.

Si Codex y Claude trabajan como `PRIMARY` simultáneamente en tareas distintas, no deben compartir working tree. Cada uno usa un `git worktree` separado:

```text
main repository

worktrees/
├── feature-a   ← Codex PRIMARY
└── feature-b   ← Claude PRIMARY
```

Cuando uno es `SECONDARY_REVIEWER` del otro no necesita otro worktree, porque permanece estrictamente read-only.

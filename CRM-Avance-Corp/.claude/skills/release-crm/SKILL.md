---
name: release-crm
description: Construye el artefacto de release del CRM (ZIP + manifiesto SHA-256) y lo publica en crm.miavance.com vía MCP de Hostinger. Solo invocación humana.
disable-model-invocation: true
---

# Release del CRM a crm.miavance.com

Publica a **PRODUCCIÓN**. Por eso `disable-model-invocation: true`: solo Miguel lo invoca
con `/release-crm` en Claude. En Codex, la invocación humana equivalente es
`$release-crm`, implementada en `.agents/skills/release-crm/SKILL.md` de la raíz
del repositorio. No exigir ambas invocaciones. No saltarse pasos ni publicar
un ZIP que no haya pasado la verificación.

## Pasos

1. **Estado limpio y tronco al día**: `git status` sobre `CRM-Avance-Corp/`. Si hay cambios
   sin commitear que afectan a `app/`, avisar y pedir confirmación antes de seguir (el
   manifiesto ancla el commit actual). Haz `git fetch avancecorp`, integra sus cambios sin
   sobrescribirlos y comprueba que `main` local y `avancecorp/main` apuntan al mismo commit;
   si no, para y avisa.

2. **Gates rápidos** (en `CRM-Avance-Corp/app/`):
   ```bash
   npm run check
   ```
   Si falla, DETENERSE y reportar. No se publica con el check en rojo.

3. **Construir artefacto** (en `CRM-Avance-Corp/`):
   ```bash
   npm run release:crm
   ```
   Genera `releases/crm-<timestamp>-<hash>.zip` + `.manifest.json` (SHA-256 de cada archivo
   del dist, commit y destino `crm.miavance.com`).

4. **Verificar el manifiesto** del artefacto recién creado:
   ```bash
   npm run release:crm:verify -- releases/<el-nuevo>.manifest.json
   ```

5. **Preflight (obligatorio; el MCP no lo corre)**, desde la raíz del repositorio:
   ```bash
   node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com CRM-Avance-Corp/releases/<el-nuevo>.zip
   ```
   Compara el candidato con el commit VIVO (`version.json` → manifiesto en `releases/`) y se
   niega si el build no contiene lo publicado. Si rechaza, NO publiques: sigue «Si el
   preflight te rechaza» del `CLAUDE.md` raíz.

6. **Publicar** con el MCP de Hostinger (`hosting_deployStaticWebsite`) apuntando el ZIP
   recién verificado al sitio de `crm.miavance.com`. Mismo carril que el portal.

7. **Smoke post-deploy**:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" https://crm.miavance.com/
   ```
   y comprobar que el `index-<hash>.js` referenciado por
   `https://crm.miavance.com/` existe (HTTP 200) y coincide con el de `app/dist/index.html`.

8. **Reportar**: nombre del artefacto, commit, resultado del preflight y del smoke. Si algo
   falló después de publicar, el ZIP anterior en `releases/` es la vía de recuperación, pero el
   preflight lo rechazará (no contiene lo que acabas de publicar). No lo publiques saltándote
   el preflight por tu cuenta: reporta a Miguel la evidencia del smoke y él decide el rollback.

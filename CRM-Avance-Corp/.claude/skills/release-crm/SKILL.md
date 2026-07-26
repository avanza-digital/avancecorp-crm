---
name: release-crm
description: Construye el artefacto de release del CRM (ZIP + manifiesto SHA-256) y lo publica en crm.miavance.com vía MCP de Hostinger. Solo invocación humana.
disable-model-invocation: true
---

# Release del CRM a crm.miavance.com

Publica a **PRODUCCIÓN**. Por eso `disable-model-invocation: true`: solo Miguel lo invoca
con `/release-crm`. No saltarse pasos ni publicar un ZIP que no haya pasado la verificación.

## Pasos

1. **Estado limpio**: `git status` sobre `CRM-Avance-Corp/`. Si hay cambios sin commitear
   que afectan a `app/`, avisar y pedir confirmación antes de seguir (el manifiesto ancla
   el commit actual).

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

5. **Publicar** con el MCP de Hostinger (`hosting_deployStaticWebsite`) apuntando el ZIP
   recién verificado al sitio de `crm.miavance.com`. Mismo carril que el portal.

6. **Smoke post-deploy**:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" https://crm.miavance.com/
   ```
   y comprobar que el `index-<hash>.js` referenciado por
   `https://crm.miavance.com/` existe (HTTP 200) y coincide con el de `app/dist/index.html`.

7. **Reportar**: nombre del artefacto, commit, resultado del smoke. Si algo falló después
   de publicar, el ZIP anterior en `releases/` es el rollback inmediato (mismo paso 5).

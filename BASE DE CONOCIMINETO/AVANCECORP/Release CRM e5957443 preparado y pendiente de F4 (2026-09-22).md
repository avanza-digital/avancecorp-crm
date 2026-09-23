---
tags: [crm, release, acceso-avance, gestion-diaria, f4]
estado: paquete verificado; no publicado
fecha: 2026-09-22
---

# Release CRM e5957443 — paquete preparado, publicación pendiente

La invocación de `$release-crm` autorizó el frontend. El 22/09/2026 se preparó
desde una copia limpia del commit `e5957443ba4584b4ba1b895eba3cd9a033f5a39b`,
que coincidía con `avancecorp/main` después de integrar los PR #73 y #74. El
`main` del taller principal tenía trabajo ajeno y no se modificó para construir.

- `npm run check`: **PASS** en el commit integrado.
- `npm run check:scripts`: **PASS**, incluidos los preflights de Gestión Diaria.
- E2E locales en Docker: **234 passed, 26 skipped** (9,1 minutos). El script
  `app/scripts/e2e-docker.sh` falla con Bash 3.2 cuando `CONTAINER_ARGS` está
  vacío; se ejecutó la suite completa con `CRM_E2E_CONTAINER` definido. La
  corrección del script sigue pendiente.
- `npm run release:crm` y `release:crm:verify`: **PASS**, con configuración
  pública productiva validada y bundle sin archivos internos.

Paquete **preparado, no subido**:

- `CRM-Avance-Corp/releases/crm-20260922T235305Z-e5957443ba45.zip`
- `CRM-Avance-Corp/releases/crm-20260922T235305Z-e5957443ba45.manifest.json`
- SHA-256 ZIP: `cda249be21f7e97b9d0e055feb47321d2a38570bbc7d1b4a97ba8a95f564d3ab`
- 114 archivos, fuente limpia y destino `crm.miavance.com` según manifiesto.
  ZIP y manifiesto se copiaron al taller y se volvieron a verificar allí.

El sitio seguía HTTP 200 con el paquete anterior
`crm-20260922T221443Z-7d65fcdb484f.zip`, SHA-256
`bd9dc6c8dc10a55d5a314f862f75a45d9720b755401b84394e2976f85d891932`.
La portada y el JS principal servidos coincidieron byte a byte con sus entradas,
por lo que es un respaldo exacto de esas piezas, no del nuevo paquete.

**Bloqueo de backend:** producción aún no registra las cuatro migraciones F4
`20260922184459`, `20260922185138`, `20260922204125` y `20260922220800`.
Una consulta de solo lectura confirmó que `crm.gestion_diaria_entregas` y
`crm.gestion_diaria_control_avisos` no existen. La propuesta F4 requiere
autorización separada para conciliar el ledger de etapa 3, probar los cuatro SQL
en una rama Supabase temporal sin datos productivos, ejecutar matriz RLS/advisors
y fusionar con la política OFF. `$release-crm` no autoriza aplicar ese SQL.

**Bloqueo de despliegue:** el inventario efectivo de Hostinger de esta sesión
no expone `hosting_deployStaticWebsite`, la operación exigida por la habilidad.
No se subió ningún archivo. No hay smoke postdeploy que reportar. Antes de
continuar: obtener la autorización específica de F4, completar su instalación
y gates, reconectar la herramienta de Hostinger, reconfirmar `avancecorp/main`
y reconstruir si el commit cambió.

Relacionado: [[Gestion Diaria F4 - etapa 3 publicada con cortes OFF (2026-09-22)]],
[[Acceso Avance - apellidos y nombres separados (2026-09-22)]], [[Inicio]].

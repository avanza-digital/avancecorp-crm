---
name: release-crm
description: Verifica, construye y publica el frontend del CRM Avance Corp en crm.miavance.com (Hostinger). Adaptación para Codex del comando /release-crm de Claude; usar cuando Miguel invoque $release-crm o seleccione esta habilidad para publicar el CRM.
---

# Publicar el CRM Avance Corp

Esta habilidad publica en **crm.miavance.com**. La invocación humana de
`$release-crm` en Codex equivale a `/release-crm` en Claude y autoriza la
publicación del frontend después de pasar sus gates. No exigir además el
comando de Claude ni volver a pedir la misma autorización. Si Miguel pide solo
preparar, verificar o crear la habilidad, respetar ese alcance sin publicar.

## Proyecto y fuente

- Localizar la raíz Git que contiene `CRM-Avance-Corp/package.json`. Las rutas
  siguientes parten de esa raíz; no dependen de una carpeta temporal concreta.
- Leer `AGENTS.md`, `CRM-Avance-Corp/CLAUDE.md`, `.ai/VERIFICATION.md` y las actas
  vigentes de la funcionalidad que se publica. Usar CodeGraph para navegar código.
- El destino Git es **avancecorp/main** del repositorio `avancecorp-crm`.
  Hacer fetch, integrar cambios remotos sin sobrescribirlos y comprobar que Main
  local y `avancecorp/main` apuntan al mismo commit. No usar `origin/main` de otro
  proyecto, `tronco`, ramas de release ni push forzado.
- Construir desde una copia limpia de ese commit. Preservar trabajos ajenos;
  no incluir cambios sin confirmar ni usar `--allow-dirty`. Si esos cambios son
  parte necesaria de lo que Miguel quiere publicar, resolver su inclusión antes
  de construir. No crear un worktree automáticamente.
- Comprobar los prerrequisitos SQL/Edge ya aprobados en sus actas. Esta habilidad
  publica frontend: no aplica migraciones pendientes ni un `db push` general.
  Un backend incompatible pendiente debe resolverse con su autorización propia.

## Verificar y construir

1. Obtener PASS de `npm run check` en `CRM-Avance-Corp/app/` para el código que
   se publicará, más los gates de dominio pertinentes. Se puede reutilizar
   evidencia existente del mismo código cuando el commit solo agrega actas;
   documentar esa equivalencia. Un check fallido impide publicar.
2. Ejecutar en `CRM-Avance-Corp/`:
   ```sh
   npm run release:crm
   npm run release:crm:verify -- releases/<manifiesto-generado>.manifest.json
   ```
3. Verificar que el manifiesto identifica el commit acordado, fuente limpia,
   destino `crm.miavance.com` y SHA-256 del ZIP. Reconfirmar Main/remoto antes de
   subir; si cambiaron, integrar, comprobar el nuevo código y reconstruir.
4. Identificar el último ZIP publicado para recuperación. Conservarlo junto
   con su manifiesto; no confundir un paquete preparado con uno publicado.
5. Pasar el preflight obligatorio desde la raíz del repositorio (el conector de
   Hostinger no lo corre):
   ```sh
   node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com CRM-Avance-Corp/releases/<zip-generado>.zip
   ```
   Compara el candidato con el commit vivo y se niega si el build no contiene lo
   publicado. Si rechaza, no publicar: seguir «Si el preflight te rechaza» del
   `CLAUDE.md` raíz.

## Publicar y comprobar

- Usar el conector Hostinger disponible, operación `hosting_deployStaticWebsite`,
  para el sitio exacto `crm.miavance.com`, con el ZIP verificado. Consultar el
  esquema real de la herramienta: no inventar argumentos ni URLs de subida.
- Si la herramienta necesita una URL del ZIP, usar el mecanismo de subida
  autorizado para este proyecto; no subir archivos de entorno ni credenciales.
- Si falta el conector o acceso, conservar el paquete y explicar el bloqueo
  concreto. No cambiar proveedor, DNS ni configuración MCP como parte del release.
- Tras la respuesta de despliegue, comprobar HTTP 200 de la portada y del JS
  principal que referencia. Comparar el nombre/hash con `app/dist/index.html` y
  los bytes descargados con el manifiesto. Verificar los assets JS/CSS publicados
  y el acceso básico sin crear ni eliminar datos reales para probar.
- Si la publicación devuelve un resultado ambiguo, consultar estado y archivos
  servidos antes de repetir. Si falla la verificación posterior, diagnosticar
  con esa evidencia. El ZIP publicado anterior es la vía de recuperación, pero el
  preflight lo rechazará: no publicarlo sin preflight por cuenta propia; reportar la
  evidencia a Miguel, que decide el rollback. No reintentar indefinidamente ni revertir
  SQL o auditorías.

## Entrega

Reportar URL, commit, artefacto, huella y smoke PASS/FAIL/NOT RUN. Registrar en el
vault la versión efectivamente publicada y las limitaciones reales. Si una acta
posterior cambia Main, conservar como fuente del despliegue el commit del
manifiesto: no atribuirle otro commit ni publicar otra vez solo por esa acta.

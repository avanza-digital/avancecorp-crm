# Handoff deploy CRM orígenes 2026-07-17

> **Estado final: COMPLETADO EN PRODUCCIÓN el 2026-07-17.** El branch temporal fue eliminado y el portal de clientes no se modificó.

## Objetivo

Desplegar exclusivamente el CRM con los orígenes activos `referido`, `landing`, `formulario`, `oficina` (label `Wallking`) y `otro`. `web`, `campania` y `whatsapp` quedan retirados del selector, pero válidos para lectura histórica. No tocar el portal de clientes.

Relacionado con [[Canales de origen de leads CRM]], [[CRM conexión a datos reales]] y [[Deploy a Hostinger]].

## Implementación local completada

- Catálogo, formulario, API, tipos, métricas, datos demo y pruebas del CRM actualizados.
- Migración canónica: `CRM-Avance-Corp/supabase/migrations/20260717163959_crm_origenes_landing_formulario.sql` (misma versión registrada en producción).
- Validación local: 7 archivos de prueba, 94 pruebas aprobadas, typecheck aprobado y build aprobado.
- Ningún flujo E2E selecciona `web`, `campania` o `whatsapp` para altas nuevas.
- No se modificó el portal de clientes.

## Estado previo a la reanudación (registro histórico)

- Proyecto de producción: `dctqcbznekcyxhjujuci` (`PortalAvanceCorp`).
- El CLI de Supabase fue autenticado con la cuenta correcta y la carpeta `CRM-Avance-Corp/` quedó enlazada a ese proyecto.
- El conector/plugin Supabase se reconectó desde la UI, pero la sesión anterior siguió devolviendo `MCP internal error`. En la próxima sesión, verificar primero con `supabase.list_projects` y `supabase.get_project`.
- No usar `supabase db push`: el historial remoto contiene migraciones del portal que no existen en la carpeta CRM. El dry-run lo rechazó. No ejecutar `migration repair`.

### Branch temporal creado en ese momento

- Nombre: `crm-origenes-20260717`.
- Branch ID: `51b86977-1040-4009-bc58-febbdce25842`.
- Project ref del branch: `wplzoxigqwnpinotzcub`.
- Parent: `dctqcbznekcyxhjujuci`.
- Se creó sin copia de datos (`with_data=false`) y todavía no tenía migraciones nuevas aplicadas al entregar este handoff.
- Costo autorizado por Miguel: USD 0.01344 por hora. Eliminarlo inmediatamente después del merge o si se abandona el deploy.

## Secuencia ejecutada durante la reanudación

1. Verificar que el conector Supabase vea `dctqcbznekcyxhjujuci`.
2. Consultar el estado del branch temporal y esperar `ACTIVE_HEALTHY`.
3. Aplicar `20260717163959_crm_origenes_landing_formulario.sql` únicamente al project ref del branch `wplzoxigqwnpinotzcub`.
4. Verificar en el branch que `landing` y `formulario` sean aceptados, que los históricos sigan permitidos y que un valor inválido sea rechazado. Hacer pruebas dentro de transacción y rollback; no dejar fixtures.
5. Ejecutar advisors del branch y revisar que no haya hallazgos nuevos relevantes.
6. Fusionar el branch `51b86977-1040-4009-bc58-febbdce25842` a producción.
7. Verificar en producción la definición de `leads_origen_check` y la presencia de la migración.
8. Eliminar el branch temporal para detener el costo.
9. Rehacer `npm run build` en `CRM-Avance-Corp/app/` si fuese necesario y crear ZIP del contenido de `dist/`, con `index.html` y `.htaccess` en la raíz.
10. Confirmar la existencia de `~/.hostinger_token` sin mostrar su contenido.
11. Desplegar solamente a `crm.miavance.com` con `_DEV_NO_SUBIR/deploy-hostinger-mcp.mjs`.
12. Verificar hashes del HTML/assets, HTTP 200 de assets, ZIP remoto 404 y smoke de login/alta de lead.

## Estado de Hostinger antes de reanudar

- El deploy todavía no se había ejecutado al entregar el handoff original.
- El ZIP local preparado fue `/private/tmp/avance-crm-origenes.FjOlxi/crm-origenes.zip`; es temporal, por lo que debe recrearse si ya no existe.
- Según [[Deploy a Hostinger]], el único requisito esperado es que `~/.hostinger_token` exista y siga vigente. No leer ni mostrar el token.

## Servidor local

Se inició Vite en `http://127.0.0.1:5173/` (sesión `51643`). Puede dejar de existir al reiniciar Codex; iniciar de nuevo si hace falta.

## Resultado de la reanudación

- El conector Supabase volvió a funcionar: `list_projects` y `get_project` confirmaron `PortalAvanceCorp` (`dctqcbznekcyxhjujuci`) como `ACTIVE_HEALTHY`.
- El branch `crm-origenes-20260717` estaba sano. Se aplicó allí `crm_origenes_landing_formulario` y se probó dentro de una transacción: los 8 valores permitidos fueron aceptados, `invalido` fue rechazado y el rollback dejó 0 fixtures.
- Advisors: ningún hallazgo de seguridad nuevo. Los `unused_index` adicionales del branch eran INFO esperables por haberse creado sin datos.
- Merge confirmado en producción con migración remota `20260717163959_crm_origenes_landing_formulario`. La definición viva de `leads_origen_check` contiene los 5 orígenes activos y los 3 históricos.
- Branch temporal eliminado; al terminar solo quedó `main`.
- Build de producción aprobado: JS principal `index-BiFPTs47.js`, CSS `index-ClXZANBL.css`, catálogo `tipos-Chxbjun5.js` y API `crm-api-OTrZBRzP.js`.
- Desplegado exclusivamente a `crm.miavance.com`. HTML y los cuatro assets anteriores quedaron idénticos byte a byte entre local y producción; todos respondieron HTTP 200. `crm-origenes.zip` respondió 404 tanto en `crm.miavance.com` como en `miavance.com`.
- Smoke real: una sesión autenticada de supervisor cargó `#/clientes`, datos de producción y 0 errores de consola. El formulario de leads no se abrió con esa sesión porque `FUNCIONES_LEADS_APROBADAS=false` oculta intencionalmente esas vistas a vendedor/supervisor; no se cerró ni reemplazó la sesión. El catálogo compilado sí quedó verificado con solo los 5 activos en `ORIGENES`, y los 3 históricos únicamente en el catálogo completo de lectura.

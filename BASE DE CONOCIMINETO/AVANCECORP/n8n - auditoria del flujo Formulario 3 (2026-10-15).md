---
tags: [n8n, formulario3, auditoria]
actualizado: 2026-10-15
---

# n8n - auditoría del flujo Formulario 3 (2026-10-15)

Auditoría de solo lectura del flujo `BjI5m1PKVWhO0NDb` (Formulario 3 → CRM), hecha la tarde del 15/10. La primera pasada se hizo sobre una rama vieja; se corrigió leyendo el flujo vivo por el MCP de n8n y el generador de `avancecorp/main`.

## Estado comprobado (15/10, ~14:00 Lima)

- **Activo cada 5 min** desde 06:17 UTC, versión `e2f62a7e`. 102 ejecuciones desde las 04:00 UTC, **0 con error**. Sin rechazos ni «ya cliente» en la tabla de recibos.
- **El flujo vivo = `cargarDefinicionOperativa()` de `scripts/n8n/formulario3.fase6.mjs` en main.** Solo difieren valores por defecto que n8n reescribe (intervalo 5, condición `eq`, versión del IF). El generador base `formulario3.workflow.mjs` es histórico: no publicarlo.
- Ya resuelto en fase 6: los rechazos hacen fallar la ejecución y avisan (`exigirRevisionRechazos`); huellas repetidas se deduplican antes del lote; poda del VPS en 144 h.
- PR #294 (origen nativo `formulario_3`) **publicada el 15/10 ~16:23 Lima** (build `build-20261015T212300418Z`, Edge v26, migraciones A y B; acta `docs/FORMULARIO3-ORIGEN-NATIVO-PUBLICADO.md`). n8n sigue mandando FORMULARIO + campaña y el servidor lo traduce. **Ninguna fila de n8n ha pasado aún por la Edge v26**: el último recibo es de 13:50 UTC y los 116 se reclasificaron con la migración B. Revisar la primera fila nueva.
- Desde las 13:51 UTC las ejecuciones con éxito no se guardan (`saveDataSuccessExecution=none`): desde n8n no se ve si el cron corre cuando no hay filas nuevas. Solo los errores dejan rastro.

## Fase 7 (15/10, noche): puntos 1 y 2, más el latido y el resumen diario

Preparada, probada y **sin publicar** (publicar flujos en n8n necesita el permiso de Miguel). Acta: `CRM-Avance-Corp/docs/N8N-FORMULARIO3-FASE7.md`.

- **Una celda rara solo frena su fila.** La fila queda «rechazada» con la columna afectada.
- **El aviso incluye las filas que hay que revisar,** también la del cliente que no se pudo registrar.
- **Correo diario a las 7 p. m.** (flujo `Chn5g93IgxNlkF3K`) con nuevos, duplicados, clientes que volvieron, filas para revisar y la última lectura de la hoja (tabla de latido `CJpN45ukEXmZInuG`).
- **Pruebas:** 57/57 tests y 12 mutantes; banco en n8n (ejecución 268) y resumen de prueba (269, correo enviado). Codex revisó el plan y el código; sus hallazgos están aceptados.

## Pendientes que siguen vigentes (antes de la fase 7)

1. **Fila veneno (P2).** `texto()` lanza ante un tipo inesperado (`formulario3.mjs:20`), sin captura por fila en «Preparar leads» (código igual al vivo). Una celda VERDADERO/FALSO en la hoja frena **todas** las importaciones hasta corregirla (avisa 1 vez por hora).
2. **«Ya cliente» que no se pudo anotar no avisa (P2).** `exigirRevisionRechazos` solo mira `rechazado`. «YA ES CLIENTE: NO se pudo anotar (nadie a cargo de este cliente)» (`resultado-importacion.ts`, rama `sin_ficha`) queda solo en la tabla de recibos.
3. **Permisos de las credenciales (P2, sin verificar lo concedido).** Por defecto n8n pide para Gmail `https://mail.google.com/` y para Sheets `spreadsheets`. Preferir Resend con clave solo de envío y una cuenta de servicio de solo lectura. El secreto del importador es el mismo del Apps Script.
4. **MCP de n8n con escritura en todos los proyectos.** Desde el 15/10 el MCP está a nivel de usuario: cualquier sesión puede ejecutar, editar o publicar el flujo vivo. El acta de fase 6 prohíbe ejecutar a mano con el cron activo y n8n no tiene límite de concurrencia por flujo.
5. Huella por contenido: editar una fila ya importada la reenvía. Si el lead quedó descartado, convertido o borrado, el índice `uq_leads_telefono_vivo` no lo frena y nace otro lead. Decisión documentada en fase 6; vigilar.

Relacionado: [[Formulario 3 - fase 6 carga y activación (2026-10-15)]] · [[Formulario 3 - origen nativo preparado (2026-10-15)]] · [[n8n - Formulario 3 preparado y avisos conectados (2026-10-14)]]

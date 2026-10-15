# n8n - Formulario 3preparado y avisos conectados

Estado al 14/10/2026, continuación **N8N-AVANCE-141026**. Codex PRIMARY; Miguel hizo personalmente todos los pasos del navegador. Claude revisó el trabajo dos veces; se evaluaron y aplicaron las mejoras pertinentes. No se operó el navegador de Miguel.

## Decisión de negocio

Los leads de esta campaña deben mostrar **Formulario 3** en el CRM, conservando el canal **FORMULARIO**, el mismo reparto y las mismas reglas de conversión. No es un nuevo canal con reglas distintas. Se deben cargar las filas existentes y las futuras de la hoja ya filtrada.

La hoja vigente reemplaza la del inicio de la instalación: https://docs.google.com/spreadsheets/d/1lPvJ-65PNY1d4eme5xpcJ8ITVazkQRdjtkgW4ZLoIsI/edit#gid=0 — pestaña **Hoja 1**, rango A1:J. Lectura verificada: 127leads, 121 en PEN / 6 en USD; se omite una fila totalmente vacía. Cuenta Google: miguel@miavance.com. No se modificó la hoja.

Se conservan las decisiones de [[Carga de leads desde hoja de Google]]: piso del rango de capital, moneda mixta PEN con nota, ambos teléfonos para que el importador elija el válido, sin vendedor forzado y consentimiento SI para estas respuestas de Facebook cuando no viene columna explícita.

## Estado real de n8n

- Instancia: https://n8n-t27j.srv1906432.hstgr.cloud — 2.43.5.
- Flujo principal: **Avance Corp — Formulario 3 → CRM**, ID **BjI5m1PKVWhO0NDb**: https://n8n-t27j.srv1906432.hstgr.cloud/workflow/BjI5m1PKVWhO0NDb.
- Borrador de22 nodos y26 conexiones, guardado y comparado con el generador local; **INACTIVO**, `enviar_crm=false`, **Importar en CRM deshabilitado**. Nunca se enviaron leads reales al CRM.
- Google Sheets: credencial **Google Sheets account 2**, ID **vPzsYCzKnotpycYi**. La antigua **6Ak0p9yph1Jd5Llw** no sirve para este flujo: la asignación automática del MCP puede elegirla; fijar expresamente la correcta.
- Importador: **Simplified Custom Auth account**, ID **YNRHr2PjhfLXnKff**, tipo **httpTemplatedCustomAuth**. Miguel rellenó `anon_key` y `importar_secret`; ninguno se compartió en el chat ni se guardó en archivos del repo.
- Plantilla de autenticación: cabeceras `Authorization: Bearer {{anon_key}}` y `x-importar-secret: {{importar_secret}}`. El secreto proviene de la propiedad **IMPORTAR_SECRET** del Apps Script existente; ANON_KEY está en su código. No usar service_role.
- Endpoint existente: https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-importar-leads.
- Autenticación real PASS: ejecución 16, POST con `{"filas":[]}` devolvió400/`Sin filas que importar`, antes de cualquier escritura. Ejecución 23verificó también la identidad de la fila por la salida de error del HTTP real.
- Recibos definitivos: Data Table **1foRUzITWOnUJsNf**, **Formulario 3 — importaciones**, vacía al cierre. Solo registra importado, duplicado, ya_cliente o rechazado; nunca pendientes/aplazados.

## Protecciones y avisos

Valida los diez encabezados antes de mapear, usa SHA-256del contenido sin el número de fila, omite recibos confirmados, procesa de una en una y reintenta HTTP hasta 3 veces con timeout de 20 s. Selecciona hasta 25 pendientes rotando un puesto por intervalo de 5 minutos; así, las primeras filas lentas no bloquean permanentemente a las demás. Antes de cada fila verifica un presupuesto de 100 s sobre un timeout total de 180 s. Los pendientes vuelven al bucle; el resumen falla después de procesar el lote. Si todo se aplaza y no hay avance también falla.

Miguel pidió avisos a **miguel@miavance.com**. Flujo **Avance Corp — Avisos de Formulario 3**, ID **4jfthNhVJLiZUeIo**, publicado y enlazado en `settings.errorWorkflow`. Gmail OAuth2 **FNfEzbpTEsdutlzd / Gmail account**, autorizado por Miguel; Gmail API habilitada en el proyecto existente. Data Table de avisos **TcpMCmhVw3oT9GjD**.

Correo de prueba real enviado 1 vez (ejecución 26); repetición dentro de la misma hora no envió otro (28). Máximo un aviso por hora de reloj; la clave de prueba es distinta de la real. El correo contiene el enlace al flujo y el identificador de ejecución, sin datos de leads ni el error crudo. La recepción de un fallo de producción por Error Trigger queda pendiente de la activación del principal: n8n no dispara ese mecanismo desde ejecuciones manuales.

## Evidencia y límites

Archivos reproducibles en `CRM-Avance-Corp/scripts/n8n/`: módulos de mapeo, workflow y alertas, sus tests, `verificacion-20261014.json` y `revisiones-claude-20261014.txt`.

PASS: 25 tests locales; `npm run check:scripts`; validación MCP/SDK; vista previa real de 127 leads; aislamiento de errores 20/21 permitiendo procesar 22; recuperación solo de pendientes; repetición sin nuevos envíos; límite 25; rotación; falta de tiempo; importador deshabilitado sin recibos falsos; autenticación real; correo y supresión de repetición. Las ejecuciones simuladas usaron datos sintéticos y una tabla distinta, eliminada al terminar. Los tres workflows temporales quedaron archivados. Los recibos de producción siguen en 0.

Los dos dictámenes de Claude fueron CHANGES_REQUESTED; se aplicaron las correcciones y se ejecutaron los checks finales. No afirmar que Claude emitió PASS. Su hipótesis inicial sobre el tipo de credencial se rechazó con esquema/documentación vigente y autenticación real; el segundo review aceptó esa evidencia.

La entrega es **al menos una vez**, no exactamente una vez: una caída entre el POST exitoso y el recibo puede provocar reintento; el CRM tiene su guarda de duplicación de 7 días. No ejecutar importaciones manuales simultáneamente con el cron; el backfill supervisado debe hacerse con el flujo inactivo. Un aviso que corre dentro de n8n no detecta la caída completa del VPS/n8n.

Build/E2E del frontend: NOT RUN, sin cambios en el CRM en esta etapa. No hubo deploy ni escrituras de leads en la base.

## Continuación necesaria antes de activar

1. Implementar y verificar que el CRM persista y muestre **Formulario 3** como campaña bajo **FORMULARIO**. El payload ya incluye `campania_origen`, pero el Edge existente todavía lo ignora; actualmente solo iría en la nota. **La etiqueta visible no está implementada.**
2. Seguir el procedimiento de publicación del CRM. Después realizar una importación controlada y comprobar el resultado visible, reparto y recibo.
3. Solo entonces habilitar el nodo HTTP, cambiar `enviar_crm` y activar el cron de 5 minutos. No dar por terminada la integración completa con el borrador aún apagado.

Relacionado: [[n8n instalado en VPS y Hermes retirado (2026-10-14)]] · [[Carga de leads desde hoja de Google]] · [[Canales de origen de leads CRM]].

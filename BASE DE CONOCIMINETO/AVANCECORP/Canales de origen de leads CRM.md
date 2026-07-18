# Canales de origen de leads CRM

Decisión vigente desde el 2026-07-17.

## Orígenes seleccionables

- `referido` — Referido
- `landing` — LANDING
- `formulario` — FORMULARIO
- `oficina` — Wallking
- `otro` — Otro

## Orígenes históricos

`web`, `campania` y `whatsapp` ya no están disponibles al crear o editar leads. Se conservan como valores válidos de lectura para no romper los registros históricos ni sus métricas.

La clave técnica `oficina` se mantiene para preservar compatibilidad; únicamente cambia su etiqueta visible a `Wallking`.

Este cambio pertenece exclusivamente al CRM y a la restricción `crm.leads.origen`. No modifica el portal de clientes ni sus tablas o flujos.

## Estado en producción

Desplegado y verificado el 2026-07-17:

- Supabase: migración remota `20260717163959_crm_origenes_landing_formulario`; constraint probado primero en branch con rollback y luego verificado en producción.
- Frontend: `crm.miavance.com` sirve `index-BiFPTs47.js` y `tipos-Chxbjun5.js`; hashes idénticos al build local y assets HTTP 200.
- El branch temporal se eliminó y el ZIP de despliegue no quedó público (404 en CRM y portal).
- El portal de clientes no fue desplegado ni modificado.

Relacionado con [[F0 Cimientos BD del CRM]] y [[CRM conexión a datos reales]].

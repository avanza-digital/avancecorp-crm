# Canales de origen de leads CRM

Decisión vigente desde el 2026-07-17, ampliada el 2026-09-01.

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

## Alta manual

Desde el 2026-09-01, `landing` y `formulario` también son seleccionables al
crear un lead manualmente. Esta decisión reemplaza la restricción D8 del
2026-08-11 que reservaba ambos orígenes para el puente automático.

La regla especial de `referido` no cambia: solo un vendedor puede declararlo y
el lead queda a su propio nombre. Supervisores y gerencia pueden seleccionar
`landing`, `formulario`, `oficina` u `otro`.

### Efecto en la conversión mensual

Un lead `landing` o `formulario` creado manualmente cuenta en la cartera, la
trazabilidad, los cierres, el numerador y cualquier otra métrica que le
corresponda. La única excepción es su recepción: aporta **0 al divisor mensual**
del analista. Por ello, si convierte, puede sumar 1 al numerador sin sumar 1 al
divisor y la conversión puede superar el 100 %.

La regla depende de la procedencia del alta, no solo del texto del origen. Un
`landing` o `formulario` ingresado por el puente automático conserva su aporte
normal de 1 al divisor. La base sella esa procedencia en
`crm.leads.alta_manual`; no se deduce de `creado_por`, porque su FK puede quedar
en `NULL` al eliminarse el perfil autor.

## Estado en producción

Desplegado y verificado el 2026-07-17:

- Supabase: migración remota `20260717163959_crm_origenes_landing_formulario`; constraint probado primero en branch con rollback y luego verificado en producción.
- Frontend: `crm.miavance.com` sirve `index-BiFPTs47.js` y `tipos-Chxbjun5.js`; hashes idénticos al build local y assets HTTP 200.
- El branch temporal se eliminó y el ZIP de despliegue no quedó público (404 en CRM y portal).
- El portal de clientes no fue desplegado ni modificado.

Relacionado con [[F0 Cimientos BD del CRM]] y [[CRM conexión a datos reales]].

# Leads: filtro de origen (2026-09-16)

Relacionado: [[Inicio]] · [[Leads filtro integrado - vista local 2026-09-13]] ·
[[Canales de origen de leads CRM]] · [[Filtro por fuente de conversion comercial 2026-09-07]]

## Pedido de Miguel

«En el módulo Leads todo el sistema tiene filtro de origen». Aclaración suya:
**Leads es Leads** (la pantalla del menú «Leads», `cartera.tsx` en el código) y
**Cartera es otra cosa** (clientes y contratos, `mi-cartera.tsx`). Es un filtro
más en un módulo, no una función nueva.

## Decisión

Selector **«Origen»** junto a etapa, recepción y analista, con «Todos los
orígenes» por defecto. Los 5 orígenes vigentes (Referido, LANDING, FORMULARIO,
Walking, Otro) arriba y los 3 históricos (Web, Campaña, WhatsApp) en un grupo
aparte, para consultar leads antiguos sin que parezcan opciones de alta.

Como el filtro de recepción del 13/09: **tabla, Total leads, Capital en juego,
Activos, Convertidos y distribución por etapa salen del mismo conjunto
filtrado** antes de paginar. El origen compone con etapa, analista, búsqueda y
fechas; «Limpiar filtros» también lo reinicia.

## Cómo se hizo

- Servidor: `crm.cartera_filtrada_fn` recibe `p_origen` (10 argumentos); la
  firma de 9 se retira en la misma migración (`20260916220124`). Sin el
  parámetro responde igual que antes. Valores fuera del CHECK de
  `crm.leads.origen` se rechazan (22023). Ámbito, RLS y permisos intactos.
- Front: `«Todos»` no viaja; con un origen elegido el cliente exige que el
  servidor devuelva el mismo origen y filas coherentes, o rechaza la respuesta.
  Por eso el orden de publicación es **servidor primero, front después**.
- Ensayo en copia local a paridad con producción
  (`CRM-Avance-Corp/supabase/scripts/cartera-origen/`): equivalencia sin filtro
  para 11 actores, instalación, oráculo propio, reversa y reinstalación: PASS.

## Hallazgo colateral

El gate analítico de producción (`private.assert_analitica_leads_citas`) estaba
en rojo el 16/09 porque `crm.contrato_eliminar_auditado(uuid,uuid)` (migración
`20260916160000`, otra sesión) cuenta leads y no está declarado. Esta migración
no lo tapa: exige que lo rojo quede exactamente igual. Declararlo es tarea de
quien lo publicó.

## Estado

**En producción desde el 16/09/2026 (~18:45 Lima).** SQL instalado y registrado
por Miguel con `!` (migración `20260916220124`), front publicado con su token
(release `crm-20260916T231007Z-322ca2fcf373`, commit `322ca2fc`), smoke byte a
byte contra el manifiesto. Codex revisó (CHANGES_REQUESTED por la reversa sin
guardas) y se atendió antes de publicar. Acta completa en `MIGRACIONES.md` y en
`CRM-Avance-Corp/supabase/scripts/cartera-origen/README.md`.

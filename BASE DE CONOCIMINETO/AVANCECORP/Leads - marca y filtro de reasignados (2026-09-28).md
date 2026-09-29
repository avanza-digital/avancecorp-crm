# Leads: marca y filtro de reasignados (2026-09-28)

Pedido de Miguel: saber cuántos leads fueron reasignados, filtrarlos y ver una
marca en la fila y la ficha sin perder «Sistema»/«Manual». Relacionado con
[[Procedencia del lead - sistema o manual (2026-09-19)]],
[[Leads - filtro de origen (2026-09-16)]] y
[[Distribución de leads por capital y trazabilidad CRM]].

**Regla:** «Reasignado» indica trayectoria de asignación, no procedencia del
alta. Cuenta si hoy tiene analista y antes estuvo a cargo de un analista,
con evidencia en la actividad `reasignacion` y `vendedor_anterior` no nulo.
La primera entrega automática o desde la bandeja no cuenta. A → B, A →
bandeja → B y A → bandeja → A sí cuentan. Un lead aparcado sin titular actual
no figura en la cifra de reasignados. Sistema/Manual permanece como marca
separada: un lead puede ser «Sistema · Reasignado» o «Manual · Reasignado».

La migración `20260929010707_crm_leads_reasignados.sql` amplía la cartera
keyset con `p_reasignados`, `reasignado` por fila y
`resumen.totales.reasignados`. El conteo sale de la misma base filtrada que
los indicadores y la tabla, antes de paginar; respeta la RLS y se combina con
etapa, origen, procedencia, analista, búsqueda y fechas. La ficha relee por id
y comprueba su historial bajo RLS para conservar la marca si se abre desde
otra pantalla. En demo se aplica la misma regla al historial local.

Estado: implementación local y ensayo SQL aislado; pendiente de publicación.
Verificación del 29/09: `npm run check` en `app/` PASS (4.845 tests y build),
`app/e2e/cartera-keyset.spec.ts` en Docker 5/5 PASS. La migración actualizada
pasó preflight y postflight en `avc_leads_reasignados_test3`, banco Docker
aislado copiado del esquema local anterior y con los datos de configuración
necesarios. En ese mismo banco, el fixture SQL transaccional pasó: trigger real,
conteos, filtros, consumidor `resumen_cartera_fn`, RLS por rol y veto de
reasignaciones inventadas. El banco `test2` también pasó antes de reforzar el
preflight de trigger/policy y agregar el smoke del consumidor.

Se creó una branch de prueba de Supabase de la organización confirmada por
Miguel, pero su reproducción automática de migraciones terminó en
`MIGRATIONS_FAILED` antes de alcanzar la firma de cartera requerida. Se
eliminó inmediatamente para no acumular costo; no se aplicó SQL allí ni en
producción. El fallo de replay es una limitación conocida del proyecto
([[Diagnostico de Branching antes de F1 (2026-09-01)]]). Los preflights de seed
y RLS no arrancaron sin `SUPABASE_URL`; siguen pendientes la matriz RLS y
advisors en branch autorizada, y regenerar los tipos desde el esquema nuevo
(el comando actual apunta al proyecto productivo, todavía sin la firma).

La primera corrida de la suite E2E completa encontró una expectativa vieja en
`sla-operacion.spec.ts` ante la cola de «Hoy»; el caso corregido pasó 1/1. La
segunda corrida coincidió con otras dos suites Docker en la misma máquina y
Chromium falló al abrir la primera pantalla por saturación; se detuvo esa
ejecución, sin atribuirle un PASS. Miguel pidió publicar solo Reasignados, por
lo que el siguiente artefacto debe excluir los commits locales no publicados
de «Hoy del analista». La publicación usa `$release-crm` invocado por Miguel.
Comprobación agregada de producción el 28/09: 4.817 eventos `reasignacion`
de agosto y setiembre, todos con la clave `vendedor_anterior`; 152 tienen un
analista previo. La regla produce 104 leads de la cartera operativa global
actual. El dato depende del corte y de la visibilidad del usuario, por lo que
la cifra definitiva es la que calculará el filtro en cada sesión.

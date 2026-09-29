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

La migración `20260929164200_crm_leads_reasignados.sql` amplía la cartera
keyset con `p_reasignados`, `reasignado` por fila y
`resumen.totales.reasignados`. El conteo sale de la misma base filtrada que
los indicadores y la tabla, antes de paginar; respeta la RLS y se combina con
etapa, origen, procedencia, analista, búsqueda y fechas. La ficha relee por id
y comprueba su historial bajo RLS para conservar la marca si se abre desde
otra pantalla. En demo se aplica la misma regla al historial local.

Estado: implementación local y ensayo SQL aislado; pendiente de publicación.
Verificación del 29/09: `npm run check` en `app/` PASS (4.903 tests y build),
`app/e2e/cartera-keyset.spec.ts` en Docker 5/5 PASS y suite E2E completa
284 PASS / 26 omitidos. La migración actualizada
pasó preflight y postflight en `avc_leads_reasignados_test4`, banco Docker
aislado copiado del esquema local anterior y con los datos de configuración
necesarios. En ese mismo banco, el fixture SQL transaccional pasó: trigger real,
conteos, filtros, consumidor `resumen_cartera_fn`, RLS por rol y veto de
INSERT/UPDATE/DELETE de eventos inventados. Una revisión secundaria detectó
que el preflight debía rechazar también una policy ALL permisiva o permisos
de escritura futuros; esa comprobación quedó aplicada y pasó en `test4`.

Se creó una branch de prueba de Supabase de la organización confirmada por
Miguel, pero su reproducción automática de migraciones terminó en
`MIGRATIONS_FAILED` antes de alcanzar la firma de cartera requerida. Se
eliminó inmediatamente para no acumular costo; no se aplicó SQL allí ni en
producción. El fallo de replay es una limitación conocida del proyecto
([[Diagnostico de Branching antes de F1 (2026-09-01)]]). Los preflights de seed
y RLS no arrancaron sin `SUPABASE_URL`; siguen pendientes la matriz RLS y
advisors en branch autorizada, y regenerar los tipos desde el esquema nuevo
(el comando actual apunta al proyecto productivo, todavía sin la firma).

El CRM vivo cambió durante la preparación: primero salió «Hoy» v3 y después
el anexo de contrato (commit vivo `fb79c46f8848` al 29/09). El candidato de
rescate parte de ese commit vivo y agrega solo Reasignados a lo ya publicado;
el preflight de Hostinger pasó. La suite E2E completa de esa app terminó
284 PASS / 26 omitidos en un contenedor propio. El SQL no está publicado:
faltan el gate remoto de RLS/advisors y la autorización de la migración; el
frontend tampoco está desplegado. La publicación usa `$release-crm` invocado
por Miguel, y necesita el conector Hostinger disponible.
Comprobación agregada de producción el 28/09: 4.817 eventos `reasignacion`
de agosto y setiembre, todos con la clave `vendedor_anterior`; 152 tienen un
analista previo. La regla produce 104 leads de la cartera operativa global
actual. El dato depende del corte y de la visibilidad del usuario, por lo que
la cifra definitiva es la que calculará el filtro en cada sesión.

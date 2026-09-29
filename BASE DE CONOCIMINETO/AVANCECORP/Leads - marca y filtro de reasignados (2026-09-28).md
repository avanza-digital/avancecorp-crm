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
Verificación del 29/09 sobre el vivo `ce9e688f28d4` más Reasignados:
`npm run check` en `app/` PASS (317 archivos / 4.909 tests y build).
La corrida previa sobre `fb79c46f` pasó `cartera-keyset.spec.ts` en Docker
5/5 y la suite completa 284 PASS / 26 omitidos. La migración actualizada
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
([[Diagnostico de Branching antes de F1 (2026-09-01)]]). `seed:preflight` y
`test:rls:preflight` PASS con la configuración real del Supabase local
(`127.0.0.1:55321`), sin conexiones ni siembra: validan runtime, variables y
matriz. Siguen pendientes la matriz RLS HTTP y advisors en branch autorizada. Se generaron los tipos de `public,crm` desde
`avc_leads_reasignados_test4` con `supabase gen types typescript --db-url`
(CLI 2.117.0): la firma completa de `cartera_filtrada_fn` coincide byte a byte
con `database.types.ts`, incluido `p_reasignados?: boolean`. El script
`npm run gen:types` apunta a producción, todavía sin la firma; no se ejecutó
contra ella ni se incorporaron diferencias ajenas del banco local.

El CRM vivo cambió durante la preparación: «Hoy» v3, anexo de contrato y
«Seguimiento/Hoy del supervisor» con cola v3. La copia aislada de rescate
`rescue/reasignados-ce9` parte del commit vivo
`ce9e688f28d43502c6ee66eac49a6a867774d25d`
(`build-20260929T164822097Z`) y agrega Reasignados sobre lo ya publicado.
Conserva el anexo y la cola v3. En el E2E heredado `acceso-avance-ux.spec.ts`
se corrigió un selector ambiguo: el correo se muestra tanto en el aviso como
en el resumen; se verifica el valor del resumen mediante su rol `definition`.
No cambia la aplicación de Acceso Avance. La suite E2E completa terminó
285 PASS / 1 flaky / 26 omitidos (10,9 min): el selector heredado pasó al
reintentar con la corrección; una repetición limpia del spec dio 3/3 PASS
sin reintentos. Resultado final de los 286 casos ejecutables: PASS, con el
incidente de la primera corrida conservado en el log. `npm run check:scripts` PASS en la
copia anterior; su código, package.json y scripts son idénticos en esta base.

El SQL y el frontend no están publicados: faltan el gate remoto de RLS/advisors
y la aplicación autorizada de la migración antes del frontend. La conexión
Hostinger incorporada en la sesión solo expone facturación, pero se verificó
la vía local ya documentada en [[Deploy a Hostinger]]: el cliente
`_DEV_NO_SUBIR/deploy-hostinger-mcp.mjs` arranca el MCP oficial de hosting
(contrato 2.x `search`/`execute`) y el token guardado permite consultar
`crm.miavance.com`. No requiere otro token ni cambios de configuración.
Se conserva el preflight obligatorio y la invocación humana de release.
Lectura productiva del 29/09 al cierre: firma anterior, trigger, policy de
INSERT, veto de UPDATE/DELETE y sello analítico siguen coincidiendo con el
preflight; la firma de 12 argumentos aún no existe.
Comprobación agregada de producción el 28/09: 4.817 eventos `reasignacion`
de agosto y setiembre, todos con la clave `vendedor_anterior`; 152 tienen un
analista previo. La regla produce 104 leads de la cartera operativa global
actual. El dato depende del corte y de la visibilidad del usuario, por lo que
la cifra definitiva es la que calculará el filtro en cada sesión.

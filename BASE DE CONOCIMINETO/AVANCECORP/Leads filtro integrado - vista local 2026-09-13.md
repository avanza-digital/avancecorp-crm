# Leads: filtro integrado — vista local y publicación

Relacionado: [[Inicio]] · [[Leads recibidos por dia para analistas 2026-09-12]]

## Corrección del requisito

Miguel rechazó el panel de conteos separado: necesita un selector de recepción
junto al filtro por etapa, ver y abrir los leads del período, y que TODOS los
componentes de este módulo usen los mismos filtros (tabla, total, capital,
activos, convertidos y distribución). Incluye analistas y supervisores.

Miguel confirmó después que el supervisor debe medir **los leads recibidos por
los analistas de su equipo**, no los que ingresan a su bandeja desde Coordinación.
Con fechas seleccionadas, se excluyen los pendientes de repartir; puede elegir
todo su equipo o un analista concreto. La vista sin fechas mantiene el inventario
actual y su opción de pendientes. Al pasar de «Sin asignar» a un rango, el selector
vuelve a «Todos los analistas» para no dejar un filtro contradictorio.

La vista local fue aprobada. Miguel autorizó después la publicación con
«ok publica». Se conserva el checkout aislado y no se incluyen los cambios
pendientes de otras sesiones.

## Vista previa inicial (histórico)

- Vista previa funcional únicamente en el modo DEMO local, con los componentes
  reales del CRM; conserva sin cambios el contrato de las sesiones reales.
- Checkout aislado: `/private/tmp/crm-filtro-leads.HMw8ft/repo`, base `d3ce2c1`.
- Servidor local en el puerto 5199; iniciar con `VITE_ENABLE_DEMO=true npm run dev -- --host 127.0.0.1 --port 5199 --strictPort`.
- Fechas inclusivas en Lima, combinadas con etapa, analista y búsqueda.
- Los totales se calculan sobre toda la colección demo antes de paginar, nunca
  sobre las 50 primeras filas. Fechas inválidas ocultan cifras anteriores.
- No se creó ni modificó ninguna rama de Supabase para esta vista previa.
- No se hizo commit, push ni deploy de esta corrección.

## Verificación local

PASS: typecheck, lint (4 avisos preexistentes de coverflow), 55 tests dirigidos,
build y comprobación visual en navegador. Incluye totales con más de 50 filas,
combinación por rol, límites horarios y apertura de fichas.

NOT RUN: gate de realidad (este checkout no tiene credenciales), RLS e integración
con datos reales. No son reemplazados por pruebas demo.

## Implementación real autorizada

La RPC `crm.cartera_filtrada_fn` usa un único conjunto filtrado para la tabla y
todos sus indicadores, antes de paginar. La recepción real sale del ledger de
asignaciones, no de `creado_en` ni de la última edición. Los días son inclusivos
en Lima. El último recibimiento que coincide aporta fecha y marca aproximada.
Un lead aparece una sola vez; las reasignaciones no inflan el total.

El alcance es la cartera que el actor todavía puede ver: no se abre acceso
histórico a leads transferidos fuera de su ámbito. Sin fechas se conserva el
inventario vigente de convertidos de 45 días; con fechas se incluyen convertidos
antiguos que coincidan con la recepción y sigan visibles. Capital PEN/USD separado.

El resumen general conserva su contrato y sus cierres mensuales para las otras
pantallas; delega el inventario al núcleo común para no duplicar contadores.
El censo analítico sigue en 34 declarados, 30 sujetos al techo y cuatro auxiliares.

Pruebas finales: 3.444 frontend PASS; 173 E2E PASS / 26 SKIP; SQL con paginación,
bordes de fecha, aislamiento de equipos y acceso revocado PASS; Auth/Data API
real y limpieza de la cuenta efímera PASS. El resumen anterior y el adaptador
dieron JSON idéntico para 16 actores durante el ensayo atómico con ROLLBACK.

Rama exclusiva: `leads-filtro-integrado-20260913` (`tohbxwumyjnxxxuhdfto`).
Migración: `20260913213842_crm_cartera_filtro_recepcion.sql`.
El estado final de instalación se registra en el ledger de migraciones y la
evidencia de publicación. Los avisos/deuda del gate general no se declaran PASS.

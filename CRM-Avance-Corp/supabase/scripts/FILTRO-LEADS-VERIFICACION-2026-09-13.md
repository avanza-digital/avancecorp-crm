# Filtro integrado de recepción de Leads — verificación

Autorización de Miguel: «ok publica», después de aprobar la vista local y
confirmar que el supervisor mide los recibidos por los analistas de su equipo.

## Alcance

Selector junto a etapa. Fecha, etapa, analista y búsqueda filtran el mismo
conjunto para filas, total, capital, activos, convertidos y distribución. El
total no depende de las primeras 50 filas. Días inclusivos en Lima; recepción
del ledger, un lead una vez, último episodio coincidente con su marca aproximada.
Se mantiene la visibilidad actual y no se amplían permisos a leads transferidos.

SQL: `20260913213842_crm_cartera_filtro_recepcion.sql`.
SHA-256: `b194cce80a4b666bc8bbcb2c2631e4fe72132b04e4a86300807c6cc891bc4915`.
Rama exclusiva: `leads-filtro-integrado-20260913` / `tohbxwumyjnxxxuhdfto`.
Base reconstruida y contrastada con las 278 migraciones productivas; datos de
prueba sembrados antes del ensayo y de la instalación. Delta de instalación: una migración.
Las 19 Edge Functions de la rama coinciden con producción (versión/hash/JWT).
Merge productivo completado el 13/09/2026. Las cuatro definiciones y ACL
coinciden con el banco; historial previo y funciones ajenas conservados.

## Gates

| Comprobación | Resultado |
|---|---|
| `npm run check` | PASS: lint, tipos, 238 archivos / 3.444 tests, cobertura, build y bundle; cuatro avisos previos de coverflow |
| `npm run test:e2e` | PASS: 173; 26 SKIP del banco existente |
| Preflights de scripts, seed, RLS y Edge | PASS |
| `ensayar-cartera-filtrada.mjs` | PASS antes de instalar; JSON anterior/nuevo idéntico para 16 actores, todo en ROLLBACK |
| `test-cartera-filtrada.sql` | PASS instalado: 74 leads ficticios, paginación completa, fechas, totales/capital, scopes y permisos negativos; ROLLBACK |
| `test-leads-recibidos-data-api.mjs` | PASS instalado: cuenta Auth real efímera, fila/total correctos, anónimo rechazado y cero residuos |
| Tipos generados desde la rama | PASS del contrato añadido; se conserva el resto del archivo para no arrastrar cambios de catálogo ajenos |
| Gobernanza analítica | PASS: 34 declarados, 30 bajo techo, cuatro auxiliares; sin alterar otras excepciones ni el techo |
| Matriz RLS general | FAIL: 1.740 PASS / 66 FAIL de 1.806; no se declara PASS global ni un A/B global |
| Advisors | Sin hallazgos nuevos sobre las tres funciones nuevas; deuda general previa conservada |
| `gate:realidad` productivo | FAIL técnico: siete mediciones sin divergencias, la octava no tiene SELECT sobre `periodos_cerrados`; equivalente SQL de solo lectura confirma cero metas bajo sello. No se cambió ese permiso |
| Review de Claude por wrapper protegido | NOT RUN: terminó sin dictamen; no se eludió el wrapper |

El auditor RLS independiente revisó la consulta y la consolidación del resumen.
Se aceptaron la selección determinista del episodio/fecha aproximada y los
candados, snapshots y comprobaciones de integridad del sello. Se descartó el
límite de 366 días del panel anterior: este filtro no genera series diarias y
el requisito admite rangos libres válidos. No hubo una cadena de reviews.

La matriz general arrastra expectativas de contratos antiguos, permisos de
corrección documental, pruebas de identidad/facturación y un banco sin política
ni hito de rentabilidad. Sus fallos se conservan en el log local
`/private/tmp/crm-filtro-leads.HMw8ft/rls-final.log`; no se alteraron esas funciones
ni se debilitó el gate. La huella de todas las funciones ajenas al cambio, sus
ACL y las 278 migraciones previas coincide con producción antes y después de
la matriz: `187bc606b26f76b5b02c66e449b7ef08` (funciones) y
`cebb7ae22fc40dd8a9ee9cebc1069a70` (historial).

Decisión del PRIMARY: el alcance publicable se sostiene en la equivalencia
anterior/nueva del único lector adaptado, las sondas de cartera/permisos de la
matriz y los oráculos nuevos instalados. No se declara saneado el resto del CRM
ni se incluye una reparación de esa deuda en esta publicación.

## Protección del resto del CRM

La nueva consulta pública es SECURITY INVOKER sobre `crm.leads` con RLS. Los
helpers privados validan actor/alcance y no están expuestos por Data API. El
adaptador `resumen_cartera_fn()` conserva firma, ACL, estado y cierres mensuales;
las demás pantallas no reciben el filtro de este módulo. No se alteran tablas,
políticas ni objetos de `public`. No se activan banderas de otras funcionalidades.

El build publicable debe salir de un checkout limpio cuyo commit coincida con
Main local y `avancecorp/main`. ZIP/manifiesto y comprobación HTTP identifican
el artefacto final; una prueba local o una migración en rama no equivalen a deploy.

# P-0XX — el USD pendiente deja de congelar el capital del mes

Estado: **publicado y verificado el 24/10/2026**. [Acta de publicación y evidencia productiva](capital-pendientes-20261023/PUBLICACION.md).
La preparación y pruebas iniciales que siguen se conservan como historial.
Base Git: `avancecorp/main`, `9c11fc75`. Trabajo en clon independiente; los repositorios originales conservan su trabajo local.

## Cambio

- `private.publicar_corte_capital` usa `v_hasta` y filtra las operaciones sin valoración antes de formar `base`,
  producción y facturación. Conserva identidad de personas, metadata de metas, locks, huella e historial.
- Los lectores existentes entregan `ventas_pendientes` mediante `private.capital_estado_corte`. Los importes
  originales quedan separados del capital confirmado; cuando llega TC, el worker incorpora la nueva valoración.
- `crm.capital_operaciones_valoradas_v2_fn` añade cobertura del analista después de delegar la autorización a v1.
  V1 conserva exactamente su respuesta. El cliente retrocede a v1 únicamente ante `PGRST202`.
- Facturación, metas y detalle del analista muestran «US$ 20,000 pendiente de tipo de cambio». El detalle incluye
  monto/moneda, fuente y fecha comercial. En Facturación el aviso dice expresamente que los pendientes son del
  mes completo antes de los filtros; los importes de lista y cuadro conservan el mismo corte y rango.
- El sello mensual no se modifica. La nueva puerta devuelve cobertura completa para un mes ya sellado.

Migración: [`20261024030000_crm_capital_pendientes_sin_bloquear.sql`](../../supabase/migrations/20261024030000_crm_capital_pendientes_sin_bloquear.sql).
El preflight rechaza un publicador distinto del auditado (`md5(prosrc)=629ec2c60834ab1dc72abcbef8542486`).
No modifica tablas, triggers, policies ni grants de `public`.

## Cinco casos solicitados

| Caso | Resultado en SQL local y rama Supabase |
| --- | --- |
| PEN 10:00, USD sin TC 11:00, PEN 12:00 | PASS: dos PEN, S/ 6.000; US$ 20.000 en pendientes; corte hasta hoy. |
| Llega TC 3,4 | PASS: nueva revisión, tres ventas, USD = S/ 68.000, total S/ 74.000; pendientes vacío. |
| Sellar con USD pendiente | PASS: rechazo por valoración pendiente; sin cierre ni sello creados. |
| Dos corridas sin cambios | PASS: mismo ID/revisión, tanto antes como después del TC. |
| Lista y cuadro diario | PASS: mismo corte y rango, S/ 6.000 y luego S/ 74.000; total independiente de paginación. |

26 aserciones SQL por banco. Incluyen datos originales del pendiente, aislamiento entre equipos, analista sin meta
ni producción valorada, ACL de la nueva puerta y cierre válido seguido de publicación sobre sello inmutable.
La simulación de fecha de cierre existe solo dentro de savepoints de la prueba y se revierte.

## Verificación adicional

- PASS: `test-rls.mjs --capital-pendientes-cloud`, 12 comprobaciones mediante Auth/PostgREST reales y cinco sesiones.
- PASS: `npm run check`, 477 archivos / 7.748 pruebas, lint, TypeScript, cobertura, configuración, push, build,
  bundle y duplicación. Diez avisos de lint existentes, cero errores.
- PASS: Playwright en Docker, ocho escenarios relacionados, cero fallos. Facturación, ranking, detalle y cumplimiento
  propio; transición a TC, meses mixtos, Citas y sello. Capturas inspeccionadas con datos exclusivamente sintéticos.
- PASS: firma de tipos de la nueva RPC idéntica a la salida del generador oficial `postgres-meta` sobre el banco candidato;
  conservada la metadata PostgREST del cliente. No se reemplazan tipos ajenos al cambio.
- PASS: advisors de rama antes/después. Único aviso de seguridad añadido: la puerta nueva es SECURITY DEFINER accesible
  a `authenticated`, comportamiento intencional y probado con autorización por ámbito. Sin nuevos avisos de rendimiento.
  Los 402 avisos de seguridad previos permanecen; este cambio no pretende resolverlos.
- NOT RUN: `gate:realidad` contra producción, por el límite explícito de verificar solo en rama. No se afirma paridad
  global de datos productivos. La regresión sin meta y los estados degradados del frontend sí están cubiertos.

El aviso de la puerta autenticada se evalúa con sus comprobaciones internas y ACL, no desactivando el definer:
[referencia del linter de Supabase](https://supabase.com/docs/guides/database/database-linter).

## Entorno y límites

Rama temporal `capital-pendientes-20261023`, proyecto `buacdmufspxktdfdllte`, organización AVANCECORP- CRM-PORTAL;
coste de US$ 0,01344/h autorizado expresamente. Creada sin datos. Su bootstrap histórico falló en la migración
`20260811210049`, antes de las funciones de capital. Se restauró únicamente el esquema del banco local existente,
preservando owners/ACL y servicios administrados; las funciones críticas se compararon antes de aplicar la candidata.
Publicador, estado y sello coincidían con las huellas esperadas. No se copió información de clientes.

La candidata se aplicó solo en esta rama; Supabase la registró como `20261024032900` con nombre
`crm_capital_pendientes_sin_bloquear`. Los cron heredados se desactivaron antes de preparar la base.
El banco SQL local estaba aislado con `network=none` y sin puertos. SQL terminó en rollback; HTTP conservó únicamente
cuentas y ventas sintéticas hasta la eliminación de la rama.

Reproducción: [README del banco](../../supabase/scripts/capital-pendientes/README.md).

## Revisión y entrega

Subagentes de investigación SQL, interfaz y pruebas trabajaron solo en lectura; el PRIMARY implementó.
El auditor RLS pidió filtrar por mes el contador de revisiones del test: corregido y repetido con PASS.
La revisión independiente de Claude se ejecuta mediante el wrapper obligatorio del repositorio.
Su dictamen `CHANGES_REQUESTED` y la resolución fundada del PRIMARY se conservan en
[revisión original](capital-pendientes-20261023/claude-review.md) y
[resolución](capital-pendientes-20261023/resolucion-review.md). No se pidió otra consulta para obtener un PASS.

La huella conserva la fecha de corte: un nuevo día puede generar revisión aun con las mismas operaciones.
Dos corridas con la misma fecha y contenido conservan el mismo ID. Es la consecuencia de publicar «hasta hoy»
y mantener la huella existente. Un analista sin meta ni capital valorado ve sus pendientes en cumplimiento;
su detalle sigue sujeto a la autorización v1 y no se añade una entrada artificial al ranking.

## Limpieza comprobada

Rama temporal eliminada el 24/10/2026 a las 03:55 UTC (23/10, 22:55 Lima); `delete_branch` respondió success
y el listado posterior ya no contiene su ID ni su project ref. Archivo privado de credenciales retirado.
Eliminados únicamente los contenedores `avancecorp-capital-banco-20261023` y
`avancecorp-capital-pendientes-20261023`; el contenedor E2E terminó con retirada automática.
Las ramas ajenas y los repositorios originales no se modificaron.

Evidencia conservada: [SQL de rama](capital-pendientes-20261023/sql-rama.log),
[Auth/PostgREST](capital-pendientes-20261023/auth-http.log),
[resumen de verificaciones](capital-pendientes-20261023/checks.json),
[Facturación](capital-pendientes-20261023/facturacion-pendiente.png) y
[detalle del analista](capital-pendientes-20261023/analista-pendiente.png).

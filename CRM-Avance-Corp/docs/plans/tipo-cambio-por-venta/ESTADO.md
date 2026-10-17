# Tipo de cambio fijo por venta — estado al 16/10/2026 (Lima)

Publicación autorizada con «ok publiquemos», en preparación y pruebas en la
rama temporal de Supabase. **Sin publicación ni activación productiva todavía.**
Estado vigente de este flujo: [PUBLICACION-20261017.md](PUBLICACION-20261017.md).
La pausa anterior
se levantó con «sigamos». El alcance completo de PLAN.md se mantiene.

## Resultado comprobado

USD 20 000 del 02/10 a 3,4000 conserva **S/ 68 000**, incluso tras aceptar otra
cotización de 3,1000. Una segunda venta de USD 10 000 aporta S/ 31 000: total
**S/ 99 000**. Se comprueba en numeric de Postgres, Auth/PostgREST reales,
lecturas del corte, detalle y sello mensual con reloj simulado.

## Implementación

Once migraciones candidatas: fundación `20261016190725`, operaciones
`20261016201516`, cortes/lecturas `20261016204221`, sello/activación
`20261016204946`, detalle `20261016220524`, escritores `20261016223745`,
reevaluación `20261016230914`, Citas `20261016233037`, índices `20261017025829`
y cierre acotado `20261017033241`, más conservación del censo analítico
`20261017040525`. Lista ejecutable compartida en
`supabase/scripts/tipo-cambio-por-venta/migraciones-locales.mjs`.

- Tasa por fecha/política y evidencia inmutables, siete pares completos BCRP,
  confirmación temporal, cola persistente reservada y backoff 1/5/15/60 minutos.
  El calculador legado conserva su algoritmo.
- Una valoración por fuente financiera/revisión; PEN a 1. Correcciones
  monetarias agregan revisión; reasignación o imputación sola no revalúan.
  Stock y desgloses conservan el cómputo y atribución nativos.
- Ranking, Metas, resúmenes, Equipo, Facturación/detalle y Citas/CSV usan el
  corte aceptado. Importe, población, metas e identidad del divisor comparten
  publicación. Pendientes conservan la última foto completa; sin primera foto
  no se inventan puestos ni equivalentes cero.
- Escritura CRM/portal con TC conocido materializa en su transacción; sin TC
  registra la venta y deja pendiente. No HTTP externo dentro de la transacción.
- Cierre atómico, mismo candado que corrección, cobertura revalidada bajo
  bloqueo. La última candidata exige reconciliación previa y limita espera
  de locks a 5 s: no procesa atrasos bajo bloqueos globales. El ciclo reintenta
  y muestra atascado tras 24 h; no reactiva cron ni fuerza tasa.
- API v1 estricta conservada; nuevas RPC v2/v3. Solo PGRST202 habilita fallback.
  RLS, auditoría, helpers revocados y escrituras de servicio. Huella completa
  de catálogo public idéntica antes/después. Copias Edge locales idénticas.

Semánticas y exportadores: [MAPA-CONSUMIDORES.md](MAPA-CONSUMIDORES.md).
Escritores: [INTEGRACION-ESCRITORES.md](INTEGRACION-ESCRITORES.md).
Citas: [INTEGRACION-CITAS.md](INTEGRACION-CITAS.md).

## Verificación ejecutada

| Gate | Resultado y alcance |
| --- | --- |
| Frontend `npm run check` | **PASS**, 424 archivos / 6 755 tests, lint/tipos/cobertura/release/build/bundle, duplicación 0,77 %. Se corrigieron las dos regresiones de test de la pausa. |
| Tipos completos | Generados con postgres-meta oficial sobre esquema restaurado + candidatas, public/crm, conservando metadata PostgREST 14.5. Typecheck posterior PASS. No se borraron propiedades previas. La última migración cambia solo un helper privado. |
| SQL | **PASS**, 27 dominio/legado + 16 atribución + 89 cortes/escritores/Citas; replay de diez candidatas y cuatro carreras concurrentes. Incluye 600 ventas conocidas diferidas antes del cierre, sin materializarlas bajo bloqueo. |
| Edge/simulador | **PASS**, 30 casos Deno; fmt/check y preflight Edge integral. |
| Auth/HTTP real | **PASS**, once cuentas ficticias GoTrue, ocho ámbitos mensuales (incluida Coordinación), PII, puertas y tablas denegadas, corrección autorizada/denegada, F4 preparar/revisar/confirmar, idempotencia, pendiente y recuperación. |
| Supabase Advisors | **PASS de comparación**: ningún WARN/ERROR nuevo; no significa banco sin avisos. Ver ADVISORS.md. |
| E2E Docker dirigidos | Ranking/Facturación 2 PASS; Citas 2 nuevos y 3 legados PASS; rangos mixtos 1 PASS escritorio/móvil. |
| Suite E2E completa | Corrida real: **427 PASS / 1 FAIL / 1 flaky / 26 skipped**, 18,4 min. El FAIL era el guard de test que rechazaba el PGRST202 simulado de compatibilidad. Se validó su cuerpo y se repitió TODO graficas.spec.ts: **5 PASS / 0 FAIL**, incluido el caso intermitente. No afirmar que aquella corrida completa devolvió PASS. No queda un fallo reproducido sin resolver. |
| Backend offline | check:scripts y preflight Edge PASS; seed/RLS preflight PASS con valores ficticios y loopback (sin conexión). Los once scripts nuevos pasan node --check. |
| Gate de realidad productivo general | **FAIL/INCOMPLETO**, límites descritos abajo; no es un PASS ni un motivo para ampliar grants. |

Los E2E de UI interceptan payloads reales de bancos sintéticos. La autenticación
y las RPC se acreditan por el gate HTTP separado; no se afirma un navegador F4
con Auth real ni render PDF binario/subida Storage. Los escritores nativos y
su reserva/rollback documental sí se ejecutan.

## Octubre reconstruido y producción de solo lectura

Censo actualizado 16/10 22:20 Lima: **116 operaciones**; 99 PEN por
**S/ 3 979 200**, 17 USD por **USD 195 423,33**. Sin fecha comercial faltante ni
vínculo a inversiones faltante. Metas: PEN 7 100 000 y USD 0. Ninguna deuda
monetaria pendiente; solo agosto figura sellado. Job 3 activo, postgres, base y
comando compatibles. Ningún cambio productivo de esta tarea instalado.

Las nueve fechas USD se descargaron nuevamente del BCRP y consolidaron. Replay
histórico con diez candidatas: **116 valoraciones, S/ 4 650 700,67**, pendientes
0; repetir crea **0 revisiones**. El clon usa hechos monetarios/ids de fuente,
pero contactos, documentos y personas ficticios; se retiró al terminar.
El banco anterior persistente de 108 operaciones / S/ 4 588 500,67 se conserva
como evidencia de otra captura, sin borrar ni reescribir su auditoría.
Comparación actual/propuesta por analista, avance y posición en
[SIMULACION-ACTUALIZADA.md](SIMULACION-ACTUALIZADA.md): misma población nativa,
TC de consulta 3,4401 frente a tasas por venta; total anterior S/4 651 475,80 y
fijo S/4 650 700,67. No confundir el cambio de metodología con una venta nueva.

Son controles del inventario stock. Ranking y Citas conservan sus propias
reglas de elegibilidad/atribución: no atribuir diferencias de población al TC.
El censo cambia; repetirlo y reconciliar al activar, incluso después de este
ensayo satisfactorio.

## Revisión independiente

Fundación: `REVISION-FUNDACION-2026-10-16.txt`. Integración final:
[REVISION-FINAL-2026-10-16.txt](REVISION-FINAL-2026-10-16.txt), dictamen
CHANGES_REQUESTED evaluado por el PRIMARY. Resolución documentada en
[EVALUACION-REVISION-FINAL.md](EVALUACION-REVISION-FINAL.md): cierre acotado
implementado y probado; las hipótesis de monto/fecha stock y escala monetaria
se contrastaron con cuerpos nativos, tipos y dos aserciones adicionales.
No se pidió otra consulta para obtener conformidad.

## Límites del gate de realidad

La ejecución general de solo lectura informó 45 ventas de analistas dados de
baja y 273 clientes sin domicilio legal; atribución nativa preservada y problemas
de datos ajenos a TC. `metas_bajo_el_sello` no pudo leer periodos_cerrados y
`conversion_un_solo_nucleo` agotó statement timeout. No se cambiaron permisos.
La comprobación autorizada complementaria confirma agosto como único mes
sellado, metas PEN 7 100 000/USD 0 y cero deudas monetarias; los ensayos locales
comparan once meses de producción nativa y ocho ámbitos reales HTTP. Esto no
convierte el gate general fallido en PASS ni certifica datos documentales.

## Entrega y activación

[ACTIVACION.md](ACTIVACION.md) prepara orden, preflight, worker/secretos, bundle,
cron nuevo, seguimiento, reversa y aviso no enviado. La publicación requiere
el flujo autorizado desde un commit verificado igual a avancecorp/main. Este
worktree contiene cambios ajenos y no se publica ni se limpia automáticamente.

ATR-4 vigente conserva capital al anular: no hay ajuste monetario parcial USD
que implementar por suposición. Si aparece una deuda monetaria sin origen o
meta USD sin equivalente fijo, el preflight/sello rechaza; resolver el dato y
la política antes de activar. Suspender no pausa el cron: un cierre desde
octubre durante suspensión bloquea reactivación automática, preservando historia.

Evidencia local: `/private/tmp/avancecorp-tc-20261016/`, archivos de inventario y
simulación modo 0600. Logs finales: app-check-reanudado.log, typecheck-final.log,
sql-final-review.log, atribucion-review.log, sql-cierre-600-final.log,
http-final-review-repetido.log, deno-final.log, edge-preflight-final.log,
e2e-final-completo.log, e2e-graficas-final.log, e2e-rangos-mixtos.log,
advisors-final-review.log, check-scripts-final-repetido.log y
historico-final-diez.log. No versionar exportaciones productivas ni secretos.

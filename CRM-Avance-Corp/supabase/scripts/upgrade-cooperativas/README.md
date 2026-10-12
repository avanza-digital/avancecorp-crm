# Upgrade cooperativo separado de reinversión

Estado: **SQL y frontend publicados y verificados en producción.** SQL aplicado
el 06/10/2026 (07/10 UTC); verificación final de publicación 07/10 05:02 UTC.
PR #208 fusionado en `62a375f0`; frontend vigente desde Main `3bdfded2c813`.
Decisión de Miguel: «Sí, upgrade y reinversión separados». La primera inversión
sigue bloqueada cuando la persona ya tiene historial en cualquier empresa.

## Comportamiento

- Qorilazo y Prodelco muestran «Registrar upgrade» para una inversión vigente,
  con los mismos permisos de escritura y postventa de la ficha.
- Pide únicamente el aporte adicional, depósito, comprobante y condiciones de
  la nueva inversión. Crea una fuente nueva; conserva íntegra la anterior.
- Persona, empresa, origen y tipo se validan en servidor. La clave no puede
  cambiar de reinversión a upgrade ni adquirir origen después de ser ordinaria.
- El historial distingue «Upgrade confirmado · aporte adicional». Recuperar
  conserva el tipo y la referencia original, incluso desde otro botón.
- Una inversión vencida admite la reinversión existente, pero no este upgrade.
- No cambia las reglas de tasas/atribución de Avance, comisiones ni ranking.
  El nuevo capital se registra por la misma puerta cooperativa existente;
  `es_cierre_inicial` y `es_primera_conversion` son falsos.

## SQL y publicación

Migración: `../../migrations/20261006221545_crm_upgrade_cooperativas.sql`.
Añade `tipo` a `crm.inversion_solicitud_origenes`, con `reinversion` por defecto
para los vínculos anteriores; agrega la RPC `crm.preparar_upgrade_fn` y el
tipo de historial `upgrade`. Mantiene las ACL y la tabla sin escritura directa.
Preflight de cuerpos vivos y del catálogo de historial: rechaza deriva.

Una carrera real descubrió un `55P03` en el candado del lead, antes del trigger
de continuidad. La migración traduce ese conflicto a `PT409` en preparación y
confirmación cooperativa. En la confirmación conserva la guarda que vuelve a
lanzar el error original para solicitudes F4 ordinarias. El parche sustituye
una condición bajo la huella exacta del cuerpo, sin alterar el escritor económico.

Miguel aprobó el SQL exacto de `39f9e0e7`, la rama temporal y la publicación.
La rama se verificó, se integró mediante `merge_branch` y se eliminó después del
postflight productivo. SHA-256 del SQL aplicado:
`1a5caac35c5bbf6c10764dfee97f3f582ad2f2ad22f56e5d0774efd65adf1bbe`.
No reaplicar la migración ni ejecutar `db push` general.

PR #209 ya está integrado y conserva Celular cerrado mientras su SQL/Edge siguen
pendientes; no asumir esa instalación. Gate completo Docker terminado: 369 PASS,
1 caso flaky y 26 omitidos; el caso de gráficas se reprodujo y corrigió en #211,
con repetición aislada PASS sin retries y CI PASS. No afirmar cero retries en
la suite completa. Main con #210: check 6.286/392 y Docker F5 13/13 PASS.

#212 integrado y publicación conjunta realizada por la otra sesión desde Main
limpio `3bdfded2c813`, igual al remoto; conserva la ascendencia del release vivo.
Build `build-20261007T045430720Z`, ZIP SHA-256
`053780737f010276acda83b6d6cf8c035ac4e3f947e179ff820eaf9f593afafd`.
Comprobación independiente HTTPS de 155 archivos PASS, portada/versión exactas
y ZIP no público. UI productiva con Gerencia PASS en Qorilazo y Prodelco:
Upgrade visible/habilitado, Reinversión separada y Nueva inversión deshabilitada.
No se crearon inversiones productivas. Postflight SQL 07/10 05:01 UTC mantiene
las siete huellas y permisos PASS. Evidencia y capturas sin datos personales en
`../../../output/upgrade-cooperativas-20261006/deploy/`. No repetir el deploy.
Estado actualizado: `../../../docs/encargos/2026-10-06-upgrade-cooperativas-RETOMA.md`.

## Verificación remota y productiva

- Rama equivalente sin datos de clientes reales. El replay histórico se detuvo
  en una migración antigua dependiente de datos; se reconstruyó con esquema,
  configuración e historial productivos cotejados. No se declara replay histórico PASS.
- Matriz RLS final: **3.076 aserciones PASS, cero fallos**. Se corrigieron dos
  problemas de fixtures entre corridas: representación de ACL de propietario y
  cuenta bancaria sintética residual. Se repitió el gate íntegro después.
- Casos de llamadas omitidos porque su backend aún no existe; variante de nombre
  canónico sin fixture y canario de meses cerrados sin datos: no acreditados aquí.
- SQL propio: **8 grupos PASS**. Auth, RPC y Storage reales: **PASS** para
  comprobante, confirmación, reintento único, inversión original intacta,
  recuperación, historial separado y permisos negativos. Solo datos sintéticos.
- Postflight productivo: **PASS**, siete huellas de funciones exactas, ACL,
  RLS/default/CHECK correctos; historial previo y 22 Edge Functions intactos.
  Supabase resegmentó el archivo en 22 sentencias al registrar el merge.
- Advisors: seguridad 337→338 por el RPC autenticado SECURITY DEFINER previsto,
  con sesión/rol/persona/empresa/fuente validados y helpers privados INVOKER.
  [Criterio del aviso](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
  Rendimiento 212→212, sin avisos nuevos.
- Rama de pago eliminada y credenciales temporales borradas; producción no
  recibió operaciones financieras de prueba.

Logs y huellas: `../../../output/upgrade-cooperativas-20261006/`.

Reversa: `reversa.sql` toma candado antes de comprobar que no existen upgrades.
Solo restaura el esquema antes del primer upgrade. Con operaciones registradas,
rechaza eliminar su clasificación: revertir únicamente el frontend y conservar
los registros. No borra inversiones, comprobantes ni capital.

## Banco local y pruebas

`banco.mjs` solo acepta el contenedor local
`supabase_db_avancecorp-pr190-20261006` y la base propia
`upgrade_cooperativas_20261006`, sellada con un comentario. La copia procede del
dump local anterior a esta tarea; los seis cuerpos críticos iniciales coinciden
con producción. No admite URL remota.

La plantilla tenía datos de configuración con referencias a autores ausentes y
avisos de ACL/extensiones al restaurar. Los objetos de continuidad y sus ACL
se comprobaron; las pruebas crean operaciones nuevas por las RPC reales. Para
el control global de cobertura, la prueba completa las identidades neutrales
faltantes de antiguos perfiles sintéticos dentro de su transacción; no sustituye
funciones ni cambia contratos. No se afirma paridad de todo el banco ajeno.

```sh
node supabase/scripts/upgrade-cooperativas/banco.mjs aplicar
node supabase/scripts/upgrade-cooperativas/banco.mjs test
node supabase/scripts/upgrade-cooperativas/concurrencia.mjs
node supabase/scripts/upgrade-cooperativas/banco.mjs replay
```

`test` revierte su transacción. `concurrencia` conserva muestras sintéticas en
esta base aislada para usar dos conexiones reales. `replay` elimina sus
clasificaciones de prueba dentro de una transacción, ensaya reversa + migración
exacta + pruebas con otros documentos sintéticos, y hace rollback; verifica que
la huella de las funciones quede intacta. No usar estos fixtures en una rama
con datos reales.

PASS: Qorilazo PEN, Prodelco PEN/USD; preparar/confirmar/reintentar; comprobante
obligatorio; origen íntegro; origen de otra persona del mismo analista rechazado;
empresa distinta rechazada; vendedor/supervisor propio/gerencia permitidos y
vendedor ajeno/supervisor ajeno/directorio rechazados; idempotencia por tipo;
historial de ficha real; origen vencido/anulado; cancelación; ACL; reversa/replay.
PASS con dos sesiones: tipos distintos con la misma clave; doble confirmación;
anulación contra confirmación; negativa de reversa con upgrades registrados.

Se integró `avancecorp/main` (`a0c334ba`) conservando los cambios de llamadas
y cierre de gestiones. Frontend final: `npm run check` PASS (392 archivos,
6.275 pruebas; lint/typecheck/build/bundle). Docker local: `f5-cartera` +
`f6-postventa` + `ficha-cliente-cierre`, 26/26. El SQL final y su reversa
volvieron a pasar el replay. Tipos generados desde la base local; se
incorporaron solo los dos objetos cambiados.
Preflights scripts/seed/RLS/Edge PASS; seed/RLS usan las variables ficticias
offline del workflow. No sustituyen la matriz SQL real descrita arriba.

Los E2E de navegador usan HTTP simulado y las pruebas SQL usan funciones reales
con `SET ROLE authenticated`; son puertas separadas, no un E2E browser→BD real.

## Revisión independiente

LEVEL 3: Claude emitió `CHANGES_REQUESTED`. El PRIMARY corrigió la cancelación,
la referencia del origen al recuperar y la ventana de la reversa; añadió las
pruebas de ficha/historial, aislamiento por persona, roles y carreras reales.
La hipótesis de catálogo cerrado quedó descartada por el lector y su prueba;
la clasificación inicial y el trigger B11 se verificaron sin cambiar métricas.
Se conservó el validador compartido: el banco no sustituye una medición de
rendimiento en producción. No se descartan solicitudes financieras automáticamente
ante un borrador corrupto; la API rechaza intenciones mixtas.

Una segunda consulta acotada a los cambios finales terminó sin un dictamen
válido (salida vacía del wrapper); no se declara `PASS` del reviewer final ni
se repite la consulta para obtenerlo. El cierre técnico del PRIMARY se basa en
los controles ejecutados arriba. La aprobación humana de GitHub y del SQL ya
se obtuvo; los controles remotos están documentados arriba. La publicación del
frontend conserva sus gates pendientes y no se presenta como realizada.

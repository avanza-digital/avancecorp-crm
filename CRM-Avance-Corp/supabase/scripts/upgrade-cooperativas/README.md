# Upgrade cooperativo separado de reinversión

Estado: preparado y probado localmente el 06/10/2026. **No aplicado en producción.**
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

Orden pendiente: aprobación de SQL y PR → rama Supabase con esquema equivalente
→ aplicar solo esta migración, matriz RLS y advisors → integración de backend
→ frontend construido desde main local/remoto idénticos → lectura y botones en
producción. Nunca `db push` general ni `apply_migration` directo al proyecto vivo.
Las comprobaciones remotas de rama/advisors/publicación están **NOT RUN**.

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

Frontend: `npm run check` PASS (386 archivos, 6.217 pruebas); después se agregó
la prueba de render del historial y el subconjunto final pasó 91/91, con lint
final PASS. Docker local: `f5-cartera` + `f6-postventa`, 19/19. Tipos generados
desde la base local; se incorporaron solo los dos objetos cambiados.
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
los controles ejecutados arriba. Falta la aprobación humana de GitHub y del SQL,
y después los controles remotos previos a publicar.

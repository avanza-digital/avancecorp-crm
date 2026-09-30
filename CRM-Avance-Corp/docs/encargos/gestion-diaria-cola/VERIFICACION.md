# Gestión diaria: evidencia local (30/09/2026)

Acta histórica del ensayo local. La validación remota posterior y el estado
de publicación están en [RELEASE.md](RELEASE.md).

| Comprobación | Resultado |
|---|---|
| `npm --prefix app run check` | PASS final: 320 archivos, 4941 tests; lint, tipos, cobertura, release-config, push, build, bundle y duplicación |
| Matriz SQL `ensayar.mjs` | PASS: 530 leads y 10 denegaciones; escritor real v4, reintentos, Lima, deshacer, cierre de vuelta, ámbitos |
| SQL de roles | PASS: supervisor propio, llamada contestada, grupo conservado tras dos intentos y cierre de tarea, metadata no UUID, reasignación autenticada por gerencia, ancla de tarea y clientes por responsable |
| Guardas anteriores | PASS: `assert_cola_v3`, `assert_sla_nucleo` |
| `check:scripts` | PASS; hubo que permitir localhost para el servidor de prueba Typesafe |
| Preflight seed/RLS | PASS offline con destino/credenciales sintéticos; no conectado a producción |
| `test:edge-preflight` | PASS |
| Pruebas dirigidas | PASS: pantalla, hook, contrato HTTP y resultado de llamada; la regresión final del hook acredita aislamiento de lecturas anteriores al guardado y deshacer |
| E2E dirigido previo | PASS: 11 existentes + nueva vuelta; transporte interceptado, no acredita RLS |
| E2E completo | PASS: 289 passed, 26 skipped (315 casos, 11,2 min), Docker local |
| E2E final tras correcciones | PASS: 1/1, teclado con Enter + latencia de 80 ms, reintento de guardado, siguiente entre páginas, persistencia y cierre de vuelta (13,3 s) |
| Revisión RLS independiente | CHANGES_REQUESTED atendido, decisiones abajo |
| Revisión final y a11y | CHANGES_REQUESTED atendido; decisión del PRIMARY y pruebas abajo, sin tercera consulta |
| `git diff --check` | PASS |
| Migración en rama remota / advisors | NOT RUN: pendiente del flujo de publicación; no se presenta el banco local como rama remota |

## Gate de realidad (sólo lectura)

Ejecutado contra producción sin imprimir ni persistir credenciales. Estado real:
2655 leads activos, 18263 actividades, 1455 tareas pendientes y 30 miembros
operativos. Los supuestos de cartera, historial, agenda y equipo sí existen.
Hay un aviso no relacionado: 284 clientes sin domicilio legal. El gate salió
con código 2 por dos mediciones ajenas a la cola: `periodos_cerrados` denegó
lectura y la consulta de conciliación de conversión agotó el tiempo. Se reporta
**FAIL parcial del gate de realidad**, no un PASS global ni un cambio de permisos.

## Decisiones sobre revisión RLS

- P1 aceptado: la cola personal del supervisor usa `accion_atencion` del núcleo
  SLA con ids propios, `global=false`, visibles `[actor]` y el mismo reloj. Se
  probó por RPC autenticada con alta real.
- P2 aceptado: la reasignación se prueba con UPDATE gerencial autenticado,
  triggers/ledger activos y tarea exigible; presencia positiva y sin gestión
  heredada. Un lead recién reasignado sin señal exigible no se fuerza a la cola.
- P2 de reloj descartado con evidencia: el trigger de actividades
  `20260904130000_crm_f2b_b2_veto_persona_mutaciones.sql:1095` sella
  `clock_timestamp()` después del lock. Las llamadas no empatan por `now()` de
  una transacción larga. El desempate por clave sólo estabiliza empates reales.
- P2 de ledger/matriz: entrada documentada en MIGRACIONES; `ensayar.mjs` es la
  matriz específica de esta puerta, complementaria al gate general. Ni anon
  ni service_role reciben EXECUTE en la nueva RPC.
- P3 de grupo aceptado: se reconstruye el grupo original desde la primera
  gestión del día y sus hechos previos, sin una nueva marca de estado.
- P3 de reloj cliente aceptado: el próximo cambio incluye su vencimiento.
- P3 de reloj dividido resuelto: el motor ahora recibe el mismo `p_ahora`.

Las pruebas de 530 leads usan fixture histórico dentro de rollback; llamadas y
reintentos pasan por el escritor real. Las tareas históricas de cliente son
fixtures de lectura por responsable; no se modifican objetos ni filas public.
No se editaron migraciones anteriores ni se sobrescribieron cambios ajenos.

## Decisiones sobre revisión final y accesibilidad

Los dictámenes originales se conservan en [revisión RLS](revision-rls.txt) y
[revisión final](revision-final-a11y.txt); no se presentan como un PASS del
reviewer. Codex resolvió sus observaciones con evidencia nueva:

- P2 foco aceptado: elegir otra fila deja pendiente el relevo del foco hasta que
  llega su consulta. E2E en Docker elige COLA 08 con Enter bajo latencia; el foco
  termina en su nombre y, tras guardar, en COLA 09.
- P2 máscara aceptado con solución distinta: se eliminó la máscara local para
  leads. Una revisión nueva de la consulta nace después del guardado confirmado
  y no admite datos de consultas anteriores. El hook prueba la respuesta tardía
  y un deshacer posterior; la pantalla prueba dos guardados y recargas tardías,
  y que un deshacer desde otra vista permite elegir nuevamente al lead.
- P3 doble lectura corregido: se eliminó el `refetch` del observador anterior
  al guardar; la revisión nueva solicita la cola actual.
- P3 grupo corregido: prevalece el grupo de la primera gestión cuando la fila
  ya está gestionada/programada. SQL con dos llamadas reales y cierre de tarea
  comprueba que permanece en `primera_atencion`.
- P3 UUID corregido: casts protegidos; SQL con metadata histórica defectuosa
  confirma que la cola sigue respondiendo.
- P3 día: la pantalla usa el día confirmado de `useDiaAnalista`; los errores
  de contrato no se reintentan automáticamente. Se conserva el eco de día para
  no mezclar respuestas de días distintos.
- P3 ramas antiguas: se retiró `hayMas` y su enlace para listas truncadas. La
  alternativa sin `trabajo` permanece para carga/error. Al no ocultar leads,
  su rango coincide con los elementos devueltos. El cierre previo de tareas de
  cliente conserva su máscara transitoria; durante esa recarga el rango es el
  de la página del servidor. Esta limitación existente no afecta el avance de
  leads y se mantiene fuera de esta corrección.

El último ensayo completo del banco tardó 2,8 s (incluye varias lecturas,
escrituras y asserts; **no** es la latencia de una RPC individual). Medir la
lectura con volumen y plan de producción en la rama remota forma parte del
flujo de release, junto con advisors y preflight. No se publicaron artefactos.

El gate final conserva cuatro avisos de accesibilidad preexistentes en
`coverflow-carousel.tsx` y el aviso de tamaño del bundle; no hay errores ni
avisos nuevos de este cambio. Las 26 omisiones de E2E se reportan como skipped,
no como aprobadas. El E2E dirigido se repitió después de corregir foco y consultas.

Logs locales de esta sesión: `/private/tmp/gd-check-final.log`,
`/private/tmp/gd-e2e-completo.log`, `/private/tmp/gd-vuelta-e2e.log`,
`/private/tmp/gd-sql-final.log`. La matriz guarda además
`supabase/scripts/gestion-diaria-cola/resultado-local.json` y genera la muestra
de contrato del frontend desde el SQL ejecutado.

Capturas sintéticas revisadas: [última página](ultima-pagina.png) y
[vuelta completada](vuelta-completada.png). Los colores y la estructura de la
pantalla existente se conservan. El progreso aparece como resultado y hora,
texto de pendientes/gestionados/programados y estado final explícito.

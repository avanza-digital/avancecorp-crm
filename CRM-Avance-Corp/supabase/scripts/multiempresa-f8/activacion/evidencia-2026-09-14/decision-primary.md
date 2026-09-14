# F8: decisión del PRIMARY sobre la revisión de activación

Estado: preparación probada; encendido productivo NOT RUN, pendiente de aprobación.
Revisión LEVEL 3. Codex es el único autor; Claude es asesor sin herramientas.

## Primera revisión: CHANGES_REQUESTED

- P2 atribución: aceptado. El generador exige `responsable_id` y referencia
  explícitos. La plantilla verifica Gerencia activa, escribe esa referencia en
  `motivo` y declara a Codex ejecutor administrativo. La propuesta privada enlaza
  referencia, responsables propuestos y SHA256 del SQL, con estado PENDIENTE.
  `auth.uid()` permanece NULL, sin suplantar al responsable ni fingir su firma.
  El solicitante puede aprobar el paquete; no se inventa un requisito de contactar a
  otra persona. La reversa nominal también exige actor operativo y referencia.
- P2 composición entre equipos: no se agrega una restricción de negocio nueva.
  El solicitante eligió cuatro personas. El hecho de que una analista pertenezca a otro
  supervisor describe esta selección, no obliga a que todo piloto futuro tenga
  esa distribución. Sí se validan los cuatro UUID, roles y supervisores exactos
  de la selección capturada, con un test del SQL completo ante un supervisor
  distinto. Se conserva la jerarquía sin reasignar y se prueba el alcance.
- P3 contención: aceptado. La cobertura previa queda fuera de F8; el trigger la
  repite bajo el candado. La comprobación final compara exactamente miembros y
  sus capacidades, sin iterar todo el equipo CRM. Se eliminan `FOR SHARE` sobre
  perfiles, equipo, Auth y flags. F3 compartido se toma antes de F8 exclusivo.
- P3 fallos del texto completo: aceptado. Se documenta `ON_ERROR_STOP=1`, sin
  `-1` ni ejecución por trozos. Los tests ejecutan el archivo completo con error
  de supervisor, responsable incorrecto y repetición: no dejan miembros parciales.
- P3 package.json: el diff solo añade el comando del ensayo y dos `node --check`.
  No cambia dependencias ni scripts de producción; se adjunta al segundo review.

## Hallazgo adicional demostrado por el PRIMARY

La primera versión administrativa tomaba F8 exclusivo y luego `FOR SHARE` de
banderas. Una actualización global toma la fila primero y su trigger espera F8.
En el banco cerrado, dos transacciones terminadas con ROLLBACK reprodujeron:

```text
ERROR: deadlock detected
A mantiene el advisory lock F8 y espera ShareLock de una fila de flags.
B mantiene la fila de flags y espera ExclusiveLock del advisory lock F8.
CONTEXT: private.trg_multiempresa_flags_bloquear_piloto_f8(), línea 15.
```

Se quitaron los bloqueos de fila del nuevo script. Los tests de concurrencia
observan el candado adquirido antes de iniciar el competidor; verifican éxito
sin deadlock frente a bandera global y reversa (ambas transacciones rollback),
y exactamente un éxito ante dos activaciones que intentan hacer COMMIT.
Este hallazgo y su corrección afectan solo al script aún no ejecutado, no a una
migración productiva ni a una interrupción del CRM.

## Verificación actual

PASS: 24 tests (23 subcasos), sintaxis y 43 verificadores offline existentes.
Cinco auditorías de alta, ninguna sesión humana simulada; fechas de siete días,
capacidad para cuatro, ajenos excluidos, jerarquía y siete huellas conservadas.
Reversa nominal verificada e idempotente sobre OFF.

NOT RUN en esta preparación: SQL productivo, sesiones reales Auth/HTTP, suite
RLS general y ensayo remoto adicional. El motor ya instalado tiene evidencia
local/remota previa en las carpetas de F8; no se presenta como una nueva corrida.
No cambian frontend, schema, tipos ni migraciones versionadas.

## Segunda revisión focalizada

Dictamen **PASS**, sin cambios obligatorios. Confianza MEDIUM por hipótesis
sobre otras banderas no incluidas en la evidencia inicial. No se pidió otra
consulta; el PRIMARY cerró las recomendaciones con evidencia:

- Las cuatro banderas globales compiten contra la activación completa. Todos
  los casos pasan; las sesiones competidoras se observan esperando el advisory
  lock exacto de F8 (`granted=false`) antes de resolver la carrera.
- La carrera final ejecuta COMMIT: una activación confirma, otra se rechaza por
  revisión previa y la bandera global por «Apaga F8 antes de activar el rollout
  global». Persisten cuatro miembros, un único control activo y banderas OFF.
- Se probó la rama de rechazo previo por cobertura incoherente con una fuente
  temporal sintética. Se restauran definición y huellas al abortar la transacción.
- Se aclaró que el INSERT conserva los KEY SHARE implícitos de las FK; no se
  afirma ausencia de todo bloqueo de filas. No hay cambio funcional del SQL.
- Conexión productiva comprobada mediante BEGIN READ ONLY / ROLLBACK:
  postgres, auth.uid NULL y READ COMMITTED. La escritura sigue NOT RUN.
- Se sustituye el nombre del solicitante por su rol en esta decisión saneada.

El caso opcional de Gerencia con equipo inactivo no se añade: la consulta ya
exige `p.activo AND e.activo`; el paquete no cambia esas reglas. Sigue vigente
el rechazo seguro ante cualquier cuenta o rol distinto al capturado.

Segunda y última consulta de esta tarea. Los tests finales se repitieron tras
las ampliaciones y pasaron 24; no se atribuyen al reviewer pruebas que no ejecutó.

# F4 — reconstrucción, finanzas y lectura vigente

Continuación del encargo de Miguel: terminar F4 y guardar commits. Codex es
PRIMARY, Claude es reviewer sin herramientas. Desarrollo en
`/private/tmp/avancecorp-f4-desarrollo`, rama `codex/f4-cierre`.

Se construyó un segundo banco Supabase independiente, `avancecorp-f4-reconstruccion`
(API 57321, PG 57322), desde el volcado de solo esquema del 07/09 y fixtures
sintéticas creadas mediante Auth y RPC reales. La candidata completa tiene
48 funciones (18 adaptadas, 30 nuevas), 11 módulos y siete tablas. La paridad
conservó cuatro contratos, dos cierres, 52 cuotas y PEN 8000.

El corpus original F2 pasó diez grupos, incluyendo su siembra y oráculo de
idempotencia originales antes de F4. F4 conserva los resueltos, clasifica los
faltantes/conflictivos y vincula DNI/CE/pasaporte mediante lote acotado. Desde
la instalación, F2 global se rechaza con 55000 incluso si F4 está apagada.

La matriz financiera pasó doce grupos: renovación 0.15, elegibilidad por
cliente/mes, rango parcial, PEN/USD, anulaciones iniciales Avance/cooperativa,
demos, reasignación efectiva de cadena y ambas precedencias sello/confirmación.
No se alteraron Capital, snapshots ni meses sellados. El esquema y el código
no contienen un motor/registro identificado de comisión pagada; se preguntó
a Miguel por su ubicación y sigue pendiente su respuesta. No se inventa una
regla ni se afirma conciliación de pagos.

La revisión de consumidores encontró un defecto: el lead convertido conserva
tenencia histórica después de reasignar la relación, por lo que
`cierres_externos_fn` seguía mostrando teléfono vivo al asesor anterior.
La corrección consulta el responsable canónico para ese dato; la foto del
cierre y su atribución histórica se conservan. Se reprodujo el fallo antes y
pasaron 18 grupos después. El inventario clasifica 26 consumidores directos,
18 escritores, 97 consumidores transitivos y 24 triggers entre 546 funciones.

Se introspectaron los tipos antes/después con el mismo postgres-meta v0.99.0.
Solo se integraron los 17 nodos F4: el dump del 07/09 no contiene algunos RPC
de otras tareas que ya estaban tipados en la rama. Typecheck y build PASS;
3047 tests frontend PASS con dos workers, 42 tests PDF Deno PASS y los cuatro
preflights backend PASS. La primera ejecución frontend a máxima concurrencia
falló por timeouts; no se modificaron tests para conseguir el segundo resultado.

Estado aún abierto: revisión integral Claude, restauración pareada DB/Storage,
regresiones finales y límite de CPU observado en el runtime PDF local. Una
reconstrucción HTTP ya pasó Portal, cooperativas, Avance, documento, fusión,
revisión de responsable y reintentos. Los PDFs PEN/USD nuevos se revisaron en
14 páginas, sin modificar su contenido, pero la tanda de recuperación Deno
se interrumpió por WORKER_LIMIT; no se presenta como PASS completo. El modo
oneshot tampoco eliminó ese fallo. Los contratos interrumpidos conservan sus
reservas/objetos para recuperación, no se editan sus leases ni se borran filas.

G4 continúa abierto hasta resolver/verificar los puntos anteriores. No hubo
publicación ni modificación de banderas productivas. La observación de 14
vínculos resueltos y un faltante productivo sigue siendo la del 07/09 11:32;
no es un recenso actual.

Relacionadas: [[F4 multiempresa - cotitulares y correccion versionada (2026-09-08)]],
[[F4 multiempresa - historicos recuperables y commits (2026-09-08)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

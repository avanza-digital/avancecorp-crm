# Contrato PDF v10 / anexo v2 — publicación del 10/10/2026

**Publicado y verificado en PortalAvanceCorp** (`dctqcbznekcyxhjujuci`).
Commit de producción: `5616d1e834c4c9e28e0fb7caeee2b3eae0a02498`,
[PR #250](https://github.com/avanza-digital/avancecorp-crm/pull/250).
Main local y `avancecorp/main` se comprobaron iguales antes del despliegue.
Los archivos ajenos del árbol de trabajo se conservaron.

Los contratos nuevos usan los correos corregidos de 8.1/14.2 y la firma original
transparente; el anexo muestra la cuenta destino del snapshot sellado, como texto
y conservando sus ceros iniciales. Los PDF históricos no se regeneran.

## Evidencia de la publicación

- Artefacto obtenido con `git archive` desde el commit verificado: 17 archivos
  iguales al candidato ensayado. SHA-256 del TAR:
  `eefd9a043b5d0e6c2afb08b1b69fdbae2f262aefbc797cc9fd4a9b3506dddffc`.
- Edge 28 desplegada explícitamente a las 16:56:46 UTC (11:56:46 Lima), JWT activo.
  SHA del bundle: `a4a340dff251bb3cfa2bc1002a92bcb32fe484d38d09ac9f6b57a5f99fe3088d`.
- Drenaje comprobado: 534 segundos. Las 66 reservas v9 tenían intentos cero,
  ninguna lease ni bytes y ningún objeto en Storage. Los logs posteriores al
  despliegue no mostraron solicitudes atendidas por la versión 27; sí su cierre.
- `merge_branch` solicitado a las 17:06:13 UTC. Terminó correctamente;
  postflight de las 17:07:12 UTC PASS. Historial 462/462, con la candidata
  `20261010154908` una sola vez y las 461 entradas anteriores intactas.
- Default y dos funciones privadas estampan v10. Los cuerpos solo cambian el
  literal; OID, owner, ACL, configuración y atributos permanecen iguales.
  Trigger de inmutabilidad activo (`O`); CHECKs conservan versiones históricas.
- Las 66 reservas pendientes pasaron a v10 sin cambiar sus snapshots. Las
  298 filas de PDF vigentes conservaron todas sus columnas y sus huellas.
  Las 3.107 entradas ACL de funciones/tablas/columnas/secuencias son iguales.
- Se descargaron por HTTP seis PDF de v2/v5/v6/v7/v8/v9: SHA y bytes exactos
  antes y después. La Edge rechaza solicitudes sin autorización con HTTP 401.
- El merge creó Edge 29, bundle
  `6b76ecb125c535d628075ac6d9fcdc941dea53e427beb7382a6d7a0be343a707`.
  Aunque cambió la huella del paquete, sus diez módulos coinciden byte por byte
  con Edge 28 y Main. Las otras 22 funciones conservan sus SHA y configuración JWT.
- Advisors de producción: seguridad 366→366; rendimiento 231→227. Cero avisos
  nuevos; cuatro índices dejaron de figurar como no utilizados.

Antes del despliegue hubo una eliminación auditada ajena a esta tarea a las
16:29:54 UTC: dos PDF v9 pasaron a la auditoría. Las 298 filas vigentes más esas
dos copias reconstruyen exactamente las huellas de las 300 del inventario inicial.
El postflight se contrasta contra el inventario inmediato previo de 298 filas.
El único job v9 bloqueado por integridad ya existía y no se alteró.

## Ensayo y límites

Rama temporal sin datos de clientes: `pdf-v10-correcciones-20261010`,
`vffwlmrhmstlddyhracm`. Catálogo previo: 9/9 huellas y ACL iguales a producción,
461 registros de migraciones con sus arrays SQL exactos. Solo se añadió la candidata.
El replay histórico necesitó fixtures y restauraciones de catálogo documentados;
no se modificaron migraciones originales ni se copiaron filas de clientes.

PASS: ciclo remoto v9→v10→v9→v10; matriz RLS 319 aserciones; HTTP real de emisión
v10/anexo v2/descarga v9/denegaciones; cambiar la cuenta bancaria vigente no cambió
el anexo sellado, su PDF ni la revisión. Advisors remotos sin avisos nuevos.
Suite CRM Node24: 410 archivos y 6.611 tests; checks de GitHub aprobados. Deno
Docker: 94 pruebas; reversa: 91; PostgreSQL aislado: 39; E2E Docker: 4;
14 comparaciones de PDF y 75 páginas revisadas. Detalle en [LEEME.md](LEEME.md).

No se crearon contratos ficticios en producción: emisión autenticada productiva
de prueba **NOT RUN**. La emisión integral se probó en la rama remota; producción
se verificó mediante catálogo, identidad del código, permisos, Storage y HTTP
anónimo. Los E2E Docker simulan el backend y consumen PDF reales.

La revisión de implementación terminó PASS. La revisión operativa emitió
CHANGES_REQUESTED; el PRIMARY cerró sus hallazgos con evidencia del bundle v9,
guardas pre/postclaim, semántica de errores/leases y drenaje con Storage vacío.
La migración no consulta Storage bajo lock: esta comprobación operativa es
obligatoria en cualquier siguiente cambio de plantilla, con evidencia nueva.

## Recuperación y cierre

Reversa SQL: [reversa.sql](reversa.sql). La Edge de reversa probada genera v9/anexo
v1 y sigue leyendo v10. **No desplegar el binario v9 antiguo directamente.**
Resolver primero trabajos v10 en vuelo/con bytes, pausar emisiones, capturar
catálogo/huellas y aplicar la reversa por el carril autorizado. Ninguna reversa
borra documentos sellados ni modifica sus snapshots.

Observación final a las 17:09:29 UTC: PASS, 137 segundos después del primer
postflight, sin reservas antiguas rezagadas ni cambios en los sellados. Logs
posteriores sin errores de la función; el 401 observado corresponde al control
sin autorización.

Rama temporal eliminada a las 17:09 UTC y ausencia confirmada en Supabase. Las
otras dos ramas ajenas se conservaron. Credencial local de la rama retirada.
Uso estimado a la tarifa autorizada: US$0,0129, por debajo del límite de US$1
(estimación de tiempo, no importe de factura). Evidencia saneada:
`output/contrato-correcciones-20261010/evidencia/remota/`.

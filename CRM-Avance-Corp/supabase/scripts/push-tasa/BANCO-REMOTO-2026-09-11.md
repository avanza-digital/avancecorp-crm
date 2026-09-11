# Ensayo gestionado de notificaciones de tasa

SQL y coste autorizados por Miguel. Banco exclusivo `push-tasa-20260911`
(`pdummdtfablfkdgrmauo`), creado el 11/09 a las 16:44 UTC; se elimina al terminar.
El banco F7 queda fuera de este trabajo. Ensayo completado, producción publicada
y banco exclusivo eliminado; [acta de publicación](PUBLICACION-2026-09-11.md).

La inicialización histórica falló. Se reconstruyó este banco vacío con la
estructura y los 273 registros vigentes, sin copiar usuarios ni filas de negocio.
Las funciones, propietarios, ACL, columnas, triggers, policies, índices y vistas
coinciden. Tres CHECK conservan exactamente los mismos operandos unidos por AND,
con paréntesis normalizados por PostgreSQL. El dump omitió comentarios internos
de dos funciones; se recuperaron sus cuerpos exactos antes del ensayo.

Se habilitó el esquema CRM en la API de esta rama y se sembraron 13 cuentas,
siete leads y cinco tareas ficticias. Los crons anteriores quedaron inactivos.
F3 ON; F4/F5/F6 OFF. Cada matriz usa la misma semilla limpia, con las puertas
reales de Auth/API. Las cuentas sin correo que crea la matriz son sintéticas;
la limpieza está restringida a esta rama y al conjunto esperado del banco.

| Comprobación | Estado |
|---|---|
| Matriz anterior a push | FAIL: 50/1.827; 1.777 PASS. Referencia, no fallo atribuido a push |
| SQL de notificaciones | PASS: 48 comprobaciones remotas, todo revertido |
| Firmas y pg_net | PASS: cola real inspeccionada dentro de transacción; rollback impide entrega |
| Historial previo | PASS: 273 entradas y huella de arrays `d119bdcf2cccfc801ad667ce7161624b` intactos |
| Migración nueva | PASS: versión `20260910225540`, SQL exacto aprobado `f85af64f9abe31a753317bb5fde14d2bac9a3f54c319cee4e4654c2f2b2d230f` |
| Advisors | PASS con dos avisos esperados de tablas cerradas; sin otros hallazgos nuevos |
| Matriz posterior | FAIL: 46/1.827; 1.781 PASS. Ninguna aserción nueva fallida |
| Comparación de fallos | PASS por identidad de aserción; comparación literal FAIL por un payload distinto del mismo fallo previo, explicado abajo |
| Concurrencia gestionada | PASS: tres carreras con transacciones PostgreSQL reales |
| HTTP y revocación Auth | PASS: 16 comprobaciones HTTP y tres de baja/revocación |
| Cron gestionado | PASS: cron → pg_net → firma → Edge → proveedor, sin destinatario real |
| Tipos remotos | PASS: dos tablas y ocho RPC iguales por AST a los tipos del frontend |
| Publicación | PASS: migración, Edge, frontend y activación verificados; banco eliminado |
| Recepción en teléfono real | NOT RUN: requiere el permiso y la prueba desde la PWA de Miguel |

El instalador ejecutó el SQL, pero el registro de la rama antigua carecía de la
restricción UNIQUE de idempotencia y devolvió 42P10 al guardar el historial.
Se verificó la instalación completa, se repuso únicamente esa restricción ya
presente en producción y se registró el SQL exacto en la rama. No se repitió el
DDL ni se cambió la migración aprobada. La base productiva ya tiene esa restricción.

El ensayo remoto conserva las 48 aserciones locales. Usa actores ficticios
internos, una guarda de destino exclusiva y la cola real de pg_net; no sustituye
funciones administradas. El secreto cron del fixture se modifica únicamente
dentro del rollback. La prueba inicial encontró esas diferencias de preparación
y se adaptó el banco; no se relajaron las comprobaciones del producto.

Las dos tablas deliberadamente carecen de acceso directo de usuarios: su
[aviso de RLS sin policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
es compatible con las RPC autorizadas y no se resuelve abriendo las tablas.

La comparación conserva ambos resultados globales como FAIL. No apareció una
aserción fallida nueva. La comprobación de dos estados de conversión falla antes
y después porque falta `medible`; su payload pasa de una a dos filas
`solo_referidos`. El fixture escoge el primer candidato sin divisor ni cierres,
sin excluir `vend1` (`test-rls.mjs:10446–10462`), y siembra un referido para cada
uno (`10485–10520`). Antes, la fila candidata acumuló el cierre y los dos referidos
de `vend1`; después fueron sujetos distintos. Esto explica las cuatro deltas que
dejaron de fallar. La prueba y las funciones de conversión no cambiaron. No se
presenta esa variación como una corrección de push. Ambos payloads y la diferencia
literal están conservados en `evidencia/rls-comparacion-20260911.json`.

La solicitud HTTP se creó a las 13:17:28 de Lima por las RPC reales
`crear_lead_si_disponible` y `solicitar_tasa_fn`. El cron de las 13:18 activó
pg_net y obtuvo HTTP 200 del worker: dos procesados, cero pendientes de confirmar.
Los dos endpoints FCM inventados devolvieron 410; ambos dispositivos quedaron
inactivos, con un solo intento, y la solicitud siguió pendiente. No se invocó
manualmente el worker después del alta. La comprobación de baja usa el 204 sin
contenido de su RPC; al revocar Auth, el JWT todavía vigente recibe 403.

Dos ajustes del adaptador no cambiaron el producto: el alta directa del lead
recibió correctamente 42501 y se cambió por la RPC vigente; la RPC de baja devuelve
204, no 200. El ensayo final usa esos contratos reales. Antes del merge se retiran
los secretos VAPID y Vault de prueba de esta rama; se conservan las claves
productivas. El dispositivo real de Miguel aún debe conceder permiso y recibir
su primera prueba.

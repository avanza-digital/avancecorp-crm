# Ensayo gestionado de notificaciones de tasa

SQL y coste autorizados por Miguel. Banco exclusivo `push-tasa-20260911`
(`pdummdtfablfkdgrmauo`), creado el 11/09 a las 16:44 UTC; se elimina al terminar.
El banco F7 queda fuera de este trabajo. Producción aún no se modificó.

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
| Matriz posterior | EN CURSO |
| Concurrencia gestionada y entrega HTTP | PENDIENTE |
| Publicación y recepción en teléfono real | PENDIENTE |

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

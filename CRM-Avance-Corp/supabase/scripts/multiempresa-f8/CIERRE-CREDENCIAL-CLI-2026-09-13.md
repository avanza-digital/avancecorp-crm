# Credencial temporal CLI — retirada tras el ensayo F8

El aviso anterior a Miguel identificó incorrectamente la credencial mostrada
como la contraseña principal de producción. La salida del ensayo correspondía
a `cli_login_postgres`, un acceso temporal generado por la CLI al ejecutar
`db dump --dry-run` sin proporcionar una contraseña de base de datos.

Miguel autorizó retirar la credencial expuesta. Tras corregirle la identificación,
se eliminó exclusivamente ese acceso temporal mediante el endpoint oficial
`DELETE /v1/projects/{ref}/cli/login-role`. No se rotaron la contraseña de
`postgres`, las claves API ni las contraseñas de usuarios.

## Evidencia y verificación

- Proyecto: `dctqcbznekcyxhjujuci`.
- Caducidad observada en `pg_roles`: 13/09/2026 17:52:16 Lima
  (`2026-09-13T22:52:16.013590Z`).
- Justo antes de retirar el acceso, 19:22:30 Lima: contraseña caducada,
  cero conexiones abiertas y cero objetos propiedad del rol.
- Management API devolvió HTTP 200; consulta posterior: rol ausente.
- Verificación independiente a las 19:23:00 Lima: cero roles
  `cli_login_postgres` y cero sesiones con ese usuario.
- Proyecto `ACTIVE_HEALTHY`; consulta administrativa de lectura correcta;
  `/auth/v1/health` devolvió HTTP 200.
- `/rest/v1/` sin sesión de usuario devolvió HTTP 401: se comprobó respuesta
  del servicio, no acceso funcional con un usuario. Flujo completo autenticado:
  **NOT RUN**, no se solicitaron ni cambiaron credenciales de usuarios.
- F3 ON, F4–F7 OFF y F8 no instalada; no cambió ninguna bandera del producto.

El token de administración se obtuvo del almacén existente de la CLI y se usó
en memoria. No se imprimió, guardó en archivos ni pasó en argumentos de procesos.
No se reutilizó ni volvió a mostrar la contraseña expuesta.

## Registros del intervalo

Se consultaron las 17:40–18:00 Lima del 13/09: 81 eventos Postgres disponibles,
desde 17:40:00.015 hasta 17:59:02.926. Hubo un evento de conexión autorizada
para `cli_login_postgres` a las 17:47:16.872, con aplicación `Supavisor`,
coincidente temporalmente con la inicialización de la CLI durante el ensayo.
Ese dato no identifica al cliente final detrás del pooler ni constituye una
auditoría integral de accesos. No se infiere ausencia absoluta de uso indebido.

El endpoint nuevo `logs` devolvió un error de backend con la consulta adaptada
a su tabla unificada. Se usó `logs.all`, todavía vigente hasta el 23/09/2026,
para obtener los datos. Los errores previos no se contaron como consultas
exitosas ni como cero eventos. No se evaluó el límite global de retención;
sí se verificó disponibilidad dentro del intervalo solicitado.

## Revisión independiente y decisiones

Claude revisó esta contención como tarea de seguridad separada del desarrollo
F8 y devolvió `CHANGES_REQUESTED`. Su conclusión técnica respaldó retirar el
rol temporal y conservar las credenciales habituales.

- Se incorporaron la consulta de registros, comprobación previa inmediata,
  verificación posterior y manejo del token exclusivamente en memoria.
- La recomendación de pedir otra autorización se descartó: Miguel ya había
  autorizado retirar la credencial expuesta; el alcance corregido es menor y
  preserva los accesos habituales. Se comunicó la corrección antes de actuar.
- La caducidad se describe como evidencia del catálogo, sin asumir su
  cumplimiento en todas las rutas del pooler. La contención comprobada es la
  eliminación del rol y la ausencia de sesiones.
- Una futura operación CLI puede recrear el rol con una contraseña nueva.
  Ese comportamiento esperado no reactiva la contraseña expuesta.

## Prevención en próximos ensayos

`db dump --dry-run` puede imprimir `PGPASSWORD`; tratar su salida como secreta.
Capturarla únicamente en memoria, mostrar campos permitidos y pasar las
credenciales por variables de entorno del proceso hijo. Evitar `--debug`,
trazas HTTP y listados de procesos que incluyan valores secretos en argumentos.
No copiar las salidas originales a notas, commits ni prompts de revisión.
Las salidas ya entregadas al historial de conversación no se consideran borradas.

Fuentes: [rol temporal y eliminación por API](https://supabase.com/docs/guides/troubleshooting/permission-denied-when-deleting-the-cli_login_postgres-role-808bae),
[cambio de endpoint de registros](https://supabase.com/changelog/48235-migration-of-supabase-management-api-logs-all-analytics-endpoint-to-logs-endpoint).

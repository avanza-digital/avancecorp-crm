# Adaptadores del ensayo remoto

Estos archivos conservan el ejecutor y las comprobaciones HTTP realizadas. Su destino está cerrado al banco autorizado ya eliminado; no aceptan cambiar a producción mediante variables de entorno. Las credenciales y sesiones se leían de archivos privados temporales y no se versionan.

Para SQL se copiaron los scripts versionados `pruebas-locales.mjs`, `seguridad-local.mjs`, `volumen-local.mjs`, `casos-limite.sql` y `REVERSA.sql` a una carpeta temporal. Solo se ajustó la ruta del SQL fuente, se sustituyó el helper de conexión por `banco-remoto.mjs` (con alias de importación `banco-local.mjs`) y se amplió el timeout de los ensayos de seguridad/volumen a 180 s. La migración fue una copia literal del commit aprobado. Todos esos ensayos terminan en ROLLBACK.

Las semillas eran exclusivamente de la copia local `ficha_rapida_20260915`: 15 usuarios ficticios, sin sesiones/refresh tokens de origen. Se importaron public/crm/private, auth.users/auth.identities y buckets/objetos sintéticos. Nunca se copiaron filas de clientes productivos. Se mantuvieron cron OFF y Vault/cola vacíos.

La estructura se reconstruyó desde el catálogo vigente, conservando el objeto public, sus ACL y las políticas externas. Antes del merge se incorporaron las publicaciones concurrentes de correo y Citas. No se reparó el historial productivo; en el banco se copió literalmente el historial padre.

Incidencias del ejecutor resueltas: el banco nacía con replay histórico detenido; el ledger antiguo carecía del índice único de idempotency_key requerido por la API y se igualó al padre tras una reversa exacta; las exenciones/techo de Citas son configuración de código, no fixtures de clientes, y se copiaron del catálogo/configuración vigente. El merge transforma el bloque SQL en nueve sentencias. No se omiten esas diferencias de serialización.

Las llamadas CLI de base de datos al mismo proyecto deben ejecutarse en serie: inicializan la misma cuenta temporal cli_login_postgres. Una ejecución concurrente rotó su contraseña y obligó a repetir la captura final. Esto no modifica las claves de los usuarios del CRM.

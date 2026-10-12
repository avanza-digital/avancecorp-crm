# Conversión: sincronización del correo antes de Auth

Relacionado: [[Inicio]], [[Conversion - correo de acceso reservado antes de Auth (2026-09-25)]].

## Decisión solicitada por Miguel

El correo editado en la ficha debe ser el del primer acceso Avance. Corregirlo desde
el formulario de acceso también debe ser posible antes de crear la cuenta. Una
reserva incompleta no vuelve inmutable el correo. Una cuenta Auth existente se
administra desde gestión de acceso; editar contacto no reasigna sus credenciales.

Aclaración operativa de Miguel (03/10/2026): los analistas suelen recibir el sí del
cliente dentro de «Convertir cliente» y casi no consultan la ficha en ese momento.
El camino principal es editar «Correo de acceso Avance» en esa misma conversión,
revisarlo y continuar; la ficha se sincroniza automáticamente. No deben salir del
formulario, cancelar la solicitud ni editar la ficha como requisito previo.

## Causa y arreglo preparado

La ficha y `inversion_solicitudes.datos.alta_portal` retenían valores distintos.
La RPC bloqueaba cualquier cambio si existía `auth_claim_id`, aunque Auth no existiese.
La migración `20260925170437_crm_correo_acceso_sincronizado.sql` sincroniza ambos
sentidos con revisión y auditoría, preserva claim/token/hash inicial y protege
contra peticiones tardías. GoTrue asigna app_metadata mediante UPDATE después del
INSERT; el guard cubre los dos dentro de la misma transacción.

Solo quien puede editar la ficha por RLS sincroniza su acceso pendiente. Importar
sin actor no crea un actor ficticio y obliga a revisar una diferencia antes de Auth.

## Estado

**ACTIVO Y VERIFICADO EN PRODUCCIÓN el 03/10/2026 a las 11:16 Lima.**
Miguel confirmó «ok vamos con eso entonces» después de revisar el SQL y el flujo
directo de «Convertir cliente». No volver a pedir la misma autorización.
Origen del desarrollo: worktree autorizado `codex/correo-acceso-20260925`.
No confundir con el SQL puntual previamente aprobado/aplicado. La migración general
se activó por merge de la branch, después de completar el ensayo hospedado.
La pantalla publicada ya contiene el flujo compatible; no hizo falta otra publicación frontend.

Gates locales: 22 aserciones SQL, 21 HTTP Auth/PostgREST/Edge y roles, 4.426 tests
de frontend y 13 E2E Docker. Reversión operativa ensayada: vuelve a las RPC previas
pero conserva el guard contra altas tardías; nunca borra cuentas ni datos comerciales.
Detalles reproducibles y límites en `supabase/scripts/correo-acceso/README.md` del CRM.

## Revisión del 03/10/2026

La comprobación inicial del caso real confirmó que el arreglo general seguía sin instalar: faltaban el helper y los triggers, y las seis huellas productivas coincidían con las precondiciones de la migración. La pantalla pública ya incluía la comparación de correos y `acceso_creado` (build `build-20261002T005154879Z`), pero el servidor aún rechazaba corregir una reserva. El caso puntual se recuperó primero sin crear ni modificar cuentas Auth; ver [[Primer acceso Avance - correo de solicitud corregido 2026-10-03]]. Después se activó el arreglo general, como consta abajo.

La branch hospedada `correo-acceso-20260925` se rebasó sobre producción el 03/10:
420 migraciones, incluidas `20260925170437` y `20260925201350`. `check:scripts` y
`test:edge-preflight`: PASS. Los primeros preflights no llegaron a conectar por
falta de variables; después se obtuvieron credenciales privadas de la branch y
se completaron ambos preflights, seed y gate completo, según la activación siguiente.

Miguel encendió Docker y se repitieron las pruebas locales el 03/10:

- SQL `test-correo.sql`: **PASS, 22 aserciones**, incluida corrección de reserva
  activa y sincronización desde la solicitud hacia la ficha.
- `node --test .../correo-acceso/http.test.mjs`: **PASS, 21 pruebas**, con
  GoTrue/PostgREST locales reales, handler Edge actual, carreras y matriz de roles.
- `npm run test:e2e:docker -- e2e/acceso-avance-ux.spec.ts --workers=2`:
  **PASS, 5 pruebas**; incluye corregir el correo dentro del formulario y continuar.

El banco persistente `correo_acceso_20260925` conservaba su base y contenedores;
faltaba únicamente el marcador temporal `creado.txt`. Se verificaron el nombre
de base, las etiquetas/destinos de ambos servicios, los tres triggers del candidato
y cero perfiles no sintéticos antes de ejecutar el SQL transaccional directamente
con `ejecutar()`. No se reconstruyó ni reinició la base. Los E2E usan backend
sintético; estas verificaciones no equivalen al gate hospedado ni a un despliegue.

## Activación autorizada del 03/10/2026

La CLI autenticada permitió recuperar de forma privada las credenciales de la
branch existente. Ambos preflights, seed y RLS, ya pasan con el destino de prueba
real. Se verificó que el SQL local de ambas migraciones coincide con
`avancecorp/main`. Comparación de funciones: 860 en producción y 866 en branch;
únicamente difieren las tres funciones reemplazadas y los seis helpers nuevos
del candidato. Los 22 Edge Functions coinciden en SHA-256 y `verify_jwt`. Los
cinco archivos de `crm-inversion-portal` desplegado coinciden byte a byte con el
handler y dependencias usados en los ensayos locales.

La primera corrida del gate hospedado se interrumpió tras encontrar contaminación
del fixture: una cuenta `BANCO RLS IDEM` del 25/09 y documentos vinculados a
identidades de esa corrida. El reset histórico sólo desactivaba leads, sin retirar
las identidades. Se conservó un respaldo completo validado con `pg_restore --list`
y se reconstruyeron únicamente datos sintéticos de la branch, manteniendo esquema,
permisos, historial de migraciones y configuración. La segunda corrida comienza
con 7 leads, 7 activos, 0 identidades y sin el grant temporal usado por el seed.
No se modificaron aserciones ni funciones para hacer pasar el gate.

Revisión adicional solicitada por `scripts/claude-review`: no produjo dictamen
válido, tampoco al repetir fuera del sandbox; **NOT RUN**, no se registra como PASS.
Se conservan los dos reviews de implementación y su evaluación en `REVISION.md`.

## Resultado de la activación

RLS hospedado completo: **PASS, 2.547 aserciones**, salida 0. Smoke con GoTrue y
PostgREST hospedados y el handler Edge actual: **PASS, tres escenarios** (correo
atrasado sin huérfano, corrección con una sola cuenta y reintento, Auth previo
inmutable con recuperación del perfil). El fixture se adaptó a la RPC vigente de
creación de leads tras el rechazo correcto del INSERT directo; no se cambiaron permisos.

Merge nativo de Supabase terminado en `FUNCTIONS_DEPLOYED`. Producción conserva
las 418 migraciones previas y registra ambas versiones originales: total 420.
Las 866 funciones CRM/private y los 1.100 objetos estructurales comparados son
idénticos a la branch ensayada. Tres triggers habilitados; seis helpers sin EXECUTE
API; índice original listo y válido, duplicado ausente. Las 22 Edge Functions y
el build frontend permanecen iguales. Advisors posteriores sin alertas nuevas.

Con acceso ya creado, el cambio de correo corresponde al administrador del portal:
Clientes → Editar → Correo electrónico, motivo y guardar; conserva la contraseña.
«Gestión de acceso» es una descripción de ese flujo, no un menú independiente.
Acta reproducible: `CRM-Avance-Corp/docs/publicaciones/correo-acceso-2026-10-03.md`.

## Cierre y limpieza del 03/10/2026

Miguel dio por resuelto el problema y pidió cerrar la sesión y borrar los recursos
innecesarios. Eliminados y verificados: branch Supabase `correo-acceso-20260925`,
los dos contenedores Auth/REST y la base sintética local `correo_acceso_20260925`,
y 20 temporales de la sesión (incluidos credenciales, contraseña, dumps y logs).
Los resultados finales permanecen en el acta. Se conservan código, migraciones,
pruebas reproducibles, reversa, memoria de la recuperación puntual y todos los
cambios y recursos de otras tareas. Producción permanece activa; tarea cerrada.

# Correo del primer acceso Avance

## Estado

Corrección preparada en `codex/correo-acceso-20260925`, en un worktree aislado
autorizado por Miguel. **No aplicada en producción ni publicada en el frontend.**
La recuperación puntual anterior de una solicitud no autoriza esta migración general.

SQL: `../../migrations/20260925170437_crm_correo_acceso_sincronizado.sql`.

## Comportamiento

- Antes de crear Auth, guardar un correo válido en la ficha sincroniza todas sus
  solicitudes Avance preparadas, incluso si ya reservaron el acceso.
- Revisar o corregir el primer acceso guarda el correo también en la ficha.
- El permiso procede de la RLS vigente de la ficha. No amplía quién puede editar
  leads ni confirmar inversiones. La auditoría registra el `auth.uid()` real.
- Con cuenta Auth creada, el correo de contacto puede editarse sin reasignar
  credenciales. La corrección de alta informa que debe usarse gestión de acceso.
- Una importación sin actor conserva el contacto pero no inventa auditoría. Si
  difiere del acceso pendiente, no se puede crear Auth hasta revisar el correo.
- Una solicitud anterior con correos distintos muestra ambos y exige elegir.
  Un borrador local distinto muestra el correo actual de la ficha y explica que
  revisar el formulario actualizará la ficha; permite usar su correo actual.
- Una revisión que cambió en otra pestaña se vuelve a mostrar antes de crear Auth.
- Rechazos SQL definitivos mantienen el formulario editable. Solo una respuesta
  incierta conserva el intento de corrección en la pantalla de recuperación.

La respuesta de solicitud agrega `acceso_creado`: permite retomar Auth existente
aunque aún no haya perfil y el contacto haya cambiado. Consumidores anteriores
usaban `v.object`, compatible con el campo adicional; el nuevo frontend lo acepta
como opcional. Orden de publicación: SQL primero, frontend después.

## Concurrencia y seguridad

La corrección y el alta se serializan en solicitud → saga. La corrección conserva
claim, token, identidad y hash original de preparación; incrementa revisión de datos
y versión de saga. No usa el vencimiento del lease como prueba de ausencia de Auth.

GoTrue real inserta primero el usuario y después asigna `raw_app_meta_data` dentro
de la misma transacción. El guard cubre INSERT y la primera asignación de claim por
UPDATE. Rechaza el correo atrasado y revierte toda la creación, incluyendo el INSERT
sin claim. Deja `auth_insertado_id` atómicamente sin cambiar estado ni CAS de saga;
la Edge vigente completa `registrar_auth`, perfil y enlace normalmente.

Solo se aplica a claims de solicitudes de inversión conocidas. Otros registros y
actualizaciones de cuentas conservan su flujo. Ninguna policy ni objeto `public`
cambia. Helpers sin EXECUTE para public/anon/authenticated/service_role, definer
con `search_path=''`. Los grants de las dos RPC se conservan.

El helper invocado desde ficha no adquiere locks de identidad. El sentido contrario
usa `FOR UPDATE NOWAIT` en el lead para evitar una espera circular al elevar el lock
compartido. Los conflictos se recuperan/reintentan con la revisión vigente.

## Banco local reproducible

Requiere el stack sintético `avancecorp-venta-cruzada` ya preparado. El runner
rechaza plantillas con perfiles no sintéticos o demasiados leads. No admite URL de
producción. Crea su propia base `correo_acceso_20260925` y servicios Auth/PostgREST
exclusivos; no modifica la base `postgres` del stack de origen.

El banco histórico tiene actores de auditoría eliminados de sus fixtures: se crean
actores sintéticos inactivos **en la copia** entre data y post-data, y después se
restauran todas las restricciones originales. No se omiten FK del banco final.
Credenciales locales se trasladan internamente; no se imprimen. SMTP sin servicio.

Desde la raíz del repositorio:

```sh
node CRM-Avance-Corp/supabase/scripts/correo-acceso/banco.mjs crear
node CRM-Avance-Corp/supabase/scripts/correo-acceso/banco.mjs aplicar
node CRM-Avance-Corp/supabase/scripts/correo-acceso/banco.mjs test
node CRM-Avance-Corp/supabase/scripts/correo-acceso/banco.mjs http-iniciar
node --test CRM-Avance-Corp/supabase/scripts/correo-acceso/http.test.mjs
node CRM-Avance-Corp/supabase/scripts/correo-acceso/banco.mjs probar-reversion
```

`crear` no reinicia un banco existente. SQL termina con ROLLBACK; HTTP crea datos
sintéticos solo en la base propia. El ensayo de reversión también se deshace.

## Verificación al 25/09/2026

| Gate | Resultado |
|---|---|
| SQL sin arreglo | RED: preparar acceso no actualizaba ficha |
| SQL con migración | PASS: 22 aserciones, incluida compatibilidad Edge anterior |
| HTTP GoTrue/PostgREST + handler Edge actual | PASS: 21 pruebas |
| Matriz de edición de ficha en HTTP | PASS: gerencia, supervisor propio y dueño permitidos; supervisor ajeno, vendedor ajeno/inactivo, directorio y coordinador sin modificaciones según RLS actual |
| Carrera corrección/Auth en ambos órdenes | PASS: correo vigente y una sola cuenta, sin huérfano |
| Respuesta perdida, reintento, revisión concurrente y ficha/corrección | PASS |
| Reversión operativa, restauración de RPC al byte y guard Auth conservado | PASS, ensayo deshecho |
| `npm run check` frontend | PASS: 298 archivos / 4.426 tests, lint, tipos, cobertura, release config, build, bundle y duplicación |
| E2E Docker acceso y contrato | PASS: 13 pruebas, escritorio/móvil; sin avisos de fuentes en corrida final |
| `check:scripts`, `test:edge-preflight` | PASS |
| `seed:preflight`, `test:rls:preflight` | PASS offline, valores sintéticos, sin conexión |
| `gate:realidad` completo | NOT RUN: worktree sin variables de producción. Consulta MCP de lectura confirmó los seis cuerpos base; caso real ya reproducido con reserva antes de Auth |
| `test-rls.mjs` completo en branch y advisors | NOT RUN: pendiente entorno hospedado autorizado |
| Tipos generados | Sin nuevas firmas ni columnas expuestas; JSON añade `acceso_creado` opcional, tipos SQL siguen Json |
| Claude | CHANGES_REQUESTED evaluado: casos reproducidos en rojo y corregidos; ver REVISION.md |

Las pruebas HTTP usan los servicios GoTrue/PostgREST reales, la Edge importada y una
redirección de transporte exclusiva a localhost. Los E2E usan backend sintético;
no se presentan como prueba de producción.

## Aplicación y reversión

1. Mostrar SQL exacto y obtener aprobación según vault. Crear/seleccionar una
   branch de Supabase autorizada; confirmar su costo antes de crear una nueva.
2. Aplicar allí; verificar matriz RLS, advisors, creación Auth y reintentos.
   Cotejar las seis huellas del preflight; si cambiaron, detener y revisar.
3. Integrar el cambio revisado en main y `avancecorp/main`, sin pisar otro trabajo.
   Merge de la migración por el flujo de branch. No `apply_migration` directo a prod.
4. Publicar frontend desde ese commit verificado mediante invocación humana
   `$release-crm` / `/release-crm`. El backend mantiene compatible la Edge actual.
5. Comprobar que una ficha y su solicitud pendiente comparten correo y que no hay
   errores nuevos de Auth. No crear cuentas ni contratos reales como prueba.

`revertir-comportamiento.sql` restaura las dos RPC y el resultado privado anteriores y desactiva ambos
triggers de sincronización. **Conserva el guard Auth y sus helpers/índice**: una
petición remota atrasada todavía debe rechazarse. No revierte correos ya auditados,
no borra cuentas ni solicitudes. Tiene guardas MD5 de los cuerpos candidatos;
si evolucionaron, se debe preparar otra reversión. Su ensayo local fue PASS.

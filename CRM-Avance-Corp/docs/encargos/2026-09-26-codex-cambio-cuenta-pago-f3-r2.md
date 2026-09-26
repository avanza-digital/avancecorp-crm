ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea o fragmento), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo R2 (ÚLTIMA ronda): Cuentas de Gloria · F3 — cambiar la cuenta de pago de contratos por pedido del cliente (LEVEL 3: pagos)

Esta es la segunda y última revisión. Tu trabajo es REFUTAR la versión final: busca fallos reales
(autorización, P04, válvula del candado, carreras con el registro de pagos, idempotencia, Storage,
sello de cuotas, aviso en dos pasos, doble depósito en Pagos, fugas). Sin hallazgo sin evidencia.
No repitas hallazgos de R1 ya resueltos salvo que demuestres que la solución no funciona.

## Decisiones de Miguel (dueño, NO son hallazgos)
- Por contrato entero; solo admin y superadmin; aviso al cliente por portal y correo; respaldo
  obligatorio = el correo del cliente donde pide el cambio (archivo PDF/imagen).
- Todo el que ya ve la cuenta la ve completa (F2b): no se discute el tapado en pantallas internas.
- El PDF firmado del contrato imprime la cuenta de la firma y NO se regenera.

## Contexto verificado (producción y banco Docker con el esquema de producción, PG 17.6)
- `crm.contrato_cuentas_pago`: UNA fila por contrato con su cuenta de pago; hasta hoy inmutable por
  `private.trg_contrato_cuenta_pago_inmutable` (md5 prosrc 349a5a7f…); authenticated sin grants.
- `public.es_admin()` = perfil admin/superadmin con activo = true. P04 (`private.membresia_crm_revocada()`):
  una fila de `crm.equipo` con activo = false para el usuario debe prevalecer sobre poderes del portal.
- Registrar un pago = UPDATE de public.cronograma_pagos a 'pagado' (portal, RLS de gestor de cartera).
  Orden REAL de triggers BEFORE (verificado con pg_get_functiondef en el banco):
  1) `trg_cronograma_pagos_00_documental_congelado` → `private.proteger_cronograma_documental()` →
     `private.bloquear_contratos_hijo_documental` → `private.bloquear_fila_contrato_pdf`:
     `perform 1 from public.contratos c where c.id = p_contrato_id for update;`
  2) `trg_cronograma_pagos_10_exigir_cuenta_pago_*` → `private.exigir_cuenta_pago_cronograma()`:
     `perform 1 from crm.contrato_cuentas_pago cp join public.contratos ct ... join crm.cuentas_bancarias cb ...
      where cp.contrato_id = new.contrato_id and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda
      for share of cp, ct;` → si no hay fila: 23514 «Sin cuenta de pago — requiere conciliación».
  Es decir: el pago bloquea CONTRATO (FOR UPDATE) y DESPUÉS el ENLACE (FOR SHARE).
- Pagos (public_html/js/admin/pagos.js): N° de cuenta y CCI solo aparecen en el Excel «Pagos a
  realizar» (líneas 719-720), y ese Excel solo exporta cuotas NO pagadas de los tramos mora/hoy/semana
  (`cuotasSegunSeleccionExport`, líneas 598-606). La pantalla no imprime la cuenta de cuotas pagadas.
  El Excel se completa DESPUÉS de depositar y se importa para registrar esos pagos. También hay registro
  manual de una cuota con su fecha real (UPDATE con `fecha_pago_real: fecha`).
- En prod: 915 cuotas pagadas, 877 con enlace (38 sin cuenta de pago, pendientes de conciliación).
- Storage: storage.protect_delete impide borrar objetos/buckets por SQL. `anon` NO tiene USAGE sobre
  el esquema private. Columnas de storage.objects: owner uuid, owner_id text, metadata jsonb.
- Guardas de eliminación auditada (contratos y usuarios): fallan cerradas ante cualquier clave foránea
  nueva hacia public.contratos (y descendientes en cascada) o hacia public.perfiles/crm.equipo/auth.users.
- Patrón de puertas: `crm.*` INVOKER que delega en `private.*` DEFINER con EXECUTE a authenticated.
- Edge Functions: tiempo máximo de ejecución 400 s (plan de pago).

## Qué cambió desde R1 y cómo se resolvió cada hallazgo
R1 (BLOCK, 7 hallazgos) — todos aceptados:
1. P1 aviso consumido sin llegar → aviso en DOS pasos: `reclamar` (reserva) + `confirmar` (lo que salió);
   notificado_en solo con todos los canales; «Enviar aviso» reintenta solo lo que faltó.
2. P1 Pagos/Excel atribuirían pagos históricos a la cuenta nueva → con evidencia (ver Contexto) Pagos no
   muestra la cuenta de cuotas pagadas; el riesgo real era un Excel exportado ANTES del cambio e importado
   DESPUÉS: la importación compara el CCI de la fila con la cuenta vigente y NO registra sola esas filas.
   Además, el sello de cada cuota toma la cuenta vigente en la FECHA del pago (ver auditor P2-2).
3. P1 aviso de cuenta superada → `private.contratos_vigentes_de_cambio`: solo se anuncian contratos que
   siguen en la cuenta de ese cambio; si ninguno, `superada` y no se envía. El texto lleva la fecha.
4. P2 id global durante await → la pantalla fija ids al empezar y bloquea reabrir mientras guarda.
5. P2 idempotencia laxa → compara cliente, cuenta, contratos, motivo y respaldo; toda edición = solicitud nueva.
6. P2 texto engañoso → `textoResultadoAviso` solo afirma lo que la Edge confirmó por canal.
7. P3 carga lenta → el formulario solo abre con cuentas y contratos cargados.

Revisión auditor-rls (CHANGES_REQUESTED) — decisiones:
- P1-1 (claves foráneas CASCADE/RESTRICT rompían la eliminación auditada y borraban constancias) →
  ACEPTADO y ampliado: los 3 registros NO tienen ninguna clave foránea (tampoco a perfiles, por la guarda
  de eliminación de usuarios). El postflight falla si aparece alguna. Lecturas: INNER JOIN a contratos y
  cuentas, LEFT JOIN a perfiles.
- P1-2 (P04) → ACEPTADO: `private.admin_banca_vigente(uid)` = admin/superadmin activo Y sin fila de
  crm.equipo con activo=false. La usan núcleo, lecturas, Storage y `reclamar` (para `p_actor`).
- P1-3 (toca public y storage) → requiere OK explícito de Miguel en el ledger (pendiente, antes de aplicar).
- P2-1 (backfill presentado como verdad) → columna `origen` ('registro'|'inferido'); la pantalla muestra
  «N sin constancia: se asume esta cuenta».
- P2-2 (pago tardío atribuido a la cuenta nueva) → ACEPTADO: el sello toma la cuenta_anterior del primer
  cambio cuyo día (Lima) es POSTERIOR a fecha_pago_real; si no, el enlace actual. Mismo día → cuenta nueva.
- P3-1 (orden de bloqueos: pedía enlace FOR UPDATE antes que contratos FOR SHARE) → RECHAZADO con
  evidencia: el pago bloquea contrato (FOR UPDATE, trigger 00) y luego enlace (FOR SHARE, trigger 10);
  el orden sugerido era el inverso y podía causar abrazo mortal. El núcleo toma contratos FOR SHARE y
  después enlaces FOR UPDATE (mismo orden que el pago).
- P3-2 → revoke all también a service_role en las 3 tablas (postflight lo exige).
- P3-3 → BEFORE DELETE que bloquea borrar en las 3 tablas; el sello solo se re-sella.
- P3-4 → el respaldo debe haberlo subido el mismo actor (owner_id/owner) y no puede respaldar otra
  solicitud (candado consultivo por ruta para serializar).
- P3-5 → `reclamar` devuelve titular_distinto/beneficiario_nombre; el aviso dice «a nombre de X».
- P3-6 → `auth.role()='service_role'` en reclamar y confirmar; reserva con TOKEN (confirmar exige el
  token; un token viejo no libera la reserva de otro intento); reserva de 10 min (no 5: la Edge puede
  durar hasta 400 s); `contratos_vigentes_de_cambio` INVOKER; comentarios que justifican cada DEFINER;
  `id` en todas las tablas; fronteras RESTRICTIVE también para anon (sin llamar funciones: anon no
  tiene USAGE sobre private); huella completa de las 16 funciones en reversa y registro.
- Nuevo tras R1 (hallado por mí): el mensaje de la importación decía «vuelve a exportarlo y paga a la
  cuenta nueva» cuando el Excel se importa DESPUÉS de depositar → riesgo de DOBLE DEPÓSITO. Ahora dice
  «No vuelvas a depositar: si ya depositaste con este Excel, registra ese pago a mano con su fecha real;
  si aún no, vuelve a exportarlo», y al cambiar la cuenta se pide a Gloria avisar a Operaciones.

## Riesgos residuales que YO declaro (juzga si están bien acotados)
- Si Operaciones deposita DESPUÉS del cambio usando un Excel viejo (a la cuenta anterior), el sistema no
  puede saber a qué cuenta fue el dinero: la importación rechaza la fila, pero si se registra a mano con
  fecha ≥ día del cambio, el sello dirá la cuenta nueva. Mitigación: aviso a Operaciones al cambiar y
  mensaje de la importación. Registrar la cuenta real del depósito exigiría tocar el registro de pagos
  (fuera de F3).
- Registro de pagos en lote que bloquee varios contratos en otro orden: Postgres detecta el abrazo y
  aborta uno (falla cerrado, se reintenta).
- Dos cambios del MISMO contrato dentro de UNA transacción comparten now(); solo el núcleo escribe
  historial y PostgREST corre una RPC por transacción, así que no ocurre en producción.

## Evidencia de ejecución (banco Docker con el esquema de producción)


### Salida del ciclo completo
```
1. aplicar: OK (postflight: ACL exactas por función, sin claves foráneas, RLS, 7 políticas, 2 triggers de sello, backfill)
2. huella: 16 funciones e60bfdfc928832449b69c8425e633bbe
3. reversa y registro sellados con la huella
4. test: 27 avisos OK · veredicto CAMBIO_CUENTA_OK (13 mutantes cazados)
5. registro ensayado (y revertido)
6. reversa: OK
7. catálogo idéntico tras la reversa (2052 líneas: funciones, políticas incl. storage, tablas, triggers, restricciones, buckets, ACL)
8. backfill ensayado con cuotas pagadas con y sin cuenta (y revertido)
9. catálogo idéntico tras el ensayo del backfill
Portal: node --test tests/*.test.mjs → 153/153 · Edge: deno test 6/6 y deno check OK
```

### Casos del test (avisos emitidos, en orden)
```
OK sello: una cuota que nace pagada guarda su cuenta (registro)
OK permisos: operaciones, analista, cliente y admin revocado (P04) → 42501
OK reglas: respaldo (inexistente, ajeno, ausente, nombre), motivo, cuenta ajena/retirada, contrato cerrado/otra moneda/sin cuenta/inexistente, misma cuenta, repetidos, vacío, nulo y todo-o-nada
OK cambio: K1 y K2 cobran en B; historial con 2 filas (anterior, nueva, quién, motivo, respaldo)
OK idempotencia: el doble clic no duplica; la solicitud con otros contratos, motivo, respaldo o cuenta se rechaza
OK sello: lo pagado antes sigue en A; lo pagado hoy va a B; un pago de ayer registrado hoy va a A; volver a pagar re-sella
OK mutante 4b cazado (sin la regla de la fecha, un pago de ayer iría a la cuenta nueva)
OK candados: el enlace no cambia sin historial; historial y sellos no se reescriben ni se borran
OK lecturas: admin y superadmin ven contratos (cuenta nueva, pendientes, pagadas por cuenta) e historial; operaciones, analista, cliente y admin revocado 42501
OK aviso: solo service_role y para admin vigente; dry_run sin efectos; reserva con token; doble reserva en_curso; sin token no confirma; a medias no sella y guarda el error; reintento solo del canal que faltó con token nuevo; token viejo rechazado; sello final no reescribible
OK aviso superado: no se envía y el historial lo muestra; el vigente anuncia solo sus contratos y el tercero; una reserva vencida cede y su token ya no vale
OK respaldos: el superadmin cambia; un correo ya usado, subido por otro admin o que no es PDF/imagen se rechaza
OK anon: 42501 en cambio, lectura y aviso
OK storage: admin y superadmin suben y leen con nombre válido; nadie sustituye ni borra; operaciones, admin revocado, cliente y anon ni leen ni suben
OK fronteras: con políticas abiertas de otro bucket, anon y operaciones siguen sin leer ni subir y nadie sustituye
OK mutante 1 cazado (sin compuerta, Operaciones cambiaría la cuenta)
OK mutante 1b cazado (sin P04, un admin revocado cambiaría la cuenta)
OK mutante 2 cazado (sin exigir historial, el enlace cambiaría a mano)
OK mutante 3 cazado (sin comprobar el tipo, un texto valdría como respaldo)
OK mutante 3b cazado (sin comprobar quién subió el respaldo, valdría el de otro admin)
OK mutante 3c cazado (sin impedir reutilizar, un correo respaldaría dos cambios)
OK mutante 4 cazado (sin sello, la cuota pagada no guardaría su cuenta)
OK mutante 5 cazado (sellar a medias daría por avisado a quien no recibió el correo)
OK mutante 6 cazado (sin token, cualquier intento confirmaría y liberaría la reserva)
OK mutante 7 cazado (sin exigir service_role, reclamar correría con cualquier sesión)
OK mutante 8 cazado (sin frontera, anon leería respaldos por otra política)
OK mutante 9 cazado (sin frontera, Operaciones leería respaldos por otra política)
```

## Migración (texto íntegro) — CRM-Avance-Corp/supabase/migrations/20260926204051_crm_cambio_cuenta_pago.sql
```sql
-- Cuentas de Gloria · F3.1: cambiar la cuenta de pago de contratos por pedido del cliente.
--
-- Qué hace (servidor; la pantalla es F3.2 y el aviso al cliente F3.3):
--   1. Registros SIN claves foráneas (ver «Diseño»):
--      · crm.cuotas_cuenta_pagada: la cuenta a la que se pagó cada cuota. La sella un trigger al
--        pasar la cuota a 'pagado', con la cuenta vigente en la FECHA DEL PAGO (si después de esa
--        fecha hubo un cambio, la cuenta anterior del primero). Las ya pagadas se sellan con la
--        cuenta contractual actual como 'inferido' (el enlace nació el 25/09 desde el perfil).
--      · crm.contrato_cuenta_pago_cambios: historial inmutable de cambios (solo notificado_en pasa
--        una vez de NULL a fecha).
--      · crm.cambio_cuenta_avisos: estado del aviso al cliente por solicitud.
--      Ninguno se borra.
--   2. El candado del enlace contrato→cuenta admite UN caso: el cambio escrito en el historial en
--      la MISMA transacción (cambiado_en = now()). Todo lo demás sigue inmutable.
--   3. Operación atómica crm.cambiar_cuenta_pago_contratos (puerta INVOKER → núcleo DEFINER):
--      solo admin/superadmin activo y con la membresía CRM NO revocada (P04); por contrato entero;
--      cuenta nueva vigente, del mismo cliente y moneda; contratos del cliente en 'activo'/'vencido'
--      con cuenta de pago; motivo y respaldo obligatorios (el correo del cliente, subido por el
--      mismo admin y no usado en otra solicitud); todo o nada; idempotente comparando TODOS los datos.
--   4. Lecturas para la pantalla, con la misma compuerta.
--   5. Bucket privado 'respaldos-cambio-cuenta' (PDF/JPG/PNG ≤10 MB): solo el admin vigente sube y
--      lee; fronteras RESTRICTIVE: nadie sustituye ni borra, y anon no entra.
--   6. Aviso al cliente en dos pasos (solo service_role, para la Edge notificar-cambio-cuenta):
--      reclamar (reserva de 10 min con token; dice qué canales faltan; no avisa cambios superados;
--      exige que quien lo pide sea admin vigente) y confirmar (con el token: registra lo que salió;
--      notificado_en solo con todos los canales entregados).
--
-- Decisiones de Miguel (26/09/2026): por contrato entero; solo admin y superadmin; aviso por portal
-- y correo; respaldo = el correo del cliente donde pide el cambio. Toca objetos de public (dos
-- triggers AFTER en public.cronograma_pagos; bloqueos FOR SHARE de public.contratos) y de storage
-- (bucket y políticas): requiere el OK explícito de Miguel, anotado en MIGRACIONES.md.
--
-- Diseño — por qué los registros no tienen claves foráneas: son constancias que deben SOBREVIVIR
-- a los contratos, cuotas, clientes, cuentas y personas que nombran. Con CASCADE se borrarían con
-- ellos; con RESTRICT bloquearían las eliminaciones auditadas; y las guardas de esas eliminaciones
-- (crm.contrato_eliminar_auditado y la eliminación de usuarios) fallan cerradas ante cualquier
-- dependencia nueva (revisión auditor-rls, P1-1). Sus únicos escritores —el núcleo, que valida
-- cada id bajo bloqueo, y el trigger del sello, que copia ids de filas reales— garantizan ids
-- válidos al escribir. Las lecturas unen con INNER JOIN a contratos y cuentas (un registro de una
-- fila eliminada no se muestra, pero se conserva) y con LEFT JOIN a perfiles para el nombre.
--
-- Bloqueos: el núcleo toma los contratos (FOR SHARE, por id) y DESPUÉS los enlaces (FOR UPDATE),
-- el mismo orden que el registro de un pago: su trigger 00 (private.proteger_cronograma_documental
-- → private.bloquear_fila_contrato_pdf) bloquea el contrato FOR UPDATE y su trigger 10
-- (private.exigir_cuenta_pago_cronograma) lee el enlace FOR SHARE. Así un pago y un cambio del mismo
-- contrato se ponen en fila en el contrato: sin abrazo mortal, y el pago que esperaba lee el enlace
-- ya cambiado. Riesgo residual: un registro de pagos en lote que bloquee varios contratos en otro
-- orden podría cruzarse con un cambio de esos mismos contratos; Postgres detecta el abrazo y aborta
-- uno de los dos (falla cerrado, sin dato erróneo; basta con reintentarlo).
--
-- Reversión: ../scripts/cuentas-gloria/reversa-cambio-cuenta-pago.sql (se niega si ya hay cambios
-- registrados o si las piezas vivas no son las ensayadas).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = to_regprocedure('private.trg_contrato_cuenta_pago_inmutable()'))
     is distinct from '349a5a7f9a52283c5331aea6d90967f9' then
    raise exception 'CAMBIO_CUENTA: el candado del enlace contrato→cuenta no es el esperado; no se toca';
  end if;
  if to_regclass('crm.contrato_cuentas_pago') is null or to_regclass('crm.cuentas_bancarias') is null
     or to_regclass('crm.equipo') is null or to_regclass('public.perfiles') is null
     or to_regclass('public.contratos') is null or to_regclass('public.cronograma_pagos') is null
     or to_regclass('storage.objects') is null or to_regclass('storage.buckets') is null
     or to_regprocedure('auth.uid()') is null or to_regprocedure('auth.role()') is null
     or to_regprocedure('private.log_audit_crm()') is null then
    raise exception 'CAMBIO_CUENTA: faltan dependencias';
  end if;
  if to_regclass('crm.cuotas_cuenta_pagada') is not null
     or to_regclass('crm.contrato_cuenta_pago_cambios') is not null
     or to_regclass('crm.cambio_cuenta_avisos') is not null then
    raise exception 'CAMBIO_CUENTA: los objetos ya existen; no se sobrescriben';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'CAMBIO_CUENTA: authenticated necesita USAGE sobre private para las puertas INVOKER';
  end if;
  -- El núcleo (DEFINER, dueño = quien aplica) lee storage.objects para validar el respaldo: el
  -- dueño debe poder leerlo sin RLS y esas columnas deben existir con esos tipos.
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false)
     or not pg_catalog.has_table_privilege(current_user, 'storage.objects', 'SELECT') then
    raise exception 'CAMBIO_CUENTA: el dueño de las funciones no puede leer storage.objects sin RLS';
  end if;
  if (select count(*) from pg_catalog.pg_attribute a
      where a.attrelid = 'storage.objects'::regclass and not a.attisdropped
        and (a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod)) in
            (('owner', 'uuid'), ('owner_id', 'text'), ('metadata', 'jsonb'), ('bucket_id', 'text'), ('name', 'text'))) <> 5 then
    raise exception 'CAMBIO_CUENTA: storage.objects no tiene las columnas esperadas';
  end if;
  if (select count(*) from pg_catalog.pg_attribute a
      where a.attrelid = 'crm.cuentas_bancarias'::regclass and not a.attisdropped
        and a.attname in ('cliente_id', 'moneda', 'banco', 'numero_cuenta', 'activa',
                          'titular_distinto', 'beneficiario_nombre')) <> 7 then
    raise exception 'CAMBIO_CUENTA: crm.cuentas_bancarias no tiene las columnas esperadas';
  end if;
end;
$precondicion$;

-- ── 0. Compuerta común: admin o superadmin activo y con la membresía CRM no revocada (P04) ─────
create function private.admin_banca_vigente(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select p_uid is not null
     and exists (
       select 1 from public.perfiles p
       where p.id = p_uid and p.rol in ('admin', 'superadmin') and p.activo is true)
     and not exists (
       select 1 from crm.equipo e
       where e.perfil_id = p_uid and e.activo is false);
$function$;
revoke all on function private.admin_banca_vigente(uuid) from public, anon, authenticated, service_role;
grant execute on function private.admin_banca_vigente(uuid) to authenticated;

-- ── 1. Registros ─────────────────────────────────────────────────────────────────────────────
create table crm.cuotas_cuenta_pagada (
  id                  uuid primary key default gen_random_uuid(),
  cuota_id            uuid not null constraint cuotas_cuenta_pagada_cuota_uq unique,
  contrato_id         uuid not null,
  cuenta_bancaria_id  uuid not null,
  origen              text not null
                      constraint cuotas_cuenta_pagada_origen_valido check (origen in ('registro', 'inferido')),
  sellada_en          timestamptz not null default now()
);
alter table crm.cuotas_cuenta_pagada enable row level security;
revoke all on crm.cuotas_cuenta_pagada from public, anon, authenticated, service_role;
create index cuotas_cuenta_pagada_contrato_idx on crm.cuotas_cuenta_pagada (contrato_id);
create index cuotas_cuenta_pagada_cuenta_idx on crm.cuotas_cuenta_pagada (cuenta_bancaria_id);

create table crm.contrato_cuenta_pago_cambios (
  id                  uuid primary key default gen_random_uuid(),
  solicitud_id        uuid not null,
  contrato_id         uuid not null,
  cliente_id          uuid not null,
  cuenta_anterior_id  uuid not null,
  cuenta_nueva_id     uuid not null,
  motivo              text not null
                      constraint contrato_cuenta_pago_cambios_motivo_valido
                      check (motivo = btrim(motivo) and length(motivo) between 5 and 500),
  respaldo_ruta       text not null
                      constraint contrato_cuenta_pago_cambios_respaldo_valido
                      check (respaldo_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$'),
  cambiado_por        uuid not null,
  cambiado_en         timestamptz not null default now(),
  notificado_en       timestamptz,
  constraint contrato_cuenta_pago_cambios_solicitud_contrato_uq unique (solicitud_id, contrato_id),
  constraint contrato_cuenta_pago_cambios_cuentas_distintas check (cuenta_anterior_id <> cuenta_nueva_id)
);
alter table crm.contrato_cuenta_pago_cambios enable row level security;
revoke all on crm.contrato_cuenta_pago_cambios from public, anon, authenticated, service_role;
create index contrato_cuenta_pago_cambios_contrato_idx on crm.contrato_cuenta_pago_cambios (contrato_id, cambiado_en desc);
create index contrato_cuenta_pago_cambios_cliente_idx on crm.contrato_cuenta_pago_cambios (cliente_id, cambiado_en desc);
create index contrato_cuenta_pago_cambios_respaldo_idx on crm.contrato_cuenta_pago_cambios (respaldo_ruta);

create table crm.cambio_cuenta_avisos (
  id              uuid primary key default gen_random_uuid(),
  solicitud_id    uuid not null constraint cambio_cuenta_avisos_solicitud_uq unique,
  reserva         uuid,
  reclamado_en    timestamptz,
  novedad_en      timestamptz,
  correo_en       timestamptz,
  superada_en     timestamptz,
  intentos        integer not null default 0 constraint cambio_cuenta_avisos_intentos_validos check (intentos >= 0),
  ultimo_error    text constraint cambio_cuenta_avisos_error_corto check (ultimo_error is null or length(ultimo_error) <= 500),
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);
alter table crm.cambio_cuenta_avisos enable row level security;
revoke all on crm.cambio_cuenta_avisos from public, anon, authenticated, service_role;

-- Candados de los registros: nada se borra; el historial solo sella el aviso; el sello solo se
-- re-sella (una cuota que vuelve a pagarse tras una anulación).
create function private.trg_registro_cuenta_pago_no_borrar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using errcode = '22023',
    message = 'Los registros de cuentas de pago no se borran';
end;
$function$;
revoke all on function private.trg_registro_cuenta_pago_no_borrar() from public, anon, authenticated, service_role;
create trigger trg_cuotas_cuenta_pagada_00_no_borrar before delete on crm.cuotas_cuenta_pagada
  for each row execute function private.trg_registro_cuenta_pago_no_borrar();
create trigger trg_contrato_cuenta_pago_cambios_00_no_borrar before delete on crm.contrato_cuenta_pago_cambios
  for each row execute function private.trg_registro_cuenta_pago_no_borrar();
create trigger trg_cambio_cuenta_avisos_00_no_borrar before delete on crm.cambio_cuenta_avisos
  for each row execute function private.trg_registro_cuenta_pago_no_borrar();

create function private.trg_contrato_cuenta_pago_cambios_inmutable()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- Solo el sello del aviso, una vez: NULL → fecha. El resto es historia.
  if row(new.id, new.solicitud_id, new.contrato_id, new.cliente_id, new.cuenta_anterior_id,
         new.cuenta_nueva_id, new.motivo, new.respaldo_ruta, new.cambiado_por, new.cambiado_en)
     is distinct from
     row(old.id, old.solicitud_id, old.contrato_id, old.cliente_id, old.cuenta_anterior_id,
         old.cuenta_nueva_id, old.motivo, old.respaldo_ruta, old.cambiado_por, old.cambiado_en)
     or (old.notificado_en is not null and new.notificado_en is distinct from old.notificado_en) then
    raise exception using errcode = '22023',
      message = 'El historial de cambios de cuenta de pago no se modifica';
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_contrato_cuenta_pago_cambios_inmutable() from public, anon, authenticated, service_role;
create trigger trg_contrato_cuenta_pago_cambios_00_inmutable
  before update on crm.contrato_cuenta_pago_cambios
  for each row execute function private.trg_contrato_cuenta_pago_cambios_inmutable();

create function private.trg_cuotas_cuenta_pagada_solo_resello()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.id is distinct from old.id or new.cuota_id is distinct from old.cuota_id then
    raise exception using errcode = '22023', message = 'El sello de una cuota solo se re-sella';
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_cuotas_cuenta_pagada_solo_resello() from public, anon, authenticated, service_role;
create trigger trg_cuotas_cuenta_pagada_00_solo_resello
  before update on crm.cuotas_cuenta_pagada
  for each row execute function private.trg_cuotas_cuenta_pagada_solo_resello();

-- ── 2. Sello de la cuenta en cada cuota pagada ─────────────────────────────────────────────
create function private.sellar_cuenta_cuota_pagada()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_cuenta uuid;
begin
  -- La cuenta vigente en la FECHA del pago: si después de esa fecha (día de Lima) hubo un cambio,
  -- la cuenta anterior del primero; si no, la cuenta contractual actual. Así, registrar tarde (o
  -- volver a registrar tras anular) un pago viejo no lo atribuye a la cuenta nueva. Un pago con
  -- fecha del mismo día del cambio va a la cuenta nueva: el Excel de Pagos exportado antes del
  -- cambio ya no se puede importar.
  if new.fecha_pago_real is not null then
    select c.cuenta_anterior_id into v_cuenta
    from crm.contrato_cuenta_pago_cambios c
    where c.contrato_id = new.contrato_id
      and (c.cambiado_en at time zone 'America/Lima')::date > new.fecha_pago_real
    order by c.cambiado_en asc, c.id asc
    limit 1;
  end if;
  if v_cuenta is null then
    select l.cuenta_bancaria_id into v_cuenta
    from crm.contrato_cuentas_pago l
    where l.contrato_id = new.contrato_id;
  end if;
  -- Sin cuenta: el trigger BEFORE de exigencia ya rechazó el pago; nada que sellar.
  if v_cuenta is null then
    return null;
  end if;
  insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
  values (new.id, new.contrato_id, v_cuenta, 'registro')
  on conflict (cuota_id) do update
    set contrato_id = excluded.contrato_id,
        cuenta_bancaria_id = excluded.cuenta_bancaria_id,
        origen = 'registro',
        sellada_en = pg_catalog.now();
  return null;
end;
$function$;
revoke all on function private.sellar_cuenta_cuota_pagada() from public, anon, authenticated, service_role;

create trigger trg_cronograma_pagos_20_sellar_cuenta_insert
  after insert on public.cronograma_pagos
  for each row when (new.estado = 'pagado')
  execute function private.sellar_cuenta_cuota_pagada();
create trigger trg_cronograma_pagos_20_sellar_cuenta_update
  after update of estado on public.cronograma_pagos
  for each row when (new.estado = 'pagado' and old.estado is distinct from 'pagado')
  execute function private.sellar_cuenta_cuota_pagada();

-- Backfill 'inferido': el enlace nació el 25/09 (P-0XX) desde la cuenta del perfil; es la mejor
-- inferencia de dónde se pagaron las cuotas anteriores, y la pantalla la muestra como tal.
insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
select cp.id, cp.contrato_id, l.cuenta_bancaria_id, 'inferido'
from public.cronograma_pagos cp
join crm.contrato_cuentas_pago l on l.contrato_id = cp.contrato_id
where cp.estado = 'pagado';

create trigger trg_audit_cuotas_cuenta_pagada
  after insert or delete or update on crm.cuotas_cuenta_pagada
  for each row execute function private.log_audit_crm();
create trigger trg_audit_contrato_cuenta_pago_cambios
  after insert or delete or update on crm.contrato_cuenta_pago_cambios
  for each row execute function private.log_audit_crm();
create trigger trg_audit_cambio_cuenta_avisos
  after insert or delete or update on crm.cambio_cuenta_avisos
  for each row execute function private.log_audit_crm();

-- ── 3. Candado del enlace: admite SOLO el cambio registrado en esta transacción ─────────────
create or replace function private.trg_contrato_cuenta_pago_inmutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if row(new.id, new.contrato_id, new.creado_en)
     is distinct from
     row(old.id, old.contrato_id, old.creado_en) then
    raise exception using
      errcode = '22023',
      message = 'La cuenta de pago del contrato es historica y no se reemplaza';
  end if;
  -- La cuenta solo cambia si el mismo cambio quedó escrito en el historial dentro de ESTA
  -- transacción (cambiado_en = now() de la transacción). Solo el núcleo del cambio escribe ese
  -- historial.
  if new.cuenta_bancaria_id is distinct from old.cuenta_bancaria_id
     and not exists (
       select 1 from crm.contrato_cuenta_pago_cambios c
       where c.contrato_id = new.contrato_id
         and c.cuenta_anterior_id = old.cuenta_bancaria_id
         and c.cuenta_nueva_id = new.cuenta_bancaria_id
         and c.cambiado_en = pg_catalog.now()
     ) then
    raise exception using
      errcode = '22023',
      message = 'La cuenta de pago del contrato solo cambia con un cambio registrado';
  end if;
  if new.creado_por is distinct from old.creado_por
     and not (
       new.creado_por is null
       and old.creado_por is not null
       and not exists (select 1 from public.perfiles p where p.id = old.creado_por)
     ) then
    raise exception using errcode = '22023', message = 'La autoria del enlace bancario es inmutable';
  end if;
  return new;
end;
$$;

-- ── 4. Respaldo: bucket privado, solo el admin vigente sube y lee; nadie sustituye ni borra ─
-- Tolera el bucket si ya existe (una reversa no puede borrarlo: storage.protect_delete), pero
-- exige su configuración privada exacta.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('respaldos-cambio-cuenta', 'respaldos-cambio-cuenta', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png']::text[])
on conflict (id) do nothing;
do $bucket_privado$
begin
  if not exists (
    select 1 from storage.buckets b
    where b.id = 'respaldos-cambio-cuenta' and b.name = 'respaldos-cambio-cuenta'
      and b.public is false and b.file_size_limit = 10485760
      and b.allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png']::text[]
  ) then
    raise exception 'CAMBIO_CUENTA: el bucket respaldos-cambio-cuenta no tiene la configuración privada esperada';
  end if;
end;
$bucket_privado$;

create function private.respaldo_cambio_cuenta_permitido(p_nombre text)
returns boolean
language sql
stable
security invoker
set search_path to ''
as $function$
  select coalesce(private.admin_banca_vigente((select auth.uid())), false)
     and coalesce(p_nombre ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false);
$function$;
revoke all on function private.respaldo_cambio_cuenta_permitido(text) from public, anon, authenticated, service_role;
grant execute on function private.respaldo_cambio_cuenta_permitido(text) to authenticated;

create policy respaldo_cambio_cuenta_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'respaldos-cambio-cuenta' and private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_select on storage.objects for select to authenticated
  using (bucket_id = 'respaldos-cambio-cuenta' and private.respaldo_cambio_cuenta_permitido(name));
-- Fronteras RESTRICTIVE (patrón de f4-comprobantes): ninguna política permisiva de otro bucket
-- abre estos respaldos ni permite sustituir o borrar sus bytes. La de anon no llama funciones
-- (anon no tiene USAGE sobre private): simplemente lo deja fuera del bucket.
create policy respaldo_cambio_cuenta_insert_frontera on storage.objects as restrictive for insert to authenticated
  with check (bucket_id is distinct from 'respaldos-cambio-cuenta' or private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_select_frontera on storage.objects as restrictive for select to authenticated
  using (bucket_id is distinct from 'respaldos-cambio-cuenta' or private.respaldo_cambio_cuenta_permitido(name));
create policy respaldo_cambio_cuenta_update_frontera on storage.objects as restrictive for update to authenticated
  using (bucket_id is distinct from 'respaldos-cambio-cuenta')
  with check (bucket_id is distinct from 'respaldos-cambio-cuenta');
create policy respaldo_cambio_cuenta_delete_frontera on storage.objects as restrictive for delete to authenticated
  using (bucket_id is distinct from 'respaldos-cambio-cuenta');
create policy respaldo_cambio_cuenta_anon_frontera on storage.objects as restrictive for all to anon
  using (bucket_id is distinct from 'respaldos-cambio-cuenta')
  with check (bucket_id is distinct from 'respaldos-cambio-cuenta');

-- ── 5. Operación: cambiar la cuenta de pago (núcleo DEFINER + puerta INVOKER) ───────────────
create function private.cambiar_cuenta_pago_contratos_autorizado(
  p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_nueva_id uuid,
  p_contrato_ids uuid[], p_motivo text, p_respaldo_ruta text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_ids uuid[];
  v_motivo text := pg_catalog.btrim(coalesce(p_motivo, ''));
  v_previos integer;
  v_igual boolean;
  v_prev_ids uuid[];
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_obj storage.objects%rowtype;
  v_ct record;
  v_contados integer := 0;
  v_hechos integer;
begin
  if not coalesce(private.admin_banca_vigente(v_actor), false) then
    raise exception using errcode = '42501',
      message = 'Solo administración puede cambiar la cuenta de pago';
  end if;
  if p_solicitud_id is null or p_cliente_id is null or p_cuenta_nueva_id is null then
    raise exception using errcode = '22023', message = 'Faltan datos del cambio';
  end if;
  v_ids := array(select distinct x from pg_catalog.unnest(p_contrato_ids) x where x is not null order by x);
  if coalesce(pg_catalog.cardinality(v_ids), 0) = 0
     or pg_catalog.cardinality(v_ids) <> coalesce(pg_catalog.cardinality(p_contrato_ids), 0)
     or pg_catalog.cardinality(v_ids) > 100 then
    raise exception using errcode = '22023', message = 'Elige entre 1 y 100 contratos, sin repetir';
  end if;
  if pg_catalog.length(v_motivo) not between 5 and 500 then
    raise exception using errcode = '22023', message = 'Escribe el motivo del cambio (5 a 500 caracteres)';
  end if;

  -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con datos
  -- distintos (cuenta, contratos, motivo o respaldo) se rechaza.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cambio-cuenta:' || p_solicitud_id::text, 0));
  select count(*),
         bool_and(c.cliente_id = p_cliente_id and c.cuenta_nueva_id = p_cuenta_nueva_id
                  and c.motivo = v_motivo and c.respaldo_ruta = p_respaldo_ruta),
         array_agg(c.contrato_id order by c.contrato_id)
    into v_previos, v_igual, v_prev_ids
  from crm.contrato_cuenta_pago_cambios c
  where c.solicitud_id = p_solicitud_id;
  if v_previos > 0 then
    if v_igual and v_prev_ids = v_ids then
      return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true,
        'contratos', v_previos);
    end if;
    raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  end if;

  -- Respaldo: el correo del cliente, en su carpeta, subido por este mismo admin y sin usar en otra
  -- solicitud (el segundo candado serializa dos solicitudes que intenten el mismo archivo).
  if p_respaldo_ruta is null
     or pg_catalog.split_part(p_respaldo_ruta, '/', 1) is distinct from p_cliente_id::text
     or not coalesce(p_respaldo_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false) then
    raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('respaldo-cambio-cuenta:' || p_respaldo_ruta, 0));
  select * into v_obj from storage.objects
  where bucket_id = 'respaldos-cambio-cuenta' and name = p_respaldo_ruta;
  if not found
     or coalesce((v_obj.metadata->>'size')::bigint, 0) not between 1 and 10485760
     or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
    raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  end if;
  if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then
    raise exception using errcode = '22023', message = 'El respaldo debe subirlo quien hace el cambio';
  end if;
  if exists (select 1 from crm.contrato_cuenta_pago_cambios c
             where c.respaldo_ruta = p_respaldo_ruta and c.solicitud_id <> p_solicitud_id) then
    raise exception using errcode = '22023', message = 'Ese correo ya respalda otro cambio registrado; revisa el historial o adjunta el correo de esta solicitud';
  end if;

  -- Cuenta nueva: del cliente y vigente.
  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_nueva_id for share;
  if not found or v_cuenta.cliente_id is distinct from p_cliente_id then
    raise exception using errcode = '22023', message = 'La cuenta nueva no es de este cliente';
  end if;
  if not v_cuenta.activa then
    raise exception using errcode = '22023', message = 'La cuenta nueva ya no está vigente';
  end if;

  -- Contratos (se bloquean antes que los enlaces, como al registrar un pago): del cliente,
  -- abiertos y en la moneda de la cuenta.
  for v_ct in
    select ct.id, ct.cliente_id, ct.moneda, ct.estado, ct.numero_contrato
    from public.contratos ct
    where ct.id = any(v_ids)
    order by ct.id
    for share
  loop
    if v_ct.cliente_id is distinct from p_cliente_id then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s no es de este cliente', v_ct.numero_contrato);
    end if;
    if v_ct.estado not in ('activo', 'vencido') then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s está cerrado (%s)', v_ct.numero_contrato, v_ct.estado);
    end if;
    if v_ct.moneda is distinct from v_cuenta.moneda then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s es en %s y la cuenta nueva en %s',
          v_ct.numero_contrato, v_ct.moneda, v_cuenta.moneda);
    end if;
    v_contados := v_contados + 1;
  end loop;
  if v_contados <> pg_catalog.cardinality(v_ids) then
    raise exception using errcode = '22023', message = 'Algún contrato no existe';
  end if;
  perform 1 from crm.contrato_cuentas_pago l where l.contrato_id = any(v_ids) order by l.contrato_id for update;

  -- Enlaces actuales: cada contrato debe tener cuenta de pago y no ser ya la nueva.
  for v_ct in
    select ct.numero_contrato, l.cuenta_bancaria_id
    from public.contratos ct
    left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
    where ct.id = any(v_ids)
    order by ct.id
  loop
    if v_ct.cuenta_bancaria_id is null then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s no tiene cuenta de pago; requiere conciliación', v_ct.numero_contrato);
    end if;
    if v_ct.cuenta_bancaria_id = p_cuenta_nueva_id then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s ya cobra en esa cuenta', v_ct.numero_contrato);
    end if;
  end loop;

  -- Primero la historia; luego el enlace (el candado exige esa historia en esta transacción).
  insert into crm.contrato_cuenta_pago_cambios
    (solicitud_id, contrato_id, cliente_id, cuenta_anterior_id, cuenta_nueva_id,
     motivo, respaldo_ruta, cambiado_por)
  select p_solicitud_id, l.contrato_id, p_cliente_id, l.cuenta_bancaria_id, p_cuenta_nueva_id,
         v_motivo, p_respaldo_ruta, v_actor
  from crm.contrato_cuentas_pago l
  where l.contrato_id = any(v_ids);

  update crm.contrato_cuentas_pago
     set cuenta_bancaria_id = p_cuenta_nueva_id
   where contrato_id = any(v_ids);
  get diagnostics v_hechos = row_count;
  if v_hechos <> pg_catalog.cardinality(v_ids) then
    raise exception 'CAMBIO_CUENTA: se esperaban % enlaces y se cambiaron %', pg_catalog.cardinality(v_ids), v_hechos;
  end if;

  return pg_catalog.jsonb_build_object(
    'solicitud_id', p_solicitud_id, 'ya_aplicada', false, 'contratos', v_hechos,
    'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda);
end;
$function$;
revoke all on function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)
  from public, anon, authenticated, service_role;
grant execute on function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)
  to authenticated;

create function crm.cambiar_cuenta_pago_contratos(
  p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_nueva_id uuid,
  p_contrato_ids uuid[], p_motivo text, p_respaldo_ruta text)
returns jsonb
language sql
volatile security invoker
set search_path to ''
as $function$
  select private.cambiar_cuenta_pago_contratos_autorizado(
    p_solicitud_id, p_cliente_id, p_cuenta_nueva_id, p_contrato_ids, p_motivo, p_respaldo_ruta);
$function$;
revoke all on function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)
  to authenticated;

-- ── 6. Lecturas para la pantalla (misma compuerta) ──────────────────────────────────────────
create function private.contratos_cuenta_pago_cliente_autorizado(p_cliente_id uuid)
returns table (
  contrato_id uuid, numero_contrato text, moneda text, estado text,
  cuenta_bancaria_id uuid, banco text, tipo_cuenta text, numero_cuenta text, cci text,
  cuotas_pendientes bigint, proxima_fecha date, pagadas_por_cuenta jsonb
)
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if not coalesce(private.admin_banca_vigente((select auth.uid())), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede ver las cuentas de pago';
  end if;
  return query
  select ct.id, ct.numero_contrato, ct.moneda, ct.estado,
         l.cuenta_bancaria_id, cb.banco, cb.tipo_cuenta, cb.numero_cuenta, cb.cci,
         (select count(*) from public.cronograma_pagos cp
           where cp.contrato_id = ct.id and cp.estado in ('pendiente', 'vencido')),
         (select min(cp.fecha_programada) from public.cronograma_pagos cp
           where cp.contrato_id = ct.id and cp.estado in ('pendiente', 'vencido')),
         coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'cuenta_bancaria_id', s.cuenta_bancaria_id, 'banco', sb.banco,
                    'numero_cuenta', sb.numero_cuenta, 'cuotas', s.n, 'inferidas', s.inferidas)
                  order by s.n desc)
           from (select q.cuenta_bancaria_id, count(*) as n,
                        count(*) filter (where q.origen = 'inferido') as inferidas
                 from crm.cuotas_cuenta_pagada q
                 join public.cronograma_pagos cp on cp.id = q.cuota_id and cp.estado = 'pagado'
                 where q.contrato_id = ct.id
                 group by q.cuenta_bancaria_id) s
           join crm.cuentas_bancarias sb on sb.id = s.cuenta_bancaria_id), '[]'::jsonb)
  from public.contratos ct
  left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  where ct.cliente_id = p_cliente_id
    and ct.estado in ('activo', 'vencido')
  order by ct.moneda, ct.numero_contrato;
end;
$function$;
revoke all on function private.contratos_cuenta_pago_cliente_autorizado(uuid) from public, anon, authenticated, service_role;
grant execute on function private.contratos_cuenta_pago_cliente_autorizado(uuid) to authenticated;

create function crm.contratos_cuenta_pago_cliente_fn(p_cliente_id uuid)
returns table (
  contrato_id uuid, numero_contrato text, moneda text, estado text,
  cuenta_bancaria_id uuid, banco text, tipo_cuenta text, numero_cuenta text, cci text,
  cuotas_pendientes bigint, proxima_fecha date, pagadas_por_cuenta jsonb
)
language sql
stable security invoker
set search_path to ''
as $function$
  select * from private.contratos_cuenta_pago_cliente_autorizado(p_cliente_id);
$function$;
revoke all on function crm.contratos_cuenta_pago_cliente_fn(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.contratos_cuenta_pago_cliente_fn(uuid) to authenticated;

create function private.cambios_cuenta_pago_cliente_autorizado(p_cliente_id uuid)
returns table (
  cambio_id uuid, solicitud_id uuid, cambiado_en timestamptz, numero_contrato text,
  banco_anterior text, numero_anterior text, banco_nuevo text, numero_nuevo text,
  motivo text, respaldo_ruta text, cambiado_por_nombre text, notificado_en timestamptz,
  aviso_estado text, aviso_error text
)
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if not coalesce(private.admin_banca_vigente((select auth.uid())), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede ver el historial de cuentas de pago';
  end if;
  return query
  select c.id, c.solicitud_id, c.cambiado_en, ct.numero_contrato,
         a.banco, a.numero_cuenta, n.banco, n.numero_cuenta,
         c.motivo, c.respaldo_ruta, pr.nombre_completo, c.notificado_en,
         case when c.notificado_en is not null then 'enviado'
              when av.superada_en is not null then 'superado'
              else 'pendiente' end,
         av.ultimo_error
  from crm.contrato_cuenta_pago_cambios c
  join public.contratos ct on ct.id = c.contrato_id
  join crm.cuentas_bancarias a on a.id = c.cuenta_anterior_id
  join crm.cuentas_bancarias n on n.id = c.cuenta_nueva_id
  left join public.perfiles pr on pr.id = c.cambiado_por and pr.rol <> 'cliente'
  left join crm.cambio_cuenta_avisos av on av.solicitud_id = c.solicitud_id
  where c.cliente_id = p_cliente_id
  order by c.cambiado_en desc, ct.numero_contrato;
end;
$function$;
revoke all on function private.cambios_cuenta_pago_cliente_autorizado(uuid) from public, anon, authenticated, service_role;
grant execute on function private.cambios_cuenta_pago_cliente_autorizado(uuid) to authenticated;

create function crm.cambios_cuenta_pago_cliente_fn(p_cliente_id uuid)
returns table (
  cambio_id uuid, solicitud_id uuid, cambiado_en timestamptz, numero_contrato text,
  banco_anterior text, numero_anterior text, banco_nuevo text, numero_nuevo text,
  motivo text, respaldo_ruta text, cambiado_por_nombre text, notificado_en timestamptz,
  aviso_estado text, aviso_error text
)
language sql
stable security invoker
set search_path to ''
as $function$
  select * from private.cambios_cuenta_pago_cliente_autorizado(p_cliente_id);
$function$;
revoke all on function crm.cambios_cuenta_pago_cliente_fn(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.cambios_cuenta_pago_cliente_fn(uuid) to authenticated;

-- ── 7. Aviso al cliente en dos pasos (solo service_role, para la Edge Function) ─────────────
-- Contratos de la solicitud que SIGUEN cobrando en la cuenta de ese cambio (sin un cambio
-- posterior). Solo esos se anuncian: un aviso atrasado nunca presenta una cuenta superada.
-- INVOKER: solo la llama crm.reclamar_aviso_cambio_cuenta, que ya corre como su dueño.
create function private.contratos_vigentes_de_cambio(p_solicitud_id uuid)
returns text[]
language sql
stable
security invoker
set search_path to ''
as $function$
  select coalesce(array_agg(ct.numero_contrato order by ct.numero_contrato), '{}'::text[])
  from crm.contrato_cuenta_pago_cambios c
  join public.contratos ct on ct.id = c.contrato_id
  join crm.contrato_cuentas_pago l on l.contrato_id = c.contrato_id
  where c.solicitud_id = p_solicitud_id
    and l.cuenta_bancaria_id = c.cuenta_nueva_id
    and not exists (
      select 1 from crm.contrato_cuenta_pago_cambios c2
      where c2.contrato_id = c.contrato_id and c2.cambiado_en > c.cambiado_en);
$function$;
revoke all on function private.contratos_vigentes_de_cambio(uuid) from public, anon, authenticated, service_role;

create function crm.reclamar_aviso_cambio_cuenta(p_solicitud_id uuid, p_actor uuid, p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_cliente uuid;
  v_cuenta_nueva uuid;
  v_cambiado_en timestamptz;
  v_aviso crm.cambio_cuenta_avisos%rowtype;
  v_vigentes text[];
  v_perfil public.perfiles%rowtype;
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_reserva uuid;
begin
  if (select auth.role()) is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Solo el servicio de avisos reclama avisos';
  end if;
  -- Quien pide el aviso (lo identifica la Edge por su sesión) debe ser admin vigente (P04).
  if not coalesce(private.admin_banca_vigente(p_actor), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede avisar cambios de cuenta';
  end if;
  select c.cliente_id, c.cuenta_nueva_id, c.cambiado_en
    into v_cliente, v_cuenta_nueva, v_cambiado_en
  from crm.contrato_cuenta_pago_cambios c
  where c.solicitud_id = p_solicitud_id
  limit 1;
  if v_cliente is null then
    return pg_catalog.jsonb_build_object('encontrada', false);
  end if;
  if exists (select 1 from crm.contrato_cuenta_pago_cambios c
             where c.solicitud_id = p_solicitud_id and c.notificado_en is not null) then
    return pg_catalog.jsonb_build_object('encontrada', true, 'ya_notificada', true);
  end if;

  if not p_dry_run then
    insert into crm.cambio_cuenta_avisos (solicitud_id) values (p_solicitud_id)
    on conflict (solicitud_id) do nothing;
  end if;
  select * into v_aviso from crm.cambio_cuenta_avisos
  where solicitud_id = p_solicitud_id
  for update;

  if v_aviso.superada_en is not null then
    return pg_catalog.jsonb_build_object('encontrada', true, 'superada', true);
  end if;
  v_vigentes := private.contratos_vigentes_de_cambio(p_solicitud_id);
  if pg_catalog.cardinality(v_vigentes) = 0 then
    if not p_dry_run then
      update crm.cambio_cuenta_avisos
         set superada_en = pg_catalog.clock_timestamp(), reserva = null, reclamado_en = null,
             actualizado_en = pg_catalog.clock_timestamp()
       where solicitud_id = p_solicitud_id;
    end if;
    return pg_catalog.jsonb_build_object('encontrada', true, 'superada', true);
  end if;
  -- Reserva de 10 minutos, más que la ejecución máxima de una Edge Function (400 s): mientras un
  -- envío sigue en curso, otro intento no lo duplica.
  if v_aviso.reclamado_en is not null
     and v_aviso.reclamado_en > pg_catalog.clock_timestamp() - interval '10 minutes' then
    return pg_catalog.jsonb_build_object('encontrada', true, 'en_curso', true);
  end if;
  if not p_dry_run then
    v_reserva := gen_random_uuid();
    update crm.cambio_cuenta_avisos
       set reserva = v_reserva, reclamado_en = pg_catalog.clock_timestamp(), intentos = intentos + 1,
           actualizado_en = pg_catalog.clock_timestamp()
     where solicitud_id = p_solicitud_id;
  end if;

  select * into v_perfil from public.perfiles where id = v_cliente;
  select * into v_cuenta from crm.cuentas_bancarias where id = v_cuenta_nueva;
  return pg_catalog.jsonb_build_object(
    'encontrada', true, 'ya_notificada', false, 'superada', false, 'en_curso', false,
    'dry_run', p_dry_run, 'reserva', v_reserva,
    'cliente_id', v_perfil.id, 'nombre_completo', v_perfil.nombre_completo,
    'nombres', v_perfil.nombres, 'correo', v_perfil.correo, 'activo', v_perfil.activo,
    'banco_nuevo', v_cuenta.banco, 'moneda', v_cuenta.moneda,
    'ultimos_nuevo', pg_catalog.right(v_cuenta.numero_cuenta, 4),
    'titular_distinto', coalesce(v_cuenta.titular_distinto, false),
    'beneficiario_nombre', case when v_cuenta.titular_distinto then v_cuenta.beneficiario_nombre end,
    'cambiado_en', v_cambiado_en,
    'contratos', pg_catalog.to_jsonb(v_vigentes),
    'pendiente_novedad', v_aviso.novedad_en is null,
    'pendiente_correo', v_aviso.correo_en is null
                        and coalesce(pg_catalog.btrim(v_perfil.correo), '') <> '');
end;
$function$;
revoke all on function crm.reclamar_aviso_cambio_cuenta(uuid, uuid, boolean) from public, anon, authenticated, service_role;
grant execute on function crm.reclamar_aviso_cambio_cuenta(uuid, uuid, boolean) to service_role;

create function crm.confirmar_aviso_cambio_cuenta(
  p_solicitud_id uuid, p_reserva uuid, p_novedad boolean, p_correo boolean, p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_aviso crm.cambio_cuenta_avisos%rowtype;
  v_tiene_correo boolean;
  v_completo boolean;
begin
  if (select auth.role()) is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Solo el servicio de avisos confirma avisos';
  end if;
  -- Solo la reserva vigente confirma: un intento viejo nunca libera la reserva de uno nuevo.
  update crm.cambio_cuenta_avisos
     set novedad_en = case when p_novedad and novedad_en is null then pg_catalog.clock_timestamp() else novedad_en end,
         correo_en  = case when p_correo and correo_en is null then pg_catalog.clock_timestamp() else correo_en end,
         reserva = null,
         reclamado_en = null,
         ultimo_error = pg_catalog.left(nullif(pg_catalog.btrim(p_error), ''), 500),
         actualizado_en = pg_catalog.clock_timestamp()
   where solicitud_id = p_solicitud_id
     and p_reserva is not null
     and reserva = p_reserva
  returning * into v_aviso;
  if not found then
    raise exception using errcode = '22023', message = 'La reserva del aviso ya no es válida; vuelve a intentarlo';
  end if;
  select coalesce(pg_catalog.btrim(p.correo), '') <> '' into v_tiene_correo
  from crm.contrato_cuenta_pago_cambios c
  join public.perfiles p on p.id = c.cliente_id
  where c.solicitud_id = p_solicitud_id
  limit 1;
  v_completo := v_aviso.novedad_en is not null
                and (v_aviso.correo_en is not null or not coalesce(v_tiene_correo, false));
  if v_completo then
    update crm.contrato_cuenta_pago_cambios
       set notificado_en = pg_catalog.clock_timestamp()
     where solicitud_id = p_solicitud_id and notificado_en is null;
  end if;
  return pg_catalog.jsonb_build_object(
    'completo', v_completo, 'novedad', v_aviso.novedad_en is not null,
    'correo', v_aviso.correo_en is not null, 'tiene_correo', coalesce(v_tiene_correo, false));
end;
$function$;
revoke all on function crm.confirmar_aviso_cambio_cuenta(uuid, uuid, boolean, boolean, text) from public, anon, authenticated, service_role;
grant execute on function crm.confirmar_aviso_cambio_cuenta(uuid, uuid, boolean, boolean, text) to service_role;

-- ── 8. Comentarios ─────────────────────────────────────────────────────────────────────────
comment on table crm.cuotas_cuenta_pagada is
  'Constancia: cuenta bancaria a la que se pagó cada cuota. origen=registro: la vigente en la fecha del pago, sellada al registrarlo; origen=inferido: backfill del 26/09 con la cuenta contractual (el enlace nació el 25/09 desde el perfil). Solo vale mientras la cuota esté en pagado. Sin claves foráneas a propósito: sobrevive a las eliminaciones auditadas. No se borra. DATOS SENSIBLES por referencia.';
comment on column crm.cuotas_cuenta_pagada.id is 'Identificador del sello.';
comment on column crm.cuotas_cuenta_pagada.cuota_id is 'Cuota de public.cronograma_pagos (sin FK; ver la tabla). Un sello por cuota.';
comment on column crm.cuotas_cuenta_pagada.contrato_id is 'Contrato de la cuota (sin FK).';
comment on column crm.cuotas_cuenta_pagada.cuenta_bancaria_id is 'Cuenta de crm.cuentas_bancarias a la que se pagó (sin FK).';
comment on column crm.cuotas_cuenta_pagada.origen is 'registro = sellada al registrar el pago; inferido = backfill desde la cuenta contractual.';
comment on column crm.cuotas_cuenta_pagada.sellada_en is 'Cuándo se selló o re-selló.';
comment on table crm.contrato_cuenta_pago_cambios is
  'Historial inmutable de cambios de cuenta de pago de contratos por pedido del cliente (F3, 26/09/2026). Solo notificado_en pasa una vez de NULL a fecha; nada se borra. Sin claves foráneas a propósito: la constancia sobrevive a contratos, cliente, cuentas y personas. DATOS SENSIBLES: motivo y respaldo (correo del cliente).';
comment on column crm.contrato_cuenta_pago_cambios.id is 'Identificador del cambio.';
comment on column crm.contrato_cuenta_pago_cambios.solicitud_id is 'Id de la operación (idempotencia): un cambio de varios contratos comparte solicitud.';
comment on column crm.contrato_cuenta_pago_cambios.contrato_id is 'Contrato cuya cuenta de pago cambió (sin FK).';
comment on column crm.contrato_cuenta_pago_cambios.cliente_id is 'Cliente titular del contrato (sin FK).';
comment on column crm.contrato_cuenta_pago_cambios.cuenta_anterior_id is 'Cuenta de pago antes del cambio (sin FK).';
comment on column crm.contrato_cuenta_pago_cambios.cuenta_nueva_id is 'Cuenta de pago desde el cambio (sin FK).';
comment on column crm.contrato_cuenta_pago_cambios.motivo is 'Motivo escrito por administración (5 a 500 caracteres).';
comment on column crm.contrato_cuenta_pago_cambios.respaldo_ruta is 'Ruta en el bucket privado respaldos-cambio-cuenta del correo del cliente que pide el cambio; respalda una sola solicitud. DATO SENSIBLE.';
comment on column crm.contrato_cuenta_pago_cambios.cambiado_por is 'Administrador que hizo el cambio (id de perfil, sin FK: sobrevive a la eliminación del usuario).';
comment on column crm.contrato_cuenta_pago_cambios.cambiado_en is 'Momento del cambio (hora de la transacción).';
comment on column crm.contrato_cuenta_pago_cambios.notificado_en is 'Aviso al cliente completo (todos sus canales entregados).';
comment on table crm.cambio_cuenta_avisos is 'Estado del aviso al cliente por solicitud de cambio de cuenta de pago: reserva de envío con token (10 min), canales entregados, superado por un cambio posterior, intentos y último error. No se borra.';
comment on column crm.cambio_cuenta_avisos.id is 'Identificador.';
comment on column crm.cambio_cuenta_avisos.solicitud_id is 'Solicitud de crm.contrato_cuenta_pago_cambios.';
comment on column crm.cambio_cuenta_avisos.reserva is 'Token de la reserva en curso: confirmar exige el mismo token.';
comment on column crm.cambio_cuenta_avisos.reclamado_en is 'Inicio de la reserva en curso (se libera al confirmar o a los 10 minutos).';
comment on column crm.cambio_cuenta_avisos.novedad_en is 'Cuándo se publicó la novedad en el portal del cliente.';
comment on column crm.cambio_cuenta_avisos.correo_en is 'Cuándo se envió el correo al cliente.';
comment on column crm.cambio_cuenta_avisos.superada_en is 'El cambio quedó superado por otro posterior: no se avisa.';
comment on column crm.cambio_cuenta_avisos.intentos is 'Reservas de envío realizadas.';
comment on column crm.cambio_cuenta_avisos.ultimo_error is 'Último error de envío (para la pantalla).';
comment on column crm.cambio_cuenta_avisos.creado_en is 'Primera reserva.';
comment on column crm.cambio_cuenta_avisos.actualizado_en is 'Último cambio de estado.';
comment on function private.admin_banca_vigente(uuid) is 'Compuerta de la F3: admin/superadmin activo y con la membresía CRM NO revocada (P04). SECURITY DEFINER porque lee crm.equipo, que authenticated no puede leer; solo responde sí/no y nunca amplía el público de public.es_admin().';
comment on function private.trg_registro_cuenta_pago_no_borrar() is 'Candado: los registros de cuentas de pago (sellos, historial, avisos) no se borran. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.trg_contrato_cuenta_pago_cambios_inmutable() is 'Candado del historial de cambios de cuenta de pago: solo notificado_en NULL→fecha. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.trg_cuotas_cuenta_pagada_solo_resello() is 'Candado del sello: id y cuota inmutables; solo se re-sella la cuenta. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.sellar_cuenta_cuota_pagada() is 'Trigger AFTER en public.cronograma_pagos: sella la cuenta vigente en la fecha del pago al pasar una cuota a pagado. SECURITY DEFINER porque quien registra el pago (gestor de cartera) no tiene grants sobre los registros crm.';
comment on function private.trg_contrato_cuenta_pago_inmutable() is 'Candado del enlace contrato→cuenta: id, contrato y fecha inmutables; la cuenta solo cambia con un cambio registrado en crm.contrato_cuenta_pago_cambios en la misma transacción (F3).';
comment on function private.respaldo_cambio_cuenta_permitido(text) is 'Storage: solo admin/superadmin vigente (P04) sube o lee respaldos, con nombre <cliente_uuid>/<uuid>.(pdf|jpg|jpeg|png).';
comment on function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text) is 'Núcleo del cambio de cuenta de pago: solo admin vigente (P04); por contrato entero; atómico e idempotente por solicitud (compara todos los datos). SECURITY DEFINER porque authenticated no tiene grants sobre el enlace, el historial ni storage.objects.';
comment on function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text) is 'Puerta (INVOKER) del cambio de cuenta de pago de contratos por pedido del cliente. La usa la ventana «Cuentas» del portal (solo admin).';
comment on function private.contratos_cuenta_pago_cliente_autorizado(uuid) is 'Contratos abiertos del cliente con su cuenta de pago, cuotas pendientes y cuotas pagadas por cuenta (con las inferidas aparte). Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre enlace ni sellos. DATOS SENSIBLES.';
comment on function crm.contratos_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) de los contratos abiertos del cliente con su cuenta de pago. Solo admin.';
comment on function private.cambios_cuenta_pago_cliente_autorizado(uuid) is 'Historial de cambios de cuenta de pago del cliente con el estado del aviso. Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre el historial. DATOS SENSIBLES.';
comment on function crm.cambios_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) del historial de cambios de cuenta de pago del cliente. Solo admin.';
comment on function private.contratos_vigentes_de_cambio(uuid) is 'Contratos de una solicitud que siguen cobrando en la cuenta de ese cambio (sin cambios posteriores). INVOKER; la llama crm.reclamar_aviso_cambio_cuenta.';
comment on function crm.reclamar_aviso_cambio_cuenta(uuid, uuid, boolean) is 'Paso 1 del aviso al cliente: reserva el envío (token, 10 min), dice qué canales faltan y devuelve los datos (cuenta nueva tapada, titular, solo contratos vigentes). No avisa cambios superados. Solo service_role y para un actor admin vigente. SECURITY DEFINER porque escribe el estado del aviso.';
comment on function crm.confirmar_aviso_cambio_cuenta(uuid, uuid, boolean, boolean, text) is 'Paso 2 del aviso al cliente: con el token de la reserva, registra los canales entregados y el error; sella notificado_en cuando llegó por todos sus canales. Solo service_role. SECURITY DEFINER porque escribe el historial.';

-- ── 9. Postflight ──────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_pagadas_con_cuenta bigint;
  v_selladas bigint;
  v_f record;
begin
  select count(*) into v_pagadas_con_cuenta
  from public.cronograma_pagos cp join crm.contrato_cuentas_pago l on l.contrato_id = cp.contrato_id
  where cp.estado = 'pagado';
  select count(*) into v_selladas from crm.cuotas_cuenta_pagada where origen = 'inferido';
  if v_selladas <> v_pagadas_con_cuenta
     or exists (select 1 from crm.cuotas_cuenta_pagada where origen <> 'inferido') then
    raise exception 'CAMBIO_CUENTA: backfill incompleto (% sellos de % pagadas con cuenta)', v_selladas, v_pagadas_con_cuenta;
  end if;

  -- Ninguna clave foránea entra ni sale de los registros: las eliminaciones auditadas de
  -- contratos y de usuarios no ven dependencias nuevas.
  if exists (
    select 1 from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and (c.conrelid in ('crm.cuotas_cuenta_pagada'::regclass, 'crm.contrato_cuenta_pago_cambios'::regclass,
                          'crm.cambio_cuenta_avisos'::regclass)
           or c.confrelid in ('crm.cuotas_cuenta_pagada'::regclass, 'crm.contrato_cuenta_pago_cambios'::regclass,
                              'crm.cambio_cuenta_avisos'::regclass))
  ) then
    raise exception 'CAMBIO_CUENTA: los registros no deben tener claves foráneas';
  end if;

  -- Nadie de la API toca las tablas.
  if exists (
    select 1
    from (values ('crm.cuotas_cuenta_pagada'::regclass), ('crm.contrato_cuenta_pago_cambios'::regclass),
                 ('crm.cambio_cuenta_avisos'::regclass)) t(oid)
    cross join (values ('anon'), ('authenticated'), ('service_role')) r(rol)
    where pg_catalog.has_table_privilege(r.rol, t.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  ) or exists (
    select 1 from pg_catalog.pg_class t
    where t.oid in ('crm.cuotas_cuenta_pagada'::regclass, 'crm.contrato_cuenta_pago_cambios'::regclass,
                    'crm.cambio_cuenta_avisos'::regclass)
      and not t.relrowsecurity
  ) then
    raise exception 'CAMBIO_CUENTA: una tabla de registro quedó accesible desde la API o sin RLS';
  end if;

  -- EXECUTE exacto por función (rol NULL = solo su dueño) y search_path vacío.
  for v_f in
    select * from (values
      ('private.admin_banca_vigente(uuid)', 'authenticated'),
      ('private.trg_registro_cuenta_pago_no_borrar()', null),
      ('private.trg_contrato_cuenta_pago_cambios_inmutable()', null),
      ('private.trg_cuotas_cuenta_pagada_solo_resello()', null),
      ('private.sellar_cuenta_cuota_pagada()', null),
      ('private.respaldo_cambio_cuenta_permitido(text)', 'authenticated'),
      ('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)', 'authenticated'),
      ('crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)', 'authenticated'),
      ('private.contratos_cuenta_pago_cliente_autorizado(uuid)', 'authenticated'),
      ('crm.contratos_cuenta_pago_cliente_fn(uuid)', 'authenticated'),
      ('private.cambios_cuenta_pago_cliente_autorizado(uuid)', 'authenticated'),
      ('crm.cambios_cuenta_pago_cliente_fn(uuid)', 'authenticated'),
      ('private.contratos_vigentes_de_cambio(uuid)', null),
      ('crm.reclamar_aviso_cambio_cuenta(uuid,uuid,boolean)', 'service_role'),
      ('crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)', 'service_role')
    ) as f(firma, rol)
  loop
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'CAMBIO_CUENTA: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'CAMBIO_CUENTA: search_path inesperado en %', v_f.firma;
    end if;
  end loop;

  if (select count(*) from pg_catalog.pg_trigger
      where tgrelid = 'public.cronograma_pagos'::regclass
        and tgname in ('trg_cronograma_pagos_20_sellar_cuenta_insert', 'trg_cronograma_pagos_20_sellar_cuenta_update')) <> 2 then
    raise exception 'CAMBIO_CUENTA: faltan los triggers del sello';
  end if;
  if (select count(*) from pg_catalog.pg_policies
      where schemaname = 'storage' and tablename = 'objects' and policyname like 'respaldo\_cambio\_cuenta\_%') <> 7 then
    raise exception 'CAMBIO_CUENTA: las políticas del bucket no son las 7 esperadas';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

## Test (texto íntegro) — CRM-Avance-Corp/supabase/scripts/cuentas-gloria/test-cambio-cuenta-pago.sql
```sql
-- PRUEBA de 20260926204051_crm_cambio_cuenta_pago (F3.1) — SOLO BANCO.
-- ⚠️ Jamás contra producción: siembra usuarios, contratos, cuentas y archivos FICTICIOS en UNA
-- transacción que termina en ROLLBACK. Los disparadores de public.contratos se apagan SOLO
-- mientras se insertan los contratos ficticios (dentro de la transacción) y se vuelven a
-- encender antes de probar nada.
--
-- Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-cambio-cuenta-pago.sql   (migración aplicada)
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';

-- Paridad con producción: si el banco no tiene la exigencia de cuenta al registrar un pago
-- (P-0XX S3, ya en producción), se instala DENTRO de esta transacción.
select to_regprocedure('private.exigir_cuenta_pago_cronograma()') is null as falta_exigir \gset
\if :falta_exigir
\ir ../../migrations/20260925194026_p0xx_pagos_solo_cuenta_contractual.sql
\endif

-- ── Siembra ficticia ─────────────────────────────────────────────────────────────────────────
-- 01 admin · 02 operaciones · 03 analista · 04 superadmin · 05 cliente C · 06 cliente D ·
-- 07 admin con la membresía CRM revocada (P04) · 08 otro admin.
insert into auth.users (id, email, aud, role) values
  ('e7b10000-0000-4000-8000-000000000001', 'f3.admin@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000002', 'f3.oper@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000003', 'f3.analista@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000004', 'f3.super@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000005', 'f3.cliente.c@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000006', 'f3.cliente.d@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000007', 'f3.revocada@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000008', 'f3.admin2@prueba.invalid', 'authenticated', 'authenticated');
insert into public.perfiles (id, nombre_completo, nombres, dni, correo, rol, activo, asesor_perfil_id) values
  ('e7b10000-0000-4000-8000-000000000001', 'F3 ADMIN PRUEBA', null, '77710001', 'f3.admin@prueba.invalid', 'admin', true, null),
  ('e7b10000-0000-4000-8000-000000000002', 'F3 OPERACIONES PRUEBA', null, '77710002', 'f3.oper@prueba.invalid', 'operaciones', true, null),
  ('e7b10000-0000-4000-8000-000000000003', 'F3 ANALISTA PRUEBA', null, '77710003', 'f3.analista@prueba.invalid', 'analista', true, null),
  ('e7b10000-0000-4000-8000-000000000004', 'F3 SUPERADMIN PRUEBA', null, '77710004', 'f3.super@prueba.invalid', 'superadmin', true, null),
  ('e7b10000-0000-4000-8000-000000000005', 'PRUEBA CLIENTE CE', 'CLIENTE', '77710005', 'f3.cliente.c@prueba.invalid', 'cliente', true, 'e7b10000-0000-4000-8000-000000000003'),
  ('e7b10000-0000-4000-8000-000000000006', 'PRUEBA CLIENTE DE', 'CLIENTE', '77710006', 'f3.cliente.d@prueba.invalid', 'cliente', true, 'e7b10000-0000-4000-8000-000000000003'),
  ('e7b10000-0000-4000-8000-000000000007', 'F3 ADMIN REVOCADA', null, '77710007', 'f3.revocada@prueba.invalid', 'admin', true, null),
  ('e7b10000-0000-4000-8000-000000000008', 'F3 ADMIN DOS', null, '77710008', 'f3.admin2@prueba.invalid', 'admin', true, null);
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('e7b10000-0000-4000-8000-000000000007', 'gerencia', false);

-- Cuentas del cliente C: A (vigente, la de pago hoy), B (vigente, la nueva), X (retirada), U (USD),
-- T (vigente, a nombre de un tercero). Z es del cliente D.
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, beneficiario_nombre, beneficiario_dni, activa, origen, creado_en, desactivada_en) values
  ('e7b1c000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'ahorros', '19100000000001', '00219100000000000001', false, null, null, true, 'contrato', '2026-01-01', null),
  ('e7b1c000-0000-4000-8000-000000000002', 'e7b10000-0000-4000-8000-000000000005', 'PEN', 'Interbank', 'ahorros', '89830000000002', '00389800000000000002', false, null, null, true, 'contrato', '2026-09-20', null),
  ('e7b1c000-0000-4000-8000-000000000003', 'e7b10000-0000-4000-8000-000000000005', 'PEN', 'BBVA', 'ahorros', '01100000000003', '01110000000000000003', false, null, null, false, 'contrato', '2025-01-01', '2025-06-01'),
  ('e7b1c000-0000-4000-8000-000000000004', 'e7b10000-0000-4000-8000-000000000005', 'USD', 'BCP', 'ahorros', '19100000000004', '00219100000000000004', false, null, null, true, 'contrato', '2026-01-01', null),
  ('e7b1c000-0000-4000-8000-000000000005', 'e7b10000-0000-4000-8000-000000000006', 'PEN', 'BCP', 'ahorros', '19100000000005', '00219100000000000005', false, null, null, true, 'contrato', '2026-01-01', null),
  ('e7b1c000-0000-4000-8000-000000000006', 'e7b10000-0000-4000-8000-000000000005', 'PEN', 'Scotiabank', 'ahorros', '00070000000006', '00907000000000000006', true, 'MARIA TERCERA PRUEBA', '44556677', true, 'contrato', '2026-09-21', null);

-- Contratos: K1 activo PEN, K2 vencido PEN, K3 activo USD, K4 renovado PEN (cerrado), K5 activo sin cuenta.
alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial) values
  ('e7b1d000-0000-4000-8000-000000000001', 'F3-K1', 'e7b10000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b1d000-0000-4000-8000-000000000002', 'F3-K2', 'e7b10000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'vencido',  '2025-01-01', '2026-01-01', 'd0000000-0000-4000-8000-000000000002', '2025-01-01'),
  ('e7b1d000-0000-4000-8000-000000000003', 'F3-K3', 'e7b10000-0000-4000-8000-000000000005', 10000, 'USD', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b1d000-0000-4000-8000-000000000004', 'F3-K4', 'e7b10000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'renovado', '2025-01-01', '2026-01-01', 'd0000000-0000-4000-8000-000000000002', '2025-01-01'),
  ('e7b1d000-0000-4000-8000-000000000005', 'F3-K5', 'e7b10000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01');
alter table public.contratos enable trigger user;

insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values
  ('e7b1d000-0000-4000-8000-000000000001', 'e7b1c000-0000-4000-8000-000000000001'),
  ('e7b1d000-0000-4000-8000-000000000002', 'e7b1c000-0000-4000-8000-000000000001'),
  ('e7b1d000-0000-4000-8000-000000000003', 'e7b1c000-0000-4000-8000-000000000004'),
  ('e7b1d000-0000-4000-8000-000000000004', 'e7b1c000-0000-4000-8000-000000000001');

-- Cuotas (con todos los disparadores): K1 #1 nace pagada (el sello de INSERT la marca en A);
-- K1 #2, K1 #3 y K2 #1 pendientes.
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado) values
  ('e7b1e000-0000-4000-8000-000000000001', 'e7b1d000-0000-4000-8000-000000000001', 1, '2026-02-01', 100, 'pagado'),
  ('e7b1e000-0000-4000-8000-000000000002', 'e7b1d000-0000-4000-8000-000000000001', 2, '2026-10-01', 100, 'pendiente'),
  ('e7b1e000-0000-4000-8000-000000000003', 'e7b1d000-0000-4000-8000-000000000002', 1, '2026-10-05', 100, 'pendiente'),
  ('e7b1e000-0000-4000-8000-000000000004', 'e7b1d000-0000-4000-8000-000000000001', 3, '2026-11-01', 100, 'pendiente');

-- Respaldos ya subidos (como postgres), cada uno con quien lo subió (owner y owner_id).
insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values
  -- R1: el correo del cliente C, subido por el admin (para S1)
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000001.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf"}'),
  -- R_D: en la carpeta del cliente D
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000006/e7b1f000-0000-4000-8000-000000000002.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf"}'),
  -- R3 y R4: para S3 y S4 (admin)
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000003.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf"}'),
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000004.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf"}'),
  -- R5: para S5, subido por el superadmin
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000005.pdf',
   'e7b10000-0000-4000-8000-000000000004', 'e7b10000-0000-4000-8000-000000000004', '{"size": 2048, "mimetype": "application/pdf"}'),
  -- R_ADMIN2: subido por OTRO admin
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000006.pdf',
   'e7b10000-0000-4000-8000-000000000008', 'e7b10000-0000-4000-8000-000000000008', '{"size": 2048, "mimetype": "application/pdf"}'),
  -- R_TXT: nombre .pdf pero contenido de texto
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000007.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "text/plain"}'),
  -- R_OPER y R_REVOC: para los mutantes de permisos
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000008.pdf',
   'e7b10000-0000-4000-8000-000000000002', 'e7b10000-0000-4000-8000-000000000002', '{"size": 2048, "mimetype": "application/pdf"}'),
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000009.pdf',
   'e7b10000-0000-4000-8000-000000000007', 'e7b10000-0000-4000-8000-000000000007', '{"size": 2048, "mimetype": "application/pdf"}'),
  -- R_ALT: otro correo válido del admin, sin usar
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-00000000000b.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf"}');

-- ── Utilidades ───────────────────────────────────────────────────────────────────────────────
-- Intenta el cambio como un usuario; devuelve 'OK:<json>' o 'ERR:<sqlstate>:<mensaje>'.
create function pg_temp.cambio(p_uid uuid, p_sol uuid, p_cta uuid, p_ids uuid[], p_mot text, p_ruta text,
  p_cli uuid default 'e7b10000-0000-4000-8000-000000000005') returns text
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.cambiar_cuenta_pago_contratos(p_sol, p_cli, p_cta, p_ids, p_mot, p_ruta);
    execute 'reset role';
    return 'OK:' || r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR:' || e || ':' || m;
  end;
end;
$f$;
-- Reclamar / confirmar el aviso con el rol indicado (por defecto el de la Edge: service_role).
create function pg_temp.reclamar(p_sol uuid, p_actor uuid, p_dry boolean default false,
  p_rol text default 'service_role') returns jsonb
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_rol)::text, true);
  execute format('set local role %I', p_rol);
  begin
    r := crm.reclamar_aviso_cambio_cuenta(p_sol, p_actor, p_dry);
    execute 'reset role';
    return r;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return jsonb_build_object('error', e, 'mensaje', m);
  end;
end;
$f$;
create function pg_temp.confirmar(p_sol uuid, p_res uuid, p_nov boolean, p_cor boolean, p_err text default null,
  p_rol text default 'service_role') returns jsonb
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_rol)::text, true);
  execute format('set local role %I', p_rol);
  begin
    r := crm.confirmar_aviso_cambio_cuenta(p_sol, p_res, p_nov, p_cor, p_err);
    execute 'reset role';
    return r;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return jsonb_build_object('error', e, 'mensaje', m);
  end;
end;
$f$;
-- Cuenta respaldos del bucket visibles para un rol/usuario.
create function pg_temp.respaldos_visibles(p_rol text, p_uid uuid default null) returns integer
language plpgsql as $f$
declare n integer;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_rol)
         else json_build_object('sub', p_uid, 'role', p_rol) end::text, true);
  execute format('set local role %I', p_rol);
  select count(*) into n from storage.objects where bucket_id = 'respaldos-cambio-cuenta';
  execute 'reset role';
  return n;
end;
$f$;
create function pg_temp.espera(p_resultado text, p_prefijo text, p_caso text) returns void
language plpgsql as $f$
begin
  if p_resultado is null or p_resultado not like p_prefijo || '%' then
    raise exception 'FALLO [%]: esperaba «%…», vino «%»', p_caso, p_prefijo, p_resultado;
  end if;
end;
$f$;
create function pg_temp.enlace(p_contrato uuid) returns uuid language sql as $f$
  select cuenta_bancaria_id from crm.contrato_cuentas_pago where contrato_id = p_contrato;
$f$;
create function pg_temp.sello(p_cuota uuid) returns uuid language sql as $f$
  select cuenta_bancaria_id from crm.cuotas_cuenta_pagada where cuota_id = p_cuota;
$f$;
create function pg_temp.hoy() returns date language sql as $f$
  select (now() at time zone 'America/Lima')::date;
$f$;
-- Aplica un mutante reemplazando un fragmento del cuerpo vivo; falla si el fragmento no está.
create function pg_temp.mutar(p_firma text, p_de text, p_a text) returns void
language plpgsql as $f$
declare s text; t text;
begin
  s := pg_get_functiondef(p_firma::regprocedure);
  t := replace(s, p_de, p_a);
  if t = s then raise exception 'MUTANTE MAL ESCRITO: no se encontró el fragmento en %', p_firma; end if;
  execute t;
end;
$f$;

-- ── A. Permisos, reglas, cambio e idempotencia ───────────────────────────────────────────────
do $casos$
declare
  A constant uuid := 'e7b1c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b1c000-0000-4000-8000-000000000002';
  X constant uuid := 'e7b1c000-0000-4000-8000-000000000003';
  Z constant uuid := 'e7b1c000-0000-4000-8000-000000000005';
  K1 constant uuid := 'e7b1d000-0000-4000-8000-000000000001';
  K2 constant uuid := 'e7b1d000-0000-4000-8000-000000000002';
  K3 constant uuid := 'e7b1d000-0000-4000-8000-000000000003';
  K4 constant uuid := 'e7b1d000-0000-4000-8000-000000000004';
  K5 constant uuid := 'e7b1d000-0000-4000-8000-000000000005';
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
  OPER constant uuid := 'e7b10000-0000-4000-8000-000000000002';
  ANAL constant uuid := 'e7b10000-0000-4000-8000-000000000003';
  CLI constant uuid := 'e7b10000-0000-4000-8000-000000000005';
  REVOC constant uuid := 'e7b10000-0000-4000-8000-000000000007';
  R1 constant text := 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000001.pdf';
  R_D constant text := 'e7b10000-0000-4000-8000-000000000006/e7b1f000-0000-4000-8000-000000000002.pdf';
  R_ALT constant text := 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-00000000000b.pdf';
  R_REVOC constant text := 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000009.pdf';
  S1 constant uuid := 'e7b1a000-0000-4000-8000-000000000001';
  MOT constant text := 'El cliente lo pidió por correo el 26/09';
  v text;
begin
  -- Sello al insertar una cuota ya pagada.
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000001') is distinct from A
     or (select origen from crm.cuotas_cuenta_pagada where cuota_id = 'e7b1e000-0000-4000-8000-000000000001') <> 'registro' then
    raise exception 'FALLO: la cuota pagada al insertarse debía quedar sellada en A como registro';
  end if;
  raise notice 'OK sello: una cuota que nace pagada guarda su cuenta (registro)';

  -- Permisos: solo admin o superadmin con la membresía CRM vigente.
  perform pg_temp.espera(pg_temp.cambio(OPER, S1, B, array[K1, K2], MOT, R1), 'ERR:42501', 'operaciones');
  perform pg_temp.espera(pg_temp.cambio(ANAL, S1, B, array[K1, K2], MOT, R1), 'ERR:42501', 'analista');
  perform pg_temp.espera(pg_temp.cambio(CLI, S1, B, array[K1, K2], MOT, R1), 'ERR:42501', 'cliente');
  perform pg_temp.espera(pg_temp.cambio(REVOC, S1, B, array[K1, K2], MOT, R_REVOC), 'ERR:42501', 'admin con membresía CRM revocada');
  raise notice 'OK permisos: operaciones, analista, cliente y admin revocado (P04) → 42501';

  -- Reglas (todas 22023 y sin cambiar nada).
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-0000000000ff.pdf'), 'ERR:22023:Adjunta el correo', 'respaldo inexistente');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, R_D), 'ERR:22023:Adjunta el correo', 'respaldo de otro cliente');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, null), 'ERR:22023:Adjunta el correo', 'sin respaldo');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, 'e7b10000-0000-4000-8000-000000000005/libre.pdf'), 'ERR:22023:Adjunta el correo', 'nombre inválido');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], 'x', R1), 'ERR:22023:Escribe el motivo', 'motivo corto');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], '    ', R1), 'ERR:22023:Escribe el motivo', 'motivo en blanco');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, Z, array[K1], MOT, R1), 'ERR:22023:La cuenta nueva no es de este cliente', 'cuenta ajena');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, X, array[K1], MOT, R1), 'ERR:22023:La cuenta nueva ya no está vigente', 'cuenta retirada');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K4], MOT, R1), 'ERR:22023:El contrato F3-K4 está cerrado', 'contrato cerrado');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K3], MOT, R1), 'ERR:22023:El contrato F3-K3 es en USD', 'moneda distinta');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K5], MOT, R1), 'ERR:22023:El contrato F3-K5 no tiene cuenta de pago', 'sin cuenta');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, A, array[K1], MOT, R1), 'ERR:22023:El contrato F3-K1 ya cobra en esa cuenta', 'misma cuenta');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K1], MOT, R1), 'ERR:22023:Elige entre 1 y 100', 'repetidos');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[]::uuid[], MOT, R1), 'ERR:22023:Elige entre 1 y 100', 'vacío');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, null], MOT, R1), 'ERR:22023:Elige entre 1 y 100', 'con nulo');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, gen_random_uuid()], MOT, R1), 'ERR:22023:Algún contrato no existe', 'contrato inexistente');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K4], MOT, R1), 'ERR:22023:El contrato F3-K4 está cerrado', 'todo o nada');
  if pg_temp.enlace(K1) is distinct from A or (select count(*) from crm.contrato_cuenta_pago_cambios) <> 0 then
    raise exception 'FALLO: un rechazo dejó cambios a medias';
  end if;
  raise notice 'OK reglas: respaldo (inexistente, ajeno, ausente, nombre), motivo, cuenta ajena/retirada, contrato cerrado/otra moneda/sin cuenta/inexistente, misma cuenta, repetidos, vacío, nulo y todo-o-nada';

  -- Cambio correcto de K1 y K2 a B.
  v := pg_temp.cambio(ADMIN, S1, B, array[K1, K2], MOT, R1);
  perform pg_temp.espera(v, 'OK:', 'cambio correcto');
  if pg_temp.enlace(K1) is distinct from B or pg_temp.enlace(K2) is distinct from B
     or (select count(*) from crm.contrato_cuenta_pago_cambios
         where solicitud_id = S1 and cuenta_anterior_id = A and cuenta_nueva_id = B
           and cambiado_por = ADMIN and cliente_id = CLI and motivo = MOT and respaldo_ruta = R1) <> 2 then
    raise exception 'FALLO: el cambio no dejó los enlaces en B con 2 filas de historial completas: %', v;
  end if;
  raise notice 'OK cambio: K1 y K2 cobran en B; historial con 2 filas (anterior, nueva, quién, motivo, respaldo)';

  -- Idempotencia: la misma solicitud no se repite; con cualquier dato distinto se rechaza.
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K2], MOT, R1), 'OK:{"contratos": 2, "ya_aplicada": true', 'doble clic');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K2, K1], MOT, R1), 'OK:{"contratos": 2, "ya_aplicada": true', 'doble clic en otro orden');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, R1), 'ERR:22023:Esta solicitud ya se usó', 'otros contratos');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K2], 'Otro motivo distinto del original', R1), 'ERR:22023:Esta solicitud ya se usó', 'otro motivo');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K2], MOT, R_ALT), 'ERR:22023:Esta solicitud ya se usó', 'otro respaldo');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, 'e7b1c000-0000-4000-8000-000000000006', array[K1, K2], MOT, R1), 'ERR:22023:Esta solicitud ya se usó', 'otra cuenta');
  if (select count(*) from crm.contrato_cuenta_pago_cambios) <> 2 then
    raise exception 'FALLO: el doble clic duplicó historial';
  end if;
  raise notice 'OK idempotencia: el doble clic no duplica; la solicitud con otros contratos, motivo, respaldo o cuenta se rechaza';
end;
$casos$;

-- ── B. Sello: lo pagado conserva su cuenta; cuenta por FECHA del pago ────────────────────────
do $sello$
declare
  A constant uuid := 'e7b1c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b1c000-0000-4000-8000-000000000002';
  n integer;
begin
  -- Pago hecho hoy, después del cambio → cuenta nueva.
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy()
   where id = 'e7b1e000-0000-4000-8000-000000000002';
  -- Pago hecho AYER (antes del cambio) pero registrado hoy → cuenta anterior.
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy() - 1
   where id = 'e7b1e000-0000-4000-8000-000000000004';
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000001') is distinct from A
     or pg_temp.sello('e7b1e000-0000-4000-8000-000000000002') is distinct from B
     or pg_temp.sello('e7b1e000-0000-4000-8000-000000000004') is distinct from A then
    raise exception 'FALLO: la cuota vieja debía seguir en A, la pagada hoy en B y la pagada ayer en A';
  end if;
  -- Anular y volver a pagar re-sella (una sola fila por cuota).
  update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null
   where id = 'e7b1e000-0000-4000-8000-000000000004';
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy()
   where id = 'e7b1e000-0000-4000-8000-000000000004';
  select count(*) into n from crm.cuotas_cuenta_pagada where cuota_id = 'e7b1e000-0000-4000-8000-000000000004';
  if n <> 1 or pg_temp.sello('e7b1e000-0000-4000-8000-000000000004') is distinct from B then
    raise exception 'FALLO: volver a pagar debía re-sellar la misma fila en B (filas=%)', n;
  end if;
  if exists (select 1 from crm.cuotas_cuenta_pagada
             where contrato_id = 'e7b1d000-0000-4000-8000-000000000001' and origen <> 'registro') then
    raise exception 'FALLO: los sellos del registro debían marcarse como registro';
  end if;
  raise notice 'OK sello: lo pagado antes sigue en A; lo pagado hoy va a B; un pago de ayer registrado hoy va a A; volver a pagar re-sella';
end;
$sello$;

-- M4b: el sello sin la regla de la fecha → un pago de ayer se atribuiría a la cuenta nueva.
savepoint m4b;
select pg_temp.mutar('private.sellar_cuenta_cuota_pagada()', 'if new.fecha_pago_real is not null then', 'if false then');
do $m4b$ begin
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy() - 1
   where id = 'e7b1e000-0000-4000-8000-000000000003';
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000003') is distinct from 'e7b1c000-0000-4000-8000-000000000002' then
    raise exception 'MUTANTE 4b NO CAZADO';
  end if;
  raise notice 'OK mutante 4b cazado (sin la regla de la fecha, un pago de ayer iría a la cuenta nueva)';
end $m4b$;
rollback to savepoint m4b;

-- ── C. Candados ──────────────────────────────────────────────────────────────────────────────
do $candados$
declare S1 constant uuid := 'e7b1a000-0000-4000-8000-000000000001';
begin
  -- El enlace no se mueve sin historial en la transacción.
  begin
    update crm.contrato_cuentas_pago set cuenta_bancaria_id = 'e7b1c000-0000-4000-8000-000000000001'
     where contrato_id = 'e7b1d000-0000-4000-8000-000000000001';
    raise exception 'FALLO: el enlace cambió sin historial';
  exception when sqlstate '22023' then null;
  end;
  -- El historial no se reescribe (motivo ni autor) ni se borra.
  begin
    update crm.contrato_cuenta_pago_cambios set motivo = 'reescrito por prueba' where solicitud_id = S1;
    raise exception 'FALLO: el historial se pudo reescribir';
  exception when sqlstate '22023' then null;
  end;
  begin
    update crm.contrato_cuenta_pago_cambios set cambiado_por = 'e7b10000-0000-4000-8000-000000000008' where solicitud_id = S1;
    raise exception 'FALLO: el autor del cambio se pudo reescribir';
  exception when sqlstate '22023' then null;
  end;
  begin
    delete from crm.contrato_cuenta_pago_cambios where solicitud_id = S1;
    raise exception 'FALLO: el historial se pudo borrar';
  exception when sqlstate '22023' then null;
  end;
  -- El sello no se borra ni cambia de cuota.
  begin
    delete from crm.cuotas_cuenta_pagada where cuota_id = 'e7b1e000-0000-4000-8000-000000000001';
    raise exception 'FALLO: un sello se pudo borrar';
  exception when sqlstate '22023' then null;
  end;
  begin
    update crm.cuotas_cuenta_pagada set cuota_id = gen_random_uuid() where cuota_id = 'e7b1e000-0000-4000-8000-000000000001';
    raise exception 'FALLO: un sello cambió de cuota';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'OK candados: el enlace no cambia sin historial; historial y sellos no se reescriben ni se borran';
end;
$candados$;

-- ── D. Lecturas (admin y superadmin sí; el resto 42501) ──────────────────────────────────────
do $lecturas$
declare r record; u uuid; n integer;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  select * into r from crm.contratos_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005') where numero_contrato = 'F3-K1';
  if r.cuenta_bancaria_id is distinct from 'e7b1c000-0000-4000-8000-000000000002' or r.cuotas_pendientes <> 0
     or r.pagadas_por_cuenta <> jsonb_build_array(
          jsonb_build_object('cuenta_bancaria_id', 'e7b1c000-0000-4000-8000-000000000002', 'banco', 'Interbank',
                             'numero_cuenta', '89830000000002', 'cuotas', 2, 'inferidas', 0),
          jsonb_build_object('cuenta_bancaria_id', 'e7b1c000-0000-4000-8000-000000000001', 'banco', 'BCP',
                             'numero_cuenta', '19100000000001', 'cuotas', 1, 'inferidas', 0)) then
    raise exception 'FALLO: la lectura de K1 no muestra B, 0 pendientes y B=2 / A=1 pagadas: %', row_to_json(r);
  end if;
  if (select count(*) from crm.contratos_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005')) <> 4 then
    raise exception 'FALLO: debían listarse los 4 contratos abiertos (sin el renovado)';
  end if;
  if (select count(*) from crm.cambios_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005')
      where cambiado_por_nombre = 'F3 ADMIN PRUEBA' and aviso_estado = 'pendiente') <> 2 then
    raise exception 'FALLO: el historial debía traer 2 cambios del admin con aviso pendiente';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
  select count(*) into n from crm.contratos_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005');
  if n <> 4 then raise exception 'FALLO: el superadmin debía leer los 4 contratos, leyó %', n; end if;
  foreach u in array array['e7b10000-0000-4000-8000-000000000002', 'e7b10000-0000-4000-8000-000000000003',
                           'e7b10000-0000-4000-8000-000000000005', 'e7b10000-0000-4000-8000-000000000007']::uuid[] loop
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    begin
      perform crm.contratos_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005');
      raise exception 'FALLO: % pudo leer las cuentas de pago', u;
    exception when insufficient_privilege then null;
    end;
    begin
      perform crm.cambios_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005');
      raise exception 'FALLO: % pudo leer el historial de cambios', u;
    exception when insufficient_privilege then null;
    end;
  end loop;
  raise notice 'OK lecturas: admin y superadmin ven contratos (cuenta nueva, pendientes, pagadas por cuenta) e historial; operaciones, analista, cliente y admin revocado 42501';
end;
$lecturas$;

-- ── E. Aviso en dos pasos (reservar con token → confirmar por canal), solo service_role ─────
do $aviso$
declare
  v jsonb; r1 uuid; r2 uuid;
  S1 constant uuid := 'e7b1a000-0000-4000-8000-000000000001';
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
begin
  -- Solo service_role: authenticated no tiene EXECUTE; y el dueño sin el rol del servicio, tampoco.
  v := pg_temp.reclamar(S1, ADMIN, true, 'authenticated');
  if v->>'error' is distinct from '42501' then raise exception 'FALLO: authenticated reclamó un aviso: %', v; end if;
  v := pg_temp.confirmar(S1, gen_random_uuid(), true, true, null, 'authenticated');
  if v->>'error' is distinct from '42501' then raise exception 'FALLO: authenticated confirmó un aviso: %', v; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role', 'authenticated')::text, true);
  begin
    perform crm.reclamar_aviso_cambio_cuenta(S1, ADMIN, true);
    raise exception 'FALLO: reclamar corrió sin el rol del servicio';
  exception when insufficient_privilege then null;
  end;
  -- Quien lo pide debe ser admin vigente.
  if pg_temp.reclamar(S1, 'e7b10000-0000-4000-8000-000000000002', true)->>'error' is distinct from '42501'
     or pg_temp.reclamar(S1, 'e7b10000-0000-4000-8000-000000000007', true)->>'error' is distinct from '42501'
     or pg_temp.reclamar(S1, null, true)->>'error' is distinct from '42501' then
    raise exception 'FALLO: operaciones, un admin revocado o un actor nulo pudieron pedir el aviso';
  end if;

  v := pg_temp.reclamar(S1, ADMIN, true);
  if (v->>'dry_run')::boolean is not true or v->>'ultimos_nuevo' <> '0002' or v->'reserva' <> 'null'::jsonb
     or v->'contratos' <> '["F3-K1", "F3-K2"]'::jsonb or (v->>'titular_distinto')::boolean
     or v->'beneficiario_nombre' <> 'null'::jsonb
     or exists (select 1 from crm.cambio_cuenta_avisos) then
    raise exception 'FALLO: dry_run no debía escribir nada y debía traer los 2 contratos: %', v;
  end if;
  v := pg_temp.reclamar(S1, ADMIN);
  r1 := (v->>'reserva')::uuid;
  if r1 is null or (v->>'pendiente_novedad')::boolean is not true or (v->>'pendiente_correo')::boolean is not true
     or v->>'correo' <> 'f3.cliente.c@prueba.invalid' then
    raise exception 'FALLO: la primera reserva debía traer token y pedir portal y correo: %', v;
  end if;
  v := pg_temp.reclamar(S1, ADMIN);
  if (v->>'en_curso')::boolean is not true then
    raise exception 'FALLO: una segunda reserva inmediata debía decir en_curso: %', v;
  end if;
  -- Sin el token de la reserva no se confirma.
  if pg_temp.confirmar(S1, gen_random_uuid(), true, true)->>'error' is distinct from '22023'
     or pg_temp.confirmar(S1, null, true, true)->>'error' is distinct from '22023' then
    raise exception 'FALLO: se confirmó un aviso sin el token de su reserva';
  end if;
  -- Llegó el portal pero falló el correo: NO se sella; se guarda el error y se libera la reserva.
  v := pg_temp.confirmar(S1, r1, true, false, 'Resend respondió 500');
  if v ? 'error' or (v->>'completo')::boolean
     or exists (select 1 from crm.contrato_cuenta_pago_cambios where notificado_en is not null)
     or (select ultimo_error from crm.cambio_cuenta_avisos where solicitud_id = S1) <> 'Resend respondió 500'
     or (select reserva from crm.cambio_cuenta_avisos where solicitud_id = S1) is not null then
    raise exception 'FALLO: un aviso a medias no debía sellarse: %', v;
  end if;
  -- El reintento solo pide lo que faltó (el correo), con un token nuevo; el viejo ya no vale.
  v := pg_temp.reclamar(S1, ADMIN);
  r2 := (v->>'reserva')::uuid;
  if r2 is null or r2 = r1 or (v->>'pendiente_novedad')::boolean or (v->>'pendiente_correo')::boolean is not true then
    raise exception 'FALLO: el reintento debía pedir solo el correo con un token nuevo: %', v;
  end if;
  if pg_temp.confirmar(S1, r1, false, true)->>'error' is distinct from '22023' then
    raise exception 'FALLO: un token viejo confirmó el aviso';
  end if;
  v := pg_temp.confirmar(S1, r2, false, true);
  if (v->>'completo')::boolean is not true
     or (select count(*) from crm.contrato_cuenta_pago_cambios where solicitud_id = S1 and notificado_en is not null) <> 2 then
    raise exception 'FALLO: con portal y correo entregados debía sellarse: %', v;
  end if;
  v := pg_temp.reclamar(S1, ADMIN);
  if (v->>'ya_notificada')::boolean is not true then
    raise exception 'FALLO: tras sellar debía decir ya_notificada: %', v;
  end if;
  begin
    update crm.contrato_cuenta_pago_cambios set notificado_en = now() where solicitud_id = S1;
    raise exception 'FALLO: el sello del aviso se pudo reescribir';
  exception when sqlstate '22023' then null;
  end;
  begin
    delete from crm.cambio_cuenta_avisos where solicitud_id = S1;
    raise exception 'FALLO: el estado del aviso se pudo borrar';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'OK aviso: solo service_role y para admin vigente; dry_run sin efectos; reserva con token; doble reserva en_curso; sin token no confirma; a medias no sella y guarda el error; reintento solo del canal que faltó con token nuevo; token viejo rechazado; sello final no reescribible';
end;
$aviso$;

-- ── F. Aviso superado, cuenta de un tercero y reserva vencida ───────────────────────────────
-- S3 mueve K1 de B a A y S4 lo pasa a T (cuenta a nombre de un tercero): el aviso de S3 ya no se envía.
do $superado$
declare v jsonb; v_estado text; r1 uuid; r2 uuid;
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
  S3 constant uuid := 'e7b1a000-0000-4000-8000-000000000003';
  S4 constant uuid := 'e7b1a000-0000-4000-8000-000000000004';
begin
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S3, 'e7b1c000-0000-4000-8000-000000000001',
    array['e7b1d000-0000-4000-8000-000000000001'::uuid], 'El cliente pidió volver a su cuenta anterior',
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000003.pdf'), 'OK:', 'S3');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S4, 'e7b1c000-0000-4000-8000-000000000006',
    array['e7b1d000-0000-4000-8000-000000000001'::uuid], 'El cliente pidió cobrar en la cuenta de su esposa',
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000004.pdf'), 'OK:', 'S4');
  v := pg_temp.reclamar(S3, ADMIN);
  if (v->>'superada')::boolean is not true then
    raise exception 'FALLO: el aviso de un cambio superado no debía enviarse: %', v;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role', 'authenticated')::text, true);
  select h.aviso_estado into v_estado from crm.cambios_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005') h
  where h.solicitud_id = S3;
  if v_estado is distinct from 'superado' then
    raise exception 'FALLO: el historial debía mostrar el aviso de S3 como superado, mostró %', v_estado;
  end if;
  v := pg_temp.reclamar(S4, ADMIN);
  r1 := (v->>'reserva')::uuid;
  if v->'contratos' <> '["F3-K1"]'::jsonb or (v->>'titular_distinto')::boolean is not true
     or v->>'beneficiario_nombre' <> 'MARIA TERCERA PRUEBA' or v->>'ultimos_nuevo' <> '0006' then
    raise exception 'FALLO: el aviso de S4 debía anunciar solo F3-K1 y a nombre del tercero: %', v;
  end if;
  -- Reserva vencida (10 min): otro intento toma una reserva nueva y el token viejo deja de valer.
  update crm.cambio_cuenta_avisos set reclamado_en = clock_timestamp() - interval '11 minutes' where solicitud_id = S4;
  v := pg_temp.reclamar(S4, ADMIN);
  r2 := (v->>'reserva')::uuid;
  if r2 is null or r2 = r1 then
    raise exception 'FALLO: una reserva vencida debía ceder a un intento nuevo: %', v;
  end if;
  if pg_temp.confirmar(S4, r1, true, true)->>'error' is distinct from '22023'
     or (pg_temp.confirmar(S4, r2, true, true)->>'completo')::boolean is not true then
    raise exception 'FALLO: solo la reserva vigente debía confirmar';
  end if;
  raise notice 'OK aviso superado: no se envía y el historial lo muestra; el vigente anuncia solo sus contratos y el tercero; una reserva vencida cede y su token ya no vale';
end;
$superado$;

-- ── G. Superadmin, respaldo ajeno, reutilizado o que no es PDF/imagen ────────────────────────
do $respaldos$
declare n integer;
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
  SUPER constant uuid := 'e7b10000-0000-4000-8000-000000000004';
  K2 constant uuid := 'e7b1d000-0000-4000-8000-000000000002';
  A constant uuid := 'e7b1c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b1c000-0000-4000-8000-000000000002';
  MOT constant text := 'El cliente lo pidió por correo el 26/09';
begin
  perform pg_temp.espera(pg_temp.cambio(SUPER, 'e7b1a000-0000-4000-8000-000000000005', A, array[K2],
    'Pedido del cliente por correo (superadmin)', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000005.pdf'),
    'OK:', 'superadmin');
  if pg_temp.enlace(K2) is distinct from A then raise exception 'FALLO: el cambio del superadmin no movió K2 a A'; end if;
  select count(*) into n from crm.contrato_cuenta_pago_cambios;
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000006', B, array[K2], MOT,
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000001.pdf'), 'ERR:22023:Ese correo ya respalda otro cambio', 'respaldo reutilizado');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000007', B, array[K2], MOT,
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000006.pdf'), 'ERR:22023:El respaldo debe subirlo quien hace el cambio', 'respaldo de otro admin');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000008', B, array[K2], MOT,
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000007.pdf'), 'ERR:22023:Adjunta el correo', 'respaldo que no es PDF/imagen');
  if pg_temp.enlace(K2) is distinct from A or (select count(*) from crm.contrato_cuenta_pago_cambios) <> n then
    raise exception 'FALLO: un respaldo rechazado dejó cambios';
  end if;
  raise notice 'OK respaldos: el superadmin cambia; un correo ya usado, subido por otro admin o que no es PDF/imagen se rechaza';
end;
$respaldos$;

-- ── H. anon no ejecuta nada ─────────────────────────────────────────────────────────────────
set local role anon;
do $anon$
begin
  begin
    perform crm.cambiar_cuenta_pago_contratos(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo largo', 'x');
    raise exception 'FALLO: anon pudo ejecutar el cambio';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.contratos_cuenta_pago_cliente_fn(gen_random_uuid());
    raise exception 'FALLO: anon pudo leer las cuentas de pago';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.reclamar_aviso_cambio_cuenta(gen_random_uuid(), gen_random_uuid(), true);
    raise exception 'FALLO: anon pudo reclamar un aviso';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK anon: 42501 en cambio, lectura y aviso';
end;
$anon$;
reset role;

-- ── I. Storage ──────────────────────────────────────────────────────────────────────────────
do $storage$
declare n integer; total integer;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-00000000000c.png',
          'e7b10000-0000-4000-8000-000000000001', '{"size": 10, "mimetype": "image/png"}');
  begin
    insert into storage.objects (bucket_id, name) values ('respaldos-cambio-cuenta', 'nombre-libre.pdf');
    raise exception 'FALLO: admin subió con nombre inválido';
  exception when insufficient_privilege then null;
  end;
  update storage.objects set metadata = '{}' where bucket_id = 'respaldos-cambio-cuenta';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO: se pudo sustituir un respaldo'; end if;
  -- Storage además prohíbe todo borrado directo (storage.protect_delete); cualquiera de los
  -- dos candados vale: lo que importa es que no se borre nada.
  begin
    delete from storage.objects where bucket_id = 'respaldos-cambio-cuenta';
    get diagnostics n = row_count;
    if n <> 0 then raise exception 'FALLO: se pudo borrar un respaldo'; end if;
  exception when others then
    if sqlerrm like 'FALLO:%' then raise; end if;
  end;
  execute 'reset role';
  select count(*) into total from storage.objects where bucket_id = 'respaldos-cambio-cuenta';
  if pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000001') <> total
     or pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000004') <> total then
    raise exception 'FALLO: admin y superadmin debían leer los % respaldos', total;
  end if;
  if pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000002') <> 0
     or pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000007') <> 0
     or pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000005') <> 0
     or pg_temp.respaldos_visibles('anon') <> 0 then
    raise exception 'FALLO: operaciones, un admin revocado, el cliente o anon leyeron respaldos';
  end if;
  foreach n in array array[2, 7] loop
    perform set_config('request.jwt.claims', json_build_object('sub', format('e7b10000-0000-4000-8000-00000000000%s', n), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      insert into storage.objects (bucket_id, name) values ('respaldos-cambio-cuenta',
        'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-0000000000d0.pdf');
      execute 'reset role';
      raise exception 'FALLO: el usuario % subió un respaldo', n;
    exception when insufficient_privilege then execute 'reset role';
    end;
  end loop;
  raise notice 'OK storage: admin y superadmin suben y leen con nombre válido; nadie sustituye ni borra; operaciones, admin revocado, cliente y anon ni leen ni suben';
end;
$storage$;

-- Fronteras: aunque otra política permisiva abriera TODO storage.objects, este bucket sigue cerrado.
savepoint fronteras;
create policy f3_prueba_abierta_anon on storage.objects for select to anon using (true);
create policy f3_prueba_abierta_auth_select on storage.objects for select to authenticated using (true);
create policy f3_prueba_abierta_auth_update on storage.objects for update to authenticated using (true) with check (true);
create policy f3_prueba_abierta_auth_insert on storage.objects for insert to authenticated with check (true);
do $fronteras$
declare n integer;
begin
  if pg_temp.respaldos_visibles('anon') <> 0
     or pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000002') <> 0 then
    raise exception 'FALLO: una política abierta de otro bucket dejó leer respaldos a anon u operaciones';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  update storage.objects set metadata = '{}' where bucket_id = 'respaldos-cambio-cuenta';
  get diagnostics n = row_count;
  execute 'reset role';
  if n <> 0 then raise exception 'FALLO: una política abierta dejó sustituir un respaldo'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into storage.objects (bucket_id, name) values ('respaldos-cambio-cuenta',
      'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-0000000000d1.pdf');
    execute 'reset role';
    raise exception 'FALLO: una política abierta dejó subir a operaciones';
  exception when insufficient_privilege then execute 'reset role';
  end;
  raise notice 'OK fronteras: con políticas abiertas de otro bucket, anon y operaciones siguen sin leer ni subir y nadie sustituye';
end $fronteras$;
rollback to savepoint fronteras;

-- ── Mutantes ─────────────────────────────────────────────────────────────────────────────────
-- M1: el núcleo sin la compuerta → Operaciones cambiaría la cuenta (con un respaldo suyo).
savepoint m1;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  'if not coalesce(private.admin_banca_vigente(v_actor), false) then', 'if false then');
do $m1$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000002', 'e7b1a000-0000-4000-8000-0000000000a1',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000008.pdf'),
    'OK:', 'MUTANTE 1 NO CAZADO');
  raise notice 'OK mutante 1 cazado (sin compuerta, Operaciones cambiaría la cuenta)';
end $m1$;
rollback to savepoint m1;

-- M1b: la compuerta sin P04 → un admin con la membresía CRM revocada cambiaría la cuenta.
savepoint m1b;
select pg_temp.mutar('private.admin_banca_vigente(uuid)', 'e.perfil_id = p_uid and e.activo is false', 'false');
do $m1b$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000007', 'e7b1a000-0000-4000-8000-0000000000b1',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000009.pdf'),
    'OK:', 'MUTANTE 1b NO CAZADO');
  raise notice 'OK mutante 1b cazado (sin P04, un admin revocado cambiaría la cuenta)';
end $m1b$;
rollback to savepoint m1b;

-- M2: el candado sin exigir historial → el enlace cambiaría a mano.
savepoint m2;
select pg_temp.mutar('private.trg_contrato_cuenta_pago_inmutable()',
  'if new.cuenta_bancaria_id is distinct from old.cuenta_bancaria_id', 'if false');
do $m2$ declare cazado boolean := false; begin
  begin
    update crm.contrato_cuentas_pago set cuenta_bancaria_id = 'e7b1c000-0000-4000-8000-000000000002'
     where contrato_id = 'e7b1d000-0000-4000-8000-000000000002';
    cazado := true;
  exception when sqlstate '22023' then cazado := false;
  end;
  if not cazado then raise exception 'MUTANTE 2 NO CAZADO'; end if;
  raise notice 'OK mutante 2 cazado (sin exigir historial, el enlace cambiaría a mano)';
end $m2$;
rollback to savepoint m2;

-- M3: el núcleo sin comprobar el tipo del archivo → un texto valdría como respaldo.
savepoint m3;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  $r$or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then$r$, 'then');
do $m3$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000001', 'e7b1a000-0000-4000-8000-0000000000a3',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000007.pdf'),
    'OK:', 'MUTANTE 3 NO CAZADO');
  raise notice 'OK mutante 3 cazado (sin comprobar el tipo, un texto valdría como respaldo)';
end $m3$;
rollback to savepoint m3;

-- M3b: el núcleo sin comprobar quién subió el respaldo → valdría el archivo de otro admin.
savepoint m3b;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  'if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then', 'if false then');
do $m3b$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000001', 'e7b1a000-0000-4000-8000-0000000000b3',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000006.pdf'),
    'OK:', 'MUTANTE 3b NO CAZADO');
  raise notice 'OK mutante 3b cazado (sin comprobar quién subió el respaldo, valdría el de otro admin)';
end $m3b$;
rollback to savepoint m3b;

-- M3c: el núcleo sin impedir reutilizar el respaldo → un mismo correo respaldaría dos cambios.
savepoint m3c;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  'where c.respaldo_ruta = p_respaldo_ruta and c.solicitud_id <> p_solicitud_id', 'where false');
do $m3c$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000001', 'e7b1a000-0000-4000-8000-0000000000c3',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000001.pdf'),
    'OK:', 'MUTANTE 3c NO CAZADO');
  raise notice 'OK mutante 3c cazado (sin impedir reutilizar, un correo respaldaría dos cambios)';
end $m3c$;
rollback to savepoint m3c;

-- M4: el sello no sella → la cuota pagada no guardaría su cuenta.
savepoint m4;
create or replace function private.sellar_cuenta_cuota_pagada() returns trigger
language plpgsql security definer set search_path to '' as $m$ begin return null; end; $m$;
update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy()
 where id = 'e7b1e000-0000-4000-8000-000000000003';
do $m4$ begin
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000003') is not null then
    raise exception 'MUTANTE 4 NO CAZADO';
  end if;
  raise notice 'OK mutante 4 cazado (sin sello, la cuota pagada no guardaría su cuenta)';
end $m4$;
rollback to savepoint m4;

-- M5: confirmar sella aunque falte un canal → el aviso a medias se daría por hecho.
savepoint m5;
select pg_temp.mutar('crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)',
  'v_completo := v_aviso.novedad_en is not null', 'v_completo := true or v_aviso.novedad_en is not null');
do $m5$ declare v jsonb; S5 constant uuid := 'e7b1a000-0000-4000-8000-000000000005'; begin
  v := pg_temp.reclamar(S5, 'e7b10000-0000-4000-8000-000000000001');
  v := pg_temp.confirmar(S5, (v->>'reserva')::uuid, true, false, 'correo caído');
  if not coalesce((v->>'completo')::boolean, false) then
    raise exception 'MUTANTE 5 NO CAZADO';
  end if;
  raise notice 'OK mutante 5 cazado (sellar a medias daría por avisado a quien no recibió el correo)';
end $m5$;
rollback to savepoint m5;

-- M6: confirmar sin exigir el token → un intento viejo liberaría la reserva de uno nuevo.
savepoint m6;
select pg_temp.mutar('crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)',
  'and reserva = p_reserva', '');
do $m6$ declare v jsonb; S5 constant uuid := 'e7b1a000-0000-4000-8000-000000000005'; begin
  perform pg_temp.reclamar(S5, 'e7b10000-0000-4000-8000-000000000001');
  v := pg_temp.confirmar(S5, gen_random_uuid(), true, true);
  if v ? 'error' then
    raise exception 'MUTANTE 6 NO CAZADO';
  end if;
  raise notice 'OK mutante 6 cazado (sin token, cualquier intento confirmaría y liberaría la reserva)';
end $m6$;
rollback to savepoint m6;

-- M7: reclamar sin exigir el rol del servicio → el dueño lo correría con otra sesión.
savepoint m7;
select pg_temp.mutar('crm.reclamar_aviso_cambio_cuenta(uuid,uuid,boolean)',
  $r$if (select auth.role()) is distinct from 'service_role' then$r$, 'if false then');
do $m7$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  perform crm.reclamar_aviso_cambio_cuenta('e7b1a000-0000-4000-8000-000000000005', 'e7b10000-0000-4000-8000-000000000001', true);
  raise notice 'OK mutante 7 cazado (sin exigir service_role, reclamar correría con cualquier sesión)';
exception when insufficient_privilege then
  raise exception 'MUTANTE 7 NO CAZADO';
end $m7$;
rollback to savepoint m7;

-- M8: sin la frontera de anon → una política abierta de otro bucket le dejaría leer respaldos.
savepoint m8;
drop policy respaldo_cambio_cuenta_anon_frontera on storage.objects;
create policy f3_prueba_abierta_anon on storage.objects for select to anon using (true);
do $m8$ begin
  if pg_temp.respaldos_visibles('anon') = 0 then raise exception 'MUTANTE 8 NO CAZADO'; end if;
  raise notice 'OK mutante 8 cazado (sin frontera, anon leería respaldos por otra política)';
end $m8$;
rollback to savepoint m8;

-- M9: sin la frontera de lectura → una política abierta dejaría leer respaldos a Operaciones.
savepoint m9;
drop policy respaldo_cambio_cuenta_select_frontera on storage.objects;
create policy f3_prueba_abierta_auth_select on storage.objects for select to authenticated using (true);
do $m9$ begin
  if pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000002') = 0 then
    raise exception 'MUTANTE 9 NO CAZADO';
  end if;
  raise notice 'OK mutante 9 cazado (sin frontera, Operaciones leería respaldos por otra política)';
end $m9$;
rollback to savepoint m9;

select 'CAMBIO_CUENTA_OK' as veredicto;
rollback;
```

## Reversa — CRM-Avance-Corp/supabase/scripts/cuentas-gloria/reversa-cambio-cuenta-pago.sql
```sql
-- REVERSA de 20260926204051_crm_cambio_cuenta_pago (F3.1).
-- Se NIEGA si ya hay cambios de cuenta registrados (desde ese momento el historial es la única
-- verdad de a dónde se paga cada contrato) o si las piezas vivas no son las ensayadas (huella
-- completa de las 16 funciones: cuerpo, DEFINER, search_path, comentario y EXECUTE sin el dueño).
-- Repone el candado original del enlace contrato→cuenta byte a byte (huella 349a5a7f…).
-- El bucket 'respaldos-cambio-cuenta' se conserva (Storage no permite borrar buckets ni objetos
-- por SQL); sin sus políticas queda cerrado para todo usuario de la API.
begin;
set local lock_timeout = '5s';
do $pre$
declare
  v_funciones integer;
  v_huella text;
begin
  if to_regclass('crm.contrato_cuenta_pago_cambios') is null then
    raise exception 'REVERSA: la F3.1 no está aplicada';
  end if;
  if exists (select 1 from crm.contrato_cuenta_pago_cambios) then
    raise exception 'REVERSA: ya hay cambios de cuenta de pago registrados; no se revierte a ciegas';
  end if;
  select count(*), pg_catalog.md5(pg_catalog.string_agg(linea, E'\n' order by linea))
    into v_funciones, v_huella
  from (
    select p.oid::regprocedure::text || '|' || pg_catalog.md5(p.prosrc) || '|' || p.prosecdef::text || '|'
           || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '-') || '|'
           || coalesce(pg_catalog.md5(pg_catalog.obj_description(p.oid, 'pg_proc')), '-') || '|'
           || coalesce((select pg_catalog.string_agg(g, ',' order by g)
                        from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                                     || ':' || a.privilege_type as g
                              from pg_catalog.aclexplode(p.proacl) a
                              where a.grantee <> p.proowner) acl), '-') as linea
    from pg_catalog.pg_proc p
    where p.oid in (
      select to_regprocedure(f) from pg_catalog.unnest(array[
        'private.admin_banca_vigente(uuid)',
        'private.trg_registro_cuenta_pago_no_borrar()',
        'private.trg_contrato_cuenta_pago_cambios_inmutable()',
        'private.trg_cuotas_cuenta_pagada_solo_resello()',
        'private.sellar_cuenta_cuota_pagada()',
        'private.trg_contrato_cuenta_pago_inmutable()',
        'private.respaldo_cambio_cuenta_permitido(text)',
        'private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
        'crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)',
        'private.contratos_cuenta_pago_cliente_autorizado(uuid)',
        'crm.contratos_cuenta_pago_cliente_fn(uuid)',
        'private.cambios_cuenta_pago_cliente_autorizado(uuid)',
        'crm.cambios_cuenta_pago_cliente_fn(uuid)',
        'private.contratos_vigentes_de_cambio(uuid)',
        'crm.reclamar_aviso_cambio_cuenta(uuid,uuid,boolean)',
        'crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)']) f)
  ) s;
  if v_funciones <> 16 or v_huella is distinct from 'e60bfdfc928832449b69c8425e633bbe' then
    raise exception 'REVERSA: las piezas vivas no son las de la F3.1 ensayada (% funciones, huella %); no se toca',
      v_funciones, v_huella;
  end if;
end $pre$;

-- Políticas del bucket (el bucket NO se borra por SQL: storage.protect_delete lo impide; sin
-- políticas queda cerrado; si hace falta, se elimina vacío desde el panel de Storage).
drop policy respaldo_cambio_cuenta_insert on storage.objects;
drop policy respaldo_cambio_cuenta_select on storage.objects;
drop policy respaldo_cambio_cuenta_insert_frontera on storage.objects;
drop policy respaldo_cambio_cuenta_select_frontera on storage.objects;
drop policy respaldo_cambio_cuenta_update_frontera on storage.objects;
drop policy respaldo_cambio_cuenta_delete_frontera on storage.objects;
drop policy respaldo_cambio_cuenta_anon_frontera on storage.objects;

-- Sello en public.cronograma_pagos.
drop trigger trg_cronograma_pagos_20_sellar_cuenta_insert on public.cronograma_pagos;
drop trigger trg_cronograma_pagos_20_sellar_cuenta_update on public.cronograma_pagos;

-- Operación, lecturas y aviso.
drop function crm.confirmar_aviso_cambio_cuenta(uuid, uuid, boolean, boolean, text);
drop function crm.reclamar_aviso_cambio_cuenta(uuid, uuid, boolean);
drop function private.contratos_vigentes_de_cambio(uuid);
drop function crm.cambios_cuenta_pago_cliente_fn(uuid);
drop function private.cambios_cuenta_pago_cliente_autorizado(uuid);
drop function crm.contratos_cuenta_pago_cliente_fn(uuid);
drop function private.contratos_cuenta_pago_cliente_autorizado(uuid);
drop function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text);
drop function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text);
drop function private.respaldo_cambio_cuenta_permitido(text);
drop function private.sellar_cuenta_cuota_pagada();

-- Candado original del enlace (antes de retirar el historial al que la versión F3 consulta).
create or replace function private.trg_contrato_cuenta_pago_inmutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if row(new.id, new.contrato_id, new.cuenta_bancaria_id, new.creado_en)
     is distinct from
     row(old.id, old.contrato_id, old.cuenta_bancaria_id, old.creado_en) then
    raise exception using
      errcode = '22023',
      message = 'La cuenta de pago del contrato es historica y no se reemplaza';
  end if;
  if new.creado_por is distinct from old.creado_por
     and not (
       new.creado_por is null
       and old.creado_por is not null
       and not exists (select 1 from public.perfiles p where p.id = old.creado_por)
     ) then
    raise exception using errcode = '22023', message = 'La autoria del enlace bancario es inmutable';
  end if;
  return new;
end;
$$;
comment on function private.trg_contrato_cuenta_pago_inmutable() is null;

-- Registros (sus triggers se van con ellos) y sus candados.
drop table crm.cambio_cuenta_avisos;
drop table crm.contrato_cuenta_pago_cambios;
drop table crm.cuotas_cuenta_pagada;
drop function private.trg_registro_cuenta_pago_no_borrar();
drop function private.trg_contrato_cuenta_pago_cambios_inmutable();
drop function private.trg_cuotas_cuenta_pagada_solo_resello();
drop function private.admin_banca_vigente(uuid);

do $chk$
begin
  if (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
      where oid = 'private.trg_contrato_cuenta_pago_inmutable()'::regprocedure)
     is distinct from '349a5a7f9a52283c5331aea6d90967f9' then
    raise exception 'REVERSA: el candado repuesto no es el original';
  end if;
  if exists (select 1 from pg_catalog.pg_policies where schemaname = 'storage' and policyname like 'respaldo\_cambio\_cuenta\_%')
     or exists (select 1 from pg_catalog.pg_trigger where tgrelid = 'public.cronograma_pagos'::regclass
                and tgname like 'trg\_cronograma\_pagos\_20\_sellar\_cuenta\_%')
     or to_regprocedure('private.admin_banca_vigente(uuid)') is not null then
    raise exception 'REVERSA: quedaron piezas de la F3.1';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;
```

## Edge — _supabase_functions/functions/notificar-cambio-cuenta/index.ts
```ts
/**
 * Edge Function: notificar-cambio-cuenta (F3.3, 26/09/2026)
 *
 * Avisa al cliente que su cuenta de pago cambió (por su pedido), por 2 canales:
 *   1) Novedad in-portal (tabla `novedades`) → badge en vivo.
 *   2) Correo (Resend) con la plantilla institucional.
 *
 * Lo invoca el panel admin (ventana «Cuentas») justo después de
 * `crm.cambiar_cuenta_pago_contratos`, con `{ solicitud_id }`.
 *
 * Dos pasos (nada se da por avisado sin haber salido):
 *   1) `crm.reclamar_aviso_cambio_cuenta` reserva el envío (10 min, con token) y dice qué
 *      canales faltan. Un doble clic recibe `en_curso`; un aviso ya completo, `ya_notificada`;
 *      un cambio superado por otro posterior, `superada` (no se avisa una cuenta que ya no rige).
 *   2) Se envía SOLO lo pendiente y `crm.confirmar_aviso_cambio_cuenta` (con el token) registra
 *      lo que de verdad salió. El historial queda «avisado» solo con todos los canales
 *      entregados; si algo falló, el botón «Enviar aviso» reintenta únicamente lo que faltó.
 * `dry_run: true` devuelve el texto que se enviaría, sin reservar ni enviar.
 *
 * verify_jwt: TRUE (la puerta de Supabase exige un JWT válido); aquí dentro solo pasan
 * admin/superadmin activos, y la base vuelve a exigirlo para el actor (`p_actor`), incluida la
 * membresía CRM no revocada (P04): si la niega, 403.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { plantillaEmail, redactarAviso } from './aviso.ts'

const ALLOWED_ORIGINS = new Set([
  'https://miavance.com',
  'https://www.miavance.com',
])

function corsHeaders(req: Request) {
  const origin = req.headers.get('Origin') || ''
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : 'https://miavance.com',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

function json(cors: Record<string, string>, payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

Deno.serve(async (req) => {
  const cors = corsHeaders(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json(cors, { error: 'Método no permitido' }, 405)

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    /* ---------- AUTENTICACIÓN: solo admin/superadmin activos ---------- */
    const token = req.headers.get('Authorization')?.replace('Bearer ', '')
    if (!token) return json(cors, { error: 'No autorizado' }, 401)
    const { data: { user } } = await supabase.auth.getUser(token)
    if (!user) return json(cors, { error: 'No autorizado' }, 401)
    const { data: perfil } = await supabase
      .from('perfiles').select('rol, activo').eq('id', user.id).single()
    if (!perfil?.activo || !['admin', 'superadmin'].includes(perfil.rol)) {
      return json(cors, { error: 'No autorizado' }, 403)
    }

    const body = await req.json().catch(() => ({}))
    const solicitudId: string = body?.solicitud_id
    const dryRun: boolean = body?.dry_run === true
    if (typeof solicitudId !== 'string' || !UUID.test(solicitudId)) {
      return json(cors, { error: 'solicitud_id inválido' }, 400)
    }

    /* ---------- PASO 1: RESERVA + DATOS ---------- */
    const crm = supabase.schema('crm')
    const { data: datos, error: errClaim } = await crm.rpc('reclamar_aviso_cambio_cuenta', {
      p_solicitud_id: solicitudId, p_actor: user.id, p_dry_run: dryRun,
    })
    if (errClaim?.code === '42501') return json(cors, { error: 'No autorizado' }, 403)
    if (errClaim) throw errClaim
    if (!datos?.encontrada) return json(cors, { error: 'Cambio no encontrado' }, 404)
    if (datos.ya_notificada) return json(cors, { success: true, ya_notificada: true })
    if (datos.superada) return json(cors, { success: false, superada: true })
    if (datos.en_curso) return json(cors, { success: false, en_curso: true })

    const { titulo, mensaje } = redactarAviso(datos)
    if (dryRun) return json(cors, { success: true, dry_run: true, correo: datos.correo, titulo, mensaje })

    const confirmar = async (novedad: boolean, correo: boolean, error: string | null) => {
      const { data, error: errConf } = await crm.rpc('confirmar_aviso_cambio_cuenta', {
        p_solicitud_id: solicitudId, p_reserva: datos.reserva,
        p_novedad: novedad, p_correo: correo, p_error: error,
      })
      if (errConf) throw errConf
      return data
    }

    if (!datos.activo) {
      const estado = await confirmar(false, false, 'Cliente inactivo: no se envió el aviso')
      return json(cors, { success: false, ...estado, detalle: 'Cliente inactivo' })
    }

    /* ---------- PASO 2: ENVÍO DE LO PENDIENTE ---------- */
    const errores: string[] = []
    let novedadAhora = false
    if (datos.pendiente_novedad) {
      const { error: errNov } = await supabase.from('novedades').insert({
        titulo, mensaje, destinatario_id: datos.cliente_id, enviado_por: null,
      })
      if (errNov) {
        errores.push('No se pudo publicar el aviso en el portal')
        console.warn('[notificar-cambio-cuenta] novedad falló:', errNov.message)
      } else {
        novedadAhora = true
      }
    }

    let correoAhora = false
    if (datos.pendiente_correo) {
      try {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: 'Avance Corp <info@miavance.com>',
            to: [datos.correo],
            subject: titulo,
            html: plantillaEmail(datos.nombre_completo || 'estimado cliente', titulo, mensaje),
          }),
        })
        correoAhora = res.ok
        if (!res.ok) errores.push(`El correo no se pudo enviar (Resend ${res.status})`)
      } catch (e) {
        errores.push('El correo no se pudo enviar')
        console.warn('[notificar-cambio-cuenta] correo falló:', e)
      }
    }

    const estado = await confirmar(novedadAhora, correoAhora, errores.length ? errores.join('; ') : null)
    return json(cors, { success: estado?.completo === true, ...estado })
  } catch (error) {
    console.error('[notificar-cambio-cuenta] error:', error)
    return json(cors, { error: 'No se pudo enviar el aviso' }, 500)
  }
})
```

## Edge — _supabase_functions/functions/notificar-cambio-cuenta/aviso.ts
```ts
// Texto del aviso al cliente por un cambio de su cuenta de pago (F3.3, 26/09/2026).
// Puro y sin red: lo prueba aviso.test.ts. La cuenta nueva va TAPADA (••••1234); si es de
// un tercero, el aviso dice a nombre de quién está.

export type DatosAviso = {
  nombre_completo: string | null
  nombres: string | null
  banco_nuevo: string
  moneda: string
  ultimos_nuevo: string
  titular_distinto?: boolean
  beneficiario_nombre?: string | null
  contratos: string[]
  cambiado_en: string
}

// Fecha del cambio en hora de Lima: «26 de septiembre de 2026».
export function fechaLima(iso: string): string {
  const [y, m, d] = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date(iso)).split('-').map(Number)
  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
  return `${d} de ${meses[m - 1]} de ${y}`
}

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

export function redactarAviso(d: DatosAviso): { titulo: string; mensaje: string } {
  const nombrePila = (d.nombres || d.nombre_completo || 'estimado cliente').split(' ')[0]
  const moneda = d.moneda === 'USD' ? 'dólares' : 'soles'
  const lista = d.contratos.length === 1
    ? `del contrato ${d.contratos[0]}`
    : `de los contratos ${d.contratos.slice(0, -1).join(', ')} y ${d.contratos[d.contratos.length - 1]}`
  const cuenta = d.titular_distinto
    ? `la cuenta ${d.banco_nuevo} en ${moneda} terminada en ••••${d.ultimos_nuevo}, a nombre de ${d.beneficiario_nombre || 'la persona que indicaste'}`
    : `tu cuenta ${d.banco_nuevo} en ${moneda} terminada en ••••${d.ultimos_nuevo}`
  const titulo = 'Cambio de tu cuenta de pago'
  const mensaje = `Hola ${nombrePila}, atendimos tu pedido: desde el ${fechaLima(d.cambiado_en)}, los pagos ${lista} se depositan en ${cuenta}. Los pagos ya realizados no cambian.\n\nSi tú no solicitaste este cambio, comunícate de inmediato con Avance Corp.`
  return { titulo, mensaje }
}

export function plantillaEmail(nombre: string, titulo: string, mensaje: string): string {
  const nombreEsc = escapeHtml(nombre)
  const tituloEsc = escapeHtml(titulo)
  const mensajeEsc = escapeHtml(mensaje).replace(/\n/g, '<br>')
  const preheader = escapeHtml(mensaje.slice(0, 110).replace(/\s+/g, ' ').trim())
  const etiqueta = 'CAMBIO DE CUENTA DE PAGO'

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="x-apple-disable-message-reformatting">
<title>${tituloEsc}</title>
</head>
<body style="margin:0;padding:0;background:#f4f2ec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">
  <div style="display:none;font-size:1px;color:#f4f2ec;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">${preheader}</div>
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ec;padding:32px 16px;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;max-width:600px;width:100%;border:1px solid #e8e3d4;">
        <tr>
          <td style="background:#0a0e1a;padding:36px 48px;text-align:center;border-bottom:3px solid #c9a96e;">
            <img src="https://miavance.com/img/avance-logo-full.png" alt="Avance Corp" width="180" style="display:block;margin:0 auto;max-width:180px;height:auto;">
            <div style="font-size:10px;color:#c9a96e;margin-top:14px;letter-spacing:0.22em;font-weight:600;">${etiqueta}</div>
          </td>
        </tr>
        <tr>
          <td style="padding:40px 48px 0;">
            <p style="margin:0;font-size:13px;color:#8a8780;letter-spacing:0.04em;">Estimado(a)</p>
            <p style="margin:4px 0 0;font-size:18px;color:#1a1f2e;font-weight:600;">${nombreEsc}</p>
          </td>
        </tr>
        <tr>
          <td style="padding:28px 48px 0;">
            <div style="width:32px;height:2px;background:#c9a96e;margin-bottom:18px;"></div>
            <h1 style="margin:0;font-size:24px;color:#0a0e1a;font-weight:700;line-height:1.3;letter-spacing:-0.01em;">${tituloEsc}</h1>
          </td>
        </tr>
        <tr>
          <td style="padding:24px 48px 0;">
            <p style="margin:0;font-size:15px;color:#3a3f4e;line-height:1.75;">${mensajeEsc}</p>
          </td>
        </tr>
        <tr>
          <td style="padding:36px 48px 8px;">
            <table cellpadding="0" cellspacing="0"><tr>
              <td style="background:#0a0e1a;">
                <a href="https://miavance.com" style="display:inline-block;padding:14px 32px;color:#c9a96e;text-decoration:none;font-size:13px;font-weight:700;letter-spacing:0.12em;text-transform:uppercase;border:1px solid #c9a96e;">Ingresar al portal</a>
              </td>
            </tr></table>
          </td>
        </tr>
        <tr>
          <td style="background:#0a0e1a;padding:32px 48px;margin-top:24px;">
            <div style="font-size:13px;color:#c9a96e;font-weight:700;letter-spacing:0.06em;margin-bottom:6px;">AVANCE CORP S.A.C.</div>
            <div style="font-size:11px;color:#8a8a8a;line-height:1.7;">
              RUC 20611392088<br>San Isidro · Lima · Per&uacute;<br>
              <a href="mailto:info@miavance.com" style="color:#c9a96e;text-decoration:none;">info@miavance.com</a> &nbsp;·&nbsp;
              <a href="https://miavance.com" style="color:#c9a96e;text-decoration:none;">miavance.com</a>
            </div>
            <div style="font-size:10px;color:#5a5a5a;line-height:1.6;padding-top:16px;margin-top:16px;border-top:1px solid #1a1f2e;">
              Recibiste este correo porque eres cliente de Avance Corp S.A.C. Comunicaci&oacute;n institucional automatizada.
            </div>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`
}
```

## Pantalla — public_html/js/admin/cambio-cuenta-core.js (íntegro)
```js
// Cambio de la cuenta de pago de contratos por pedido del cliente (F3, 26/09/2026).
// Núcleo puro de la ventana «Cuentas»: validaciones, contratos elegibles, ruta del
// respaldo (el correo del cliente) y textos. Sin DOM ni red: lo prueba
// tests/cambio-cuenta-core.test.mjs. La frontera real está en el servidor
// (crm.cambiar_cuenta_pago_contratos): esto solo da buena experiencia.

export const BUCKET_RESPALDOS = 'respaldos-cambio-cuenta'
export const MAX_RESPALDO_BYTES = 10 * 1024 * 1024
const TIPOS = { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png' }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function puedeCambiarCuentaPago(rol) {
  return rol === 'admin' || rol === 'superadmin'
}

export function validarRespaldo(archivo) {
  if (!archivo) return 'Adjunta el correo del cliente donde pide el cambio (PDF o imagen).'
  if (!TIPOS[archivo.type]) return 'El respaldo debe ser PDF, JPG o PNG.'
  if (!(archivo.size > 0)) return 'El archivo del respaldo está vacío.'
  if (archivo.size > MAX_RESPALDO_BYTES) return 'El respaldo no puede superar 10 MB.'
  return null
}

// Misma forma que exige el servidor: <cliente_uuid>/<uuid>.(pdf|jpg|png)
export function rutaRespaldo(clienteId, archivoId, archivo) {
  if (!UUID.test(String(clienteId)) || !UUID.test(String(archivoId))) {
    throw new Error('Identificadores inválidos para el respaldo.')
  }
  const extension = TIPOS[archivo?.type]
  if (!extension) throw new Error('El respaldo debe ser PDF, JPG o PNG.')
  return `${String(clienteId).toLowerCase()}/${String(archivoId).toLowerCase()}.${extension}`
}

// Contratos que pueden pasar a la cuenta nueva: misma moneda, con cuenta de pago y que no
// cobren ya en ella. Los demás se muestran pero no se pueden marcar.
export function contratosElegibles(contratos, cuentaNueva) {
  if (!cuentaNueva) return []
  return contratos.filter((c) => c.moneda === cuentaNueva.moneda
    && c.cuenta_bancaria_id
    && c.cuenta_bancaria_id !== cuentaNueva.id)
}

export function motivoNoElegible(contrato, cuentaNueva) {
  if (!contrato.cuenta_bancaria_id) return 'sin cuenta de pago (requiere conciliación)'
  if (!cuentaNueva) return ''
  if (contrato.moneda !== cuentaNueva.moneda) return `es en ${contrato.moneda}`
  if (contrato.cuenta_bancaria_id === cuentaNueva.id) return 'ya cobra en esa cuenta'
  return ''
}

export function validarCambio({ cuentaNueva, contratoIds, motivo, archivo }) {
  if (!cuentaNueva) return 'Elige la cuenta nueva.'
  if (!Array.isArray(contratoIds) || contratoIds.length === 0) return 'Marca al menos un contrato.'
  const texto = String(motivo ?? '').trim()
  if (texto.length < 5 || texto.length > 500) return 'Escribe el motivo del cambio (5 a 500 caracteres).'
  return validarRespaldo(archivo)
}

function fechaLima(valor) {
  if (!valor) return '—'
  const fecha = /^\d{4}-\d{2}-\d{2}$/.test(valor) ? new Date(`${valor}T12:00:00Z`) : new Date(valor)
  return fecha.toLocaleDateString('es-PE', {
    timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit'
  })
}

export function textoContrato(c) {
  const moneda = c.moneda === 'USD' ? 'Dólares' : 'Soles'
  const cuenta = c.cuenta_bancaria_id
    ? `cobra en ${c.banco} N° ${c.numero_cuenta}`
    : 'SIN cuenta de pago'
  const pendientes = Number(c.cuotas_pendientes) || 0
  const proximas = pendientes
    ? `${pendientes} cuota${pendientes === 1 ? '' : 's'} pendiente${pendientes === 1 ? '' : 's'} (próxima ${fechaLima(c.proxima_fecha)})`
    : 'sin cuotas pendientes'
  const pagadas = (Array.isArray(c.pagadas_por_cuenta) ? c.pagadas_por_cuenta : [])
    .map((p) => {
      // «inferidas»: cuotas pagadas antes de que existiera el sello; su cuenta se supone
      // (la del contrato al activarse el sello), no consta.
      const inferidas = Number(p.inferidas) || 0
      const nota = inferidas ? ` (${inferidas} sin constancia: se asume esta cuenta)` : ''
      return `${p.cuotas} en ${p.banco} N° ${p.numero_cuenta}${nota}`
    })
  const textoPagadas = pagadas.length ? ` · Pagadas: ${pagadas.join('; ')}` : ''
  return `${c.numero_contrato} · ${moneda} · ${cuenta} · ${proximas}${textoPagadas}`
}

const AVISO = {
  enviado: 'aviso enviado',
  superado: 'aviso no enviado: hubo un cambio posterior',
}

export function avisoPendiente(h) {
  return (h.aviso_estado || (h.notificado_en ? 'enviado' : 'pendiente')) === 'pendiente'
}

export function textoCambio(h) {
  const estado = h.aviso_estado || (h.notificado_en ? 'enviado' : 'pendiente')
  const aviso = AVISO[estado] || (h.aviso_error ? `aviso PENDIENTE (${h.aviso_error})` : 'aviso PENDIENTE')
  const por = h.cambiado_por_nombre ? ` · por ${h.cambiado_por_nombre}` : ''
  return `${fechaLima(h.cambiado_en)} · ${h.numero_contrato} · ${h.banco_anterior} N° ${h.numero_anterior} → ${h.banco_nuevo} N° ${h.numero_nuevo} · «${h.motivo}»${por} · ${aviso}`
}

// Tras cambiar: un Excel de Pagos exportado antes ya no vale para esos contratos (Pagos lo
// rechaza al importarlo); avisar a Operaciones evita que depositen a la cuenta vieja.
export function textoExitoCambio(n, aviso) {
  const cuantos = `${n} contrato${n === 1 ? '' : 's'}`
  const esos = n === 1 ? 'ese contrato' : 'esos contratos'
  return `Cuenta de pago cambiada en ${cuantos}. ${aviso} Avisa a Operaciones: un Excel de pagos exportado antes de este cambio ya no vale para ${esos}.`
}

// Traduce los errores del servidor sin inventar: sus mensajes ya son para personas.
export function mensajeErrorCambio(error) {
  if (!error) return 'No se pudo cambiar la cuenta de pago.'
  if (error.code === '42501') return 'Solo administración puede cambiar la cuenta de pago.'
  if (error.code === '22023' && error.message) return error.message
  return 'No se pudo cambiar la cuenta de pago. Recarga la ventana y vuelve a intentar.'
}

// Texto honesto del resultado del aviso: solo afirma lo que la Edge Function confirmó.
export function textoResultadoAviso(data, error) {
  if (error || !data) return 'No se pudo avisar al cliente: usa «Enviar aviso» en el historial.'
  if (data.ya_notificada) return 'El cliente ya había sido avisado.'
  if (data.superada) return 'No se envió el aviso: hubo un cambio posterior en esos contratos.'
  if (data.en_curso) return 'El aviso se está enviando; revisa el historial en un momento.'
  if (data.detalle === 'Cliente inactivo') return 'No se avisó: el cliente está inactivo.'
  if (data.completo) {
    return data.tiene_correo
      ? 'Se avisó al cliente en su portal y por correo.'
      : 'Se avisó al cliente en su portal (no tiene correo registrado).'
  }
  const portal = data.novedad ? 'portal ✓' : 'portal ✗'
  const correo = data.tiene_correo ? (data.correo ? 'correo ✓' : 'correo ✗') : 'sin correo registrado'
  return `Aviso incompleto (${portal}, ${correo}): usa «Enviar aviso» en el historial para reintentar.`
}
```

## Pantalla — extracto de public_html/js/admin/clientes.js (ventana «Cuentas», cambio y aviso)
```js
function actualizarBotonCambio() {
  const btn = document.getElementById('btnMostrarCambioPago')
  const listo = CAMBIO_PAGO.cuentasListas && CAMBIO_PAGO.contratosListos && !CAMBIO_GUARDANDO
  btn.disabled = !listo
  btn.title = listo ? '' : 'Cargando cuentas y contratos…'
}

function cargarPagoModal(clienteId, token) {
  const grupo = document.getElementById('cb_pago_group')
  grupo.classList.toggle('hidden', !PUEDE_CAMBIAR_CUENTA_PAGO)
  if (!PUEDE_CAMBIAR_CUENTA_PAGO) return
  const lista = document.getElementById('cb_contratos_pago')
  const cambios = document.getElementById('cb_cambios_pago')
  CAMBIO_PAGO.contratosListos = false
  actualizarBotonCambio()
  lista.textContent = 'Cargando contratos…'
  cambios.textContent = 'Cargando historial…'
  void supabase.schema('crm').rpc('contratos_cuenta_pago_cliente_fn', { p_cliente_id: clienteId })
    .then(({ data, error }) => {
      if (token !== CUENTAS_MODAL_TOKEN) return
      if (error || !Array.isArray(data)) {
        lista.textContent = 'No se pudieron cargar los contratos. Vuelve a abrir la ventana.'
        CAMBIO_PAGO.contratos = []
        CAMBIO_PAGO.contratosListos = false
        actualizarBotonCambio()
        return
      }
      CAMBIO_PAGO.contratos = data
      CAMBIO_PAGO.contratosListos = true
      actualizarBotonCambio()
      pintarLista(lista, data.map(textoContrato), 'Sin contratos abiertos.')
    })
  void supabase.schema('crm').rpc('cambios_cuenta_pago_cliente_fn', { p_cliente_id: clienteId })
    .then(({ data, error }) => {
      if (token !== CUENTAS_MODAL_TOKEN) return
      if (error || !Array.isArray(data)) {
        cambios.textContent = 'No se pudo cargar el historial de cambios.'
        return
      }
      pintarCambiosPago(cambios, data)
    })
}

function pintarLista(elemento, textos, vacio) {
  elemento.replaceChildren()
  if (textos.length === 0) {
    elemento.textContent = vacio
    return
  }
  const ul = document.createElement('ul')
  ul.style.margin = '6px 0 12px'
  ul.style.paddingLeft = '20px'
  for (const texto of textos) {
    const li = document.createElement('li')
    li.textContent = texto
    ul.appendChild(li)
  }
  elemento.appendChild(ul)
}

function pintarCambiosPago(elemento, cambios) {
  elemento.replaceChildren()
  if (cambios.length === 0) {
    elemento.textContent = 'Sin cambios de cuenta de pago.'
    return
  }
  const ul = document.createElement('ul')
  ul.style.margin = '6px 0 12px'
  ul.style.paddingLeft = '20px'
  const avisados = new Set()
  for (const h of cambios) {
    const li = document.createElement('li')
    li.appendChild(document.createTextNode(textoCambio(h) + ' '))
    const ver = document.createElement('button')
    ver.type = 'button'
    ver.className = 'btn-icon'
    ver.textContent = 'Ver correo'
    ver.addEventListener('click', () => verRespaldo(h.respaldo_ruta))
    li.appendChild(ver)
    // Un aviso por solicitud: el botón aparece una vez aunque la solicitud tenga varios contratos.
    if (avisoPendiente(h) && !avisados.has(h.solicitud_id)) {
      avisados.add(h.solicitud_id)
      const reenviar = document.createElement('button')
      reenviar.type = 'button'
      reenviar.className = 'btn-icon'
      reenviar.textContent = 'Enviar aviso'
      reenviar.addEventListener('click', () => void avisarCliente(h.solicitud_id, reenviar))
      li.appendChild(document.createTextNode(' '))
      li.appendChild(reenviar)
    }
    ul.appendChild(li)
  }
  elemento.appendChild(ul)
}

async function verRespaldo(ruta) {
  const { data, error } = await supabase.storage.from(BUCKET_RESPALDOS).createSignedUrl(ruta, 300)
  if (error || !data?.signedUrl) {
    mostrarError('No se pudo abrir el correo del cliente.')
    return
  }
  window.open(data.signedUrl, '_blank', 'noopener')
}

function abrirCambioPago() {
  if (CAMBIO_GUARDANDO || !CAMBIO_PAGO.cuentasListas || !CAMBIO_PAGO.contratosListos) return
  const errEl = document.getElementById('cb_cambio_error')
  errEl.classList.add('hidden')
  CAMBIO_PAGO.apertura += 1
  renovarSolicitud()
  CAMBIO_PAGO.archivoId = crypto.randomUUID()
  document.getElementById('cb_cambio_correo_cliente').textContent = CAMBIO_PAGO.correo
    ? `Correo registrado del cliente: ${CAMBIO_PAGO.correo}. Verifica que la solicitud venga de esa dirección.`
    : 'El cliente no tiene correo registrado: verifica bien el origen de la solicitud.'
  const select = document.getElementById('cb_cambio_cuenta')
  select.replaceChildren()
  const vacia = document.createElement('option')
  vacia.value = ''
  vacia.textContent = '— Elegir la cuenta nueva —'
  select.appendChild(vacia)
  for (const c of CAMBIO_PAGO.cuentas) {
    const opt = document.createElement('option')
    opt.value = c.id
    opt.textContent = `${c.moneda === 'USD' ? 'Dólares' : 'Soles'} · ${c.banco} · N° ${c.numero}`
    select.appendChild(opt)
  }
  document.getElementById('cb_cambio_respaldo').value = ''
  document.getElementById('cb_cambio_motivo').value = ''
  pintarContratosCambio()
  document.getElementById('cb_cambio_group').classList.remove('hidden')
  document.getElementById('btnMostrarCambioPago').classList.add('hidden')
}

function cerrarCambioPago() {
  if (CAMBIO_GUARDANDO) return
  document.getElementById('cb_cambio_group').classList.add('hidden')
  document.getElementById('btnMostrarCambioPago').classList.remove('hidden')
}

function cuentaNuevaElegida() {
  const id = document.getElementById('cb_cambio_cuenta').value
  return CAMBIO_PAGO.cuentas.find((c) => c.id === id) || null
}

// Por defecto quedan marcados todos los contratos elegibles; los demás se ven con su motivo.
function pintarContratosCambio() {
  const cont = document.getElementById('cb_cambio_contratos')
  cont.replaceChildren()
  const cuenta = cuentaNuevaElegida()
  if (!cuenta) {
    cont.textContent = 'Elige la cuenta nueva para ver qué contratos pueden pasar a ella.'
    return
  }
  const elegibles = new Set(contratosElegibles(CAMBIO_PAGO.contratos, cuenta).map((c) => c.contrato_id))
  if (elegibles.size === 0) {
    cont.textContent = 'Ningún contrato abierto puede pasar a esta cuenta.'
  }
  for (const c of CAMBIO_PAGO.contratos) {
    const label = document.createElement('label')
    label.style.display = 'flex'
    label.style.gap = '8px'
    label.style.alignItems = 'center'
    label.style.margin = '4px 0'
    const chk = document.createElement('input')
    chk.type = 'checkbox'
    chk.value = c.contrato_id
    chk.dataset.contratoCambio = '1'
    chk.style.width = 'auto'
    chk.style.margin = '0'
    const ok = elegibles.has(c.contrato_id)
    chk.checked = ok
    chk.disabled = !ok
    chk.addEventListener('change', renovarSolicitud)
    label.appendChild(chk)
    const motivo = ok ? '' : ` — no aplica: ${motivoNoElegible(c, cuenta)}`
    label.appendChild(document.createTextNode(`${textoContrato(c)}${motivo}`))
    cont.appendChild(label)
  }
}

async function confirmarCambioPago() {
  const errEl = document.getElementById('cb_cambio_error')
  errEl.classList.add('hidden')
  const btn = document.getElementById('btnConfirmarCambioPago')
  if (btn.disabled || CAMBIO_GUARDANDO) return
  // Todo lo de esta operación se fija AHORA: los await siguientes no leen estado global.
  const clienteId = CAMBIO_PAGO.clienteId
  const solicitudId = CAMBIO_PAGO.solicitudId
  const archivoId = CAMBIO_PAGO.archivoId
  const apertura = CAMBIO_PAGO.apertura
  const cuenta = cuentaNuevaElegida()
  const contratoIds = [...document.querySelectorAll('#cb_cambio_contratos input[data-contrato-cambio]:checked')]
    .map((chk) => chk.value)
  const motivo = document.getElementById('cb_cambio_motivo').value.trim()
  const archivo = document.getElementById('cb_cambio_respaldo').files?.[0] || null
  const falta = validarCambio({ cuentaNueva: cuenta, contratoIds, motivo, archivo })
  if (falta) {
    errEl.textContent = falta
    errEl.classList.remove('hidden')
    return
  }
  const sigueEnEsteCliente = () =>
    !document.getElementById('modalCuentas').classList.contains('hidden')
    && document.getElementById('cb_clienteId').value === clienteId
    && CAMBIO_PAGO.clienteId === clienteId
    && CAMBIO_PAGO.apertura === apertura
  CAMBIO_GUARDANDO = true
  actualizarBotonCambio()
  document.getElementById('btnCancelarCambioPago').disabled = true
  btn.disabled = true
  btn.textContent = 'Guardando…'
  let aplicado = false
  try {
    // 1) Respaldo al bucket privado. Si ya se subió en un intento anterior, se reutiliza.
    const ruta = rutaRespaldo(clienteId, archivoId, archivo)
    const subida = await supabase.storage.from(BUCKET_RESPALDOS)
      .upload(ruta, archivo, { contentType: archivo.type, upsert: false })
    if (subida.error && !/exist/i.test(subida.error.message || '')) {
      throw new Error('No se pudo subir el correo del cliente. Vuelve a intentar.')
    }
    // 2) El cambio (todo o nada, idempotente por solicitud).
    const { data, error } = await supabase.schema('crm').rpc('cambiar_cuenta_pago_contratos', {
      p_solicitud_id: solicitudId,
      p_cliente_id: clienteId,
      p_cuenta_nueva_id: cuenta.id,
      p_contrato_ids: contratoIds,
      p_motivo: motivo,
      p_respaldo_ruta: ruta,
    })
    if (error) throw new Error(mensajeErrorCambio(error))
    // 3) Aviso al cliente (portal + correo). El cambio ya está hecho aunque el aviso falle.
    const aviso = await avisarCliente(solicitudId, null)
    const n = Number(data?.contratos) || contratoIds.length
    mostrarExito(textoExitoCambio(n, aviso))
    aplicado = true
  } catch (error) {
    const mensaje = error?.message || 'No se pudo cambiar la cuenta de pago.'
    if (!sigueEnEsteCliente()) {
      mostrarError(mensaje)
      return
    }
    errEl.textContent = mensaje
    errEl.classList.remove('hidden')
  } finally {
    CAMBIO_GUARDANDO = false
    document.getElementById('btnCancelarCambioPago').disabled = false
    actualizarBotonCambio()
    btn.disabled = false
    btn.textContent = 'Confirmar cambio'
  }
  // Ya fuera del guardado (cerrar el formulario está bloqueado mientras guarda).
  if (aplicado && sigueEnEsteCliente()) {
    cerrarCambioPago()
    cargarPagoModal(clienteId, CUENTAS_MODAL_TOKEN)
  }
}

// Devuelve un texto para el aviso de éxito; con botón (reenvío) refresca el historial.
async function avisarCliente(solicitudId, boton) {
  if (boton) {
    boton.disabled = true
    boton.textContent = 'Enviando…'
  }
  let texto
  try {
    const { data, error } = await supabase.functions.invoke('notificar-cambio-cuenta', {
      body: { solicitud_id: solicitudId },
    })
    texto = textoResultadoAviso(data, error)
  } catch {
    texto = textoResultadoAviso(null, true)
  }
  if (boton) {
    mostrarExito(texto)
    if (CAMBIO_PAGO.clienteId) cargarPagoModal(CAMBIO_PAGO.clienteId, CUENTAS_MODAL_TOKEN)
  }
  return texto
}

```

## Pagos — diff de public_html/js/admin/pagos.js y cuentas-pago-core.js
```diff
diff --git a/js/admin/cuentas-pago-core.js b/js/admin/cuentas-pago-core.js
index bd58c16..1bb74d8 100644
--- a/js/admin/cuentas-pago-core.js
+++ b/js/admin/cuentas-pago-core.js
@@ -1,7 +1,8 @@
 /**
  * Reglas puras para resolver la cuenta de depósito de cada cuota.
  *
- * La cuenta de pago siempre es la cuenta inmutable vinculada al contrato.
+ * La cuenta de pago es la cuenta vinculada al contrato. Desde el 26/09/2026 (F3) solo
+ * cambia por pedido del cliente, con historial; lo ya pagado conserva su cuenta.
  * La ausencia de vínculo exige conciliación antes de pagar o exportar.
  */
 
@@ -135,3 +136,25 @@ export function cuentaPagoCompleta(cuenta) {
         || (texto(cuenta.beneficiario_nombre) && texto(cuenta.beneficiario_dni))),
   )
 }
+
+/**
+ * F3: un Excel exportado ANTES de cambiar la cuenta de pago del contrato trae la cuenta vieja;
+ * registrar ese pago dejaría constancia de la cuenta nueva sin que el dinero fuera allí.
+ * Compara solo dígitos (el formato de la celda no importa). Sin CCI en la fila → no opina.
+ */
+export function cuentaCambiadaDesdeExport(cuota) {
+  const exportado = String(cuota?.cci_excel ?? '').replace(/\D/g, '')
+  if (!exportado) return false
+  const actual = cuentaParaCuota(cuota)
+  return !actual || String(actual.cci ?? '').replace(/\D/g, '') !== exportado
+}
+
+// El Excel se importa DESPUÉS de depositar: nunca se pide volver a pagar. Un pago ya hecho se
+// registra a mano con su fecha real y el servidor lo atribuye a la cuenta vigente en esa fecha.
+export function mensajeCuentaCambiadaFila(cliente) {
+  return `${cliente}: la cuenta de pago de este contrato cambió después de exportar el Excel. No vuelvas a depositar: si ya depositaste con este Excel, registra ese pago a mano con su fecha real; si aún no, vuelve a exportarlo.`
+}
+
+export function mensajeCuentaCambiadaLote(n) {
+  return `La cuenta de pago cambió después de exportar el Excel en ${n} fila${n === 1 ? '' : 's'}. No vuelvas a depositar: registra a mano, con su fecha real, los pagos que ya hiciste con este Excel; para los que falten, vuelve a exportarlo.`
+}
diff --git a/js/admin/pagos.js b/js/admin/pagos.js
index 58b2824..7803791 100644
--- a/js/admin/pagos.js
+++ b/js/admin/pagos.js
@@ -29,7 +29,10 @@ import {
   asociarCuentasPagoPantalla,
   cuentaPagoCompleta,
   cuentaParaCuota,
-} from './cuentas-pago-core.js?v=2'
+  cuentaCambiadaDesdeExport,
+  mensajeCuentaCambiadaFila,
+  mensajeCuentaCambiadaLote,
+} from './cuentas-pago-core.js?v=3'
 import { POR_PAGINA_POR_TRAMO, planPagina, etiquetaPagina } from './agenda-paginas-core.js?v=1'
 import {
   PAGE_SIZE_TABLA, parametrosTabla, mapearFilaResumen, totalDeRespuesta, paginaFueraDeRango, ultimaPagina,
@@ -864,6 +867,8 @@ async function onArchivoImportSeleccionado(e) {
         cliente: [row['Apellidos'], row['Nombres']].map(v => String(v || '').trim()).filter(Boolean).join(' ') || String(row['Cliente'] || ''),
         concepto: String(row['Concepto'] || ''),
         moneda: String(row['Moneda'] || 'PEN'),
+        // CCI con el que se exportó la fila: si la cuenta del contrato cambió después, se rechaza.
+        cci_excel: String(row['CCI'] ?? '').trim(),
         fila: numFila,
       })
     })
@@ -902,6 +907,23 @@ async function onArchivoImportSeleccionado(e) {
       aMarcar.push(...validadas)
     }
 
+    // CUENTA DE DEPÓSITO (F3): si la cuenta de pago del contrato cambió después de exportar el
+    // Excel, esa fila no se registra sola: el depósito pudo ir a la cuenta vieja. Nunca se pide
+    // volver a depositar (ver mensajeCuentaCambiadaFila).
+    if (aMarcar.length > 0) {
+      const filasCuenta = await consultarCuentasContractuales([...new Set(aMarcar.map(x => x.contrato_id))])
+      const vigentes = []
+      asociarCuentasPagoContrato(aMarcar, filasCuenta).forEach(item => {
+        if (cuentaCambiadaDesdeExport(item)) {
+          rechazadas.push({ fila: item.fila, motivo: mensajeCuentaCambiadaFila(item.cliente) })
+        } else {
+          vigentes.push(item)
+        }
+      })
+      aMarcar.length = 0
+      aMarcar.push(...vigentes)
+    }
+
     document.getElementById('imp_loading').classList.add('hidden')
 
     if (aMarcar.length === 0 && rechazadas.length === 0) {
@@ -961,7 +983,12 @@ async function aplicarImportacion() {
 
     // El archivo puede ser antiguo. Se consulta de nuevo antes de marcar;
     // el trigger del servidor repite la regla en la misma transacción del UPDATE.
-    await verificarCuentasParaCuotas(IMPORT_PENDING)
+    const conCuenta = await verificarCuentasParaCuotas(IMPORT_PENDING)
+    // La cuenta pudo cambiar entre la vista previa y este clic (F3).
+    const cambiadas = conCuenta.filter(cuentaCambiadaDesdeExport)
+    if (cambiadas.length > 0) {
+      throw new Error(mensajeCuentaCambiadaLote(cambiadas.length))
+    }
 
     // Updates en paralelo. Cada update incluye `.eq('estado', 'pendiente')` para
     // evitar pisar pagos ya registrados manualmente entre el export y el import.
```

## Qué te pido
1. Refuta: ¿algún camino deja cambiar la cuenta sin ser admin vigente, sin respaldo propio, o mueve el
   enlace sin historial? ¿La válvula `cambiado_en = now()` puede abusarse con los permisos descritos?
2. ¿El sello por fecha atribuye mal algún pago en los flujos reales (Excel importado tras depositar,
   registro manual, anulación y nuevo pago)? ¿El nuevo mensaje de Pagos evita el doble depósito?
3. ¿El aviso en dos pasos puede duplicarse, perderse o anunciar una cuenta superada? ¿El token cubre
   el caso de una Edge lenta?
4. Storage: ¿las fronteras (incluida la de anon) y la regla «mismo actor, sin reutilizar» son correctas?
5. ¿Algo en el orden de bloqueos (contrato FOR SHARE → enlace FOR UPDATE) puede bloquear o romper el
   registro de pagos?
6. ¿Riesgos residuales bien acotados? ¿Falta algún test o mutante crítico?
Termina con VERDICT (PASS/BLOCK).

-- P04 distingue «membresía CRM REVOCADA» de «persona AJENA al CRM».
--
-- Restaura la invariante que la migración original de P04 declaró por escrito y
-- que hoy no se cumple. 20260804144555 (P04 banca), líneas 5-8:
--
--     «Un admin del portal sin membresia CRM conserva el fallback global
--      definido por P04; si tiene una fila en crm.equipo y esa membresia se
--      apaga, la revocacion prevalece.»
--
-- Es decir: P04 nunca quiso frenar a quien NUNCA fue del CRM. Quiso frenar al
-- OFFBOARDING — a quien tenía membresía y se la apagamos.
--
-- Cómo se perdió esa distinción (arqueología de 4 días):
--   · 20260804144555 — P04 escribe `and private.puede_acceder_crm()` en el
--     guard bancario. En ese momento `private.es_lector_global()` AÚN devolvía
--     true para admin/superadmin del portal, así que `puede_acceder_crm()` era
--     true para ellos: el «fallback global» del comentario funcionaba y el
--     único bloqueado era el revocado. Gate verde 2026-08-04.
--   · 20260807203740 — el rediseño «rol CRM efectivo» ESTRECHA
--     `es_lector_global()` a Directorio con membresía. Nadie lo notó porque el
--     catálogo (20260807235933) había borrado la línea de P04 del guard: el
--     fallback ya no se consultaba.
--   · 20260808173537 — la reconciliación del gate F0 REPONE la línea de P04
--     sobre la forma vigente. Correcto en su intención, pero al componerse con
--     el `es_lector_global()` estrecho el resultado cambió de sentido: pasó de
--     «bloquea al revocado» a «bloquea a todo el que no sea del CRM».
--
-- Efecto real medido en producción (2026-08-08, sesiones simuladas con
-- set_config de request.jwt.claims):
--   · `gloria@` (admin del portal, soporte a los analistas, SIN fila en
--     crm.equipo): `es_admin()` = true pero `puede_acceder_crm()` = false →
--     perdió crear contratos, corregirlos y la pantalla de Pagos. No es una
--     persona offboardeada: nunca fue del CRM, su trabajo vive en el portal.
--   · `AdminCorp@` (superadmin, sin fila): mismo bloqueo.
--
-- Decisión de negocio (Miguel, 2026-08-08): el offboarding real de la empresa
-- se hace ELIMINANDO/desactivando el usuario desde administración, y toda
-- función del portal ya exige `perfiles.activo = true`. La membresía CRM no es
-- ni debe ser el documento de identidad del personal de portal.
--
-- DELTA COMPLETO DE AUTORIZACIÓN (auditoría adversarial, 2026-08-08). El cambio
-- es monótono creciente: nadie pierde acceso. Como ¬puede_acceder_crm() implica
-- rol_crm() IS NULL, la rama CRM del guard es inalcanzable dentro del delta ⇒
-- todo el que gane algo lo gana por `es_admin()` o por `es_analista()`+cartera.
-- Cuatro poblaciones, censadas en prod el 2026-08-08:
--   1. admin/superadmin de portal SIN fila — 2 hoy (gloria, AdminCorp). Ganan
--      banca de todos los clientes (la rama es_admin no tiene scoping), Pagos y
--      alta/corrección. ES EL OBJETIVO DE ESTA MIGRACIÓN.
--   2. analista de portal SIN fila — 0 hoy (los 19 analistas activos tienen
--      membresía activa; el «20» del ledger de ayer era un conteo errado).
--      Ganaría banca sobre SU cartera y alta legacy; el scoping por cartera se
--      conserva intacto.
--   3. superadmin de portal CON fila ACTIVA de rol ≠ gerencia — 0 hoy.
--      ACEPTADO A PROPÓSITO, no omisión: `public.es_admin()` incluye a
--      superadmin por diseño DEL PORTAL, así que ese poder bancario es del
--      portal, no del CRM. No contradice el comment de 20260807203740:87-89
--      («Cualquier otro rol queda fuera del gate GLOBAL»): `rol_crm()` sigue
--      devolviendo NULL para superadmin no-gerencia, así que NO obtiene ámbito
--      CRM alguno — solo conserva lo que su rol de portal ya concede. Clavado
--      en el gate para que revertirlo sea una decisión consciente.
--   4. admin/analista con `perfiles.activo = false` — 0 hoy y CERRADO:
--      `public.es_admin()` y `public.es_analista()` exigen `activo = true`
--      (verificado con pg_get_functiondef contra prod el 2026-08-08). El cierre
--      por perfil apagado NO depende de esta migración.
-- NO ganan nada los roles de portal `comercial` ni `directorio` (es_admin y
-- es_analista falsos ⇒ el `exists` entero es falso). Los 3 `comercial` con fila
-- REVOCADA siguen bloqueados: es exactamente el objetivo de P04.
--
-- SUPERFICIE REAL. Se reescriben 2 funciones, pero
-- `private.puede_gestionar_cuentas_cliente` es el gate único de CINCO puntos de
-- entrada, tres de ellos en `crm.*` — no leer «2 funciones» como «2 pantallas»:
--   · crm.cuentas_bancarias_cliente_fn   (numero_cuenta, cci, beneficiario_dni)
--   · crm.crear_contrato_con_cuenta      (+ wrapper …_producto del catálogo)
--   · crm.actualizar_contrato_con_cuenta
--   · public.crear_contrato              (canal legacy, para TODO actor)
--   · public.actualizar_contrato         (rama analista/CRM catalogado)
-- Agravante que sube el listón de esta revisión: `crm.cuentas_bancarias` y
-- `crm.contrato_cuentas_pago` tienen RLS ON y CERO policies, así que bajo el
-- guard no hay segunda línea de defensa: toda la autorización vive aquí.
-- Se suma `crm.cuentas_pago_contratos_fn` (Pagos), reescrita también.
--
-- Las otras dos consumidoras de `puede_acceder_crm()` (`crm.equipo_visible_fn` y
-- `private.es_directorio_crm_activo`) quedan intactas A PROPÓSITO: son
-- superficies CRM y ahí exigir acceso CRM es lo correcto. Consecuencia
-- verificada: gloria sigue SIN poder leer ninguna tabla `crm.*` por PostgREST,
-- porque `crm_actor_activo_gate` (20260803164348) conserva `puede_acceder_crm()`.
--
-- ⚠️ FRAGILIDAD QUE INTRODUCE (aceptada y documentada): a partir de aquí el
-- offboarding CRM es `activo = false`, NUNCA `DELETE`. Borrar la fila de
-- `crm.equipo` de un analista lo convierte en «ajeno al CRM» y le DEVUELVE la
-- banca sobre su cartera; antes borrarla lo dejaba igual de bloqueado. No hay
-- policy DELETE para `authenticated` (la vía existe solo por service_role) y el
-- proceso real de la empresa desactiva al usuario completo, lo que cierra por
-- `perfiles.activo`. Un trigger que vete el DELETE sobre `crm.equipo` queda
-- anotado como deuda en el ledger.
--
-- No contiene statements sobre objetos de `public`.

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if to_regprocedure('private.puede_acceder_crm()') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('public.es_admin()') is null
     or to_regprocedure('public.es_analista()') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null
     or to_regprocedure('crm.cuentas_pago_contratos_fn(uuid[])') is null
     or to_regclass('crm.equipo') is null
     or to_regclass('crm.contrato_cuentas_pago') is null
     or to_regclass('crm.cuentas_bancarias') is null then
    raise exception 'Falta una dependencia del guard bancario o del resolver de Pagos';
  end if;

  -- `membresia_crm_revocada()` distingue revocado de ajeno con `activo is false`.
  -- Ese predicado da FALSE para NULL, así que si algún día se relajara el
  -- NOT NULL de la columna, una fila con activo NULL dejaría de contar como
  -- revocada: fail-OPEN silencioso. Se ancla aquí la premisa que lo sostiene
  -- (`activo boolean not null default true`, 20260709000001_cimientos_crm).
  if not exists (
    select 1
    from pg_attribute a
    where a.attrelid = 'crm.equipo'::regclass
      and a.attname = 'activo'
      and a.attnotnull
      and not a.attisdropped
  ) then
    raise exception 'crm.equipo.activo dejó de ser NOT NULL: revisar membresia_crm_revocada antes de aplicar';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La pregunta que P04 siempre quiso hacer
-- ---------------------------------------------------------------------------
--
-- Fail-closed por construcción: sin `auth.uid()` el `exists` es falso y la
-- función devuelve false («no revocado»), pero ninguno de los dos llamadores
-- autoriza por sí solo — ambos exigen además un poder de portal vivo
-- (`es_admin`/`es_analista`, que a su vez exigen `perfiles.activo`). Este
-- helper NUNCA concede: solo puede quitar.
--
-- Lee el estado VIVO en cada llamada, igual que `puede_acceder_crm()`: el JWT
-- identifica a la persona, jamás transporta su membresía.
create or replace function private.membresia_crm_revocada()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from crm.equipo e
    where e.perfil_id = (select auth.uid())
      and e.activo is false
  );
$function$;

comment on function private.membresia_crm_revocada() is
  'Offboarding CRM explícito: true solo si la persona TIENE fila en crm.equipo y está apagada. Ausencia de fila = ajena al CRM (su rol de portal gobierna), nunca revocación. ⚠️ El offboarding es activo=false, NUNCA DELETE: borrar la fila devuelve el poder de portal. Helper interno que solo resta poder; jamás concede.';

revoke all on function private.membresia_crm_revocada()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Guard bancario contractual (banca + public.crear_contrato/actualizar_contrato)
-- ---------------------------------------------------------------------------
--
-- Cuerpo copiado VERBATIM de la definición viva en prod (20260808173537); el
-- único cambio es la línea del gate P04 y su comentario. Ramas de portal y de
-- CRM (vendedor/supervisor/gerencia) intactas.
create or replace function private.puede_gestionar_cuentas_cliente(
  p_cliente_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    -- Prevalencia P04 (2026-08-09): lo que prevalece sobre el rol de portal es
    -- la REVOCACIÓN explícita de la membresía CRM, no su ausencia. Quien nunca
    -- fue del CRM conserva el fallback global que P04 documentó desde el origen.
    and not (select private.membresia_crm_revocada())
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo is true
        and (
          -- Poder del portal, ya condicionado por el gate P04 de arriba.
          (select public.es_admin())
          or (
            (select public.es_analista())
            and (
              cli.asesor_perfil_id = (select auth.uid())
              or (
                cli.asesor_perfil_id is null
                and cli.creado_por = (select auth.uid())
              )
            )
          )
          or (
            private.rol_crm((select auth.uid())) in (
              'vendedor', 'supervisor', 'gerencia'
            )
            and (
              private.rol_crm((select auth.uid())) = 'gerencia'
              or cli.asesor_perfil_id in (
                select private.vendedor_ids_visibles((select auth.uid()))
              )
            )
          )
        )
    );
$function$;

comment on function private.puede_gestionar_cuentas_cliente(uuid) is
  'Autoriza banca contractual. Prevalencia P04 (2026-08-09): una membresía CRM REVOCADA prevalece sobre cualquier poder de portal; la ausencia de membresía no bloquea (personal de portal ajeno al CRM). Helper interno de las RPC definer, sin EXECUTE directo.';

revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Resolver de la pantalla de Pagos
-- ---------------------------------------------------------------------------
--
-- Cuerpo copiado VERBATIM de la definición viva en prod (20260804144555); el
-- único cambio es el gate de la primera condición. `es_admin()` sigue siendo
-- OBLIGATORIO: Pagos nunca se abre a un rol CRM que no sea admin del portal.
create or replace function crm.cuentas_pago_contratos_fn(p_contrato_ids uuid[])
returns table (
  contrato_id uuid,
  cuenta_bancaria_id uuid,
  moneda text,
  banco text,
  tipo_cuenta text,
  numero_cuenta text,
  cci text,
  titular_distinto boolean,
  beneficiario_nombre text,
  beneficiario_dni text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  -- P04 (2026-08-09): bloquea la revocación explícita, no la ausencia de
  -- membresía. El rol admin del portal sigue siendo condición necesaria.
  if (select private.membresia_crm_revocada())
     or not (select public.es_admin()) then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  end if;
  if coalesce(cardinality(p_contrato_ids), 0) > 5000 then
    raise exception using errcode = '22023', message = 'Demasiados contratos en una sola consulta';
  end if;
  if coalesce(cardinality(p_contrato_ids), 0) = 0 then
    return;
  end if;

  if exists (
    select 1
    from crm.contrato_cuentas_pago ccp
    join public.contratos ct on ct.id = ccp.contrato_id
    join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
    where ccp.contrato_id = any(p_contrato_ids)
      and (
        cb.cliente_id is distinct from ct.cliente_id
        or cb.moneda is distinct from ct.moneda
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'Hay un contrato con cuenta de pago inconsistente; requiere conciliacion antes de pagar';
  end if;

  return query
  select
    ccp.contrato_id,
    cb.id as cuenta_bancaria_id,
    cb.moneda,
    cb.banco,
    cb.tipo_cuenta,
    cb.numero_cuenta,
    cb.cci,
    cb.titular_distinto,
    cb.beneficiario_nombre,
    cb.beneficiario_dni
  from crm.contrato_cuentas_pago ccp
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ccp.contrato_id = any(p_contrato_ids);
end;
$function$;

comment on function crm.cuentas_pago_contratos_fn(uuid[]) is
  'Entrega a Pagos la fotografia contractual solo para admin del portal sin membresia CRM revocada (P04, 2026-08-09).';

revoke all on function crm.cuentas_pago_contratos_fn(uuid[])
  from public, anon, service_role;
grant execute on function crm.cuentas_pago_contratos_fn(uuid[])
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Comentario huérfano del wrapper de corrección
-- ---------------------------------------------------------------------------
--
-- `crm.actualizar_contrato_con_cuenta` no cambia de cuerpo, pero su comment
-- (20260804144555) dice «atraviesan el gate vivo P04» — frase que a partir de
-- hoy significa otra cosa. Se re-emite para que la documentación del catálogo
-- no quede describiendo la semántica anterior.
comment on function crm.actualizar_contrato_con_cuenta(uuid, jsonb, jsonb) is
  'Corrige contratos enlazados o legacy; ambos atraviesan el guard bancario vivo, cuyo gate P04 (2026-08-09) bloquea la membresia CRM revocada y no la ausencia de membresia.';

commit;

-- REGISTRO en supabase_migrations.schema_migrations de 20261017211313_crm_reemplazar_inversion_vista_previa.
-- GENERADO por generar-registrador.mjs: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar
-- la migración. Idempotente; se niega si los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 64274e1486a7dad98d8e90876c943c2e).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_reemplazar_inversion_vista_previa_registro'));
do $chk$
begin
  if (
    to_regprocedure('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)') is not null
    and to_regprocedure('private.reemplazo_dia_registro_venta(uuid)') is not null
    and to_regprocedure('private.reemplazo_fecha_comercial(uuid,date)') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261017211313 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261017211313' and (coalesce(name, '') <> 'crm_reemplazar_inversion_vista_previa' or statements is distinct from array[$mig$-- 20261017211313_crm_reemplazar_inversion_vista_previa.sql
--
-- «Reemplazar inversión», Fase 2 (la pantalla): ANTES de confirmar, la pantalla muestra en qué mes queda la venta. Ese mes
-- lo decide el servidor: private.reemplazar_inversion_avance (20261017162053) le pone al contrato que queda la fecha
-- comercial que habría tenido si se hubiera registrado bien EL DÍA DE LA VENTA (least(fecha_inicio, día de registro), con
-- el día heredado por la cadena de copias «reemplazada por»), salvo que la fecha la haya corregido Gerencia o venga de una
-- migración, que se conserva. La ficha no trae ni el día de registro de la venta ni el origen de la fecha, así que la
-- pantalla no puede calcularlo sin inventar. Decisión de Miguel (17/10/2026): consulta en el servidor, exacta, y UNA sola
-- regla para la vista previa y para el reemplazo (sin dos copias que puedan separarse).
--
-- QUÉ HACE
--   1. private.reemplazo_dia_registro_venta(p_fuente): el día de registro de la VENTA (la copia más reciente que nombra al
--      contrato como reemplazada_por, prefiriendo la de una venta; si no hay, el registro del propio contrato en Lima).
--   2. private.reemplazo_fecha_comercial(p_fuente, p_fecha_inicio): la fecha comercial (y su fuente) que dejaría el
--      reemplazo con esa fecha de inicio. Son las mismas expresiones que tenía el núcleo, sacadas a una función.
--   2b. private.contrato_tiene_cuotas_pagadas(p_contrato): la regla de «cuotas pagadas» (el reemplazo se niega: el contrato
--      nuevo nacería con todas las cuotas pendientes). En producción el 17/10, 294 de 514 inversiones Avance «nuevo» vigentes
--      la cumplen (gate de realidad): la pantalla tiene que decirlo ANTES de llenar el formulario, no al confirmar.
--   3. El núcleo private.reemplazar_inversion_avance pasa a llamar a 1., 2. y 2b. en vez de llevar las reglas dentro. Cuerpo
--      vivo + 3 cambios por ancla; preflight y postflight fijan las huellas antes y después. No cambia nada más.
--   4. crm.reemplazar_inversion_vista_previa_fn(p_fuente_id, p_fecha_inicio, p_conservar_id): SOLO LECTURA. Devuelve la
--      fecha comercial y el mes de hoy y los que quedarían (con la fecha de inicio pedida, o con la de la inversión que se
--      conserva), y si el contrato tiene cuotas pagadas. DEFINER (justificación: lee public.contratos,
--      public.cronograma_pagos y crm.inversiones_eliminadas, que la API no lee entera; la
--      copia no tiene ningún privilegio para la API). Las puertas COMUNES del reemplazo: sesión, admin del portal
--      (private.eliminar_inversion_roles) y membresía del CRM no revocada; la exigencia de Gerencia (venta de un lead,
--      origen de capital confirmado) la aplica el reemplazo al confirmar, porque saberlo exige el contexto con sus candados
--      FOR UPDATE (auditor-rls, P3-4). No decide si se puede reemplazar: eso lo dice el reemplazo (mes cerrado, plazo, cuotas
--      pagadas…). VOLATILE A PROPÓSITO y se llama por POST: private.eliminar_inversion_roles toma FOR SHARE sobre el perfil
--      y la membresía, que fallaría en una transacción de solo lectura (GET o STABLE en PostgREST: auditor-rls, P3-2).
--
-- CAPAS: puerta (crm) → ayudantes (private, INVOKER). CENSO ANALÍTICO: sin count(. NO toca objetos de public ni tablas.
-- Aplicar en UN mensaje (`supabase db query --linked --file`), DESPUÉS de 20261017162053 (su preflight lo exige).
-- REVERSA: supabase/scripts/reemplazar-inversion-vista-previa/reversa.sql (devuelve el núcleo a su huella de la Fase 1).
-- PRUEBAS: supabase/scripts/reemplazar-inversion-vista-previa/probar.sh (banco Docker, ROLLBACK).

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  if not exists (select 1 from pg_catalog.pg_locks l
                 where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid() and l.granted
                   and l.mode = 'ExclusiveLock' and l.objsubid = 1
                   and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'PREFLIGHT reemplazar_inversion_vista_previa: esta sesión no tiene el candado de migraciones';
  end if;
  -- La Fase 1 aplicada tal cual se ensayó (20261017162053): el núcleo que se cambia y lo que la puerta nueva llama.
  if (md5(pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure)) = '541ce30ffcc213adaebc036dda48a6a2'
      and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure)) = '755b35a2b92b4d46cf6e7294d6d77ea9'
      and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure)) = '3a055eeabb9a0b96981ff910c33354d5'
      and md5(pg_catalog.pg_get_functiondef('private.eliminar_inversion_roles(uuid)'::regprocedure)) = 'e9a2341105e4028565f81164d5e02c4c'
      and md5(pg_catalog.pg_get_functiondef('private.membresia_crm_revocada()'::regprocedure)) = '47f8ceb6455f4855562941a7057be02c') is not true then
    raise exception 'PREFLIGHT reemplazar_inversion_vista_previa: falta la Fase 1 (20261017162053) o cambió una función que usa';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure
                   and p.proowner = 'postgres'::regrole and not p.prosecdef and p.provolatile = 'v'
                   and p.proconfig = array['search_path=""'] and p.proacl = '{postgres=X/postgres}'::aclitem[]) then
    raise exception 'PREFLIGHT reemplazar_inversion_vista_previa: cambiaron los metadatos del núcleo';
  end if;
  if to_regprocedure('private.reemplazo_dia_registro_venta(uuid)') is not null
     or to_regprocedure('private.reemplazo_fecha_comercial(uuid,date)') is not null
     or to_regprocedure('private.contrato_tiene_cuotas_pagadas(uuid)') is not null
     or to_regprocedure('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)') is not null then
    raise exception 'PREFLIGHT reemplazar_inversion_vista_previa: los objetos nuevos ya existen';
  end if;
end
$preflight$;

-- ── 1 · Ayudante: el día de registro de la VENTA ─────────────────────────────────────────────────────────────────────
create function private.reemplazo_dia_registro_venta(p_fuente uuid)
returns date
language sql
stable
set search_path = ''
as $function$
  -- Si el contrato ya era el resultado de un reemplazo, el día de la venta que reemplazó (la copia lo guarda); si varias
  -- copias lo nombran, manda la de una venta y luego la más reciente. Si no, el de su propio registro, en Lima.
  select coalesce(
    (select (ie.snapshot #>> '{reemplazo,dia_registro_venta}')::date from crm.inversiones_eliminadas ie
      where ie.reemplazada_por = p_fuente order by ie.es_conversion desc, ie.eliminado_en desc, ie.id desc limit 1),
    (select (c.creado_en at time zone 'America/Lima')::date from public.contratos c where c.id = p_fuente))
$function$;

-- ── 2 · Ayudante: la fecha comercial que deja el reemplazo ───────────────────────────────────────────────────────────
create function private.reemplazo_fecha_comercial(p_fuente uuid, p_fecha_inicio date,
  out fecha_comercial date, out fuente_cierre_comercial text, out dia_registro_venta date)
returns record
language sql
stable
set search_path = ''
as $function$
  -- La que habría tenido si se hubiera registrado bien el día de la venta (private.definir_periodo_comercial_contrato:
  -- least(fecha_inicio, día de registro)). Una fecha que Gerencia corrigió (correccion_manual) o una migrada se conserva.
  select case when c.fuente_cierre_comercial in ('registro', 'fecha_inicio_inferida')
              then least(p_fecha_inicio, d.dia) else c.fecha_cierre_comercial end,
         case when c.fuente_cierre_comercial in ('registro', 'fecha_inicio_inferida')
              then case when p_fecha_inicio < d.dia then 'fecha_inicio_inferida' else 'registro' end
              else c.fuente_cierre_comercial end,
         d.dia
  from public.contratos c
  cross join lateral (select private.reemplazo_dia_registro_venta(p_fuente) as dia) d
  where c.id = p_fuente
$function$;

-- ── 2b · Ayudante: el contrato ya tiene cuotas pagadas ───────────────────────────────────────────────────────────────
create function private.contrato_tiene_cuotas_pagadas(p_contrato uuid)
returns boolean
language sql
stable
set search_path = ''
as $function$
  -- Pagada, trasladada o con algo cobrado: el reemplazo se llevaría esos pagos con el cronograma (revisión de negocio, P1).
  select exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = p_contrato
                 and (cp.estado in ('pagado', 'trasladado') or cp.monto_pagado is not null))
$function$;

-- ── 3 · El núcleo usa los ayudantes (una sola regla) ─────────────────────────────────────────────────────────────────
do $nucleo$
declare
  v_def text := pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure);
  v_cambios text[][] := array[
    array['  -- El día de registro de la VENTA: si el original ya era el resultado de un reemplazo, el de la venta que reemplazó (la
  -- cadena lo guarda en la copia); si no, el de su propio registro (Codex r1, P1). Vale para los dos modos.
  v_dia_registro := coalesce(
    (select (ie.snapshot #>> ''{reemplazo,dia_registro_venta}'')::date from crm.inversiones_eliminadas ie
      where ie.reemplazada_por = p_fuente order by ie.es_conversion desc, ie.eliminado_en desc, ie.id desc limit 1),
    (v_orig.creado_en at time zone ''America/Lima'')::date);
',
          '  -- El día de registro de la VENTA (la cadena de copias o el registro del propio contrato): private.reemplazo_dia_
  -- registro_venta, la MISMA que usa la vista previa (20261017211313). Vale para los dos modos.
  v_dia_registro := private.reemplazo_dia_registro_venta(p_fuente);
'],
    array['  if v_orig.fuente_cierre_comercial in (''registro'', ''fecha_inicio_inferida'') then
    v_fecha_cc := least(v_fi, v_dia_registro);
    v_fuente_cc := case when v_fi < v_dia_registro then ''fecha_inicio_inferida'' else ''registro'' end;
  else
    v_fecha_cc := v_orig.fecha_cierre_comercial;
    v_fuente_cc := v_orig.fuente_cierre_comercial;
  end if;
',
          '  -- La regla vive en private.reemplazo_fecha_comercial, la MISMA que usa la vista previa (20261017211313).
  select f.fecha_comercial, f.fuente_cierre_comercial into v_fecha_cc, v_fuente_cc
    from private.reemplazo_fecha_comercial(p_fuente, v_fi) f;
'],
    array['  if exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = p_fuente
             and (cp.estado in (''pagado'', ''trasladado'') or cp.monto_pagado is not null)) then
',
          '  -- La regla vive en private.contrato_tiene_cuotas_pagadas, la MISMA que avisa la vista previa (20261017211313).
  if private.contrato_tiene_cuotas_pagadas(p_fuente) then
']
  ];
  i int;
begin
  for i in 1 .. array_length(v_cambios, 1) loop
    if (length(v_def) - length(replace(v_def, v_cambios[i][1], ''))) / length(v_cambios[i][1]) <> 1 then
      raise exception 'nucleo: el ancla % no aparece exactamente una vez', i;
    end if;
    v_def := replace(v_def, v_cambios[i][1], v_cambios[i][2]);
  end loop;
  -- El DDL resultante es EXACTAMENTE el ensayado en el banco (misma huella que exige el postflight).
  if md5(v_def) is distinct from 'b6af7422802edc85ced40d6b9cc26e49' then
    raise exception 'nucleo: el cuerpo resultante no es el ensayado';
  end if;
  execute v_def;
end
$nucleo$;

-- ── 4 · Puerta de solo lectura: la vista previa del mes ──────────────────────────────────────────────────────────────
create function crm.reemplazar_inversion_vista_previa_fn(p_fuente_id uuid, p_fecha_inicio date default null,
  p_conservar_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_orig public.contratos%rowtype;
  v_cons public.contratos%rowtype;
  v_fi date;
  v_res record;
begin
  if v_uid is null then
    raise exception 'Inicia sesión para reemplazar inversiones' using errcode = '42501';
  end if;
  begin
    v_roles := private.eliminar_inversion_roles(v_uid);
  exception when deadlock_detected or lock_not_available then
    -- El FOR SHARE del perfil o la membresía chocó con otra operación (auditor-rls, P3-3): nada que deshacer.
    raise exception 'Otra operación está usando estos datos; vuelve a intentar en unos segundos' using errcode = 'PT409';
  end;
  if v_roles ->> 'portal' is null and not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  if v_roles ->> 'portal' is null then
    raise exception 'Una inversión de Avance la reemplaza un admin del portal' using errcode = '42501';
  end if;
  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  select * into v_orig from public.contratos c where c.id = p_fuente_id;
  if v_orig.id is null then
    raise exception 'La inversión no existe o ya fue eliminada' using errcode = 'P0002';
  end if;
  if p_conservar_id is not null then
    select * into v_cons from public.contratos c where c.id = p_conservar_id;
    if v_cons.id is null then
      raise exception 'La inversión que se conserva no existe o ya fue eliminada' using errcode = 'P0002';
    end if;
    if v_cons.id = v_orig.id then
      raise exception 'Elige otra inversión: la que se conserva no puede ser la misma' using errcode = '22023';
    end if;
    if v_cons.cliente_id is distinct from v_orig.cliente_id then
      raise exception 'La inversión que se conserva es de otro cliente: el cliente no cambia en un reemplazo' using errcode = '22023';
    end if;
    v_fi := v_cons.fecha_inicio;
  else
    -- Como el reemplazo (que rechaza una fecha no finita): ±infinity no es una fecha de inicio (auditor-rls, P3-1).
    if p_fecha_inicio is null or not pg_catalog.isfinite(p_fecha_inicio) then
      raise exception 'Indica la fecha de inicio de la inversión correcta' using errcode = '22023';
    end if;
    v_fi := p_fecha_inicio;
  end if;
  select * into v_res from private.reemplazo_fecha_comercial(p_fuente_id, v_fi);
  return pg_catalog.jsonb_build_object(
    'fuente_id', v_orig.id,
    'fecha_inicio', v_fi,
    'fecha_comercial_actual', v_orig.fecha_cierre_comercial,
    'mes_actual', pg_catalog.date_trunc('month', v_orig.fecha_cierre_comercial::timestamp)::date,
    'fecha_comercial_resultante', v_res.fecha_comercial,
    'mes_resultante', pg_catalog.date_trunc('month', v_res.fecha_comercial::timestamp)::date,
    'cambia_mes', pg_catalog.date_trunc('month', v_res.fecha_comercial::timestamp)
                  is distinct from pg_catalog.date_trunc('month', v_orig.fecha_cierre_comercial::timestamp),
    'fecha_corregida', v_res.fuente_cierre_comercial not in ('registro', 'fecha_inicio_inferida'),
    -- El reemplazo se negaría al confirmar: la pantalla lo dice antes (gate de realidad: 294 de 514 en producción).
    'cuotas_pagadas', private.contrato_tiene_cuotas_pagadas(v_orig.id));
end
$function$;

-- ── 5 · Permisos ───────────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function private.reemplazo_dia_registro_venta(uuid) from public, anon, authenticated, service_role;
revoke all on function private.reemplazo_fecha_comercial(uuid, date) from public, anon, authenticated, service_role;
revoke all on function private.contrato_tiene_cuotas_pagadas(uuid) from public, anon, authenticated, service_role;
revoke all on function crm.reemplazar_inversion_vista_previa_fn(uuid, date, uuid) from public, anon, service_role;
grant execute on function crm.reemplazar_inversion_vista_previa_fn(uuid, date, uuid) to authenticated;

-- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function private.reemplazo_dia_registro_venta(uuid) is
  'Reemplazar inversión: día de registro de la VENTA de un contrato (la copia «reemplazada por» que lo nombra, prefiriendo la de una venta y la más reciente; si no hay, su propio registro en Lima). Una sola regla para el reemplazo y su vista previa.';
comment on function private.reemplazo_fecha_comercial(uuid, date) is
  'Reemplazar inversión: fecha comercial (y su fuente) que deja el reemplazo con esa fecha de inicio: least(fecha_inicio, día de registro de la venta); una fecha corregida por Gerencia o migrada se conserva. La usan private.reemplazar_inversion_avance y crm.reemplazar_inversion_vista_previa_fn.';
comment on function private.contrato_tiene_cuotas_pagadas(uuid) is
  'Reemplazar inversión: el contrato tiene cuotas pagadas, trasladadas o con algo cobrado (el reemplazo se niega: se perderían esos pagos). Una sola regla para el reemplazo y su vista previa.';
comment on function crm.reemplazar_inversion_vista_previa_fn(uuid, date, uuid) is
  'Reemplazar inversión, vista previa de SOLO LECTURA: fecha comercial y mes de hoy y los que quedarían con la fecha de inicio pedida (o la de la inversión que se conserva). Puertas comunes del reemplazo (sesión, admin del portal, membresía); la Gerencia de una venta la exige el reemplazo al confirmar. No decide si se puede reemplazar. VOLATILE a propósito y por POST (toma FOR SHARE del perfil). No se llama con service_role.';

-- ── 7 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
begin
  if md5(pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure))
       is distinct from 'b6af7422802edc85ced40d6b9cc26e49' then
    raise exception 'POSTFLIGHT: el núcleo no quedó con la huella esperada';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure
                   and p.proowner = 'postgres'::regrole and not p.prosecdef and p.provolatile = 'v'
                   and p.proconfig = array['search_path=""'] and p.proacl = '{postgres=X/postgres}'::aclitem[]) then
    raise exception 'POSTFLIGHT: dueño, seguridad, configuración o permisos del núcleo';
  end if;
  if (select pg_catalog.bool_and(not p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
                                 and p.proowner = 'postgres'::regrole and p.proacl = '{postgres=X/postgres}'::aclitem[])
      from pg_catalog.pg_proc p
      where p.oid in ('private.reemplazo_dia_registro_venta(uuid)'::regprocedure,
                      'private.reemplazo_fecha_comercial(uuid,date)'::regprocedure,
                      'private.contrato_tiene_cuotas_pagadas(uuid)'::regprocedure)) is not true then
    raise exception 'POSTFLIGHT: los ayudantes son INVOKER, STABLE, search_path vacío y sin EXECUTE para la API';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure
                   and p.prosecdef and p.proowner = 'postgres'::regrole and p.provolatile = 'v'
                   and p.proconfig @> array['search_path=""'])
     or exists (select 1 from pg_catalog.pg_proc p
                cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                where p.oid = 'crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure
                  and a.grantee <> p.proowner and a.grantee <> 'authenticated'::regrole)
     or not has_function_privilege('authenticated', 'crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)', 'execute') then
    raise exception 'POSTFLIGHT: la vista previa es DEFINER de postgres, VOLATILE, search_path vacío, EXECUTE solo authenticated';
  end if;
  -- F7 por su cuenta: ninguna función nueva ni el núcleo nombran una pieza cerrada (misma normalización que
  -- private.assert_f7_piezas_cerradas).
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and p.oid in ('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure,
                             'private.reemplazo_dia_registro_venta(uuid)'::regprocedure,
                             'private.reemplazo_fecha_comercial(uuid,date)'::regprocedure,
                             'private.contrato_tiene_cuotas_pagadas(uuid)'::regprocedure,
                             'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure)
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT: una función nueva nombra una pieza cerrada de F7';
  end if;
  if exists (select 1 from private.puertas_analista_sin_vigencia() c
             where c.objeto in ('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)',
                                'private.reemplazo_dia_registro_venta(uuid)',
                                'private.reemplazo_fecha_comercial(uuid,date)',
                                'private.contrato_tiene_cuotas_pagadas(uuid)',
                                'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)')) then
    raise exception 'POSTFLIGHT: una función nueva entró al censo de vigencia del analista';
  end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto in ('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)',
                                'private.reemplazo_dia_registro_venta(uuid)',
                                'private.reemplazo_fecha_comercial(uuid,date)',
                                'private.contrato_tiene_cuotas_pagadas(uuid)',
                                'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)')) then
    raise exception 'POSTFLIGHT: una función nueva entró al censo analítico';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
$mig$])) then
    raise exception 'REGISTRO: la versión 20261017211313 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261017211313', 'crm_reemplazar_inversion_vista_previa', array[$mig$-- 20261017211313_crm_reemplazar_inversion_vista_previa.sql
--
-- «Reemplazar inversión», Fase 2 (la pantalla): ANTES de confirmar, la pantalla muestra en qué mes queda la venta. Ese mes
-- lo decide el servidor: private.reemplazar_inversion_avance (20261017162053) le pone al contrato que queda la fecha
-- comercial que habría tenido si se hubiera registrado bien EL DÍA DE LA VENTA (least(fecha_inicio, día de registro), con
-- el día heredado por la cadena de copias «reemplazada por»), salvo que la fecha la haya corregido Gerencia o venga de una
-- migración, que se conserva. La ficha no trae ni el día de registro de la venta ni el origen de la fecha, así que la
-- pantalla no puede calcularlo sin inventar. Decisión de Miguel (17/10/2026): consulta en el servidor, exacta, y UNA sola
-- regla para la vista previa y para el reemplazo (sin dos copias que puedan separarse).
--
-- QUÉ HACE
--   1. private.reemplazo_dia_registro_venta(p_fuente): el día de registro de la VENTA (la copia más reciente que nombra al
--      contrato como reemplazada_por, prefiriendo la de una venta; si no hay, el registro del propio contrato en Lima).
--   2. private.reemplazo_fecha_comercial(p_fuente, p_fecha_inicio): la fecha comercial (y su fuente) que dejaría el
--      reemplazo con esa fecha de inicio. Son las mismas expresiones que tenía el núcleo, sacadas a una función.
--   2b. private.contrato_tiene_cuotas_pagadas(p_contrato): la regla de «cuotas pagadas» (el reemplazo se niega: el contrato
--      nuevo nacería con todas las cuotas pendientes). En producción el 17/10, 294 de 514 inversiones Avance «nuevo» vigentes
--      la cumplen (gate de realidad): la pantalla tiene que decirlo ANTES de llenar el formulario, no al confirmar.
--   3. El núcleo private.reemplazar_inversion_avance pasa a llamar a 1., 2. y 2b. en vez de llevar las reglas dentro. Cuerpo
--      vivo + 3 cambios por ancla; preflight y postflight fijan las huellas antes y después. No cambia nada más.
--   4. crm.reemplazar_inversion_vista_previa_fn(p_fuente_id, p_fecha_inicio, p_conservar_id): SOLO LECTURA. Devuelve la
--      fecha comercial y el mes de hoy y los que quedarían (con la fecha de inicio pedida, o con la de la inversión que se
--      conserva), y si el contrato tiene cuotas pagadas. DEFINER (justificación: lee public.contratos,
--      public.cronograma_pagos y crm.inversiones_eliminadas, que la API no lee entera; la
--      copia no tiene ningún privilegio para la API). Las puertas COMUNES del reemplazo: sesión, admin del portal
--      (private.eliminar_inversion_roles) y membresía del CRM no revocada; la exigencia de Gerencia (venta de un lead,
--      origen de capital confirmado) la aplica el reemplazo al confirmar, porque saberlo exige el contexto con sus candados
--      FOR UPDATE (auditor-rls, P3-4). No decide si se puede reemplazar: eso lo dice el reemplazo (mes cerrado, plazo, cuotas
--      pagadas…). VOLATILE A PROPÓSITO y se llama por POST: private.eliminar_inversion_roles toma FOR SHARE sobre el perfil
--      y la membresía, que fallaría en una transacción de solo lectura (GET o STABLE en PostgREST: auditor-rls, P3-2).
--
-- CAPAS: puerta (crm) → ayudantes (private, INVOKER). CENSO ANALÍTICO: sin count(. NO toca objetos de public ni tablas.
-- Aplicar en UN mensaje (`supabase db query --linked --file`), DESPUÉS de 20261017162053 (su preflight lo exige).
-- REVERSA: supabase/scripts/reemplazar-inversion-vista-previa/reversa.sql (devuelve el núcleo a su huella de la Fase 1).
-- PRUEBAS: supabase/scripts/reemplazar-inversion-vista-previa/probar.sh (banco Docker, ROLLBACK).

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  if not exists (select 1 from pg_catalog.pg_locks l
                 where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid() and l.granted
                   and l.mode = 'ExclusiveLock' and l.objsubid = 1
                   and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'PREFLIGHT reemplazar_inversion_vista_previa: esta sesión no tiene el candado de migraciones';
  end if;
  -- La Fase 1 aplicada tal cual se ensayó (20261017162053): el núcleo que se cambia y lo que la puerta nueva llama.
  if (md5(pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure)) = '541ce30ffcc213adaebc036dda48a6a2'
      and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure)) = '755b35a2b92b4d46cf6e7294d6d77ea9'
      and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure)) = '3a055eeabb9a0b96981ff910c33354d5'
      and md5(pg_catalog.pg_get_functiondef('private.eliminar_inversion_roles(uuid)'::regprocedure)) = 'e9a2341105e4028565f81164d5e02c4c'
      and md5(pg_catalog.pg_get_functiondef('private.membresia_crm_revocada()'::regprocedure)) = '47f8ceb6455f4855562941a7057be02c') is not true then
    raise exception 'PREFLIGHT reemplazar_inversion_vista_previa: falta la Fase 1 (20261017162053) o cambió una función que usa';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure
                   and p.proowner = 'postgres'::regrole and not p.prosecdef and p.provolatile = 'v'
                   and p.proconfig = array['search_path=""'] and p.proacl = '{postgres=X/postgres}'::aclitem[]) then
    raise exception 'PREFLIGHT reemplazar_inversion_vista_previa: cambiaron los metadatos del núcleo';
  end if;
  if to_regprocedure('private.reemplazo_dia_registro_venta(uuid)') is not null
     or to_regprocedure('private.reemplazo_fecha_comercial(uuid,date)') is not null
     or to_regprocedure('private.contrato_tiene_cuotas_pagadas(uuid)') is not null
     or to_regprocedure('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)') is not null then
    raise exception 'PREFLIGHT reemplazar_inversion_vista_previa: los objetos nuevos ya existen';
  end if;
end
$preflight$;

-- ── 1 · Ayudante: el día de registro de la VENTA ─────────────────────────────────────────────────────────────────────
create function private.reemplazo_dia_registro_venta(p_fuente uuid)
returns date
language sql
stable
set search_path = ''
as $function$
  -- Si el contrato ya era el resultado de un reemplazo, el día de la venta que reemplazó (la copia lo guarda); si varias
  -- copias lo nombran, manda la de una venta y luego la más reciente. Si no, el de su propio registro, en Lima.
  select coalesce(
    (select (ie.snapshot #>> '{reemplazo,dia_registro_venta}')::date from crm.inversiones_eliminadas ie
      where ie.reemplazada_por = p_fuente order by ie.es_conversion desc, ie.eliminado_en desc, ie.id desc limit 1),
    (select (c.creado_en at time zone 'America/Lima')::date from public.contratos c where c.id = p_fuente))
$function$;

-- ── 2 · Ayudante: la fecha comercial que deja el reemplazo ───────────────────────────────────────────────────────────
create function private.reemplazo_fecha_comercial(p_fuente uuid, p_fecha_inicio date,
  out fecha_comercial date, out fuente_cierre_comercial text, out dia_registro_venta date)
returns record
language sql
stable
set search_path = ''
as $function$
  -- La que habría tenido si se hubiera registrado bien el día de la venta (private.definir_periodo_comercial_contrato:
  -- least(fecha_inicio, día de registro)). Una fecha que Gerencia corrigió (correccion_manual) o una migrada se conserva.
  select case when c.fuente_cierre_comercial in ('registro', 'fecha_inicio_inferida')
              then least(p_fecha_inicio, d.dia) else c.fecha_cierre_comercial end,
         case when c.fuente_cierre_comercial in ('registro', 'fecha_inicio_inferida')
              then case when p_fecha_inicio < d.dia then 'fecha_inicio_inferida' else 'registro' end
              else c.fuente_cierre_comercial end,
         d.dia
  from public.contratos c
  cross join lateral (select private.reemplazo_dia_registro_venta(p_fuente) as dia) d
  where c.id = p_fuente
$function$;

-- ── 2b · Ayudante: el contrato ya tiene cuotas pagadas ───────────────────────────────────────────────────────────────
create function private.contrato_tiene_cuotas_pagadas(p_contrato uuid)
returns boolean
language sql
stable
set search_path = ''
as $function$
  -- Pagada, trasladada o con algo cobrado: el reemplazo se llevaría esos pagos con el cronograma (revisión de negocio, P1).
  select exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = p_contrato
                 and (cp.estado in ('pagado', 'trasladado') or cp.monto_pagado is not null))
$function$;

-- ── 3 · El núcleo usa los ayudantes (una sola regla) ─────────────────────────────────────────────────────────────────
do $nucleo$
declare
  v_def text := pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure);
  v_cambios text[][] := array[
    array['  -- El día de registro de la VENTA: si el original ya era el resultado de un reemplazo, el de la venta que reemplazó (la
  -- cadena lo guarda en la copia); si no, el de su propio registro (Codex r1, P1). Vale para los dos modos.
  v_dia_registro := coalesce(
    (select (ie.snapshot #>> ''{reemplazo,dia_registro_venta}'')::date from crm.inversiones_eliminadas ie
      where ie.reemplazada_por = p_fuente order by ie.es_conversion desc, ie.eliminado_en desc, ie.id desc limit 1),
    (v_orig.creado_en at time zone ''America/Lima'')::date);
',
          '  -- El día de registro de la VENTA (la cadena de copias o el registro del propio contrato): private.reemplazo_dia_
  -- registro_venta, la MISMA que usa la vista previa (20261017211313). Vale para los dos modos.
  v_dia_registro := private.reemplazo_dia_registro_venta(p_fuente);
'],
    array['  if v_orig.fuente_cierre_comercial in (''registro'', ''fecha_inicio_inferida'') then
    v_fecha_cc := least(v_fi, v_dia_registro);
    v_fuente_cc := case when v_fi < v_dia_registro then ''fecha_inicio_inferida'' else ''registro'' end;
  else
    v_fecha_cc := v_orig.fecha_cierre_comercial;
    v_fuente_cc := v_orig.fuente_cierre_comercial;
  end if;
',
          '  -- La regla vive en private.reemplazo_fecha_comercial, la MISMA que usa la vista previa (20261017211313).
  select f.fecha_comercial, f.fuente_cierre_comercial into v_fecha_cc, v_fuente_cc
    from private.reemplazo_fecha_comercial(p_fuente, v_fi) f;
'],
    array['  if exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = p_fuente
             and (cp.estado in (''pagado'', ''trasladado'') or cp.monto_pagado is not null)) then
',
          '  -- La regla vive en private.contrato_tiene_cuotas_pagadas, la MISMA que avisa la vista previa (20261017211313).
  if private.contrato_tiene_cuotas_pagadas(p_fuente) then
']
  ];
  i int;
begin
  for i in 1 .. array_length(v_cambios, 1) loop
    if (length(v_def) - length(replace(v_def, v_cambios[i][1], ''))) / length(v_cambios[i][1]) <> 1 then
      raise exception 'nucleo: el ancla % no aparece exactamente una vez', i;
    end if;
    v_def := replace(v_def, v_cambios[i][1], v_cambios[i][2]);
  end loop;
  -- El DDL resultante es EXACTAMENTE el ensayado en el banco (misma huella que exige el postflight).
  if md5(v_def) is distinct from 'b6af7422802edc85ced40d6b9cc26e49' then
    raise exception 'nucleo: el cuerpo resultante no es el ensayado';
  end if;
  execute v_def;
end
$nucleo$;

-- ── 4 · Puerta de solo lectura: la vista previa del mes ──────────────────────────────────────────────────────────────
create function crm.reemplazar_inversion_vista_previa_fn(p_fuente_id uuid, p_fecha_inicio date default null,
  p_conservar_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_orig public.contratos%rowtype;
  v_cons public.contratos%rowtype;
  v_fi date;
  v_res record;
begin
  if v_uid is null then
    raise exception 'Inicia sesión para reemplazar inversiones' using errcode = '42501';
  end if;
  begin
    v_roles := private.eliminar_inversion_roles(v_uid);
  exception when deadlock_detected or lock_not_available then
    -- El FOR SHARE del perfil o la membresía chocó con otra operación (auditor-rls, P3-3): nada que deshacer.
    raise exception 'Otra operación está usando estos datos; vuelve a intentar en unos segundos' using errcode = 'PT409';
  end;
  if v_roles ->> 'portal' is null and not coalesce((v_roles ->> 'gerencia')::boolean, false) then
    raise exception 'Solo admin o gerencia pueden reemplazar inversiones' using errcode = '42501';
  end if;
  if v_roles ->> 'portal' is null then
    raise exception 'Una inversión de Avance la reemplaza un admin del portal' using errcode = '42501';
  end if;
  if private.membresia_crm_revocada() then
    raise exception 'Tu membresía del CRM está revocada: no puedes reemplazar inversiones' using errcode = '42501';
  end if;
  select * into v_orig from public.contratos c where c.id = p_fuente_id;
  if v_orig.id is null then
    raise exception 'La inversión no existe o ya fue eliminada' using errcode = 'P0002';
  end if;
  if p_conservar_id is not null then
    select * into v_cons from public.contratos c where c.id = p_conservar_id;
    if v_cons.id is null then
      raise exception 'La inversión que se conserva no existe o ya fue eliminada' using errcode = 'P0002';
    end if;
    if v_cons.id = v_orig.id then
      raise exception 'Elige otra inversión: la que se conserva no puede ser la misma' using errcode = '22023';
    end if;
    if v_cons.cliente_id is distinct from v_orig.cliente_id then
      raise exception 'La inversión que se conserva es de otro cliente: el cliente no cambia en un reemplazo' using errcode = '22023';
    end if;
    v_fi := v_cons.fecha_inicio;
  else
    -- Como el reemplazo (que rechaza una fecha no finita): ±infinity no es una fecha de inicio (auditor-rls, P3-1).
    if p_fecha_inicio is null or not pg_catalog.isfinite(p_fecha_inicio) then
      raise exception 'Indica la fecha de inicio de la inversión correcta' using errcode = '22023';
    end if;
    v_fi := p_fecha_inicio;
  end if;
  select * into v_res from private.reemplazo_fecha_comercial(p_fuente_id, v_fi);
  return pg_catalog.jsonb_build_object(
    'fuente_id', v_orig.id,
    'fecha_inicio', v_fi,
    'fecha_comercial_actual', v_orig.fecha_cierre_comercial,
    'mes_actual', pg_catalog.date_trunc('month', v_orig.fecha_cierre_comercial::timestamp)::date,
    'fecha_comercial_resultante', v_res.fecha_comercial,
    'mes_resultante', pg_catalog.date_trunc('month', v_res.fecha_comercial::timestamp)::date,
    'cambia_mes', pg_catalog.date_trunc('month', v_res.fecha_comercial::timestamp)
                  is distinct from pg_catalog.date_trunc('month', v_orig.fecha_cierre_comercial::timestamp),
    'fecha_corregida', v_res.fuente_cierre_comercial not in ('registro', 'fecha_inicio_inferida'),
    -- El reemplazo se negaría al confirmar: la pantalla lo dice antes (gate de realidad: 294 de 514 en producción).
    'cuotas_pagadas', private.contrato_tiene_cuotas_pagadas(v_orig.id));
end
$function$;

-- ── 5 · Permisos ───────────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function private.reemplazo_dia_registro_venta(uuid) from public, anon, authenticated, service_role;
revoke all on function private.reemplazo_fecha_comercial(uuid, date) from public, anon, authenticated, service_role;
revoke all on function private.contrato_tiene_cuotas_pagadas(uuid) from public, anon, authenticated, service_role;
revoke all on function crm.reemplazar_inversion_vista_previa_fn(uuid, date, uuid) from public, anon, service_role;
grant execute on function crm.reemplazar_inversion_vista_previa_fn(uuid, date, uuid) to authenticated;

-- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function private.reemplazo_dia_registro_venta(uuid) is
  'Reemplazar inversión: día de registro de la VENTA de un contrato (la copia «reemplazada por» que lo nombra, prefiriendo la de una venta y la más reciente; si no hay, su propio registro en Lima). Una sola regla para el reemplazo y su vista previa.';
comment on function private.reemplazo_fecha_comercial(uuid, date) is
  'Reemplazar inversión: fecha comercial (y su fuente) que deja el reemplazo con esa fecha de inicio: least(fecha_inicio, día de registro de la venta); una fecha corregida por Gerencia o migrada se conserva. La usan private.reemplazar_inversion_avance y crm.reemplazar_inversion_vista_previa_fn.';
comment on function private.contrato_tiene_cuotas_pagadas(uuid) is
  'Reemplazar inversión: el contrato tiene cuotas pagadas, trasladadas o con algo cobrado (el reemplazo se niega: se perderían esos pagos). Una sola regla para el reemplazo y su vista previa.';
comment on function crm.reemplazar_inversion_vista_previa_fn(uuid, date, uuid) is
  'Reemplazar inversión, vista previa de SOLO LECTURA: fecha comercial y mes de hoy y los que quedarían con la fecha de inicio pedida (o la de la inversión que se conserva). Puertas comunes del reemplazo (sesión, admin del portal, membresía); la Gerencia de una venta la exige el reemplazo al confirmar. No decide si se puede reemplazar. VOLATILE a propósito y por POST (toma FOR SHARE del perfil). No se llama con service_role.';

-- ── 7 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
begin
  if md5(pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure))
       is distinct from 'b6af7422802edc85ced40d6b9cc26e49' then
    raise exception 'POSTFLIGHT: el núcleo no quedó con la huella esperada';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure
                   and p.proowner = 'postgres'::regrole and not p.prosecdef and p.provolatile = 'v'
                   and p.proconfig = array['search_path=""'] and p.proacl = '{postgres=X/postgres}'::aclitem[]) then
    raise exception 'POSTFLIGHT: dueño, seguridad, configuración o permisos del núcleo';
  end if;
  if (select pg_catalog.bool_and(not p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
                                 and p.proowner = 'postgres'::regrole and p.proacl = '{postgres=X/postgres}'::aclitem[])
      from pg_catalog.pg_proc p
      where p.oid in ('private.reemplazo_dia_registro_venta(uuid)'::regprocedure,
                      'private.reemplazo_fecha_comercial(uuid,date)'::regprocedure,
                      'private.contrato_tiene_cuotas_pagadas(uuid)'::regprocedure)) is not true then
    raise exception 'POSTFLIGHT: los ayudantes son INVOKER, STABLE, search_path vacío y sin EXECUTE para la API';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure
                   and p.prosecdef and p.proowner = 'postgres'::regrole and p.provolatile = 'v'
                   and p.proconfig @> array['search_path=""'])
     or exists (select 1 from pg_catalog.pg_proc p
                cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                where p.oid = 'crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure
                  and a.grantee <> p.proowner and a.grantee <> 'authenticated'::regrole)
     or not has_function_privilege('authenticated', 'crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)', 'execute') then
    raise exception 'POSTFLIGHT: la vista previa es DEFINER de postgres, VOLATILE, search_path vacío, EXECUTE solo authenticated';
  end if;
  -- F7 por su cuenta: ninguna función nueva ni el núcleo nombran una pieza cerrada (misma normalización que
  -- private.assert_f7_piezas_cerradas).
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and p.oid in ('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure,
                             'private.reemplazo_dia_registro_venta(uuid)'::regprocedure,
                             'private.reemplazo_fecha_comercial(uuid,date)'::regprocedure,
                             'private.contrato_tiene_cuotas_pagadas(uuid)'::regprocedure,
                             'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure)
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT: una función nueva nombra una pieza cerrada de F7';
  end if;
  if exists (select 1 from private.puertas_analista_sin_vigencia() c
             where c.objeto in ('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)',
                                'private.reemplazo_dia_registro_venta(uuid)',
                                'private.reemplazo_fecha_comercial(uuid,date)',
                                'private.contrato_tiene_cuotas_pagadas(uuid)',
                                'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)')) then
    raise exception 'POSTFLIGHT: una función nueva entró al censo de vigencia del analista';
  end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto in ('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)',
                                'private.reemplazo_dia_registro_venta(uuid)',
                                'private.reemplazo_fecha_comercial(uuid,date)',
                                'private.contrato_tiene_cuotas_pagadas(uuid)',
                                'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)')) then
    raise exception 'POSTFLIGHT: una función nueva entró al censo analítico';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261017211313' and name = 'crm_reemplazar_inversion_vista_previa' and cardinality(statements) = 1
                   and md5(statements[1]) = '64274e1486a7dad98d8e90876c943c2e') then
    raise exception 'REGISTRO: la fila 20261017211313 / crm_reemplazar_inversion_vista_previa no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261017211313 / crm_reemplazar_inversion_vista_previa (1 sentencia: el archivo entero)';
end $post$;
commit;

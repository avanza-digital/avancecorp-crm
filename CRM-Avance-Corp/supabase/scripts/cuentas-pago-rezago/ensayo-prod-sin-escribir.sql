-- ENSAYO EN PRODUCCIÓN, SIN ESCRIBIR, de 20261001233019_crm_cuentas_pago_motivo_y_rezago.sql.
-- GENERADO por generar-derivados.py con el archivo real de la migración (md5 1f7b154d62932444e349ac382d7dac6a).
--
-- Corre la migración entera dentro de una transacción que TERMINA SIEMPRE en un error a propósito
-- («ENSAYO_DESHECHO»): no queda nada escrito, tampoco si algo falla antes. El resultado se lee en
-- el texto de ese error:
--   antes_sin_funciones / carga / despues : conteo por caso (el «antes» se cuenta dos veces: con
--                                           la regla nueva y con una consulta aparte)
--   pagos      : una cuota REAL marcada como pagada, por conexión directa, en un contrato de cada
--                caso bloqueado, en cada contrato que la carga vinculó y en uno que ya estaba bien
--   identidad  : sobre un contrato bloqueado, qué texto recibe un gestor de cartera (el detalle)
--                y qué texto recibe un analista (el genérico)
--   veredicto  : PASA (todo se probó y salió como dicta la regla), FALLA (algo salió distinto;
--                ver «fallos») o INCOMPLETO (nada falló, pero algo no se pudo probar; ver
--                «sin_probar»). todo_como_se_esperaba = true solo con PASA.
--   conexion   : con qué usuario de la base corrió (sirve para saber qué es «conexión directa»)
-- Si la propia migración se niega (preflight, un candidato en conciliación, el tope, un candado
-- ocupado), el error que verás es el SUYO y no ENSAYO_DESHECHO; tampoco queda nada escrito.
-- «Nada escrito» son los DATOS: mientras corre toma los mismos candados que la migración (unos
-- segundos), y puede consumir números de secuencia y dejar rastro en los registros del servidor.
-- Después, para convertir el argumento en un hecho: censo-sin-funciones.sql debe dar lo mismo que antes.
--   supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/ensayo-prod-sin-escribir.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $ensayo_antes$
declare
  v jsonb;
begin
  select coalesce(jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v
  from (select c.caso, count(*) as n from (
  select case
           when cp.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
           when cp.id is not null then 'cuenta_no_corresponde'
           when q.en_moneda = 1 then 'una_cuenta'
           when q.en_moneda > 1 then 'varias_cuentas'
           when q.otra_moneda > 0 then 'otra_moneda'
           else 'sin_cuenta'
         end as caso
  from public.contratos ct
  left join crm.contrato_cuentas_pago cp on cp.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  cross join lateral (
    select count(*) filter (where a.moneda = ct.moneda) as en_moneda,
           count(*) filter (where a.moneda <> ct.moneda) as otra_moneda
    from crm.cuentas_bancarias a
    where a.cliente_id = ct.cliente_id and a.activa
  ) q
  ) c group by c.caso) s;
  perform set_config('crm.ensayo_rezago_antes', v::text, true);
end;
$ensayo_antes$;

-- ───────────── la migración, tal cual (sin su begin/commit) ─────────────
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
declare
  v_huella text;
begin
  -- La carga decide con lo que lee DESPUÉS de tomar sus candados. En REPEATABLE READ o
  -- SERIALIZABLE leería una fotografía anterior al candado (podría no ver una segunda cuenta
  -- registrada mientras esperaba) y elegiría a ciegas: no se aplica en otro aislamiento.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REZAGO PREFLIGHT: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  select pg_catalog.md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('private.exigir_cuenta_pago_cronograma()');
  -- La huella de P-0XX S3 (primera vez) o la de esta migración (repetición).
  if v_huella is null
     or v_huella not in ('5efb8619e4342763ae77df2ee0bb1f61', 'd7618dcf85653943e62745513b3c4938') then
    raise exception 'REZAGO PREFLIGHT: el bloqueo de pagos vivo (%) no es el esperado; no se toca',
      coalesce(v_huella, 'no existe');
  end if;
  -- Las otras tres funciones: o no existen todavía, o son exactamente las de esta migración.
  if exists (
    select 1
    from (values
      ('private.cuenta_pago_diagnostico(uuid[])', 'a1dfb0c46b9365df308801bab9d5481a'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])', '4c45dbbfd85f5de82372b343b0b1dfc0'),
      ('crm.cuentas_pago_motivos_fn(uuid[])', '45898bb671a3bf536375a0fb5fb33ec6')
    ) as f(firma, huella)
    join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
    where pg_catalog.md5(p.prosrc) <> f.huella
  ) then
    raise exception 'REZAGO PREFLIGHT: alguna función de esta migración ya existe con otro cuerpo; no se pisa';
  end if;
  if pg_catalog.to_regclass('crm.contrato_cuentas_pago') is null
     or pg_catalog.to_regclass('crm.cuentas_bancarias') is null
     or pg_catalog.to_regclass('crm.cuotas_cuenta_pagada') is null
     or pg_catalog.to_regclass('crm.contrato_cuenta_pago_cambios') is null
     or pg_catalog.to_regclass('public.contratos') is null
     or pg_catalog.to_regclass('public.cronograma_pagos') is null
     or pg_catalog.to_regclass('private.backfill_cuentas_p0xx') is null
     or pg_catalog.to_regclass('private.conciliacion_cuentas_p0xx') is null
     or pg_catalog.to_regprocedure('public.es_gestor_cartera()') is null
     or pg_catalog.to_regprocedure('private.membresia_crm_revocada()') is null
     or pg_catalog.to_regprocedure('private.log_audit_crm()') is null
     or pg_catalog.to_regprocedure('auth.role()') is null then
    raise exception 'REZAGO PREFLIGHT: faltan dependencias';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_attribute a
      where a.attrelid = 'public.contratos'::regclass and not a.attisdropped
        and a.attname in ('id', 'numero_contrato', 'cliente_id', 'moneda', 'estado', 'es_demo')) <> 6
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.cuentas_bancarias'::regclass and not a.attisdropped
           and a.attname in ('id', 'cliente_id', 'moneda', 'activa')) <> 4
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.contrato_cuentas_pago'::regclass and not a.attisdropped
           and a.attname in ('id', 'contrato_id', 'cuenta_bancaria_id', 'creado_por')) <> 4
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'private.backfill_cuentas_p0xx'::regclass and not a.attisdropped
           and a.attname in ('tipo', 'fila_id', 'cliente_id', 'contrato_id', 'marca_actor',
                             'insertada_en', 'revertida_en')) <> 7
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'private.conciliacion_cuentas_p0xx'::regclass and not a.attisdropped
           and a.attname in ('clase', 'cliente_id', 'moneda', 'motivo')) <> 4 then
    raise exception 'REZAGO PREFLIGHT: alguna tabla no tiene las columnas esperadas';
  end if;
  -- El bloqueo debe seguir colgado de sus dos triggers, habilitados.
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_10_exigir_cuenta_pago_insert',
                         'trg_cronograma_pagos_10_exigir_cuenta_pago_update')
        and t.tgfoid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REZAGO PREFLIGHT: los triggers del bloqueo de pagos no están como se espera';
  end if;
  -- La carga confía en estos dos triggers del vínculo: coherencia cliente/moneda y bitácora.
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass
        and t.tgname in ('trg_contrato_cuenta_pago_coherente', 'trg_audit_contrato_cuentas_pago')
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REZAGO PREFLIGHT: faltan los triggers de coherencia o de bitácora del vínculo';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE')
     or not pg_catalog.has_schema_privilege('authenticated', 'crm', 'USAGE') then
    raise exception 'REZAGO PREFLIGHT: authenticated necesita USAGE sobre crm y private para la puerta INVOKER';
  end if;
  -- El diagnóstico es INVOKER y sin EXECUTE para nadie: solo funciona porque el bloqueo, el
  -- autorizador y él tienen el MISMO dueño (quien aplica), que además debe leer contratos,
  -- vínculos y cuentas sin RLS.
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false) then
    raise exception 'REZAGO PREFLIGHT: el dueño de las funciones debe tener bypassrls';
  end if;
  if (select pg_catalog.pg_get_userbyid(p.proowner) from pg_catalog.pg_proc p
      where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure)
     is distinct from current_user::text then
    raise exception 'REZAGO PREFLIGHT: quien aplica (%) no es el dueño del bloqueo de pagos', current_user;
  end if;
end;
$precondicion$;

-- ── 1. La regla, una sola vez ────────────────────────────────────────────────────────────────
-- INVOKER y sin EXECUTE para nadie: solo la llaman el bloqueo y el autorizador (ambos DEFINER, del
-- mismo dueño) y quien aplica migraciones (censo). Con NULL clasifica todos los contratos.
create or replace function private.cuenta_pago_diagnostico(p_contrato_ids uuid[] default null)
returns table (
  contrato_id uuid,
  numero_contrato text,
  cliente_id uuid,
  moneda text,
  estado text,
  es_demo boolean,
  caso text,
  cuentas_en_moneda integer,
  cuentas_otra_moneda integer,
  mensaje text
)
language sql
stable
security invoker
set search_path to ''
as $function$
  select
    ct.id,
    ct.numero_contrato,
    ct.cliente_id,
    ct.moneda,
    ct.estado,
    ct.es_demo,
    d.caso,
    q.en_moneda,
    q.otra_moneda,
    case d.caso
      when 'ok' then null
      when 'cuenta_no_corresponde' then pg_catalog.format(
        'Contrato %s: su cuenta de pago no es del cliente o de la moneda del contrato; no se paga hasta corregirla.',
        ct.numero_contrato)
      when 'una_cuenta' then pg_catalog.format(
        'Contrato %s sin cuenta de pago: el cliente ya tiene una cuenta en %s; falta vincularla a este contrato.',
        ct.numero_contrato, m.del_contrato)
      when 'varias_cuentas' then pg_catalog.format(
        'Contrato %s sin cuenta de pago: el cliente tiene %s cuentas en %s; confirma con él en cuál cobra este contrato.',
        ct.numero_contrato, q.en_moneda, m.del_contrato)
      when 'otra_moneda' then pg_catalog.format(
        'Contrato %s sin cuenta de pago: el contrato es en %s y el cliente solo tiene cuenta en %s; pídele una en %s.',
        ct.numero_contrato, m.del_contrato, m.la_otra, m.del_contrato)
      else pg_catalog.format(
        'Contrato %s sin cuenta de pago: el cliente no tiene ninguna cuenta bancaria vigente; pídele una en %s.',
        ct.numero_contrato, m.del_contrato)
    end
  from public.contratos ct
  left join crm.contrato_cuentas_pago cp on cp.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  -- Solo cuentan las cuentas ACTIVAS del cliente: una inactiva no sirve para un vínculo nuevo.
  cross join lateral (
    select (pg_catalog.count(*) filter (where a.moneda = ct.moneda))::integer as en_moneda,
           (pg_catalog.count(*) filter (where a.moneda <> ct.moneda))::integer as otra_moneda
    from crm.cuentas_bancarias a
    where a.cliente_id = ct.cliente_id
      and a.activa is true
  ) q
  -- 'ok' es EXACTAMENTE la condición del bloqueo: hay vínculo y su cuenta (activa o no) es del
  -- mismo cliente y de la misma moneda del contrato.
  cross join lateral (
    select case
      when cp.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
      when cp.id is not null then 'cuenta_no_corresponde'
      when q.en_moneda = 1 then 'una_cuenta'
      when q.en_moneda > 1 then 'varias_cuentas'
      when q.otra_moneda > 0 then 'otra_moneda'
      else 'sin_cuenta'
    end as caso
  ) d
  cross join lateral (
    select case ct.moneda when 'PEN' then 'soles' when 'USD' then 'dólares' else ct.moneda end as del_contrato,
           case ct.moneda when 'PEN' then 'dólares' when 'USD' then 'soles' else 'otra moneda' end as la_otra
  ) m
  where p_contrato_ids is null
     or ct.id = any (p_contrato_ids);
$function$;
revoke all on function private.cuenta_pago_diagnostico(uuid[]) from public, anon, authenticated, service_role;

-- ── 2. El bloqueo: igual de estricto; al rechazar dice el motivo ─────────────────────────────
create or replace function private.exigir_cuenta_pago_cronograma()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rol text;
  v_mensaje text;
begin
  if new.estado is distinct from 'pagado' then
    return new;
  end if;

  -- La cuenta vinculada puede haber sido versionada y estar inactiva: sigue
  -- siendo la instruccion contractual. Bloqueamos la fila del vinculo y del
  -- contrato hasta el COMMIT para no validar una fotografia que se borra o
  -- cambia de cliente/moneda durante el registro del pago.
  perform 1
  from crm.contrato_cuentas_pago cp
  join public.contratos ct on ct.id = cp.contrato_id
  join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  where cp.contrato_id = new.contrato_id
    and cb.cliente_id = ct.cliente_id
    and cb.moneda = ct.moneda
  for share of cp, ct;

  if not found then
    -- Solo aquí, con el pago YA rechazado, se calcula el motivo: el pago válido no llega a esta
    -- rama. El motivo nombra la moneda y cuántas cuentas tiene el cliente, así que se le dice
    -- únicamente a quien puede registrar pagos:
    --   · una conexión directa a la base (sin rol de la API y que NO entra por la API: la API
    --     siempre se conecta como authenticator);
    --   · el rol de servicio;
    --   · un gestor de cartera con la membresía CRM vigente.
    -- A cualquier otro —este trigger corre ANTES de la RLS en un INSERT— se le da el texto
    -- genérico de siempre.
    v_rol := nullif((select auth.role()), '');
    if (v_rol is null and session_user is distinct from 'authenticator')
       or v_rol = 'service_role'
       or ((select public.es_gestor_cartera()) is true
           and (select private.membresia_crm_revocada()) is false) then
      select d.mensaje into v_mensaje
      from private.cuenta_pago_diagnostico(array[new.contrato_id]) d;
    end if;
    raise exception using
      errcode = '23514',
      message = coalesce(v_mensaje, 'Sin cuenta de pago — requiere conciliación');
  end if;
  return new;
end;
$function$;
revoke all on function private.exigir_cuenta_pago_cronograma() from public, anon, authenticated, service_role;

-- ── 3. Lectura del motivo para la pantalla de Pagos ──────────────────────────────────────────
-- DEFINER porque authenticated no tiene permisos sobre vínculos ni cuentas. Misma compuerta que
-- crm.cuentas_pago_contratos_fn: gestor de cartera (admin, superadmin u operaciones) y sin la
-- membresía CRM revocada. Nunca clasifica «todos»: sin ids no devuelve nada.
create or replace function private.cuentas_pago_motivos_autorizado(p_contrato_ids uuid[])
returns table (contrato_id uuid, caso text, mensaje text)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if (select private.membresia_crm_revocada()) is not false
     or (select public.es_gestor_cartera()) is not true then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  end if;
  if coalesce(pg_catalog.cardinality(p_contrato_ids), 0) > 5000 then
    raise exception using errcode = '22023', message = 'Demasiados contratos en una sola consulta';
  end if;
  if coalesce(pg_catalog.cardinality(p_contrato_ids), 0) = 0 then
    return;
  end if;

  return query
  select d.contrato_id, d.caso, d.mensaje
  from private.cuenta_pago_diagnostico(p_contrato_ids) d
  where d.caso <> 'ok';
end;
$function$;
revoke all on function private.cuentas_pago_motivos_autorizado(uuid[]) from public, anon, authenticated, service_role;
grant execute on function private.cuentas_pago_motivos_autorizado(uuid[]) to authenticated;

create or replace function crm.cuentas_pago_motivos_fn(p_contrato_ids uuid[])
returns table (contrato_id uuid, caso text, mensaje text)
language sql
stable
security invoker
set search_path to ''
as $function$
  select * from private.cuentas_pago_motivos_autorizado(p_contrato_ids);
$function$;
revoke all on function crm.cuentas_pago_motivos_fn(uuid[]) from public, anon, authenticated, service_role;
grant execute on function crm.cuentas_pago_motivos_fn(uuid[]) to authenticated;

comment on function private.cuenta_pago_diagnostico(uuid[]) is 'La regla ÚNICA de la cuenta de pago por contrato: caso (ok, una_cuenta, varias_cuentas, otra_moneda, sin_cuenta, cuenta_no_corresponde), cuántas cuentas ACTIVAS tiene el cliente en la moneda del contrato y en la otra, y el motivo redactado para la persona (sin números de cuenta, CCI ni documentos). ok = la condición exacta del bloqueo de pagos. NULL = todos los contratos (censo). INVOKER y sin EXECUTE para nadie: solo la usan el bloqueo, el autorizador de la puerta y quien aplica migraciones.';
comment on function private.exigir_cuenta_pago_cronograma() is 'Trigger BEFORE en public.cronograma_pagos: una cuota solo pasa a pagado si el contrato tiene vínculo con una cuenta del mismo cliente y moneda (bloquea vínculo y contrato FOR SHARE hasta el COMMIT). Al rechazar (23514) dice el motivo de private.cuenta_pago_diagnostico solo a quien puede registrar pagos (conexión directa que no entra por la API, rol de servicio, o gestor de cartera con membresía CRM vigente); a los demás, el texto genérico. El pago válido no calcula el motivo. SECURITY DEFINER porque quien registra el pago no tiene permisos sobre vínculos ni cuentas.';
comment on function private.cuentas_pago_motivos_autorizado(uuid[]) is 'Motivo por el que no se pueden pagar los contratos pedidos (solo los que NO están ok). Compuerta de crm.cuentas_pago_contratos_fn: gestor de cartera sin la membresía CRM revocada; máximo 5000 ids; sin ids no devuelve nada. SECURITY DEFINER porque authenticated no tiene permisos sobre vínculos ni cuentas.';
comment on function crm.cuentas_pago_motivos_fn(uuid[]) is 'Puerta (INVOKER) del motivo por el que un contrato no se puede pagar: contrato_id, caso y mensaje para la persona. La usa Pagos del portal. Solo gestor de cartera.';

-- ── 4. Carga del rezago: solo donde hay UNA cuenta activa posible ────────────────────────────
-- Candados. La tabla de cuentas en modo EXCLUSIVE, antes que nada: espera a que termine quien
-- esté registrando, cambiando o retirando una cuenta (esos caminos bloquean primero la fila de la
-- cuenta y después escriben; tomar aquí un candado más débil permitiría un abrazo mortal) y,
-- mientras dura la carga, nadie mueve cuentas. Las lecturas siguen permitidas: registrar un pago
-- solo LEE cuentas. Después, cada contrato FOR SHARE —el orden de un pago: contrato → vínculo— y
-- bajo ese candado se vuelve a clasificar. Como en S1, no se toma el candado consultivo del alta.
-- Si la espera pasa de lock_timeout, se cancela todo sin dejar nada a medias.
lock table crm.cuentas_bancarias in exclusive mode;

do $rezago$
declare
  c_marca constant text := 'migracion:rezago-vinculos:20261001';
  -- El rezago conocido es de 23 contratos (censo del 01/10/2026). Más candidatos que eso no es
  -- rezago: es que algo cambió (p. ej. vínculos borrados) y no se vincula a ciegas.
  c_tope constant integer := 23;
  v_antes jsonb;
  v_despues jsonb;
  v_candidatos integer;
  v_hechos integer := 0;
  v_rastro integer;
  v_discrepancias integer;
  v_fila record;
  v_d record;
  v_cuenta uuid;
  v_vinculo uuid;
  v_numeros text[] := '{}';
begin
  select coalesce(pg_catalog.jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_antes
  from (select d.caso, pg_catalog.count(*) as n
        from private.cuenta_pago_diagnostico() d group by d.caso) s;

  v_candidatos := coalesce((v_antes ->> 'una_cuenta')::integer, 0);
  if v_candidatos > c_tope then
    raise exception 'REZAGO: % contratos por vincular y el rezago conocido es de %; no se toca nada',
      v_candidatos, c_tope;
  end if;

  for v_fila in
    select d.contrato_id
    from private.cuenta_pago_diagnostico() d
    where d.caso = 'una_cuenta'
    order by d.contrato_id
  loop
    perform 1 from public.contratos ct where ct.id = v_fila.contrato_id for share;

    select d.cliente_id, d.moneda, d.numero_contrato into v_d
    from private.cuenta_pago_diagnostico(array[v_fila.contrato_id]) d
    where d.caso = 'una_cuenta';
    if not found then
      continue;
    end if;

    -- La guarda de S1: si el perfil legado de ese cliente y moneda quedó marcado con una
    -- instrucción inválida o distinta para el mismo CCI, la única cuenta no es inequívoca.
    if exists (
      select 1 from private.conciliacion_cuentas_p0xx x
      where x.clase = 'perfil' and x.cliente_id = v_d.cliente_id and x.moneda = v_d.moneda
        and x.motivo in ('perfil_invalido', 'mismo_cci_datos_distintos')
    ) then
      raise exception 'REZAGO: el contrato % tiene una sola cuenta, pero su perfil legado quedó en conciliación; no se vincula nada hasta que Operaciones lo confirme',
        v_d.numero_contrato;
    end if;

    -- STRICT: si no es exactamente una, la migración entera se cancela.
    select cb.id into strict v_cuenta
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_d.cliente_id
      and cb.moneda = v_d.moneda
      and cb.activa is true;

    -- El trigger de coherencia cancela toda la migración si la pareja no vale.
    insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id, creado_por)
    values (v_fila.contrato_id, v_cuenta, null)
    returning id into v_vinculo;

    insert into private.backfill_cuentas_p0xx (tipo, fila_id, cliente_id, contrato_id, marca_actor)
    values ('vinculo', v_vinculo, v_d.cliente_id, v_fila.contrato_id, c_marca);

    v_hechos := v_hechos + 1;
    v_numeros := v_numeros || v_d.numero_contrato;
  end loop;

  select coalesce(pg_catalog.jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_despues
  from (select d.caso, pg_catalog.count(*) as n
        from private.cuenta_pago_diagnostico() d group by d.caso) s;

  -- Nada de pérdida silenciosa: si el antes y el después no cuadran, se cancela todo.
  if v_hechos <> v_candidatos then
    raise exception 'REZAGO: había % contratos por vincular y se vincularon %', v_candidatos, v_hechos;
  end if;
  if coalesce((v_despues ->> 'una_cuenta')::integer, 0) <> 0 then
    raise exception 'REZAGO: quedaron contratos con una sola cuenta posible sin vincular: %', v_despues;
  end if;
  if coalesce((v_despues ->> 'ok')::integer, 0) <> coalesce((v_antes ->> 'ok')::integer, 0) + v_hechos then
    raise exception 'REZAGO: los contratos ok no subieron en lo vinculado (antes %, después %, vinculados %)',
      v_antes, v_despues, v_hechos;
  end if;
  if (v_despues - 'ok' - 'una_cuenta') is distinct from (v_antes - 'ok' - 'una_cuenta') then
    raise exception 'REZAGO: cambió un caso que la carga no debía tocar (antes %, después %)', v_antes, v_despues;
  end if;
  select pg_catalog.count(*) into v_rastro
  from private.backfill_cuentas_p0xx b
  join crm.contrato_cuentas_pago l on l.id = b.fila_id and l.contrato_id = b.contrato_id
  join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id and cb.cliente_id = b.cliente_id and cb.activa is true
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and b.insertada_en = pg_catalog.now();
  if v_rastro <> v_hechos then
    raise exception 'REZAGO: el rastro (%) no coincide con los vínculos creados (%)', v_rastro, v_hechos;
  end if;
  -- La regla vive en dos sitios (la consulta del bloqueo y el caso 'ok' del diagnóstico): con los
  -- contratos reales delante, no puede haber ni uno en que digan cosas distintas.
  select pg_catalog.count(*) into v_discrepancias
  from private.cuenta_pago_diagnostico() d
  where (d.caso = 'ok') is distinct from exists (
    select 1
    from crm.contrato_cuentas_pago cp
    join public.contratos ct on ct.id = cp.contrato_id
    join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
    where cp.contrato_id = d.contrato_id
      and cb.cliente_id = ct.cliente_id
      and cb.moneda = ct.moneda);
  if v_discrepancias <> 0 then
    raise exception 'REZAGO: en % contratos el diagnóstico y el bloqueo no dicen lo mismo', v_discrepancias;
  end if;

  -- Para la última sentencia del archivo (después del COMMIT): el conteo antes y después.
  perform pg_catalog.set_config('crm.rezago_vinculos_resultado',
    pg_catalog.jsonb_build_object('antes', v_antes, 'despues', v_despues,
      'vinculados', v_hechos, 'contratos', pg_catalog.to_jsonb(v_numeros), 'marca', c_marca)::text, false);
  raise notice 'REZAGO: antes % · después % · vinculados % %', v_antes, v_despues, v_hechos, v_numeros;
end;
$rezago$;

-- ── 5. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  for v_f in
    select * from (values
      ('private.exigir_cuenta_pago_cronograma()', null, true, 'v', 'd7618dcf85653943e62745513b3c4938'),
      ('private.cuenta_pago_diagnostico(uuid[])', null, false, 's', 'a1dfb0c46b9365df308801bab9d5481a'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])', 'authenticated', true, 's', '4c45dbbfd85f5de82372b343b0b1dfc0'),
      ('crm.cuentas_pago_motivos_fn(uuid[])', 'authenticated', false, 's', '45898bb671a3bf536375a0fb5fb33ec6')
    ) as f(firma, rol, definer, volatilidad, huella)
  loop
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure
                     and pg_catalog.md5(p.prosrc) = v_f.huella
                     and p.prosecdef = v_f.definer and p.provolatile = v_f.volatilidad
                     and pg_catalog.pg_get_userbyid(p.proowner) = current_user::text) then
      raise exception 'REZAGO POSTFLIGHT: cuerpo, DEFINER/INVOKER, volatilidad o dueño inesperados en %', v_f.firma;
    end if;
    if exists (
         select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
         where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
           and a.grantee <> p.proowner
           and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid))
       or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
       or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE'))
       or not exists (select 1 from pg_catalog.pg_proc p
                      where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""'])
       or pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'REZAGO POSTFLIGHT: EXECUTE, search_path o comentario inesperados en %', v_f.firma;
    end if;
  end loop;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_10_exigir_cuenta_pago_insert',
                         'trg_cronograma_pagos_10_exigir_cuenta_pago_update')
        and t.tgfoid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REZAGO POSTFLIGHT: los triggers del bloqueo de pagos no quedaron como estaban';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
-- ───────────── fin de la migración ─────────────

do $ensayo_fin$
declare
  c_generico constant text := 'Sin cuenta de pago — requiere conciliación';
  v_antes jsonb := current_setting('crm.ensayo_rezago_antes', true)::jsonb;
  v_carga jsonb := current_setting('crm.rezago_vinculos_resultado', true)::jsonb;
  v_despues jsonb;
  v_pagos jsonb := '[]'::jsonb;
  v_identidad jsonb := '[]'::jsonb;
  v_fallos text[] := array[]::text[];
  v_sin_probar text[] := array[]::text[];
  r record;
  v_caso record;
  v_bloqueado record;
  v_quien record;
  v_cuota uuid;
  v_resultado text;
  v_codigo text;
  v_mensaje text;
  v_bien boolean;
  v_probados integer := 0;
begin
  select coalesce(jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_despues
  from (select d.caso, count(*) as n from private.cuenta_pago_diagnostico() d group by d.caso) s;

  if v_antes is distinct from (v_carga -> 'antes') then
    v_fallos := v_fallos || 'el conteo previo hecho sin funciones no coincide con el de la regla nueva'::text;
  end if;

  -- 1) Pagos por conexión directa (sin usuario de la API: se espera el detalle).
  for r in
    (select distinct on (d.caso) d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'bloqueado'::text as que
     from private.cuenta_pago_diagnostico() d
     where d.caso <> 'ok'
       and exists (select 1 from public.cronograma_pagos cp
                   where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
     order by d.caso, d.es_demo, d.numero_contrato)
    union all
    (select d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'vinculado por la carga'
     from private.backfill_cuentas_p0xx b
     join private.cuenta_pago_diagnostico() d on d.contrato_id = b.contrato_id
     where b.tipo = 'vinculo' and b.marca_actor = 'migracion:rezago-vinculos:20261001' and b.insertada_en = now())
    union all
    (select d.contrato_id, d.numero_contrato, d.caso, d.mensaje, 'ya estaba bien'
     from private.cuenta_pago_diagnostico() d
     where d.caso = 'ok' and d.estado = 'activo'
       and not exists (select 1 from private.backfill_cuentas_p0xx b
                       where b.tipo = 'vinculo' and b.contrato_id = d.contrato_id and b.insertada_en = now())
       and exists (select 1 from public.cronograma_pagos cp
                   where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
     order by d.es_demo desc, d.numero_contrato
     limit 1)
  loop
    select cp.id into v_cuota
    from public.cronograma_pagos cp
    where cp.contrato_id = r.contrato_id and cp.estado in ('pendiente', 'vencido')
    order by cp.fecha_programada, cp.numero_cuota
    limit 1;
    v_codigo := null;
    v_mensaje := null;
    if v_cuota is null then
      v_resultado := 'sin cuota pendiente que probar';
      v_bien := null;
      v_sin_probar := v_sin_probar
        || format('contrato %s (%s): no tiene ninguna cuota pendiente que probar', r.numero_contrato, r.que);
    else
      begin
        update public.cronograma_pagos
             set estado = 'pagado',
                 fecha_pago_real = (now() at time zone 'America/Lima')::date,
                 monto_pagado = monto_programado
           where id = v_cuota;
        v_resultado := 'pagada';
      exception when others then
        v_resultado := 'bloqueada';
        v_codigo := sqlstate;
        v_mensaje := sqlerrm;
      end;
      v_bien := case when r.caso = 'ok' then v_resultado = 'pagada'
                     else v_resultado = 'bloqueada' and v_codigo = '23514' and v_mensaje = r.mensaje end;
      if v_bien is not true then
        v_fallos := v_fallos
          || format('contrato %s (%s, caso %s): %s %s', r.numero_contrato, r.que, r.caso, v_resultado, coalesce(v_mensaje, ''));
      end if;
    end if;
    v_pagos := v_pagos || jsonb_build_object(
      'contrato', r.numero_contrato, 'caso', r.caso, 'que', r.que,
      'resultado', v_resultado, 'codigo', v_codigo, 'mensaje', v_mensaje, 'como_se_esperaba', v_bien);
  end loop;

  -- Cobertura: un ensayo que no pudo probar algo NO es un ensayo que pasó. Cada caso bloqueado
  -- que exista tiene que haberse probado, y también un contrato que ya estaba bien.
  for v_caso in
    select c.caso, c.n
    from (select key as caso, value::text::integer as n from jsonb_each(v_despues)) c
    where c.caso <> 'ok' and c.n > 0
  loop
    if not exists (select 1 from jsonb_array_elements(v_pagos) x
                   where x ->> 'caso' = v_caso.caso and x ->> 'que' = 'bloqueado') then
      v_sin_probar := v_sin_probar
        || format('caso %s: hay %s contratos y ninguno con una cuota pendiente que probar', v_caso.caso, v_caso.n);
    end if;
  end loop;
  if not exists (select 1 from jsonb_array_elements(v_pagos) x where x ->> 'que' = 'ya estaba bien') then
    v_sin_probar := v_sin_probar || 'ningún contrato que ya estaba bien tiene una cuota pendiente que probar'::text;
  end if;

  -- 2) A quién se le dice el detalle. Va AL FINAL: la identidad simulada queda puesta hasta el
  --    error que deshace todo. No cambia de rol: solo los datos de sesión que lee el bloqueo.
  select d.contrato_id, d.numero_contrato, d.caso, d.mensaje into v_bloqueado
  from private.cuenta_pago_diagnostico() d
  where d.caso <> 'ok'
    and exists (select 1 from public.cronograma_pagos cp
                where cp.contrato_id = d.contrato_id and cp.estado in ('pendiente', 'vencido'))
  order by d.es_demo, d.numero_contrato
  limit 1;
  if not found then
    v_sin_probar := v_sin_probar || 'identidad: no hay ningún contrato bloqueado con una cuota pendiente'::text;
  else
    select cp.id into v_cuota
    from public.cronograma_pagos cp
    where cp.contrato_id = v_bloqueado.contrato_id and cp.estado in ('pendiente', 'vencido')
    order by cp.fecha_programada, cp.numero_cuota
    limit 1;
    for v_quien in
      (select 'gestor de cartera'::text as papel, p.id, true as detalle
       from public.perfiles p
       where p.rol in ('admin', 'superadmin', 'operaciones') and p.activo
         and not exists (select 1 from crm.equipo e where e.perfil_id = p.id and e.activo is false)
       order by p.id limit 1)
      union all
      (select 'analista (no gestor)', p.id, false
       from public.perfiles p
       where p.rol = 'analista' and p.activo
       order by p.id limit 1)
    loop
      v_probados := v_probados + 1;
      perform set_config('request.jwt.claim.sub', v_quien.id::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims',
        jsonb_build_object('sub', v_quien.id, 'role', 'authenticated')::text, true);
      v_codigo := null;
      v_mensaje := null;
      begin
        update public.cronograma_pagos
             set estado = 'pagado',
                 fecha_pago_real = (now() at time zone 'America/Lima')::date,
                 monto_pagado = monto_programado
           where id = v_cuota;
        v_resultado := 'pagada';
      exception when others then
        v_resultado := 'bloqueada';
        v_codigo := sqlstate;
        v_mensaje := sqlerrm;
      end;
      v_bien := v_resultado = 'bloqueada' and v_codigo = '23514'
                and v_mensaje = case when v_quien.detalle then v_bloqueado.mensaje else c_generico end;
      if v_bien is not true then
        v_fallos := v_fallos
          || format('identidad %s: %s %s', v_quien.papel, v_resultado, coalesce(v_mensaje, ''));
      end if;
      v_identidad := v_identidad || jsonb_build_object(
        'quien', v_quien.papel, 'contrato', v_bloqueado.numero_contrato, 'caso', v_bloqueado.caso,
        'resultado', v_resultado, 'codigo', v_codigo, 'mensaje', v_mensaje, 'como_se_esperaba', v_bien);
    end loop;
    if v_probados < 2 then
      v_sin_probar := v_sin_probar
        || 'identidad: falta un gestor de cartera vigente o un analista activo con quien probar'::text;
    end if;
  end if;

  raise exception 'ENSAYO_DESHECHO >> %', jsonb_build_object(
    'veredicto', case when cardinality(v_fallos) > 0 then 'FALLA'
                      when cardinality(v_sin_probar) > 0 then 'INCOMPLETO'
                      else 'PASA' end,
    'fallos', to_jsonb(v_fallos), 'sin_probar', to_jsonb(v_sin_probar),
    'conexion', jsonb_build_object('session_user', session_user::text, 'current_user', current_user::text),
    'antes_sin_funciones', v_antes, 'carga', v_carga, 'despues', v_despues,
    'pagos', v_pagos, 'identidad', v_identidad,
    'todo_como_se_esperaba', cardinality(v_fallos) = 0 and cardinality(v_sin_probar) = 0);
end;
$ensayo_fin$;

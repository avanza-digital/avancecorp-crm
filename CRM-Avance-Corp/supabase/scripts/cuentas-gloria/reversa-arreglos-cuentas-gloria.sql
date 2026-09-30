-- REVERSA de 20260927020317_crm_cuentas_gloria_motivo_y_cuenta_retirada.
-- Devuelve byte a byte las piezas de la F3 (núcleo del cambio, lectura de contratos y regla del
-- motivo). Se niega si las piezas vivas no son las de esta migración (huella 2d448025afaa5d8a9734c7f4fce65799).
begin;
set local lock_timeout = '5s';
do $pre$
declare v_huella text;
begin
  select pg_catalog.md5(pg_catalog.string_agg(p.oid::regprocedure::text || '|' || pg_catalog.md5(p.prosrc)
           || '|' || coalesce(pg_catalog.md5(pg_catalog.obj_description(p.oid, 'pg_proc')), '-'), E'\n'
           order by p.oid::regprocedure::text))
    into v_huella
  from pg_catalog.pg_proc p
  where p.oid in (to_regprocedure('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)'),
                  to_regprocedure('private.contratos_cuenta_pago_cliente_autorizado(uuid)'),
                  to_regprocedure('crm.contratos_cuenta_pago_cliente_fn(uuid)'));
  if v_huella is distinct from '2d448025afaa5d8a9734c7f4fce65799' then
    raise exception 'REVERSA: las piezas vivas no son las de estos arreglos (huella %); no se toca', v_huella;
  end if;
end $pre$;

create or replace function private.cambiar_cuenta_pago_contratos_autorizado(
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
  v_etag text;
  v_en_curso text;
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
  -- El mismo archivo subido otra vez con otra ruta tampoco vale: se compara la huella del
  -- contenido que calcula Storage (eTag), no un dato del navegador.
  v_etag := nullif(pg_catalog.btrim(v_obj.metadata->>'eTag', '"'), '');
  if v_etag is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('respaldo-etag:' || v_etag, 0));
    if exists (select 1 from crm.contrato_cuenta_pago_cambios c
               join storage.objects o on o.bucket_id = 'respaldos-cambio-cuenta' and o.name = c.respaldo_ruta
               where c.solicitud_id <> p_solicitud_id
                 and pg_catalog.btrim(o.metadata->>'eTag', '"') = v_etag) then
      raise exception using errcode = '22023', message = 'Ese correo ya respalda otro cambio registrado; revisa el historial o adjunta el correo de esta solicitud';
    end if;
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

  -- Un aviso al cliente en curso para estos contratos (reservado y sin confirmar): si el cambio
  -- entrara ahora, ese aviso anunciaría una cuenta que este cambio deja atrás. Con los enlaces ya
  -- bloqueados, toda reserva hecha antes está confirmada en la base y se ve aquí.
  select ct.numero_contrato into v_en_curso
  from crm.contrato_cuenta_pago_cambios c
  join crm.cambio_cuenta_avisos av on av.solicitud_id = c.solicitud_id
  join public.contratos ct on ct.id = c.contrato_id
  where c.contrato_id = any(v_ids)
    and av.reserva is not null
    and av.reclamado_en > pg_catalog.clock_timestamp() - interval '10 minutes'
  order by ct.numero_contrato
  limit 1;
  if v_en_curso is not null then
    raise exception using errcode = '22023',
      message = pg_catalog.format('Se está enviando al cliente el aviso de un cambio anterior del contrato %s; espera unos segundos y vuelve a intentar', v_en_curso);
  end if;

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

drop function crm.contratos_cuenta_pago_cliente_fn(uuid);
drop function private.contratos_cuenta_pago_cliente_autorizado(uuid);
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

comment on function private.contratos_cuenta_pago_cliente_autorizado(uuid) is 'Contratos abiertos del cliente con su cuenta de pago, cuotas pendientes y cuotas pagadas por cuenta (con las inferidas aparte). Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre enlace ni sellos. DATOS SENSIBLES.';
comment on function crm.contratos_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) de los contratos abiertos del cliente con su cuenta de pago. Solo admin.';

alter table crm.contrato_cuenta_pago_cambios drop constraint contrato_cuenta_pago_cambios_motivo_valido;
alter table crm.contrato_cuenta_pago_cambios add constraint contrato_cuenta_pago_cambios_motivo_valido
  check (motivo = btrim(motivo) and length(motivo) between 5 and 500);

do $chk$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc where oid = 'private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)'::regprocedure) <> '179140cc3e79d812bffef136f06e7edf'
     or (select md5(prosrc) from pg_catalog.pg_proc where oid = 'private.contratos_cuenta_pago_cliente_autorizado(uuid)'::regprocedure) <> '7b8f1e9658788425659566b2e37a956d'
     or (select md5(prosrc) from pg_catalog.pg_proc where oid = 'crm.contratos_cuenta_pago_cliente_fn(uuid)'::regprocedure) <> '4720e000300e7eda76f9a1f45ecd2c34' then
    raise exception 'REVERSA: las piezas repuestas no son las de la F3';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;

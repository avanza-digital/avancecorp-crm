-- Conversión por cierre comercial, con acreditación hasta finalizar el día 10.
-- CANDIDATA EN ENSAYO: conciliación inicial y gates completos pendientes.
-- Ensayo remoto autorizado el 27/09/2026; NO autorizada para producción.

-- Detenerse ante drift: no sobrescribir otra corrección publicada mientras se
-- preparaba esta entrega. Los cuerpos se contrastaron en vivo y en el banco.
do $guardia$
declare r record;
begin
  for r in select * from (values
    ('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])','2898d61d586704a79249ff6cc18bdf22'),
    ('private.cierre_mes_ventana_desde(date)','c9827033f0b810fb6d20f1f8e93d8249'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)','548b517e2a4c64f36d787c22856b5ee3'),
    ('crm.corregir_fecha_cierre_comercial(uuid,date,text)','fcfd9b4d59e2ee2190fc5d530b915d71')
  ) as esperada(firma,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'La definicion de % cambio; revisar antes de aplicar',r.firma;
    end if;
  end loop;
end;
$guardia$;

-- Una sola frontera para admisión y sello: día 11 a las 00:00 de Lima,
-- extremo excluido. No depende del timezone de la sesión ni de Cron.
create or replace function private.conversion_plazo_hasta(p_periodo date)
returns timestamptz
language plpgsql immutable strict security invoker
set search_path = ''
as $func$
begin
  if not pg_catalog.isfinite(p_periodo)
     or p_periodo <> pg_catalog.date_trunc('month', p_periodo::timestamp)::date then
    raise exception 'El periodo debe ser el primer dia de un mes finito'
      using errcode = '22023';
  end if;
  return (p_periodo::timestamp + interval '1 month 10 days')
    at time zone 'America/Lima';
end;
$func$;

-- Solo evalúa hechos recibidos del escritor interno. No es una RPC y NO usa
-- now(): un crédito válido no caduca al leerlo después del corte o del sello.
-- La capa de hechos conservará la decisión bajo los candados mensuales.
create or replace function private.conversion_decidir_plazo(
  p_fecha_comercial date,
  p_confirmado_en timestamptz,
  p_vinculado_en timestamptz,
  p_sellado_en timestamptz
)
returns table (
  periodo_comercial date,
  plazo_hasta timestamptz,
  acreditado_en timestamptz,
  estado text
)
language plpgsql immutable security invoker
set search_path = ''
as $func$
begin
  if (p_fecha_comercial is not null and not pg_catalog.isfinite(p_fecha_comercial))
     or (p_confirmado_en is not null and not pg_catalog.isfinite(p_confirmado_en))
     or (p_vinculado_en is not null and not pg_catalog.isfinite(p_vinculado_en))
     or (p_sellado_en is not null and not pg_catalog.isfinite(p_sellado_en)) then
    raise exception 'La acreditacion requiere fechas finitas' using errcode = '22023';
  end if;

  periodo_comercial := pg_catalog.date_trunc('month', p_fecha_comercial::timestamp)::date;
  plazo_hasta := private.conversion_plazo_hasta(periodo_comercial);
  -- GREATEST omite NULL en Postgres: no debe hacer parecer confirmada una
  -- solicitud pendiente solo porque existe el vínculo (ni a la inversa).
  acreditado_en := case when p_confirmado_en is not null and p_vinculado_en is not null
    then greatest(p_confirmado_en, p_vinculado_en) end;
  estado := case
    when p_fecha_comercial is null then 'pendiente_fuente'
    when p_confirmado_en is null then 'pendiente_confirmacion'
    when p_vinculado_en is null then 'pendiente_vinculo'
    when p_fecha_comercial > (acreditado_en at time zone 'America/Lima')::date
      then 'fecha_futura'
    when acreditado_en >= plazo_hasta then 'fuera_de_plazo'
    when p_sellado_en is not null and acreditado_en >= p_sellado_en then 'mes_sellado'
    else 'acreditada'
  end;
  return next;
end;
$func$;

-- Reloj exclusivamente de servidor. El banco puede sustituir esta función
-- dentro de una transacción revertida; no existe parámetro ni setting cliente.
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker
set search_path = ''
as $func$ select pg_catalog.clock_timestamp() $func$;

-- Hecho estable de acreditación; no modifica el ledger de asignaciones ni
-- sus relojes. La fuente conserva su UUID aunque se retire el contrato.
-- La tabla no tiene puerta de escritura/lectura directa para clientes.
create table crm.conversion_acreditaciones (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  lead_id uuid not null unique references crm.leads(id),
  episodio_id uuid not null unique references crm.lead_asignaciones(id),
  inversionista_id uuid references crm.inversionistas(id),
  analista_id uuid,
  origen text not null,
  fuente_tipo text not null check (fuente_tipo in ('contrato','cierre_externo')),
  fuente_id uuid not null,
  fecha_comercial date not null,
  confirmado_en timestamptz not null,
  vinculado_en timestamptz not null,
  acreditado_en timestamptz not null,
  periodo_comercial date not null,
  plazo_hasta timestamptz not null,
  estado text not null check (estado in ('acreditada','fuera_de_plazo','mes_sellado',
    'fecha_futura','fuente_demo','operacion_cartera')),
  sellado_en timestamptz,
  incluida_en_sello boolean,
  politica_desde date not null default date '2026-09-01'
    check (politica_desde = date '2026-09-01'),
  motivo text not null check (length(btrim(motivo)) between 5 and 300),
  creado_en timestamptz not null default clock_timestamp(),
  actualizado_en timestamptz not null default clock_timestamp(),
  unique (fuente_tipo, fuente_id),
  check ((sellado_en is null) = (incluida_en_sello is null)),
  check (periodo_comercial = date_trunc('month',fecha_comercial::timestamp)::date),
  check (acreditado_en = greatest(confirmado_en,vinculado_en)),
  check (plazo_hasta = private.conversion_plazo_hasta(periodo_comercial))
);
alter table crm.conversion_acreditaciones enable row level security;
revoke all on table crm.conversion_acreditaciones from public, anon, authenticated, service_role;
create index conversion_acreditaciones_periodo_analista_idx
  on crm.conversion_acreditaciones(periodo_comercial,analista_id);
create index conversion_acreditaciones_persona_idx
  on crm.conversion_acreditaciones(inversionista_id);
create trigger trg_audit_conversion_acreditaciones
  after insert or update or delete on crm.conversion_acreditaciones
  for each row execute function private.log_audit_crm();

-- Instalación ≠ activación. Una fila privada evita que instalar el esquema
-- borre temporalmente el crédito legado. Sólo la conciliación atómica activa
-- la política; los UUID del manifiesto real nunca se publican en el repositorio.
create table crm.conversion_politica (
  unica boolean primary key default true check (unica),
  vigente_desde date not null default date '2026-09-01' check (vigente_desde=date '2026-09-01'),
  activada_en timestamptz,
  manifiesto_huella text,
  resultado jsonb,
  check ((activada_en is null and manifiesto_huella is null and resultado is null)
    or (activada_en is not null and manifiesto_huella is not null and resultado is not null))
);
alter table crm.conversion_politica enable row level security;
revoke all on table crm.conversion_politica from public,anon,authenticated,service_role;
create trigger trg_audit_conversion_politica
  after insert or update or delete on crm.conversion_politica
  for each row execute function private.log_audit_crm();
insert into crm.conversion_politica(unica) values(true);

-- Una sola elegibilidad viva para lector, estado e inclusión en la foto.
-- No añade triggers ni cambia las puertas de contratos en public.
create or replace function private.conversion_exclusion_fuente(p_tipo text,p_id uuid)
returns text language sql stable security invoker set search_path=''
as $func$
  select case p_tipo
    when 'contrato' then coalesce((select case
      when coalesce(c.es_demo,false) then 'fuente_demo'
      when c.categoria<>'nuevo' or exists(select 1 from crm.operaciones_cartera o
        where o.contrato_nuevo_id=c.id) then 'operacion_cartera'
      else 'elegible' end from public.contratos c where c.id=p_id),'fuente_retirada')
    when 'cierre_externo' then coalesce((select case when ce.es_cierre_inicial
      then 'elegible' else 'operacion_cartera' end from crm.cierres_externos ce where ce.id=p_id),'fuente_retirada')
    else 'fuente_retirada' end
$func$;
revoke all on function private.conversion_exclusion_fuente(text,uuid) from public,anon,authenticated,service_role;

-- El mes se inserta bajo el candado de cerrar_periodo. Guardar la pertenencia
-- de CADA acreditación a esa foto: el estado de admisión no prueba que una
-- fuente siguiera siendo elegible al sellar. Una baja anterior no crea deuda;
-- una baja posterior no borra la prueba del crédito incluido en el sello.
create or replace function private.conversion_fijar_sello_trg()
returns trigger language plpgsql security definer set search_path=''
as $func$
begin
  if new.periodo>=date '2026-09-01' and exists(
    select 1 from crm.conversion_politica where activada_en is not null) then
    perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),
      (new.periodo-date '2000-01-01')::integer);
    update crm.conversion_acreditaciones ca set sellado_en=new.cerrado_en,
      incluida_en_sello=(ca.estado='acreditada'
        and not private.cierre_externo_anulado(ca.lead_id)
        and private.conversion_exclusion_fuente(ca.fuente_tipo,ca.fuente_id)='elegible'),
      actualizado_en=private.conversion_instante_servidor()
    where ca.periodo_comercial=new.periodo and ca.sellado_en is null;
  end if;
  return new;
end;
$func$;
revoke all on function private.conversion_fijar_sello_trg() from public,anon,authenticated,service_role;
create trigger trg_conversion_fijar_sello after insert on crm.periodos_cerrados
  for each row execute function private.conversion_fijar_sello_trg();

-- La puerta auditada de retirada archiva en CRM antes de borrar el contrato.
-- Serializar aquí con el sello incluso si el lead apunta a otro contrato
-- legado. No basta el FK SET NULL de leads, ni se añade un trigger a public.
create or replace function private.conversion_bloquear_retiro_trg()
returns trigger language plpgsql security definer set search_path=''
as $func$
declare v_periodo date;
begin
  if not exists(select 1 from crm.conversion_acreditaciones
      where fuente_tipo='contrato' and fuente_id=new.contrato_id) then return new; end if;
  -- La eliminación ya posee el contrato. NOWAIT evita un ciclo con otra
  -- puerta que posea el lead y espere el contrato; el caller debe reintentar.
  perform 1 from crm.leads l where l.contrato_id=new.contrato_id or l.id in
    (select ca.lead_id from crm.conversion_acreditaciones ca
     where ca.fuente_tipo='contrato' and ca.fuente_id=new.contrato_id)
    order by l.id for update nowait;
  for v_periodo in select distinct periodo_comercial from crm.conversion_acreditaciones
      where fuente_tipo='contrato' and fuente_id=new.contrato_id order by periodo_comercial loop
    perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
  end loop;
  return new;
exception when lock_not_available then
  raise exception 'El lead tiene otra operacion en curso; reintenta la retirada' using errcode='PT409';
end;
$func$;
revoke all on function private.conversion_bloquear_retiro_trg() from public,anon,authenticated,service_role;
create trigger trg_conversion_bloquear_retiro before insert on crm.contratos_eliminados_auditoria
  for each row execute function private.conversion_bloquear_retiro_trg();

-- Único escritor interno de una fuente ELEGIDA, nunca del contrato más nuevo
-- o más antiguo de un perfil. Los timestamps los toma del servidor y de la
-- fuente real. No acepta relojes del navegador ni reloj de backfill inventado.
create or replace function private.conversion_acreditar_fuente(
  p_lead_id uuid, p_fuente_tipo text, p_fuente_id uuid, p_motivo text
)
returns uuid
language plpgsql volatile security invoker
set search_path = ''
as $func$
declare
  v_lead crm.leads%rowtype;
  v_episodio crm.lead_asignaciones%rowtype;
  v_anterior crm.conversion_acreditaciones%rowtype;
  v_observado crm.conversion_acreditaciones%rowtype;
  v_fuente record;
  v_decision record;
  v_persona uuid;
  v_periodo date;
  v_lock date;
  v_sello timestamptz;
  v_vinculado timestamptz;
  v_ahora timestamptz;
  v_estado text;
  v_id uuid;
begin
  if p_fuente_tipo is null or p_fuente_tipo not in ('contrato','cierre_externo')
     or p_fuente_id is null or p_motivo is null
     or length(btrim(p_motivo)) not between 5 and 300 then
    raise exception 'Fuente o motivo de acreditacion invalido' using errcode='22023';
  end if;
  -- Las puertas de negocio ya serializan el lead. No tomar aquí un row lock
  -- nuevo: la corrección comercial entra con el candado mensual y hacerlo
  -- en orden lead -> mes introduciría un ciclo con esa puerta.
  select * into v_lead from crm.leads where id=p_lead_id;
  if not found then raise exception 'Lead no encontrado' using errcode='P0002'; end if;
  select * into v_episodio from crm.lead_asignaciones
    where lead_id=p_lead_id and resultado='convertido';
  if not found then
    raise exception 'No existe un episodio convertido que acreditar' using errcode='P0409';
  end if;
  if (coalesce(v_episodio.resultado_en,v_episodio.finalizado_en) at time zone 'America/Lima')::date
    < date '2026-09-01' then
    -- Vigencia aprobada: este escritor no reinterpreta agosto ni meses previos.
    return null;
  end if;
  if coalesce(v_episodio.resultado_en,v_episodio.finalizado_en) is null then
    raise exception 'El episodio convertido no tiene reloj verificable' using errcode='P0409';
  end if;
  v_persona := private.inversionista_canonica(v_lead.inversionista_id);
  select * into v_anterior from crm.conversion_acreditaciones where lead_id=p_lead_id;

  if p_fuente_tipo='contrato' then
    select c.fecha_cierre_comercial as fecha,c.creado_en as confirmado,
      c.cliente_id=v_lead.perfil_id as pertenece,
      coalesce(c.es_demo,false) as demo,
      c.categoria<>'nuevo' or exists(select 1 from crm.operaciones_cartera o
        where o.contrato_nuevo_id=c.id) as cartera
    into v_fuente from public.contratos c where c.id=p_fuente_id;
  else
    select coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date) as fecha,
      ce.creado_en as confirmado,ce.lead_id=p_lead_id as pertenece,
      false as demo,not ce.es_cierre_inicial as cartera
    into v_fuente from crm.cierres_externos ce where ce.id=p_fuente_id;
  end if;
  if not found then raise exception 'La fuente elegida no existe' using errcode='P0002'; end if;
  if v_fuente.pertenece is distinct from true then
    raise exception 'La fuente no corresponde al lead' using errcode='P0409';
  end if;
  if v_fuente.fecha is null or v_fuente.confirmado is null then
    raise exception 'La fuente no tiene fecha comercial o confirmacion verificable' using errcode='P0409';
  end if;

  v_periodo := pg_catalog.date_trunc('month',v_fuente.fecha::timestamp)::date;
  -- Mismas llaves que crm.cerrar_periodo, en orden si cambia el destino.
  for v_lock in select distinct p from unnest(array[v_anterior.periodo_comercial,v_periodo]) p
      where p is not null order by p loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_lock-date '2000-01-01')::integer);
  end loop;
  select * into v_observado from crm.conversion_acreditaciones where lead_id=p_lead_id for update;
  if v_observado is distinct from v_anterior then
    raise exception 'La acreditacion cambio mientras esperaba el candado; vuelve a intentar'
      using errcode='PT409';
  end if;
  if not exists(select 1 from crm.leads l where l.id=p_lead_id
      and l.perfil_id is not distinct from v_lead.perfil_id
      and l.inversionista_id is not distinct from v_lead.inversionista_id
      and l.origen is not distinct from v_lead.origen) then
    raise exception 'La identidad o el origen cambio durante la acreditacion; vuelve a intentar'
      using errcode='PT409';
  end if;
  -- La corrección comercial puede haber terminado mientras esperábamos el
  -- candado. No conservar un mes leído antes de esperar: exigir reintento.
  if p_fuente_tipo='contrato' and not exists(select 1 from public.contratos c
      where c.id=p_fuente_id and c.fecha_cierre_comercial=v_fuente.fecha
        and c.cliente_id=v_lead.perfil_id) then
    raise exception 'La fuente cambio durante la acreditacion; vuelve a intentar' using errcode='PT409';
  elsif p_fuente_tipo='cierre_externo' and not exists(select 1 from crm.cierres_externos ce
      where ce.id=p_fuente_id and ce.lead_id=p_lead_id
        and coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date)=v_fuente.fecha) then
    raise exception 'La fuente cambio durante la acreditacion; vuelve a intentar' using errcode='PT409';
  end if;

  if v_anterior.id is not null and v_anterior.fuente_tipo=p_fuente_tipo
     and v_anterior.fuente_id=p_fuente_id and v_anterior.fecha_comercial=v_fuente.fecha
     and v_anterior.origen=v_lead.origen then
    -- Un reintento no rejuvenece el reloj ni caduca después del día 10.
    return v_anterior.id;
  end if;
  if v_anterior.id is not null and exists(select 1 from crm.periodos_cerrados pc
      where pc.periodo=v_anterior.periodo_comercial) then
    if v_anterior.fuente_tipo=p_fuente_tipo and v_anterior.fuente_id=p_fuente_id
      and v_anterior.fecha_comercial=v_fuente.fecha then
      -- Un cambio de origen operativo no reescribe la atribución congelada
      -- ni impide la edición legítima del lead después del sello.
      return v_anterior.id;
    end if;
    raise exception 'La acreditacion pertenece a un mes sellado' using errcode='P0409';
  end if;

  -- El candado por identidad evita que dos leads legados acrediten una misma
  -- persona concurrentemente. No reemplaza el candado mensual del sello.
  if v_persona is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.conversion_acreditaciones'),
      pg_catalog.hashtext(v_persona::text));
    if exists(select 1 from crm.conversion_acreditaciones ca where ca.lead_id<>p_lead_id
      and ca.estado='acreditada'
      and ca.periodo_comercial>=date '2026-09-01'
      and private.inversionista_canonica(ca.inversionista_id)=v_persona) then
      raise exception 'La identidad ya tiene una captacion acreditada' using errcode='P0409';
    end if;
  end if;

  v_ahora := private.conversion_instante_servidor();
  v_vinculado := case when v_anterior.fuente_tipo=p_fuente_tipo
      and v_anterior.fuente_id=p_fuente_id and v_anterior.periodo_comercial=v_periodo
    then v_anterior.vinculado_en else v_ahora end;
  -- Corregir el día dentro del mismo mes no crea un vínculo nuevo. Mover la
  -- operación a otro mes sí revalida su admisión con recepción actual, sin
  -- abrir retroactivamente un período cuyo plazo ya venció.
  select pc.cerrado_en into v_sello from crm.periodos_cerrados pc where pc.periodo=v_periodo;
  select * into v_decision from private.conversion_decidir_plazo(
    v_fuente.fecha,v_fuente.confirmado,v_vinculado,v_sello);
  v_estado := case when v_fuente.demo then 'fuente_demo'
    when v_fuente.cartera then 'operacion_cartera' else v_decision.estado end;
  if v_anterior.id is null then
  insert into crm.conversion_acreditaciones(lead_id,episodio_id,inversionista_id,analista_id,
    origen,fuente_tipo,fuente_id,fecha_comercial,confirmado_en,vinculado_en,acreditado_en,
    periodo_comercial,plazo_hasta,estado,motivo,creado_en,actualizado_en)
  values(p_lead_id,v_episodio.id,v_persona,v_episodio.analista_id,v_lead.origen,
    p_fuente_tipo,p_fuente_id,v_fuente.fecha,v_fuente.confirmado,v_vinculado,
    v_decision.acreditado_en,v_periodo,v_decision.plazo_hasta,v_estado,btrim(p_motivo),v_ahora,v_ahora)
  -- Si ganó otra fuente del mismo lead en otro mes, no hacer un UPSERT que
  -- sobrescriba un período cuyo candado nunca tomamos. El caller reintentará.
  on conflict(lead_id) do nothing
  returning id into v_id;
  if v_id is null then
    raise exception 'Otra acreditacion gano la carrera; vuelve a intentar' using errcode='PT409';
  end if;
  else
    update crm.conversion_acreditaciones set
      inversionista_id=v_persona,origen=v_lead.origen,
      fuente_tipo=p_fuente_tipo,fuente_id=p_fuente_id,
      fecha_comercial=v_fuente.fecha,confirmado_en=v_fuente.confirmado,
      vinculado_en=v_vinculado,acreditado_en=v_decision.acreditado_en,
      periodo_comercial=v_periodo,plazo_hasta=v_decision.plazo_hasta,
      estado=v_estado,motivo=btrim(p_motivo),actualizado_en=v_ahora
    where id=v_anterior.id returning id into v_id;
  end if;
  return v_id;
end;
$func$;

-- Resolver solamente vínculos explícitos, sin fallback por perfil ni orden de
-- antigüedad de contratos. Una ambigüedad queda pendiente, no elige un ganador.
create or replace function private.conversion_sincronizar_lead(p_lead_id uuid)
returns uuid language plpgsql volatile security invoker set search_path=''
as $func$
declare
  v_tipo text;
  v_fuente uuid;
  v_cantidad integer;
  v_anterior crm.conversion_acreditaciones%rowtype;
begin
  if not exists(select 1 from crm.lead_asignaciones la where la.lead_id=p_lead_id
      and la.resultado='convertido' and coalesce(la.resultado_en,la.finalizado_en)
        >= '2026-09-01 00:00 America/Lima'::timestamptz) then return null; end if;
  select * into v_anterior from crm.conversion_acreditaciones where lead_id=p_lead_id;
  if found and (case v_anterior.fuente_tipo
      when 'contrato' then exists(select 1 from public.contratos where id=v_anterior.fuente_id)
      else exists(select 1 from crm.cierres_externos where id=v_anterior.fuente_id) end) then
    return private.conversion_acreditar_fuente(p_lead_id,v_anterior.fuente_tipo,
      v_anterior.fuente_id,'Sincronizacion de la fuente ya acreditada');
  end if;
  with fuentes as (
    select 1 as prioridad,case when i.contrato_id is not null then 'contrato'
      else 'cierre_externo' end as tipo,coalesce(i.contrato_id,i.cierre_externo_id) as id
    from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id
    where s.lead_origen_id=p_lead_id and s.estado='confirmada' and i.es_primera_conversion
      and coalesce(i.contrato_id,i.cierre_externo_id) is not null
    union all
    select 2,'contrato',c.id from crm.leads l join public.contratos c on c.id=l.contrato_id
      and c.cliente_id=l.perfil_id where l.id=p_lead_id
    union all
    select 3,'cierre_externo',ce.id from crm.cierres_externos ce
      where ce.lead_id=p_lead_id and ce.es_cierre_inicial
  ), elegidas as (
    select distinct tipo,id from fuentes where prioridad=(select min(prioridad) from fuentes)
  ) select count(*),min(tipo),min(id::text)::uuid into v_cantidad,v_tipo,v_fuente from elegidas;
  if v_cantidad<>1 then return null; end if;
  return private.conversion_acreditar_fuente(p_lead_id,v_tipo,v_fuente,
    'Vinculo explicito de confirmacion o cierre inicial');
end;
$func$;

create or replace function private.conversion_acreditacion_evento_trg()
returns trigger language plpgsql security definer set search_path=''
as $func$
declare v_lead uuid;
begin
  if tg_table_name='leads' then
    v_lead:=new.id;
    if new.contrato_id is distinct from old.contrato_id and new.contrato_id is not null
       and exists(select 1 from public.contratos c where c.id=new.contrato_id) then
      -- El enlace explícito del lead prevalece al conciliar un reemplazo. La
      -- pertenencia, mes, duplicado y plazo se revalidan en el escritor común.
      perform private.conversion_acreditar_fuente(v_lead,'contrato',new.contrato_id,
        'Cambio explicito del contrato vinculado al lead');
      return new;
    end if;
  elsif tg_table_name='lead_asignaciones' then v_lead:=new.lead_id;
  elsif tg_table_name='inversion_solicitudes' then v_lead:=new.lead_origen_id;
  elsif tg_table_name='cierres_externos' then v_lead:=new.lead_id;
  end if;
  if v_lead is not null then perform private.conversion_sincronizar_lead(v_lead); end if;
  return new;
end;
$func$;

create trigger trg_conversion_acreditacion_episodio
  after insert or update of resultado,resultado_en,finalizado_en on crm.lead_asignaciones
  for each row when (new.resultado='convertido')
  execute function private.conversion_acreditacion_evento_trg();
create trigger trg_zz_conversion_acreditacion_lead
  after update of contrato_id,perfil_id,origen on crm.leads
  for each row when (new.etapa='convertido' and
    (new.contrato_id is distinct from old.contrato_id
     or new.perfil_id is distinct from old.perfil_id or new.origen is distinct from old.origen))
  execute function private.conversion_acreditacion_evento_trg();
create trigger trg_conversion_acreditacion_solicitud
  after insert or update of estado,inversion_id on crm.inversion_solicitudes
  for each row when (new.estado='confirmada' and new.lead_origen_id is not null)
  execute function private.conversion_acreditacion_evento_trg();
create trigger trg_conversion_acreditacion_cooperativa
  after insert or update of fecha_comercial,lead_id,es_cierre_inicial on crm.cierres_externos
  for each row when (new.es_cierre_inicial)
  execute function private.conversion_acreditacion_evento_trg();

-- Operación administrativa de instalación, NO RPC, invoker y cerrada incluso
-- a service_role. Recibe un manifiesto privado revisado, no descubre contratos
-- por perfil. El operador autorizado ejecuta y verifica en una transacción.
create or replace function private.conversion_conciliar_y_activar(p_manifiesto jsonb)
returns jsonb language plpgsql volatile security invoker set search_path=''
as $func$
declare
  v_politica crm.conversion_politica%rowtype;
  v_huella text := md5(p_manifiesto::text);
  v_filas jsonb;
  v_total integer;
  v_vinculos integer;
  v_fila record;
  v_lead crm.leads%rowtype;
  v_episodio crm.lead_asignaciones%rowtype;
  v_lock date;
  v_ahora timestamptz;
  v_resultado jsonb;
begin
  if p_manifiesto is null or jsonb_typeof(p_manifiesto)<>'object'
    or p_manifiesto->>'version' is distinct from '1'
    or p_manifiesto->>'politica_desde' is distinct from '2026-09-01'
    or jsonb_typeof(p_manifiesto->'entradas') is distinct from 'array' then
    raise exception 'Manifiesto de conciliacion invalido' using errcode='22023';
  end if;
  v_filas:=p_manifiesto->'entradas';
  v_total:=jsonb_array_length(v_filas);
  if v_total>10000 then raise exception 'Manifiesto demasiado grande' using errcode='22023'; end if;
  select * into strict v_politica from crm.conversion_politica where unica for update;
  if v_politica.activada_en is not null then
    if v_politica.manifiesto_huella=v_huella then return v_politica.resultado; end if;
    raise exception 'La politica ya fue activada con otro manifiesto' using errcode='P0409';
  end if;
  if exists(select 1 from jsonb_to_recordset(v_filas) x(lead_id uuid,episodio_id uuid)
      where x.lead_id is null or x.episodio_id is null)
    or v_total<>(select count(distinct x.lead_id) from jsonb_to_recordset(v_filas) x(lead_id uuid))
    or v_total<>(select count(distinct x.episodio_id) from jsonb_to_recordset(v_filas) x(episodio_id uuid)) then
    raise exception 'El manifiesto repite u omite un lead o episodio' using errcode='22023';
  end if;
  -- Primero los leads, como las puertas oficiales; después TODOS los meses
  -- en orden. No tomar nuevos locks de leads después de un candado mensual.
  perform 1 from crm.leads l where l.id in
    (select x.lead_id from jsonb_to_recordset(v_filas) x(lead_id uuid)) order by l.id for update;
  for v_lock in
    select distinct periodo from (
      select date_trunc('month',x.fecha_comercial::timestamp)::date as periodo
        from jsonb_to_recordset(v_filas) x(fecha_comercial date)
      union all select ca.periodo_comercial from crm.conversion_acreditaciones ca
        where ca.lead_id in (select x.lead_id from jsonb_to_recordset(v_filas) x(lead_id uuid))
      union all select date '2026-09-01'
    ) meses where periodo is not null order by periodo
  loop
    perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),(v_lock-date '2000-01-01')::integer);
  end loop;
  if exists(select 1 from crm.periodos_cerrados where periodo>=date '2026-09-01') then
    raise exception 'No activar sobre meses de la nueva politica ya sellados' using errcode='P0409';
  end if;
  v_ahora:=private.conversion_instante_servidor();
  if v_total>0 and v_ahora>=private.conversion_plazo_hasta(date '2026-09-01') then
    raise exception 'La conciliacion inicial de septiembre ya esta fuera de plazo' using errcode='P0409';
  end if;
  if exists(select 1 from crm.lead_asignaciones la where la.resultado='convertido'
      and coalesce(la.resultado_en,la.finalizado_en)>='2026-09-01 00:00 America/Lima'::timestamptz
      and not exists(select 1 from jsonb_to_recordset(v_filas) x(episodio_id uuid) where x.episodio_id=la.id)) then
    raise exception 'Hay conversiones sin revisar en el manifiesto; actualizar el diagnostico' using errcode='P0409';
  end if;
  for v_fila in select * from jsonb_to_recordset(v_filas) x(
      lead_id uuid,episodio_id uuid,analista_id uuid,origen text,perfil_id uuid,
      inversionista_id uuid,resultado_en timestamptz,fuente_tipo text,fuente_id uuid,
      fecha_comercial date,confirmado_en timestamptz) order by lead_id
  loop
    select * into v_lead from crm.leads where id=v_fila.lead_id;
    select * into v_episodio from crm.lead_asignaciones where id=v_fila.episodio_id;
    if v_lead.id is null or v_episodio.id is null or v_lead.etapa<>'convertido'
      or v_episodio.lead_id<>v_lead.id or v_episodio.resultado<>'convertido'
      or v_episodio.resultado_en is distinct from v_fila.resultado_en
      or v_episodio.analista_id is distinct from v_fila.analista_id
      or v_lead.origen is distinct from v_fila.origen
      or v_lead.perfil_id is distinct from v_fila.perfil_id
      or v_lead.inversionista_id is distinct from v_fila.inversionista_id then
      raise exception 'El lead o episodio cambio desde la revision; no activar' using errcode='PT409';
    end if;
    if v_fila.fuente_id is null then
      if v_fila.fuente_tipo is not null or exists(select 1 from crm.conversion_acreditaciones
          where lead_id=v_fila.lead_id) then
        raise exception 'Un pendiente del manifiesto ya tiene acreditacion; revisar' using errcode='PT409';
      end if;
      continue;
    end if;
    if v_fila.fuente_tipo='contrato' then
      if not exists(select 1 from public.contratos c where c.id=v_fila.fuente_id
        and c.cliente_id=v_lead.perfil_id and c.fecha_cierre_comercial=v_fila.fecha_comercial
        and c.creado_en=v_fila.confirmado_en and not coalesce(c.es_demo,false) and c.categoria='nuevo'
        and not exists(select 1 from crm.operaciones_cartera oc where oc.contrato_nuevo_id=c.id)) then
        raise exception 'La fuente contractual cambio desde la revision; no activar' using errcode='PT409';
      end if;
    elsif v_fila.fuente_tipo='cierre_externo' then
      if not exists(select 1 from crm.cierres_externos ce where ce.id=v_fila.fuente_id
        and ce.lead_id=v_lead.id and ce.es_cierre_inicial and ce.creado_en=v_fila.confirmado_en
        and coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date)=v_fila.fecha_comercial) then
        raise exception 'La fuente cooperativa cambio desde la revision; no activar' using errcode='PT409';
      end if;
    else
      raise exception 'Tipo de fuente invalido en manifiesto' using errcode='22023';
    end if;
    perform private.conversion_acreditar_fuente(v_fila.lead_id,v_fila.fuente_tipo,v_fila.fuente_id,
      'Conciliacion inicial de fuente explicitamente verificada');
  end loop;
  select count(*) into v_vinculos from jsonb_to_recordset(v_filas) x(fuente_id uuid) where fuente_id is not null;
  if (select count(*) from crm.conversion_acreditaciones ca where ca.lead_id in
      (select x.lead_id from jsonb_to_recordset(v_filas) x(lead_id uuid)))<>v_vinculos then
    raise exception 'El recuento conciliado no corresponde al manifiesto' using errcode='PT409';
  end if;
  v_ahora:=private.conversion_instante_servidor();
  if v_total>0 and v_ahora>=private.conversion_plazo_hasta(date '2026-09-01') then
    raise exception 'El plazo vencio durante la conciliacion; no activar parcialmente' using errcode='P0409';
  end if;
  v_resultado:=jsonb_build_object('version',1,'episodios',v_total,'vinculos',v_vinculos,
    'pendientes',v_total-v_vinculos,'activada_en',v_ahora);
  update crm.conversion_politica set activada_en=v_ahora,manifiesto_huella=v_huella,resultado=v_resultado where unica;
  return v_resultado;
end;
$func$;
revoke all on function private.conversion_conciliar_y_activar(jsonb) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.conversion_cierres(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric, p_leads uuid[])
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select 'cierre'::text, la.analista_id, la.lead_id, null::uuid,
  l.origen = 'referido', null::boolean, null::text,
  private.cierre_externo_anulado(la.lead_id), l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, null::timestamptz,
  coalesce(la.resultado_en, la.finalizado_en), 0,
  case when private.cierre_externo_anulado(la.lead_id) then 0
    when l.origen = 'referido' then
      case when p_periodo is not null then p_factor else
        private.peso_referido_conversion(date_trunc('month',
          coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima')::date) end
    when l.origen in ('landing', 'formulario') then 1
    else 0 end
from crm.lead_asignaciones la
join crm.leads l on l.id = la.lead_id
where la.resultado = 'convertido'
  -- La política previa conserva agosto y todos los meses anteriores.
  and (not exists(select 1 from crm.conversion_politica where activada_en is not null)
    or coalesce(la.resultado_en, la.finalizado_en) < '2026-09-01 00:00:00 America/Lima'::timestamptz)
  and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
  and coalesce(la.resultado_en, la.finalizado_en) < p_fin
  and (p_global or la.analista_id = any(p_visibles))
  and (p_leads is null or la.lead_id in (select id from unnest(p_leads) seleccion(id)))
union all
select 'cierre'::text, ca.analista_id, ca.lead_id, null::uuid,
  ca.origen = 'referido', null::boolean, null::text,
  private.cierre_externo_anulado(ca.lead_id), ca.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, null::timestamptz,
  ca.fecha_comercial::timestamp at time zone 'America/Lima', 0,
  case when private.cierre_externo_anulado(ca.lead_id) then 0
    when ca.origen = 'referido' then
      case when p_periodo is not null then p_factor
        else private.peso_referido_conversion(ca.periodo_comercial) end
    when ca.origen in ('landing', 'formulario') then 1
    else 0 end
from crm.conversion_acreditaciones ca
join crm.leads l on l.id=ca.lead_id
where ca.estado='acreditada'
  and exists(select 1 from crm.conversion_politica where activada_en is not null)
  -- No reabrir agosto por la acreditación en septiembre de un contrato viejo.
  and ca.periodo_comercial >= date '2026-09-01'
  and (ca.fecha_comercial::timestamp at time zone 'America/Lima') >= p_ini
  and (ca.fecha_comercial::timestamp at time zone 'America/Lima') < p_fin
  and (p_global or ca.analista_id = any(p_visibles))
  and (p_leads is null or ca.lead_id in (select id from unnest(p_leads) seleccion(id)))
  -- Una fuente retirada no sigue fabricando cierres en un mes abierto.
  -- El hecho y su auditoría sobreviven; un mes sellado se sirve por su foto.
  and private.conversion_exclusion_fuente(ca.fuente_tipo,ca.fuente_id)='elegible';
$function$;

CREATE OR REPLACE FUNCTION crm.corregir_fecha_cierre_comercial(p_contrato_id uuid, p_fecha date, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_motivo text := nullif(btrim(p_motivo), '');
  v_hoy_lima date := (clock_timestamp() at time zone 'America/Lima')::date;
  v_contrato public.contratos%rowtype;
  v_periodo_anterior date;
  v_periodo_nuevo date;
  v_lock_primero date;
  v_lock_segundo date;
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede corregir el cierre comercial'
      using errcode = '42501';
  end if;

  if p_contrato_id is null then
    raise exception 'El contrato es obligatorio' using errcode = '22023';
  end if;
  if p_fecha is null or not isfinite(p_fecha) or p_fecha > v_hoy_lima then
    raise exception 'La fecha de cierre comercial es invalida o futura'
      using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300 then
    raise exception 'El motivo debe tener entre 5 y 300 caracteres'
      using errcode = '22023';
  end if;

  select c.* into v_contrato
  from public.contratos c
  where c.id = p_contrato_id
  for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  if v_contrato.fecha_cierre_comercial = p_fecha then
    return jsonb_build_object(
      'ok', true,
      'cambio', false,
      'contrato_id', p_contrato_id,
      'fecha_cierre_comercial', p_fecha
    );
  end if;

  v_periodo_anterior := date_trunc(
    'month', v_contrato.fecha_cierre_comercial
  )::date;
  v_periodo_nuevo := date_trunc('month', p_fecha)::date;
  v_lock_primero := least(v_periodo_anterior, v_periodo_nuevo);
  v_lock_segundo := greatest(v_periodo_anterior, v_periodo_nuevo);

  -- Mismas llaves del sello mensual, siempre en orden para no crear deadlocks.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_lock_primero - date '2000-01-01')::integer
  );
  if v_lock_segundo is distinct from v_lock_primero then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_lock_segundo - date '2000-01-01')::integer
    );
  end if;

  if exists (
    select 1 from crm.periodos_cerrados pc
    where pc.periodo in (v_periodo_anterior, v_periodo_nuevo)
  ) then
    raise exception 'No se puede reescribir un mes comercial sellado'
      using errcode = 'P0409',
            hint = 'La correccion debe hacerse antes del sello mensual.';
  end if;

  perform pg_catalog.set_config(
    'crm.correccion_periodo_comercial', 'on', true
  );
  update public.contratos c
     set fecha_cierre_comercial = p_fecha,
         fuente_cierre_comercial = 'correccion_manual'
   where c.id = p_contrato_id;
  perform pg_catalog.set_config(
    'crm.correccion_periodo_comercial', 'off', true
  );

  -- Misma transacción y mismos candados de ambos meses: la corrección no
  -- abre una puerta de crédito retroactivo. No altera fuente/importes de capital.
  perform private.conversion_acreditar_fuente(ca.lead_id,ca.fuente_tipo,ca.fuente_id,
    'Correccion comercial auditada: '||left(v_motivo,260))
  from crm.conversion_acreditaciones ca
  where ca.fuente_tipo='contrato' and ca.fuente_id=p_contrato_id;

  -- El trigger general conserva la fila completa. Esta segunda entrada agrega
  -- el motivo de negocio que audit_log no tiene como columna propia.
  insert into public.audit_log (
    tabla, operacion, fila_id, usuario_id, data_antes, data_despues
  ) values (
    'contratos.fecha_cierre_comercial',
    'UPDATE',
    p_contrato_id::text,
    v_uid,
    jsonb_build_object(
      'fecha_cierre_comercial', v_contrato.fecha_cierre_comercial,
      'fuente', v_contrato.fuente_cierre_comercial
    ),
    jsonb_build_object(
      'fecha_cierre_comercial', p_fecha,
      'fuente', 'correccion_manual',
      'motivo', v_motivo
    )
  );

  return jsonb_build_object(
    'ok', true,
    'cambio', true,
    'contrato_id', p_contrato_id,
    'fecha_anterior', v_contrato.fecha_cierre_comercial,
    'fecha_cierre_comercial', p_fecha
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.registrar_ajuste_si_mes_cerrado(p_lead_id uuid, p_motivo text, p_por uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;
  v_acreditacion crm.conversion_acreditaciones%rowtype;
  v_acreditacion_actual crm.conversion_acreditaciones%rowtype;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- Desde septiembre, el reloj de crédito y la prueba de que SE ABONÓ salen
  -- del hecho de acreditación, no del mes de leads.convertido_en.
  if exists(select 1 from crm.conversion_politica where activada_en is not null)
    and exists(select 1 from crm.lead_asignaciones la where la.lead_id=p_lead_id
    and la.resultado='convertido' and coalesce(la.resultado_en,la.finalizado_en)
      >= '2026-09-01 00:00 America/Lima'::timestamptz) then
    select * into v_acreditacion
    from crm.conversion_acreditaciones ca where ca.lead_id=p_lead_id
      and ca.estado='acreditada' and ca.periodo_comercial>=date '2026-09-01';
    if not found then return null; end if;
    v_periodo:=v_acreditacion.periodo_comercial;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
    select * into v_acreditacion_actual from crm.conversion_acreditaciones where lead_id=p_lead_id;
    if v_acreditacion_actual is distinct from v_acreditacion then
      raise exception 'La acreditacion cambio durante la anulacion; vuelve a intentar' using errcode='PT409';
    end if;
    if not exists(select 1 from crm.periodos_cerrados pc where pc.periodo=v_periodo) then
      return null;
    end if;
    if v_acreditacion.incluida_en_sello is distinct from true then return null; end if;
    v_acreditado:=v_acreditacion.analista_id;
    v_numerador:=case when v_acreditacion.origen='referido' then
      private.peso_referido_conversion(v_periodo)
      when v_acreditacion.origen in ('landing','formulario') then 1 else 0 end;
    if v_acreditado is null or v_numerador<=0 then return null; end if;
    -- Para referidos prevalece el peso de la foto que efectivamente se pagó.
    if exists(select 1 from crm.conversion_acreditaciones ca
      where ca.lead_id=p_lead_id and ca.origen='referido') then
      select pc.ponderacion_referido into v_numerador from crm.periodos_cerrados pc
        where pc.periodo=v_periodo;
    end if;
    if v_numerador is null or v_numerador<=0 then return null; end if;
  else
  -- ⚠️ EL CERROJO, antes de mirar si el mes esta cerrado. Sin el, una anulacion
  -- concurrente con el sellado de ESE mes lee «abierto» —porque el sello aun no
  -- ha commiteado—, devuelve NULL, y el cierre anulado se queda pagado para
  -- siempre. Misma clave que en `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  -- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
  -- caballo del mes (convertido_en usa now() de transaccion y el ledger
  -- statement_timestamp(), caso documentado): se localiza el episodio canonico
  -- del lead SIN depender del mes de leads.convertido_en, y de el salen el
  -- PERIODO real, el referido y el peso. Cero episodios => la sancion de
  -- conversion vale CERO (nunca 1 en silencio) y queda alerta; mas de uno =>
  -- excepcion de integridad (el ledger solo permite una conversion por lead).
  select count(*),
         coalesce(bool_or(e.fue_referido), false),
         min(date_trunc('month', (e.fecha_numerador at time zone 'America/Lima'))::date)
    into v_n_episodios, v_referido, v_periodo_episodio
  from private.conversion_episodios(
         '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
         null::date, true, '{}'::uuid[], 1) e
  where e.lead_id = p_lead_id and e.tipo = 'cierre';

  if v_n_episodios > 1 then
    raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, v_n_episodios;
  end if;
  if v_n_episodios = 1 and v_periodo_episodio is distinct from v_periodo then
    -- El mes REAL del cierre es el del episodio: el cerrojo y la foto del mes
    -- sellado se toman sobre ese periodo (se re-toma el candado por si acaso).
    v_periodo := v_periodo_episodio;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo - date '2000-01-01')::integer);
    if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
      return null;
    end if;
  end if;
  if v_n_episodios = 0 then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6c_ajuste_sin_episodio',
            format('lead %s: sin episodio de cierre en el ledger; la sancion de conversion vale 0', p_lead_id));
  end if;

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_n_episodios = 0 then 0
                       when v_referido then v_peso else 1 end;

  end if;

  -- ATR-4 (Miguel 31/08): «solo la conversion, siempre». La deuda de un mes
  -- sellado ya NO carga capital: el capital del analista se queda en su
  -- produccion y el de la empresa en el AUM. Solo se descuenta la conversion.
  v_pen := 0; v_usd := 0; v_detalle := '[]'::jsonb;

  -- Con capital siempre 0, la deuda existe SOLO si la conversion valia algo.
  -- numerador 0 (cierre sin episodio) => NULL POR DISENO declarado: el rastro
  -- queda en la alerta del vigia (f6c_ajuste_sin_episodio) y en la anulacion
  -- misma; no se fabrica una deuda vacia.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;

$function$;

-- Puerta de lectura independiente: no amplía los payloads estrictos de Ranking
-- ni Metas. La UI presenta esta decisión, nunca recalcula plazos o conversiones.
create or replace function private.conversion_estado_lead_v1(p_lead_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $func$
declare
  v_uid uuid := (select auth.uid());
  v_lead crm.leads%rowtype;
  v_acreditacion crm.conversion_acreditaciones%rowtype;
  v_estado text;
  v_mensaje text;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'Sin acceso al CRM' using errcode='42501';
  end if;
  -- Mismo ámbito que leads_select: incluye estacionados del supervisor y
  -- lectores globales activos. ID inexistente y ajeno tienen idéntico error.
  select * into v_lead from crm.leads l where l.id=p_lead_id and l.activo
    and (private.rol_crm(v_uid)='gerencia' or private.es_lector_global()
      or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (l.vendedor_id is null and l.asignado_supervisor_id
        in (select private.vendedor_ids_visibles(v_uid))));
  if not found then
    raise exception 'Lead no disponible en tu ambito' using errcode='42501';
  end if;
  select * into v_acreditacion from crm.conversion_acreditaciones where lead_id=p_lead_id;
  v_estado := case
    when v_lead.etapa<>'convertido' then 'no_convertido'
    when private.cierre_externo_anulado(p_lead_id) then 'anulada'
    when not exists(select 1 from crm.conversion_politica where activada_en is not null)
      then 'pendiente_activacion'
    when exists(select 1 from crm.lead_asignaciones la where la.lead_id=p_lead_id
      and la.resultado='convertido' and coalesce(la.resultado_en,la.finalizado_en)
        < '2026-09-01 00:00 America/Lima'::timestamptz) then 'politica_anterior'
    when v_acreditacion.id is null then 'pendiente_fuente'
    when private.conversion_exclusion_fuente(v_acreditacion.fuente_tipo,v_acreditacion.fuente_id)<>'elegible'
      then private.conversion_exclusion_fuente(v_acreditacion.fuente_tipo,v_acreditacion.fuente_id)
    when v_acreditacion.estado='acreditada' and v_acreditacion.periodo_comercial<date '2026-09-01'
      then 'anterior_vigencia'
    else v_acreditacion.estado end;
  v_mensaje := case v_estado
    when 'pendiente_activacion' then 'La nueva política está pendiente de activación. Se conserva el resultado anterior.'
    when 'acreditada' then 'Conversión acreditada en el mes de cierre comercial.'
    when 'fuera_de_plazo' then 'Sin crédito: la confirmación o el vínculo llegó después del día 10 del mes siguiente. No se traslada a otro mes.'
    when 'mes_sellado' then 'Sin crédito: el mes comercial ya estaba sellado cuando se acreditó el vínculo.'
    when 'pendiente_fuente' then 'Pendiente, sin crédito: falta acreditar una operación confirmada y su vínculo.'
    when 'fuente_retirada' then 'La operación vinculada fue retirada. No acredita en un mes abierto; las fotos selladas se conservan.'
    when 'fecha_futura' then 'Sin crédito: la fecha comercial era futura al acreditar el vínculo.'
    when 'fuente_demo' then 'Sin crédito: la operación está marcada como demostración.'
    when 'operacion_cartera' then 'No es una captación inicial; se aplican las reglas de cartera.'
    when 'anulada' then 'Conversión anulada. Si estaba en un mes sellado, se conserva la foto y se registra el ajuste correspondiente.'
    when 'politica_anterior' then 'Resultado histórico conservado con la política anterior a septiembre de 2026.'
    when 'anterior_vigencia' then 'Sin nuevo crédito: el mes comercial es anterior a la vigencia de esta política.'
    else 'El lead todavía no tiene una conversión acreditada.' end;
  return jsonb_build_object('version',1,'lead_id',p_lead_id,'estado',v_estado,
    'mensaje',v_mensaje,'periodo_comercial',v_acreditacion.periodo_comercial,
    'fecha_comercial',v_acreditacion.fecha_comercial,'plazo_hasta',v_acreditacion.plazo_hasta,
    'confirmado_en',v_acreditacion.confirmado_en,'vinculado_en',v_acreditacion.vinculado_en);
end;
$func$;
create or replace function crm.conversion_estado_lead_v1(p_lead_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $func$ select private.conversion_estado_lead_v1(p_lead_id) $func$;
revoke all on function private.conversion_estado_lead_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function crm.conversion_estado_lead_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function private.conversion_estado_lead_v1(uuid) to authenticated;
grant execute on function crm.conversion_estado_lead_v1(uuid) to authenticated;

-- Conserva la firma de todas las puertas de cierre; elimina la constante
-- anterior de día 10. No enciende Cron ni crea fotos retrospectivas.
create or replace function private.cierre_mes_ventana_desde(p_periodo date)
returns timestamptz
language sql immutable security invoker
set search_path = ''
as $func$
  select private.conversion_plazo_hasta(p_periodo)
$func$;

revoke all on function private.conversion_plazo_hasta(date) from public, anon, authenticated;
revoke all on function private.conversion_decidir_plazo(date,timestamptz,timestamptz,timestamptz)
  from public, anon, authenticated;
revoke all on function private.conversion_acreditar_fuente(uuid,text,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function private.conversion_instante_servidor()
  from public, anon, authenticated, service_role;
revoke all on function private.conversion_sincronizar_lead(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.conversion_acreditacion_evento_trg()
  from public, anon, authenticated, service_role;
-- La ACL del helper preexistente de cierre se conserva; no abrir acceso nuevo.

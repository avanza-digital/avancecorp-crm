-- F3-B: activar solo después del cliente compatible y la Edge importadora.
-- Transacción breve: drena escritores anteriores y reclasifica únicamente F3 legado.
-- El ledger, las asignaciones, los vetos y las fotos de meses cerrados no se editan.
-- Un cierre ya acreditado en mes abierto conserva toda su información salvo el origen.
-- Los candados financieros se intentan sin espera: ante actividad concurrente se aborta.
begin isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_advisory_xact_lock(hashtextextended('crm:formulario3:origen',0));
lock table crm.leads in share row exclusive mode;

do $preflight$ begin
  if md5(pg_get_functiondef('private.leads_before_insert()'::regprocedure))
      <> '63d6983ae0d344b770a1b92f2efdda94' then
    raise exception 'F3-B: trigger distinto de la compatibilidad validada';
  end if;
  if md5(pg_get_functiondef('private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure)) <> '581462c4ecbdab349c18655f4850e010' then raise exception 'F3-B: cambió la sincronización de acreditaciones validada'; end if;
  if md5(pg_get_functiondef('private.conversion_sincronizar_lead(uuid)'::regprocedure)) <> '38bf077cb56a54f2741f073c94f51281' then raise exception 'F3-B: cambió la sincronización de acreditaciones validada'; end if;
  if md5(pg_get_functiondef('private.conversion_acreditacion_evento_trg()'::regprocedure)) <> 'cb9ad60e0e5956dff7feb212141fbf46' then raise exception 'F3-B: cambió la sincronización de acreditaciones validada'; end if;
end; $preflight$;

create temporary table _f3_activacion_antes on commit drop as
  select l.id, to_jsonb(l) as fila from crm.leads l
  where l.origen='formulario' and l.campania_origen='Formulario 3';
create temporary table _f3_meses on commit drop as
  select distinct date_trunc('month',(f.fila->>'creado_en')::timestamptz at time zone 'America/Lima')::date periodo
    from _f3_activacion_antes f
  union select a.periodo_comercial from crm.conversion_acreditaciones a
    join _f3_activacion_antes f on f.id=a.lead_id;
do $candados$ declare mes date; begin
  for mes in select periodo from _f3_meses order by periodo loop
    if not pg_try_advisory_xact_lock(hashtext('crm.periodos_cerrados'),(mes-date '2000-01-01')::integer) then
      raise exception 'F3-B: mes en uso; reintentar cuando termine la operación comercial';
    end if;
  end loop;
  perform a.id from crm.conversion_acreditaciones a join _f3_activacion_antes f on f.id=a.lead_id
    order by a.id for update of a nowait;
  if exists(select 1 from crm.conversion_acreditaciones a join _f3_activacion_antes f on f.id=a.lead_id
      where not exists(select 1 from _f3_meses m where m.periodo=a.periodo_comercial)) then
    raise exception 'F3-B: cambió el mes de una acreditación; reintentar';
  end if;
end; $candados$;

do $coherencia$ begin
  if exists(select 1 from crm.leads l join _f3_activacion_antes f on f.id=l.id
    and (l.creado_en < timestamptz '2026-10-14 00:00:00-05'
      or exists(select 1 from crm.lead_asignaciones a where a.lead_id=l.id
        and (a.origen is distinct from 'formulario' or a.asignado_en < l.creado_en)))) then
    raise exception 'F3-B: candidato con historia previa incompatible; requiere revisión';
  end if;
  if exists(select 1 from crm.periodos_cerrados p join _f3_meses m on m.periodo=p.periodo) then
    raise exception 'F3-B: la población ya pertenece a un mes sellado';
  end if;
  if exists(select 1 from crm.leads l join _f3_activacion_antes f on f.id=l.id
    where l.etapa<>'convertido' and (l.convertido_en is not null or l.perfil_id is not null
      or l.contrato_id is not null
      or exists(select 1 from crm.conversion_acreditaciones a where a.lead_id=l.id)
      or exists(select 1 from crm.cierres_externos c where c.lead_id=l.id))) then
    raise exception 'F3-B: contacto sin convertir con vínculo financiero; requiere revisión';
  end if;
  if exists(select 1 from crm.leads l join _f3_activacion_antes f on f.id=l.id
    where l.etapa='convertido' and (l.convertido_en is null or not exists(
      select 1 from crm.conversion_acreditaciones a
      join crm.lead_asignaciones e on e.id=a.episodio_id and e.lead_id=a.lead_id
      where a.lead_id=l.id and a.origen='formulario' and a.estado='acreditada'
        and e.resultado='convertido' and e.analista_id=a.analista_id
        and a.inversionista_id is not null
        and private.inversionista_canonica(a.inversionista_id)=private.inversionista_canonica(l.inversionista_id)
        and a.sellado_en is null and a.incluida_en_sello is null and a.ajuste_anulacion_en_sello is null
        and a.periodo_comercial=date_trunc('month',l.creado_en at time zone 'America/Lima')::date
        and a.periodo_comercial=date_trunc('month',a.fecha_comercial)::date
        and a.fecha_comercial>=(l.creado_en at time zone 'America/Lima')::date
        and private.conversion_exclusion_fuente(a.fuente_tipo,a.fuente_id)='elegible'
        and ((a.fuente_tipo='contrato' and a.fuente_id=l.contrato_id and exists(
          select 1 from public.contratos c where c.id=a.fuente_id and c.cliente_id=l.perfil_id
            and c.fecha_cierre_comercial=a.fecha_comercial and c.creado_en=a.confirmado_en))
          or (a.fuente_tipo='cierre_externo' and exists(
          select 1 from crm.cierres_externos c where c.id=a.fuente_id and c.lead_id=l.id
            and c.es_cierre_inicial and c.creado_en=a.confirmado_en
            and coalesce(c.fecha_comercial,(c.creado_en at time zone 'America/Lima')::date)=a.fecha_comercial)))
    ))) then
    raise exception 'F3-B: cierre sin acreditación coherente de mes abierto; requiere revisión';
  end if;
end; $coherencia$;

create temporary table _f3_acreditaciones_antes on commit drop as
  select a.id,to_jsonb(a) fila from crm.conversion_acreditaciones a
    join _f3_activacion_antes f on f.id=a.lead_id;
create temporary table _f3_otros_antes on commit drop as
  select l.id, md5(to_jsonb(l)::text) as huella from crm.leads l
  where not exists(select 1 from _f3_activacion_antes f where f.id=l.id);

-- Se compara únicamente la población afectada. Un cambio concurrente de sus
-- tareas/historia aborta de forma segura y permite reintentar; nunca se pisa.
create function pg_temp.f3_dependencias() returns jsonb language sql stable as $fn$
  select jsonb_build_object(
    'actividades', (select md5(coalesce(jsonb_agg(to_jsonb(a) order by a.id)::text,''))
      from crm.actividades a join pg_temp._f3_activacion_antes f on f.id=a.lead_id),
    'tareas', (select md5(coalesce(jsonb_agg(to_jsonb(a) order by a.id)::text,''))
      from crm.tareas a join pg_temp._f3_activacion_antes f on f.id=a.lead_id),
    'episodios', (select md5(coalesce(jsonb_agg(to_jsonb(a) order by a.id)::text,''))
      from crm.lead_asignaciones a join pg_temp._f3_activacion_antes f on f.id=a.lead_id),
    'acreditaciones', (select md5(coalesce(jsonb_agg(to_jsonb(a)-'origen' order by a.id)::text,''))
      from crm.conversion_acreditaciones a join pg_temp._f3_activacion_antes f on f.id=a.lead_id),
    'contratos', (select md5(coalesce(jsonb_agg(to_jsonb(c) order by c.id)::text,''))
      from public.contratos c where c.id in (select (fila->>'contrato_id')::uuid from pg_temp._f3_activacion_antes)),
    'fuentes_externas', (select md5(coalesce(jsonb_agg(to_jsonb(c) order by c.id)::text,''))
      from crm.cierres_externos c join pg_temp._f3_activacion_antes f on f.id=c.lead_id),
    'solicitudes', (select md5(coalesce(jsonb_agg(to_jsonb(s) order by s.id)::text,''))
      from crm.inversion_solicitudes s join pg_temp._f3_activacion_antes f on f.id=s.lead_origen_id),
    'inversiones', (select md5(coalesce(jsonb_agg(to_jsonb(i) order by i.id)::text,''))
      from crm.inversiones i where i.id in (select s.inversion_id from crm.inversion_solicitudes s
        join pg_temp._f3_activacion_antes f on f.id=s.lead_origen_id)),
    'cierres', (select md5(coalesce(jsonb_agg(to_jsonb(a) order by a.periodo,a.vendedor_id)::text,''))
      from crm.cierre_mes_vendedor a),
    'periodos', (select md5(coalesce(jsonb_agg(to_jsonb(a) order by a.periodo)::text,''))
      from crm.periodos_cerrados a)
  );
$fn$;
create function pg_temp.f3_conversion_invariante() returns jsonb language sql stable as $fn$
  with meses as (
    select periodo as desde from pg_temp._f3_meses
  ) select coalesce(jsonb_agg(jsonb_build_object('mes',m.desde,
    'totales',(select (to_jsonb(t)-array['divisor_formulario','divisor_formulario_3','cierres_formulario','cierres_formulario_3'])
      || jsonb_build_object('divisor_formularios',t.divisor_formulario+t.divisor_formulario_3,
                           'cierres_formularios',t.cierres_formulario+t.cierres_formulario_3)
      from private.conversion_divisor_empresa_totales(m.desde,(m.desde+interval '1 month - 1 day')::date) t),
    'analistas',(select jsonb_agg((to_jsonb(t)-array['divisor_formulario','divisor_formulario_3','cierres_formulario','cierres_formulario_3'])
      || jsonb_build_object('divisor_formularios',t.divisor_formulario+t.divisor_formulario_3,
                           'cierres_formularios',t.cierres_formulario+t.cierres_formulario_3) order by t.analista_id)
      from private.conversion_divisor_empresa(m.desde,(m.desde+interval '1 month - 1 day')::date) t)
    ) order by m.desde),'[]'::jsonb) from meses m;
$fn$;
create temporary table _f3_invariantes_antes on commit drop as
  select pg_temp.f3_dependencias() as dependencias, pg_temp.f3_conversion_invariante() as conversion;
CREATE OR REPLACE FUNCTION private.leads_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'crm', 'public'
AS $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Puente de productores legados: n8n conserva su recibo y su huella.
  -- No cambia la asignación, la procedencia ni la política de alta manual.
  if new.origen='formulario' and new.campania_origen='Formulario 3' then
    new.origen := 'formulario_3';
  end if;
  if new.origen='formulario_3' then
    if new.campania_origen is not null and new.campania_origen<>'Formulario 3' then
      raise exception 'El origen Formulario 3 no admite otra campaña' using errcode='22023';
    end if;
  end if;
  -- Tambien aplica a importaciones y mantenimiento: no crear nuevos Otro.
  -- B7: base_cargada solo con la valvula de la carga de bases (trg_leads_000_base_cargada_solo_puerta).
  if new.origen is null or new.origen not in ('referido','landing','formulario','formulario_3','oficina','web','campania','whatsapp','base_cargada') then
    raise exception using errcode = '22023', message = 'Selecciona un canal concreto: Landing, Formulario, Formulario 3, Referido o Walking';
  end if;
  if not v_priv then
    -- B8: el contacto de una base cargada nace DORMIDO (descartado, motivo base_cargada) solo bajo la válvula de la carga
    -- (private.bases_carga_nace_dormido, una sola definición). Cualquier otra alta sigue sin poder nacer terminal.
    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
       and not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then
      raise exception 'Un lead nuevo no puede nacer en estado terminal';
    end if;
    new.perfil_id := null;
    new.contrato_id := null;
    new.convertido_en := null;
  end if;
  return new;
end;
$function$;

alter table crm.leads add constraint leads_formulario3_campania_check
  check (origen<>'formulario_3' or campania_origen is null or campania_origen='Formulario 3');

-- Primero el origen acreditado. El escritor vigente reconoce el mismo origen,
-- fuente y fecha y devuelve el recibo previo sin recalcular ni rejuvenecer relojes.
update crm.conversion_acreditaciones a set origen='formulario_3'
from _f3_acreditaciones_antes f where a.id=f.id;
-- La válvula existente evita romper el sello normal de origen; solo rige en esta transacción.
select set_config('crm.op_privilegiada','on',true);
update crm.leads l set origen='formulario_3'
from pg_temp._f3_activacion_antes f where l.id=f.id;
select set_config('crm.op_privilegiada','off',true);

do $postflight$
declare v_total integer;
begin
  select count(*) into v_total from pg_temp._f3_activacion_antes;
  if exists(select 1 from pg_temp._f3_acreditaciones_antes f
    left join crm.conversion_acreditaciones a on a.id=f.id
    where a.id is null or a.origen is distinct from 'formulario_3'
      or (to_jsonb(a)-'origen') is distinct from (f.fila-'origen')) then
    raise exception 'F3-B: cambió un dato acreditado distinto del origen';
  end if;
  if exists(select 1 from pg_temp._f3_activacion_antes f left join crm.leads l on l.id=f.id
      where l.id is null or l.origen is distinct from 'formulario_3'
        or (to_jsonb(l)-array['origen','actualizado_en']) is distinct from (f.fila-array['origen','actualizado_en'])) then
    raise exception 'F3-B: cambió un dato de negocio ajeno al origen';
  end if;
  if exists(select 1 from pg_temp._f3_otros_antes f full join crm.leads l on l.id=f.id
      where not exists(select 1 from pg_temp._f3_activacion_antes a where a.id=l.id)
        and (f.id is null or l.id is null or f.huella is distinct from md5(to_jsonb(l)::text))) then
    raise exception 'F3-B: cambió un contacto fuera del alcance';
  end if;
  if exists(select 1 from pg_temp._f3_invariantes_antes f
      where f.dependencias is distinct from pg_temp.f3_dependencias()
         or f.conversion is distinct from pg_temp.f3_conversion_invariante()) then
    raise exception 'F3-B: cambió historial, asignaciones, tareas, fotos cerradas o conversión agregada';
  end if;
  if exists(select 1 from crm.leads where origen='formulario' and campania_origen='Formulario 3') then
    raise exception 'F3-B: quedan contactos legados';
  end if;
  raise notice 'F3-B: % contactos reclasificados; asignaciones, historial y conversión conservados',v_total;
end; $postflight$;
notify pgrst, 'reload schema';
commit;

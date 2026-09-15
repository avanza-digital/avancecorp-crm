-- Ticket de Citas con TODO el capital del mes por analista.
-- Miguel (15/09/2026): «todo debe contar al ticket medio, nada debe quedar fuera».
-- Hasta hoy el ticket sólo cruzaba contratos nuevos con leads convertidos en el
-- mes: los clientes de alta directa, los upgrades, las renovaciones y las
-- cooperativas quedaban fuera, y una conversión sin contrato anulaba la fila
-- entera (Adelayda: S/ 230 000 cerrados en septiembre y ticket «Sin base»).
-- Ahora el lector entrega los episodios «stock» del núcleo de capital del mes
-- (el mismo que Mi cartera y Ranking) atribuidos al analista del núcleo, con la
-- identidad canónica de la persona para contar clientes únicos. El front calcula
-- ticket = capital del mes / clientes únicos con capital.
-- Además, la población incorpora los leads vinculados a ese capital aunque no
-- tengan actividad comercial en el mes, para que los filtros de persona (búsqueda,
-- lead, origen, registro, moneda estimada) puedan acotar también ese capital.
-- Sustitución en sitio de dos bloques únicos, como en 20260914044939.
-- No cambia los núcleos ni datos. Reversa: reponer los bloques anteriores (v_buscar*).
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
lock table private.analitica_leads_citas_exenciones,private.analitica_lc_sello in share row exclusive mode;
do $cambio$
declare
  v_def text;
  v_buscar_ids text := $buscar_ids$    union select c.lead_id from private.conversion_cierres(v_ini,least(v_fin,v_ahora+interval '1 microsecond'),
      p_desde,true,'{}'::uuid[],1,null::uuid[]) c where not c.anulado
  ), personas as ($buscar_ids$;
  v_nuevo_ids text := $nuevo_ids$    union select c.lead_id from private.conversion_cierres(v_ini,least(v_fin,v_ahora+interval '1 microsecond'),
      p_desde,true,'{}'::uuid[],1,null::uuid[]) c where not c.anulado
    -- Leads vinculados al capital del mes aunque no tengan actividad comercial en
    -- el mes: así los filtros de persona pueden acotar también ese capital.
    union select coalesce(k.lead_id,(select l.id from crm.leads l where l.perfil_id=k.cliente_id
      order by (l.etapa='convertido') desc,l.convertido_en desc nulls last,l.id limit 1))
    from private.capital_episodios(v_ini,
      least(v_fin,((v_ahora at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima'),
      true,'{}'::uuid[]) k
    where k.medida='stock' and not k.anulado
  ), personas as ($nuevo_ids$;
  v_buscar text := $buscar$  -- Importes reales del mes: contratos nuevos vinculados al perfil cliente.
  -- El vínculo canónico es contratos.cliente_id=leads.perfil_id. contrato_id
  -- del lead no se completa en el flujo actual; no es una fuente del ticket.
  -- El núcleo devuelve el capital; no se cuenta el monto estimado del lead,
  -- ni se añaden renovaciones, upgrades o desgloses al ticket inicial.
  with capital as materialized (
    select k.* from private.capital_episodios(v_ini,
      least(v_fin,((v_ahora at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima'),
      true,'{}'::uuid[]) k
    where k.tipo='contrato_nuevo' and k.medida='stock' and not k.anulado
  ), iniciales as (
    select distinct on(k.contrato_id) k.*,c->>'lead_id' as lead_cliente
    from capital k join jsonb_array_elements(v_conversiones_gestion) c
      on (c->>'perfil_id')::uuid=k.cliente_id
    where (c->>'convertido_en')::timestamptz>=v_ini and (c->>'convertido_en')::timestamptz<v_fin
    order by k.contrato_id,(c->>'convertido_en')::timestamptz,c->>'lead_id'
  )
  select coalesce(jsonb_agg(jsonb_build_object('contrato_id',k.contrato_id,'lead_id',k.lead_cliente,
    'perfil_id',k.cliente_id,'analista_id',k.analista_id,'moneda',k.moneda,'monto',k.monto,'fecha',k.fecha
  ) order by k.contrato_id),'[]'::jsonb) into v_capital from iniciales k;$buscar$;
  v_nuevo text := $nuevo$  -- Capital real del mes por analista, desde el mismo núcleo que Mi cartera y
  -- Ranking: contratos nuevos, upgrades, renovaciones y cierres en cooperativas.
  -- Medida stock, sin anulados, atribuido al analista del núcleo. No exige que el
  -- cliente proceda de un lead convertido: el ticket cuenta todo lo que el
  -- analista cierra en el mes. El lead y la identidad canónica sólo sirven para
  -- no contar dos veces a la misma persona. No usa el monto estimado del lead.
  with capital as materialized (
    select k.* from private.capital_episodios(v_ini,
      least(v_fin,((v_ahora at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima'),
      true,'{}'::uuid[]) k
    where k.medida='stock' and not k.anulado
  ), vinculo as (
    select distinct on (l.perfil_id) l.perfil_id,l.id as lead_id,l.inversionista_id
    from crm.leads l
    where l.perfil_id in (select cliente_id from capital where cliente_id is not null)
    order by l.perfil_id,(l.etapa='convertido') desc,l.convertido_en desc nulls last,l.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'contrato_id',k.contrato_id,'cierre_externo_id',k.cierre_externo_id,'tipo',k.tipo,
    'lead_id',coalesce(k.lead_id,v.lead_id),'perfil_id',k.cliente_id,
    'identidad_persona',coalesce(
      case when coalesce(lk.inversionista_id,v.inversionista_id,ce.inversionista_id) is not null then
        'persona:'||private.inversionista_canonica(coalesce(lk.inversionista_id,v.inversionista_id,ce.inversionista_id))::text end,
      (select 'persona:'||private.inversionista_canonica(i.id)::text from crm.inversionistas i
        where i.perfil_id=k.cliente_id order by 1 limit 1),
      'perfil:'||k.cliente_id::text,
      'lead:'||coalesce(k.lead_id,v.lead_id)::text,
      'externo:'||k.cierre_externo_id::text),
    'analista_id',k.analista_id,'analista_nombre',coalesce(pa.nombre_completo,'Sin analista'),
    'supervisor_id',e.supervisor_id,'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
    'moneda',k.moneda,'monto',k.monto,'fecha',k.fecha
  ) order by k.fecha,k.contrato_id,k.cierre_externo_id),'[]'::jsonb) into v_capital
  from capital k
  left join vinculo v on v.perfil_id=k.cliente_id
  left join crm.leads lk on lk.id=k.lead_id
  left join crm.cierres_externos ce on ce.id=k.cierre_externo_id
  left join public.perfiles pa on pa.id=k.analista_id
  left join crm.equipo e on e.perfil_id=k.analista_id
  left join public.perfiles ps on ps.id=e.supervisor_id;$nuevo$;
begin
  v_def:=pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure);
  if md5(v_def)<>'4ad2b90baf96b11b63a626122bd5d64b' then
    raise exception 'El lector de Citas difiere de la versión viva verificada el 15/09; conciliar antes de continuar';
  end if;
  if md5(pg_get_functiondef('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure))
    is distinct from 'c9e58c1da9dd7a5d52991c9e47dc19d5' then
    raise exception 'El núcleo de capital cambió; revisar el contrato del ticket';
  end if;
  perform private.assert_analitica_leads_citas();
  if (length(v_def)-length(replace(v_def,v_buscar,'')))/length(v_buscar)<>1 then
    raise exception 'No se reconoce el único bloque de capital del lector de Citas';
  end if;
  if (length(v_def)-length(replace(v_def,v_buscar_ids,'')))/length(v_buscar_ids)<>1 then
    raise exception 'No se reconoce el único bloque de población del lector de Citas';
  end if;
  execute replace(replace(v_def,v_buscar,v_nuevo),v_buscar_ids,v_nuevo_ids);
end $cambio$;
update private.analitica_leads_citas_exenciones e
set huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
 razon='Detalle operativo Gerencia: citas desde citas_episodios y cierres desde conversion_cierres. Base mensual desde ledger inmutable lead_asignaciones, personas distintas por analista; identidad y autor de alta manual desde leads. Incluye hechos mensuales de registro de citas, atribución de origen y de cierre, y el capital real completo del mes desde capital_episodios (contratos nuevos, upgrades, renovaciones y cooperativas, medida stock) atribuido al analista del núcleo, con identidad canónica para clientes únicos. No usa importes estimados como depósitos. La población conserva la identidad del inversionista canónico, con respaldo en perfil o lead cuando no existe ese vínculo, incluso sin conversión.'
from pg_proc p where p.oid='private.citas_gerencia_consulta(date,date)'::regprocedure
 and e.objeto='private.citas_gerencia_consulta(date,date)';
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
select private.assert_analitica_leads_citas();
commit;

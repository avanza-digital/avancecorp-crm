-- Diagnóstico G7 retrospectivo. No activa capacidades ni confirma inversiones.
-- NUMERIC y EXCEPT ALL conservan importes exactos y multiplicidad.
begin isolation level repeatable read read only;
set local statement_timeout='30s';
set local lock_timeout='1s';
set local search_path='';
set local timezone='UTC';
with fuentes as materialized (
  select * from private.cartera_f5_fuentes_reales()
), capital as materialized (
  select coalesce(e.contrato_id,e.cierre_externo_id) fuente_id,
    case when e.contrato_id is not null then 'avance' else ce.cooperativa end empresa,
    e.moneda,e.monto capital,e.analista_id,
    (e.fecha at time zone 'America/Lima')::date fecha_imputacion,e.tipo
  from private.capital_episodios('-infinity','infinity',true,'{}') e
  left join crm.cierres_externos ce on ce.id=e.cierre_externo_id
  where e.medida='stock'
), metricas as materialized (
  select * from private.metricas_f7_fuentes()
), diferencias_cartera as materialized (
  (select fuente_id,empresa,moneda,capital,analista_id,fecha_imputacion from capital
   except all
   select fuente_id,empresa,moneda,capital,analista_origen_id,fecha_imputacion from fuentes)
  union all
  (select fuente_id,empresa,moneda,capital,analista_origen_id,fecha_imputacion from fuentes
   except all
   select fuente_id,empresa,moneda,capital,analista_id,fecha_imputacion from capital)
), diferencias_metricas as materialized (
  (select fuente_id,empresa,moneda,capital,analista_id,fecha_imputacion,tipo from capital
   except all
   select fuente_id,empresa,moneda,capital,analista_id,fecha_imputacion,tipo_capital from metricas)
  union all
  (select fuente_id,empresa,moneda,capital,analista_id,fecha_imputacion,tipo_capital from metricas
   except all
   select fuente_id,empresa,moneda,capital,analista_id,fecha_imputacion,tipo from capital)
), personas as materialized (
  select i.id,i.estado,i.responsable_relacion_id,i.inversionista_canonico_id,
    array_agg(distinct f.empresa order by f.empresa) empresas,
    exists(select 1 from crm.inversionista_identificadores d
      where private.inversionista_canonica(d.inversionista_id)=i.id
        and d.estado='vigente' and d.verificado) documento_verificado
  from fuentes f join crm.inversionistas i on i.id=f.inversionista_id
  group by i.id
), secuencia as materialized (
  select f.*,lag(empresa) over(partition by inversionista_id order by creado_en,fuente_id) previa
  from fuentes f
), control as materialized (
  select * from crm.piloto_f8_control where singleton
), nuevas as materialized (
  -- creado_en de la fuente: no confundir fecha comercial ni alta del enlace F4.
  select f.*,exists(select 1 from crm.piloto_f8_miembros m
    where m.perfil_id=f.analista_origen_id and m.activo) analista_del_piloto
  from fuentes f cross join control c where f.creado_en>=c.inicia_en
), por_persona_empresa as materialized (
  select f.*,row_number() over(partition by empresa,inversionista_id
    order by creado_en desc,fuente_id) posicion_persona
  from fuentes f
), candidatas as materialized (
  select f.*,row_number() over(partition by empresa order by creado_en desc,fuente_id) posicion_empresa
  from por_persona_empresa f where posicion_persona=1
), muestra as materialized (
  -- Muestra histórica estratificada de lectura; NO veinte altas nuevas F8.
  select * from candidatas where posicion_empresa<=case when empresa='avance' then 10 else 5 end
)
select jsonb_build_object(
  'version',1,'corte',statement_timestamp(),'snapshot',txid_current_snapshot()::text,
  'solo_lectura',current_setting('transaction_read_only'),
  'alcance','Paridad interna de núcleos y datos existentes; no contabilidad externa ni firma G7.',
  'piloto',(select jsonb_build_object('activo',activo,'revision',revision,
    'inicia_en',inicia_en,'vence_en',vence_en) from control),
  'banderas',(select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags),
  'conciliacion',jsonb_build_object('fuentes_cartera',(select count(*) from fuentes),
    'fuentes_capital',(select count(*) from capital),'fuentes_metricas',(select count(*) from metricas),
    'diferencias_cartera_capital',(select count(*) from diferencias_cartera),
    'diferencias_metricas_capital',(select count(*) from diferencias_metricas),
    'fuentes_duplicadas',(select count(*) from(select empresa,fuente_id from fuentes
      group by empresa,fuente_id having count(*)<>1)d),
    'sin_identidad_coherente',(select count(*) from fuentes f left join crm.inversionistas i
      on i.id=f.inversionista_id where not coalesce(f.identidad_coherente,false)
        or i.id is null or i.inversionista_canonico_id is not null),
    'identidades_metricas_distintas',(select count(*) from metricas m join fuentes f
      using(empresa,fuente_id) where m.inversionista_id is distinct from f.inversionista_id)),
  'por_empresa',(select jsonb_agg(to_jsonb(t) order by empresa) from(
    select empresa,count(*) inversiones,count(distinct inversionista_id) identidades,
      count(*) filter(where inversion_id is not null) con_relacion_f4,
      count(*) filter(where inversion_id is null) legado_sin_relacion_f4,
      count(*) filter(where analista_origen_id is null) sin_atribucion
    from fuentes group by empresa)t),
  'identidades',jsonb_build_object('total',(select count(*) from personas),
    'sin_documento_verificado',(select count(*) from personas where not documento_verificado),
    'sin_responsable',(select count(*) from personas where responsable_relacion_id is null),
    'sin_perfil',(select count(*) from personas p join crm.inversionistas i on i.id=p.id where i.perfil_id is null),
    'multiempresa',(select count(*) from personas where cardinality(empresas)>1),
    'estados',(select jsonb_agg(to_jsonb(t)) from(select estado,count(*) cantidad from personas group by estado)t)),
  'altas_desde_inicio',(select jsonb_agg(to_jsonb(t) order by empresa) from(
    select e.clave empresa,count(n.fuente_id) todas,
      count(n.fuente_id) filter(where n.analista_del_piloto) equipo_piloto
    from crm.empresas e left join nuevas n on n.empresa=e.clave where e.activa group by e.clave)t),
  'recorridos_historicos',(select coalesce(jsonb_agg(to_jsonb(t) order by previa,empresa),'[]'::jsonb) from(
    select previa,empresa,count(*) transiciones,count(distinct inversionista_id) personas
    from secuencia where previa is not null group by previa,empresa)t),
  'solicitudes_nuevas',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from(
    select s.estado,count(*) cantidad from crm.inversion_solicitudes s cross join control c
    where s.creado_en>=c.inicia_en group by s.estado)t),
  'casos_existentes',jsonb_build_object(
    'cotitulares',(select count(*) from crm.inversion_titulares t join fuentes f on f.inversion_id=t.inversion_id where t.rol='cotitular'),
    'retiros',(select count(*) from crm.postventa_retiros r join fuentes f using(fuente_id,empresa)),
    'anulaciones_coopac',(select count(*) from fuentes where estado='anulado_comercialmente'),
    'upgrades',(select count(*) from crm.operaciones_cartera o join fuentes f on f.fuente_id=o.contrato_nuevo_id and f.empresa='avance' where o.tipo='upgrade'),
    'upgrades_atribuidos_a_otro',(select count(*) from crm.operaciones_cartera o join fuentes f on f.fuente_id=o.contrato_nuevo_id and f.empresa='avance'
      where o.tipo='upgrade' and f.analista_origen_id is distinct from o.vendedor_id)),
  'muestra_retrospectiva',jsonb_build_object('fuentes',(select count(*) from muestra),
    'identidades',(select count(distinct inversionista_id) from muestra),
    'por_empresa',(select jsonb_agg(to_jsonb(t) order by empresa) from(select empresa,count(*) fuentes,
      count(distinct inversionista_id) identidades from muestra group by empresa)t),
    'fuentes_hash',(select jsonb_agg(jsonb_build_object('empresa',empresa,
      'fuente',md5('G7-20260915:'||fuente_id::text),'persona',md5('G7-20260915:'||inversionista_id::text),
      'fecha_registro',creado_en,'desde_inicio',creado_en>=(select inicia_en from control)) order by empresa,creado_en,fuente_id) from muestra)),
  'fotos_selladas',(select coalesce(jsonb_agg(jsonb_build_object('periodo',pc.periodo,
    'huella_periodo',md5(to_jsonb(pc)::text),'filas',(select count(*) from crm.cierre_mes_vendedor f where f.periodo=pc.periodo),
    'huella_filas',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.vendedor_id),'[]'::jsonb)::text)
      from crm.cierre_mes_vendedor f where f.periodo=pc.periodo)) order by pc.periodo),'[]'::jsonb) from crm.periodos_cerrados pc),
  'funciones',(select jsonb_object_agg(p.oid::regprocedure::text,md5(pg_get_functiondef(p.oid)))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('crm','private')
    and p.proname in('cartera_f5_fuentes','cartera_f5_fuentes_reales','metricas_f7_fuentes','capital_episodios',
      'inversionista_canonica','cartera_inversionistas_estado_fn','inversionista_ficha_fn'))
) evidencia;
rollback;

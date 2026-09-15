begin isolation level read committed;
set local statement_timeout='20s'; set local lock_timeout='2s'; set local search_path='';
do $casos$
declare a uuid; p record; f jsonb; r jsonb:='[]';
begin
  select perfil_id into strict a from crm.piloto_f8_miembros where activo and rol_esperado='gerencia';
  for p in select i.id from crm.inversionistas i where i.responsable_relacion_id is null
    and exists(select 1 from private.cartera_f5_fuentes_reales() f where f.inversionista_id=i.id) order by i.id
  loop
    perform set_config('request.jwt.claim.sub',a::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
    set local role authenticated;
    f:=crm.inversionista_ficha_fn(p.id,1,1);
    reset role;
    r:=r||jsonb_build_array(jsonb_build_object('persona',md5('G7-20260915:'||p.id::text),
      'visible',f is not null,'nueva_inversion',(f#>>'{capacidades,nueva_inversion}')::boolean,
      'inversiones',(f->>'inversiones_total')::integer));
  end loop;
  perform set_config('g7.casos',r::text,true);
end;
$casos$;
with f as materialized(select * from private.cartera_f5_fuentes_reales())
select jsonb_build_object('corte',statement_timestamp(),'sin_responsable',current_setting('g7.casos')::jsonb,
  'cotitulares_contractuales',(select count(*) from public.contrato_titulares t join f on f.fuente_id=t.contrato_id and f.empresa='avance' where t.orden>1),
  'contratos_con_anulacion_comercial',(select count(distinct f.fuente_id) from f join crm.leads l on l.contrato_id=f.fuente_id
    join crm.cierres_avance_anulados a on a.lead_id=l.id where f.empresa='avance'),
  'gestiones_postventa',(select count(*) from crm.inversionista_gestiones),
  'depositos_reclamados',(select count(*) from crm.depositos_reclamados d join f on f.fuente_id=d.cierre_id and f.empresa<>'avance'),
  'metodo','Lecturas SQL con Gerencia, roles y ROLLBACK. No reasignaciones ni escrituras económicas.') evidencia;
rollback;

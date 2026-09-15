-- Complemento G7: ancla inmutable, autoría separada de atribución y desglose.
begin isolation level repeatable read read only;
set local statement_timeout='20s';
set local search_path='';
with ancla as (select timestamptz '2026-09-14T18:23:51.712435Z' inicio),
f as materialized(select * from private.cartera_f5_fuentes_reales()),
k as materialized(select * from private.capital_episodios('-infinity','infinity',true,'{}')),
nuevas as materialized(
  select f.*,k.registrado_por,
    exists(select 1 from crm.piloto_f8_miembros m where m.activo and m.perfil_id=k.registrado_por) autor_piloto,
    exists(select 1 from crm.piloto_f8_miembros m where m.activo and m.perfil_id=f.analista_origen_id) atribuida_piloto
  from f join k on coalesce(k.contrato_id,k.cierre_externo_id)=f.fuente_id and k.medida='stock'
  cross join ancla where f.creado_en>=ancla.inicio
),
esperado as materialized(
  select o.contrato_nuevo_id contrato_id,'desglose_'||parte.tipo tipo,o.moneda,parte.monto,
    coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),o.vendedor_id) analista_id,
    o.periodo mes_comercial,o.fecha_operacion fecha
  from crm.operaciones_cartera o join public.contratos c on c.id=o.contrato_nuevo_id and not c.es_demo
  cross join lateral(values('renovado',o.capital_renovado),('adicional',o.capital_adicional)) parte(tipo,monto)
  where parte.monto is not null
), actual as materialized(
  select contrato_id,tipo,moneda,monto,analista_id,mes_comercial,
    (fecha at time zone 'America/Lima')::date fecha from k where medida='desglose'
), diferencias as(
  (select * from esperado except all select * from actual)
  union all (select * from actual except all select * from esperado)
)
select jsonb_build_object('corte',statement_timestamp(),'ancla_acumulada',(select inicio from ancla),
  'inicio_control_vivo',(select inicia_en from crm.piloto_f8_control where singleton),
  'ancla_coincide',(select inicia_en=(select inicio from ancla) from crm.piloto_f8_control where singleton),
  'altas',(select jsonb_agg(to_jsonb(t) order by empresa) from(
    select e.clave empresa,count(n.fuente_id) fuentes,
      count(n.fuente_id) filter(where autor_piloto) autor_del_piloto,
      count(n.fuente_id) filter(where atribuida_piloto) atribuidas_al_piloto,
      count(n.fuente_id) filter(where registrado_por is null) sin_autor
    from crm.empresas e left join nuevas n on n.empresa=e.clave where e.activa group by e.clave)t),
  'confirmaciones_f4',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from(
    select s.estado,count(*) solicitudes,
      count(*) filter(where s.creado_por in(select perfil_id from crm.piloto_f8_miembros where activo)) preparadas_por_piloto,
      count(*) filter(where s.confirmado_por in(select perfil_id from crm.piloto_f8_miembros where activo)) confirmadas_por_piloto
    from crm.inversion_solicitudes s cross join ancla where s.creado_en>=ancla.inicio group by s.estado)t),
  'desglose',jsonb_build_object('filas_esperadas',(select count(*) from esperado),'filas_nucleo',(select count(*) from actual),
    'diferencias',(select count(*) from diferencias),
    'renovaciones_completas',(select count(*) from crm.operaciones_cartera o join public.contratos c on c.id=o.contrato_nuevo_id
      where not c.es_demo and o.tipo='renovacion' and o.desglose_completo),
    'renovaciones_con_suma_incorrecta',(select count(*) from crm.operaciones_cartera o join public.contratos c on c.id=o.contrato_nuevo_id
      where not c.es_demo and o.tipo='renovacion' and o.desglose_completo
        and (o.capital_renovado is null or o.capital_adicional is null
          or o.capital_renovado+o.capital_adicional is distinct from c.capital)),
    'renovaciones_historicas_sin_desglose',(select count(*) from crm.operaciones_cartera o join public.contratos c on c.id=o.contrato_nuevo_id
      where not c.es_demo and o.tipo='renovacion' and not o.desglose_completo),
    'upgrades_sin_puente_renovacion',(select count(*) from crm.operaciones_cartera o join public.contratos c on c.id=o.contrato_nuevo_id
      where not c.es_demo and o.tipo='upgrade' and o.capital_renovado is null and o.capital_adicional is null)),
  'candidato_reasignado',(select jsonb_agg(jsonb_build_object('operacion',md5('G7-20260915:'||o.id::text),
    'persona',md5('G7-20260915:'||f.inversionista_id::text),'empresa',f.empresa,
    'stock_coincide',f.capital=k.monto,'atribucion_coincide',f.analista_origen_id=k.analista_id,
    'autor_preservado_coincide',c.creado_por=k.registrado_por,
    'analista_actual_difiere_vendedor_registrado',f.analista_origen_id is distinct from o.vendedor_id))
    from crm.operaciones_cartera o join f on f.fuente_id=o.contrato_nuevo_id and f.empresa='avance'
    join public.contratos c on c.id=f.fuente_id join k on k.contrato_id=c.id and k.medida='stock'
    where o.tipo='upgrade' and f.analista_origen_id is distinct from o.vendedor_id),
  'pk_cierre_mes',(select pg_get_constraintdef(oid) from pg_constraint where conrelid='crm.cierre_mes_vendedor'::regclass and contype='p'),
  'funciones_contexto',(select jsonb_object_agg(p.oid::regprocedure::text,md5(pg_get_functiondef(p.oid)))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('crm','private')
    and p.proname in('analista_atribuido_cadena','piloto_f8_actor_activo','postventa_estado_fn','rol_crm',
      'es_lector_global','puede_gestionar_contratos_crm','inversiones_escritura_bajo_candado','inversionista_ficha_fn')),
  'limite','Coherencia interna por fuentes compartidas. No ejecución de una reasignación, autenticación documental ni aceptación financiera.'
) evidencia;
rollback;

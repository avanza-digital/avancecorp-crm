-- SIEMBRA DE CONTROL para un BANCO Docker montado con el esquema de producción y SIN datos.
--
-- Por qué existe: la migración 20261001154153 exige, como en producción, que la declaración
-- analítica de `crm.cartera_filtrada_fn` esté vigente y sellada. Esas tres tablas del trinquete
-- (`private.analitica_leads_citas_exenciones`, `…_tope`, `private.analitica_lc_sello`) son DATOS
-- de configuración: un volcado de solo esquema las deja vacías y el preflight, con razón, se
-- niega. Regla de la casa: sembrar antes que parchear — se le da al banco el dato y la guarda se
-- ejecuta de verdad; no se desmonta la guarda.
--
-- Qué siembra (sintético, cero datos de personas): una declaración por cada contador del censo
-- con SU huella calculada por la misma fórmula del censo, el techo y el sello. La fila de
-- `crm.cartera_filtrada_fn` lleva la clase y la razón reales de producción (las de la migración
-- 20260929195918) y la fecha original de su declaración (13/09). Las demás clases salen de
-- 20260922153708 (lo posterior, `operativo`): sirven para que el gate esté verde, no pretenden
-- ser el texto de producción.
--
-- NUNCA contra producción: se niega si alguna de las tres tablas ya tiene filas o si hay leads
-- o perfiles (un banco recién montado no tiene nada).
begin;
set local search_path = '';

do $guarda$
begin
  if exists (select 1 from private.analitica_leads_citas_exenciones)
     or exists (select 1 from private.analitica_lc_sello)
     or exists (select 1 from private.analitica_leads_citas_tope) then
    raise exception 'SIEMBRA: las tablas del trinquete ya tienen filas; este guion es solo para un banco recien montado';
  end if;
  if exists (select 1 from crm.leads) or exists (select 1 from public.perfiles) then
    raise exception 'SIEMBRA: hay leads o perfiles; esto no es un banco vacio';
  end if;
end;
$guarda$;

-- 1) Los dos verificadores primero: con su declaración y su huella salen del censo, como en
--    producción (migración 20260921190145).
insert into private.analitica_leads_citas_exenciones (objeto, tipo, huella, razon, declarado_en, clase)
select p.oid::regprocedure::text, 'funcion',
  md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
    '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
  'SIEMBRA DE BANCO (sintetica): verificador; cuenta para comprobar cifras ajenas.',
  '2026-09-21T00:00:00Z', 'verificador'
from pg_proc p
where p.oid in ('crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure,
                'private.citas_testigo_mes(date,date)'::regprocedure);

-- 2) El resto del censo, cada contador con su huella vigente.
insert into private.analitica_leads_citas_exenciones (objeto, tipo, huella, razon, declarado_en, clase)
select c.objeto, c.tipo,
  md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
    '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
  case when c.objeto like 'crm.cartera\_filtrada\_fn(%' escape '\'
    then 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia y reasignacion entre analistas. No calcula conversion mensual.'
    else 'SIEMBRA DE BANCO (sintetica): declaracion de relleno para que el censo quede vigente.' end,
  case when c.objeto like 'crm.cartera\_filtrada\_fn(%' escape '\'
    then '2026-09-13T00:00:00Z'::timestamptz else '2026-09-22T00:00:00Z'::timestamptz end,
  coalesce(k.clase, 'operativo')
from private.contadores_crudos_leads_citas() c
join pg_proc p on p.oid = to_regprocedure(c.objeto)
left join (values
    ('crm.cerrar_periodo(date)', 'analitica'),
    ('crm.cierres_externos_fn(date)', 'analitica'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', 'analitica'),
    ('crm.metricas_sla_fn(date,date)', 'analitica'),
    ('crm.metricas_vendedores_fn()', 'mixta'),
    ('crm.series_comerciales_fn(integer)', 'mixta'),
    ('private.citas_gerencia_consulta(date,date)', 'analitica'),
    ('private.metricas_agenda_implementacion(date,date)', 'analitica'),
    ('private.metricas_conversiones_implementacion(date,date,text)', 'analitica'),
    ('private.metricas_distribucion_leads_core(date,date,timestamp with time zone)', 'mixta'),
    ('private.metricas_reuniones_implementacion(date,date)', 'analitica'),
    ('private.metricas_sla_global_core(date,date,timestamp with time zone)', 'analitica'),
    ('private.produccion_mes_por_vendedor(timestamp with time zone,timestamp with time zone,uuid)', 'analitica'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', 'analitica'),
    ('crm.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamp with time zone,uuid)', 'analitica'),
    ('crm.metricas_multiempresa_fn(date)', 'analitica')
  ) as k(objeto, clase) on k.objeto = c.objeto
where c.tipo = 'funcion';

-- 2b) Quien llama a los núcleos (`citas_episodios` / `conversion_cierres`) también debe estar
--     declarado aunque el censo no lo atrape: el gate lo exige como su «puerta escrita».
insert into private.analitica_leads_citas_exenciones (objeto, tipo, huella, razon, declarado_en, clase)
select p.oid::regprocedure::text, 'funcion',
  md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
    '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
  'SIEMBRA DE BANCO (sintetica): consumidor declarado de un nucleo de Citas/Conversion.',
  '2026-09-22T00:00:00Z', 'analitica'
from pg_proc p
where p.prokind in ('f', 'p')
  and p.oid <> coalesce(to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)'), 0)
  and p.oid <> coalesce(to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'), 0)
  and p.oid <> coalesce(to_regprocedure('private.assert_analitica_leads_citas()'), 0)
  and p.oid <> coalesce(to_regprocedure('private.contadores_crudos_leads_citas()'), 0)
  and regexp_replace(regexp_replace(coalesce(p.prosrc, ''), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')
      ~ '\m(citas_episodios|conversion_cierres)\s*\('
  and not exists (select 1 from private.analitica_leads_citas_exenciones e
                   where e.objeto = p.oid::regprocedure::text);

-- 3) Techo: lo que hoy pesa bajo él (analítica + mixta, sin los auxiliares auditados).
insert into private.analitica_leads_citas_tope (id, tope)
select true, count(*)
from private.contadores_crudos_leads_citas() c
join private.analitica_leads_citas_exenciones e on e.objeto = c.objeto
where e.clase in ('analitica', 'mixta')
  and c.objeto not in (select a.objeto from private.auxiliares_analitica_lc_auditados() a);

-- 4) Sello de la lista.
insert into private.analitica_lc_sello (id, sello)
values (true, private.huella_exenciones_analitica_lc());

do $recibo$
declare v_gate text;
begin
  if (
    (select count(*) from private.contadores_crudos_leads_citas() c where not (c.declarada and c.huella_ok)) = 0
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto like 'crm.cartera\_filtrada\_fn(%' escape '\' and c.declarada and c.huella_ok)
  ) is not true then
    raise exception 'SIEMBRA: el censo no quedo declarado y vigente';
  end if;
  v_gate := private.assert_analitica_leads_citas();
  raise notice 'SIEMBRA-CONTROL-OK · %', v_gate;
end;
$recibo$;
commit;

-- REGISTRO en supabase_migrations.schema_migrations de 20261001154153_crm_cartera_filtro_gestion.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se
-- niega si la firma de 13 argumentos no es la publicada o si la versión ya está registrada con
-- otro nombre u otro contenido. statements = el archivo entero (md5 9236dd635b1dfadcff76d1cd2492df32).
-- GENERADO por supabase/scripts/cartera-gestion/generar-registrador.mjs; no editar a mano.
begin;
set local lock_timeout = '5s';
set local search_path = '';
select pg_advisory_xact_lock(hashtext('crm_cartera_filtro_gestion_registro'));
do $chk$
begin
  if (
    to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') is not null
    and to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)') is null
    and md5(pg_get_functiondef(to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'))) = 'bf06666fb8ef533a39a50c7d70420153'
  ) is not true then
    raise exception 'REGISTRO: la migración 20261001154153 no está aplicada tal cual; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261001154153' and (coalesce(name, '') <> 'crm_cartera_filtro_gestion' or statements is distinct from array[$migracion_20261001154153$-- Pipeline · columna «Gestionado»: filtro opcional `p_gestion` en `crm.cartera_filtrada_fn`
-- (pedido de los analistas; regla de negocio decidida por Miguel el 01/10/2026).
--
-- QUÉ. La función gana UN argumento al final, `p_gestion text default null`:
--   · null          → no recorta: la respuesta es idéntica a la de hoy;
--   · 'con_gestion' → leads cuyo titular ACTUAL ya intentó el contacto desde que los recibió
--                     (un resultado de llamada deshecho no cuenta);
--   · 'sin_gestion' → todos los demás (sin titular o sin `tenencia_desde` ⇒ sin gestión).
--   Cualquier otro valor → 22023, por el mismo bloque de validación que origen y procedencia.
--
-- POR QUÉ. El Pipeline separa, dentro de `etapa = 'nuevo'`, lo que ya se intentó contactar
-- (llamada sin respuesta, WhatsApp enviado) de lo que nadie ha tocado. NO nace una etapa
-- guardada: la columna se calcula. Regla de Miguel: un lead REASIGNADO que el analista anterior
-- ya intentó es «Nuevo» para el actual; solo cuenta lo gestionado desde `crm.leads.tenencia_desde`
-- (lo sella el trigger `trg_leads_zzz_tenencia_desde`; se renueva al reasignar y al reabrir).
-- Gestión = los 5 tipos de contacto de `actividades_contacto_episodio_idx`; una nota no cuenta.
-- Tampoco cuenta un resultado de llamada DESHECHO (`metadata.deshecho_en`): como en los núcleos
-- de Gestión Diaria, lo deshecho «no ocurrió» y el lead vuelve a «Nuevo» (decisión del 01/10).
--
-- QUÉ NO CAMBIA. La FORMA del payload (ni claves arriba ni campos por fila: hay navegadores con
-- el bundle viejo leyéndolo; el filtro no lleva eco), INVOKER bajo la RLS de leads y actividades,
-- `stable`, `search_path` vacío, dueño y ACL (solo `authenticated` ejecuta). Recorta la MISMA
-- base que los demás filtros: filas, totales, capital y embudo salen juntos. Una sola firma: se
-- retira la de 12 argumentos (dos candidatas romperían PostgREST) y su exención analítica se
-- MUEVE a la de 13 (misma clase y fecha de declaración) y se resella.
--
-- ORDEN DE PUBLICACIÓN: servidor primero, pantalla después. El frente nuevo envía `p_gestion`
-- y sin esta migración recibiría PGRST202; el frente viejo no lo envía y sigue igual.
--
-- REVERSA: `supabase/scripts/cartera-gestion/reversa.sql`, tras retirar el frente que envía
-- `p_gestion`. Quita la firma de 13, reinstala la de 12 byte a byte (md5 7169d942…), devuelve la
-- exención analítica a su firma y resella. No toca datos.
--
-- ANCLAS. La regla descansa en dos relojes que sella el servidor: el del LEAD (`tenencia_desde`,
-- guarda 4) y el de la ACTIVIDAD (`creado_en` re-sellado y `deshecho_en` reservado, guarda 5, que
-- además fija la policy de INSERT, las restrictivas de las dos tablas y que la API no pueda
-- reescribir ni borrar actividades). Todas se midieron con `search_path` vacío, que se fija abajo
-- para la transacción: el texto de `pg_get_functiondef`, `pg_get_triggerdef` y `pg_get_expr`
-- cambia con el `search_path` de la sesión, y así el resultado no depende de quién aplique.
-- Kit, ensayo y consulta de solo lectura para acreditarlas contra producción:
-- `supabase/scripts/cartera-gestion/`.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f12_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
begin
  -- 1. La función viva es la auditada: una sola firma (la de 12) y su cuerpo exacto.
  --    Guardas en positivo con `is not true`: un NULL también rechaza.
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f12) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f12))) = '7169d94239dcb191bafa3faed46f916f'
  ) is not true then
    raise exception 'PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada';
  end if;
  -- 2. Su declaración analítica está vigente (huella al día), es de inventario y la lista está
  --    sellada: esta migración la mueve y resella; no se resella a ciegas una lista alterada.
  if (
    exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = f12_larga and c.declarada and c.huella_ok)
    and (select e.clase from private.analitica_leads_citas_exenciones e
          where e.objeto = f12_larga) = 'operativo'
    and (select s.sello from private.analitica_lc_sello s where s.id)
          = private.huella_exenciones_analitica_lc()
  ) is not true then
    raise exception 'PREFLIGHT: la declaracion analitica no esta vigente y sellada';
  end if;
  -- 3. El filtro lee `crm.actividades` como INVOKER: su RLS debe seguir siendo coextensiva con
  --    la de leads (si no, un lead visible con actividades ocultas saldría «sin gestión»).
  perform private.assert_actividades_de_lead_base();
  -- 4. El reloj de la regla. «Solo cuenta lo gestionado desde que el titular ACTUAL recibió el
  --    lead» descansa en que `tenencia_desde` lo sella el servidor y se renueva al reasignar.
  --    Si el trigger falta, está apagado o cambió de cuerpo, el filtro mentiría en silencio.
  if (
    (select count(*) from pg_trigger t
      where t.tgrelid = 'crm.leads'::regclass
        and t.tgname = 'trg_leads_zzz_tenencia_desde'
        and not t.tgisinternal and t.tgenabled = 'O'
        and md5(pg_get_triggerdef(t.oid)) = 'f5849e264eb05e8a253dbd78c2362fba'
        and md5(pg_get_functiondef(t.tgfoid)) = '900508fa3ccf3eec2e738ccdeebad7be') = 1
  ) is not true then
    raise exception 'PREFLIGHT: el sello de tenencia_desde no coincide con la version auditada';
  end if;
  -- 5. El reloj y la integridad de la ACTIVIDAD. La regla compara `creado_en` con la tenencia y
  --    descarta lo deshecho, y eso solo es infalsificable mientras:
  --    (a) el servidor selle `creado_en` y revalide el ámbito (trg_01) y reserve los resultados
  --        de llamada y `deshecho_en` (trg_00);
  --    (b) haya RLS y la única vía de escritura de la API sea la policy de INSERT auditada, sin
  --        permisivas ALL ni policies de UPDATE/DELETE;
  --    (c) las RESTRICTIVAS de las dos tablas sean exactamente el gate del actor activo: una
  --        restrictiva de lectura añadida daría a titular y supervisor veredictos distintos
  --        sobre el mismo lead, y `assert_actividades_de_lead_base` solo mira que el gate esté;
  --    (d) ni `authenticated` ni `anon` puedan reescribir o borrar una actividad.
  if (
    (select count(*) from pg_trigger t
      where t.tgrelid = 'crm.actividades'::regclass and not t.tgisinternal and t.tgenabled = 'O'
        and (t.tgname::text, md5(pg_get_triggerdef(t.oid)), md5(pg_get_functiondef(t.tgfoid))) in (
          ('trg_01_gestion_lead_serializada', 'a7d2d742991f2ac9fbf3d52343a25532', '7af0e66b8a4849566e43b514245e1b86'),
          ('trg_00_actividades_resultado_solo_nucleo', '24037d111fc11c9b5fd3c9677e329bdf', '19952736370f64026f747c19b54ab38e'))) = 2
    and (select bool_and(c.relrowsecurity) from pg_class c
          where c.oid in ('crm.actividades'::regclass, 'crm.leads'::regclass))
    and (select count(*) from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a') = 1
    and exists (select 1 from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a'
            and p.polname = 'actividades_insert' and p.polpermissive
            and p.polroles = array['authenticated'::regrole::oid]
            and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = 'b2d6792bc6913861ca74f4398e6a12ab')
    and not exists (select 1 from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass
            and ((p.polcmd = '*' and p.polpermissive) or p.polcmd in ('w', 'd')))
    and (select count(*) from pg_policy p
          where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
            and not p.polpermissive) = 2
    and (select count(*) from pg_policy p
          where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
            and not p.polpermissive and p.polname = 'crm_actor_activo_gate' and p.polcmd = '*'
            and p.polroles = array['authenticated'::regrole::oid]
            and md5(pg_get_expr(p.polqual, p.polrelid)) = 'c5e6c90632bc616212336e1d089a68b3'
            and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = 'c5e6c90632bc616212336e1d089a68b3') = 2
    and not has_any_column_privilege('authenticated', 'crm.actividades', 'UPDATE')
    and not has_table_privilege('authenticated', 'crm.actividades', 'DELETE')
    and not has_any_column_privilege('anon', 'crm.actividades', 'UPDATE')
    and not has_table_privilege('anon', 'crm.actividades', 'DELETE')
  ) is not true then
    raise exception 'PREFLIGHT: la fuente de gestiones (crm.actividades) no coincide con la version auditada';
  end if;
end;
$preflight$;

-- Foto de lo que NO debe cambiar: contrato de seguridad de la función, censo analítico,
-- declaraciones ajenas, la propia declaración (clase, tipo y fecha) y el consumidor.
create temporary table cartera_gestion_preflight on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean);

create function crm.cartera_filtrada_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null,
  p_desde date default null,
  p_hasta date default null,
  p_origen text default null,
  p_procedencia text default null,
  p_reasignados boolean default false,
  p_gestion text default null
)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     -- Mismo dominio que el CHECK de crm.leads.origen: los 5 vigentes y los 3
     -- históricos (web, campania, whatsapp) siguen siendo consultables.
     or (p_origen is not null and p_origen not in
       ('referido','landing','formulario','oficina','otro','web','campania','whatsapp'))
     -- Procedencia: 'sistema' (puente automático) o 'manual' (una persona).
     -- Otro valor se rechaza: nunca un «cero resultados» silencioso.
     or (p_procedencia is not null and p_procedencia not in ('sistema','manual'))
     -- Gestión: 'con_gestion' (el titular actual ya intentó el contacto) o
     -- 'sin_gestion' (el resto). Otro valor se rechaza, igual que arriba.
     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), base as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
    from crm.leads l
    -- Una primera entrega desde la cola tiene vendedor_anterior NULL. Solo
    -- cuenta un analista ANTERIOR, incluso si volvió al mismo titular tras
    -- pasar por la bandeja. El evento lo emite el trigger del servidor.
    left join lateral (
      select true as reasignado
      from crm.actividades a
      where l.vendedor_id is not null
        and a.lead_id = l.id
        and a.tipo = 'reasignacion'
        and a.metadata ->> 'vendedor_anterior' is not null
      limit 1
    ) mov on true
    left join recepciones r on r.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      -- El origen acota la MISMA base: filas, totales, capital y embudo juntos.
      and (p_origen is null or l.origen = p_origen)
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      -- Gestión vigente: el titular ACTUAL ya intentó el contacto desde que
      -- recibió el lead (`tenencia_desde`, que se renueva al reasignar y al
      -- reabrir). Lo que gestionó un titular anterior no cuenta, ni un resultado
      -- de llamada deshecho (`deshecho_en`: no ocurrió); sin titular o sin
      -- tenencia no hay gestión. Acota la MISMA base; el payload no cambia.
      and (p_gestion is null or (l.vendedor_id is not null
        and l.tenencia_desde is not null
        and exists (select 1 from crm.actividades g
          where g.lead_id = l.id
            and g.tipo in ('llamada_realizada','llamada_no_contestada',
              'whatsapp_enviado','whatsapp_recibido','reunion_realizada')
            and g.creado_en >= l.tenencia_desde
            and not (g.metadata ? 'deshecho_en'))) = (p_gestion = 'con_gestion'))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where reasignado) as reasignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,'procedencia',p_procedencia,
    'reasignados',coalesce(p_reasignados,false),
    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
  into v_salida;
  return v_salida;
end;
$$;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) is
  'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista) y gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto; no cambia la forma de la respuesta). Sistema/Manual conserva el alta. Filas, totales y embudo desde la misma base, bajo RLS.';

-- La declaración analítica se MUEVE a la firma nueva (misma fila: conserva clase, tipo y
-- fecha), con la huella del cuerpo nuevo, y la lista se resella.
update private.analitica_leads_citas_exenciones e set
  objeto = p.oid::regprocedure::text,
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia, reasignacion entre analistas y gestion del titular actual. No calcula conversion mensual.'
from pg_proc p
where p.oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure
  and e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_gestion_preflight;
  -- 1. Una sola firma, la de 13, con el cuerpo ENSAYADO (md5 medido en el banco con
  --    search_path vacío) y el mismo contrato de seguridad que la que sustituye.
  if (
    to_regprocedure(f12) is null
    and to_regprocedure(f13) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f13))) = 'bf06666fb8ef533a39a50c7d70420153'
    and not has_function_privilege('anon', f13, 'EXECUTE')
    and not has_function_privilege('service_role', f13, 'EXECUTE')
    and has_function_privilege('authenticated', f13, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f13)) p) = pre.contrato
  ) is not true then
    raise exception 'POSTFLIGHT: firma, cuerpo, permisos o contrato invalido';
  end if;
  -- 2. El sello quedó vigente, la firma nueva está declarada con su huella y nada ajeno se
  --    movió: mismo censo, mismo conjunto en rojo (si lo había), mismas declaraciones ajenas,
  --    la propia conserva clase, tipo y fecha, y el consumidor `resumen_cartera_fn` intacto.
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f13_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f13_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f13_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
  ) is not true then
    raise exception 'POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  perform private.assert_actividades_de_lead_base();
  -- 3. La fuente de gestiones sigue siendo la auditada al terminar (misma condición que la
  --    guarda 5 del preflight: nadie la movió mientras se instalaba).
  if (
    (select count(*) from pg_trigger t
      where t.tgrelid = 'crm.actividades'::regclass and not t.tgisinternal and t.tgenabled = 'O'
        and (t.tgname::text, md5(pg_get_triggerdef(t.oid)), md5(pg_get_functiondef(t.tgfoid))) in (
          ('trg_01_gestion_lead_serializada', 'a7d2d742991f2ac9fbf3d52343a25532', '7af0e66b8a4849566e43b514245e1b86'),
          ('trg_00_actividades_resultado_solo_nucleo', '24037d111fc11c9b5fd3c9677e329bdf', '19952736370f64026f747c19b54ab38e'))) = 2
    and (select bool_and(c.relrowsecurity) from pg_class c
          where c.oid in ('crm.actividades'::regclass, 'crm.leads'::regclass))
    and (select count(*) from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a') = 1
    and exists (select 1 from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a'
            and p.polname = 'actividades_insert' and p.polpermissive
            and p.polroles = array['authenticated'::regrole::oid]
            and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = 'b2d6792bc6913861ca74f4398e6a12ab')
    and not exists (select 1 from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass
            and ((p.polcmd = '*' and p.polpermissive) or p.polcmd in ('w', 'd')))
    and (select count(*) from pg_policy p
          where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
            and not p.polpermissive) = 2
    and (select count(*) from pg_policy p
          where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
            and not p.polpermissive and p.polname = 'crm_actor_activo_gate' and p.polcmd = '*'
            and p.polroles = array['authenticated'::regrole::oid]
            and md5(pg_get_expr(p.polqual, p.polrelid)) = 'c5e6c90632bc616212336e1d089a68b3'
            and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = 'c5e6c90632bc616212336e1d089a68b3') = 2
    and not has_any_column_privilege('authenticated', 'crm.actividades', 'UPDATE')
    and not has_table_privilege('authenticated', 'crm.actividades', 'DELETE')
    and not has_any_column_privilege('anon', 'crm.actividades', 'UPDATE')
    and not has_table_privilege('anon', 'crm.actividades', 'DELETE')
  ) is not true then
    raise exception 'POSTFLIGHT: la fuente de gestiones (crm.actividades) cambio durante la instalacion';
  end if;
  raise notice 'cartera_filtro_gestion OK: firma unica de 13 argumentos, contrato de seguridad intacto, declaracion analitica movida y sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$migracion_20261001154153$])) then
    raise exception 'REGISTRO: la versión 20261001154153 ya está registrada con otro nombre u otro contenido; investigar antes de tocar';
  end if;
end;
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261001154153', 'crm_cartera_filtro_gestion', array[$migracion_20261001154153$-- Pipeline · columna «Gestionado»: filtro opcional `p_gestion` en `crm.cartera_filtrada_fn`
-- (pedido de los analistas; regla de negocio decidida por Miguel el 01/10/2026).
--
-- QUÉ. La función gana UN argumento al final, `p_gestion text default null`:
--   · null          → no recorta: la respuesta es idéntica a la de hoy;
--   · 'con_gestion' → leads cuyo titular ACTUAL ya intentó el contacto desde que los recibió
--                     (un resultado de llamada deshecho no cuenta);
--   · 'sin_gestion' → todos los demás (sin titular o sin `tenencia_desde` ⇒ sin gestión).
--   Cualquier otro valor → 22023, por el mismo bloque de validación que origen y procedencia.
--
-- POR QUÉ. El Pipeline separa, dentro de `etapa = 'nuevo'`, lo que ya se intentó contactar
-- (llamada sin respuesta, WhatsApp enviado) de lo que nadie ha tocado. NO nace una etapa
-- guardada: la columna se calcula. Regla de Miguel: un lead REASIGNADO que el analista anterior
-- ya intentó es «Nuevo» para el actual; solo cuenta lo gestionado desde `crm.leads.tenencia_desde`
-- (lo sella el trigger `trg_leads_zzz_tenencia_desde`; se renueva al reasignar y al reabrir).
-- Gestión = los 5 tipos de contacto de `actividades_contacto_episodio_idx`; una nota no cuenta.
-- Tampoco cuenta un resultado de llamada DESHECHO (`metadata.deshecho_en`): como en los núcleos
-- de Gestión Diaria, lo deshecho «no ocurrió» y el lead vuelve a «Nuevo» (decisión del 01/10).
--
-- QUÉ NO CAMBIA. La FORMA del payload (ni claves arriba ni campos por fila: hay navegadores con
-- el bundle viejo leyéndolo; el filtro no lleva eco), INVOKER bajo la RLS de leads y actividades,
-- `stable`, `search_path` vacío, dueño y ACL (solo `authenticated` ejecuta). Recorta la MISMA
-- base que los demás filtros: filas, totales, capital y embudo salen juntos. Una sola firma: se
-- retira la de 12 argumentos (dos candidatas romperían PostgREST) y su exención analítica se
-- MUEVE a la de 13 (misma clase y fecha de declaración) y se resella.
--
-- ORDEN DE PUBLICACIÓN: servidor primero, pantalla después. El frente nuevo envía `p_gestion`
-- y sin esta migración recibiría PGRST202; el frente viejo no lo envía y sigue igual.
--
-- REVERSA: `supabase/scripts/cartera-gestion/reversa.sql`, tras retirar el frente que envía
-- `p_gestion`. Quita la firma de 13, reinstala la de 12 byte a byte (md5 7169d942…), devuelve la
-- exención analítica a su firma y resella. No toca datos.
--
-- ANCLAS. La regla descansa en dos relojes que sella el servidor: el del LEAD (`tenencia_desde`,
-- guarda 4) y el de la ACTIVIDAD (`creado_en` re-sellado y `deshecho_en` reservado, guarda 5, que
-- además fija la policy de INSERT, las restrictivas de las dos tablas y que la API no pueda
-- reescribir ni borrar actividades). Todas se midieron con `search_path` vacío, que se fija abajo
-- para la transacción: el texto de `pg_get_functiondef`, `pg_get_triggerdef` y `pg_get_expr`
-- cambia con el `search_path` de la sesión, y así el resultado no depende de quién aplique.
-- Kit, ensayo y consulta de solo lectura para acreditarlas contra producción:
-- `supabase/scripts/cartera-gestion/`.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f12_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
begin
  -- 1. La función viva es la auditada: una sola firma (la de 12) y su cuerpo exacto.
  --    Guardas en positivo con `is not true`: un NULL también rechaza.
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f12) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f12))) = '7169d94239dcb191bafa3faed46f916f'
  ) is not true then
    raise exception 'PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada';
  end if;
  -- 2. Su declaración analítica está vigente (huella al día), es de inventario y la lista está
  --    sellada: esta migración la mueve y resella; no se resella a ciegas una lista alterada.
  if (
    exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = f12_larga and c.declarada and c.huella_ok)
    and (select e.clase from private.analitica_leads_citas_exenciones e
          where e.objeto = f12_larga) = 'operativo'
    and (select s.sello from private.analitica_lc_sello s where s.id)
          = private.huella_exenciones_analitica_lc()
  ) is not true then
    raise exception 'PREFLIGHT: la declaracion analitica no esta vigente y sellada';
  end if;
  -- 3. El filtro lee `crm.actividades` como INVOKER: su RLS debe seguir siendo coextensiva con
  --    la de leads (si no, un lead visible con actividades ocultas saldría «sin gestión»).
  perform private.assert_actividades_de_lead_base();
  -- 4. El reloj de la regla. «Solo cuenta lo gestionado desde que el titular ACTUAL recibió el
  --    lead» descansa en que `tenencia_desde` lo sella el servidor y se renueva al reasignar.
  --    Si el trigger falta, está apagado o cambió de cuerpo, el filtro mentiría en silencio.
  if (
    (select count(*) from pg_trigger t
      where t.tgrelid = 'crm.leads'::regclass
        and t.tgname = 'trg_leads_zzz_tenencia_desde'
        and not t.tgisinternal and t.tgenabled = 'O'
        and md5(pg_get_triggerdef(t.oid)) = 'f5849e264eb05e8a253dbd78c2362fba'
        and md5(pg_get_functiondef(t.tgfoid)) = '900508fa3ccf3eec2e738ccdeebad7be') = 1
  ) is not true then
    raise exception 'PREFLIGHT: el sello de tenencia_desde no coincide con la version auditada';
  end if;
  -- 5. El reloj y la integridad de la ACTIVIDAD. La regla compara `creado_en` con la tenencia y
  --    descarta lo deshecho, y eso solo es infalsificable mientras:
  --    (a) el servidor selle `creado_en` y revalide el ámbito (trg_01) y reserve los resultados
  --        de llamada y `deshecho_en` (trg_00);
  --    (b) haya RLS y la única vía de escritura de la API sea la policy de INSERT auditada, sin
  --        permisivas ALL ni policies de UPDATE/DELETE;
  --    (c) las RESTRICTIVAS de las dos tablas sean exactamente el gate del actor activo: una
  --        restrictiva de lectura añadida daría a titular y supervisor veredictos distintos
  --        sobre el mismo lead, y `assert_actividades_de_lead_base` solo mira que el gate esté;
  --    (d) ni `authenticated` ni `anon` puedan reescribir o borrar una actividad.
  if (
    (select count(*) from pg_trigger t
      where t.tgrelid = 'crm.actividades'::regclass and not t.tgisinternal and t.tgenabled = 'O'
        and (t.tgname::text, md5(pg_get_triggerdef(t.oid)), md5(pg_get_functiondef(t.tgfoid))) in (
          ('trg_01_gestion_lead_serializada', 'a7d2d742991f2ac9fbf3d52343a25532', '7af0e66b8a4849566e43b514245e1b86'),
          ('trg_00_actividades_resultado_solo_nucleo', '24037d111fc11c9b5fd3c9677e329bdf', '19952736370f64026f747c19b54ab38e'))) = 2
    and (select bool_and(c.relrowsecurity) from pg_class c
          where c.oid in ('crm.actividades'::regclass, 'crm.leads'::regclass))
    and (select count(*) from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a') = 1
    and exists (select 1 from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a'
            and p.polname = 'actividades_insert' and p.polpermissive
            and p.polroles = array['authenticated'::regrole::oid]
            and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = 'b2d6792bc6913861ca74f4398e6a12ab')
    and not exists (select 1 from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass
            and ((p.polcmd = '*' and p.polpermissive) or p.polcmd in ('w', 'd')))
    and (select count(*) from pg_policy p
          where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
            and not p.polpermissive) = 2
    and (select count(*) from pg_policy p
          where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
            and not p.polpermissive and p.polname = 'crm_actor_activo_gate' and p.polcmd = '*'
            and p.polroles = array['authenticated'::regrole::oid]
            and md5(pg_get_expr(p.polqual, p.polrelid)) = 'c5e6c90632bc616212336e1d089a68b3'
            and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = 'c5e6c90632bc616212336e1d089a68b3') = 2
    and not has_any_column_privilege('authenticated', 'crm.actividades', 'UPDATE')
    and not has_table_privilege('authenticated', 'crm.actividades', 'DELETE')
    and not has_any_column_privilege('anon', 'crm.actividades', 'UPDATE')
    and not has_table_privilege('anon', 'crm.actividades', 'DELETE')
  ) is not true then
    raise exception 'PREFLIGHT: la fuente de gestiones (crm.actividades) no coincide con la version auditada';
  end if;
end;
$preflight$;

-- Foto de lo que NO debe cambiar: contrato de seguridad de la función, censo analítico,
-- declaraciones ajenas, la propia declaración (clase, tipo y fecha) y el consumidor.
create temporary table cartera_gestion_preflight on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean);

create function crm.cartera_filtrada_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null,
  p_desde date default null,
  p_hasta date default null,
  p_origen text default null,
  p_procedencia text default null,
  p_reasignados boolean default false,
  p_gestion text default null
)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     -- Mismo dominio que el CHECK de crm.leads.origen: los 5 vigentes y los 3
     -- históricos (web, campania, whatsapp) siguen siendo consultables.
     or (p_origen is not null and p_origen not in
       ('referido','landing','formulario','oficina','otro','web','campania','whatsapp'))
     -- Procedencia: 'sistema' (puente automático) o 'manual' (una persona).
     -- Otro valor se rechaza: nunca un «cero resultados» silencioso.
     or (p_procedencia is not null and p_procedencia not in ('sistema','manual'))
     -- Gestión: 'con_gestion' (el titular actual ya intentó el contacto) o
     -- 'sin_gestion' (el resto). Otro valor se rechaza, igual que arriba.
     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), base as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
    from crm.leads l
    -- Una primera entrega desde la cola tiene vendedor_anterior NULL. Solo
    -- cuenta un analista ANTERIOR, incluso si volvió al mismo titular tras
    -- pasar por la bandeja. El evento lo emite el trigger del servidor.
    left join lateral (
      select true as reasignado
      from crm.actividades a
      where l.vendedor_id is not null
        and a.lead_id = l.id
        and a.tipo = 'reasignacion'
        and a.metadata ->> 'vendedor_anterior' is not null
      limit 1
    ) mov on true
    left join recepciones r on r.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      -- El origen acota la MISMA base: filas, totales, capital y embudo juntos.
      and (p_origen is null or l.origen = p_origen)
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      -- Gestión vigente: el titular ACTUAL ya intentó el contacto desde que
      -- recibió el lead (`tenencia_desde`, que se renueva al reasignar y al
      -- reabrir). Lo que gestionó un titular anterior no cuenta, ni un resultado
      -- de llamada deshecho (`deshecho_en`: no ocurrió); sin titular o sin
      -- tenencia no hay gestión. Acota la MISMA base; el payload no cambia.
      and (p_gestion is null or (l.vendedor_id is not null
        and l.tenencia_desde is not null
        and exists (select 1 from crm.actividades g
          where g.lead_id = l.id
            and g.tipo in ('llamada_realizada','llamada_no_contestada',
              'whatsapp_enviado','whatsapp_recibido','reunion_realizada')
            and g.creado_en >= l.tenencia_desde
            and not (g.metadata ? 'deshecho_en'))) = (p_gestion = 'con_gestion'))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where reasignado) as reasignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,'procedencia',p_procedencia,
    'reasignados',coalesce(p_reasignados,false),
    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
  into v_salida;
  return v_salida;
end;
$$;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) is
  'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista) y gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto; no cambia la forma de la respuesta). Sistema/Manual conserva el alta. Filas, totales y embudo desde la misma base, bajo RLS.';

-- La declaración analítica se MUEVE a la firma nueva (misma fila: conserva clase, tipo y
-- fecha), con la huella del cuerpo nuevo, y la lista se resella.
update private.analitica_leads_citas_exenciones e set
  objeto = p.oid::regprocedure::text,
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia, reasignacion entre analistas y gestion del titular actual. No calcula conversion mensual.'
from pg_proc p
where p.oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure
  and e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_gestion_preflight;
  -- 1. Una sola firma, la de 13, con el cuerpo ENSAYADO (md5 medido en el banco con
  --    search_path vacío) y el mismo contrato de seguridad que la que sustituye.
  if (
    to_regprocedure(f12) is null
    and to_regprocedure(f13) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f13))) = 'bf06666fb8ef533a39a50c7d70420153'
    and not has_function_privilege('anon', f13, 'EXECUTE')
    and not has_function_privilege('service_role', f13, 'EXECUTE')
    and has_function_privilege('authenticated', f13, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f13)) p) = pre.contrato
  ) is not true then
    raise exception 'POSTFLIGHT: firma, cuerpo, permisos o contrato invalido';
  end if;
  -- 2. El sello quedó vigente, la firma nueva está declarada con su huella y nada ajeno se
  --    movió: mismo censo, mismo conjunto en rojo (si lo había), mismas declaraciones ajenas,
  --    la propia conserva clase, tipo y fecha, y el consumidor `resumen_cartera_fn` intacto.
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f13_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f13_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f13_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
  ) is not true then
    raise exception 'POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  perform private.assert_actividades_de_lead_base();
  -- 3. La fuente de gestiones sigue siendo la auditada al terminar (misma condición que la
  --    guarda 5 del preflight: nadie la movió mientras se instalaba).
  if (
    (select count(*) from pg_trigger t
      where t.tgrelid = 'crm.actividades'::regclass and not t.tgisinternal and t.tgenabled = 'O'
        and (t.tgname::text, md5(pg_get_triggerdef(t.oid)), md5(pg_get_functiondef(t.tgfoid))) in (
          ('trg_01_gestion_lead_serializada', 'a7d2d742991f2ac9fbf3d52343a25532', '7af0e66b8a4849566e43b514245e1b86'),
          ('trg_00_actividades_resultado_solo_nucleo', '24037d111fc11c9b5fd3c9677e329bdf', '19952736370f64026f747c19b54ab38e'))) = 2
    and (select bool_and(c.relrowsecurity) from pg_class c
          where c.oid in ('crm.actividades'::regclass, 'crm.leads'::regclass))
    and (select count(*) from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a') = 1
    and exists (select 1 from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a'
            and p.polname = 'actividades_insert' and p.polpermissive
            and p.polroles = array['authenticated'::regrole::oid]
            and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = 'b2d6792bc6913861ca74f4398e6a12ab')
    and not exists (select 1 from pg_policy p
          where p.polrelid = 'crm.actividades'::regclass
            and ((p.polcmd = '*' and p.polpermissive) or p.polcmd in ('w', 'd')))
    and (select count(*) from pg_policy p
          where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
            and not p.polpermissive) = 2
    and (select count(*) from pg_policy p
          where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
            and not p.polpermissive and p.polname = 'crm_actor_activo_gate' and p.polcmd = '*'
            and p.polroles = array['authenticated'::regrole::oid]
            and md5(pg_get_expr(p.polqual, p.polrelid)) = 'c5e6c90632bc616212336e1d089a68b3'
            and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = 'c5e6c90632bc616212336e1d089a68b3') = 2
    and not has_any_column_privilege('authenticated', 'crm.actividades', 'UPDATE')
    and not has_table_privilege('authenticated', 'crm.actividades', 'DELETE')
    and not has_any_column_privilege('anon', 'crm.actividades', 'UPDATE')
    and not has_table_privilege('anon', 'crm.actividades', 'DELETE')
  ) is not true then
    raise exception 'POSTFLIGHT: la fuente de gestiones (crm.actividades) cambio durante la instalacion';
  end if;
  raise notice 'cartera_filtro_gestion OK: firma unica de 13 argumentos, contrato de seguridad intacto, declaracion analitica movida y sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$migracion_20261001154153$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261001154153' and name = 'crm_cartera_filtro_gestion' and cardinality(statements) = 1
                   and md5(statements[1]) = '9236dd635b1dfadcff76d1cd2492df32') then
    raise exception 'REGISTRO: la fila 20261001154153 / crm_cartera_filtro_gestion no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261001154153 / crm_cartera_filtro_gestion (1 sentencia: el archivo entero)';
end;
$post$;
commit;

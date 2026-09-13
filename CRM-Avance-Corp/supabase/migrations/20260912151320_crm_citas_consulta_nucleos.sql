-- Citas Gerencia: detalle operativo conectado a citas_episodios y
-- conversion_episodios. Conserva el contrato V2 y la conversión a cliente.
-- CANDIDATA: validación local; requiere branch, gate RLS y autorización antes
-- de producción. No activa las nuevas metas ni la proyección aún en borrador.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

select pg_advisory_xact_lock(hashtext('crm.citas_gerencia_consulta_nucleos'),1);
lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello, private.analitica_leads_citas_tope in share row exclusive mode;

do $preflight$
declare f record;
begin
  if to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])') is not null
    or to_regprocedure('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])') is not null then
    raise exception 'Citas: existen las firmas nuevas; revisar su procedencia antes de aplicar';
  end if;
  for f in select * from (values
    ('private.citas_gerencia_consulta(date,date)','2d39c2bfc0c7d30b9aaa42b2bcd1669f'),
    ('crm.citas_gerencia_consulta_fn(date,date)','e108a2374653d94056c31bc1b35b0bf7'),
    ('private.rol_crm(uuid)','99827f3fe2fbc3cfae5668c30015c758'),
    ('private.citas_episodios(timestamp with time zone,timestamp with time zone,timestamp with time zone)','ea636888a266941e959f26c6a5727216'),
    ('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)','8a2549dbfa59c732da04900ed90b6361'),
    ('private.cierre_anulado(uuid)','8427218ba089192bd9702e052492f70b'),
    ('private.cierre_externo_anulado(uuid)','25764138a845f5f72e1eeb1d4fdd8ff5'),
    ('private.contadores_crudos_leads_citas()','34e0ae16a95912e5a5eedd4da845e288'),
    ('private.assert_analitica_leads_citas()','0b474e7f58e1f668b62a02730b716457'),
    ('private.huella_exenciones_analitica_lc()','817926e696fa554d8485e8e1aa6e9b73')
  ) as esperadas(objeto,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(f.objeto))) is distinct from f.huella then
      raise exception 'Citas: cambió %; revisar la candidata antes de aplicarla',f.objeto;
    end if;
  end loop;
  for f in select * from (values
    ('private.citas_gerencia_consulta(date,date)','{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.citas_gerencia_consulta_fn(date,date)','{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.citas_episodios(timestamp with time zone,timestamp with time zone,timestamp with time zone)','{postgres=X/postgres}'),
    ('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)','{postgres=X/postgres}')
  ) as esperadas(objeto,permisos) loop
    if (select proacl from pg_proc where oid=to_regprocedure(f.objeto))
      is distinct from f.permisos::aclitem[] then
      raise exception 'Citas: ACL inesperado en %; revisar antes de aplicar',f.objeto;
    end if;
  end loop;
  if (select sello from private.analitica_lc_sello where id)
    is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'Citas: el registro de excepciones ya tenía un sello inválido';
  end if;
end
$preflight$;

create temporary table citas_nucleos_preflight on commit drop as
select
  (select to_jsonb(p.proacl) from pg_proc p where p.oid='private.citas_gerencia_consulta(date,date)'::regprocedure) as permisos,
  (select to_jsonb(t) from private.analitica_leads_citas_tope t where id) as tope,
  (select coalesce(jsonb_agg(to_jsonb(e) order by e.objeto),'[]'::jsonb)
    from private.analitica_leads_citas_exenciones e
    where e.objeto<>'private.citas_gerencia_consulta(date,date)') as otras_exenciones,
  (select coalesce(jsonb_agg(to_jsonb(c) order by c.objeto),'[]'::jsonb)
    from private.contadores_crudos_leads_citas() c
    where c.objeto<>'private.citas_gerencia_consulta(date,date)') as otros_contadores,
  (select count(*) from private.contadores_crudos_leads_citas()) as contadores;
-- Extracción de hechos dentro de los mismos núcleos. Una sola definición de
-- estados y una sola de cierres; las firmas anteriores conservan su contrato.
-- NULL = ámbito completo; [] = ningún lead. La selección por IDs ocurre antes
-- de materializar filas y antes de calcular pesos/cierres ajenos a la cohorte.
CREATE OR REPLACE FUNCTION private.citas_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_ahora timestamp with time zone, p_leads uuid[])
 RETURNS TABLE(tarea_id uuid, lead_id uuid, vendedor_id uuid, cancelada_por_id uuid, vence_en timestamp with time zone, estado text, modalidad text, resultado text, debio_ocurrir boolean, realizada boolean, no_show boolean, cancelada_asesor boolean, cancelada_sistema boolean, reprogramada boolean, pendiente_cierre boolean, programada_futura boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select t.id,
         t.lead_id,
         t.vendedor_id,
         t.cancelada_por_id,
         t.vence_en,
         t.estado,
         coalesce(t.modalidad_reunion, 'sin_clasificar'),
         coalesce(t.resultado_reunion, 'sin_clasificar'),
         t.vence_en <= p_ahora,
         t.estado = 'completada',
         t.estado = 'no_show',
         (t.estado = 'cancelada' and t.cancelada_por = 'asesor'),
         (t.estado = 'cancelada' and t.cancelada_por is distinct from 'asesor'),
         t.estado = 'reprogramada',
         (t.estado = 'pendiente' and t.vence_en <= p_ahora),
         (t.estado = 'pendiente' and t.vence_en > p_ahora)
  from crm.tareas t
  where t.tipo = 'reunion'
    and t.activo
    and t.vence_en >= p_ini
    and t.vence_en < p_fin
    and (p_leads is null or t.lead_id in (select id from unnest(p_leads) seleccion(id)));
$function$
;
revoke all on function private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])
  from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.citas_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_ahora timestamp with time zone DEFAULT now())
 RETURNS TABLE(tarea_id uuid, lead_id uuid, vendedor_id uuid, cancelada_por_id uuid, vence_en timestamp with time zone, estado text, modalidad text, resultado text, debio_ocurrir boolean, realizada boolean, no_show boolean, cancelada_asesor boolean, cancelada_sistema boolean, reprogramada boolean, pendiente_cierre boolean, programada_futura boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select * from private.citas_episodios(p_ini,p_fin,p_ahora,null::uuid[]);
$function$
;
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
  and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
  and coalesce(la.resultado_en, la.finalizado_en) < p_fin
  and (p_global or la.analista_id = any(p_visibles))
  and (p_leads is null or la.lead_id in (select id from unnest(p_leads) seleccion(id)));
$function$
;
revoke all on function private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])
  from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
-- Una llegada por id, por su alta ORIGINAL en Lima. No depende del estado
-- actual ni de cuántas veces se asigne, descarte, rescate o cambie de dueño.
-- La primera asignación se busca en toda la historia ANTES de aplicar ámbito.
-- Sin asignación aún: cuenta en empresa, nunca se inventa un responsable.
select 'recibido'::text, primera.analista_id, l.id, null::uuid,
  l.origen = 'referido', coalesce(primera.aproximado, false),
  'llegada'::text, false, l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, l.creado_en, null::timestamptz,
  case when l.origen in ('landing', 'formulario') and not l.alta_manual
    then 1 else 0 end, 0::numeric
from crm.leads l
left join lateral (
  select la.analista_id, la.aproximado
  from crm.lead_asignaciones la
  where la.lead_id = l.id
  order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
  limit 1
) primera on true
where l.creado_en >= p_ini and l.creado_en < p_fin
  and l.origen in ('landing', 'formulario', 'referido')
  and (p_global or primera.analista_id = any(p_visibles))

union all

-- El índice único del ledger garantiza un cierre por lead. El cierre queda
-- en quien lo consiguió, no en quien recibió la llegada. Los otros canales
-- siguen disponibles para consumidores operativos/capital, con aporte CERO.
select * from private.conversion_cierres(
  p_ini,p_fin,p_periodo,p_global,p_visibles,p_factor,null::uuid[])

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Renovación usa el mismo peso que Referido; Upgrade conserva 1.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
select 'operacion'::text,
  coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.tipo, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.tipo = 'renovacion' then
    case when p_periodo is not null then p_factor
      else private.peso_referido_conversion(o.periodo) end
    when o.tipo = 'upgrade' then 1 else 0 end
from (
  select o0.*, row_number() over (
    partition by o0.cliente_id, o0.periodo
    order by o0.fecha_operacion, o0.creado_en, o0.id
  ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.elegible_conversion
    and o0.periodo >= date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o0.periodo <= date_trunc('month', p_fin at time zone 'America/Lima')::date
) o
where o.orden_conversion = 1
  and o.fecha_operacion::timestamp at time zone 'America/Lima' >= p_ini
  and o.fecha_operacion::timestamp at time zone 'America/Lima' < p_fin
  and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),
                           o.vendedor_id) = any(p_visibles));
end;
$function$
;

CREATE OR REPLACE FUNCTION private.citas_gerencia_consulta(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_ahora timestamptz := now();
  v_ini timestamptz;
  v_fin timestamptz;
  v_filas jsonb;
  v_clientes integer;
  v_conversiones jsonb;
begin
  -- Esta puerta entrega identidades; directorio conserva su agregador sin PII.
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia'
  then raise exception 'No autorizado' using errcode='42501'; end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
    or p_desde <> date_trunc('month',p_desde)::date
    or p_hasta <> (date_trunc('month',p_desde)+interval '1 month - 1 day')::date
    or p_desde < date '2000-01-01'
    or p_desde > ((v_ahora at time zone 'America/Lima')::date + interval '1 year')::date
  then raise exception 'Seleccione un mes válido' using errcode='22023'; end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta+1)::timestamp at time zone 'America/Lima';

  with cohorte as materialized (
    select distinct e.lead_id
    from private.citas_episodios(v_ini,v_fin,v_ahora) e
    join crm.tareas t on t.id=e.tarea_id
    join crm.leads l on l.id=e.lead_id
    where l.activo and t.creado_en<=v_ahora
  ), limites_historial as (
    -- Sólo acota la lectura del núcleo; no clasifica ni cuenta estas tareas.
    select min(t.vence_en) as inicio, max(t.vence_en)+interval '1 microsecond' as fin
    from crm.tareas t join cohorte c on c.lead_id=t.lead_id
    where t.tipo='reunion' and t.activo and t.creado_en<=v_ahora
  ), historial as materialized (
    select t.*, l.nombre_completo, l.telefono, l.origen, l.moneda, l.monto_estimado,
      e.modalidad as modalidad_canonica, e.resultado as resultado_canonico,
      case when e.pendiente_cierre then 'vencida'
        when e.programada_futura then 'programada'
        when e.realizada then 'realizada'
        when e.no_show then 'no_show'
        when e.reprogramada then 'reprogramada'
        when e.cancelada_asesor then 'cancelada'
        when e.cancelada_sistema then 'sistema'
      end as estado_comercial
    from limites_historial b
    cross join lateral private.citas_episodios(
      coalesce(b.inicio,v_ini),coalesce(b.fin,v_fin),v_ahora,
      coalesce((select array_agg(c.lead_id) from cohorte c),'{}'::uuid[])) e
    join cohorte c on c.lead_id=e.lead_id
    join crm.tareas t on t.id=e.tarea_id
    join crm.leads l on l.id=e.lead_id
    where t.creado_en<=v_ahora
    -- La fila extra dispara un error; nunca se entrega un historial truncado.
    order by t.vence_en,t.id limit 10001
  ), cierres as materialized (
    -- Los hechos de cierre proceden del núcleo. Ningún aporte ponderado
    -- participa en este indicador operativo. El factor no modifica el hecho.
    -- Basta desde la primera cita: sólo se pregunta por cierres posteriores.
    select e.lead_id,max(e.fecha_numerador) as ultimo_cierre
    from private.conversion_cierres(
      coalesce((select min(h.vence_en) from historial h),v_ini),
      v_ahora+interval '1 microsecond',p_desde,true,'{}'::uuid[],1,
      coalesce((select array_agg(c.lead_id) from cohorte c),'{}'::uuid[])) e
    join cohorte c on c.lead_id=e.lead_id
    where e.tipo='cierre' and not e.anulado and e.fecha_numerador<=v_ahora
    group by e.lead_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'lead_id',t.lead_id,'nombre',t.nombre_completo,'telefono',t.telefono,
    'analista_id',t.vendedor_id,'analista_nombre',coalesce(p.nombre_completo,'Sin analista'),
    'supervisor_id',coalesce(e.supervisor_id,t.asignado_supervisor_id),
    'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
    'vence_en',t.vence_en,'estado',t.estado,'estado_comercial',t.estado_comercial,'cancelada_por',t.cancelada_por,
    'modalidad',t.modalidad_canonica,'origen',t.origen,
    'moneda',t.moneda,'monto_estimado',t.monto_estimado,
    'resultado',t.resultado_canonico,
    'nota',coalesce(t.detalle_cierre_reunion,t.nota,''),
    'reagendada_de',anterior.id,
    'creado_en',t.creado_en,
    'asistencia_registrada_en',case when t.estado='completada' then a.creado_en end,
    'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false)
  ) order by t.vence_en,t.id),'[]'::jsonb) into v_filas
  from historial t
  left join historial anterior on anterior.id=t.reagendada_de and anterior.lead_id=t.lead_id
  left join cierres c on c.lead_id=t.lead_id
  left join public.perfiles p on p.id=t.vendedor_id
  left join crm.equipo e on e.perfil_id=t.vendedor_id
  left join public.perfiles ps on ps.id=coalesce(e.supervisor_id,t.asignado_supervisor_id)
  left join crm.actividades a on a.id=t.resultado_actividad_id and a.lead_id=t.lead_id
    and a.tipo='reunion_realizada' and a.creado_en<=v_ahora;

  -- Nunca devolver un subconjunto como si fuera la totalidad de la consulta.
  if jsonb_array_length(v_filas)>10000 then
    raise exception 'La consulta supera el tamaño admitido; requiere paginación de servidor'
      using errcode='54000';
  end if;
  if exists(select 1 from jsonb_array_elements(v_filas) c where c->>'estado_comercial' is null) then
    raise exception 'Estado de reunión sin clasificación canónica: %',
      (select c->>'estado' from jsonb_array_elements(v_filas) c where c->>'estado_comercial' is null limit 1)
      using errcode='22023';
  end if;
  select count(*) into v_clientes
    from private.citas_episodios(v_ini,v_fin,v_ahora) e
    join crm.tareas t on t.id=e.tarea_id
    where t.perfil_id is not null and t.creado_en<=v_ahora;
  -- Un evento por lead, con cliente vinculado y conversión vigente al corte.
  -- El estado convertido también existe en cierres externos sin cliente del
  -- portal: esos registros no se equiparan automáticamente a esta regla.
  select coalesce(jsonb_agg(jsonb_build_object(
    'lead_id',l.id,'perfil_id',l.perfil_id,'convertido_en',l.convertido_en
  ) order by l.convertido_en,l.id),'[]'::jsonb) into v_conversiones
  from crm.leads l join public.perfiles pc on pc.id=l.perfil_id and pc.rol='cliente'
  where l.id in (select (c->>'lead_id')::uuid from jsonb_array_elements(v_filas) c)
    and l.activo and l.etapa='convertido' and l.perfil_id is not null
    and l.convertido_en is not null and l.convertido_en<=v_ahora
    and not private.cierre_anulado(l.id);
  -- Inactivar el acceso del cliente no anula su conversión. La anulación de
  -- negocio se decide exclusivamente con el helper canónico anterior.
  return jsonb_build_object('version',2,'periodo',jsonb_build_object('desde',p_desde,'hasta',p_hasta),
    'generado_en',v_ahora,'citas',v_filas,'conversiones',v_conversiones,
    'disponibilidad_depositos','conversion_cliente','citas_clientes',v_clientes);
end;
$function$
;
-- Consumidor mixto declarado: el censo también detecta sus joins de atributos.
-- La conversión a cliente es la regla ya aprobada para este módulo; no exige
-- un asiento de capital ni usa el índice ponderado como número de personas.
insert into private.analitica_leads_citas_exenciones(objeto,tipo,huella,razon)
select 'private.citas_gerencia_consulta(date,date)','funcion',
  md5(regexp_replace(regexp_replace(lower(p.prosrc),
    '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  'Detalle operativo de Gerencia: citas y estados desde citas_episodios; cierres desde conversion_cierres, compartido por conversion_episodios, sin ponderar. Joins crudos sólo para identidad, historial y evidencia de conversión vigente a perfil cliente; no calcula capital ni metas.'
from pg_proc p where p.oid='private.citas_gerencia_consulta(date,date)'::regprocedure
on conflict(objeto) do update set huella=excluded.huella, razon=excluded.razon;
update private.analitica_lc_sello
set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;

CREATE OR REPLACE FUNCTION private.assert_analitica_leads_citas()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_sin text; v_cad text; v_n integer; v_tope integer;
begin
  -- Las lecturas acotadas comparten los núcleos, pero tampoco son puertas API.
  if to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])') is null
    or to_regprocedure('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])') is null then
    raise exception 'Desapareció una lectura acotada de los núcleos de Citas/Conversión';
  end if;
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid in (
      'private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'::regprocedure,
      'private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'::regprocedure)
      and a.grantee<>'postgres'::regrole::oid
  ) then raise exception 'Una lectura acotada de Citas/Conversión tiene EXECUTE fuera de postgres'; end if;
  select string_agg(tipo || ' ' || objeto, ', ' order by objeto)
    into v_sin from private.contadores_crudos_leads_citas() where not declarada;
  if v_sin is not null then
    raise exception 'Contadores crudos de leads/citas SIN declarar: %. O beben del nucleo, o se declaran con su razon.', v_sin;
  end if;

  select string_agg(tipo || ' ' || objeto, ', ' order by objeto)
    into v_cad from private.contadores_crudos_leads_citas() where declarada and not huella_ok;
  if v_cad is not null then
    raise exception 'Contadores exentos cuyo cuerpo CAMBIO desde que se declararon (la razon caduco): %', v_cad;
  end if;

  select count(*) into v_n from private.contadores_crudos_leads_citas();
  -- Anti-vacuidad: el tope es techo, no suelo. Un censo que devuelve 0 filas es
  -- una regresion del propio censo, no un exito.
  if v_n = 0 then
    raise exception 'El censo devolvio 0 contadores: eso es una regresion del censo, no la meta';
  end if;
  select tope into v_tope from private.analitica_leads_citas_tope where id;
  if v_tope is null then raise exception 'No hay tope fijado'; end if;
  if v_n > v_tope then
    raise exception 'Los contadores crudos subieron de % a %: el trinquete solo deja bajar.', v_tope, v_n;
  end if;

  -- El sello de la lista: si alguien la relavo sin re-sellar, rojo.
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'La lista de exenciones cambio sin re-sellarse en una migracion';
  end if;

  -- Los candados del tope tienen que seguir puestos y ACTIVOS: sin esto, un
  -- despliegue privilegiado podria deshabilitar el trigger, subir el tope y
  -- dejar el gate verde.
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'private.analitica_leads_citas_tope'::regclass
         and t.tgname in ('trg_analitica_lc_tope_solo_baja','trg_analitica_lc_tope_no_truncar')
         and t.tgenabled in ('O','A')) <> 2 then
    raise exception 'Los candados del tope no estan puestos o no estan activos';
  end if;

  -- Los dos nucleos tienen que seguir vivos y con su forma.
  if to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)') is null then
    raise exception 'El nucleo de citas desaparecio';
  end if;
  if to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)') is null then
    raise exception 'El nucleo de leads desaparecio';
  end if;
  -- Y la pantalla de reuniones tiene que seguir bebiendo del de citas - mirado
  -- SIN comentarios (un `-- citas_episodios` de senuelo no vale).
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure
       and regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
           ~ '\mcitas_episodios\s*\('
  ) then
    raise exception 'La pantalla de reuniones dejo de beber del nucleo de citas';
  end if;

  -- El nucleo devuelve FILAS de toda la empresa (DEFINER): cada llamador tiene
  -- que estar DECLARADO en las exenciones (su declaracion es su puerta escrita).
  if exists (
    select 1 from pg_proc p
     where p.prokind in ('f','p')
       and p.oid <> coalesce(to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)'),0)
       and p.oid <> coalesce(to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'),0)
       and p.oid <> coalesce(to_regprocedure('private.assert_analitica_leads_citas()'),0)
       and p.oid <> coalesce(to_regprocedure('private.contadores_crudos_leads_citas()'),0)
       and regexp_replace(regexp_replace(coalesce(p.prosrc,''),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
           ~ '\m(citas_episodios|conversion_cierres)\s*\('
       and not exists (select 1 from private.analitica_leads_citas_exenciones e
                        where e.objeto = p.oid::regprocedure::text)
  ) then
    raise exception 'Hay un consumidor de citas_episodios o conversion_cierres SIN declarar: los nucleos sirven filas de toda la empresa y cada llamador declara su puerta';
  end if;

  -- El ACL del nucleo, exacto: solo postgres (el mismo patron que
  -- conversion_episodios y capital_episodios). Un grant posterior es rojo.
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = 'private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure
       and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'citas_episodios tiene EXECUTE para alguien mas que postgres';
  end if;

  return 'OK: ' || v_n || ' contadores declarados y con su huella intacta, tope ' || v_tope || ', 0 sin declarar';
end;
$function$

;

do $postflight$
begin
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid in (
      'private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure,
      'private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'::regprocedure,
      'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure,
      'private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'::regprocedure)
      and a.grantee<>'postgres'::regrole::oid
  ) then raise exception 'Citas: un núcleo tiene acceso directo fuera de postgres'; end if;
  if not exists(select 1 from private.contadores_crudos_leads_citas()
    where objeto='private.citas_gerencia_consulta(date,date)' and declarada and huella_ok) then
    raise exception 'Citas: consumidor sin declaración y huella vigentes';
  end if;
  if (select permisos from citas_nucleos_preflight) is distinct from
    (select to_jsonb(p.proacl) from pg_proc p where p.oid='private.citas_gerencia_consulta(date,date)'::regprocedure) then
    raise exception 'Citas: cambiaron permisos de la puerta privada';
  end if;
  if (select tope from citas_nucleos_preflight) is distinct from
    (select to_jsonb(t) from private.analitica_leads_citas_tope t where id)
    or (select otras_exenciones from citas_nucleos_preflight) is distinct from
    (select coalesce(jsonb_agg(to_jsonb(e) order by e.objeto),'[]'::jsonb)
      from private.analitica_leads_citas_exenciones e
      where e.objeto<>'private.citas_gerencia_consulta(date,date)')
    or (select otros_contadores from citas_nucleos_preflight) is distinct from
    (select coalesce(jsonb_agg(to_jsonb(c) order by c.objeto),'[]'::jsonb)
      from private.contadores_crudos_leads_citas() c
      where c.objeto<>'private.citas_gerencia_consulta(date,date)')
    or (select count(*) from private.contadores_crudos_leads_citas()) >
      (select contadores from citas_nucleos_preflight) then
    raise exception 'Citas: alteración fuera de alcance en el censo o las excepciones';
  end if;
  if (select sello from private.analitica_lc_sello where id)
    is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'Citas: sello final inválido';
  end if;
  -- El gate global se ejecuta y reporta por separado: esta migración no eleva
  -- su tope ni concede exenciones a los cuatro lectores ajenos detectados.
end
$postflight$;
commit;

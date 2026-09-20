-- Oráculo del día del analista (Gestión Diaria, Fase 3) sobre la copia del banco.
-- Corre como postgres; las escrituras van por las puertas de F2 con la identidad
-- del actor en request.jwt.claim.sub (como PostgREST); las LECTURAS bajo prueba
-- cambian a role authenticated para que la RLS mande. ESCRIBE de verdad
-- (llamadas, tareas, un descarte y su deshacer) y termina con rollback. Acaba con
-- GESTION_DIARIA_ANALISTA_OK o revienta con el nombre de la comprobación. Los
-- actores se DESCUBREN del fixture: un analista activo con supervisor activo,
-- ese supervisor, un analista de OTRO equipo, gerencia y el coordinador.
-- Lo ESPERADO se calcula ANTES de las escrituras, como postgres y con la misma
-- regla escrita (nunca con la función bajo prueba): el fixture puede traer
-- llamadas de hoy de otros ensayos, así que se asevera por DELTAS.
begin;
set local statement_timeout = '120s';

create temporary table o_actores on commit drop as
with v as (
  select e.perfil_id, e.supervisor_id from crm.equipo e
  where e.rol_crm = 'vendedor' and e.activo and e.supervisor_id is not null
    and exists (select 1 from crm.equipo s where s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor' and s.activo)
  order by e.perfil_id
)
select (select perfil_id from v limit 1) as v1,
       (select supervisor_id from v limit 1) as sup1,
       (select perfil_id from v where supervisor_id <> (select supervisor_id from v limit 1) limit 1) as v_ajeno,
       (select perfil_id from crm.equipo where rol_crm = 'gerencia' and activo limit 1) as ger,
       (select perfil_id from crm.equipo where rol_crm = 'coordinador' and activo limit 1) as coord;

-- Ventanas Lima de hoy y de hace 30 días.
create temporary table o_ventana on commit drop as
select ((now() at time zone 'America/Lima')::date) as hoy,
       (((now() at time zone 'America/Lima')::date)::timestamp) at time zone 'America/Lima' as ini,
       (((now() at time zone 'America/Lima')::date + 1)::timestamp) at time zone 'America/Lima' as fin,
       (((now() at time zone 'America/Lima')::date - 30)::timestamp) at time zone 'America/Lima' as ini30,
       (((now() at time zone 'America/Lima')::date - 29)::timestamp) at time zone 'America/Lima' as fin30;

-- Lo esperado ANTES de escribir (misma regla, escrita a mano).
create temporary table o_base on commit drop as
select
  (select coalesce(cardinality(array_agg(a.id)), 0) from crm.actividades a, o_ventana w, o_actores o
    where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin) as llamadas,
  (select coalesce(cardinality(array_agg(a.id)), 0) from crm.actividades a, o_ventana w, o_actores o
    where a.creado_por = o.v1 and a.tipo = 'llamada_realizada' and a.creado_en >= w.ini and a.creado_en < w.fin) as contestadas,
  (select coalesce(cardinality(array_agg(a.id)), 0) from crm.actividades a, o_ventana w, o_actores o
    where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin
      and coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona')) as utiles,
  (select coalesce(cardinality(array_agg(distinct a.lead_id)), 0) from crm.actividades a, o_ventana w, o_actores o
    where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin) as leads_tocados,
  (select coalesce(cardinality(array_agg(t.id)), 0) from crm.tareas t, o_ventana w, o_actores o
    where t.vendedor_id = o.v1 and t.tipo = 'reunion' and t.creado_en >= w.ini and t.creado_en < w.fin) as citas,
  (select coalesce(jsonb_object_agg(r.k, r.n), '{}'::jsonb) from (
     select coalesce(a.metadata->>'resultado', 'sin_resultado') as k, cardinality(array_agg(a.id)) as n
     from crm.actividades a, o_ventana w, o_actores o
     where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin
     group by 1) r) as por_resultado,
  (select coalesce(cardinality(array_agg(a.id)), 0) from crm.actividades a, o_ventana w, o_actores o
    where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini30 and a.creado_en < w.fin30) as llamadas_30,
  (select coalesce(cardinality(array_agg(a.id)), 0) from crm.actividades a, o_ventana w, o_actores o
    where a.creado_por = o.v_ajeno and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin) as llamadas_ajeno,
  (select coalesce(cardinality(array_agg(a.id)), 0) from crm.actividades a, o_ventana w, o_actores o
    where a.creado_por = o.v1 and a.metadata->>'evento' = 'resultado_llamada' and coalesce((a.metadata->>'descartado')::boolean, false)
      and a.creado_en >= w.ini and a.creado_en < w.fin) as descartados;

-- Los leads del oráculo NACEN por la vía legal (crm.crear_lead_si_disponible),
-- con la identidad de gerencia, asignados al analista: ocho para v1 (en «nuevo»,
-- sin intentos) y uno para el analista ajeno. Se deshacen con el rollback final.
create temporary table o_leads (n int, id uuid) on commit drop;
create temporary table o_ajeno (id uuid) on commit drop;
create temporary table o_ctx (k text primary key, v text) on commit drop;
do $alta$
declare a o_actores; i int; v jsonb; v_id uuid;
begin
  select * into a from o_actores;
  if a.v1 is null or a.sup1 is null or a.v_ajeno is null or a.ger is null then
    raise exception 'FIXTURE: faltan actores (v1 %, sup1 %, v_ajeno %, ger %)', a.v1, a.sup1, a.v_ajeno, a.ger;
  end if;
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  for i in 1..8 loop
    v_id := gen_random_uuid();
    v := crm.crear_lead_si_disponible(
      p_nombre_completo => format('ORACULO F3 LEAD %s', i), p_telefono => format('9996%s', lpad(i::text, 5, '0')),
      p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_id,
      p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
      p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => a.v1, p_nota => 'fixture del oraculo F3',
      p_telefono_alternativo => null);
    insert into o_leads select i, l.id from crm.leads l where l.id = v_id and l.vendedor_id = a.v1 and l.activo and l.etapa = 'nuevo';
  end loop;
  v_id := gen_random_uuid();
  v := crm.crear_lead_si_disponible(
    p_nombre_completo => 'ORACULO F3 AJENO', p_telefono => '999688888',
    p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_id,
    p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
    p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => a.v_ajeno, p_nota => 'fixture del oraculo F3',
    p_telefono_alternativo => null);
  insert into o_ajeno select l.id from crm.leads l where l.id = v_id and l.vendedor_id = a.v_ajeno and l.activo;
  if (select cardinality(array_agg(id)) from o_leads) is distinct from 8 or not exists (select 1 from o_ajeno) then
    raise exception 'FIXTURE: no se pudieron crear los leads del oraculo (%)', (select cardinality(array_agg(id)) from o_leads);
  end if;
end $alta$;

-- Cirugía del fixture (solo aquí, con los triggers de usuario apagados y
-- dentro del rollback): L6 lleva 10 días en manos del analista sin conversación;
-- L7 lleva 11 días y conversó hace 3.
do $cirugia$
declare a o_actores; L uuid[];
begin
  select * into a from o_actores;
  select array_agg(id order by n) into L from o_leads;
  -- postgres no es superusuario en Supabase: se apagan los triggers de usuario
  -- de las dos tablas (dueño), dentro de la transacción que se deshace.
  alter table crm.leads disable trigger user;
  alter table crm.actividades disable trigger user;
  update crm.leads set tenencia_desde = now() - interval '10 days' where id = L[6];
  update crm.leads set tenencia_desde = now() - interval '11 days', sla_global_iniciado_en = now() - interval '11 days',
         creado_en = now() - interval '11 days' where id = L[7];
  insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
  values (L[7], 'llamada_realizada', 'Oraculo F3: conversacion de hace 3 dias', a.v1, now() - interval '3 days');
  alter table crm.actividades enable trigger user;
  alter table crm.leads enable trigger user;
  if (select tenencia_desde from crm.leads where id = L[6]) > now() - interval '9 days' then
    raise exception 'FIXTURE: la cirugia de tenencia_desde no aplico';
  end if;
end $cirugia$;

-- ── Las llamadas del día, por la puerta de F2, como el analista ──────────────
-- Delta esperado: +6 llamadas, +3 contestadas, +5 útiles, +6 leads tocados,
-- +1 cita; por resultado: volver_a_llamar +1, no_contesto +2, numero_errado +1,
-- no_interesado +1, agendo_reunion +1; +1 descartado.
do $llamadas$
declare
  a o_actores; L uuid[]; v jsonb;
  v_manana date; v_pasado date; v_ts10 timestamptz; v_ts16 timestamptz;
begin
  select * into a from o_actores;
  select array_agg(id order by n) into L from o_leads;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  v_manana := ((now() at time zone 'America/Lima')::date + 1);
  if extract(isodow from v_manana) = 7 then v_manana := v_manana + 1; end if;
  v_pasado := v_manana + 1;
  if extract(isodow from v_pasado) = 7 then v_pasado := v_pasado + 1; end if;
  v_ts10 := (v_manana + time '10:00') at time zone 'America/Lima';
  v_ts16 := (v_pasado + time '16:00') at time zone 'America/Lima';

  -- A. contestó, volver a llamar mañana 10:00 → contactado + compromiso (llamada)
  v := crm.registrar_llamada_v3(gen_random_uuid(), L[1], 'volver_a_llamar', null, 'Pide que la llamen manana',
         jsonb_build_object('tipo', 'llamada', 'titulo', 'Volver a llamar', 'vence_en', v_ts10));
  if (v->>'ok')::boolean is not true then raise exception 'A: %', v; end if;
  insert into o_ctx values ('ts10', v_ts10::text), ('ts16', v_ts16::text), ('tarea_a', v->>'siguiente_id');
  -- B. no contestó
  v := crm.registrar_llamada_v3(gen_random_uuid(), L[2], 'no_contesto');
  if (v->>'ok')::boolean is not true then raise exception 'B: %', v; end if;
  -- C. número errado (no cuenta en la tasa), con observación
  v := crm.registrar_llamada_v3(gen_random_uuid(), L[3], 'numero_errado', null, 'Contesta otra persona, numero equivocado');
  if (v->>'ok')::boolean is not true then raise exception 'C: %', v; end if;
  -- D. contestó, no le interesa (desconfianza) → descartado hoy
  v := crm.registrar_llamada_v3(gen_random_uuid(), L[4], 'no_interesado', 'desconfianza', 'Desconfia de la empresa');
  if (v->>'ok')::boolean is not true or (v->>'descartado')::boolean is not true then raise exception 'D: %', v; end if;
  insert into o_ctx values ('act_d', v->>'actividad_id');
  -- E. contestó, agendó cita pasado mañana 16:00 → reunion_agendada + compromiso (cita) + cita agendada hoy
  v := crm.registrar_llamada_v3(gen_random_uuid(), L[5], 'agendo_reunion', null, 'Quiere verlo en la oficina',
         jsonb_build_object('tipo', 'reunion', 'titulo', 'Cita con el cliente', 'vence_en', v_ts16,
                            'modalidad_reunion', 'presencial', 'ubicacion_reunion', 'Oficina San Isidro'));
  if (v->>'ok')::boolean is not true then raise exception 'E: %', v; end if;
  insert into o_ctx values ('tarea_e', v->>'siguiente_id');
  -- G. no contestó (la quinta llamada útil del oráculo)
  v := crm.registrar_llamada_v3(gen_random_uuid(), L[8], 'no_contesto');
  if (v->>'ok')::boolean is not true then raise exception 'G: %', v; end if;
end $llamadas$;

grant select on o_actores, o_leads, o_ajeno, o_ctx, o_base, o_ventana to authenticated;

-- ── Lecturas bajo la RLS: el analista ────────────────────────────────────────
do $analista$
declare
  a o_actores; b o_base; L uuid[]; r jsonb; m jsonb; c jsonb; d jsonb; v_x jsonb;
  v_hora integer; v_n integer; v_c integer; v_pct numeric; v_nivel text; v_k text;
begin
  select * into a from o_actores;
  select * into b from o_base;
  select array_agg(id order by n) into L from o_leads;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn();
  reset role;

  -- 1. sobre
  if (r->>'version')::int <> 1 or (r->>'analista_id')::uuid <> a.v1 or r->>'zona' <> 'America/Lima'
     or (r->>'dia')::date <> (select hoy from o_ventana) or r->'generado_en' is null
     or (r->>'sin_conversacion_dias')::int <> (select dias_abandono from crm.politica_abandono where singleton)
     or (r#>>'{umbrales,bien_min_pct}')::int <> 45 or (r#>>'{umbrales,atencion_min_pct}')::int <> 25
     or (r#>>'{umbrales,minimo_llamadas_utiles}')::int <> 5 then
    raise exception '1: sobre inesperado: %', r - 'cartera' - 'compromisos' - 'descartados' - 'marcador';
  end if;

  -- 2. marcador por deltas: +6 llamadas, +3 contestadas, +5 útiles, +6 leads, +1 cita; tasa y nivel con la regla escrita
  m := r->'marcador';
  v_pct := round(100.0 * (b.contestadas + 3) / (b.utiles + 5));
  v_nivel := case when v_pct >= 45 then 'bien' when v_pct >= 25 then 'atencion' else 'bajo' end;
  if (m->>'llamadas')::int <> b.llamadas + 6 or (m->>'contestadas')::int <> b.contestadas + 3 or (m->>'utiles')::int <> b.utiles + 5
     or (m->>'tasa_contacto_pct')::numeric <> v_pct or m->>'nivel' <> v_nivel
     or (m->>'leads_tocados')::int <> b.leads_tocados + 6 or (m->>'citas_agendadas')::int <> b.citas + 1
     or m->>'primera_llamada_en' is null or m->>'ultima_llamada_en' is null
     or (m->>'primera_llamada_en')::timestamptz > (m->>'ultima_llamada_en')::timestamptz then
    raise exception '2: marcador inesperado (base %): %', row_to_json(b), m;
  end if;
  for v_k, v_n in select * from (values ('volver_a_llamar', 1), ('no_contesto', 2), ('numero_errado', 1), ('no_interesado', 1), ('agendo_reunion', 1)) t loop
    if coalesce((m#>>array['por_resultado', v_k])::int, 0) <> coalesce((b.por_resultado->>v_k)::int, 0) + v_n then
      raise exception '2: por_resultado[%] esperaba % y trajo %: %', v_k, coalesce((b.por_resultado->>v_k)::int, 0) + v_n, m#>>array['por_resultado', v_k], m->'por_resultado';
    end if;
  end loop;
  if coalesce((m#>>'{por_resultado,sin_resultado}')::int, 0) <> coalesce((b.por_resultado->>'sin_resultado')::int, 0) then
    raise exception '2: por_resultado[sin_resultado] cambio: %', m->'por_resultado';
  end if;
  select sum((h->>'llamadas')::int), sum((h->>'contestadas')::int) into v_n, v_c from jsonb_array_elements(m->'por_hora') h;
  if v_n <> (m->>'llamadas')::int or v_c <> (m->>'contestadas')::int then
    raise exception '2: por_hora no suma (llamadas %, contestadas %): %', v_n, v_c, m->'por_hora';
  end if;
  v_hora := extract(hour from ((m->>'ultima_llamada_en')::timestamptz at time zone 'America/Lima'))::int;
  select (h->>'llamadas')::int, (h->>'contestadas')::int into v_n, v_c from jsonb_array_elements(m->'por_hora') h where (h->>'hora')::int = v_hora;
  if v_n is null or v_n < 6 or v_c < 3 then
    raise exception '2: la hora Lima de las llamadas del oraculo (%) no acumula al menos 6/3 en por_hora: %', v_hora, m->'por_hora';
  end if;

  -- 3. compromisos: la llamada de mañana (L1) y la cita de pasado mañana (L5), en ese orden entre los del oráculo
  c := coalesce((select jsonb_agg(i order by (i->>'vence_en')::timestamptz, i->>'tarea_id') from jsonb_array_elements(r->'compromisos') i where (i->>'lead_id')::uuid = any (L)), '[]'::jsonb);
  if jsonb_array_length(c) <> 2 or (r->>'compromisos_total')::int < 2 or (r->>'compromisos_total')::int <> jsonb_array_length(r->'compromisos')
     or (c#>>'{0,lead_id}')::uuid <> L[1] or c#>>'{0,tipo}' <> 'llamada' or c#>>'{0,lead_etapa}' <> 'contactado'
     or (c#>>'{0,vence_en}')::timestamptz <> (select v::timestamptz from o_ctx where k = 'ts10')
     or (c#>>'{0,tarea_id}')::uuid <> (select v::uuid from o_ctx where k = 'tarea_a')
     or (c#>>'{1,lead_id}')::uuid <> L[5] or c#>>'{1,tipo}' <> 'reunion' or c#>>'{1,lead_etapa}' <> 'reunion_agendada'
     or c#>>'{1,modalidad_reunion}' <> 'presencial'
     or (c#>>'{1,tarea_id}')::uuid <> (select v::uuid from o_ctx where k = 'tarea_e') then
    raise exception '3: compromisos inesperados: % (total %)', c, r->>'compromisos_total';
  end if;
  -- ordenados por vence_en en la respuesta completa
  if exists (select 1 from (select i, lag((i->>'vence_en')::timestamptz) over (order by o) as prev
                             from jsonb_array_elements(r->'compromisos') with ordinality as t(i, o)) s
             where s.prev is not null and (s.i->>'vence_en')::timestamptz < s.prev) then
    raise exception '3: compromisos desordenados: %', r->'compromisos';
  end if;

  -- 4. cartera: los 7 leads abiertos del oráculo (L4 está descartado), con sus señales
  if (r->>'cartera_truncada')::boolean then raise exception '4: cartera truncada'; end if;
  select cardinality(array_agg(e)) into v_n from jsonb_array_elements(r->'cartera') e where (e->>'lead_id')::uuid = any (L);
  if v_n <> 7 or exists (select 1 from jsonb_array_elements(r->'cartera') e where (e->>'lead_id')::uuid = L[4]) then
    raise exception '4: la cartera debio traer 7 leads del oraculo sin el descartado (trajo %)', v_n;
  end if;
  select e into v_x from jsonb_array_elements(r->'cartera') e where (e->>'lead_id')::uuid = L[6];
  if (v_x->>'sin_conversacion')::boolean is not true or (v_x->>'dias_sin_conversacion')::int < 9
     or v_x->>'ultima_conversacion_en' is not null or (v_x->>'llamadas_ciclo')::int <> 0 or v_x->>'proxima_tarea_en' is not null then
    raise exception '4: L6 debio estar sin conversacion hace 10 dias: %', v_x;
  end if;
  select e into v_x from jsonb_array_elements(r->'cartera') e where (e->>'lead_id')::uuid = L[7];
  if (v_x->>'sin_conversacion')::boolean is not false or (v_x->>'dias_sin_conversacion')::int not between 2 and 3
     or v_x->>'ultima_conversacion_en' is null or (v_x->>'llamadas_ciclo')::int <> 1 or v_x->>'ultima_llamada_tipo' <> 'llamada_realizada'
     or v_x->>'ultima_llamada_resultado' is not null then
    raise exception '4: L7 converso hace 3 dias (1 llamada historica sin resultado): %', v_x;
  end if;
  select e into v_x from jsonb_array_elements(r->'cartera') e where (e->>'lead_id')::uuid = L[2];
  if (v_x->>'sin_conversacion')::boolean or (v_x->>'intentos_sin_respuesta')::int <> 1 or (v_x->>'llamadas_ciclo')::int <> 1
     or v_x->>'ultima_llamada_tipo' <> 'llamada_no_contestada' or v_x->>'ultima_llamada_resultado' <> 'no_contesto'
     or v_x->>'ultima_conversacion_en' is not null or v_x->>'etapa' <> 'nuevo' then
    raise exception '4: L2 (no contesto): %', v_x;
  end if;
  select e into v_x from jsonb_array_elements(r->'cartera') e where (e->>'lead_id')::uuid = L[3];
  if v_x->>'numero_errado_detalle' <> 'Contesta otra persona, numero equivocado' or v_x->>'numero_errado_en' is null
     or (v_x->>'intentos_sin_respuesta')::int <> 0 or (v_x->>'llamadas_ciclo')::int <> 1 then
    raise exception '4: L3 (numero errado): %', v_x;
  end if;
  select e into v_x from jsonb_array_elements(r->'cartera') e where (e->>'lead_id')::uuid = L[1];
  if v_x->>'etapa' <> 'contactado' or (v_x->>'proxima_tarea_en')::timestamptz <> (select v::timestamptz from o_ctx where k = 'ts10')
     or v_x->>'proxima_tarea_tipo' <> 'llamada' or v_x->>'ultima_conversacion_en' is null or (v_x->>'sin_conversacion')::boolean
     or (v_x->>'dias_sin_conversacion')::int <> 0 then
    raise exception '4: L1 (volver a llamar): %', v_x;
  end if;
  -- La cartera no trae nada ajeno.
  if exists (select 1 from jsonb_array_elements(r->'cartera') e where (e->>'lead_id')::uuid in (select id from o_ajeno)) then
    raise exception '4: la cartera del analista trae un lead ajeno';
  end if;
  -- Y está ordenada de más días sin conversación a menos (referencia ascendente).
  if exists (select 1 from (select i, lag((i->>'dias_sin_conversacion')::int) over (order by o) as prev
                             from jsonb_array_elements(r->'cartera') with ordinality as t(i, o)) s
             where s.prev is not null and (s.i->>'dias_sin_conversacion')::int > s.prev) then
    raise exception '4: cartera desordenada (dias_sin_conversacion debe ir de mayor a menor)';
  end if;

  -- 5. descartados hoy: L4 (delta +1), vigente, se puede deshacer
  if jsonb_array_length(r->'descartados') <> b.descartados + 1 then
    raise exception '5: descartados esperaba % y trajo %', b.descartados + 1, jsonb_array_length(r->'descartados');
  end if;
  select i into d from jsonb_array_elements(r->'descartados') i where (i->>'lead_id')::uuid = L[4];
  if d is null or (d->>'actividad_id')::uuid <> (select v::uuid from o_ctx where k = 'act_d')
     or d->>'resultado' <> 'no_interesado' or d->>'submotivo' <> 'desconfianza' or d->>'motivo_descarte' <> 'sin_interes'
     or (d->>'deshecho')::boolean or (d->>'vigente')::boolean is not true or (d->>'no_insista')::boolean
     or (d->>'puede_deshacer')::boolean is not true or d->>'lead_etapa' <> 'descartado' then
    raise exception '5: descartado de L4 inesperado: %', d;
  end if;

  -- 6. Deshacer (puerta de F2) → el descarte deja de estar vigente, L4 vuelve a la cartera,
  --    y el REGISTRO de F1 ya enseña deshecho_en (deuda pagada).
  set local role authenticated;
  v_x := crm.deshacer_resultado_llamada((select v::uuid from o_ctx where k = 'act_d'));
  if (v_x->>'ok')::boolean is not true or (v_x->>'descarte_revertido')::boolean is not true then raise exception '6: deshacer: %', v_x; end if;
  r := crm.gestion_diaria_analista_fn();
  v_x := crm.registro_actividad_fn((select hoy from o_ventana), (select hoy from o_ventana),
                                  p_analista_ids => array[a.v1], p_tipos => array['llamada_realizada'], p_limite => 50);
  reset role;
  select i into d from jsonb_array_elements(r->'descartados') i where (i->>'lead_id')::uuid = L[4];
  if d is null or (d->>'deshecho')::boolean is not true or (d->>'vigente')::boolean
     or (d->>'puede_deshacer')::boolean or d->>'lead_etapa' <> 'contactado' then
    raise exception '6: tras deshacer, descartado de L4: %', d;
  end if;
  if not exists (select 1 from jsonb_array_elements(r->'cartera') c2 where (c2->>'lead_id')::uuid = L[4] and c2->>'etapa' = 'contactado') then
    raise exception '6: L4 debio volver a la cartera como contactado';
  end if;
  if (r#>>'{marcador,llamadas}')::int <> b.llamadas + 6 then raise exception '6: una llamada deshecha sigue contando (llamadas %)', r#>>'{marcador,llamadas}'; end if;
  select i into v_x from jsonb_array_elements(v_x->'items') i where (i->>'id')::uuid = (select v::uuid from o_ctx where k = 'act_d');
  if v_x is null or v_x#>>'{metadata,deshecho_en}' is null or (v_x#>>'{metadata,descartado}')::boolean is not true
     or v_x#>>'{metadata,resultado}' <> 'no_interesado' or v_x#>>'{metadata,motivo_descarte}' <> 'sin_interes'
     or v_x#>>'{metadata,etapa_al_descartar}' is null then
    raise exception '6: el registro de F1 no ensena las claves nuevas (deshecho_en, descartado, motivo_descarte, etapa_al_descartar): %', v_x;
  end if;

  -- 7. Un analista solo ve su propio día
  set local role authenticated;
  begin
    perform crm.gestion_diaria_analista_fn(null, a.v_ajeno);
    raise exception '7: el analista leyo el dia de otro';
  exception when insufficient_privilege then null;
  end;
  -- 8. Fechas: futura y de hace más de un año → 22023
  begin
    perform crm.gestion_diaria_analista_fn((select hoy from o_ventana) + 1);
    raise exception '8: acepto una fecha futura';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform crm.gestion_diaria_analista_fn((select hoy from o_ventana) - 400);
    raise exception '8: acepto una fecha de hace mas de un ano';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform crm.gestion_diaria_analista_fn('-infinity'::date);
    raise exception '8: acepto -infinity';
  exception when invalid_parameter_value then null;
  end;
  -- 9. Un día pasado: marcador de ese día (base), sin los descartes de hoy; cartera y compromisos siguen siendo los de hoy
  r := crm.gestion_diaria_analista_fn((select hoy from o_ventana) - 30);
  reset role;
  if (r#>>'{marcador,llamadas}')::int <> b.llamadas_30
     or (b.llamadas_30 = 0 and (r#>>'{marcador,tasa_contacto_pct}' is not null or r#>>'{marcador,nivel}' is not null
                                or r#>'{marcador,por_resultado}' <> '{}'::jsonb or r#>'{marcador,por_hora}' <> '[]'::jsonb))
     or exists (select 1 from jsonb_array_elements(r->'descartados') i where (i->>'lead_id')::uuid = L[4])
     or not exists (select 1 from jsonb_array_elements(r->'compromisos') i where (i->>'lead_id')::uuid = L[1]) then
    raise exception '9: un dia pasado: %', r - 'cartera';
  end if;
  raise notice 'ORACULO F3: analista 1-9 en verde';
end $analista$;

-- ── El otro analista, el supervisor, gerencia y el coordinador ───────────────
do $otros$
declare a o_actores; b o_base; L uuid[]; r jsonb; v_sup_ajeno uuid;
begin
  select * into a from o_actores;
  select * into b from o_base;
  select array_agg(id order by n) into L from o_leads;
  select e.supervisor_id into v_sup_ajeno from crm.equipo e where e.perfil_id = a.v_ajeno;

  -- 10. El analista ajeno: su propio marcador y ninguna de las señales de v1
  perform set_config('request.jwt.claim.sub', a.v_ajeno::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v_ajeno, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn();
  reset role;
  if (r->>'analista_id')::uuid <> a.v_ajeno or (r#>>'{marcador,llamadas}')::int <> b.llamadas_ajeno
     or exists (select 1 from jsonb_array_elements(r->'cartera') x where (x->>'lead_id')::uuid = any (L))
     or not exists (select 1 from jsonb_array_elements(r->'cartera') x where (x->>'lead_id')::uuid in (select id from o_ajeno))
     or exists (select 1 from jsonb_array_elements(r->'descartados') i where (i->>'lead_id')::uuid = any (L)) then
    raise exception '10: el analista ajeno ve algo de v1: %', r - 'cartera';
  end if;

  -- 11. El supervisor: el día de su analista, con el mismo marcador; el de otro equipo, 42501
  perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.sup1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn(null, a.v1);
  if (r->>'analista_id')::uuid <> a.v1 or (r#>>'{marcador,llamadas}')::int <> b.llamadas + 6 or (r#>>'{marcador,contestadas}')::int <> b.contestadas + 3
     or not exists (select 1 from jsonb_array_elements(r->'compromisos') i where (i->>'lead_id')::uuid = L[5])
     or not exists (select 1 from jsonb_array_elements(r->'descartados') i where (i->>'lead_id')::uuid = L[4]) then
    raise exception '11: el supervisor no ve el dia de su analista: %', r - 'cartera';
  end if;
  if exists (select 1 from jsonb_array_elements(r->'descartados') i where (i->>'puede_deshacer')::boolean) then
    raise exception '11: el supervisor no puede deshacer por el analista (el deshacer exige ser el autor): %', r->'descartados';
  end if;
  if v_sup_ajeno is distinct from a.sup1 then
    begin
      perform crm.gestion_diaria_analista_fn(null, a.v_ajeno);
      raise exception '11: el supervisor leyo un analista de otro equipo';
    exception when insufficient_privilege then null;
    end;
  else
    raise notice '11 parcial: el analista ajeno comparte supervisor; no se prueba la denegacion entre equipos';
  end if;
  begin
    perform crm.gestion_diaria_analista_fn(null, gen_random_uuid());
    raise exception '11: el supervisor leyo un analista inexistente';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- 12. Gerencia: cualquier analista
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn(null, a.v1);
  reset role;
  if (r#>>'{marcador,llamadas}')::int <> b.llamadas + 6 or (r#>>'{marcador,citas_agendadas}')::int <> b.citas + 1 then
    raise exception '12: gerencia no ve el dia del analista: %', r - 'cartera';
  end if;
  if exists (select 1 from jsonb_array_elements(r->'descartados') i where (i->>'puede_deshacer')::boolean) then
    raise exception '12: gerencia no puede deshacer por el analista: %', r->'descartados';
  end if;

  -- 13. El coordinador no entra
  if a.coord is not null then
    perform set_config('request.jwt.claim.sub', a.coord::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', a.coord, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      perform crm.gestion_diaria_analista_fn();
      raise exception '13: el coordinador ejecuto la puerta';
    exception when insufficient_privilege then null;
    end;
    reset role;
  else
    raise notice '13 omitido: el fixture no tiene coordinador';
  end if;
  raise notice 'ORACULO F3: otros 10-13 en verde';
end $otros$;

-- ── 14. anon: sin EXECUTE (error de autorización, no cualquier error) ────────
do $anon$
begin
  set local role anon;
  begin
    perform crm.gestion_diaria_analista_fn();
    raise exception '14: anon ejecuto la puerta';
  exception when insufficient_privilege then null;
  end;
  reset role;
  if has_function_privilege('anon', 'crm.gestion_diaria_analista_fn(date,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz)', 'EXECUTE')
     or has_function_privilege('anon', 'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.gestion_diaria_analista_fn(date,uuid)', 'EXECUTE') then
    raise exception '14: la puerta o un nucleo tienen EXECUTE fuera de authenticated';
  end if;
end $anon$;

-- ── 15. El núcleo compartido, para varios analistas a la vez (lo usarán F4/F5) ─
do $varios$
declare a o_actores; b o_base; r record; v_n integer := 0;
begin
  select * into a from o_actores;
  select * into b from o_base;
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  set local role authenticated;
  for r in select * from private.gestion_diaria_llamadas((select ini from o_ventana), (select fin from o_ventana), array[a.v1, a.v_ajeno, a.v1]) loop
    v_n := v_n + 1;
    if r.vendedor_id = a.v1 and (r.llamadas <> b.llamadas + 6 or r.contestadas <> b.contestadas + 3 or r.utiles <> b.utiles + 5 or r.citas_agendadas <> b.citas + 1) then
      raise exception '15: fila de v1 inesperada: % % % %', r.llamadas, r.contestadas, r.utiles, r.citas_agendadas;
    end if;
    if r.vendedor_id = a.v_ajeno and (r.llamadas <> b.llamadas_ajeno
        or (b.llamadas_ajeno = 0 and (r.por_resultado <> '{}'::jsonb or r.por_hora <> '[]'::jsonb or r.primera_llamada_en is not null))) then
      raise exception '15: fila del ajeno inesperada: % %', r.llamadas, r.por_resultado;
    end if;
  end loop;
  reset role;
  if v_n <> 2 then raise exception '15: el nucleo debio devolver una fila por analista distinto (devolvio %)', v_n; end if;
end $varios$;

select 'GESTION_DIARIA_ANALISTA_OK';
rollback;

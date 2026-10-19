-- Oráculo de «las llamadas a clientes cuentan» (Gestión Diaria, 19/10/2026) sobre el banco.
-- Corre como postgres; las LECTURAS bajo prueba cambian a role authenticated con la identidad del actor en
-- request.jwt.claim.sub (como PostgREST). Siembra un segundo equipo, un cliente con sus tareas y cierres (cirugía
-- del fixture con los triggers de usuario apagados) y UNA llamada a lead por la puerta real; termina con ROLLBACK.
-- Lo ESPERADO se calcula ANTES, como postgres, con la regla escrita a mano (nunca con la función bajo prueba),
-- por DELTAS sobre lo que ya hubiera en el banco. Acaba imprimiendo GESTION_DIARIA_LLAMADAS_CLIENTES_OK o revienta
-- con el nombre de la comprobación.
begin;
set local statement_timeout = '120s';

-- ── Actores: el equipo 1 lo trae la siembra del banco; el equipo 2 nace aquí ──
create temporary table o_actores on commit drop as
select 'b0000000-0000-4000-8000-000000000002'::uuid as v1,
       'b0000000-0000-4000-8000-000000000001'::uuid as sup1,
       'b0000000-0000-4000-8000-000000000003'::uuid as ger,
       'c0000000-0000-4000-8000-000000000001'::uuid as sup2,
       'c0000000-0000-4000-8000-000000000002'::uuid as v2,
       'c0000000-0000-4000-8000-000000000009'::uuid as cliente_perfil;

do $equipo2$
declare a o_actores;
begin
  select * into a from o_actores;
  if not exists (select 1 from crm.equipo where perfil_id = a.v1 and rol_crm = 'vendedor' and activo and supervisor_id = a.sup1)
     or not exists (select 1 from crm.equipo where perfil_id = a.ger and rol_crm = 'gerencia' and activo) then
    raise exception 'FIXTURE: falta la siembra del banco (v1 bajo sup1, gerencia)';
  end if;
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data)
  values (a.sup2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'oraculo.sup2@avancecorp.test', '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}'),
         (a.v2,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'oraculo.v2@avancecorp.test',   '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}'),
         (a.cliente_perfil, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'oraculo.cliente@avancecorp.test', '', now(), now(), now(), '', '', '', '', '{"provider":"email"}', '{}');
  insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, debe_cambiar_password, titular_distinto, titular_distinto_usd)
  values (a.sup2, 'ORACULO SUPERVISOR 2', 'analista', true, 'DNI', false, false, false),
         (a.v2,   'ORACULO VENDEDOR 2',   'analista', true, 'DNI', false, false, false),
         (a.cliente_perfil, 'ORACULO CLIENTE', 'cliente', true, 'DNI', false, false, false);
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values (a.sup2, 'supervisor', null, true);
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values (a.v2, 'vendedor', a.sup2, true);
end $equipo2$;

-- ── Ventana Lima de hoy ───────────────────────────────────────────────────────
create temporary table o_ventana on commit drop as
select ((now() at time zone 'America/Lima')::date) as hoy,
       (((now() at time zone 'America/Lima')::date)::timestamp) at time zone 'America/Lima' as ini,
       (((now() at time zone 'America/Lima')::date + 1)::timestamp) at time zone 'America/Lima' as fin;

-- ── Lo esperado ANTES de escribir (regla escrita a mano) ──────────────────────
create temporary table o_base on commit drop as
with leads as (
  select a.id, a.tipo, coalesce(a.metadata->>'resultado', 'sin_resultado') as resultado,
         coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona') as util, a.lead_id
  from crm.actividades a, o_ventana w, o_actores o
  where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin
), clientes as (
  select g.id,
         case when coalesce(g.metadata->>'resultado', 'sin_resultado') in ('no_contesto', 'numero_errado', 'no_es_la_persona') then 'llamada_no_contestada' else 'llamada_realizada' end as tipo,
         coalesce(g.metadata->>'resultado', 'sin_resultado') as resultado,
         coalesce(g.metadata->>'resultado', 'sin_resultado') not in ('numero_errado', 'no_es_la_persona', 'sin_resultado') as util
  from crm.inversionista_gestiones g join crm.tareas t on t.id = g.tarea_id, o_ventana w, o_actores o
  where g.tipo = 'cierre' and g.creado_por = o.v1 and g.creado_en >= w.ini and g.creado_en < w.fin
    and coalesce(g.metadata->>'tipo_tarea', t.tipo) = 'llamada' and coalesce(g.metadata->>'estado', t.estado) = 'completada'
  union all
  select a.id, a.tipo, 'sin_resultado', true
  from crm.actividades_cliente a left join crm.tareas t on t.id = a.tarea_id, o_ventana w, o_actores o
  where a.creado_por = o.v1 and a.tipo in ('llamada_realizada', 'llamada_no_contestada') and a.creado_en >= w.ini and a.creado_en < w.fin
    and coalesce(t.estado, 'completada') = 'completada'
    and not exists (select 1 from crm.inversionista_gestiones g where g.tarea_id = a.tarea_id and g.tipo = 'cierre')
), todo as (
  select id, tipo, resultado, util, lead_id from leads
  union all select id, tipo, resultado, util, null from clientes
)
select (select coalesce(cardinality(array_agg(id)), 0) from todo) as llamadas,
       (select coalesce(cardinality(array_agg(id) filter (where tipo = 'llamada_realizada' and util)), 0) from todo) as contestadas,
       (select coalesce(cardinality(array_agg(id) filter (where util)), 0) from todo) as utiles,
       (select coalesce(cardinality(array_agg(distinct lead_id) filter (where lead_id is not null)), 0) from todo) as leads_tocados,
       (select coalesce(cardinality(array_agg(id)), 0) from leads) as llamadas_leads,
       (select coalesce(cardinality(array_agg(id)), 0) from clientes) as llamadas_clientes,
       (select coalesce(cardinality(array_agg(id) filter (where tipo = 'llamada_realizada' and util)), 0) from clientes) as contestadas_clientes,
       (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select resultado as k, cardinality(array_agg(id)) as n from todo group by 1) r) as por_resultado;

-- ── Fixture del cliente: tareas y cierres de postventa (cirugía con triggers apagados) ─
create temporary table o_ids (k text primary key, v uuid) on commit drop;
do $cliente$
declare
  a o_actores; w o_ventana; v_inv1 uuid := gen_random_uuid(); v_inv2 uuid := gen_random_uuid();
  v_t uuid; v_i integer; v_res text; v_ts timestamptz;
  -- (clave, tipo de tarea, estado, resultado, momento) — v1 salvo T14
  v_casos text[][] := array[
    ['T1',  'llamada',  'completada', 'agendo_reunion',  'ahora'],
    ['T2',  'llamada',  'completada', 'agendo_reunion',  'ahora'],
    ['T3',  'llamada',  'completada', 'agendo_reunion',  'ahora'],
    ['T4',  'llamada',  'completada', 'volver_a_llamar', 'ahora'],
    ['T5',  'llamada',  'completada', 'volver_a_llamar', 'ahora'],
    ['T6',  'llamada',  'completada', 'no_contesto',     'ahora'],
    ['T7',  'llamada',  'completada', 'numero_errado',   'ahora'],
    ['T8',  'llamada',  'cancelada',  null,              'ahora'],
    ['T9',  'reunion',  'completada', null,              'ahora'],
    ['T10', 'whatsapp', 'completada', 'respondio',       'ahora'],
    ['T11', 'llamada',  'completada', null,              'ahora'],
    ['T12', 'llamada',  'completada', 'volver_a_llamar', 'ayer'],
    ['T13', 'llamada',  'completada', 'no_contesto',     'inicio'],
    ['T14', 'llamada',  'completada', 'agendo_reunion',  'ahora'],
    ['T15', 'llamada',  'pendiente',  null,              'ahora'],
    ['T16', 'llamada',  'completada', 'no_contesto',     'fin'],
    ['T17', 'llamada',  'completada', 'agendo_reunion',  'jornada']
  ];
begin
  select * into a from o_actores;
  select * into w from o_ventana;
  alter table crm.inversionistas disable trigger user;
  alter table crm.tareas disable trigger user;
  alter table crm.inversionista_gestiones disable trigger user;
  alter table crm.actividades_cliente disable trigger user;
  insert into crm.inversionistas (id, estado, responsable_relacion_id, creado_por) values (v_inv1, 'activo', a.v1, a.ger), (v_inv2, 'activo', a.v2, a.ger);
  insert into o_ids values ('inv1', v_inv1), ('inv2', v_inv2);
  for v_i in 1..array_length(v_casos, 1) loop
    v_t := gen_random_uuid();
    v_res := v_casos[v_i][4];
    v_ts := case v_casos[v_i][5] when 'ahora' then now() when 'ayer' then w.ini - interval '1 second' when 'fin' then w.fin
                                 when 'jornada' then (w.hoy + time '09:30') at time zone 'America/Lima' else w.ini end;
    insert into crm.tareas (id, inversionista_id, vendedor_id, tipo, titulo, vence_en, estado, activo, creado_por, creado_en, postventa_revision,
                            cancelada_por, resultado_reunion)
    values (v_t, case when v_casos[v_i][1] = 'T14' then v_inv2 else v_inv1 end,
            case when v_casos[v_i][1] = 'T14' then a.v2 else a.v1 end,
            v_casos[v_i][2], 'Oraculo ' || v_casos[v_i][1], v_ts - interval '1 hour', v_casos[v_i][3], true,
            case when v_casos[v_i][1] = 'T14' then a.v2 else a.v1 end, v_ts - interval '2 hours', 2,
            case when v_casos[v_i][3] = 'cancelada' then 'asesor' end,
            case when v_casos[v_i][2] = 'reunion' and v_casos[v_i][3] = 'completada' then 'sin_clasificar' end);
    if v_casos[v_i][3] <> 'pendiente' then
    insert into crm.inversionista_gestiones (inversionista_id, tarea_id, tipo, detalle, metadata, creado_por, creado_en)
    values (case when v_casos[v_i][1] = 'T14' then v_inv2 else v_inv1 end, v_t, 'cierre', 'Oraculo ' || v_casos[v_i][1],
            jsonb_strip_nulls(jsonb_build_object('estado', v_casos[v_i][3], 'tipo_tarea', v_casos[v_i][2],
              'resultado', case when v_casos[v_i][2] = 'reunion' then null else v_res end,
              'resultado_reunion', case when v_casos[v_i][2] = 'reunion' then 'sin_clasificar' end)),
            case when v_casos[v_i][1] = 'T14' then a.v2 else a.v1 end, v_ts);
    end if;
    insert into o_ids values (v_casos[v_i][1], v_t);
  end loop;
  -- Legado: A1 cuenta (realizada, sin tarea); A2 NO (su tarea T6 ya tiene cierre F6); A3 NO (su tarea T15 sigue pendiente).
  insert into crm.actividades_cliente (cliente_id, vendedor_id, tarea_id, tipo, detalle, creado_por, creado_en)
  values (a.cliente_perfil, a.v1, null, 'llamada_realizada', 'Oraculo A1 legado', a.v1, now()),
         (a.cliente_perfil, a.v1, (select v from o_ids where k = 'T6'), 'llamada_no_contestada', 'Oraculo A2 espejo', a.v1, now()),
         (a.cliente_perfil, a.v1, (select v from o_ids where k = 'T15'), 'llamada_realizada', 'Oraculo A3 pendiente', a.v1, now());
  alter table crm.actividades_cliente enable trigger user;
  alter table crm.inversionista_gestiones enable trigger user;
  alter table crm.tareas enable trigger user;
  alter table crm.inversionistas enable trigger user;
end $cliente$;

-- ── UNA llamada a lead por la puerta real (como el analista) ─────────────────
create temporary table o_lead (id uuid) on commit drop;
do $lead$
declare a o_actores; v jsonb; v_id uuid := gen_random_uuid(); v_manana date; v_ts timestamptz;
begin
  select * into a from o_actores;
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  v := crm.crear_lead_si_disponible(
    p_nombre_completo => 'ORACULO LLAMADAS CLIENTES LEAD', p_telefono => '999677001',
    p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_id,
    p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
    p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => a.v1, p_nota => 'fixture del oraculo', p_telefono_alternativo => null);
  insert into o_lead select l.id from crm.leads l where l.id = v_id and l.vendedor_id = a.v1 and l.activo;
  if not exists (select 1 from o_lead) then raise exception 'FIXTURE: no se pudo crear el lead (%)', v; end if;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  v_manana := ((now() at time zone 'America/Lima')::date + 1);
  if extract(isodow from v_manana) = 7 then v_manana := v_manana + 1; end if;
  v_ts := (v_manana + time '10:00') at time zone 'America/Lima';
  v := crm.registrar_llamada_v3(gen_random_uuid(), v_id, 'volver_a_llamar', null, 'Pide que la llamen manana',
         jsonb_build_object('tipo', 'llamada', 'titulo', 'Volver a llamar', 'vence_en', v_ts));
  if (v->>'ok')::boolean is not true then raise exception 'LEAD: %', v; end if;
end $lead$;

grant select on o_actores, o_ventana, o_base, o_ids, o_lead to authenticated;

-- ── Lecturas bajo la RLS ──────────────────────────────────────────────────────
-- Delta esperado para v1: clientes +11 llamadas (T1–T7, T11, T13, T17, A1), +7 contestadas (T1–T5, T17, A1), +9 útiles
-- (T1–T6, T13, T17, A1); lead +1/+1/+1 y +1 lead tocado. Total: +12 llamadas, +8 contestadas, +10 útiles, +1 lead.
-- por_resultado: agendo_reunion +4, volver_a_llamar +3 (2 clientes + 1 lead), no_contesto +2, numero_errado +1,
-- sin_resultado +2 (T11 y A1).
do $lecturas$
declare
  a o_actores; b o_base; w o_ventana; r jsonb; m jsonb; v_n integer; v_c integer; v_k text; v_fila jsonb; v_pct numeric;
begin
  select * into a from o_actores; select * into b from o_base; select * into w from o_ventana;

  -- 1. El analista v1 ve su día con las llamadas a clientes dentro.
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn();
  reset role;
  m := r->'marcador';
  v_pct := round(100.0 * (b.contestadas + 8) / (b.utiles + 10));
  if (m->>'llamadas')::int is distinct from b.llamadas + 12 or (m->>'contestadas')::int is distinct from b.contestadas + 8
     or (m->>'utiles')::int is distinct from b.utiles + 10 or (m->>'leads_tocados')::int is distinct from b.leads_tocados + 1
     or (m->>'tasa_contacto_pct')::numeric is distinct from v_pct
     or m->>'nivel' is distinct from (case when v_pct >= 45 then 'bien' when v_pct >= 25 then 'atencion' else 'bajo' end) then
    raise exception '1: marcador inesperado (base %): %', row_to_json(b), m;
  end if;
  for v_k, v_n in select * from (values ('agendo_reunion', 4), ('volver_a_llamar', 3), ('no_contesto', 2), ('numero_errado', 1), ('sin_resultado', 2)) t loop
    if coalesce((m#>>array['por_resultado', v_k])::int, 0) <> coalesce((b.por_resultado->>v_k)::int, 0) + v_n then
      raise exception '1: por_resultado[%] esperaba % y trajo %', v_k, coalesce((b.por_resultado->>v_k)::int, 0) + v_n, m->'por_resultado';
    end if;
  end loop;
  select sum((h->>'llamadas')::int), sum((h->>'contestadas')::int) into v_n, v_c from jsonb_array_elements(m->'por_hora') h;
  if v_n is distinct from (m->>'llamadas')::int or v_c is distinct from (m->>'contestadas')::int then
    raise exception '1: por_hora no suma igual que el marcador (llamadas %, contestadas %): %', v_n, v_c, m;
  end if;
  if (m->>'primera_llamada_en')::timestamptz > (m->>'ultima_llamada_en')::timestamptz
     or (m->>'primera_llamada_en')::timestamptz > w.ini then
    raise exception '1: primera/ultima llamada: la de las 00:00 Lima (T13) debio ser la primera: %', m;
  end if;
  raise notice 'ORACULO: 1 analista en verde';

  -- 2. Su supervisor ve lo mismo en el día del analista y en la vista de equipo (marcador y cortes).
  perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.sup1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn(null, a.v1);
  if (r#>>'{marcador,llamadas}')::int is distinct from b.llamadas + 12 or (r#>>'{marcador,contestadas}')::int is distinct from b.contestadas + 8 then
    raise exception '2: el supervisor no ve las llamadas a clientes de su analista: %', r->'marcador';
  end if;
  r := crm.gestion_diaria_equipo_fn(w.hoy);
  select f into v_fila from jsonb_array_elements(r->'equipo') f where (f->>'analista_id')::uuid = a.v1;
  if v_fila is null or (v_fila#>>'{marcador,llamadas}')::int is distinct from b.llamadas + 12 or (v_fila#>>'{marcador,contestadas}')::int is distinct from b.contestadas + 8
     or v_fila->>'ultima_llamada_en' is null and v_fila#>>'{marcador,ultima_llamada_en}' is null then
    raise exception '2: la vista de equipo no trae las llamadas a clientes: %', v_fila;
  end if;
  -- Cortes de jornada: con una hora fija de la tarde (ambos cortes ya pasados) el primer corte del núcleo debe traer
  -- EXACTAMENTE la cuenta a mano de las llamadas de v1 (leads + clientes, misma regla) en su ventana, que es
  -- [inicio del DÍA Lima, primer corte) (gestion_diaria_cortes: v_ini = p_dia a medianoche). T17 (09:30 Lima, cliente,
  -- agendó reunión) y T13 (00:00 Lima) garantizan llamadas a clientes dentro de esa ventana.
  select f into v_fila from jsonb_array_elements(r#>'{cortes,equipo}') f where (f->>'analista_id')::uuid = a.v1;
  if v_fila is null then raise exception '2: los cortes de jornada no traen al analista: %', r->'cortes'; end if;
  reset role;
  select to_jsonb(x) into r from private.gestion_diaria_cortes(w.hoy, array[a.v1], (w.hoy + time '20:30') at time zone 'America/Lima') x;
  select f into v_fila from jsonb_array_elements(r->'equipo') f where (f->>'analista_id')::uuid = a.v1;
  if v_fila is null then raise exception '2: el nucleo de cortes no devolvio nada para v1: %', r; end if;
  with ventana as (
    select w.ini as ini, (r->>'primer_corte_en')::timestamptz as fin
  ), a_mano as (
    select x.id from crm.actividades x, ventana v
    where x.creado_por = a.v1 and x.tipo in ('llamada_realizada', 'llamada_no_contestada') and x.creado_en >= v.ini and x.creado_en < v.fin
    union all
    select g.id from crm.inversionista_gestiones g join crm.tareas t on t.id = g.tarea_id, ventana v
    where g.tipo = 'cierre' and g.creado_por = a.v1 and g.creado_en >= v.ini and g.creado_en < v.fin
      and coalesce(g.metadata->>'tipo_tarea', t.tipo) = 'llamada' and coalesce(g.metadata->>'estado', t.estado) = 'completada'
    union all
    select ac.id from crm.actividades_cliente ac left join crm.tareas t on t.id = ac.tarea_id, ventana v
    where ac.creado_por = a.v1 and ac.tipo in ('llamada_realizada', 'llamada_no_contestada') and ac.creado_en >= v.ini and ac.creado_en < v.fin
      and coalesce(t.estado, 'completada') = 'completada'
      and not exists (select 1 from crm.inversionista_gestiones g where g.tarea_id = ac.tarea_id and g.tipo = 'cierre')
  ) select coalesce(cardinality(array_agg(id)), 0) into v_n from a_mano;
  if v_n < 1 then raise exception '2: el fixture no dejo ninguna llamada dentro de la primera ventana de la jornada (%)', r - 'equipo'; end if;
  if (v_fila#>>'{primer_corte,llamadas}')::int is distinct from v_n then
    raise exception '2: el primer corte cuenta % y a mano salen % (ventana % → %): %', v_fila#>>'{primer_corte,llamadas}', v_n, w.ini, r->>'primer_corte_en', v_fila;
  end if;
  set local role authenticated;
  -- Paridad con el Registro de clientes: mismas 10 llamadas y 6 contestadas de clientes para v1 hoy.
  r := crm.gestiones_resumen_fn(w.hoy, w.hoy, array[a.v1]);
  if (r#>>'{totales,clientes,llamadas}')::int is distinct from b.llamadas_clientes + 11 or (r#>>'{totales,clientes,contestadas}')::int is distinct from b.contestadas_clientes + 7 then
    raise exception '2: el Registro de clientes y el marcador no cuentan lo mismo: %', r->'totales';
  end if;
  -- Otro equipo: la puerta lo niega.
  begin
    perform crm.gestion_diaria_analista_fn(null, a.v2);
    raise exception '2: el supervisor 1 leyo un analista del equipo 2';
  exception when insufficient_privilege then null;
  end;
  reset role;
  raise notice 'ORACULO: 2 supervisor en verde';

  -- 3. El ayudante es un espejo: filtra, nunca lanza.
  --    v2 pidiendo a v1 y a sí mismo: solo lo suyo (T14). sup2 pidiendo a v1: nada. v1 pidiendo a v2: nada suyo ajeno.
  perform set_config('request.jwt.claim.sub', a.v2::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select cardinality(array_agg(e.id)), cardinality(array_agg(e.id) filter (where e.vendedor_id = a.v1)) into v_n, v_c
    from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1, a.v2, null]) e;
  if coalesce(v_n, 0) <> 1 or coalesce(v_c, 0) <> 0 then raise exception '3: v2 vio % filas (% de v1); esperaba 1 y 0', v_n, v_c; end if;
  reset role;
  perform set_config('request.jwt.claim.sub', a.sup2::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.sup2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e;
  if coalesce(v_n, 0) <> 0 then raise exception '3: el supervisor 2 vio % llamadas a clientes de v1', v_n; end if;
  select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v2]) e;
  if coalesce(v_n, 0) <> 1 then raise exception '3: el supervisor 2 debio ver la unica de su analista (vio %)', v_n; end if;
  reset role;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select cardinality(array_agg(e.id)), cardinality(array_agg(e.id) filter (where e.vendedor_id <> a.v1)) into v_n, v_c
    from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1, a.v2]) e;
  if coalesce(v_n, 0) <> b.llamadas_clientes + 11 or coalesce(v_c, 0) <> 0 then raise exception '3: v1 vio % filas (% ajenas)', v_n, v_c; end if;
  reset role; -- las comprobaciones fila a fila cruzan tablas privadas: como postgres, con la identidad de v1 (el ayudante lee auth.uid())
  -- Clasificación fila a fila (T7 número errado: no contestada y no útil; T11 sin resultado: realizada y no útil; A1 legado: contacto).
  if not exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
                 join crm.inversionista_gestiones g on g.id = e.id where g.tarea_id = (select v from o_ids where k = 'T7')
                   and e.tipo = 'llamada_no_contestada' and e.util is false and e.resultado = 'numero_errado')
     or not exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
                 join crm.inversionista_gestiones g on g.id = e.id where g.tarea_id = (select v from o_ids where k = 'T11')
                   and e.tipo = 'llamada_realizada' and e.util is false and e.resultado = 'sin_resultado')
     or not exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
                 join crm.actividades_cliente ac on ac.id = e.id where ac.detalle = 'Oraculo A1 legado'
                   and e.tipo = 'llamada_realizada' and e.util is true)
     or exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
                 join crm.actividades_cliente ac on ac.id = e.id where ac.detalle = 'Oraculo A2 espejo')
     or exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
                 join crm.actividades_cliente ac on ac.id = e.id where ac.detalle = 'Oraculo A3 pendiente')
     or exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e
                 join crm.inversionista_gestiones g on g.id = e.id where g.tarea_id in (select v from o_ids where k in ('T8', 'T9', 'T10', 'T12', 'T16'))) then
    raise exception '3: la clasificacion fila a fila no es la esperada';
  end if;
  if exists (select 1 from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e where e.lead_id is not null) then
    raise exception '3: una llamada a cliente trae lead_id';
  end if;
  reset role;
  raise notice 'ORACULO: 3 espejo de visibilidad en verde';

  -- 4. Gerencia ve a los dos; Pulso y Hábitos ejecutan.
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1, a.v2]) e;
  if coalesce(v_n, 0) <> b.llamadas_clientes + 12 then raise exception '4: gerencia vio % (esperaba %)', v_n, b.llamadas_clientes + 12; end if;
  r := crm.gestion_diaria_analista_fn(null, a.v1);
  if (r#>>'{marcador,llamadas}')::int is distinct from b.llamadas + 12 then raise exception '4: gerencia no ve el dia de v1 completo: %', r->'marcador'; end if;
  r := crm.gestion_diaria_pulso_fn(w.hoy);
  if r is null or r->'generado_en' is null and r->'dia' is null then raise exception '4: pulso vacio: %', r; end if;
  r := crm.gestion_diaria_habitos_fn(w.hoy, 7);
  if r is null then raise exception '4: habitos vacio'; end if;
  reset role;
  raise notice 'ORACULO: 4 gerencia, pulso y habitos en verde';

  -- 5. Sin sesión: nada. Con la postventa apagada: las llamadas a clientes desaparecen del marcador.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e;
  if coalesce(v_n, 0) <> 0 then raise exception '5: sin sesion el ayudante devolvio % filas', v_n; end if;
  alter table crm.multiempresa_flags disable trigger user;
  update crm.multiempresa_flags set activo = false, actualizado_por = null where nombre = 'postventa_neutral'; -- actualizado_por: la copia de configuración trae un perfil que no existe en el banco
  alter table crm.multiempresa_flags enable trigger user;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn();
  reset role;
  -- Como en el Registro: la bandera apaga los cierres F6 pero NO el legado (A1 sigue contando).
  if (r#>>'{marcador,llamadas}')::int <> b.llamadas_leads + 1 + 1 then
    raise exception '5: con la postventa apagada el marcador debio traer leads + legado (%): %', b.llamadas_leads + 2, r->'marcador';
  end if;
  alter table crm.multiempresa_flags disable trigger user;
  update crm.multiempresa_flags set activo = true, actualizado_por = null where nombre = 'postventa_neutral';
  update crm.multiempresa_flags set activo = false, actualizado_por = null where nombre = 'ficha_360_neutral';
  alter table crm.multiempresa_flags enable trigger user;
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn();
  reset role;
  if (r#>>'{marcador,llamadas}')::int <> b.llamadas_leads + 2 then
    raise exception '5: con ficha_360 apagada el marcador debio traer leads + legado: %', r->'marcador';
  end if;
  alter table crm.multiempresa_flags disable trigger user;
  update crm.multiempresa_flags set activo = true, actualizado_por = null where nombre = 'ficha_360_neutral';
  alter table crm.multiempresa_flags enable trigger user;
  raise notice 'ORACULO: 5 sin sesion y bandera en verde';

  -- 5b. v1 dado de baja (cirugía): sin acceso al CRM no ve nada; su supervisor sigue viendo el histórico del miembro inactivo.
  alter table crm.equipo disable trigger user;
  update crm.equipo set activo = false where perfil_id = a.v1;
  alter table crm.equipo enable trigger user;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e;
  if coalesce(v_n, 0) <> 0 then raise exception '5b: v1 inactivo vio % llamadas a clientes', v_n; end if;
  perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.sup1, 'role', 'authenticated')::text, true);
  select cardinality(array_agg(e.id)) into v_n from private.gestion_diaria_llamadas_clientes_eventos(w.ini, w.fin, array[a.v1]) e;
  if coalesce(v_n, 0) <> b.llamadas_clientes + 11 then raise exception '5b: el supervisor dejo de ver el historico de su analista inactivo (%)', v_n; end if;
  alter table crm.equipo disable trigger user;
  update crm.equipo set activo = true where perfil_id = a.v1;
  alter table crm.equipo enable trigger user;
  raise notice 'ORACULO: 5b actor inactivo en verde';

  -- 6. Todo lo anterior otra vez en modo SOLO LECTURA (como PostgREST corre las puertas STABLE): mismas cifras, sin error.
  set local transaction_read_only = on;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_analista_fn();
  reset role;
  if (r#>>'{marcador,llamadas}')::int is distinct from b.llamadas + 12 or (r#>>'{marcador,contestadas}')::int is distinct from b.contestadas + 8 then
    raise exception '6: en solo lectura el marcador cambio: %', r->'marcador';
  end if;
  perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.sup1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_equipo_fn(w.hoy);
  reset role;
  select f into v_fila from jsonb_array_elements(r->'equipo') f where (f->>'analista_id')::uuid = a.v1;
  if (v_fila#>>'{marcador,llamadas}')::int is distinct from b.llamadas + 12 then raise exception '6: en solo lectura la vista de equipo cambio: %', v_fila->'marcador'; end if;
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := crm.gestion_diaria_pulso_fn(w.hoy);
  r := crm.gestion_diaria_habitos_fn(w.hoy, 7);
  reset role;
  raise notice 'ORACULO: 6 solo lectura en verde';
end $lecturas$;

select 'GESTION_DIARIA_LLAMADAS_CLIENTES_OK' as resultado;
rollback;

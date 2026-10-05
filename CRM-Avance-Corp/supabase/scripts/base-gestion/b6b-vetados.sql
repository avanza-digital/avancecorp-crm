-- B6b · «Ver no contactar» y detalle de las cifras del resumen, en el banco (UNA transacción, impersonación, ROLLBACK al
-- final). Falla el proceso si hay un FAIL. Corre sobre un banco con B6b (20261004045038) aplicada y los actores de seed:demo
-- (el banco del gate: se buscan por correo). Siembra 12 leads transitorios b6b00000-… que se deshacen con el ROLLBACK.
-- Qué prueba: con false la lista es la de B5 (contra una COPIA EXACTA de su cuerpo vivo, md5 b2629fba…), para cada actor,
-- en filas y orden; null = false; quién no pide los vetados (analista, coordinación, directorio → 42501); Supervisión ve los
-- de su ámbito con la marca (cuándo, motivo, quién; NULL si lo último fue «levantar» o si la marca vino de otro lead), los
-- vetados en descanso, al final y fuera de «Llamar hoy»; otro equipo no (P0002 con su analista); Gerencia ve todos; el
-- resumen no cuenta vetados; levantar la marca devuelve el lead a su analista; la detalle de cada cifra da tantas filas como
-- el resumen para TODO analista (Supervisión y Gerencia), atribuida al dueño, más reciente primero, con autor, «sigue en
-- base» y los leads retirados sin nombre. r1/r2 (auditor-rls y Codex, 04/10): evento vigente de la persona con EJECUCIÓN REAL
-- de marcar_no_contactar, levantar_no_contactar y postventa_veto_fn (sesiones de usuario: el servidor sella con
-- clock_timestamp): contraejemplos de Codex (postventa → levantar → re-vetar; marcar → levantar → marcar en una
-- transacción), persona por enlace, puente y DNI suelto, evento en un lead de otro equipo (NULL para S1, completo para
-- Gerencia), veto solo del lead, postventa vigente, bandeja, reactivación de un lead retirado y Supervisión/Gerencia
-- DESACTIVADAS → 42501. Enciende y apaga la bandera resolver_en_puertas y neutraliza la compuerta de cobertura de la cartera
-- (private.cartera_f5_exigir) dentro de la transacción (ROLLBACK).
-- Mutantes: `node supabase/scripts/base-gestion/b6b-mutantes.mjs --puerto <puerto del banco local>` inyecta cada uno en la
-- línea @@MUTANTE@@ y exige que esta suite FALLE.
\set ON_ERROR_STOP on
-- Solo banco LOCAL (P3 del auditor-rls de B6b; añadido con B6c): el secreto JWT de la base tiene que ser el valor de
-- desarrollo PÚBLICO del Supabase CLI (se compara su md5; un proyecto alojado tiene el suyo) y la conexión no va por SSL.
-- La suite cambia la bandera resolver_en_puertas y neutraliza private.cartera_f5_exigir dentro de su transacción.
do $solo_banco_local$
begin
  if (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646'
      and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid())) is not true then
    raise exception 'b6b-vetados: solo corre en un banco LOCAL de Docker (Supabase CLI); esta base no lo es';
  end if;
end $solo_banco_local$;
begin;
-- @@MUTANTE@@
-- Copia EXACTA del cuerpo vivo de B5 (20261003162400) en pg_temp: el oráculo de «con false, lo mismo que B5».
create function pg_temp.b5_obtener(p_vendedor_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(lead_id uuid, nombre_completo text, telefono text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, dias_desde_descarte integer, etapa_maxima text, intentos integer, ultimo_resultado text, ultimo_intento_en timestamp with time zone, proxima_llamada_en timestamp with time zone, rellamada_hoy boolean, enfriado_hasta date, ciclo_n integer, vendedor_id uuid, gestiona text, recibido_en timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v_rol := private.base_gestion_rol(v_uid);
  if p_vendedor_id is not null then
    if v_rol = 'vendedor' and p_vendedor_id <> v_uid then
      raise exception 'Un analista solo consulta su propia base' using errcode = '42501';
    end if;
    if v_rol = 'supervisor' and p_vendedor_id not in (select private.vendedor_ids_visibles(v_uid)) then
      raise exception 'Analista no encontrado o fuera de tu ambito' using errcode = 'P0002';
    end if;
  end if;
  return query
  with base as (
    select l.id, l.nombre_completo, l.telefono, l.distrito, l.origen, l.categoria_interes, l.monto_estimado, l.moneda,
           l.motivo_descarte, l.descartado_en, l.proxima_llamada_en, l.enfriado_hasta, l.ciclo_actual, l.vendedor_id,
           coalesce(l.tenencia_desde, l.creado_en) as recibido_en,  -- B5: cuando le llego el lead a quien lo tiene (el MES del lead)
           private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
    from crm.leads l
    where l.activo and l.etapa = 'descartado' and not l.no_contactar
      and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)
      and private.base_gestion_lead_visible(v_uid, v_rol, l.vendedor_id, l.asignado_supervisor_id)
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
  ),
  intentos as (
    -- B3c: contador, último resultado (desempate por intento_n, Codex B3 #5) y último intento salen de la MISMA definición
    -- que usan el núcleo y el enfriamiento: private.base_gestion_intentos_ciclo, con la ventana D13 de cada lead.
    select c.lead_id, c.n, c.ultimo, c.ultimo_en
    from (select array_agg(b.id order by b.id) as ids, array_agg(b.desde order by b.id) as desdes from base b) q
    cross join lateral private.base_gestion_intentos_ciclo(q.ids, q.desdes) c
  ),
  ciclo as (
    -- El ciclo vigente empieza en la ultima reapertura (cambio_etapa descartado → nuevo) o, si nunca hubo, al inicio.
    -- Se acota con el propio historial (misma fuente y mismo reloj que los cambios de etapa): robusto frente a
    -- transacciones multi-sentencia, donde now() del log y statement_timestamp() del ledger difieren.
    select b.id as lead_id,
           coalesce((select max(a.creado_en) from crm.actividades a
                      where a.lead_id = b.id and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_anterior' = 'descartado'),
                    '-infinity'::timestamptz) as desde
    from base b
  ),
  etapas as (
    select a.lead_id,
           max(greatest(private.base_gestion_etapa_rango(a.metadata->>'etapa_anterior'),
                        private.base_gestion_etapa_rango(case when a.metadata->>'etapa_nueva' <> 'descartado' then a.metadata->>'etapa_nueva' end))) as rango
    from crm.actividades a join ciclo c on c.lead_id = a.lead_id
    where a.tipo = 'cambio_etapa' and a.creado_en >= c.desde
      -- Codex B3 #6: el descarte del ciclo anterior puede compartir instante con la reapertura (misma transaccion): fuera.
      and not (a.creado_en = c.desde and a.metadata->>'etapa_nueva' = 'descartado')
    group by a.lead_id
  )
  select b.id, b.nombre_completo, b.telefono, b.distrito, b.origen, b.categoria_interes, b.monto_estimado, b.moneda,
         b.motivo_descarte, b.descartado_en,
         case when b.descartado_en is null then null else (v_hoy - (b.descartado_en at time zone 'America/Lima')::date)::integer end,
         case coalesce(e.rango, 0) when 1 then 'nuevo' when 2 then 'contactado' when 3 then 'reunion_agendada'
                                   when 4 then 'propuesta_enviada' when 5 then 'convertido' else 'sin_datos' end,
         coalesce(i.n, 0), i.ultimo, i.ultimo_en,
         b.proxima_llamada_en,
         (b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),
         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo, b.recibido_en
  from base b
  left join intentos i on i.lead_id = b.id
  left join etapas e on e.lead_id = b.id
  left join public.perfiles p on p.id = b.vendedor_id
  -- Contrato (encargo): rellamada vencida o de hoy → etapa maxima (desc) → dias desde el descarte (asc); la hora de la
  -- rellamada solo desempata (Codex B3 #4).
  order by (b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy) desc,
           coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone 'America/Lima')::date desc nulls last,  -- menos dias desde el descarte primero
           b.proxima_llamada_en asc nulls last,
           b.id;
end;
$function$;

-- ───────── Utilidades (todo en pg_temp: se va con el ROLLBACK) ─────────
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
grant execute on function pg_temp.sesion(uuid) to authenticated;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$ insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
grant execute on function pg_temp.caso(text,text,text) to authenticated;
create function pg_temp.err(p_caso text, p_esperado text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform pg_temp.caso(p_caso, p_esperado, 'paso'); exception when others then perform pg_temp.caso(p_caso, p_esperado, sqlstate || ' ' || sqlerrm); end $$;
grant execute on function pg_temp.err(text,text,text) to authenticated;
grant execute on function pg_temp.b5_obtener(uuid) to authenticated;

-- Huella de una lista (filas + orden). h5: la copia de B5; h6: B6b proyectada a las columnas de B5; h6t: B6b entera.
create function pg_temp.h5(p uuid) returns text language sql as $$
  select count(*) || ':' || coalesce(md5(string_agg(row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda, t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado, t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona, t.recibido_en)::text, '|' order by t.ordinality)), '-')
    from pg_temp.b5_obtener(p) with ordinality t $$;
create function pg_temp.h6(p uuid, v boolean) returns text language sql as $$
  select count(*) || ':' || coalesce(md5(string_agg(row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda, t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado, t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona, t.recibido_en)::text, '|' order by t.ordinality)), '-')
    from crm.obtener_base_gestion(p, v) with ordinality t $$;
create function pg_temp.h6t(p uuid, v boolean) returns text language plpgsql as $$
declare x text;
begin
  -- Un rechazo no tumba la suite: queda como «error <sqlstate>» y el caso falla donde debe (un mutante cae en SU caso).
  select count(*) || ':' || coalesce(md5(string_agg(t::text, '|' order by t.ordinality)), '-') into x from crm.obtener_base_gestion(p, v) with ordinality t;
  return x;
exception when others then return 'error ' || sqlstate;
end $$;
-- Una fila de la lista del actor: «no_contactar|en|motivo|por|rellamada_hoy».
create function pg_temp.fila(p_lead uuid, p_vet boolean, p_v uuid default null) returns text language sql as $$
  select coalesce((select format('%s|%s|%s|%s|%s', t.no_contactar::text, coalesce(to_char(t.no_contactar_en at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), '-'),
                                 coalesce(t.no_contactar_motivo, '-'), coalesce(t.no_contactar_por, '-'), t.rellamada_hoy::text)
                     from crm.obtener_base_gestion(p_v, p_vet) t where t.lead_id = p_lead), 'sin fila') $$;
grant execute on function pg_temp.h5(uuid), pg_temp.h6(uuid,boolean), pg_temp.h6t(uuid,boolean), pg_temp.fila(uuid,boolean,uuid) to authenticated;

-- ───────── Actores (seed:demo) y leads transitorios ─────────
create temp table f as select
  (select id from auth.users where email = 'vend1.crm@demo.avancecorp.pe') v1,
  (select id from auth.users where email = 'vend2.crm@demo.avancecorp.pe') v2,
  (select id from auth.users where email = 'vend3.crm@demo.avancecorp.pe') v3,
  (select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe') s1,
  (select id from auth.users where email = 'sup2.crm@demo.avancecorp.pe') s2,
  (select id from auth.users where email = 'gerencia.crm@demo.avancecorp.pe') g,
  (select id from auth.users where email = 'coordinador.crm@demo.avancecorp.pe') k,
  (select id from auth.users where email = 'directorio.crm@demo.avancecorp.pe') d,
  (now() at time zone 'America/Lima')::date hoy,
  -- vetados: a*; limpios: b*; otro equipo: c*
  'b6b00000-0000-4000-8000-0000000000a1'::uuid lv,   -- V1, vetado por su analista (marca completa)
  'b6b00000-0000-4000-8000-0000000000a2'::uuid lvd,  -- V1, vetado y en descanso
  'b6b00000-0000-4000-8000-0000000000a3'::uuid lvp,  -- V1, vetado sin actividad (la marca vino de otro lead de la persona)
  'b6b00000-0000-4000-8000-0000000000a4'::uuid lvl,  -- V1, marcado, levantado y re-vetado sin actividad propia
  'b6b00000-0000-4000-8000-0000000000a5'::uuid lvr,  -- V1, vetado con rellamada de hoy
  'b6b00000-0000-4000-8000-0000000000b1'::uuid l1,   -- V1, limpio
  'b6b00000-0000-4000-8000-0000000000b2'::uuid l2,   -- V2, limpio (equipo de S1)
  'b6b00000-0000-4000-8000-0000000000b3'::uuid lr,   -- V1, limpio con rellamada de hoy
  'b6b00000-0000-4000-8000-0000000000b4'::uuid lde,  -- V1, limpio en descanso (fuera siempre)
  'b6b00000-0000-4000-8000-0000000000b5'::uuid lx,   -- V1, con intento de hoy y luego retirado (soft-delete)
  'b6b00000-0000-4000-8000-0000000000b6'::uuid lm,   -- V1, reactivado el mes pasado
  'b6b00000-0000-4000-8000-0000000000c1'::uuid l3v;  -- V3 (equipo de S2), vetado
alter table f add column n_v1 text, add column n_s1 text, add column n_v3 text;
update f set n_v1 = (select nombre_completo from public.perfiles where id = f.v1), n_s1 = (select nombre_completo from public.perfiles where id = f.s1), n_v3 = (select nombre_completo from public.perfiles where id = f.v3);
grant select on f to authenticated;
do $$ begin
  if (select v1 is null or v2 is null or v3 is null or s1 is null or s2 is null or g is null or k is null or d is null from f) then
    raise exception 'b6b-vetados: faltan actores de seed:demo en este banco (correr el gate o seed:demo antes)';
  end if;
  if exists (select 1 from crm.leads where id::text like 'b6b00000-%') then
    raise exception 'b6b-vetados: ya hay leads b6b00000-… en el banco';
  end if;
end $$;
select pg_temp.sesion(null);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, 'oficina', 'nuevo', x.v, 1000, 'PEN', x.v, true
  from f, lateral (values
    (f.lv,  'B6B VETADO COMPLETO',   '966600101', f.v1), (f.lvd, 'B6B VETADO EN DESCANSO', '966600102', f.v1),
    (f.lvp, 'B6B VETADO POR PERSONA', '966600103', f.v1), (f.lvl, 'B6B VETADO RELEVANTADO', '966600104', f.v1),
    (f.lvr, 'B6B VETADO CON RELLAMADA', '966600105', f.v1), (f.l1, 'B6B LIMPIO UNO', '966600106', f.v1),
    (f.l2,  'B6B LIMPIO DOS',         '966600107', f.v2), (f.lr, 'B6B LIMPIO RELLAMADA', '966600108', f.v1),
    (f.lde, 'B6B LIMPIO EN DESCANSO', '966600109', f.v1), (f.lx, 'B6B RETIRADO', '966600110', f.v1),
    (f.lm,  'B6B REACTIVADO MES PASADO', '966600111', f.v1), (f.l3v, 'B6B VETADO OTRO EQUIPO', '966600112', f.v3)) x(id, nombre, tel, v);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id::text like 'b6b00000-%';
-- Vetos por la puerta, cada uno con SU analista.
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.marcar_no_contactar((select lv from f), 'pidió que no lo llamen');
select crm.marcar_no_contactar((select lvd from f), 'vetado y en descanso');
select crm.marcar_no_contactar((select lvl from f), 'marca vieja');
select crm.marcar_no_contactar((select lvr from f), 'vetado con rellamada');
reset role;
select pg_temp.sesion((select v3 from f)); set local role authenticated;
select crm.marcar_no_contactar((select l3v from f), 'otro equipo');
reset role;
-- LVL: la marca vieja (−10 min), Supervisión la levanta (−5 min) y la persona lo vuelve a vetar desde OTRO lead (sin
-- actividad en este): lo último del propio lead es «levantar» → la marca va NULL.
select pg_temp.sesion(null);
update crm.actividades set creado_en = creado_en - interval '10 minutes' where lead_id = (select lvl from f) and metadata->>'evento' = 'no_contactar';
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select crm.levantar_no_contactar((select lvl from f), 'se levanta para la prueba');
reset role;
select pg_temp.sesion(null);
update crm.actividades set creado_en = creado_en - interval '5 minutes' where lead_id = (select lvl from f) and metadata->>'accion' = 'levantar';
select set_config('crm.op_privilegiada', 'on', true);
update crm.leads set no_contactar = true where id in ((select lvl from f), (select lvp from f));
select set_config('crm.op_privilegiada', 'off', true);
-- Descanso y rellamada de hoy (00:01 Lima de hoy: siempre «de hoy»), bajo el GUC del núcleo (el sello solo deja escribir al núcleo).
select set_config('crm.op_base_gestion', 'on', true);
update crm.leads set enfriado_hasta = (select hoy + 10 from f) where id in ((select lvd from f), (select lde from f));
update crm.leads set proxima_llamada_en = ((select hoy from f)::timestamp at time zone 'America/Lima') + interval '1 minute' where id in ((select lr from f), (select lvr from f));
select set_config('crm.op_base_gestion', 'off', true);
create temp table e as select
  (select to_char(a.creado_en at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') from crm.actividades a, f where a.lead_id = f.lv and a.metadata->>'accion' = 'marcar') lv_en;
grant select on e to authenticated;
select pg_temp.caso('banco: 12 leads transitorios descartados, 6 vetados', '12/6',
  (select count(*) filter (where etapa = 'descartado') || '/' || count(*) filter (where no_contactar) from crm.leads where id::text like 'b6b00000-%'));

-- ───────── Contrato (catálogo) ─────────
select pg_temp.caso('la copia de B5 es exacta (md5 del cuerpo vivo de B5)', 'b2629fba517938457b64cdbc5856ee82', (select md5(prosrc) from pg_proc where oid = 'pg_temp.b5_obtener(uuid)'::regprocedure));
select pg_temp.caso('obtener_base_gestion: una sola sobrecarga (uuid, boolean)', '1|true', (select count(*) || '|' || bool_and(oid = 'crm.obtener_base_gestion(uuid,boolean)'::regprocedure) from pg_proc where proname = 'obtener_base_gestion' and pronamespace = 'crm'::regnamespace));
select pg_temp.caso('ACL exacta, DEFINER de postgres, search_path vacío (las dos)', '2',
  (select count(*)::text from pg_proc p where p.oid in ('crm.obtener_base_gestion(uuid,boolean)'::regprocedure, 'crm.base_gestion_resumen_detalle(uuid,text)'::regprocedure)
     and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]));
select pg_temp.caso('anon y service_role sin EXECUTE (las dos)', 'false',
  (select bool_or(has_function_privilege(r, f, 'EXECUTE'))::text from unnest(array['anon','service_role']) r, unnest(array['crm.obtener_base_gestion(uuid,boolean)','crm.base_gestion_resumen_detalle(uuid,text)']) f));
select pg_temp.caso('fuera del censo analítico (las dos)', '0',
  (select count(*)::text from private.contadores_crudos_leads_citas() c where c.objeto in ('crm.obtener_base_gestion(uuid,boolean)', 'crm.base_gestion_resumen_detalle(uuid,text)')));

-- ───────── Con false = B5, para cada actor (filas y orden); null = false; columnas nuevas vacías ─────────
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso('V1: false = B5', pg_temp.h5(null), pg_temp.h6(null, false));
select pg_temp.caso('V1: (V1, false) = B5 (V1)', pg_temp.h5((select v1 from f)), pg_temp.h6((select v1 from f), false));
select pg_temp.caso('V1: null = false (todas las columnas)', pg_temp.h6t(null, false), pg_temp.h6t(null, null));
select pg_temp.caso('V1: sin parámetro = false', pg_temp.h6t(null, false), (select count(*) || ':' || coalesce(md5(string_agg(t::text, '|' order by t.ordinality)), '-') from crm.obtener_base_gestion() with ordinality t));
select pg_temp.caso('V1: sus filas traen no_contactar=false y la marca vacía', '0', (select count(*)::text from crm.obtener_base_gestion() t where t.no_contactar or t.no_contactar_en is not null or t.no_contactar_motivo is not null or t.no_contactar_por is not null));
select pg_temp.caso('V1: no ve ninguno de sus vetados', '0', (select count(*)::text from crm.obtener_base_gestion() t, f where t.lead_id in (f.lv, f.lvd, f.lvp, f.lvl, f.lvr)));
reset role;
select pg_temp.sesion((select v2 from f)); set local role authenticated;
select pg_temp.caso('V2: false = B5', pg_temp.h5(null), pg_temp.h6(null, false));
reset role;
select pg_temp.sesion((select v3 from f)); set local role authenticated;
select pg_temp.caso('V3: false = B5', pg_temp.h5(null), pg_temp.h6(null, false));
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: false = B5', pg_temp.h5(null), pg_temp.h6(null, false));
select pg_temp.caso('S1: (V1, false) = B5 (V1)', pg_temp.h5((select v1 from f)), pg_temp.h6((select v1 from f), false));
select pg_temp.caso('S1: null = false', pg_temp.h6t(null, false), pg_temp.h6t(null, null));
reset role;
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: false = B5', pg_temp.h5(null), pg_temp.h6(null, false));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.caso('G: false = B5', pg_temp.h5(null), pg_temp.h6(null, false));
select pg_temp.caso('G: (V3, false) = B5 (V3)', pg_temp.h5((select v3 from f)), pg_temp.h6((select v3 from f), false));
select pg_temp.caso('G: null = false', pg_temp.h6t(null, false), pg_temp.h6t(null, null));
select pg_temp.caso('G: la lista de B5 no es trivial (≥ 5 filas: los limpios transitorios)', 'ok', case when split_part(pg_temp.h5(null), ':', 1)::int >= 5 then 'ok' else pg_temp.h5(null) end);
reset role;

-- ───────── Quién NO pide los vetados ─────────
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('V1 pide los vetados → 42501', '42501 Solo Supervision y Gerencia ven los leads marcados No contactar', 'select count(*) from crm.obtener_base_gestion(null, true)');
select pg_temp.err('V1 pide los vetados de su propia base → 42501', '42501 Solo Supervision y Gerencia ven los leads marcados No contactar', format('select count(*) from crm.obtener_base_gestion(%L, true)', (select v1 from f)));
reset role;
select pg_temp.sesion((select k from f)); set local role authenticated;
select pg_temp.err('Coordinación pide los vetados → 42501', '42501 La base para gestion es para analistas, Supervision y Gerencia', 'select count(*) from crm.obtener_base_gestion(null, true)');
reset role;
select pg_temp.sesion((select d from f)); set local role authenticated;
select pg_temp.err('Directorio pide los vetados → 42501', '42501 La base para gestion es para analistas, Supervision y Gerencia', 'select count(*) from crm.obtener_base_gestion(null, true)');
reset role;

-- ───────── Supervisión 1 con los vetados ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: LV con marca completa (cuándo, motivo, quién), fuera de «Llamar hoy»',
  (select format('true|%s|pidió que no lo llamen|%s|false', e.lv_en, f.n_v1) from e, f), pg_temp.fila((select lv from f), true));
select pg_temp.caso('S1: sin pedirlos no ve LV', 'sin fila', pg_temp.fila((select lv from f), false));
select pg_temp.caso('S1: LVD (vetado en descanso) se ve', (select format('true|%s|vetado y en descanso|%s|false', '*', f.n_v1) from f),
  regexp_replace(pg_temp.fila((select lvd from f), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.caso('S1: LDE (no vetado en descanso) no se ve ni con vetados', 'sin fila', pg_temp.fila((select lde from f), true));
select pg_temp.caso('S1: LVP (marca de otro lead de la persona) → marca NULL', 'true|-|-|-|false', pg_temp.fila((select lvp from f), true));
select pg_temp.caso('S1: LVL (lo último del lead fue «levantar») → marca NULL', 'true|-|-|-|false', pg_temp.fila((select lvl from f), true));
select pg_temp.caso('S1: LVR (vetado con rellamada de hoy) → rellamada_hoy false', 'false', split_part(pg_temp.fila((select lvr from f), true), '|', 5));
select pg_temp.caso('S1: LR (limpio con rellamada de hoy) → rellamada_hoy true', 'true', split_part(pg_temp.fila((select lr from f), true), '|', 5));
select pg_temp.caso('S1: «Llamar hoy» primero (ninguna fila con rellamada_hoy después de una sin ella)', 'ok',
  (select case when coalesce(max(t.ordinality) filter (where t.rellamada_hoy), 0) < coalesce(min(t.ordinality) filter (where not t.rellamada_hoy), 1e9) then 'ok' else 'mezclado' end
     from crm.obtener_base_gestion(null, true) with ordinality t));
select pg_temp.caso('S1: los vetados van al final', 'ok',
  (select case when max(t.ordinality) filter (where not t.no_contactar) < min(t.ordinality) filter (where t.no_contactar) then 'ok' else 'mezclado' end
     from crm.obtener_base_gestion(null, true) with ordinality t));
select pg_temp.caso('S1: con true = la lista sin vetados + los vetados, en ese orden', pg_temp.h6t(null, false),
  (select count(*) || ':' || coalesce(md5(string_agg(t::text, '|' order by t.ordinality)), '-') from crm.obtener_base_gestion(null, true) with ordinality t where not t.no_contactar));
select pg_temp.caso('S1: no ve el vetado del otro equipo (L3V)', 'sin fila', pg_temp.fila((select l3v from f), true));
select pg_temp.caso('S1: (V1, true) trae solo los de V1, con sus 5 vetados', 'ok|5',
  (select case when bool_and(t.vendedor_id = f.v1) then 'ok' else 'ajenos' end || '|' || count(*) filter (where t.no_contactar and t.lead_id::text like 'b6b00000-%') from crm.obtener_base_gestion((select v1 from f), true) t, f));
select pg_temp.err('S1 pide los vetados de V3 (otro equipo) → P0002', 'P0002 Analista no encontrado o fuera de tu ambito', format('select count(*) from crm.obtener_base_gestion(%L, true)', (select v3 from f)));
reset role;
-- Ámbito: como postgres CON la sesión de S1 (auth.uid() = S1), para leer su subárbol.
select pg_temp.caso('S1: con true no trae NADA fuera de su ámbito', '0',
  (select count(*)::text from crm.obtener_base_gestion(null, true) t
    where t.vendedor_id is distinct from null and t.vendedor_id not in (select private.vendedor_ids_visibles((select s1 from f)))));
select pg_temp.caso('S1: true − false = exactamente los vetados descartados vivos de su ámbito',
  (select count(*)::text from crm.leads l where l.activo and l.etapa = 'descartado' and l.no_contactar
      and (l.vendedor_id in (select private.vendedor_ids_visibles((select s1 from f)))
           or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select s1 from f)))))),
  ((select count(*) from crm.obtener_base_gestion(null, true)) - (select count(*) from crm.obtener_base_gestion(null, false)))::text);

-- ───────── Supervisión 2 y Gerencia ─────────
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: con true no ve ningún lead de V1', '0', (select count(*)::text from crm.obtener_base_gestion(null, true) t, f where t.lead_id in (f.lv, f.lvd, f.lvp, f.lvl, f.lvr, f.l1, f.lr)));
select pg_temp.caso('S2: con true ve el vetado de su equipo (L3V) con su marca', (select format('true|*|otro equipo|%s|false', f.n_v3) from f),
  regexp_replace(pg_temp.fila((select l3v from f), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.err('S2 pide los vetados de V1 → P0002', 'P0002 Analista no encontrado o fuera de tu ambito', format('select count(*) from crm.obtener_base_gestion(%L, true)', (select v1 from f)));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.caso('G: con true = la lista sin vetados + los vetados al final', pg_temp.h6t(null, false),
  (select count(*) || ':' || coalesce(md5(string_agg(t::text, '|' order by t.ordinality)), '-') from crm.obtener_base_gestion(null, true) with ordinality t where not t.no_contactar));
select pg_temp.caso('G: ve los 6 vetados transitorios (también los de otro equipo y en descanso)', '6', (select count(*)::text from crm.obtener_base_gestion(null, true) t where t.lead_id::text like 'b6b00000-%' and t.no_contactar));
reset role;
select pg_temp.sesion((select g from f));
select pg_temp.caso('G: true − false = TODOS los vetados descartados vivos', (select count(*)::text from crm.leads where activo and etapa = 'descartado' and no_contactar),
  ((select count(*) from crm.obtener_base_gestion(null, true)) - (select count(*) from crm.obtener_base_gestion(null, false)))::text);

-- ───────── El resumen no cuenta vetados ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1 resumen de V1: en base = su lista sin vetados (y no con vetados)',
  (select count(*) || '≠' || (select count(*) from crm.obtener_base_gestion((select v1 from f), true)) from crm.obtener_base_gestion((select v1 from f), false)),
  (select r.en_base || '≠' || (select count(*) from crm.obtener_base_gestion((select v1 from f), true)) from crm.base_gestion_resumen() r, f where r.vendedor_id = f.v1));
select pg_temp.caso('S1 resumen de V1: rellamadas de hoy = las de su lista (LR sí, LVR no)',
  (select count(*) filter (where t.rellamada_hoy)::text from crm.obtener_base_gestion((select v1 from f), false) t),
  (select r.rellamadas_hoy::text from crm.base_gestion_resumen() r, f where r.vendedor_id = f.v1));
select pg_temp.caso('S1 resumen de V1: con vetados habría más (la prueba no es trivial)', 'true',
  ((select count(*) from crm.obtener_base_gestion((select v1 from f), true)) > (select count(*) from crm.obtener_base_gestion((select v1 from f), false)))::text);
reset role;

-- ───────── Supervisión levanta la marca: el lead vuelve a la base de su analista ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select crm.levantar_no_contactar((select lv from f), 'volvió a pedir información');
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso('V1: tras levantar la marca, LV vuelve a su base sin marca', 'false|-|-|-|false', pg_temp.fila((select lv from f), false));
reset role;

-- ───────── Detalle de las cifras ─────────
-- Intentos: V1 sobre L1 (−3 s) y sobre LX (−1 s, luego retirado); uno de AYER sobre L1 (no cuenta hoy); S1 sobre L2 (de V2, −2 s).
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.registrar_intento_base('b6b00000-0000-4000-8000-0000000000e0', (select l1 from f), 'no_contesto', 'de ayer');
reset role;
select pg_temp.sesion(null);
update crm.actividades set creado_en = creado_en - interval '1 day' where id = 'b6b00000-0000-4000-8000-0000000000e0';
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.registrar_intento_base('b6b00000-0000-4000-8000-0000000000e1', (select l1 from f), 'no_contesto', null);
select crm.registrar_intento_base('b6b00000-0000-4000-8000-0000000000e2', (select lx from f), 'numero_errado', null);
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select crm.registrar_intento_base('b6b00000-0000-4000-8000-0000000000e3', (select l2 from f), 'no_interesado', 'lo llamó Supervisión');
reset role;
-- Reactivaciones: LM el mes pasado (−40 días), L1 hoy.
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.reactivar_lead_base('b6b00000-0000-4000-8000-0000000000f0', (select lm from f), 'del mes pasado');
reset role;
select pg_temp.sesion(null);
update crm.actividades set creado_en = creado_en - interval '40 days' where id = 'b6b00000-0000-4000-8000-0000000000f0';
update crm.actividades set creado_en = creado_en - interval '3 seconds' where id = 'b6b00000-0000-4000-8000-0000000000e1';
update crm.actividades set creado_en = creado_en - interval '2 seconds' where id = 'b6b00000-0000-4000-8000-0000000000e3';
update crm.actividades set creado_en = creado_en - interval '1 second' where id = 'b6b00000-0000-4000-8000-0000000000e2';
update crm.leads set activo = false where id = (select lx from f);  -- LX retirado (soft-delete) DESPUÉS de su intento

select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1 detalle de V1, intentos de hoy (los del banco): LX retirado (sin nombre), L1; el de ayer no', (select format('-|numero_errado|%1$s|false ; B6B LIMPIO UNO|no_contesto|%1$s|true', f.n_v1) from f),
  (select string_agg(format('%s|%s|%s|%s', coalesce(t.nombre_completo, '-'), t.detalle, t.autor, t.sigue_en_base::text), ' ; ' order by t.ord)
     from crm.base_gestion_resumen_detalle((select v1 from f), 'intentos_hoy') with ordinality t(lead_id, nombre_completo, en, detalle, autor, sigue_en_base, ord)
    where t.lead_id::text like 'b6b00000-%'));
select pg_temp.caso('S1 detalle de V2: el intento que registró Supervisión cuenta para el DUEÑO', (select format('B6B LIMPIO DOS|no_interesado|%s|true', f.n_s1) from f),
  (select string_agg(format('%s|%s|%s|%s', coalesce(t.nombre_completo, '-'), t.detalle, t.autor, t.sigue_en_base::text), ' ; ')
     from crm.base_gestion_resumen_detalle((select v2 from f), 'intentos_hoy') t where t.lead_id::text like 'b6b00000-%'));
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.reactivar_lead_base('b6b00000-0000-4000-8000-0000000000f1', (select l1 from f), 'quiere reunión');
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1 detalle de V1, reactivaciones del mes: L1 con su nota y ya fuera de la base; la del mes pasado no',
  (select format('B6B LIMPIO UNO|quiere reunión|%s|false', f.n_v1) from f),
  (select string_agg(format('%s|%s|%s|%s', coalesce(t.nombre_completo, '-'), t.detalle, t.autor, t.sigue_en_base::text), ' ; ')
     from crm.base_gestion_resumen_detalle((select v1 from f), 'reactivaciones_mes') t where t.lead_id::text like 'b6b00000-%'));
select pg_temp.caso('S1: tras reactivar, el intento de hoy sobre L1 ya no «sigue en base»', 'false',
  (select string_agg(t.sigue_en_base::text, ',') from crm.base_gestion_resumen_detalle((select v1 from f), 'intentos_hoy') t, f where t.lead_id = f.l1));
select pg_temp.caso('S1: detalle = cifra en TODO analista de su resumen (intentos y reactivaciones)', 'ok',
  coalesce((select string_agg(format('%s %s/%s %s/%s', r.nombre, r.intentos_hoy, (select count(*) from crm.base_gestion_resumen_detalle(r.vendedor_id, 'intentos_hoy')),
                                     r.reactivaciones_mes, (select count(*) from crm.base_gestion_resumen_detalle(r.vendedor_id, 'reactivaciones_mes'))), ' · ')
              from crm.base_gestion_resumen() r
             where r.intentos_hoy <> (select count(*) from crm.base_gestion_resumen_detalle(r.vendedor_id, 'intentos_hoy'))
                or r.reactivaciones_mes <> (select count(*) from crm.base_gestion_resumen_detalle(r.vendedor_id, 'reactivaciones_mes'))), 'ok'));
select pg_temp.caso('S1: las cifras no son triviales (≥ 3 intentos de hoy y ≥ 1 reactivación del mes)', 'ok',
  (select case when sum(r.intentos_hoy) >= 3 and sum(r.reactivaciones_mes) >= 1 then 'ok' else sum(r.intentos_hoy) || '/' || sum(r.reactivaciones_mes) end from crm.base_gestion_resumen() r));
select pg_temp.caso('S1: más reciente primero', 'ok',
  (select case when bool_and(x.en <= x.antes) is not false then 'ok' else 'desordenado' end
     from (select t.en, lag(t.en) over (order by t.ord) antes
             from crm.base_gestion_resumen_detalle((select v1 from f), 'intentos_hoy') with ordinality t(lead_id, nombre_completo, en, detalle, autor, sigue_en_base, ord)) x));
select pg_temp.err('S1 detalle con cifra desconocida → 22023', '22023 Cifra invalida: se espera intentos_hoy o reactivaciones_mes', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select v1 from f), 'en_base'));
select pg_temp.err('S1 detalle con cifra NULL → 22023', '22023 Cifra invalida: se espera intentos_hoy o reactivaciones_mes', format('select count(*) from crm.base_gestion_resumen_detalle(%L, null)', (select v1 from f)));
select pg_temp.err('S1 detalle sin analista → 22023', '22023 Indica el analista', 'select count(*) from crm.base_gestion_resumen_detalle(null, ''intentos_hoy'')');
select pg_temp.err('S1 detalle de V3 (otro equipo) → P0002', 'P0002 Analista no encontrado o fuera de tu ambito', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select v3 from f), 'intentos_hoy'));
reset role;
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.err('S2 detalle de V1 (otro equipo) → P0002', 'P0002 Analista no encontrado o fuera de tu ambito', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select v1 from f), 'reactivaciones_mes'));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.caso('G: detalle = cifra en TODO analista de la operación', 'ok',
  coalesce((select string_agg(r.nombre, ' · ') from crm.base_gestion_resumen() r
             where r.intentos_hoy <> (select count(*) from crm.base_gestion_resumen_detalle(r.vendedor_id, 'intentos_hoy'))
                or r.reactivaciones_mes <> (select count(*) from crm.base_gestion_resumen_detalle(r.vendedor_id, 'reactivaciones_mes'))), 'ok'));
select pg_temp.err('G detalle de Coordinación (no es analista) → P0002', 'P0002 Analista no encontrado o fuera de tu ambito', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select k from f), 'intentos_hoy'));
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err('V1 abre la detalle → 42501', '42501 Solo Supervision y Gerencia ven el resumen de la base', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select v1 from f), 'intentos_hoy'));
reset role;
select pg_temp.sesion((select k from f)); set local role authenticated;
select pg_temp.err('Coordinación abre la detalle → 42501', '42501 La base para gestion es para analistas, Supervision y Gerencia', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select v1 from f), 'intentos_hoy'));
reset role;

-- ───────── r2 (Codex r2 + auditor-rls r2, 04/10): evento vigente de la persona, con EJECUCIÓN REAL de las puertas ─────────
-- marcar_no_contactar, levantar_no_contactar y postventa_veto_fn se llaman con sesión de usuario: trg_01_gestion_lead_serializada
-- sella cada nota con clock_timestamp(), así que el orden de las notas es el real aunque todo ocurra en UNA transacción.
-- Andamio (solo en esta transacción): el banco del gate tiene 51 contratos sin identidad coherente (fixtures del gate), así que
-- la cartera F5 no está «habilitada» y private.postventa_persona se niega (P0409) antes de vetar. Se neutraliza SOLO esa
-- compuerta de cobertura (private.cartera_f5_exigir), ajena al veto; el resto de postventa_veto_fn corre tal cual.
select pg_temp.sesion(null);
create or replace function private.cartera_f5_exigir() returns void language plpgsql security definer set search_path = '' as $andamio$
begin return; end
$andamio$;
create temp table f2 as select
  -- P (a): postventa → levantar desde Y → re-vetar desde Y.  X enlace · Y puente · Z DNI suelto.
  'b6b00000-0000-4000-8000-0000000000d1'::uuid lx,  'b6b00000-0000-4000-8000-0000000000d2'::uuid ly,  'b6b00000-0000-4000-8000-0000000000d3'::uuid lz,
  -- P2 (b): marcar X2 → levantar desde Y2 → marcar Y2 (contraejemplo 2 de Codex).  X2 enlace · Y2 puente · Z2 DNI.
  'b6b00000-0000-4000-8000-0000000000e1'::uuid lx2, 'b6b00000-0000-4000-8000-0000000000e2'::uuid ly2, 'b6b00000-0000-4000-8000-0000000000e3'::uuid lz2,
  -- P5 (c): marcar Y5 (puente) → levantar desde X5 → marcar X5.
  'b6b00000-0000-4000-8000-0000000000e4'::uuid lx5, 'b6b00000-0000-4000-8000-0000000000e5'::uuid ly5,
  -- P3 (d): X3 de V1 (equipo de S1) · Y3 de V3 (equipo de S2), puente; el evento vigente queda en Y3.
  'b6b00000-0000-4000-8000-0000000000e6'::uuid lx3, 'b6b00000-0000-4000-8000-0000000000e7'::uuid ly3,
  -- R (e): W enlace y W2 puente, vetos SOLO del lead (bandera apagada): la persona no está vetada.
  'b6b00000-0000-4000-8000-0000000000d4'::uuid lw,  'b6b00000-0000-4000-8000-0000000000e8'::uuid lw2,
  -- Q4 (f): Z4, vetada por postventa (vigente).
  'b6b00000-0000-4000-8000-0000000000d6'::uuid lz4,
  'b6b00000-0000-4000-8000-0000000000d5'::uuid lmr,  -- V1, reactivado este mes y luego retirado
  'b6b00000-0000-4000-8000-0000000000d9'::uuid lbj,  -- bandeja de S1 (sin analista), vetado
  'b6b00000-0000-4000-8000-0000000000f1'::uuid pp,  'b6b00000-0000-4000-8000-0000000000f4'::uuid pp2, 'b6b00000-0000-4000-8000-0000000000f5'::uuid pp5,
  'b6b00000-0000-4000-8000-0000000000f6'::uuid pp3, 'b6b00000-0000-4000-8000-0000000000f2'::uuid pr,  'b6b00000-0000-4000-8000-0000000000f3'::uuid pq4;
grant select on f2 to authenticated;
update crm.multiempresa_flags set activo = false where nombre = 'resolver_en_puertas';  -- siembra y vetos «solo del lead» con la bandera apagada
insert into crm.inversionistas (id) select unnest(array[f2.pp, f2.pp2, f2.pp5, f2.pp3, f2.pr, f2.pq4]) from f2;
insert into crm.inversionista_identificadores (inversionista_id, tipo_documento, documento_normalizado, estado, verificado)
select x.p, 'DNI', x.d, 'vigente', true from f2, lateral (values (f2.pp, '71000001'), (f2.pp2, '71000002')) x(p, d);
insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, vendedor_id, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.n, x.t, x.dni, 'oficina', 'nuevo', x.v, x.sup, 1000, 'PEN', coalesce(x.v, x.sup), true
  from f, f2, lateral (values
     (f2.lx,  'B6B P X ENLACE',   '966600301', null::text, f.v1, null::uuid), (f2.ly,  'B6B P Y PUENTE',   '966600302', null, f.v1, null::uuid),
     (f2.lz,  'B6B P Z DNI',      '966600303', '71000001', f.v1, null::uuid),
     (f2.lx2, 'B6B P2 X ENLACE',  '966600304', null, f.v1, null::uuid), (f2.ly2, 'B6B P2 Y PUENTE',  '966600305', null, f.v1, null::uuid),
     (f2.lz2, 'B6B P2 Z DNI',     '966600306', '71000002', f.v1, null::uuid),
     (f2.lx5, 'B6B P5 X ENLACE',  '966600307', null, f.v1, null::uuid), (f2.ly5, 'B6B P5 Y PUENTE',  '966600308', null, f.v1, null::uuid),
     (f2.lx3, 'B6B P3 X EQUIPO 1', '966600309', null, f.v1, null::uuid), (f2.ly3, 'B6B P3 Y EQUIPO 2', '966600310', null, f.v3, null::uuid),
     (f2.lw,  'B6B R W ENLACE',   '966600311', null, f.v1, null::uuid), (f2.lw2, 'B6B R W2 PUENTE',  '966600312', null, f.v1, null::uuid),
     (f2.lz4, 'B6B Q4 POSTVENTA', '966600313', null, f.v1, null::uuid),
     (f2.lmr, 'B6B REACTIVADO RETIRADO', '966600205', null, f.v1, null::uuid), (f2.lbj, 'B6B BANDEJA', '966600209', null, null::uuid, f.s1)) x(id, n, t, dni, v, sup);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde'
 where id in (select unnest(array[lx, ly, lz, lx2, ly2, lz2, lx5, ly5, lx3, ly3, lw, lw2, lz4, lmr, lbj]) from f2);
-- Enlaces (uno por persona: leads_inversionista_uidx) bajo la válvula privilegiada; puentes en crm.inversionista_leads.
select set_config('crm.op_privilegiada', 'on', true);
update crm.leads l set inversionista_id = x.p from f2, lateral (values (f2.lx, f2.pp), (f2.lx2, f2.pp2), (f2.lx5, f2.pp5), (f2.lx3, f2.pp3), (f2.lw, f2.pr), (f2.lz4, f2.pq4)) x(lead, p) where l.id = x.lead;
select set_config('crm.op_privilegiada', 'off', true);
insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
select x.p, x.lead, 'historico' from f2, lateral (values (f2.pp, f2.ly), (f2.pp2, f2.ly2), (f2.pp5, f2.ly5), (f2.pp3, f2.ly3), (f2.pr, f2.lw2)) x(p, lead);
select pg_temp.caso('r2 banco: 15 leads más; persona resuelta como marcar/levantar (enlace, puente, DNI)', '15|6|5|2',
  (select count(*) || '|' || count(l.inversionista_id) || '|' || (select count(*) from crm.inversionista_leads il where il.lead_id = any(array[f2.ly, f2.ly2, f2.ly5, f2.ly3, f2.lw2]))
          || '|' || count(*) filter (where l.inversionista_id is null and private.inversionista_por_documento('DNI', l.dni) is not null)
     from crm.leads l, f2 where l.id in (f2.lx, f2.ly, f2.lz, f2.lx2, f2.ly2, f2.lz2, f2.lx5, f2.ly5, f2.lx3, f2.ly3, f2.lw, f2.lw2, f2.lz4, f2.lmr, f2.lbj)
     group by f2.ly, f2.ly2, f2.ly5, f2.ly3, f2.lw2));

-- (e) Vetos SOLO del lead (bandera apagada): W y después W2, de la misma persona R, que NO se veta.
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.marcar_no_contactar((select lw from f2), 'veto solo del lead');
select crm.marcar_no_contactar((select lw2 from f2), 'veto solo de W2');
reset role;

-- Desde aquí, la bandera ENCENDIDA (como en producción).
select pg_temp.sesion(null);
update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas';
-- (a) P: postventa (Gerencia) → S1 levanta desde Y → V1 re-veta desde Y.
select pg_temp.sesion((select g from f)); set local role authenticated;
select crm.postventa_veto_fn(gen_random_uuid(), (select pp from f2), true, 'cliente pidió no recibir llamadas');
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select crm.levantar_no_contactar((select ly from f2), 'levanta desde Y');
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.marcar_no_contactar((select ly from f2), 'Y re-veta tras la postventa');
-- (b) P2: V1 marca X2 → S1 levanta desde Y2 → V1 marca Y2.
select crm.marcar_no_contactar((select lx2 from f2), 'X2 marca');
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select crm.levantar_no_contactar((select ly2 from f2), 'levanta desde Y2');
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.marcar_no_contactar((select ly2 from f2), 'Y2 re-veta');
-- (c) P5: V1 marca Y5 (puente) → S1 levanta desde X5 → V1 marca X5.
select crm.marcar_no_contactar((select ly5 from f2), 'Y5 marca');
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select crm.levantar_no_contactar((select lx5 from f2), 'levanta desde X5');
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.marcar_no_contactar((select lx5 from f2), 'X5 re-veta');
reset role;
-- (d) P3: V3 (equipo de S2) marca Y3; X3 (de V1, equipo de S1) queda vetado por la persona.
select pg_temp.sesion((select v3 from f)); set local role authenticated;
select crm.marcar_no_contactar((select ly3 from f2), 'Y3 otro equipo');
reset role;
-- (f) Q4: postventa vigente.
select pg_temp.sesion((select g from f)); set local role authenticated;
select crm.postventa_veto_fn(gen_random_uuid(), (select pq4 from f2), true, 'cliente quiere solo correo');
reset role;
-- Bandeja de S1, marcada por S1.
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select crm.marcar_no_contactar((select lbj from f2), 'bandeja vetada');
reset role;

select pg_temp.sesion(null);
create temp table e2 as select
  (select to_char(a.creado_en at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') from crm.actividades a, f2 where a.lead_id = f2.ly and a.metadata->>'accion' = 'marcar' and a.detalle like 'Marcado%') y_en,
  (select p.nombre_completo from public.perfiles p, f where p.id = f.g) n_g,
  (select p.nombre_completo from public.perfiles p, f where p.id = f.v3) n_v3;
grant select on e2 to authenticated;
select pg_temp.caso('r2 ejecución real: las notas del veto llevan el sello del servidor (clock_timestamp, > now() de la transacción)', 'true',
  (select bool_and(a.creado_en > now())::text from crm.actividades a, f2 where a.metadata->>'evento' = 'no_contactar' and a.lead_id in (f2.lx, f2.ly, f2.lz, f2.lx2, f2.ly2, f2.lz4)));
select pg_temp.caso('r2 ejecución real: la postventa escribió su nota en X, Y y Z (los tres leads de la persona)', '3',
  (select count(*)::text from crm.actividades a, f2 where a.metadata ? 'postventa_gestion_id' and a.lead_id in (f2.lx, f2.ly, f2.lz)));
select pg_temp.caso('r2 personas vetadas: P, P2, P5, P3, Q4 sí; R no', 'true|true|true|true|true|false',
  (select string_agg(coalesce(i.no_contactar::text, '-'), '|' order by x.o) from f2, lateral (values (1, f2.pp), (2, f2.pp2), (3, f2.pp5), (4, f2.pp3), (5, f2.pq4), (6, f2.pr)) x(o, p) join crm.inversionistas i on i.id = x.p));

select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('r2 (a) contraejemplo 1: X (enlace) muestra la marca de Y, no la de la postventa', (select format('true|%s|Y re-veta tras la postventa|%s|false', e2.y_en, f.n_v1) from e2, f),
  pg_temp.fila((select lx from f2), true));
select pg_temp.caso('r2 (a) Z (DNI suelto) muestra la marca de Y', (select format('true|*|Y re-veta tras la postventa|%s|false', f.n_v1) from f),
  regexp_replace(pg_temp.fila((select lz from f2), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.caso('r2 (a) Y (puente) muestra su marca', (select format('true|*|Y re-veta tras la postventa|%s|false', f.n_v1) from f),
  regexp_replace(pg_temp.fila((select ly from f2), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.caso('r2 (b) contraejemplo 2 (una transacción): X2 (enlace) muestra la marca de Y2', (select format('true|*|Y2 re-veta|%s|false', f.n_v1) from f),
  regexp_replace(pg_temp.fila((select lx2 from f2), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.caso('r2 (b) Z2 (DNI suelto) muestra la marca de Y2', (select format('true|*|Y2 re-veta|%s|false', f.n_v1) from f),
  regexp_replace(pg_temp.fila((select lz2 from f2), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.caso('r2 (c) Y5 (puente) muestra la marca de X5, no la suya vieja', (select format('true|*|X5 re-veta|%s|false', f.n_v1) from f),
  regexp_replace(pg_temp.fila((select ly5 from f2), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.caso('r2 (d) el evento vigente está en un lead de OTRO equipo: S1 ve X3 vetado pero sin marca', 'true|-|-|-|false', pg_temp.fila((select lx3 from f2), true));
select pg_temp.caso('r2 (e) veto solo del lead (persona sin vetar): W muestra SU nota, no la de W2', (select format('true|*|veto solo del lead|%s|false', f.n_v1) from f),
  regexp_replace(pg_temp.fila((select lw from f2), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.caso('r2 (f) postventa vigente: motivo de la postventa (del detalle) y su autor', (select format('true|*|cliente quiere solo correo|%s|false', e2.n_g) from e2),
  regexp_replace(pg_temp.fila((select lz4 from f2), true), '^true\|[^|]+\|', 'true|*|'));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.caso('r2 (d) Gerencia sí ve la marca de X3 (escrita en Y3, de otro equipo)', (select format('true|*|Y3 otro equipo|%s|false', e2.n_v3) from e2),
  regexp_replace(pg_temp.fila((select lx3 from f2), true), '^true\|[^|]+\|', 'true|*|'));
reset role;

-- Bandeja (vendedor NULL, asignado_supervisor_id = S1): S1 y Gerencia lo ven; S2 no.
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('r1 bandeja: S1 ve el vetado de su bandeja con su marca', (select format('true|*|bandeja vetada|%s|false', f.n_s1) from f),
  regexp_replace(pg_temp.fila((select lbj from f2), true), '^true\|[^|]+\|', 'true|*|'));
select pg_temp.caso('r1 bandeja: sin pedirlos, S1 no lo ve', 'sin fila', pg_temp.fila((select lbj from f2), false));
reset role;
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('r1 bandeja: S2 (otro equipo) no lo ve', 'sin fila', pg_temp.fila((select lbj from f2), true));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.caso('r1 bandeja: Gerencia lo ve', 'true', split_part(pg_temp.fila((select lbj from f2), true), '|', 1));
reset role;

-- Reactivado este mes y luego retirado: cuenta en la cifra, sin nombre ni nota.
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select crm.reactivar_lead_base('b6b00000-0000-4000-8000-0000000000fa', (select lmr from f2), 'nota que no debe verse');
reset role;
select pg_temp.sesion(null);
update crm.leads set activo = false where id = (select lmr from f2);
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('r1 retirado: su reactivación del mes sale sin nombre ni nota', (select format('-|-|%s|false', f.n_v1) from f),
  (select string_agg(format('%s|%s|%s|%s', coalesce(t.nombre_completo, '-'), coalesce(t.detalle, '-'), t.autor, t.sigue_en_base::text), ' ; ')
     from crm.base_gestion_resumen_detalle((select v1 from f), 'reactivaciones_mes') t, f2 where t.lead_id = f2.lmr));
select pg_temp.caso('r1 retirado: detalle = cifra sigue cuadrando para V1', 'ok',
  (select case when r.reactivaciones_mes = (select count(*) from crm.base_gestion_resumen_detalle(r.vendedor_id, 'reactivaciones_mes'))
                and r.intentos_hoy = (select count(*) from crm.base_gestion_resumen_detalle(r.vendedor_id, 'intentos_hoy')) then 'ok' else 'no cuadra' end
     from crm.base_gestion_resumen() r, f where r.vendedor_id = f.v1));
reset role;

-- Miembros DESACTIVADOS (Supervisión y Gerencia con su membresía inactiva): 42501 en las dos puertas.
select pg_temp.sesion(null);
alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
update crm.equipo set activo = false where perfil_id in ((select s2 from f), (select g from f));
alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.err('r1 Supervisión desactivada pide los vetados → 42501', '42501 La base para gestion es para analistas, Supervision y Gerencia', 'select count(*) from crm.obtener_base_gestion(null, true)');
select pg_temp.err('r1 Supervisión desactivada abre la detalle → 42501', '42501 La base para gestion es para analistas, Supervision y Gerencia', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select v3 from f), 'intentos_hoy'));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.err('r1 Gerencia desactivada pide los vetados → 42501', '42501 La base para gestion es para analistas, Supervision y Gerencia', 'select count(*) from crm.obtener_base_gestion(null, true)');
select pg_temp.err('r1 Gerencia desactivada abre la detalle → 42501', '42501 La base para gestion es para analistas, Supervision y Gerencia', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select v1 from f), 'intentos_hoy'));
reset role;

-- ───────── Resultado ─────────
update r set ok = coalesce(obtenido = esperado, false);  -- un NULL no es PASS
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 220)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B6b: hay casos FAIL'; end if; end $$;
rollback;

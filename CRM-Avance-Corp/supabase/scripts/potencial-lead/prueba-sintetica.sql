-- Prueba sintética de 20260930213647_crm_potencial_lead.
-- SOLO en un banco (Docker propio con el esquema de producción), como supabase_admin. Todo
-- ocurre en UNA transacción que termina en raise: no deja filas, ni actores, ni la bandera.
-- ⚠️ Nunca se llama a una función sin EXECUTE bajo `set role` (tumba Postgres 17.6 con
-- plan_filter): los permisos de los ayudantes privados se leen del catálogo.
--
-- Mundo: gerencia G · supervisor S1 con sub-supervisor S1n · analista V1 (de S1) y V1n (de
-- S1n) · supervisor S2 con analista V2 · coordinador C · directorio D · X con equipo
-- inactivo. Leads: L1 (V1), L1n (V1n), L2 (V2), LP (parqueado en S1), LC (V1 convertido),
-- LD (V1 descartado), LI (V1 inactivo) y un id que no existe.
begin;
set local lock_timeout = '5s';

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('G'), ('S1'), ('S1n'), ('V1'), ('V1n'), ('S2'), ('V2'), ('C'), ('D'), ('X');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('L3'), ('LPV'), ('NADA');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;

-- Fixtures sin disparadores (solo filas que cumplen los CHECK).
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@potencial.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo)
  select id, 'POTENCIAL ' || k, case k when 'D' then 'directorio' when 'G' then 'admin' else 'analista' end, true from act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  (pg_temp.a('G'), 'gerencia', null, true),
  (pg_temp.a('S1'), 'supervisor', null, true),
  (pg_temp.a('S1n'), 'supervisor', pg_temp.a('S1'), true),
  (pg_temp.a('V1'), 'vendedor', pg_temp.a('S1'), true),
  (pg_temp.a('V1n'), 'vendedor', pg_temp.a('S1n'), true),
  (pg_temp.a('S2'), 'supervisor', null, true),
  (pg_temp.a('V2'), 'vendedor', pg_temp.a('S2'), true),
  (pg_temp.a('C'), 'coordinador', null, true),
  (pg_temp.a('D'), 'directorio', null, true),
  (pg_temp.a('X'), 'vendedor', pg_temp.a('S1'), false);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, asignado_supervisor_id, activo, motivo_descarte) values
  (pg_temp.l('L1'),  'POTENCIAL L1',  '+51987650001', 'landing', 50000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('L1n'), 'POTENCIAL L1N', '+51987650002', 'landing', 15000, 'PEN', 'nuevo',      pg_temp.a('V1n'), null, true, null),
  (pg_temp.l('L2'),  'POTENCIAL L2',  '+51987650003', 'landing', 30000, 'PEN', 'contactado', pg_temp.a('V2'),  null, true, null),
  (pg_temp.l('LP'),  'POTENCIAL LP',  '+51987650004', 'landing', 12000, 'PEN', 'nuevo',      null, pg_temp.a('S1'), true, null),
  (pg_temp.l('LC'),  'POTENCIAL LC',  '+51987650005', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LD'),  'POTENCIAL LD',  '+51987650006', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V1'),  null, true, 'sin_interes'),
  (pg_temp.l('LI'),  'POTENCIAL LI',  '+51987650007', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, false, null),
  (pg_temp.l('L3'),  'POTENCIAL L3',  '+51987650008', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LPV'), 'POTENCIAL LPV', '+51987650009', 'landing', 20000, 'PEN', 'nuevo',      null, pg_temp.a('V1'), true, null);
-- actualizado_en sembrado en el pasado: si marcar tocara crm.leads, cambiaría (Codex r1).
update crm.leads set actualizado_en = '2026-01-02 03:04:05+00' where id = pg_temp.l('L1');
set local session_replication_role = origin;

-- Fija la identidad de la sesión. Se escriben las DOS formas: el auth.uid() de producción lee
-- request.jwt.claims (->> 'sub') y el de esta imagen del banco solo request.jwt.claim.sub.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Llamar a la puerta como un actor autenticado; devuelve 'ok:<nivel>' o el SQLSTATE.
create function pg_temp.marcar(p_actor uuid, p_lead uuid, p_nivel text) returns text language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    v := crm.marcar_potencial_lead_fn(p_lead, p_nivel::crm.nivel_potencial);
    reset role;
    return 'ok:' || (v ->> 'nivel');
  exception when others then
    reset role;
    return sqlstate;
  end;
end $f$;

-- Cuántas filas de la marca ve un actor para un lead (RLS).
create function pg_temp.ve(p_actor uuid, p_lead uuid) returns text language plpgsql as $f$
declare n int; m int;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    select count(*) into n from crm.lead_potencial where lead_id = p_lead;
    select count(*) into m from crm.lead_potencial_eventos where lead_id = p_lead;
  exception when others then
    reset role;
    return sqlstate;
  end;
  reset role;
  return n || '/' || m;
end $f$;

-- Una escritura directa por la API (sin la puerta) como un actor; devuelve 'ok' o el SQLSTATE.
create function pg_temp.escribe(p_actor uuid, p_sql text) returns text language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    execute p_sql;
    reset role;
    return 'ok';
  exception when others then
    reset role;
    return sqlstate;
  end;
end $f$;

-- Una operación como supabase_admin; devuelve 'ok' o el SQLSTATE.
create function pg_temp.admin(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $f$;

do $prueba$
declare
  v_actividades_antes int;
  v_marcado_en timestamptz;
  v_n int;
begin
  -- ── Catálogo: ayudantes privados sin EXECUTE para la API; puerta solo authenticated ──
  perform pg_temp.esperar('privadas sin EXECUTE de anon/authenticated/service_role/PUBLIC', '0', (
    select count(*)::text from pg_proc p, aclexplode(p.proacl) x
    where p.oid in ('private.potencial_rechazo(uuid,uuid)'::regprocedure,
                    'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::regprocedure,
                    'private.potencial_bloquear_lead(uuid)'::regprocedure,
                    'private.potencial_evento_inmutable()'::regprocedure)
      and x.grantee <> 'postgres'::regrole));
  perform pg_temp.esperar('puerta: EXECUTE solo postgres y authenticated', 'authenticated,postgres', (
    select string_agg(x.grantee::regrole::text, ',' order by x.grantee::regrole::text)
    from pg_proc p, aclexplode(p.proacl) x
    where p.oid = 'crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)'::regprocedure and x.privilege_type = 'EXECUTE'));
  perform pg_temp.esperar('tablas sin grants para la API (ni SELECT)', '0', (
    select count(*)::text from unnest(array['anon','authenticated','service_role']) r(rol),
      unnest(array['crm.lead_potencial','crm.lead_potencial_eventos']) t(tabla),
      unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) x(priv)
    where has_table_privilege(r.rol, t.tabla, x.priv)));
  perform pg_temp.esperar('bandera nace apagada', 'false', (select activo::text from crm.multiempresa_flags where nombre = 'potencial_lead'));

  -- ── Bandera APAGADA: quien pasa rol y ámbito recibe 55000; los demás, su rechazo ──
  perform pg_temp.esperar('sin sesión', '42501', pg_temp.marcar(null, pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('V1 sin lead (null)', '22023', pg_temp.marcar(pg_temp.a('V1'), null, 'estrella'));
  perform pg_temp.esperar('V1 → su lead L1 (pasa, bandera apagada)', '55000', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('V1 → L2 de otro equipo', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L2'), 'estrella'));
  perform pg_temp.esperar('V1 → LP parqueado en su supervisor', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LP'), 'estrella'));
  perform pg_temp.esperar('V1 → LPV parqueado «en él» (solo un supervisor marca parqueos)', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LPV'), 'estrella'));
  perform pg_temp.esperar('V1 → L1n de otro analista del mismo árbol', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1n'), 'estrella'));
  perform pg_temp.esperar('V1 → LC convertido', '22023', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LC'), 'estrella'));
  perform pg_temp.esperar('V1 → LD descartado', '22023', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LD'), 'estrella'));
  perform pg_temp.esperar('V1 → LI inactivo', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LI'), 'estrella'));
  perform pg_temp.esperar('V1 → lead inexistente', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('NADA'), 'estrella'));
  perform pg_temp.esperar('S1 → L1 de su analista', '55000', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('S1 → L1n de su sub-supervisor', '55000', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1n'), 'estrella'));
  perform pg_temp.esperar('S1 → LP parqueado en su bandeja', '55000', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('LP'), 'estrella'));
  perform pg_temp.esperar('S1 → L2 de otro supervisor', 'P0002', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L2'), 'estrella'));
  perform pg_temp.esperar('S1n → L1 de su jefe (no es su árbol)', 'P0002', pg_temp.marcar(pg_temp.a('S1n'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('S2 → L1', 'P0002', pg_temp.marcar(pg_temp.a('S2'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('gerencia → L1', '42501', pg_temp.marcar(pg_temp.a('G'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('coordinador → L1', '42501', pg_temp.marcar(pg_temp.a('C'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('directorio → L1', '42501', pg_temp.marcar(pg_temp.a('D'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('X con equipo inactivo → L1', '42501', pg_temp.marcar(pg_temp.a('X'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('nivel inválido', '22P02', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'dorado'));
  perform pg_temp.esperar('con la bandera apagada no se escribió nada', '0', (select (count(*) + (select count(*) from crm.lead_potencial_eventos))::text from crm.lead_potencial));

  -- ── Escritura directa por la API: siempre denegada (sin grants) ──
  perform pg_temp.esperar('V1 INSERT directo en lead_potencial', '42501', pg_temp.escribe(pg_temp.a('V1'),
    format('insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values (%L, ''estrella'', ''manual'', %L, now())', pg_temp.l('L1'), pg_temp.a('V1'))));
  perform pg_temp.esperar('V1 INSERT directo en lead_potencial_eventos', '42501', pg_temp.escribe(pg_temp.a('V1'),
    format('insert into crm.lead_potencial_eventos (lead_id, nivel_nuevo, motivo, por) values (%L, ''estrella'', ''manual'', %L)', pg_temp.l('L1'), pg_temp.a('V1'))));
  perform pg_temp.esperar('gerencia UPDATE directo en lead_potencial', '42501', pg_temp.escribe(pg_temp.a('G'), 'update crm.lead_potencial set nivel = ''frio'''));

  -- ── Bandera ENCENDIDA (como lo hará la fase 3) ──
  update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';
  select count(*) into v_actividades_antes from crm.actividades a where a.lead_id = pg_temp.l('L1');

  perform pg_temp.esperar('V1 marca L1 estrella', 'ok:estrella', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('primer evento: null → estrella por V1', 'null>estrella/manual/V1', (
    select coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo || '/' || e.motivo || '/' || (select k from act where id = e.por)
    from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l('L1') order by e.orden limit 1));
  select p.marcado_en into v_marcado_en from crm.lead_potencial p where p.lead_id = pg_temp.l('L1');

  perform pg_temp.esperar('V1 cambia L1 a tibio', 'ok:tibio', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'tibio'));
  perform pg_temp.esperar('S1 (su supervisor) vuelve L1 a estrella', 'ok:estrella', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('S1 doble clic (mismo nivel, <60 s) responde', 'ok:estrella', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('el doble clic no escribe evento', 'null>estrella,estrella>tibio,tibio>estrella', (
    select string_agg(coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo, ',' order by e.orden)
    from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l('L1')));
  -- La marca de S1 «envejece» 2 minutos: reconfirmar YA escribe y reinicia el reloj.
  update crm.lead_potencial set marcado_en = now() - interval '2 minutes' where lead_id = pg_temp.l('L1');
  select p.marcado_en into v_marcado_en from crm.lead_potencial p where p.lead_id = pg_temp.l('L1');
  perform pg_temp.esperar('S1 reconfirma estrella pasado el minuto', 'ok:estrella', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('reconfirmar reinicia marcado_en', 'true', (
    select (p.marcado_en > v_marcado_en)::text from crm.lead_potencial p where p.lead_id = pg_temp.l('L1')));
  perform pg_temp.esperar('estado vigente de L1: una fila, estrella, manual, por S1', '1|estrella|manual|S1', (
    select count(*) || '|' || max(p.nivel::text) || '|' || max(p.origen) || '|' || max((select k from act where id = p.marcado_por))
    from crm.lead_potencial p where p.lead_id = pg_temp.l('L1')));
  perform pg_temp.esperar('historial de L1 en orden', 'null>estrella,estrella>tibio,tibio>estrella,estrella>estrella', (
    select string_agg(coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo, ',' order by e.orden)
    from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l('L1')));
  perform pg_temp.esperar('marcar NO toca crm.leads.actualizado_en (sembrado en 2026-01-02)', '2026-01-02 03:04:05+00', (
    select to_char(l.actualizado_en at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') || '+00' from crm.leads l where l.id = pg_temp.l('L1')));
  perform pg_temp.esperar('marcar NO crea actividades (no es gestión)', v_actividades_antes::text, (
    select count(*)::text from crm.actividades a where a.lead_id = pg_temp.l('L1')));

  perform pg_temp.esperar('S1 marca LP parqueado', 'ok:frio', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('LP'), 'frio'));
  perform pg_temp.esperar('V1 sigue sin poder con L2', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L2'), 'estrella'));
  perform pg_temp.esperar('gerencia sigue sin marcar', '42501', pg_temp.marcar(pg_temp.a('G'), pg_temp.l('L1'), 'frio'));
  perform pg_temp.esperar('V1 sigue sin marcar un convertido', '22023', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('LC'), 'estrella'));

  -- ── Lectura: sin grants la API no lee; con un grant de prueba (deshecho) la RLS filtra ──
  perform pg_temp.esperar('sin grant: V1 no lee la tabla directo', '42501', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('L1')));
  perform pg_temp.esperar('sin grant: gerencia tampoco', '42501', pg_temp.ve(pg_temp.a('G'), pg_temp.l('L1')));
  grant select on crm.lead_potencial, crm.lead_potencial_eventos to authenticated;
  perform pg_temp.esperar('V1 ve la marca de L1 (vigente/eventos)', '1/4', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('L1')));
  perform pg_temp.esperar('S1 ve la marca de L1', '1/4', pg_temp.ve(pg_temp.a('S1'), pg_temp.l('L1')));
  perform pg_temp.esperar('gerencia ve la marca de L1', '1/4', pg_temp.ve(pg_temp.a('G'), pg_temp.l('L1')));
  perform pg_temp.esperar('directorio ve la marca de L1', '1/4', pg_temp.ve(pg_temp.a('D'), pg_temp.l('L1')));
  perform pg_temp.esperar('V2 NO ve la marca de L1', '0/0', pg_temp.ve(pg_temp.a('V2'), pg_temp.l('L1')));
  perform pg_temp.esperar('S2 NO ve la marca de L1', '0/0', pg_temp.ve(pg_temp.a('S2'), pg_temp.l('L1')));
  perform pg_temp.esperar('coordinador NO ve la marca de L1', '0/0', pg_temp.ve(pg_temp.a('C'), pg_temp.l('L1')));
  perform pg_temp.esperar('V1 NO ve la marca de LP (parqueado)', '0/0', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('LP')));
  perform pg_temp.esperar('S1 ve la marca de LP', '1/1', pg_temp.ve(pg_temp.a('S1'), pg_temp.l('LP')));

  -- ── Historial inmutable (incluso para el superusuario) ──
  perform pg_temp.esperar('UPDATE del historial', 'P0409', pg_temp.admin('update crm.lead_potencial_eventos set motivo = ''caducidad'', por = null'));
  perform pg_temp.esperar('DELETE del historial', 'P0409', pg_temp.admin('delete from crm.lead_potencial_eventos'));
  perform pg_temp.esperar('TRUNCATE del historial', 'P0409', pg_temp.admin('truncate crm.lead_potencial_eventos'));
  perform pg_temp.esperar('evento manual sin autor', '23514', pg_temp.admin(format(
    'insert into crm.lead_potencial_eventos (lead_id, nivel_nuevo, motivo, por) values (%L, ''frio'', ''manual'', null)', pg_temp.l('L1'))));
  perform pg_temp.esperar('segunda fila vigente para el mismo lead', '23505', pg_temp.admin(format(
    'insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values (%L, ''frio'', ''manual'', %L, now())', pg_temp.l('L1'), pg_temp.a('V1'))));

  -- ── La marca es del lead: viaja al reasignar ──
  set local session_replication_role = replica;
  update crm.leads set vendedor_id = pg_temp.a('V2') where id = pg_temp.l('L1');
  set local session_replication_role = origin;
  perform pg_temp.esperar('tras reasignar L1 a V2: V2 ve la marca', '1/4', pg_temp.ve(pg_temp.a('V2'), pg_temp.l('L1')));
  perform pg_temp.esperar('tras reasignar: V1 ya no la ve', '0/0', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('L1')));
  perform pg_temp.esperar('tras reasignar: V2 puede marcar L1', 'ok:tibio', pg_temp.marcar(pg_temp.a('V2'), pg_temp.l('L1'), 'tibio'));
  perform pg_temp.esperar('tras reasignar: V1 ya no puede', 'P0002', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('tras reasignar: S1 ya no puede', 'P0002', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L1'), 'estrella'));
  perform pg_temp.esperar('tras reasignar: S2 (nuevo supervisor) sí puede', 'ok:estrella', pg_temp.marcar(pg_temp.a('S2'), pg_temp.l('L1'), 'estrella'));

  -- ── Analista desactivado tras marcar: ya no marca ni ve ──
  perform pg_temp.esperar('V1 marca L3', 'ok:tibio', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L3'), 'tibio'));
  set local session_replication_role = replica;
  update crm.equipo set activo = false where perfil_id = pg_temp.a('V1');
  set local session_replication_role = origin;
  perform pg_temp.esperar('V1 desactivado ya no marca L3', '42501', pg_temp.marcar(pg_temp.a('V1'), pg_temp.l('L3'), 'estrella'));
  perform pg_temp.esperar('V1 desactivado ya no ve la marca de L3', '0/0', pg_temp.ve(pg_temp.a('V1'), pg_temp.l('L3')));
  perform pg_temp.esperar('S1 sí la ve y la puede cambiar', 'ok:frio', pg_temp.marcar(pg_temp.a('S1'), pg_temp.l('L3'), 'frio'));

  -- ── Auditoría: filas en public.audit_log con su autor ──
  perform pg_temp.esperar('bitácora: V1 escribió en lead_potencial y en su historial', 'true', (
    select (count(*) filter (where a.tabla = 'crm.lead_potencial') > 0
            and count(*) filter (where a.tabla = 'crm.lead_potencial_eventos') > 0)::text
    from public.audit_log a where a.usuario_id = pg_temp.a('V1')));
  perform pg_temp.esperar('bitácora: S1 figura como autor de sus marcas', 'true', (
    select (count(*) > 0)::text from public.audit_log a
    where a.usuario_id = pg_temp.a('S1') and a.tabla = 'crm.lead_potencial'));
  -- ── Auditoría: las escrituras dejaron rastro en la bitácora ──
  select count(*) into v_n from pg_trigger t
  where t.tgrelid in ('crm.lead_potencial'::regclass, 'crm.lead_potencial_eventos'::regclass)
    and t.tgname like 'trg_audit_%' and t.tgenabled = 'O';
  perform pg_temp.esperar('dos disparadores de auditoría activos', '2', v_n::text);

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'SINTETICA potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res)
      using errcode = 'P0001';
  else
    raise exception 'SINTETICA potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido)
      using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;

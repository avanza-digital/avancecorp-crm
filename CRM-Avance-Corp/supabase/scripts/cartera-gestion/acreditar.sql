-- ACREDITAR 20261001154153_crm_cartera_filtro_gestion — SOLO LECTURA.
-- Un único DO que termina SIEMPRE en `raise`: no puede escribir nada (ni el `search_path`
-- que fija para medir sobrevive). Sirve ANTES de publicar (¿pasaría la migración su
-- preflight? ¿coinciden las anclas?) y DESPUÉS (¿quedó lo ensayado?). El informe llega en el
-- texto del «error».
--
--   producción (lo corre quien publica):  supabase db query --linked --file supabase/scripts/cartera-gestion/acreditar.sql
--   banco:                                docker exec -i -e PGPASSWORD=postgres <contenedor> psql -U postgres -h 127.0.0.1 -d postgres < acreditar.sql
--
-- Todas las huellas se miden con `search_path` vacío (el texto de pg_get_functiondef y de
-- pg_get_triggerdef cambia con el search_path de la sesión). Solo conteos: ningún dato personal.
do $acreditar$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f12_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  md5_f12 constant text := '7169d94239dcb191bafa3faed46f916f';
  md5_f13 constant text := 'bf06666fb8ef533a39a50c7d70420153';
  huella_f12 constant text := '1e2cdd16e5d59f2dd6a8280052312009';
  huella_f13 constant text := '22284ce4b9e70790d6e23622f4cd6682';
  md5_trigger constant text := 'f5849e264eb05e8a253dbd78c2362fba';
  md5_trigger_fn constant text := '900508fa3ccf3eec2e738ccdeebad7be';
  -- Guarda 5: el reloj y la integridad de la ACTIVIDAD.
  md5_trg01 constant text := 'a7d2d742991f2ac9fbf3d52343a25532';
  md5_trg01_fn constant text := '7af0e66b8a4849566e43b514245e1b86';
  md5_trg00 constant text := '24037d111fc11c9b5fd3c9677e329bdf';
  md5_trg00_fn constant text := '19952736370f64026f747c19b54ab38e';
  md5_insert_check constant text := 'b2d6792bc6913861ca74f4398e6a12ab';
  md5_gate constant text := 'c5e6c90632bc616212336e1d089a68b3';
  razon_f12 constant text := 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia y reasignacion entre analistas. No calcula conversion mensual.';
  o12 oid; o13 oid; viva oid; viva_larga text;
  estado text; informe text := ''; todo_ok boolean := true;
  v text; b boolean; e record;
  r_nuevo bigint; r_titular bigint; r_con bigint; r_sin bigint; r_sin_tenencia bigint;
  r_abiertos_sin_tenencia bigint; r_contacto_previo bigint; r_solo_deshecho bigint;
begin
  perform set_config('search_path', '', true);
  o12 := to_regprocedure(f12);
  o13 := to_regprocedure(f13);
  estado := case
    when o12 is not null and o13 is null then 'ANTES de publicar (vive la firma de 12 argumentos)'
    when o13 is not null and o12 is null then 'DESPUES de publicar (vive la firma de 13 argumentos)'
    else 'INESPERADO (ni solo la de 12 ni solo la de 13)' end;
  viva := coalesce(o13, o12);
  viva_larga := case when o13 is not null then f13_larga else f12_larga end;

  -- 1. Identidad de la función viva.
  b := (select count(*) from pg_proc where proname = 'cartera_filtrada_fn' and pronamespace = 'crm'::regnamespace) = 1;
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s una sola firma de cartera_filtrada_fn', case when b then '[OK]' else '[DIFERENTE]' end);
  v := md5(pg_get_functiondef(viva));
  b := v = case when o13 is not null then md5_f13 else md5_f12 end;
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s md5 de pg_get_functiondef = %s (esperado %s)', case when b then '[OK]' else '[DIFERENTE]' end,
    coalesce(v, '(no existe)'), case when o13 is not null then md5_f13 else md5_f12 end);
  v := (select p.proowner::regrole::text || ' · ' || case when p.prosecdef then 'DEFINER' else 'INVOKER' end || ' · volatilidad ' || p.provolatile::text
          || ' · ' || coalesce(array_to_string(p.proconfig, ','), '(sin config)') || ' · ACL ' || coalesce(p.proacl::text, '(null)') from pg_proc p where p.oid = viva);
  -- Dueño postgres, INVOKER, stable, search_path vacío (se guarda con comillas) y ACL por lista
  -- blanca, sin depender del orden: solo postgres y authenticated, PUBLIC fuera.
  b := exists (select 1 from pg_proc p
    where p.oid = viva and p.proowner = 'postgres'::regrole and not p.prosecdef and p.provolatile = 's'
      and p.proconfig = array['search_path=""']
      and (select array_agg(x.g order by x.g) from (
            select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end || ':' || a.privilege_type as g
            from aclexplode(p.proacl) a) x) = array['authenticated:EXECUTE', 'postgres:EXECUTE']);
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s contrato de seguridad: %s', case when b then '[OK]' else '[DIFERENTE]' end, coalesce(v, '(no existe)'));
  b := not has_function_privilege('anon', viva, 'EXECUTE') and not has_function_privilege('service_role', viva, 'EXECUTE')
       and has_function_privilege('authenticated', viva, 'EXECUTE');
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s EXECUTE: anon no, service_role no, authenticated sí', case when b then '[OK]' else '[DIFERENTE]' end);

  -- 2. Declaración analítica de la función viva y sello de la lista.
  select x.clase, x.huella, x.razon, x.declarado_en into e from private.analitica_leads_citas_exenciones x where x.objeto = viva_larga;
  b := exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto = viva_larga and c.declarada and c.huella_ok)
       and e.clase = 'operativo'
       and e.huella = case when o13 is not null then huella_f13 else huella_f12 end;
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s declaración analítica vigente: clase %s, huella %s (esperada %s), declarada el %s',
    case when b then '[OK]' else '[DIFERENTE]' end, coalesce(e.clase, '(sin fila)'), coalesce(e.huella, '(sin fila)'),
    case when o13 is not null then huella_f13 else huella_f12 end, coalesce(e.declarado_en::date::text, '(sin fila)'));
  if o13 is null then
    b := e.razon = razon_f12;
    informe := informe || format(E'\n  %s la razón declarada es la de 20260929195918 (la reversa devuelve ese texto)',
      case when b then '[OK]' else '[AVISO: otro texto; no impide publicar]' end);
  end if;
  b := (select s.sello from private.analitica_lc_sello s where s.id) = private.huella_exenciones_analitica_lc();
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s sello de la lista de exenciones vigente', case when b then '[OK]' else '[DIFERENTE]' end);
  v := (select coalesce(string_agg(c.objeto, ', ' order by c.objeto), '(ninguno)') from private.contadores_crudos_leads_citas() c where not (c.declarada and c.huella_ok));
  informe := informe || format(E'\n  [INFO] censo: %s contadores; en rojo: %s (la migración conserva ese conjunto tal cual)',
    (select count(*) from private.contadores_crudos_leads_citas()), v);
  begin
    v := private.assert_analitica_leads_citas();
  exception when others then v := 'ROJO: ' || sqlerrm;
  end;
  informe := informe || format(E'\n  [INFO] gate analítico: %s', left(v, 300));

  -- 3. Lo que el filtro da por cierto: lectura de actividades coextensiva y reloj de tenencia.
  begin
    v := private.assert_actividades_de_lead_base(); b := true;
  exception when others then v := sqlerrm; b := false;
  end;
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s assert_actividades_de_lead_base: %s', case when b then '[OK]' else '[DIFERENTE]' end, left(v, 200));
  select md5(pg_get_triggerdef(t.oid)) as def, md5(pg_get_functiondef(t.tgfoid)) as fn, t.tgenabled::text as activo into e
    from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zzz_tenencia_desde' and not t.tgisinternal;
  b := e.def = md5_trigger and e.fn = md5_trigger_fn and e.activo = 'O';
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s trigger trg_leads_zzz_tenencia_desde: definición %s (esperada %s), función %s (esperada %s), estado %s (esperado O)',
    case when b then '[OK]' else '[DIFERENTE]' end, coalesce(e.def, '(no existe)'), md5_trigger, coalesce(e.fn, '(no existe)'), md5_trigger_fn, coalesce(e.activo, '-'));
  -- 3b. Guarda 5: los dos sellos de crm.actividades, la policy de INSERT, las restrictivas y
  --     que la API no pueda reescribir ni borrar una actividad.
  select md5(pg_get_triggerdef(t.oid)) as def, md5(pg_get_functiondef(t.tgfoid)) as fn, t.tgenabled::text as activo into e
    from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_01_gestion_lead_serializada' and not t.tgisinternal;
  b := e.def = md5_trg01 and e.fn = md5_trg01_fn and e.activo = 'O';
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s trigger trg_01_gestion_lead_serializada (sella creado_en y revalida el ámbito): definición %s (esperada %s), función %s (esperada %s), estado %s (esperado O)',
    case when b then '[OK]' else '[DIFERENTE]' end, coalesce(e.def, '(no existe)'), md5_trg01, coalesce(e.fn, '(no existe)'), md5_trg01_fn, coalesce(e.activo, '-'));
  select md5(pg_get_triggerdef(t.oid)) as def, md5(pg_get_functiondef(t.tgfoid)) as fn, t.tgenabled::text as activo into e
    from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_resultado_solo_nucleo' and not t.tgisinternal;
  b := e.def = md5_trg00 and e.fn = md5_trg00_fn and e.activo = 'O';
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s trigger trg_00_actividades_resultado_solo_nucleo (reserva el resultado de llamada y deshecho_en): definición %s (esperada %s), función %s (esperada %s), estado %s (esperado O)',
    case when b then '[OK]' else '[DIFERENTE]' end, coalesce(e.def, '(no existe)'), md5_trg00, coalesce(e.fn, '(no existe)'), md5_trg00_fn, coalesce(e.activo, '-'));
  b := (select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('crm.actividades'::regclass, 'crm.leads'::regclass));
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s RLS encendida en crm.actividades y crm.leads', case when b then '[OK]' else '[DIFERENTE]' end);
  v := (select md5(pg_get_expr(p.polwithcheck, p.polrelid)) from pg_policy p
         where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a' and p.polname = 'actividades_insert'
           and p.polpermissive and p.polroles = array['authenticated'::regrole::oid]);
  b := v = md5_insert_check
       and (select count(*) from pg_policy p where p.polrelid = 'crm.actividades'::regclass and p.polcmd = 'a') = 1;
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s una sola policy de INSERT en crm.actividades (actividades_insert, permisiva, solo authenticated): with check %s (esperado %s)',
    case when b then '[OK]' else '[DIFERENTE]' end, coalesce(v, '(no existe o no es la esperada)'), md5_insert_check);
  v := (select coalesce(string_agg(p.polname || ' [' || p.polcmd::text || ']', ', ' order by p.polname), '(ninguna)') from pg_policy p
         where p.polrelid = 'crm.actividades'::regclass and ((p.polcmd = '*' and p.polpermissive) or p.polcmd in ('w', 'd')));
  b := v = '(ninguna)';
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s policies permisivas ALL o de UPDATE/DELETE en crm.actividades: %s', case when b then '[OK]' else '[DIFERENTE]' end, v);
  v := (select coalesce(string_agg(p.polrelid::regclass::text || '.' || p.polname || ' [' || p.polcmd::text || '] '
           || coalesce(md5(pg_get_expr(p.polqual, p.polrelid)), '-') || '/' || coalesce(md5(pg_get_expr(p.polwithcheck, p.polrelid)), '-'),
           ', ' order by p.polrelid::regclass::text, p.polname), '(ninguna)')
        from pg_policy p where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass) and not p.polpermissive);
  b := (select count(*) from pg_policy p
         where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass) and not p.polpermissive) = 2
       and (select count(*) from pg_policy p
         where p.polrelid in ('crm.actividades'::regclass, 'crm.leads'::regclass)
           and not p.polpermissive and p.polname = 'crm_actor_activo_gate' and p.polcmd = '*'
           and p.polroles = array['authenticated'::regrole::oid]
           and md5(pg_get_expr(p.polqual, p.polrelid)) = md5_gate
           and md5(pg_get_expr(p.polwithcheck, p.polrelid)) = md5_gate) = 2;
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s restrictivas de crm.actividades y crm.leads: exactamente crm_actor_activo_gate en cada una, expresión %s — hay: %s',
    case when b then '[OK]' else '[DIFERENTE]' end, md5_gate, v);
  b := not has_any_column_privilege('authenticated', 'crm.actividades', 'UPDATE')
       and not has_table_privilege('authenticated', 'crm.actividades', 'DELETE')
       and not has_any_column_privilege('anon', 'crm.actividades', 'UPDATE')
       and not has_table_privilege('anon', 'crm.actividades', 'DELETE');
  todo_ok := todo_ok and b is true;
  informe := informe || format(E'\n  %s authenticated y anon sin UPDATE (ninguna columna) ni DELETE sobre crm.actividades', case when b then '[OK]' else '[DIFERENTE]' end);
  informe := informe || format(E'\n  [INFO] consumidor crm.resumen_cartera_fn(): md5 %s', md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)));
  if o13 is not null and to_regclass('supabase_migrations.schema_migrations') is not null then
    informe := informe || format(E'\n  [INFO] registro en schema_migrations: %s',
      coalesce((select m.name from supabase_migrations.schema_migrations m where m.version = '20261001154153'), '(sin registrar: falta registrar.sql)'));
  end if;

  -- 4. REALIDAD: qué verá el Pipeline hoy con la misma regla (conteos sobre leads activos).
  select count(*),
         count(*) filter (where l.vendedor_id is not null),
         count(*) filter (where g.con),
         count(*) filter (where not g.con),
         count(*) filter (where l.vendedor_id is not null and l.tenencia_desde is null),
         count(*) filter (where not g.con and l.vendedor_id is not null and exists (select 1 from crm.actividades a
           where a.lead_id = l.id and a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
             and a.creado_en < l.tenencia_desde)),
         -- «Nuevo» solo porque lo que se intentó en esta tenencia se deshizo.
         count(*) filter (where not g.con and l.vendedor_id is not null and exists (select 1 from crm.actividades a
           where a.lead_id = l.id and a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
             and a.creado_en >= l.tenencia_desde))
    into r_nuevo, r_titular, r_con, r_sin, r_sin_tenencia, r_contacto_previo, r_solo_deshecho
  from crm.leads l
  -- La MISMA regla que la función: titular, tenencia y un contacto NO deshecho dentro de ella.
  cross join lateral (select (l.vendedor_id is not null and l.tenencia_desde is not null
      and exists (select 1 from crm.actividades a where a.lead_id = l.id
        and a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
        and a.creado_en >= l.tenencia_desde
        and not (a.metadata ? 'deshecho_en'))) as con) g
  where l.activo is true and l.etapa = 'nuevo';
  select count(*) into r_abiertos_sin_tenencia from crm.leads l
   where l.activo is true and l.vendedor_id is not null and l.tenencia_desde is null
     and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada');

  raise exception E'ACREDITAR cartera_filtro_gestion (solo lectura, search_path vacío)\n ESTADO: %\n ANCLAS:%\n VEREDICTO: %\n REALIDAD (leads activos en etapa «nuevo», toda la empresa): % en total · % con titular · «Gestionado» (con gestión vigente) % · «Nuevo» (sin gestión) % · de esos «Nuevo», % tienen contactos de ANTES de la tenencia actual (reasignados o reabiertos) y % lo son solo porque su intento se deshizo · con titular y SIN tenencia_desde % (saldrían siempre en «Nuevo») · abiertos con titular y sin tenencia_desde en cualquier etapa: %',
    estado, informe,
    case when not todo_ok then 'HAY DIFERENCIAS: no publicar (ni registrar) sin entenderlas'
      when o13 is null then 'todas las anclas coinciden: la migración pasaría su preflight'
      else 'todas las anclas coinciden: quedó instalado lo ensayado' end,
    r_nuevo, r_titular, r_con, r_sin, r_contacto_previo, r_solo_deshecho, r_sin_tenencia, r_abiertos_sin_tenencia;
end;
$acreditar$;

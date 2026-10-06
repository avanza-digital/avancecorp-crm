-- Control de catálogo de SOLO LECTURA. No instala ni revierte migraciones.
begin transaction read only;
set local statement_timeout = '15s';
do $control$
declare r record; f record; o oid;
begin
  for r in select * from (values
    ('private.puede_consultar_cliente_ficha(uuid)','c1afbe30f28add201886f43cd80654e9',true,'["search_path=\"\""]','postgres'),
    ('private.puede_acceder_crm()','0af3b93e54bbcf517b9a6257b5f56e1d',true,'["search_path=\"\""]','postgres'),
    ('private.vendedor_ids_visibles(uuid)','33ece9bae4828f7ffdb837c6128ca9d6',true,'["search_path=\"\""]','postgres'),
    ('private.rol_crm(uuid)','d2878a210be96ac85973d51dfcfb27a5',true,'["search_path=\"\""]','postgres'),
    ('private.inversionista_canonica(uuid)','6c7ff6001df2cb047967fa61b3ceb763',true,'["search_path=\"\""]','postgres'),
    ('private.postventa_visible(uuid)','a2828040bc65878d55efd7d4bf012d70',true,'["search_path=\"\""]','postgres'),
    ('private.gestion_diaria_citas_core(date,text,uuid,integer,timestamp with time zone,uuid)','09950bf78694c9f7dc80dc7989a8e083',false,'["search_path=\"\""]','postgres'),
    ('crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamp with time zone,uuid)','ef4e80b86b1cd7009788003294f883a8',false,'["search_path=\"\""]','postgres'),
    ('private.resolver_en_puertas_bajo_candado()','3d0fb83b13c9950461184de7c678ba64',true,'["search_path=\"\""]','postgres'),
    ('private.cartera_f5_personas_visibles(uuid)','4b294fb77677a1775f0d23aa3693be7f',true,'["search_path=\"\""]','postgres'),
    ('private.cartera_f5_personas_visibles()','ea16b975acbc58c7b24a878f443fafec',true,'["search_path=\"\""]','postgres'),
    ('crm.postventa_tarea_fn(uuid,uuid,integer,text,jsonb,uuid)','4fe2e158e6d359fcc25c64bc6624d2e5',true,'["search_path=\"\"", "lock_timeout=5s"]','postgres'),
    ('crm.postventa_estado_fn()','74cf97ec7ef00b076e5da0b2fe970056',true,'["search_path=\"\"", "lock_timeout=5s"]','postgres'),
    ('private.nombre_de_autor(uuid)','93958afa67a69c834e6d7c3a8bc82766',true,'["search_path=\"\""]','postgres'),
    ('private.gestion_diaria_equipo_ambito(uuid)','ef075bd0d064ad843f7f810a870a4b06',false,'["search_path=\"\""]','postgres'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamp with time zone,uuid)','2b8685cd63c5549a3513adb18d9a931d',false,'["search_path=\"\""]','postgres'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamp with time zone,uuid)','43f946b14f91bfd7da15d384fecdde67',false,'["search_path=\"\""]','postgres')
  ) v(firma,huella,definer,config,dueno) loop
    o:=to_regprocedure(r.firma);
    if o is null then raise exception 'Falta dependencia: %',r.firma; end if;
    select * into strict f from pg_proc where oid=o;
    if md5(f.prosrc)<>r.huella or f.prosecdef<>r.definer or to_jsonb(f.proconfig) is distinct from r.config::jsonb or pg_get_userbyid(f.proowner)<>r.dueno then
      raise exception 'Catálogo distinto del verificado: %',r.firma; end if;
  end loop;
  for r in select unnest(array['private.gestiones_validar(date,date,uuid[])','private.gestiones_clientes_eventos(date,date,uuid[],boolean,integer,text[],timestamp with time zone,uuid,text)','private.gestiones_operativas_eventos(date,date,uuid[],boolean,integer,text[],timestamp with time zone,uuid,text,text,text)','private.gestiones_clientes_identidades(jsonb)','private.gestiones_identificar_tareas(jsonb)','private.gestion_cliente_identidad(uuid,uuid)','crm.citas_clientes_fn(date,date,uuid[],integer,timestamp with time zone,uuid)','private.citas_clientes_core(date,date,uuid[],integer,timestamp with time zone,uuid)','crm.registro_actividad_v2_fn(date,date,uuid[],text[],text,integer,timestamp with time zone,uuid,text,text)','crm.gestiones_resumen_fn(date,date,uuid[])','crm.gestion_diaria_citas_v2_fn(date,text,uuid,integer,timestamp with time zone,uuid)','crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamp with time zone,uuid)']) firma loop
    if to_regprocedure(r.firma) is not null then raise exception 'Ya existe la función nueva: %',r.firma; end if;
  end loop;
  for r in select unnest(array['crm.inversionista_gestiones_autor_fecha_idx','crm.inversionista_gestiones_cierre_tarea_idx','crm.actividades_cliente_autor_fecha_idx']) nombre loop
    if to_regclass(r.nombre) is not null then raise exception 'Ya existe el índice nuevo: %',r.nombre; end if;
  end loop;
  for r in select unnest(array['crm.tareas','crm.inversionista_gestiones','crm.actividades_cliente']) nombre loop
    if not coalesce((select relrowsecurity from pg_class where oid=to_regclass(r.nombre)),false) then raise exception 'RLS ausente: %',r.nombre; end if;
  end loop;
  if has_table_privilege('anon','crm.inversionista_gestiones','SELECT') or has_table_privilege('authenticated','crm.inversionista_gestiones','SELECT') then raise exception 'El historial F6 tiene acceso directo inesperado'; end if;
end;
$control$;
select 'PASS' estado, 'antes' fase, current_database() base, current_timestamp verificado_en;
rollback;

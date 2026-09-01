-- ENSAYO de las OLAS 2 y 2b de la F7 — CONTRA PRODUCCION, SIN ESCRIBIR NADA.
--
-- 🤖 GENERADO por `scripts/generar-ensayo-f7-olas.mjs` — NO editar a mano.
--    Concatena los ARCHIVOS REALES (migraciones, registradores y marchas atras).
--    Si tocas cualquiera de ellos, vuelve a generar.
--
-- Termina SIEMPRE en `raise`: la transaccion entera se deshace. Lo unico que
-- deja es el veredicto en el mensaje de error. Doctrina «probar en produccion
-- sin escribir nada».
--
-- Los siete actos:
--   0 · foto previa del mundo
--   1 · VIAJE EN EL TIEMPO coherente — con el CHECK `f7_obs_ventana` PUESTO:
--       se mueven `cerrada_en` y `drop_no_antes_de` a la vez, bajando el
--       trigger NOMBRADO. La ventana queda SIN cumplir a proposito.
--   2 · MUTANTE DE LA VENTANA — se ejecuta el preflight REAL de cada ola y se
--       exige que ABORTE, con su mensaje. Si sobrevive, la guarda no existe.
--   3 · se cumple la ventana y corren las MIGRACIONES REALES
--   4 · corren los REGISTRADORES REALES (sus pines exigen el mundo post-DROP)
--   5 · corren las MARCHAS ATRAS REALES
--   6 · se comprueba que el mundo volvio ENTERO (definicion, comentario, ACL)
--   7 · veredicto y rollback

begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';

-- =====================================================================
-- ACTO 0 · FOTO PREVIA
-- =====================================================================
do $acto0$
declare v_n int;
begin
  select count(*) into v_n from private.f7_piezas_en_observacion;
  raise notice 'ACTO 0 · el libro tiene % piezas', v_n;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'ENSAYO ABORTADO: % alerta(s) del vigia abiertas — stop-the-line', v_n;
  end if;
end $acto0$;

-- =====================================================================
-- ACTO 1 · VIAJE EN EL TIEMPO, CON EL CHECK PUESTO.
-- El CHECK exige drop_no_antes_de >= cerrada_en + 14, y el trigger congela
-- `cerrada_en` y prohibe encoger la ventana. Se baja el trigger NOMBRADO, se
-- mueven las DOS fechas de forma coherente, y se vuelve a subir. El CHECK no
-- se toca en ningun momento: la migracion se probara con su guarda instalada.
-- La ventana queda a MAÑANA — sin cumplir — para el mutante del ACTO 2.
-- =====================================================================
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set cerrada_en = (now() at time zone 'America/Lima')::date - 14,
       drop_no_antes_de = (now() at time zone 'America/Lima')::date + 1
 where ola = 'F5.d' and estado = 'observacion';
update private.f7_piezas_en_observacion
   set cerrada_en = (now() at time zone 'America/Lima')::date - 14,
       drop_no_antes_de = (now() at time zone 'America/Lima')::date + 1
 where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'observacion';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- =====================================================================
-- ACTO 2 · EL MUTANTE DE LA VENTANA. Se ejecuta el preflight REAL —el del
-- archivo, no una copia— y se exige que ABORTE por la ventana. Se comprueba el
-- TEXTO del error: un fallo de sintaxis tambien aborta, y contarlo como exito
-- seria justo el falso verde que esta auditoria vino a matar.
-- =====================================================================
do $acto2$
declare v_cazado boolean; v_msg text;
begin
  -- (2a) OLA 2
  v_cazado := false;
  begin
    execute $mutante_sql$do $ola2_pre$
declare
  -- firma | huella del CUERPO | huella de la DEFINICION COMPLETA | comentario vivo
  -- (capturado de produccion el 2026-09-01; donde pone null, el comentario ES null).
  v_pin constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          '8640b1246f620ab40558cec2875ada23','956fb5f32191291d4b7ebafce5abbdb1', null],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          '4156191492c25479be73b0365263d946','1d884ef9f60a55dd4d0613a256e3ea71', null],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
          '06f79b07b4d65dcf50cd4359fb598723','a93f2db825cc26c19b1756cde0cdc435', null],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',
          '1148d0ca1beb33797995eeff3c579bd4','230bcc46e72191600cbd5fc789e1d503', null],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          'b7e0de18b559ec7fd650619cd22b9cb5','c786d25a9aca26f6a818dd57abe6ef72',
          'Corrección Portal catalogada que además conserva la coherencia de la cuenta bancaria contractual.'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          'f0e519cc4ee79c9334ae59a23844b23b','7128b0ebb65497e67c56d5383988b512',
          'Corrección Portal catalogada; conserva Admin/Superadmin/Analista, cartera, ventana y cierres de public.actualizar_contrato.'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',
          '893c857e27ec6405a3ac6e291458c346','58f41209f1cedf46198e7c76903f7bbb',
          'Alta Portal catalogada; conserva la autorización de public.crear_contrato y fija la condición en la misma transacción.']
  ];
  v_firmas constant text[] := array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)'
  ];
  -- Nombres desnudos para el censo de texto (sin esquema ni argumentos).
  v_nombres constant text[] := array[
    'actualizar_contrato_con_cuenta_producto','actualizar_contrato_producto',
    'crear_contrato_con_cuenta_producto','crear_contrato_producto'
  ];
  v_fila text[]; v_h text; v_hd text; v_com text; v_own text;
  v_n int; v_hoy date; v_verd text; v_detalle text; v_estado text;
  v_cuando timestamptz; v_oids oid[];
begin
  v_hoy := (now() at time zone 'America/Lima')::date;

  -- ------------------------------------------------------------------
  -- (a) LA VENTANA, POR FIRMA. No se cuenta la ola: se exige que CADA UNA
  --     de las siete este en el libro, en observacion, con su OK escrito y
  --     con su fecha cumplida. Una fila sustituida ya no pasa por conteo.
  -- ------------------------------------------------------------------
  select count(*), string_agg(f.firma || ' → ' || coalesce(
           (select l.estado || ', demolible ' || coalesce(l.drop_no_antes_de::text,'SIN FECHA')
              from private.f7_piezas_en_observacion l where l.firma = f.firma),
           'NO ESTA EN EL LIBRO'), ' | ')
    into v_n, v_detalle
  from unnest(v_firmas) as f(firma)
  where not exists (
    select 1 from private.f7_piezas_en_observacion l
     where l.firma = f.firma and l.ola = 'F5.d' and l.estado = 'observacion'
       and length(l.ok_miguel) >= 20
       and l.drop_no_antes_de is not null
       and l.drop_no_antes_de::date <= v_hoy);
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % de las 7 firmas no estan listas (hoy % en Lima). %', v_n, v_hoy, v_detalle;
  end if;

  -- Y la cohorte F5.d no tiene NINGUNA fila de mas: el conjunto es exacto.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and not (firma = any (v_firmas));
  if v_n > 0 then
    raise exception 'OLA 2 preflight: la cohorte F5.d tiene % fila(s) que NO son de las siete firmas — investigar antes de demoler', v_n;
  end if;

  -- ------------------------------------------------------------------
  -- (b) STOP-THE-LINE CON VIGIA VIVO. Cero alertas abiertas NO basta:
  --     un vigilante apagado tambien devuelve cero. Se exige que el cron
  --     exista, este activo, tenga el comando exacto, y que su ULTIMA
  --     corrida sea reciente y exitosa.
  -- ------------------------------------------------------------------
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: hay % alerta(s) del vigia sin resolver. Stop-the-line: se atienden ANTES y en otro paquete.', v_n;
  end if;

  select count(*) into v_n from cron.job j
   where j.jobname = 'crm-f7-piezas-vigia' and j.active
     and j.command = 'select private.vigia_f7_piezas()' and j.database = 'postgres';
  if v_n <> 1 then
    raise exception 'OLA 2 preflight: el cron del vigia F7 no esta vivo con su comando exacto (coincidencias: %)', v_n;
  end if;

  select r.status, r.start_time into v_estado, v_cuando
  from cron.job_run_details r
  join cron.job j on j.jobid = r.jobid
  where j.jobname = 'crm-f7-piezas-vigia'
  order by r.start_time desc limit 1;
  if v_estado is null then
    raise exception 'OLA 2 preflight: el vigia F7 no tiene NINGUNA corrida registrada — no hay observacion que acreditar';
  end if;
  if v_estado <> 'succeeded' then
    raise exception 'OLA 2 preflight: la ultima corrida del vigia F7 fue «%» (%). Cero alertas no prueba nada con el vigilante en rojo.', v_estado, v_cuando;
  end if;
  if v_cuando < now() - interval '48 hours' then
    raise exception 'OLA 2 preflight: la ultima corrida del vigia F7 es del % — lleva mas de 48h sin observar', v_cuando;
  end if;

  -- El censo estructural del propio guardian, ANTES de tocar nada.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 preflight: el vigilante F7 ya esta en rojo ANTES de demoler: %', v_verd;
  end if;

  -- ------------------------------------------------------------------
  -- (c) SON LAS QUE MEDI, ENTERAS. Cuerpo + definicion completa (que
  --     arrastra args, retorno, volatilidad, SECURITY DEFINER, search_path,
  --     STRICT, coste y filas) + owner + comentario.
  -- ------------------------------------------------------------------
  foreach v_fila slice 1 in array v_pin loop
    select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
           obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
      into v_h, v_hd, v_com, v_own
    from pg_proc p where p.oid = to_regprocedure(v_fila[1]);
    if v_h is null then
      raise exception 'OLA 2 preflight: % ya no existe — investigar antes de seguir', v_fila[1];
    end if;
    if v_h is distinct from v_fila[2] then
      raise exception 'OLA 2 preflight: % cambio de CUERPO desde la captura (huella %)', v_fila[1], v_h;
    end if;
    if v_hd is distinct from v_fila[3] then
      raise exception 'OLA 2 preflight: % cambio de DEFINICION desde la captura (huella %) — volatilidad, search_path, SECURITY DEFINER o atributos derivaron', v_fila[1], v_hd;
    end if;
    if v_com is distinct from v_fila[4] then
      raise exception 'OLA 2 preflight: % cambio de COMENTARIO desde la captura — la marcha atras dejaria de ser fiel', v_fila[1];
    end if;
    if v_own is distinct from 'postgres' then
      raise exception 'OLA 2 preflight: % cambio de dueño a «%» — la marcha atras no sabria reconstruirla', v_fila[1], v_own;
    end if;
  end loop;

  -- ------------------------------------------------------------------
  -- (d) SIGUEN CERRADAS, POR PRIVILEGIO EFECTIVO. `aclexplode(NULL)` no
  --     devuelve filas y una funcion con ACL por defecto concede EXECUTE a
  --     PUBLIC: leer `proacl` a secas es un falso verde. Se lee el ACL
  --     EFECTIVO (`acldefault` cuando es NULL) y ademas se pregunta por
  --     privilegio efectivo — que SI ve las concesiones por membresia.
  -- ------------------------------------------------------------------
  select count(*) into v_n
  from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = any (array(select to_regprocedure(f) from unnest(v_firmas) f))
    and a.privilege_type = 'EXECUTE' and a.grantee is distinct from p.proowner;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % concesion(es) EXECUTE efectivas fuera del dueño — alguien las reabrio', v_n;
  end if;

  select string_agg(f.firma || '→' || r.rol, '; ') into v_detalle
  from unnest(v_firmas) as f(firma),
       unnest(array['anon','authenticated','service_role']) as r(rol)
  where has_function_privilege(r.rol, to_regprocedure(f.firma), 'EXECUTE');
  if v_detalle is not null then
    raise exception 'OLA 2 preflight: privilegio EFECTIVO de ejecucion todavia vivo: %', v_detalle;
  end if;

  -- ------------------------------------------------------------------
  -- (e) EL CENSO EXHAUSTIVO, INMEDIATAMENTE ANTES DEL DROP. `DROP FUNCTION`
  --     sin CASCADE frena las dependencias que Postgres registra, pero NO
  --     ve los nombres dentro de cuerpos guardados como texto. Se miran
  --     nueve superficies, en TODOS los esquemas.
  -- ------------------------------------------------------------------
  v_oids := array(select to_regprocedure(f) from unnest(v_firmas) f);

  with censo as (
    -- 1) dependencias que Postgres SI registra
    select 'pg_depend'::text as fuente,
           coalesce(d.classid::regclass::text,'?') || ' #' || d.objid::text as objeto
      from pg_depend d
     where d.refclassid = 'pg_proc'::regclass and d.refobjid = any (v_oids)
       and d.deptype in ('n','a')
    union all
    -- 2) cuerpos plpgsql/sql clasicos (todos los esquemas, todas las funciones)
    select 'pg_proc.prosrc', p.oid::regprocedure::text
      from pg_proc p, unnest(v_nombres) as t(nom)
     where p.prosrc is not null and strpos(lower(p.prosrc), lower(t.nom)) > 0
       and not (p.oid = any (v_oids))
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    -- 3) cuerpos SQL estandar (BEGIN ATOMIC), que no viven en `prosrc`
    select 'pg_proc.prosqlbody', p.oid::regprocedure::text
      from pg_proc p, unnest(v_nombres) as t(nom)
     where p.prosqlbody is not null
       and strpos(lower(pg_get_function_sqlbody(p.oid)), lower(t.nom)) > 0
       and not (p.oid = any (v_oids))
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    -- 4) vistas y vistas materializadas
    select 'vista', c.oid::regclass::text
      from pg_class c, unnest(v_nombres) as t(nom)
     where c.relkind in ('v','m') and strpos(lower(pg_get_viewdef(c.oid)), lower(t.nom)) > 0
    union all
    -- 5) policies de RLS
    select 'policy', pol.polname || ' on ' || pol.polrelid::regclass::text
      from pg_policy pol, unnest(v_nombres) as t(nom)
     where strpos(lower(coalesce(pg_get_expr(pol.polqual, pol.polrelid),'')
                     || ' ' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid),'')), lower(t.nom)) > 0
    union all
    -- 6) defaults y columnas generadas
    select 'default/generada', ad.adrelid::regclass::text || '.' || a.attname
      from pg_attrdef ad
      join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum,
           unnest(v_nombres) as t(nom)
     where strpos(lower(pg_get_expr(ad.adbin, ad.adrelid)), lower(t.nom)) > 0
    union all
    -- 7) constraints (CHECK con llamada a funcion)
    select 'constraint', con.conname || ' on ' || coalesce(con.conrelid::regclass::text,'-')
      from pg_constraint con, unnest(v_nombres) as t(nom)
     where strpos(lower(pg_get_constraintdef(con.oid)), lower(t.nom)) > 0
    union all
    -- 8) indices de expresion y parciales
    select 'indice', i.indexrelid::regclass::text
      from pg_index i, unnest(v_nombres) as t(nom)
     where (i.indexprs is not null or i.indpred is not null)
       and strpos(lower(pg_get_indexdef(i.indexrelid)), lower(t.nom)) > 0
    union all
    -- 9) trabajos programados
    select 'cron.job', j.jobname
      from cron.job j, unnest(v_nombres) as t(nom)
     where strpos(lower(j.command), lower(t.nom)) > 0
  )
  select count(*), string_agg(fuente || ': ' || objeto, ' | ') into v_n, v_detalle from censo;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: el censo encontro % referencia(s) VIVA(s) a las gemelas — resolverlas primero. %', v_n, v_detalle;
  end if;
end $ola2_pre$;$mutante_sql$;
  exception when others then
    v_cazado := true; v_msg := sqlerrm;
  end;
  if not v_cazado then
    raise exception 'MUTANTE-VENTANA OLA 2 SOBREVIVIO: el preflight no aborto con la ventana sin cumplir';
  end if;
  -- 🔎 La guarda de la Ola 2 es COMPUESTA (firma, ola, estado, OK y fecha), asi
  --    que «no estan listas» sola NO identifica la causa temporal: podria venir
  --    de un libro alterado. Se exige ademas que el detalle nombre la fecha de
  --    MAÑANA, que es exactamente lo que el viaje en el tiempo puso — y que solo
  --    puede salir de la rama de la ventana. (Lo pidio Codex en la 2.ª vuelta.)
  if v_msg not like '%no estan listas%' then
    raise exception 'MUTANTE-VENTANA OLA 2: aborto, pero por OTRA razon (%). La guarda temporal no esta probada.', v_msg;
  end if;
  if v_msg not like ('%demolible ' || ((now() at time zone 'America/Lima')::date + 1)::text || '%') then
    raise exception 'MUTANTE-VENTANA OLA 2: aborto por «no estan listas» pero SIN nombrar la fecha futura (%) — la causa no era la ventana: %',
      ((now() at time zone 'America/Lima')::date + 1), v_msg;
  end if;
  raise notice 'ACTO 2a · mutante de ventana CAZADO por el preflight real: %', v_msg;

  -- (2b) OLA 2b
  v_cazado := false;
  begin
    execute $mutante_sql$do $ola2b_pre$
declare
  v_firma  constant text := 'crm.metricas_altas_analista_fn(integer)';
  v_cuerpo constant text := 'df8a99e0dfc4e1d94794073787aa84d7';
  v_defin  constant text := 'f439e788e16a49fa23d8b52c0047f929';
  v_coment constant text := 'Agregado para gráfica de gerencia: altas de clientes por mes y por analista (nombra SOLO al asesor interno, nunca al cliente). Mismo ámbito por rol.';
  v_nombre constant text := 'metricas_altas_analista_fn';
  -- Las dos del bridge NO se tocan: se comprueba que siguen intactas.
  v_bridge constant text[] := array[
    'crm.metricas_distribucion_leads_fn(date,date)',
    'crm.metricas_distribucion_leads_v2_fn(date,date)'];
  v_h text; v_hd text; v_com text; v_own text; v_estado text;
  v_cuando timestamptz; v_n int; v_hoy date; v_ventana date;
  v_verd text; v_detalle text; v_oid oid;
begin
  v_hoy := (now() at time zone 'America/Lima')::date;

  -- (a) LA VENTANA, de su propia fila del libro.
  select f.drop_no_antes_de::date into v_ventana
    from private.f7_piezas_en_observacion f
   where f.firma = v_firma and f.ola = 'F7.1' and f.estado = 'observacion'
     and length(f.ok_miguel) >= 20;
  if v_ventana is null then
    raise exception 'OLA 2b preflight: % no esta en el libro como F7.1 en observacion con su OK y su fecha', v_firma;
  end if;
  if v_ventana > v_hoy then
    raise exception 'OLA 2b preflight: % sigue en su ventana (demolible desde %, hoy % en Lima)', v_firma, v_ventana, v_hoy;
  end if;

  -- (b) STOP-THE-LINE CON VIGIA VIVO (cero alertas de un vigilante muerto
  --     tambien es cero: se exige el cron activo, con su comando exacto, y una
  --     ultima corrida reciente y exitosa).
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % alerta(s) del vigia sin resolver — stop-the-line', v_n;
  end if;

  select count(*) into v_n from cron.job j
   where j.jobname = 'crm-f7-piezas-vigia' and j.active
     and j.command = 'select private.vigia_f7_piezas()' and j.database = 'postgres';
  if v_n <> 1 then
    raise exception 'OLA 2b preflight: el cron del vigia F7 no esta vivo con su comando exacto (coincidencias: %)', v_n;
  end if;

  select r.status, r.start_time into v_estado, v_cuando
  from cron.job_run_details r
  join cron.job j on j.jobid = r.jobid
  where j.jobname = 'crm-f7-piezas-vigia'
  order by r.start_time desc limit 1;
  if v_estado is null then
    raise exception 'OLA 2b preflight: el vigia F7 no tiene NINGUNA corrida registrada';
  end if;
  if v_estado <> 'succeeded' then
    raise exception 'OLA 2b preflight: la ultima corrida del vigia F7 fue «%» (%)', v_estado, v_cuando;
  end if;
  if v_cuando < now() - interval '48 hours' then
    raise exception 'OLA 2b preflight: la ultima corrida del vigia F7 es del % — mas de 48h sin observar', v_cuando;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2b preflight: el vigilante F7 ya esta en rojo ANTES de demoler: %', v_verd;
  end if;

  -- (c) ES LA QUE MEDI, ENTERA: cuerpo + definicion completa + comentario + dueño.
  v_oid := to_regprocedure(v_firma);
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
         obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
    into v_h, v_hd, v_com, v_own
  from pg_proc p where p.oid = v_oid;
  if v_h is null then
    raise exception 'OLA 2b preflight: % ya no existe', v_firma;
  end if;
  if v_h is distinct from v_cuerpo then
    raise exception 'OLA 2b preflight: % cambio de CUERPO desde la captura (huella %)', v_firma, v_h;
  end if;
  if v_hd is distinct from v_defin then
    raise exception 'OLA 2b preflight: % cambio de DEFINICION desde la captura (huella %)', v_firma, v_hd;
  end if;
  if v_com is distinct from v_coment then
    raise exception 'OLA 2b preflight: % cambio de COMENTARIO — la marcha atras dejaria de ser fiel', v_firma;
  end if;
  if v_own is distinct from 'postgres' then
    raise exception 'OLA 2b preflight: % cambio de dueño a «%»', v_firma, v_own;
  end if;

  -- (d) SIGUE CERRADA, POR PRIVILEGIO EFECTIVO (con `acldefault` para el caso
  --     `proacl IS NULL`, que concede EXECUTE a PUBLIC y daba falso verde).
  select count(*) into v_n
  from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = v_oid and a.privilege_type = 'EXECUTE'
    and a.grantee is distinct from p.proowner;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % concesion(es) EXECUTE efectivas fuera del dueño', v_n;
  end if;

  select string_agg(r.rol, ', ') into v_detalle
  from unnest(array['anon','authenticated','service_role']) as r(rol)
  where has_function_privilege(r.rol, v_oid, 'EXECUTE');
  if v_detalle is not null then
    raise exception 'OLA 2b preflight: privilegio EFECTIVO de ejecucion todavia vivo para: %', v_detalle;
  end if;

  -- (e) LAS DOS DEL BRIDGE, INTACTAS ANTES DE EMPEZAR (esta migracion no las toca).
  select count(*) into v_n from unnest(v_bridge) as b(firma)
   where to_regprocedure(b.firma) is null;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % funcion(es) del bridge ya no existen — el mundo no es el que esta migracion asume', v_n;
  end if;

  -- (f) EL CENSO EXHAUSTIVO, INMEDIATAMENTE ANTES DEL DROP: nueve superficies,
  --     todos los esquemas.
  with censo as (
    select 'pg_depend'::text as fuente,
           coalesce(d.classid::regclass::text,'?') || ' #' || d.objid::text as objeto
      from pg_depend d
     where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_oid
       and d.deptype in ('n','a')
    union all
    select 'pg_proc.prosrc', p.oid::regprocedure::text
      from pg_proc p
     where p.prosrc is not null and strpos(lower(p.prosrc), v_nombre) > 0
       and p.oid <> v_oid
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    select 'pg_proc.prosqlbody', p.oid::regprocedure::text
      from pg_proc p
     where p.prosqlbody is not null
       and strpos(lower(pg_get_function_sqlbody(p.oid)), v_nombre) > 0
       and p.oid <> v_oid
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    select 'vista', c.oid::regclass::text from pg_class c
     where c.relkind in ('v','m') and strpos(lower(pg_get_viewdef(c.oid)), v_nombre) > 0
    union all
    select 'policy', pol.polname || ' on ' || pol.polrelid::regclass::text from pg_policy pol
     where strpos(lower(coalesce(pg_get_expr(pol.polqual, pol.polrelid),'')
                     || ' ' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid),'')), v_nombre) > 0
    union all
    select 'default/generada', ad.adrelid::regclass::text || '.' || a.attname
      from pg_attrdef ad join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
     where strpos(lower(pg_get_expr(ad.adbin, ad.adrelid)), v_nombre) > 0
    union all
    select 'constraint', con.conname || ' on ' || coalesce(con.conrelid::regclass::text,'-')
      from pg_constraint con
     where strpos(lower(pg_get_constraintdef(con.oid)), v_nombre) > 0
    union all
    select 'indice', i.indexrelid::regclass::text from pg_index i
     where (i.indexprs is not null or i.indpred is not null)
       and strpos(lower(pg_get_indexdef(i.indexrelid)), v_nombre) > 0
    union all
    select 'cron.job', j.jobname from cron.job j
     where strpos(lower(j.command), v_nombre) > 0
  )
  select count(*), string_agg(fuente || ': ' || objeto, ' | ') into v_n, v_detalle from censo;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: el censo encontro % referencia(s) VIVA(s) al tablero — resolverlas primero. %', v_n, v_detalle;
  end if;
end $ola2b_pre$;$mutante_sql$;
  exception when others then
    v_cazado := true; v_msg := sqlerrm;
  end;
  if not v_cazado then
    raise exception 'MUTANTE-VENTANA OLA 2b SOBREVIVIO: el preflight no aborto con la ventana sin cumplir';
  end if;
  if v_msg not like '%sigue en su ventana%' then
    raise exception 'MUTANTE-VENTANA OLA 2b: aborto, pero por OTRA razon (%)', v_msg;
  end if;
  raise notice 'ACTO 2b · mutante de ventana CAZADO por el preflight real: %', v_msg;
end $acto2$;

-- =====================================================================
-- ACTO 3 · SE CUMPLE LA VENTANA (hoy) y corren las MIGRACIONES REALES.
-- =====================================================================
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set drop_no_antes_de = (now() at time zone 'America/Lima')::date
 where estado = 'observacion'
   and (ola = 'F5.d' or firma = 'crm.metricas_altas_analista_fn(integer)');
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- ---------- MIGRACION REAL: 20260913130000_crm_f7_ola2_demoler_las_siete_gemelas_v2.sql ----------
-- P-055 F7 · OLA 2 v2 — DEMOLER LAS SIETE GEMELAS DEL CATALOGO VIEJO.
--
-- Tercer paso del metodo de Miguel: CERRAR (F5.d, 30/08, registro 186) →
-- OBSERVAR (14 dias) → DERRIBAR. Las siete llevan revocadas desde el 30/08:
-- nadie puede llamarlas, y su intento muere en 42501 antes del cuerpo.
--
-- ⛔ NO SE PUEDE APLICAR ANTES DEL 2026-09-13. No es disciplina: el libro
--    guarda `drop_no_antes_de` por fila y el preflight lo exige POR FIRMA. Si
--    se corre antes, ABORTA — y esta bien que aborte.
--
-- ✏️ POR QUE HAY UNA v2 — la v1 (`20260913120000`, commit 9695d67) NUNCA se
--    aplico en ningun sitio: el registro remoto va por 196 y esta va fechada el
--    13/09. Se commiteo declarada «lista para correr» y la segunda auditoria de
--    Codex la devolvio NO-GO. Como las migraciones commiteadas NO se editan
--    (regla del CRM, con guardian que la hace cumplir), la v1 se RETIRA del
--    arbol en el mismo commit que trae esta v2 — no puede quedarse: un replay
--    de banco aplica por orden de version y habria demolido con los preflights
--    debiles. Queda anotado en MIGRACIONES.md.
--
--    Los siete falsos verdes de la v1, corregidos aqui:
--     ① exigia SIETE FILAS de la ola F5.d, no las SIETE FIRMAS exactas: una
--       fila sustituida cumplia el conteo con el conjunto equivocado;
--     ② el stop-the-line contaba alertas abiertas pero no miraba al VIGIA:
--       pasaba con el cron apagado, roto o sin correr en dias (cero alertas
--       tambien es lo que devuelve un vigilante muerto);
--     ③ la huella cubria solo `prosrc`: owner, SECURITY DEFINER, volatilidad,
--       `search_path`, STRICT, coste, filas o comentario podian derivar sin que
--       nadie se enterara. Ahora se fija `pg_get_functiondef` ENTERA + owner +
--       comentario;
--     ④ el ACL se leia con `aclexplode(proacl)`, y `aclexplode(NULL)` no
--       devuelve filas: una funcion con ACL por defecto (que concede EXECUTE a
--       PUBLIC) daba VERDE. Ahora se lee el ACL EFECTIVO con `acldefault` y se
--       pregunta ademas por privilegio efectivo a los tres roles de la API;
--     ⑤ «nadie vivo las nombra» miraba solo `prosrc` de tres esquemas. Ahora el
--       censo cubre `pg_depend`, `prosrc`, `prosqlbody`, vistas, policies,
--       defaults, columnas generadas, constraints, indices de expresion y
--       `cron.job`, en TODOS los esquemas;
--     ⑥ el acta se escribia por `ola`, sin comprobar cuantas filas movio;
--     ⑦ el postflight buscaba por `proname` (un overload nuevo daba falso rojo)
--       y aceptaba la puerta VIEJA como prueba de vida: ahora fija por firma
--       exacta las puertas vivas PDF v2/v3 y el trigger de snapshot.
--
-- MATERIAL DE MARCHA ATRAS: `scripts/rollback-f7-ola2-gemelas.sql` recrea las
-- siete con su DEFINICION VIVA capturada de produccion el 01/09 (owner, ACL,
-- atributos y COMENTARIOS incluidos). El repo tiene 167 de 196 archivos y la
-- F5.d cambio sus cuerpos despues de nacer: la fuente es el REGISTRO y el
-- catalogo vivo, jamas la carpeta local.
--
-- ARTEFACTOS — 📌 MEDIDO, no supuesto: el oraculo
-- `scripts/test-productos-inversion.sql` NO hay que podarlo, y demolerlas NO
-- pone rojo `gate:config`. Ese oraculo es AUTOCONTENIDO: el gate le crea un
-- clon de `template0` (`gate-config-operativa.mjs`) y el propio archivo hace
-- `\ir` de `20260807203751` y `20260807235933`, o sea que se recrea las gemelas
-- antes de probarlas. Su mundo no depende de produccion. La primera auditoria
-- afirmo lo contrario y la segunda lo REFUTO ella misma.
-- El que SI se ponia rojo era `test-rls.mjs`, que corre contra un Supabase de
-- verdad y exigia `42501` exacto: ya acepta `42501` (cerrada) o `PGRST202`
-- (demolida) para estas siete firmas, y solo para ellas.
--
-- Publicacion (Miguel, con `!`): esta migracion → registrar-f7-ola2-version.sql
-- → gates → advisors.

-- [ensayo] begin; retirado (20260913130000_crm_f7_ola2_demoler_las_siete_gemelas_v2.sql)

set local lock_timeout = '5s';
set local statement_timeout = '300s';

-- =====================================================================
-- 0) PREFLIGHT: la ventana, el libro, el vigia, las huellas y el censo.
-- =====================================================================
do $ola2_pre$
declare
  -- firma | huella del CUERPO | huella de la DEFINICION COMPLETA | comentario vivo
  -- (capturado de produccion el 2026-09-01; donde pone null, el comentario ES null).
  v_pin constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          '8640b1246f620ab40558cec2875ada23','956fb5f32191291d4b7ebafce5abbdb1', null],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          '4156191492c25479be73b0365263d946','1d884ef9f60a55dd4d0613a256e3ea71', null],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
          '06f79b07b4d65dcf50cd4359fb598723','a93f2db825cc26c19b1756cde0cdc435', null],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',
          '1148d0ca1beb33797995eeff3c579bd4','230bcc46e72191600cbd5fc789e1d503', null],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          'b7e0de18b559ec7fd650619cd22b9cb5','c786d25a9aca26f6a818dd57abe6ef72',
          'Corrección Portal catalogada que además conserva la coherencia de la cuenta bancaria contractual.'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          'f0e519cc4ee79c9334ae59a23844b23b','7128b0ebb65497e67c56d5383988b512',
          'Corrección Portal catalogada; conserva Admin/Superadmin/Analista, cartera, ventana y cierres de public.actualizar_contrato.'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',
          '893c857e27ec6405a3ac6e291458c346','58f41209f1cedf46198e7c76903f7bbb',
          'Alta Portal catalogada; conserva la autorización de public.crear_contrato y fija la condición en la misma transacción.']
  ];
  v_firmas constant text[] := array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)'
  ];
  -- Nombres desnudos para el censo de texto (sin esquema ni argumentos).
  v_nombres constant text[] := array[
    'actualizar_contrato_con_cuenta_producto','actualizar_contrato_producto',
    'crear_contrato_con_cuenta_producto','crear_contrato_producto'
  ];
  v_fila text[]; v_h text; v_hd text; v_com text; v_own text;
  v_n int; v_hoy date; v_verd text; v_detalle text; v_estado text;
  v_cuando timestamptz; v_oids oid[];
begin
  v_hoy := (now() at time zone 'America/Lima')::date;

  -- ------------------------------------------------------------------
  -- (a) LA VENTANA, POR FIRMA. No se cuenta la ola: se exige que CADA UNA
  --     de las siete este en el libro, en observacion, con su OK escrito y
  --     con su fecha cumplida. Una fila sustituida ya no pasa por conteo.
  -- ------------------------------------------------------------------
  select count(*), string_agg(f.firma || ' → ' || coalesce(
           (select l.estado || ', demolible ' || coalesce(l.drop_no_antes_de::text,'SIN FECHA')
              from private.f7_piezas_en_observacion l where l.firma = f.firma),
           'NO ESTA EN EL LIBRO'), ' | ')
    into v_n, v_detalle
  from unnest(v_firmas) as f(firma)
  where not exists (
    select 1 from private.f7_piezas_en_observacion l
     where l.firma = f.firma and l.ola = 'F5.d' and l.estado = 'observacion'
       and length(l.ok_miguel) >= 20
       and l.drop_no_antes_de is not null
       and l.drop_no_antes_de::date <= v_hoy);
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % de las 7 firmas no estan listas (hoy % en Lima). %', v_n, v_hoy, v_detalle;
  end if;

  -- Y la cohorte F5.d no tiene NINGUNA fila de mas: el conjunto es exacto.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and not (firma = any (v_firmas));
  if v_n > 0 then
    raise exception 'OLA 2 preflight: la cohorte F5.d tiene % fila(s) que NO son de las siete firmas — investigar antes de demoler', v_n;
  end if;

  -- ------------------------------------------------------------------
  -- (b) STOP-THE-LINE CON VIGIA VIVO. Cero alertas abiertas NO basta:
  --     un vigilante apagado tambien devuelve cero. Se exige que el cron
  --     exista, este activo, tenga el comando exacto, y que su ULTIMA
  --     corrida sea reciente y exitosa.
  -- ------------------------------------------------------------------
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: hay % alerta(s) del vigia sin resolver. Stop-the-line: se atienden ANTES y en otro paquete.', v_n;
  end if;

  select count(*) into v_n from cron.job j
   where j.jobname = 'crm-f7-piezas-vigia' and j.active
     and j.command = 'select private.vigia_f7_piezas()' and j.database = 'postgres';
  if v_n <> 1 then
    raise exception 'OLA 2 preflight: el cron del vigia F7 no esta vivo con su comando exacto (coincidencias: %)', v_n;
  end if;

  select r.status, r.start_time into v_estado, v_cuando
  from cron.job_run_details r
  join cron.job j on j.jobid = r.jobid
  where j.jobname = 'crm-f7-piezas-vigia'
  order by r.start_time desc limit 1;
  if v_estado is null then
    raise exception 'OLA 2 preflight: el vigia F7 no tiene NINGUNA corrida registrada — no hay observacion que acreditar';
  end if;
  if v_estado <> 'succeeded' then
    raise exception 'OLA 2 preflight: la ultima corrida del vigia F7 fue «%» (%). Cero alertas no prueba nada con el vigilante en rojo.', v_estado, v_cuando;
  end if;
  if v_cuando < now() - interval '48 hours' then
    raise exception 'OLA 2 preflight: la ultima corrida del vigia F7 es del % — lleva mas de 48h sin observar', v_cuando;
  end if;

  -- El censo estructural del propio guardian, ANTES de tocar nada.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 preflight: el vigilante F7 ya esta en rojo ANTES de demoler: %', v_verd;
  end if;

  -- ------------------------------------------------------------------
  -- (c) SON LAS QUE MEDI, ENTERAS. Cuerpo + definicion completa (que
  --     arrastra args, retorno, volatilidad, SECURITY DEFINER, search_path,
  --     STRICT, coste y filas) + owner + comentario.
  -- ------------------------------------------------------------------
  foreach v_fila slice 1 in array v_pin loop
    select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
           obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
      into v_h, v_hd, v_com, v_own
    from pg_proc p where p.oid = to_regprocedure(v_fila[1]);
    if v_h is null then
      raise exception 'OLA 2 preflight: % ya no existe — investigar antes de seguir', v_fila[1];
    end if;
    if v_h is distinct from v_fila[2] then
      raise exception 'OLA 2 preflight: % cambio de CUERPO desde la captura (huella %)', v_fila[1], v_h;
    end if;
    if v_hd is distinct from v_fila[3] then
      raise exception 'OLA 2 preflight: % cambio de DEFINICION desde la captura (huella %) — volatilidad, search_path, SECURITY DEFINER o atributos derivaron', v_fila[1], v_hd;
    end if;
    if v_com is distinct from v_fila[4] then
      raise exception 'OLA 2 preflight: % cambio de COMENTARIO desde la captura — la marcha atras dejaria de ser fiel', v_fila[1];
    end if;
    if v_own is distinct from 'postgres' then
      raise exception 'OLA 2 preflight: % cambio de dueño a «%» — la marcha atras no sabria reconstruirla', v_fila[1], v_own;
    end if;
  end loop;

  -- ------------------------------------------------------------------
  -- (d) SIGUEN CERRADAS, POR PRIVILEGIO EFECTIVO. `aclexplode(NULL)` no
  --     devuelve filas y una funcion con ACL por defecto concede EXECUTE a
  --     PUBLIC: leer `proacl` a secas es un falso verde. Se lee el ACL
  --     EFECTIVO (`acldefault` cuando es NULL) y ademas se pregunta por
  --     privilegio efectivo — que SI ve las concesiones por membresia.
  -- ------------------------------------------------------------------
  select count(*) into v_n
  from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = any (array(select to_regprocedure(f) from unnest(v_firmas) f))
    and a.privilege_type = 'EXECUTE' and a.grantee is distinct from p.proowner;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % concesion(es) EXECUTE efectivas fuera del dueño — alguien las reabrio', v_n;
  end if;

  select string_agg(f.firma || '→' || r.rol, '; ') into v_detalle
  from unnest(v_firmas) as f(firma),
       unnest(array['anon','authenticated','service_role']) as r(rol)
  where has_function_privilege(r.rol, to_regprocedure(f.firma), 'EXECUTE');
  if v_detalle is not null then
    raise exception 'OLA 2 preflight: privilegio EFECTIVO de ejecucion todavia vivo: %', v_detalle;
  end if;

  -- ------------------------------------------------------------------
  -- (e) EL CENSO EXHAUSTIVO, INMEDIATAMENTE ANTES DEL DROP. `DROP FUNCTION`
  --     sin CASCADE frena las dependencias que Postgres registra, pero NO
  --     ve los nombres dentro de cuerpos guardados como texto. Se miran
  --     nueve superficies, en TODOS los esquemas.
  -- ------------------------------------------------------------------
  v_oids := array(select to_regprocedure(f) from unnest(v_firmas) f);

  with censo as (
    -- 1) dependencias que Postgres SI registra
    select 'pg_depend'::text as fuente,
           coalesce(d.classid::regclass::text,'?') || ' #' || d.objid::text as objeto
      from pg_depend d
     where d.refclassid = 'pg_proc'::regclass and d.refobjid = any (v_oids)
       and d.deptype in ('n','a')
    union all
    -- 2) cuerpos plpgsql/sql clasicos (todos los esquemas, todas las funciones)
    select 'pg_proc.prosrc', p.oid::regprocedure::text
      from pg_proc p, unnest(v_nombres) as t(nom)
     where p.prosrc is not null and strpos(lower(p.prosrc), lower(t.nom)) > 0
       and not (p.oid = any (v_oids))
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    -- 3) cuerpos SQL estandar (BEGIN ATOMIC), que no viven en `prosrc`
    select 'pg_proc.prosqlbody', p.oid::regprocedure::text
      from pg_proc p, unnest(v_nombres) as t(nom)
     where p.prosqlbody is not null
       and strpos(lower(pg_get_function_sqlbody(p.oid)), lower(t.nom)) > 0
       and not (p.oid = any (v_oids))
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    -- 4) vistas y vistas materializadas
    select 'vista', c.oid::regclass::text
      from pg_class c, unnest(v_nombres) as t(nom)
     where c.relkind in ('v','m') and strpos(lower(pg_get_viewdef(c.oid)), lower(t.nom)) > 0
    union all
    -- 5) policies de RLS
    select 'policy', pol.polname || ' on ' || pol.polrelid::regclass::text
      from pg_policy pol, unnest(v_nombres) as t(nom)
     where strpos(lower(coalesce(pg_get_expr(pol.polqual, pol.polrelid),'')
                     || ' ' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid),'')), lower(t.nom)) > 0
    union all
    -- 6) defaults y columnas generadas
    select 'default/generada', ad.adrelid::regclass::text || '.' || a.attname
      from pg_attrdef ad
      join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum,
           unnest(v_nombres) as t(nom)
     where strpos(lower(pg_get_expr(ad.adbin, ad.adrelid)), lower(t.nom)) > 0
    union all
    -- 7) constraints (CHECK con llamada a funcion)
    select 'constraint', con.conname || ' on ' || coalesce(con.conrelid::regclass::text,'-')
      from pg_constraint con, unnest(v_nombres) as t(nom)
     where strpos(lower(pg_get_constraintdef(con.oid)), lower(t.nom)) > 0
    union all
    -- 8) indices de expresion y parciales
    select 'indice', i.indexrelid::regclass::text
      from pg_index i, unnest(v_nombres) as t(nom)
     where (i.indexprs is not null or i.indpred is not null)
       and strpos(lower(pg_get_indexdef(i.indexrelid)), lower(t.nom)) > 0
    union all
    -- 9) trabajos programados
    select 'cron.job', j.jobname
      from cron.job j, unnest(v_nombres) as t(nom)
     where strpos(lower(j.command), lower(t.nom)) > 0
  )
  select count(*), string_agg(fuente || ': ' || objeto, ' | ') into v_n, v_detalle from censo;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: el censo encontro % referencia(s) VIVA(s) a las gemelas — resolverlas primero. %', v_n, v_detalle;
  end if;
end $ola2_pre$;

-- =====================================================================
-- 1) LA DEMOLICION.
-- =====================================================================
drop function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb);
drop function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb);
drop function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb);
drop function crm.crear_contrato_producto(uuid,jsonb,jsonb);
drop function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb);
drop function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb);
drop function public.crear_contrato_producto(uuid,jsonb,jsonb);

-- =====================================================================
-- 2) EL ACTA: el libro las marca demolidas (la maquina de estados solo deja
--    ir a `demolida` por migracion, y de ahi no se vuelve sin candado bajado).
--    Se actualiza POR FIRMA EXACTA, no por ola, y se exige el ROW_COUNT.
-- =====================================================================
do $ola2_acta$
declare v_n int;
begin
  update private.f7_piezas_en_observacion
     set estado = 'demolida',
         -- El trigger `solo_crece` EXIGE rastro al cambiar de estado: quien y por que.
         nota = coalesce(nota,'') || ' | DEMOLIDA por la OLA 2 (migracion '
                || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
                || ', `!` de Miguel): ventana de observacion cumplida POR FIRMA, vigia vivo y en verde,'
                || ' definicion completa verificada contra la captura del 01/09, censo de nueve superficies'
                || ' sin referencias vivas y marcha atras recreadora ensayada.'
   where estado = 'observacion'
     and firma = any (array[
       'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
       'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
       'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
       'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
       'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
       'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
       'public.crear_contrato_producto(uuid,jsonb,jsonb)']);
  get diagnostics v_n = row_count;
  if v_n <> 7 then
    raise exception 'OLA 2 acta: el libro registro % actas, esperaba exactamente 7', v_n;
  end if;
end $ola2_acta$;

-- =====================================================================
-- 3) POSTFLIGHT: se fueron las 7 POR FIRMA, las puertas vivas siguen en pie
--    con su firma exacta, y el libro cuadra.
-- =====================================================================
do $ola2_post$
declare
  v_firmas constant text[] := array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)'];
  -- Las puertas VIVAS del contrato, por FIRMA EXACTA. Buscar por `proname`
  -- daba falso rojo ante un overload nuevo, y aceptar «v2 o la vieja» daba
  -- falso verde si la que sobrevivia era la equivocada.
  v_vivas constant text[] := array[
    'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)',
    'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)'];
  v_f text; v_n int; v_verd text;
begin
  foreach v_f in array v_firmas loop
    if to_regprocedure(v_f) is not null then
      raise exception 'OLA 2 postflight: % sigue viva', v_f;
    end if;
  end loop;

  foreach v_f in array v_vivas loop
    if to_regprocedure(v_f) is null then
      raise exception 'OLA 2 postflight: se llevo por delante la puerta VIVA %', v_f;
    end if;
  end loop;

  -- El trigger de snapshot del catalogo de condiciones sigue armado: es lo que
  -- escribe las condiciones de cada contrato al cerrarlo o corregirlo, y 18
  -- personas lo mueven a diario.
  select count(*) into v_n from pg_trigger t
   where t.tgrelid = 'public.contratos'::regclass
     and t.tgname = 'trg_contratos_producto_snapshot' and not t.tgisinternal
     and t.tgenabled <> 'D';
  if v_n <> 1 then
    raise exception 'OLA 2 postflight: el trigger de snapshot del catalogo no quedo armado (coincidencias %)', v_n;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = any (v_firmas) and estado = 'demolida';
  if v_n <> 7 then
    raise exception 'OLA 2 postflight: el libro marca % de las 7 firmas demolidas', v_n;
  end if;
  -- Y no se toco ninguna otra cohorte.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where not (firma = any (v_firmas)) and estado = 'demolida';
  if v_n <> 0 then
    raise exception 'OLA 2 postflight: % pieza(s) AJENA(s) quedaron marcadas demolidas', v_n;
  end if;

  -- Los guardianes, en la misma transaccion.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 postflight: el vigilante F7 en rojo: %', v_verd;
  end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 postflight: analitica en rojo: %', v_verd;
  end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2 postflight: la demolicion levanto % alerta(s)', v_n;
  end if;
end $ola2_post$;

-- [ensayo] commit; retirado (20260913130000_crm_f7_ola2_demoler_las_siete_gemelas_v2.sql)


-- ---------- REGISTRADOR REAL: registrar-f7-ola2-version.sql ----------
-- REGISTRADOR de la OLA 2 — las siete gemelas demolidas.
--
-- 🤖 GENERADO por `scripts/generar-registrador-f7.mjs` — NO editar a mano.
--    El cuerpo de la migracion se lee DEL ARCHIVO al generar, para que no pueda
--    repetirse el fallo de ATR-4 (registrador con una version vieja dentro).
--    Si tocas la migracion, vuelve a generar: `node scripts/generar-registrador-f7.mjs`.
--
-- Inserta la version 20260913130000 en el registro SOLO si el mundo vivo ES el
-- posterior a la migracion. Patron de los registradores de ATR: pines del mundo
-- + relectura fail-closed despues del insert. `!` de Miguel, TRAS la migracion.
-- [ensayo] begin; retirado (registrar-f7-ola2-version.sql)
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $reg_ola2$
declare
  v_firmas constant text[] := array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)'];
  v_n int; v_verd text; v_cuerpo text;
begin
  -- 1) LAS SIETE SE FUERON DE VERDAD (esto es lo que la migracion hizo).
  select count(*) into v_n from unnest(v_firmas) as f(firma)
   where to_regprocedure(f.firma) is not null;
  if v_n > 0 then
    raise exception 'registrar OLA 2: % gemela(s) siguen vivas — no se registra lo que no paso', v_n;
  end if;

  -- 2) EL LIBRO tiene las siete actas, por firma exacta.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = any (v_firmas) and estado = 'demolida';
  if v_n <> 7 then
    raise exception 'registrar OLA 2: el libro marca % de las 7 firmas demolidas', v_n;
  end if;

  -- 3) LAS PUERTAS VIVAS siguen en pie y el trigger de snapshot, armado.
  if to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)') is null
     or to_regprocedure('crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)') is null then
    raise exception 'registrar OLA 2: falta una puerta VIVA de contratos — no se registra un mundo roto';
  end if;
  select count(*) into v_n from pg_trigger t
   where t.tgrelid = 'public.contratos'::regclass
     and t.tgname = 'trg_contratos_producto_snapshot' and not t.tgisinternal
     and t.tgenabled <> 'D';
  if v_n <> 1 then
    raise exception 'registrar OLA 2: el trigger de snapshot del catalogo no esta armado';
  end if;

  -- 4) LOS GUARDIANES, EN VERDE.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'registrar OLA 2: vigilante F7 en rojo: %', v_verd;
  end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'registrar OLA 2: % alerta(s) del vigia sin resolver', v_n;
  end if;

  v_cuerpo := $mig_ola2$-- P-055 F7 · OLA 2 v2 — DEMOLER LAS SIETE GEMELAS DEL CATALOGO VIEJO.
--
-- Tercer paso del metodo de Miguel: CERRAR (F5.d, 30/08, registro 186) →
-- OBSERVAR (14 dias) → DERRIBAR. Las siete llevan revocadas desde el 30/08:
-- nadie puede llamarlas, y su intento muere en 42501 antes del cuerpo.
--
-- ⛔ NO SE PUEDE APLICAR ANTES DEL 2026-09-13. No es disciplina: el libro
--    guarda `drop_no_antes_de` por fila y el preflight lo exige POR FIRMA. Si
--    se corre antes, ABORTA — y esta bien que aborte.
--
-- ✏️ POR QUE HAY UNA v2 — la v1 (`20260913120000`, commit 9695d67) NUNCA se
--    aplico en ningun sitio: el registro remoto va por 196 y esta va fechada el
--    13/09. Se commiteo declarada «lista para correr» y la segunda auditoria de
--    Codex la devolvio NO-GO. Como las migraciones commiteadas NO se editan
--    (regla del CRM, con guardian que la hace cumplir), la v1 se RETIRA del
--    arbol en el mismo commit que trae esta v2 — no puede quedarse: un replay
--    de banco aplica por orden de version y habria demolido con los preflights
--    debiles. Queda anotado en MIGRACIONES.md.
--
--    Los siete falsos verdes de la v1, corregidos aqui:
--     ① exigia SIETE FILAS de la ola F5.d, no las SIETE FIRMAS exactas: una
--       fila sustituida cumplia el conteo con el conjunto equivocado;
--     ② el stop-the-line contaba alertas abiertas pero no miraba al VIGIA:
--       pasaba con el cron apagado, roto o sin correr en dias (cero alertas
--       tambien es lo que devuelve un vigilante muerto);
--     ③ la huella cubria solo `prosrc`: owner, SECURITY DEFINER, volatilidad,
--       `search_path`, STRICT, coste, filas o comentario podian derivar sin que
--       nadie se enterara. Ahora se fija `pg_get_functiondef` ENTERA + owner +
--       comentario;
--     ④ el ACL se leia con `aclexplode(proacl)`, y `aclexplode(NULL)` no
--       devuelve filas: una funcion con ACL por defecto (que concede EXECUTE a
--       PUBLIC) daba VERDE. Ahora se lee el ACL EFECTIVO con `acldefault` y se
--       pregunta ademas por privilegio efectivo a los tres roles de la API;
--     ⑤ «nadie vivo las nombra» miraba solo `prosrc` de tres esquemas. Ahora el
--       censo cubre `pg_depend`, `prosrc`, `prosqlbody`, vistas, policies,
--       defaults, columnas generadas, constraints, indices de expresion y
--       `cron.job`, en TODOS los esquemas;
--     ⑥ el acta se escribia por `ola`, sin comprobar cuantas filas movio;
--     ⑦ el postflight buscaba por `proname` (un overload nuevo daba falso rojo)
--       y aceptaba la puerta VIEJA como prueba de vida: ahora fija por firma
--       exacta las puertas vivas PDF v2/v3 y el trigger de snapshot.
--
-- MATERIAL DE MARCHA ATRAS: `scripts/rollback-f7-ola2-gemelas.sql` recrea las
-- siete con su DEFINICION VIVA capturada de produccion el 01/09 (owner, ACL,
-- atributos y COMENTARIOS incluidos). El repo tiene 167 de 196 archivos y la
-- F5.d cambio sus cuerpos despues de nacer: la fuente es el REGISTRO y el
-- catalogo vivo, jamas la carpeta local.
--
-- ARTEFACTOS — 📌 MEDIDO, no supuesto: el oraculo
-- `scripts/test-productos-inversion.sql` NO hay que podarlo, y demolerlas NO
-- pone rojo `gate:config`. Ese oraculo es AUTOCONTENIDO: el gate le crea un
-- clon de `template0` (`gate-config-operativa.mjs`) y el propio archivo hace
-- `\ir` de `20260807203751` y `20260807235933`, o sea que se recrea las gemelas
-- antes de probarlas. Su mundo no depende de produccion. La primera auditoria
-- afirmo lo contrario y la segunda lo REFUTO ella misma.
-- El que SI se ponia rojo era `test-rls.mjs`, que corre contra un Supabase de
-- verdad y exigia `42501` exacto: ya acepta `42501` (cerrada) o `PGRST202`
-- (demolida) para estas siete firmas, y solo para ellas.
--
-- Publicacion (Miguel, con `!`): esta migracion → registrar-f7-ola2-version.sql
-- → gates → advisors.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '300s';

-- =====================================================================
-- 0) PREFLIGHT: la ventana, el libro, el vigia, las huellas y el censo.
-- =====================================================================
do $ola2_pre$
declare
  -- firma | huella del CUERPO | huella de la DEFINICION COMPLETA | comentario vivo
  -- (capturado de produccion el 2026-09-01; donde pone null, el comentario ES null).
  v_pin constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          '8640b1246f620ab40558cec2875ada23','956fb5f32191291d4b7ebafce5abbdb1', null],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          '4156191492c25479be73b0365263d946','1d884ef9f60a55dd4d0613a256e3ea71', null],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
          '06f79b07b4d65dcf50cd4359fb598723','a93f2db825cc26c19b1756cde0cdc435', null],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',
          '1148d0ca1beb33797995eeff3c579bd4','230bcc46e72191600cbd5fc789e1d503', null],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          'b7e0de18b559ec7fd650619cd22b9cb5','c786d25a9aca26f6a818dd57abe6ef72',
          'Corrección Portal catalogada que además conserva la coherencia de la cuenta bancaria contractual.'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          'f0e519cc4ee79c9334ae59a23844b23b','7128b0ebb65497e67c56d5383988b512',
          'Corrección Portal catalogada; conserva Admin/Superadmin/Analista, cartera, ventana y cierres de public.actualizar_contrato.'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',
          '893c857e27ec6405a3ac6e291458c346','58f41209f1cedf46198e7c76903f7bbb',
          'Alta Portal catalogada; conserva la autorización de public.crear_contrato y fija la condición en la misma transacción.']
  ];
  v_firmas constant text[] := array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)'
  ];
  -- Nombres desnudos para el censo de texto (sin esquema ni argumentos).
  v_nombres constant text[] := array[
    'actualizar_contrato_con_cuenta_producto','actualizar_contrato_producto',
    'crear_contrato_con_cuenta_producto','crear_contrato_producto'
  ];
  v_fila text[]; v_h text; v_hd text; v_com text; v_own text;
  v_n int; v_hoy date; v_verd text; v_detalle text; v_estado text;
  v_cuando timestamptz; v_oids oid[];
begin
  v_hoy := (now() at time zone 'America/Lima')::date;

  -- ------------------------------------------------------------------
  -- (a) LA VENTANA, POR FIRMA. No se cuenta la ola: se exige que CADA UNA
  --     de las siete este en el libro, en observacion, con su OK escrito y
  --     con su fecha cumplida. Una fila sustituida ya no pasa por conteo.
  -- ------------------------------------------------------------------
  select count(*), string_agg(f.firma || ' → ' || coalesce(
           (select l.estado || ', demolible ' || coalesce(l.drop_no_antes_de::text,'SIN FECHA')
              from private.f7_piezas_en_observacion l where l.firma = f.firma),
           'NO ESTA EN EL LIBRO'), ' | ')
    into v_n, v_detalle
  from unnest(v_firmas) as f(firma)
  where not exists (
    select 1 from private.f7_piezas_en_observacion l
     where l.firma = f.firma and l.ola = 'F5.d' and l.estado = 'observacion'
       and length(l.ok_miguel) >= 20
       and l.drop_no_antes_de is not null
       and l.drop_no_antes_de::date <= v_hoy);
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % de las 7 firmas no estan listas (hoy % en Lima). %', v_n, v_hoy, v_detalle;
  end if;

  -- Y la cohorte F5.d no tiene NINGUNA fila de mas: el conjunto es exacto.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and not (firma = any (v_firmas));
  if v_n > 0 then
    raise exception 'OLA 2 preflight: la cohorte F5.d tiene % fila(s) que NO son de las siete firmas — investigar antes de demoler', v_n;
  end if;

  -- ------------------------------------------------------------------
  -- (b) STOP-THE-LINE CON VIGIA VIVO. Cero alertas abiertas NO basta:
  --     un vigilante apagado tambien devuelve cero. Se exige que el cron
  --     exista, este activo, tenga el comando exacto, y que su ULTIMA
  --     corrida sea reciente y exitosa.
  -- ------------------------------------------------------------------
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: hay % alerta(s) del vigia sin resolver. Stop-the-line: se atienden ANTES y en otro paquete.', v_n;
  end if;

  select count(*) into v_n from cron.job j
   where j.jobname = 'crm-f7-piezas-vigia' and j.active
     and j.command = 'select private.vigia_f7_piezas()' and j.database = 'postgres';
  if v_n <> 1 then
    raise exception 'OLA 2 preflight: el cron del vigia F7 no esta vivo con su comando exacto (coincidencias: %)', v_n;
  end if;

  select r.status, r.start_time into v_estado, v_cuando
  from cron.job_run_details r
  join cron.job j on j.jobid = r.jobid
  where j.jobname = 'crm-f7-piezas-vigia'
  order by r.start_time desc limit 1;
  if v_estado is null then
    raise exception 'OLA 2 preflight: el vigia F7 no tiene NINGUNA corrida registrada — no hay observacion que acreditar';
  end if;
  if v_estado <> 'succeeded' then
    raise exception 'OLA 2 preflight: la ultima corrida del vigia F7 fue «%» (%). Cero alertas no prueba nada con el vigilante en rojo.', v_estado, v_cuando;
  end if;
  if v_cuando < now() - interval '48 hours' then
    raise exception 'OLA 2 preflight: la ultima corrida del vigia F7 es del % — lleva mas de 48h sin observar', v_cuando;
  end if;

  -- El censo estructural del propio guardian, ANTES de tocar nada.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 preflight: el vigilante F7 ya esta en rojo ANTES de demoler: %', v_verd;
  end if;

  -- ------------------------------------------------------------------
  -- (c) SON LAS QUE MEDI, ENTERAS. Cuerpo + definicion completa (que
  --     arrastra args, retorno, volatilidad, SECURITY DEFINER, search_path,
  --     STRICT, coste y filas) + owner + comentario.
  -- ------------------------------------------------------------------
  foreach v_fila slice 1 in array v_pin loop
    select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
           obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
      into v_h, v_hd, v_com, v_own
    from pg_proc p where p.oid = to_regprocedure(v_fila[1]);
    if v_h is null then
      raise exception 'OLA 2 preflight: % ya no existe — investigar antes de seguir', v_fila[1];
    end if;
    if v_h is distinct from v_fila[2] then
      raise exception 'OLA 2 preflight: % cambio de CUERPO desde la captura (huella %)', v_fila[1], v_h;
    end if;
    if v_hd is distinct from v_fila[3] then
      raise exception 'OLA 2 preflight: % cambio de DEFINICION desde la captura (huella %) — volatilidad, search_path, SECURITY DEFINER o atributos derivaron', v_fila[1], v_hd;
    end if;
    if v_com is distinct from v_fila[4] then
      raise exception 'OLA 2 preflight: % cambio de COMENTARIO desde la captura — la marcha atras dejaria de ser fiel', v_fila[1];
    end if;
    if v_own is distinct from 'postgres' then
      raise exception 'OLA 2 preflight: % cambio de dueño a «%» — la marcha atras no sabria reconstruirla', v_fila[1], v_own;
    end if;
  end loop;

  -- ------------------------------------------------------------------
  -- (d) SIGUEN CERRADAS, POR PRIVILEGIO EFECTIVO. `aclexplode(NULL)` no
  --     devuelve filas y una funcion con ACL por defecto concede EXECUTE a
  --     PUBLIC: leer `proacl` a secas es un falso verde. Se lee el ACL
  --     EFECTIVO (`acldefault` cuando es NULL) y ademas se pregunta por
  --     privilegio efectivo — que SI ve las concesiones por membresia.
  -- ------------------------------------------------------------------
  select count(*) into v_n
  from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = any (array(select to_regprocedure(f) from unnest(v_firmas) f))
    and a.privilege_type = 'EXECUTE' and a.grantee is distinct from p.proowner;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % concesion(es) EXECUTE efectivas fuera del dueño — alguien las reabrio', v_n;
  end if;

  select string_agg(f.firma || '→' || r.rol, '; ') into v_detalle
  from unnest(v_firmas) as f(firma),
       unnest(array['anon','authenticated','service_role']) as r(rol)
  where has_function_privilege(r.rol, to_regprocedure(f.firma), 'EXECUTE');
  if v_detalle is not null then
    raise exception 'OLA 2 preflight: privilegio EFECTIVO de ejecucion todavia vivo: %', v_detalle;
  end if;

  -- ------------------------------------------------------------------
  -- (e) EL CENSO EXHAUSTIVO, INMEDIATAMENTE ANTES DEL DROP. `DROP FUNCTION`
  --     sin CASCADE frena las dependencias que Postgres registra, pero NO
  --     ve los nombres dentro de cuerpos guardados como texto. Se miran
  --     nueve superficies, en TODOS los esquemas.
  -- ------------------------------------------------------------------
  v_oids := array(select to_regprocedure(f) from unnest(v_firmas) f);

  with censo as (
    -- 1) dependencias que Postgres SI registra
    select 'pg_depend'::text as fuente,
           coalesce(d.classid::regclass::text,'?') || ' #' || d.objid::text as objeto
      from pg_depend d
     where d.refclassid = 'pg_proc'::regclass and d.refobjid = any (v_oids)
       and d.deptype in ('n','a')
    union all
    -- 2) cuerpos plpgsql/sql clasicos (todos los esquemas, todas las funciones)
    select 'pg_proc.prosrc', p.oid::regprocedure::text
      from pg_proc p, unnest(v_nombres) as t(nom)
     where p.prosrc is not null and strpos(lower(p.prosrc), lower(t.nom)) > 0
       and not (p.oid = any (v_oids))
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    -- 3) cuerpos SQL estandar (BEGIN ATOMIC), que no viven en `prosrc`
    select 'pg_proc.prosqlbody', p.oid::regprocedure::text
      from pg_proc p, unnest(v_nombres) as t(nom)
     where p.prosqlbody is not null
       and strpos(lower(pg_get_function_sqlbody(p.oid)), lower(t.nom)) > 0
       and not (p.oid = any (v_oids))
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    -- 4) vistas y vistas materializadas
    select 'vista', c.oid::regclass::text
      from pg_class c, unnest(v_nombres) as t(nom)
     where c.relkind in ('v','m') and strpos(lower(pg_get_viewdef(c.oid)), lower(t.nom)) > 0
    union all
    -- 5) policies de RLS
    select 'policy', pol.polname || ' on ' || pol.polrelid::regclass::text
      from pg_policy pol, unnest(v_nombres) as t(nom)
     where strpos(lower(coalesce(pg_get_expr(pol.polqual, pol.polrelid),'')
                     || ' ' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid),'')), lower(t.nom)) > 0
    union all
    -- 6) defaults y columnas generadas
    select 'default/generada', ad.adrelid::regclass::text || '.' || a.attname
      from pg_attrdef ad
      join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum,
           unnest(v_nombres) as t(nom)
     where strpos(lower(pg_get_expr(ad.adbin, ad.adrelid)), lower(t.nom)) > 0
    union all
    -- 7) constraints (CHECK con llamada a funcion)
    select 'constraint', con.conname || ' on ' || coalesce(con.conrelid::regclass::text,'-')
      from pg_constraint con, unnest(v_nombres) as t(nom)
     where strpos(lower(pg_get_constraintdef(con.oid)), lower(t.nom)) > 0
    union all
    -- 8) indices de expresion y parciales
    select 'indice', i.indexrelid::regclass::text
      from pg_index i, unnest(v_nombres) as t(nom)
     where (i.indexprs is not null or i.indpred is not null)
       and strpos(lower(pg_get_indexdef(i.indexrelid)), lower(t.nom)) > 0
    union all
    -- 9) trabajos programados
    select 'cron.job', j.jobname
      from cron.job j, unnest(v_nombres) as t(nom)
     where strpos(lower(j.command), lower(t.nom)) > 0
  )
  select count(*), string_agg(fuente || ': ' || objeto, ' | ') into v_n, v_detalle from censo;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: el censo encontro % referencia(s) VIVA(s) a las gemelas — resolverlas primero. %', v_n, v_detalle;
  end if;
end $ola2_pre$;

-- =====================================================================
-- 1) LA DEMOLICION.
-- =====================================================================
drop function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb);
drop function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb);
drop function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb);
drop function crm.crear_contrato_producto(uuid,jsonb,jsonb);
drop function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb);
drop function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb);
drop function public.crear_contrato_producto(uuid,jsonb,jsonb);

-- =====================================================================
-- 2) EL ACTA: el libro las marca demolidas (la maquina de estados solo deja
--    ir a `demolida` por migracion, y de ahi no se vuelve sin candado bajado).
--    Se actualiza POR FIRMA EXACTA, no por ola, y se exige el ROW_COUNT.
-- =====================================================================
do $ola2_acta$
declare v_n int;
begin
  update private.f7_piezas_en_observacion
     set estado = 'demolida',
         -- El trigger `solo_crece` EXIGE rastro al cambiar de estado: quien y por que.
         nota = coalesce(nota,'') || ' | DEMOLIDA por la OLA 2 (migracion '
                || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
                || ', `!` de Miguel): ventana de observacion cumplida POR FIRMA, vigia vivo y en verde,'
                || ' definicion completa verificada contra la captura del 01/09, censo de nueve superficies'
                || ' sin referencias vivas y marcha atras recreadora ensayada.'
   where estado = 'observacion'
     and firma = any (array[
       'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
       'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
       'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
       'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
       'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
       'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
       'public.crear_contrato_producto(uuid,jsonb,jsonb)']);
  get diagnostics v_n = row_count;
  if v_n <> 7 then
    raise exception 'OLA 2 acta: el libro registro % actas, esperaba exactamente 7', v_n;
  end if;
end $ola2_acta$;

-- =====================================================================
-- 3) POSTFLIGHT: se fueron las 7 POR FIRMA, las puertas vivas siguen en pie
--    con su firma exacta, y el libro cuadra.
-- =====================================================================
do $ola2_post$
declare
  v_firmas constant text[] := array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)'];
  -- Las puertas VIVAS del contrato, por FIRMA EXACTA. Buscar por `proname`
  -- daba falso rojo ante un overload nuevo, y aceptar «v2 o la vieja» daba
  -- falso verde si la que sobrevivia era la equivocada.
  v_vivas constant text[] := array[
    'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)',
    'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)'];
  v_f text; v_n int; v_verd text;
begin
  foreach v_f in array v_firmas loop
    if to_regprocedure(v_f) is not null then
      raise exception 'OLA 2 postflight: % sigue viva', v_f;
    end if;
  end loop;

  foreach v_f in array v_vivas loop
    if to_regprocedure(v_f) is null then
      raise exception 'OLA 2 postflight: se llevo por delante la puerta VIVA %', v_f;
    end if;
  end loop;

  -- El trigger de snapshot del catalogo de condiciones sigue armado: es lo que
  -- escribe las condiciones de cada contrato al cerrarlo o corregirlo, y 18
  -- personas lo mueven a diario.
  select count(*) into v_n from pg_trigger t
   where t.tgrelid = 'public.contratos'::regclass
     and t.tgname = 'trg_contratos_producto_snapshot' and not t.tgisinternal
     and t.tgenabled <> 'D';
  if v_n <> 1 then
    raise exception 'OLA 2 postflight: el trigger de snapshot del catalogo no quedo armado (coincidencias %)', v_n;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = any (v_firmas) and estado = 'demolida';
  if v_n <> 7 then
    raise exception 'OLA 2 postflight: el libro marca % de las 7 firmas demolidas', v_n;
  end if;
  -- Y no se toco ninguna otra cohorte.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where not (firma = any (v_firmas)) and estado = 'demolida';
  if v_n <> 0 then
    raise exception 'OLA 2 postflight: % pieza(s) AJENA(s) quedaron marcadas demolidas', v_n;
  end if;

  -- Los guardianes, en la misma transaccion.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 postflight: el vigilante F7 en rojo: %', v_verd;
  end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2 postflight: analitica en rojo: %', v_verd;
  end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2 postflight: la demolicion levanto % alerta(s)', v_n;
  end if;
end $ola2_post$;

commit;
$mig_ola2$;

  -- 5) Si la version ya existe: muda => abortar; cuerpo distinto => abortar.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260913130000' and statements is null;
  if v_n > 0 then
    raise exception 'registrar ola2: la version existe MUDA — repararla, no pisarla';
  end if;
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260913130000' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar ola2: la version existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260913130000', 'crm_f7_ola2_demoler_las_siete_gemelas_v2', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 6) RELECTURA fail-closed: la fila EXACTA, o se cae la transaccion entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260913130000'
     and name = 'crm_f7_ola2_demoler_las_siete_gemelas_v2'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar ola2: la relectura no encontro la fila exacta';
  end if;
end $reg_ola2$;

select '20260913130000 registrada: las 7 gemelas del catalogo viejo, demolidas y con su acta' as resultado,
       (select count(*) from supabase_migrations.schema_migrations) as versiones,
       (select count(*) from private.f7_piezas_en_observacion where estado = 'demolida') as piezas_demolidas;
-- [ensayo] commit; retirado (registrar-f7-ola2-version.sql)


-- ---------- MIGRACION REAL: 20260914130000_crm_f7_ola2b_demoler_el_tablero_de_altas_v2.sql ----------
-- P-055 F7 · OLA 2b v2 — DEMOLER EL TABLERO DE ALTAS POR ANALISTA.
--
-- Cierre parcial de la cohorte de la Ola 1 (F7.1, cerrada el 31/08, registro
-- 191). ⛔ NO ANTES DEL 2026-09-14 (su `drop_no_antes_de`).
--
-- ✏️ POR QUE HAY UNA v2 — la v1 (`20260914120000`, commit 9695d67) NUNCA se
--    aplico: el registro remoto va por 196 y esta va fechada el 14/09. La
--    segunda auditoria de Codex la devolvio NO-GO y las migraciones commiteadas
--    no se editan, asi que la v1 se RETIRA del arbol en el mismo commit que
--    trae esta v2. Anotado en MIGRACIONES.md.
--
-- 🔴 POR QUE SOLO UNA DE LAS TRES — hallazgo del ensayo del 01/09:
--    `metricas_distribucion_leads_fn` y `metricas_distribucion_leads_v2_fn`
--    pertenecen al rol `crm_metricas_bridge`, y por el canal de publicacion
--    (`supabase db query`) NO se puede asumir ese rol: ni `alter function ...
--    owner to` ni `set role` funcionan (42501 «permission denied to set role»).
--    Consecuencia: si se demolieran, la marcha atras las recrearia con dueño
--    `postgres` y el vigilante F7 las veria REABIERTAS respecto de su ACL
--    declarada `{crm_metricas_bridge=X/crm_metricas_bridge}`.
--    ⇒ **No se derriba lo que no se sabe reconstruir.** Las dos se quedan
--    cerradas y en observacion; su demolicion queda como DEUDA DECLARADA.
--    Codex (01/09) matiza — y tiene razon — que «solo un superusuario puede»
--    es demasiado fuerte: existe una via transaccional plausible (conceder
--    temporalmente `SET OPTION` a la membresia de postgres con el `ADMIN
--    OPTION` que ya existe, y `CREATE` en `crm` al bridge, restaurando ambos).
--    NO esta ensayada y NO entra aqui: va en su propio paquete, con ensayo
--    adversarial y fotos exactas de `pg_auth_members` y `nspacl`.
--
-- 🔴 `metricas_altas_analista_fn` NO tiene archivo en el repo: su partida de
--    nacimiento vive en el registro remoto (version 20260716203331). El
--    material de marcha atras es la CAPTURA VIVA del 01/09, en
--    `scripts/rollback-f7-ola2b-tableros.sql` — que ahora tambien restituye su
--    COMENTARIO (la v1 lo perdia, y el ensayo salia verde igual porque solo
--    comparaba `md5(prosrc)`).
--
-- 📌 Dato honesto para el acta: `pg_stat_statements` registra 72 llamadas
--    historicas a esta funcion desde el reset del 2026-04-25, sin posibilidad
--    de fecharlas respecto del cierre del 31/08. No prueba uso posterior al
--    cierre — prueba que la pieza SI se uso alguna vez, y por eso se cerro
--    primero y se observa antes de derribar.
--
-- Publicacion (Miguel, con `!`): migracion → registrar-f7-ola2b-version.sql →
-- gates → advisors.

-- [ensayo] begin; retirado (20260914130000_crm_f7_ola2b_demoler_el_tablero_de_altas_v2.sql)

set local lock_timeout = '5s';
set local statement_timeout = '300s';

do $ola2b_pre$
declare
  v_firma  constant text := 'crm.metricas_altas_analista_fn(integer)';
  v_cuerpo constant text := 'df8a99e0dfc4e1d94794073787aa84d7';
  v_defin  constant text := 'f439e788e16a49fa23d8b52c0047f929';
  v_coment constant text := 'Agregado para gráfica de gerencia: altas de clientes por mes y por analista (nombra SOLO al asesor interno, nunca al cliente). Mismo ámbito por rol.';
  v_nombre constant text := 'metricas_altas_analista_fn';
  -- Las dos del bridge NO se tocan: se comprueba que siguen intactas.
  v_bridge constant text[] := array[
    'crm.metricas_distribucion_leads_fn(date,date)',
    'crm.metricas_distribucion_leads_v2_fn(date,date)'];
  v_h text; v_hd text; v_com text; v_own text; v_estado text;
  v_cuando timestamptz; v_n int; v_hoy date; v_ventana date;
  v_verd text; v_detalle text; v_oid oid;
begin
  v_hoy := (now() at time zone 'America/Lima')::date;

  -- (a) LA VENTANA, de su propia fila del libro.
  select f.drop_no_antes_de::date into v_ventana
    from private.f7_piezas_en_observacion f
   where f.firma = v_firma and f.ola = 'F7.1' and f.estado = 'observacion'
     and length(f.ok_miguel) >= 20;
  if v_ventana is null then
    raise exception 'OLA 2b preflight: % no esta en el libro como F7.1 en observacion con su OK y su fecha', v_firma;
  end if;
  if v_ventana > v_hoy then
    raise exception 'OLA 2b preflight: % sigue en su ventana (demolible desde %, hoy % en Lima)', v_firma, v_ventana, v_hoy;
  end if;

  -- (b) STOP-THE-LINE CON VIGIA VIVO (cero alertas de un vigilante muerto
  --     tambien es cero: se exige el cron activo, con su comando exacto, y una
  --     ultima corrida reciente y exitosa).
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % alerta(s) del vigia sin resolver — stop-the-line', v_n;
  end if;

  select count(*) into v_n from cron.job j
   where j.jobname = 'crm-f7-piezas-vigia' and j.active
     and j.command = 'select private.vigia_f7_piezas()' and j.database = 'postgres';
  if v_n <> 1 then
    raise exception 'OLA 2b preflight: el cron del vigia F7 no esta vivo con su comando exacto (coincidencias: %)', v_n;
  end if;

  select r.status, r.start_time into v_estado, v_cuando
  from cron.job_run_details r
  join cron.job j on j.jobid = r.jobid
  where j.jobname = 'crm-f7-piezas-vigia'
  order by r.start_time desc limit 1;
  if v_estado is null then
    raise exception 'OLA 2b preflight: el vigia F7 no tiene NINGUNA corrida registrada';
  end if;
  if v_estado <> 'succeeded' then
    raise exception 'OLA 2b preflight: la ultima corrida del vigia F7 fue «%» (%)', v_estado, v_cuando;
  end if;
  if v_cuando < now() - interval '48 hours' then
    raise exception 'OLA 2b preflight: la ultima corrida del vigia F7 es del % — mas de 48h sin observar', v_cuando;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2b preflight: el vigilante F7 ya esta en rojo ANTES de demoler: %', v_verd;
  end if;

  -- (c) ES LA QUE MEDI, ENTERA: cuerpo + definicion completa + comentario + dueño.
  v_oid := to_regprocedure(v_firma);
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
         obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
    into v_h, v_hd, v_com, v_own
  from pg_proc p where p.oid = v_oid;
  if v_h is null then
    raise exception 'OLA 2b preflight: % ya no existe', v_firma;
  end if;
  if v_h is distinct from v_cuerpo then
    raise exception 'OLA 2b preflight: % cambio de CUERPO desde la captura (huella %)', v_firma, v_h;
  end if;
  if v_hd is distinct from v_defin then
    raise exception 'OLA 2b preflight: % cambio de DEFINICION desde la captura (huella %)', v_firma, v_hd;
  end if;
  if v_com is distinct from v_coment then
    raise exception 'OLA 2b preflight: % cambio de COMENTARIO — la marcha atras dejaria de ser fiel', v_firma;
  end if;
  if v_own is distinct from 'postgres' then
    raise exception 'OLA 2b preflight: % cambio de dueño a «%»', v_firma, v_own;
  end if;

  -- (d) SIGUE CERRADA, POR PRIVILEGIO EFECTIVO (con `acldefault` para el caso
  --     `proacl IS NULL`, que concede EXECUTE a PUBLIC y daba falso verde).
  select count(*) into v_n
  from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = v_oid and a.privilege_type = 'EXECUTE'
    and a.grantee is distinct from p.proowner;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % concesion(es) EXECUTE efectivas fuera del dueño', v_n;
  end if;

  select string_agg(r.rol, ', ') into v_detalle
  from unnest(array['anon','authenticated','service_role']) as r(rol)
  where has_function_privilege(r.rol, v_oid, 'EXECUTE');
  if v_detalle is not null then
    raise exception 'OLA 2b preflight: privilegio EFECTIVO de ejecucion todavia vivo para: %', v_detalle;
  end if;

  -- (e) LAS DOS DEL BRIDGE, INTACTAS ANTES DE EMPEZAR (esta migracion no las toca).
  select count(*) into v_n from unnest(v_bridge) as b(firma)
   where to_regprocedure(b.firma) is null;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % funcion(es) del bridge ya no existen — el mundo no es el que esta migracion asume', v_n;
  end if;

  -- (f) EL CENSO EXHAUSTIVO, INMEDIATAMENTE ANTES DEL DROP: nueve superficies,
  --     todos los esquemas.
  with censo as (
    select 'pg_depend'::text as fuente,
           coalesce(d.classid::regclass::text,'?') || ' #' || d.objid::text as objeto
      from pg_depend d
     where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_oid
       and d.deptype in ('n','a')
    union all
    select 'pg_proc.prosrc', p.oid::regprocedure::text
      from pg_proc p
     where p.prosrc is not null and strpos(lower(p.prosrc), v_nombre) > 0
       and p.oid <> v_oid
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    select 'pg_proc.prosqlbody', p.oid::regprocedure::text
      from pg_proc p
     where p.prosqlbody is not null
       and strpos(lower(pg_get_function_sqlbody(p.oid)), v_nombre) > 0
       and p.oid <> v_oid
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    select 'vista', c.oid::regclass::text from pg_class c
     where c.relkind in ('v','m') and strpos(lower(pg_get_viewdef(c.oid)), v_nombre) > 0
    union all
    select 'policy', pol.polname || ' on ' || pol.polrelid::regclass::text from pg_policy pol
     where strpos(lower(coalesce(pg_get_expr(pol.polqual, pol.polrelid),'')
                     || ' ' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid),'')), v_nombre) > 0
    union all
    select 'default/generada', ad.adrelid::regclass::text || '.' || a.attname
      from pg_attrdef ad join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
     where strpos(lower(pg_get_expr(ad.adbin, ad.adrelid)), v_nombre) > 0
    union all
    select 'constraint', con.conname || ' on ' || coalesce(con.conrelid::regclass::text,'-')
      from pg_constraint con
     where strpos(lower(pg_get_constraintdef(con.oid)), v_nombre) > 0
    union all
    select 'indice', i.indexrelid::regclass::text from pg_index i
     where (i.indexprs is not null or i.indpred is not null)
       and strpos(lower(pg_get_indexdef(i.indexrelid)), v_nombre) > 0
    union all
    select 'cron.job', j.jobname from cron.job j
     where strpos(lower(j.command), v_nombre) > 0
  )
  select count(*), string_agg(fuente || ': ' || objeto, ' | ') into v_n, v_detalle from censo;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: el censo encontro % referencia(s) VIVA(s) al tablero — resolverlas primero. %', v_n, v_detalle;
  end if;
end $ola2b_pre$;

drop function crm.metricas_altas_analista_fn(integer);

do $ola2b_acta$
declare v_n int;
begin
  update private.f7_piezas_en_observacion
     set estado = 'demolida',
         nota = coalesce(nota,'') || ' | DEMOLIDA por la OLA 2b (migracion '
                || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
                || ', `!` de Miguel): ventana cumplida, vigia vivo y en verde, definicion completa y'
                || ' comentario verificados contra la captura del 01/09, censo de nueve superficies sin'
                || ' referencias vivas y marcha atras recreadora ensayada.'
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'observacion';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'OLA 2b acta: el libro registro % actas, esperaba exactamente 1', v_n;
  end if;
end $ola2b_acta$;

do $ola2b_post$
declare v_n int; v_verd text;
begin
  if to_regprocedure('crm.metricas_altas_analista_fn(integer)') is not null then
    raise exception 'OLA 2b postflight: la funcion sigue viva';
  end if;

  -- Las dos del bridge NO se tocan (deuda declarada): siguen vivas y con SU dueño.
  select count(*) into v_n
  from pg_proc p
  where p.oid in (to_regprocedure('crm.metricas_distribucion_leads_fn(date,date)'),
                  to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)'))
    and pg_get_userbyid(p.proowner) = 'crm_metricas_bridge';
  if v_n <> 2 then
    raise exception 'OLA 2b postflight: las 2 del bridge no siguen vivas con su dueño (coincidencias %)', v_n;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'OLA 2b postflight: el acta no quedo escrita';
  end if;
  -- Solo esta pieza cambio de estado en esta migracion: la cohorte F7.1 conserva
  -- sus 4 pasillos permanentes y sus 2 del bridge en observacion.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F7.1' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'OLA 2b postflight: la cohorte F7.1 tiene % demolidas, esperaba 1', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'OLA 2b postflight: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'OLA 2b postflight: analitica en rojo: %', v_verd; end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then raise exception 'OLA 2b postflight: la demolicion levanto % alerta(s)', v_n; end if;
end $ola2b_post$;

-- [ensayo] commit; retirado (20260914130000_crm_f7_ola2b_demoler_el_tablero_de_altas_v2.sql)


-- ---------- REGISTRADOR REAL: registrar-f7-ola2b-version.sql ----------
-- REGISTRADOR de la OLA 2b — el tablero de altas por analista, demolido.
--
-- 🤖 GENERADO por `scripts/generar-registrador-f7.mjs` — NO editar a mano.
--    El cuerpo de la migracion se lee DEL ARCHIVO al generar, para que no pueda
--    repetirse el fallo de ATR-4 (registrador con una version vieja dentro).
--    Si tocas la migracion, vuelve a generar: `node scripts/generar-registrador-f7.mjs`.
--
-- Inserta la version 20260914130000 en el registro SOLO si el mundo vivo ES el
-- posterior a la migracion. Patron de los registradores de ATR: pines del mundo
-- + relectura fail-closed despues del insert. `!` de Miguel, TRAS la migracion.
-- [ensayo] begin; retirado (registrar-f7-ola2b-version.sql)
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $reg_ola2b$
declare
  v_n int; v_verd text; v_cuerpo text;
begin
  -- 1) EL TABLERO SE FUE (esto es lo que la migracion hizo).
  if to_regprocedure('crm.metricas_altas_analista_fn(integer)') is not null then
    raise exception 'registrar OLA 2b: la funcion sigue viva — no se registra lo que no paso';
  end if;

  -- 2) SU ACTA esta en el libro.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'registrar OLA 2b: el libro no tiene su acta (filas %)', v_n;
  end if;

  -- 3) LAS DOS DEL BRIDGE, INTACTAS Y CON SU DUEÑO (deuda declarada: no se tocan).
  select count(*) into v_n from pg_proc p
   where p.oid in (to_regprocedure('crm.metricas_distribucion_leads_fn(date,date)'),
                   to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)'))
     and pg_get_userbyid(p.proowner) = 'crm_metricas_bridge';
  if v_n <> 2 then
    raise exception 'registrar OLA 2b: las 2 del bridge no siguen vivas con su dueño (coincidencias %)', v_n;
  end if;

  -- 4) LOS GUARDIANES, EN VERDE.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'registrar OLA 2b: vigilante F7 en rojo: %', v_verd;
  end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'registrar OLA 2b: % alerta(s) del vigia sin resolver', v_n;
  end if;

  v_cuerpo := $mig_ola2b$-- P-055 F7 · OLA 2b v2 — DEMOLER EL TABLERO DE ALTAS POR ANALISTA.
--
-- Cierre parcial de la cohorte de la Ola 1 (F7.1, cerrada el 31/08, registro
-- 191). ⛔ NO ANTES DEL 2026-09-14 (su `drop_no_antes_de`).
--
-- ✏️ POR QUE HAY UNA v2 — la v1 (`20260914120000`, commit 9695d67) NUNCA se
--    aplico: el registro remoto va por 196 y esta va fechada el 14/09. La
--    segunda auditoria de Codex la devolvio NO-GO y las migraciones commiteadas
--    no se editan, asi que la v1 se RETIRA del arbol en el mismo commit que
--    trae esta v2. Anotado en MIGRACIONES.md.
--
-- 🔴 POR QUE SOLO UNA DE LAS TRES — hallazgo del ensayo del 01/09:
--    `metricas_distribucion_leads_fn` y `metricas_distribucion_leads_v2_fn`
--    pertenecen al rol `crm_metricas_bridge`, y por el canal de publicacion
--    (`supabase db query`) NO se puede asumir ese rol: ni `alter function ...
--    owner to` ni `set role` funcionan (42501 «permission denied to set role»).
--    Consecuencia: si se demolieran, la marcha atras las recrearia con dueño
--    `postgres` y el vigilante F7 las veria REABIERTAS respecto de su ACL
--    declarada `{crm_metricas_bridge=X/crm_metricas_bridge}`.
--    ⇒ **No se derriba lo que no se sabe reconstruir.** Las dos se quedan
--    cerradas y en observacion; su demolicion queda como DEUDA DECLARADA.
--    Codex (01/09) matiza — y tiene razon — que «solo un superusuario puede»
--    es demasiado fuerte: existe una via transaccional plausible (conceder
--    temporalmente `SET OPTION` a la membresia de postgres con el `ADMIN
--    OPTION` que ya existe, y `CREATE` en `crm` al bridge, restaurando ambos).
--    NO esta ensayada y NO entra aqui: va en su propio paquete, con ensayo
--    adversarial y fotos exactas de `pg_auth_members` y `nspacl`.
--
-- 🔴 `metricas_altas_analista_fn` NO tiene archivo en el repo: su partida de
--    nacimiento vive en el registro remoto (version 20260716203331). El
--    material de marcha atras es la CAPTURA VIVA del 01/09, en
--    `scripts/rollback-f7-ola2b-tableros.sql` — que ahora tambien restituye su
--    COMENTARIO (la v1 lo perdia, y el ensayo salia verde igual porque solo
--    comparaba `md5(prosrc)`).
--
-- 📌 Dato honesto para el acta: `pg_stat_statements` registra 72 llamadas
--    historicas a esta funcion desde el reset del 2026-04-25, sin posibilidad
--    de fecharlas respecto del cierre del 31/08. No prueba uso posterior al
--    cierre — prueba que la pieza SI se uso alguna vez, y por eso se cerro
--    primero y se observa antes de derribar.
--
-- Publicacion (Miguel, con `!`): migracion → registrar-f7-ola2b-version.sql →
-- gates → advisors.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '300s';

do $ola2b_pre$
declare
  v_firma  constant text := 'crm.metricas_altas_analista_fn(integer)';
  v_cuerpo constant text := 'df8a99e0dfc4e1d94794073787aa84d7';
  v_defin  constant text := 'f439e788e16a49fa23d8b52c0047f929';
  v_coment constant text := 'Agregado para gráfica de gerencia: altas de clientes por mes y por analista (nombra SOLO al asesor interno, nunca al cliente). Mismo ámbito por rol.';
  v_nombre constant text := 'metricas_altas_analista_fn';
  -- Las dos del bridge NO se tocan: se comprueba que siguen intactas.
  v_bridge constant text[] := array[
    'crm.metricas_distribucion_leads_fn(date,date)',
    'crm.metricas_distribucion_leads_v2_fn(date,date)'];
  v_h text; v_hd text; v_com text; v_own text; v_estado text;
  v_cuando timestamptz; v_n int; v_hoy date; v_ventana date;
  v_verd text; v_detalle text; v_oid oid;
begin
  v_hoy := (now() at time zone 'America/Lima')::date;

  -- (a) LA VENTANA, de su propia fila del libro.
  select f.drop_no_antes_de::date into v_ventana
    from private.f7_piezas_en_observacion f
   where f.firma = v_firma and f.ola = 'F7.1' and f.estado = 'observacion'
     and length(f.ok_miguel) >= 20;
  if v_ventana is null then
    raise exception 'OLA 2b preflight: % no esta en el libro como F7.1 en observacion con su OK y su fecha', v_firma;
  end if;
  if v_ventana > v_hoy then
    raise exception 'OLA 2b preflight: % sigue en su ventana (demolible desde %, hoy % en Lima)', v_firma, v_ventana, v_hoy;
  end if;

  -- (b) STOP-THE-LINE CON VIGIA VIVO (cero alertas de un vigilante muerto
  --     tambien es cero: se exige el cron activo, con su comando exacto, y una
  --     ultima corrida reciente y exitosa).
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % alerta(s) del vigia sin resolver — stop-the-line', v_n;
  end if;

  select count(*) into v_n from cron.job j
   where j.jobname = 'crm-f7-piezas-vigia' and j.active
     and j.command = 'select private.vigia_f7_piezas()' and j.database = 'postgres';
  if v_n <> 1 then
    raise exception 'OLA 2b preflight: el cron del vigia F7 no esta vivo con su comando exacto (coincidencias: %)', v_n;
  end if;

  select r.status, r.start_time into v_estado, v_cuando
  from cron.job_run_details r
  join cron.job j on j.jobid = r.jobid
  where j.jobname = 'crm-f7-piezas-vigia'
  order by r.start_time desc limit 1;
  if v_estado is null then
    raise exception 'OLA 2b preflight: el vigia F7 no tiene NINGUNA corrida registrada';
  end if;
  if v_estado <> 'succeeded' then
    raise exception 'OLA 2b preflight: la ultima corrida del vigia F7 fue «%» (%)', v_estado, v_cuando;
  end if;
  if v_cuando < now() - interval '48 hours' then
    raise exception 'OLA 2b preflight: la ultima corrida del vigia F7 es del % — mas de 48h sin observar', v_cuando;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'OLA 2b preflight: el vigilante F7 ya esta en rojo ANTES de demoler: %', v_verd;
  end if;

  -- (c) ES LA QUE MEDI, ENTERA: cuerpo + definicion completa + comentario + dueño.
  v_oid := to_regprocedure(v_firma);
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
         obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
    into v_h, v_hd, v_com, v_own
  from pg_proc p where p.oid = v_oid;
  if v_h is null then
    raise exception 'OLA 2b preflight: % ya no existe', v_firma;
  end if;
  if v_h is distinct from v_cuerpo then
    raise exception 'OLA 2b preflight: % cambio de CUERPO desde la captura (huella %)', v_firma, v_h;
  end if;
  if v_hd is distinct from v_defin then
    raise exception 'OLA 2b preflight: % cambio de DEFINICION desde la captura (huella %)', v_firma, v_hd;
  end if;
  if v_com is distinct from v_coment then
    raise exception 'OLA 2b preflight: % cambio de COMENTARIO — la marcha atras dejaria de ser fiel', v_firma;
  end if;
  if v_own is distinct from 'postgres' then
    raise exception 'OLA 2b preflight: % cambio de dueño a «%»', v_firma, v_own;
  end if;

  -- (d) SIGUE CERRADA, POR PRIVILEGIO EFECTIVO (con `acldefault` para el caso
  --     `proacl IS NULL`, que concede EXECUTE a PUBLIC y daba falso verde).
  select count(*) into v_n
  from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = v_oid and a.privilege_type = 'EXECUTE'
    and a.grantee is distinct from p.proowner;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % concesion(es) EXECUTE efectivas fuera del dueño', v_n;
  end if;

  select string_agg(r.rol, ', ') into v_detalle
  from unnest(array['anon','authenticated','service_role']) as r(rol)
  where has_function_privilege(r.rol, v_oid, 'EXECUTE');
  if v_detalle is not null then
    raise exception 'OLA 2b preflight: privilegio EFECTIVO de ejecucion todavia vivo para: %', v_detalle;
  end if;

  -- (e) LAS DOS DEL BRIDGE, INTACTAS ANTES DE EMPEZAR (esta migracion no las toca).
  select count(*) into v_n from unnest(v_bridge) as b(firma)
   where to_regprocedure(b.firma) is null;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % funcion(es) del bridge ya no existen — el mundo no es el que esta migracion asume', v_n;
  end if;

  -- (f) EL CENSO EXHAUSTIVO, INMEDIATAMENTE ANTES DEL DROP: nueve superficies,
  --     todos los esquemas.
  with censo as (
    select 'pg_depend'::text as fuente,
           coalesce(d.classid::regclass::text,'?') || ' #' || d.objid::text as objeto
      from pg_depend d
     where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_oid
       and d.deptype in ('n','a')
    union all
    select 'pg_proc.prosrc', p.oid::regprocedure::text
      from pg_proc p
     where p.prosrc is not null and strpos(lower(p.prosrc), v_nombre) > 0
       and p.oid <> v_oid
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    select 'pg_proc.prosqlbody', p.oid::regprocedure::text
      from pg_proc p
     where p.prosqlbody is not null
       and strpos(lower(pg_get_function_sqlbody(p.oid)), v_nombre) > 0
       and p.oid <> v_oid
       and not exists (select 1 from private.f7_piezas_en_observacion lib
                        where lib.firma = p.oid::regprocedure::text
                          and lib.estado in ('observacion','cerrada_permanente','demolida'))
    union all
    select 'vista', c.oid::regclass::text from pg_class c
     where c.relkind in ('v','m') and strpos(lower(pg_get_viewdef(c.oid)), v_nombre) > 0
    union all
    select 'policy', pol.polname || ' on ' || pol.polrelid::regclass::text from pg_policy pol
     where strpos(lower(coalesce(pg_get_expr(pol.polqual, pol.polrelid),'')
                     || ' ' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid),'')), v_nombre) > 0
    union all
    select 'default/generada', ad.adrelid::regclass::text || '.' || a.attname
      from pg_attrdef ad join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
     where strpos(lower(pg_get_expr(ad.adbin, ad.adrelid)), v_nombre) > 0
    union all
    select 'constraint', con.conname || ' on ' || coalesce(con.conrelid::regclass::text,'-')
      from pg_constraint con
     where strpos(lower(pg_get_constraintdef(con.oid)), v_nombre) > 0
    union all
    select 'indice', i.indexrelid::regclass::text from pg_index i
     where (i.indexprs is not null or i.indpred is not null)
       and strpos(lower(pg_get_indexdef(i.indexrelid)), v_nombre) > 0
    union all
    select 'cron.job', j.jobname from cron.job j
     where strpos(lower(j.command), v_nombre) > 0
  )
  select count(*), string_agg(fuente || ': ' || objeto, ' | ') into v_n, v_detalle from censo;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: el censo encontro % referencia(s) VIVA(s) al tablero — resolverlas primero. %', v_n, v_detalle;
  end if;
end $ola2b_pre$;

drop function crm.metricas_altas_analista_fn(integer);

do $ola2b_acta$
declare v_n int;
begin
  update private.f7_piezas_en_observacion
     set estado = 'demolida',
         nota = coalesce(nota,'') || ' | DEMOLIDA por la OLA 2b (migracion '
                || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
                || ', `!` de Miguel): ventana cumplida, vigia vivo y en verde, definicion completa y'
                || ' comentario verificados contra la captura del 01/09, censo de nueve superficies sin'
                || ' referencias vivas y marcha atras recreadora ensayada.'
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'observacion';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'OLA 2b acta: el libro registro % actas, esperaba exactamente 1', v_n;
  end if;
end $ola2b_acta$;

do $ola2b_post$
declare v_n int; v_verd text;
begin
  if to_regprocedure('crm.metricas_altas_analista_fn(integer)') is not null then
    raise exception 'OLA 2b postflight: la funcion sigue viva';
  end if;

  -- Las dos del bridge NO se tocan (deuda declarada): siguen vivas y con SU dueño.
  select count(*) into v_n
  from pg_proc p
  where p.oid in (to_regprocedure('crm.metricas_distribucion_leads_fn(date,date)'),
                  to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)'))
    and pg_get_userbyid(p.proowner) = 'crm_metricas_bridge';
  if v_n <> 2 then
    raise exception 'OLA 2b postflight: las 2 del bridge no siguen vivas con su dueño (coincidencias %)', v_n;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'OLA 2b postflight: el acta no quedo escrita';
  end if;
  -- Solo esta pieza cambio de estado en esta migracion: la cohorte F7.1 conserva
  -- sus 4 pasillos permanentes y sus 2 del bridge en observacion.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F7.1' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'OLA 2b postflight: la cohorte F7.1 tiene % demolidas, esperaba 1', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'OLA 2b postflight: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'OLA 2b postflight: analitica en rojo: %', v_verd; end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then raise exception 'OLA 2b postflight: la demolicion levanto % alerta(s)', v_n; end if;
end $ola2b_post$;

commit;
$mig_ola2b$;

  -- 5) Si la version ya existe: muda => abortar; cuerpo distinto => abortar.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260914130000' and statements is null;
  if v_n > 0 then
    raise exception 'registrar ola2b: la version existe MUDA — repararla, no pisarla';
  end if;
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260914130000' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar ola2b: la version existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260914130000', 'crm_f7_ola2b_demoler_el_tablero_de_altas_v2', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 6) RELECTURA fail-closed: la fila EXACTA, o se cae la transaccion entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260914130000'
     and name = 'crm_f7_ola2b_demoler_el_tablero_de_altas_v2'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar ola2b: la relectura no encontro la fila exacta';
  end if;
end $reg_ola2b$;

select '20260914130000 registrada: el tablero de altas por analista, demolido y con su acta' as resultado,
       (select count(*) from supabase_migrations.schema_migrations) as versiones,
       (select count(*) from private.f7_piezas_en_observacion where estado = 'demolida') as piezas_demolidas;
-- [ensayo] commit; retirado (registrar-f7-ola2b-version.sql)


-- =====================================================================
-- ACTO 5 · LAS MARCHAS ATRAS REALES.
-- =====================================================================
-- ---------- MARCHA ATRAS REAL: rollback-f7-ola2b-tableros.sql ----------
-- MARCHA ATRAS de la OLA 2b — recrea `metricas_altas_analista_fn` con su
-- DEFINICION VIVA capturada de produccion el 2026-09-01.
--
-- Su partida de nacimiento NO esta en el repo (el repo tiene 167 de 193
-- archivos): vive en el registro remoto, version 20260716203331. La fuente es
-- la captura viva, no la carpeta local.
--
-- ⚠️ La fila del registro NO se borra aqui: retirarla A MANO.
-- ⚠️ Se revoca EXPLICITAMENTE a los tres roles de la API: recrear una funcion
--    hace que los default privileges le devuelvan EXECUTE (lo cazo el
--    vigilante F7 durante el ensayo del 01/09).
--
-- ✏️ CORRECCION del 01/09 (auditoria de Codex): la version anterior NO
--    restituia el COMENTARIO de la funcion, asi que la marcha atras era
--    materialmente INFIEL — y el ensayo salia verde igual, porque solo
--    comparaba `md5(prosrc)`. Es la prueba concreta de que una huella de
--    cuerpo no acredita una recreacion fiel. Ahora se restituye el comentario
--    y el postflight fija la DEFINICION COMPLETA (`pg_get_functiondef`, que
--    arrastra args, retorno, volatilidad, SECURITY DEFINER, search_path, coste
--    y filas), el dueño, el comentario y el ACL efectivo.

-- [ensayo] begin; retirado (rollback-f7-ola2b-tableros.sql)
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $rb_pre$
declare v_n int;
begin
  if to_regprocedure('crm.metricas_altas_analista_fn(integer)') is not null then
    raise exception 'rollback OLA 2b: la funcion YA existe — investigar antes de recrear';
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'rollback OLA 2b: el libro no la marca demolida — el mundo no es el que este guion revierte';
  end if;
end $rb_pre$;

CREATE OR REPLACE FUNCTION crm.metricas_altas_analista_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, analista_id uuid, analista_nombre text, altas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'private', 'public', 'crm'
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', cli.creado_en at time zone 'America/Lima'))::date as mes,
    coalesce(cli.asesor_perfil_id, cli.creado_por) as analista_id,
    coalesce(asesor.nombre_completo, 'Sin asesor') as analista_nombre,
    count(*)::bigint as altas
  from public.perfiles cli
  left join public.perfiles asesor
         on asesor.id = coalesce(cli.asesor_perfil_id, cli.creado_por)
  cross join ambito a
  where cli.rol = 'cliente'
    and cli.creado_en >= ((date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))
          at time zone 'America/Lima')
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 4 desc;
$function$;
alter function crm.metricas_altas_analista_fn(integer) owner to postgres;
revoke all on function crm.metricas_altas_analista_fn(integer) from public, anon, authenticated, service_role;
-- El comentario VIVO, al pie de la letra (capturado de produccion el 01/09).
comment on function crm.metricas_altas_analista_fn(integer) is
  'Agregado para gráfica de gerencia: altas de clientes por mes y por analista (nombra SOLO al asesor interno, nunca al cliente). Mismo ámbito por rol.';

-- El libro vuelve a `observacion`. La maquina de estados PROHIBE salir de
-- `demolida` salvo «por migracion con el candado bajado»: se baja el trigger
-- NOMBRADO y se vuelve a subir en la MISMA transaccion.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set estado = 'observacion',
       nota = coalesce(nota,'') || ' | REVERTIDA a observacion por la marcha atras ('
              || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || '): recreada al byte desde la captura viva del 01/09.'
 where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

do $rb_post$
declare v_h text; v_hd text; v_com text; v_own text; v_verd text; v_n int; v_oid oid;
begin
  v_oid := 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
         obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
    into v_h, v_hd, v_com, v_own
  from pg_proc p where p.oid = v_oid;

  -- (1) El CUERPO, al byte.
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'rollback OLA 2b: el cuerpo no volvio al byte (huella %)', v_h;
  end if;
  -- (2) La DEFINICION COMPLETA: args, retorno, volatilidad, SECURITY DEFINER,
  --     search_path, coste y filas. Aqui es donde se caza la deriva que la
  --     huella del cuerpo no ve.
  if v_hd is distinct from 'f439e788e16a49fa23d8b52c0047f929' then
    raise exception 'rollback OLA 2b: la DEFINICION no volvio al byte (huella %) — algun atributo derivo', v_hd;
  end if;
  -- (3) El COMENTARIO (el fallo que la auditoria del 01/09 destapo).
  if v_com is distinct from 'Agregado para gráfica de gerencia: altas de clientes por mes y por analista (nombra SOLO al asesor interno, nunca al cliente). Mismo ámbito por rol.' then
    raise exception 'rollback OLA 2b: el comentario no quedo restituido: %', coalesce(v_com,'<null>');
  end if;
  -- (4) El DUEÑO.
  if v_own is distinct from 'postgres' then
    raise exception 'rollback OLA 2b: quedo con dueño «%»', v_own;
  end if;
  -- (5) Y CERRADA de verdad: ACL efectivo sin concesiones ajenas al dueño, y
  --     privilegio efectivo nulo para los tres roles de la API (recrear una
  --     funcion hace que los default privileges le devuelvan EXECUTE).
  select count(*) into v_n
  from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = v_oid and a.privilege_type = 'EXECUTE'
    and a.grantee is distinct from p.proowner;
  if v_n > 0 then
    raise exception 'rollback OLA 2b: quedo con % concesion(es) EXECUTE fuera del dueño', v_n;
  end if;
  select count(*) into v_n from unnest(array['anon','authenticated','service_role']) as r(rol)
   where has_function_privilege(r.rol, v_oid, 'EXECUTE');
  if v_n > 0 then
    raise exception 'rollback OLA 2b: % rol(es) de la API conservan privilegio EFECTIVO de ejecucion', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback OLA 2b: vigilante F7 en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-OLA2b-OK: metricas_altas_analista_fn recreada al byte y cerrada' as resultado;
-- [ensayo] commit; retirado (rollback-f7-ola2b-tableros.sql)


-- ---------- MARCHA ATRAS REAL: rollback-f7-ola2-gemelas.sql ----------
-- MARCHA ATRAS de la OLA 2 (las siete gemelas) — recrea las 7 piezas con su DEFINICION VIVA,
-- capturada de produccion el 2026-09-01 (owner, atributos y comentario incluidos).
--
-- Por que la fuente es la CAPTURA y no el repo: el repo tiene 167 de 193
-- archivos y la F5.d cambio los cuerpos de las gemelas DESPUES de que nacieran.
-- La carpeta local mentiria; el catalogo vivo no.
--
-- ⚠️ La fila del registro NO se borra aqui: retirarla A MANO (regla del proyecto).
-- ⚠️ Recrear en `public` SI REABRE la puerta: los default privileges de Supabase
--    devuelven EXECUTE a anon/authenticated/service_role en cuanto la funcion
--    vuelve a existir, y `revoke ... from public` (el ROL) no los quita. Por eso
--    cada recreacion revoca EXPLICITAMENTE a los tres roles de la API.
--    Lo cazo el vigilante F7 durante el ensayo del 01/09, no una lectura.

-- [ensayo] begin; retirado (rollback-f7-ola2-gemelas.sql)
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Anti-pisado: solo se recrea si de verdad NO estan (si alguien ya las repuso,
-- este guion no las machaca a ciegas).
do $rb_pre$
declare v_n int;
begin
  select count(*) into v_n from unnest(array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', 'crm.crear_contrato_producto(uuid,jsonb,jsonb)', 'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'public.crear_contrato_producto(uuid,jsonb,jsonb)']) f
   where to_regprocedure(f) is not null;
  if v_n > 0 then
    raise exception 'rollback F5.d: % pieza(s) YA existen — investigar antes de recrear', v_n;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and estado = 'demolida';
  if v_n <> 7 then
    raise exception 'rollback F5.d: el libro marca % demolidas, esperaba 7 — el mundo no es el que este guion revierte', v_n;
  end if;
end $rb_pre$;

CREATE OR REPLACE FUNCTION crm.actualizar_contrato_con_cuenta_producto(p_id uuid, p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_condicion_resultante uuid;
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  perform crm.actualizar_contrato_con_cuenta(
    p_id, p_contrato, p_cronograma
  );
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  select c.producto_condicion_id into v_condicion_resultante
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  v_resultado := jsonb_build_object('id', p_id, 'ok', true)
    || private.metadata_condicion_producto(v_condicion_resultante);
  return v_resultado;
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;
alter function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) owner to postgres;
revoke all on function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION crm.actualizar_contrato_producto(p_id uuid, p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_condicion_resultante uuid;
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.actualizar_contrato(p_id, p_contrato, p_cronograma);
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  select c.producto_condicion_id into v_condicion_resultante
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;
alter function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) owner to postgres;
revoke all on function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_producto(p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := crm.crear_contrato_con_cuenta(
    p_contrato, p_cronograma, p_cuenta
  );
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  return v_resultado
    || private.metadata_condicion_producto(p_producto_condicion_id);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;
alter function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb) owner to postgres;
revoke all on function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION crm.crear_contrato_producto(p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  return v_resultado
    || private.metadata_condicion_producto(p_producto_condicion_id);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;
alter function crm.crear_contrato_producto(uuid,jsonb,jsonb) owner to postgres;
revoke all on function crm.crear_contrato_producto(uuid,jsonb,jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.actualizar_contrato_con_cuenta_producto(p_id uuid, p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_condicion_resultante uuid;
  v_resultado jsonb;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para actualizar contratos con cuenta desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  perform crm.actualizar_contrato_con_cuenta(
    p_id, p_contrato, p_cronograma
  );
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  v_resultado := jsonb_build_object('id', p_id, 'ok', true)
    || private.metadata_condicion_producto(v_condicion_resultante);
  return v_resultado;
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;
alter function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) owner to postgres;
revoke all on function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) from public, anon, authenticated, service_role;
comment on function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) is $cmt$Corrección Portal catalogada que además conserva la coherencia de la cuenta bancaria contractual.$cmt$;

CREATE OR REPLACE FUNCTION public.actualizar_contrato_producto(p_id uuid, p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_condicion_resultante uuid;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para actualizar contratos desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.actualizar_contrato(p_id, p_contrato, p_cronograma);
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;
alter function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) owner to postgres;
revoke all on function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) from public, anon, authenticated, service_role;
comment on function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) is $cmt$Corrección Portal catalogada; conserva Admin/Superadmin/Analista, cartera, ventana y cierres de public.actualizar_contrato.$cmt$;

CREATE OR REPLACE FUNCTION public.crear_contrato_producto(p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_contrato_id uuid;
  v_condicion_resultante uuid;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para crear contratos desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  v_contrato_id := (v_resultado->>'id')::uuid;
  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = v_contrato_id;
  if not found then
    raise exception 'Contrato no encontrado después del alta' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;
alter function public.crear_contrato_producto(uuid,jsonb,jsonb) owner to postgres;
revoke all on function public.crear_contrato_producto(uuid,jsonb,jsonb) from public, anon, authenticated, service_role;
comment on function public.crear_contrato_producto(uuid,jsonb,jsonb) is $cmt$Alta Portal catalogada; conserva la autorización de public.crear_contrato y fija la condición en la misma transacción.$cmt$;

-- El libro vuelve a `observacion`. La maquina de estados PROHIBE salir de
-- `demolida` salvo «por migracion con el candado bajado» (doctrina
-- limpieza-leads): se baja el trigger NOMBRADO, se corrige y se vuelve a subir
-- en la MISMA transaccion. Jamas un `disable trigger user` a ciegas.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set estado = 'observacion',
       nota = coalesce(nota,'') || ' | REVERTIDA a observacion por la marcha atras ('
              || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || '): la pieza fue recreada al byte desde la captura viva del 01/09.'
 where ola = 'F5.d' and estado = 'demolida';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- Verificacion: volvieron las 7 ENTERAS y los guardianes quedan verdes.
-- ✏️ 01/09 (auditoria de Codex): comparar solo `md5(prosrc)` NO acredita una
--    recreacion fiel — en la Ola 2b una funcion volvio SIN su comentario y el
--    ensayo salio verde igual. Aqui se fija ademas la DEFINICION COMPLETA
--    (`pg_get_functiondef`: args, retorno, volatilidad, SECURITY DEFINER,
--    search_path, coste, filas), el COMENTARIO, el DUEÑO y el ACL EFECTIVO.
do $rb_post$
declare
  -- firma | huella del CUERPO | huella de la DEFINICION | comentario vivo (null = sin comentario)
  v_fn constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          '8640b1246f620ab40558cec2875ada23','956fb5f32191291d4b7ebafce5abbdb1', null],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          '4156191492c25479be73b0365263d946','1d884ef9f60a55dd4d0613a256e3ea71', null],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
          '06f79b07b4d65dcf50cd4359fb598723','a93f2db825cc26c19b1756cde0cdc435', null],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',
          '1148d0ca1beb33797995eeff3c579bd4','230bcc46e72191600cbd5fc789e1d503', null],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          'b7e0de18b559ec7fd650619cd22b9cb5','c786d25a9aca26f6a818dd57abe6ef72',
          'Corrección Portal catalogada que además conserva la coherencia de la cuenta bancaria contractual.'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          'f0e519cc4ee79c9334ae59a23844b23b','7128b0ebb65497e67c56d5383988b512',
          'Corrección Portal catalogada; conserva Admin/Superadmin/Analista, cartera, ventana y cierres de public.actualizar_contrato.'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',
          '893c857e27ec6405a3ac6e291458c346','58f41209f1cedf46198e7c76903f7bbb',
          'Alta Portal catalogada; conserva la autorización de public.crear_contrato y fija la condición en la misma transacción.']
  ];
  v_fila text[]; v_h text; v_hd text; v_com text; v_own text;
  v_verd text; v_n int; v_oid oid;
begin
  foreach v_fila slice 1 in array v_fn loop
    v_oid := to_regprocedure(v_fila[1]);
    if v_oid is null then
      raise exception 'rollback F5.d: % no se recreo', v_fila[1];
    end if;
    select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
           obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
      into v_h, v_hd, v_com, v_own
    from pg_proc p where p.oid = v_oid;

    if v_h is distinct from v_fila[2] then
      raise exception 'rollback F5.d: % no volvio al byte en el CUERPO (huella %)', v_fila[1], v_h;
    end if;
    if v_hd is distinct from v_fila[3] then
      raise exception 'rollback F5.d: % no volvio al byte en la DEFINICION (huella %) — algun atributo derivo', v_fila[1], v_hd;
    end if;
    if v_com is distinct from v_fila[4] then
      raise exception 'rollback F5.d: % no recupero su COMENTARIO (quedo: %)', v_fila[1], coalesce(v_com,'<null>');
    end if;
    if v_own is distinct from 'postgres' then
      raise exception 'rollback F5.d: % quedo con dueño «%»', v_fila[1], v_own;
    end if;

    -- Y CERRADA: recrear una funcion hace que los default privileges le
    -- devuelvan EXECUTE a anon/authenticated/service_role.
    select count(*) into v_n
    from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = v_oid and a.privilege_type = 'EXECUTE'
      and a.grantee is distinct from p.proowner;
    if v_n > 0 then
      raise exception 'rollback F5.d: % quedo con % concesion(es) EXECUTE fuera del dueño', v_fila[1], v_n;
    end if;
    select count(*) into v_n from unnest(array['anon','authenticated','service_role']) as r(rol)
     where has_function_privilege(r.rol, v_oid, 'EXECUTE');
    if v_n > 0 then
      raise exception 'rollback F5.d: % conserva privilegio EFECTIVO para % rol(es) de la API', v_fila[1], v_n;
    end if;
  end loop;

  -- El libro devolvio LAS SIETE FIRMAS EXACTAS a observacion. Contar 7 filas de
  -- la ola no basta: una cohorte sustituida cumple el conteo con el conjunto
  -- equivocado, y esto es una marcha atras de emergencia — el peor momento para
  -- enterarse. (Lo pidio Codex en la 2.ª vuelta.)
  select count(*) into v_n
  from unnest(array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)']) as f(firma)
  where not exists (
    select 1 from private.f7_piezas_en_observacion l
     where l.firma = f.firma and l.ola = 'F5.d' and l.estado = 'observacion');
  if v_n > 0 then
    raise exception 'rollback F5.d: % de las 7 firmas NO volvieron a observacion', v_n;
  end if;
  -- Y la cohorte no tiene filas de mas ni ninguna demolida.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and estado = 'demolida';
  if v_n <> 0 then
    raise exception 'rollback F5.d: quedan % gemelas marcadas demolidas', v_n;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion where ola = 'F5.d';
  if v_n <> 7 then
    raise exception 'rollback F5.d: la cohorte F5.d tiene % filas, esperaba exactamente 7', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F5.d: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F5.d: analitica en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-F5.d-OK: las 7 piezas recreadas al byte y cerradas como estaban' as resultado;
-- [ensayo] commit; retirado (rollback-f7-ola2-gemelas.sql)


-- =====================================================================
-- ACTO 6 · ¿VOLVIO EL MUNDO? Las ocho, vivas y cerradas, con su definicion
-- COMPLETA y su comentario. Y las dos del bridge, intactas con su dueño.
-- =====================================================================
do $acto6$
declare
  v_esperado constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)','956fb5f32191291d4b7ebafce5abbdb1'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)','1d884ef9f60a55dd4d0613a256e3ea71'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)','a93f2db825cc26c19b1756cde0cdc435'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)','230bcc46e72191600cbd5fc789e1d503'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)','c786d25a9aca26f6a818dd57abe6ef72'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)','7128b0ebb65497e67c56d5383988b512'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)','58f41209f1cedf46198e7c76903f7bbb'],
    array['crm.metricas_altas_analista_fn(integer)','f439e788e16a49fa23d8b52c0047f929']
  ];
  v_fila text[]; v_hd text; v_n int; v_verd text;
begin
  foreach v_fila slice 1 in array v_esperado loop
    if to_regprocedure(v_fila[1]) is null then
      raise exception 'ACTO 6: % NO volvio', v_fila[1];
    end if;
    select md5(pg_get_functiondef(p.oid)) into v_hd from pg_proc p where p.oid = to_regprocedure(v_fila[1]);
    if v_hd is distinct from v_fila[2] then
      raise exception 'ACTO 6: % volvio con OTRA definicion (huella %)', v_fila[1], v_hd;
    end if;
  end loop;

  select count(*) into v_n from pg_proc p
   where p.oid in (to_regprocedure('crm.metricas_distribucion_leads_fn(date,date)'),
                   to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)'))
     and pg_get_userbyid(p.proowner) = 'crm_metricas_bridge';
  if v_n <> 2 then
    raise exception 'ACTO 6: las 2 del bridge no siguen con su dueño (coincidencias %)', v_n;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion where estado = 'demolida';
  if v_n <> 0 then
    raise exception 'ACTO 6: quedan % pieza(s) marcadas demolidas tras la marcha atras', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'ACTO 6: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'ACTO 6: analitica en rojo: %', v_verd; end if;
  select private.assert_analista_vigencia() into v_verd;
  if v_verd not like 'OK%' then raise exception 'ACTO 6: vigencia en rojo: %', v_verd; end if;
end $acto6$;

-- =====================================================================
-- ACTO 7 · VEREDICTO. Termina SIEMPRE en error: nada se queda.
-- =====================================================================
do $acto7$
declare v_v int; v_d int;
begin
  select count(*) into v_v from supabase_migrations.schema_migrations;
  select count(*) into v_d from private.f7_piezas_en_observacion;
  raise exception 'F7-OLAS-2y2b-ENSAYO-VERDE: mutante de ventana cazado en las dos olas por el preflight REAL (con el CHECK puesto), migraciones y registradores aplicados (registro habria quedado en % versiones), marchas atras recrearon las 8 con definicion y comentario al byte, libro con % piezas y guardianes en verde. TODO DESHECHO.', v_v, v_d;
end $acto7$;

rollback;

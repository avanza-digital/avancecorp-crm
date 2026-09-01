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
begin;
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
commit;

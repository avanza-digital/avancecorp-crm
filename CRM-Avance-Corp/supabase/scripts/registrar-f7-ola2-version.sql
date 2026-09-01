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
begin;
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
commit;

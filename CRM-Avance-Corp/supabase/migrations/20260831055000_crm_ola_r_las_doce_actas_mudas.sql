-- P-055 OLA R (v3) - LAS DOCE ACTAS MUDAS DEL REGISTRO GANAN SU CUERPO.
--
-- 12 versiones de prod tienen fila SIN statements (aplicadas en su dia por
-- guion directo): sin cuerpo, ningun banco puede replay-ar la historia. Este
-- reparador les da su cuerpo EXACTO desde los archivos del repo, cuya
-- FIDELIDAD contra el catalogo vivo quedo demostrada objeto a objeto y
-- auditada (Codex la sostuvo). La evidencia es el CATALOGO VIVO, no git: dos
-- archivos (182000/182500) se commitearon el 26/08 y el ledger los da por
-- aplicados el 28/08; el instante real no es recuperable
-- (track_commit_timestamp=off). Por eso NO se afirma fecha de aplicacion.
--
-- Contrato (Miguel + DOS refutaciones de Codex + auditor-rls, 30/08):
--  * DOS estados globales y NINGUN hibrido: PRE (189 versiones, 12 mudas, LAS
--    12) -> repara; POST (0 mudas y las 12 con cuerpo objetivo EXACTO) ->
--    no-op; 11 mudas u otro mundo ABORTA (mano ajena: reconciliar a mano).
--  * La identidad del cuerpo es POR ELEMENTO (Codex v2: md5 del texto unido
--    NO ve fronteras desplazadas): md5(string_agg(md5(elemento) order by
--    ordinality)) + conteo + cero elementos NULL o vacios.
--  * Tags con VERSION COMPLETA $olar_<version>_<i>$ (Codex v2: los sufijos
--    de 6 digitos colisionaban entre 0820190500 y 0828190500).
--  * DIFF CERO por CONTENIDO, no conteos: funciones con firma completa,
--    policies con qual/withcheck, triggers por triggerdef, checks por def,
--    cron por comando, comments con classoid, default-ACL con namespace,
--    columnas con identidad/generacion/collation/ACL/stats.
--  * Se registra con su propio registrador: jamas la muda 13. Orden:
--    esta version (055000) ANTES que la F7.1 (060000); el registrador de la
--    F7.1 queda ENCADENADO a que esta exista.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: PRE o POST, nada mas + FOTO por contenido.
-- =====================================================================
create temp table _olar_esperado (version text primary key, huella_elems text, n_sentencias int) on commit drop;
insert into _olar_esperado values
  ('20260819162752', '399f72b907f4bab63ad4fb124c4d4755', 17),
  ('20260819211815', '14e8587e631e35d318b580d23f0342f5', 13),
  ('20260820190500', '6e4ae5f02480d3a0fc913b38cdcfa578', 17),
  ('20260826151907', 'f6b4b452868510ad433d3fd4418b4874', 10),
  ('20260826154500', '066eaf9312823cdc860545ca3764c5f7', 9),
  ('20260826173523', '8a3bb03f7da1d3a6f9181fd61bedd8c9', 11),
  ('20260826174500', 'b4444752f25e85f5d54a830b9f24fe9e', 10),
  ('20260826182000', 'e1d79c85d595e72f61ddfaacb081c87b', 7),
  ('20260826182500', '1f71c71f2b2db9dae6d23a6080be838f', 10),
  ('20260828190000', '018116c2ff04537be42e034abba7de2a', 7),
  ('20260828190500', 'a109153ca42c6de632c8ea23b19bde1f', 19),
  ('20260828191000', '3390c367bf9b573b525c508ad21bd576', 6);

do $$
declare v_total int; v_mudas int; v_lista text[]; v_mal text; v_sent int;
begin
  select count(*) into v_total from supabase_migrations.schema_migrations;
  select count(*) into v_mudas from supabase_migrations.schema_migrations where statements is null;
  select coalesce(array_agg(version order by version), '{}') into v_lista
    from supabase_migrations.schema_migrations where statements is null;

  if v_mudas = 0 then
    select e.version into v_mal from _olar_esperado e
      left join supabase_migrations.schema_migrations m on m.version = e.version
     where m.version is null
        or (select md5(string_agg(md5(u.s), '|' order by u.ord))
           from unnest(m.statements) with ordinality as u(s, ord)) is distinct from e.huella_elems
        or coalesce(array_length(m.statements, 1), 0) <> e.n_sentencias
        or exists (select 1 from unnest(m.statements) s where s is null or btrim(s) = '')
     limit 1;
    if v_mal is not null then
      raise exception 'OLA R: mundo POST pero la version % NO tiene el cuerpo objetivo - reconciliar a mano, jamas pisar', v_mal;
    end if;
  elsif v_mudas = 12 then
    if v_total <> 189 then
      raise exception 'OLA R preflight: hay % versiones (deben ser exactamente 189 antes de reparar)', v_total;
    end if;
    if v_lista <> array['20260819162752', '20260819211815', '20260820190500', '20260826151907', '20260826154500', '20260826173523', '20260826174500', '20260826182000', '20260826182500', '20260828190000', '20260828190500', '20260828191000']::text[] then
      raise exception 'OLA R preflight: las mudas NO son las 12 conocidas (%)', v_lista;
    end if;
  else
    raise exception 'OLA R preflight: % mudas - ni PRE (12) ni POST (0); una mano ajena toco el registro: reconciliar a mano', v_mudas;
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations
              where statements is not null and array_length(statements, 1) is null) then
    raise exception 'OLA R preflight: hay versiones con statements VACIO (reparadas a medias)';
  end if;
  select sum(n_sentencias) into v_sent from _olar_esperado;
  if v_sent <> 136 then
    raise exception 'OLA R preflight: el objetivo no suma 136 sentencias (%)', v_sent;
  end if;

  create temp table _olar_foto on commit drop as
  select
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('public','crm','private')) as fns,
    (select md5(string_agg(n.nspname || '.' || p.proname
        || '(' || pg_get_function_identity_arguments(p.oid) || ')'
        || ':' || md5(p.prosrc) || ':' || p.prorettype::regtype::text
        || ':' || p.provolatile::text || ':' || p.prosecdef::text
        || ':' || coalesce(p.proconfig::text,'-') || ':' || p.proowner::regrole::text
        || ':' || coalesce(p.proacl::text,'-'), '|'
        order by n.nspname, p.proname, p.oid))
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('public','crm','private') and p.prokind = 'f') as huella_fns,
    (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname in ('public','crm','private') and c.relkind in ('r','v','m','i')) as rels,
    -- Codex v2: CONTENIDO, no conteos
    (select md5(coalesce(string_agg(pol.polname || ':' || pol.polrelid::regclass::text
        || ':' || coalesce(pg_get_expr(pol.polqual, pol.polrelid), '-')
        || ':' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '-'), '|'
        order by pol.polrelid, pol.polname), '-')) from pg_policy pol) as policies_h,
    (select md5(coalesce(string_agg(pg_get_triggerdef(t.oid), '|' order by t.oid), '-'))
      from pg_trigger t where not t.tgisinternal) as triggers_h,
    (select md5(coalesce(string_agg(c.conname || ':' || pg_get_constraintdef(c.oid), '|'
        order by c.conrelid, c.conname), '-')) from pg_constraint c where c.contype = 'c') as checks_h,
    (select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.username || ':' || md5(j.command), '|'
        order by j.jobid), '-')) from cron.job j) as crons_h,
    (select md5(coalesce(string_agg(d.classoid::text || ':' || d.objoid::text || ':' || d.objsubid || ':' || md5(d.description), '|'
        order by d.classoid, d.objoid, d.objsubid), '-')) from pg_description d) as comments_h,
    (select md5(coalesce(string_agg(d.defaclrole::regrole::text || ':' || coalesce(d.defaclnamespace::regnamespace::text, '-')
        || ':' || d.defaclobjtype::text || ':' || d.defaclacl::text, '|'
        order by d.oid), '-')) from pg_default_acl d) as defacl_h,
    (select md5(string_agg(n.nspname || '.' || c.relname || '.' || a.attname || ':' || a.atttypid::regtype::text
        || ':' || a.attnotnull::text || ':' || coalesce(pg_get_expr(ad.adbin, ad.adrelid), '-')
        || ':' || a.attidentity::text || ':' || a.attgenerated::text
        || ':' || a.attcollation::text || ':' || coalesce(a.attacl::text, '-') || ':' || a.attstattarget::text, '|'
        order by n.nspname, c.relname, a.attnum))
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
      left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
      where n.nspname in ('public','crm','private') and c.relkind = 'r'
        and a.attnum > 0 and not a.attisdropped) as columnas_h,
    (select count(*) from public.contratos) as contratos,
    (select count(*) from crm.leads) as leads;

end $$;

-- =====================================================================
-- 1) LOS 12 CUERPOS (NULL-guard: solo escribe sobre NULL; en POST no-op).
-- =====================================================================
-- 20260819162752 (crm_domicilio_legal_faltante): 17 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260819162752_0$-- Domicilio legal faltante: desbloquea el 2.o contrato de un cliente antiguo.
--
-- EL SINTOMA (Miguel, 2026-08-19): «los vendedores no pueden registrar otro
-- contrato a clientes antiguos».
--
-- LA CAUSA, medida en produccion. `crm.crear_contrato_con_cuenta_pdf_v2` reserva
-- el PDF en la MISMA transaccion del alta, y `private.contrato_pdf_snapshot_v2_base`
-- exige los datos que van escritos en el documento: del cliente
-- nombre_completo, tipo_documento, dni, DOMICILIO y correo; del analista
-- nombre_completo, dni, telefono y correo. Si falta uno, el raise revierte el
-- contrato ENTERO. Reproducido en produccion sin escribir nada (bloque DO que
-- termina en raise) sobre el contrato d2625108-3081-46e5-a016-6bdc7b19a984.
--
-- Censo del 2026-08-19 sobre los 319 clientes con contrato: 313 sin domicilio
-- (98%) y CERO sin cualquiera de los otros cuatro campos. El domicilio es el
-- unico culpable, y esta medido campo por campo, no por muestreo.
--
-- Y el vendedor no veia ni siquiera ese mensaje: `aErrorApi` no reconocia el
-- 23514 y lo convertia en «No se pudo guardar el cambio.» (corregido en el
-- front por este mismo cambio). Por eso nadie pudo diagnosticarlo.
--
-- POR QUE NO PODIAN ARREGLARLO ELLOS. `perfiles_analista_update` exige
-- `creado_en > now() - '05:00:00'`: la ventana de «Corregir» dura 5 h desde que
-- el vendedor creo al cliente. Un cliente de hace meses cae fuera, asi que el
-- vendedor no podia emitir NI escribir el dato. `perfiles_analista_select` no
-- tiene ventana: podia LEER el hueco sin poder cerrarlo.
--
-- QUE ABRE (decisiones de Miguel, 2026-08-19): (1) el VENDEDOR rellena el
-- domicilio de sus clientes sin depender de nadie; (2) SOLO se rellena el
-- vacio — un domicilio ya registrado no se pisa nunca desde aqui.
--
-- EL GATE ES PRESTADO, NO COPIADO: `private.puede_gestionar_cuentas_cliente()`,
-- el mismo con el que `crm.crear_contrato_con_cuenta` decide quien gestiona la
-- banca contractual del cliente. Inventar un segundo concepto de «cartera» es
-- la via por la que este proyecto ya se hizo dano. Es condicion NECESARIA para
-- emitir pero no suficiente (`public.crear_contrato` exige ademas rol), asi que
-- el conjunto que podra escribir el domicilio es un SUPERCONJUNTO del que
-- emite: no se afirma equivalencia. Medido ejecutando el predicado real: de los
-- 313 afectados, 312 los resuelve su propio asesor y 1 (sin asesor asignado)
-- necesita a Gerencia. Inalcanzables: 0.
--
-- AUDITORIA ADVERSARIA (2026-08-19, 4 lentes: Codex + auditor-rls + carreras +
-- consecuencias legales). Lo aplicado aqui:
--   · el permiso se REEVALUA despues del lock (autorizacion caducada);
--   · no se devuelve el domicilio ajeno (era lectura de PII para el supervisor,
--     que por RLS no puede leer esa columna);
--   · `for no key update` en vez de `for update`: misma exclusion mutua sin
--     frenar inserts de tablas hijas con FK a ese perfil;
--   · `get diagnostics` sobre el UPDATE: responder 'completado' habiendo tocado
--     0 filas seria mentir al vendedor y dejarlo bloqueado creyendo que guardo;
--   · se rechazan los caracteres INVISIBLES (ancho cero, guion suave, controles
--     bidi). Comprobado contra el CHECK vivo de produccion: seis U+200B lo
--     pasan hoy, se imprimirian como NADA en el contrato y —al no ser vacios
--     para btrim— cerrarian el hueco PARA SIEMPRE (el trigger
--     `perfiles_domicilio_legal_no_borrar` impide volver a NULL y esta funcion
--     nunca pisa lo existente);
--   · el postflight comprobaba `search_path=` cuando el catalogo guarda
--     `search_path=""`: la sonda era SIEMPRE falsa y habria hecho rollback de
--     la migracion entera, en todas sus ejecuciones;
--   · `create or replace` + sondas de datos fuera: la version anterior exigia
--     que el defecto siguiera vivo, asi que no se podia reaplicar en un branch
--     ya saneado. Las sondas de COMPORTAMIENTO (que ejecutan las funciones, en
--     vez de mirar el catalogo) viven en
--     `supabase/scripts/test-domicilio-legal.sql`.
--
-- No altera NINGUN objeto de `public`: crea funciones en `crm` que ESCRIBEN una
-- columna de `public.perfiles`, igual que la RPC de Gerencia ya viva. Lo que si
-- cambia es QUIEN escribe esa columna saltandose la RLS del portal (antes solo
-- Gerencia; ahora toda la cartera CRM): queda anotado en el registro de
-- excepciones de MIGRACIONES.md aunque no haya DDL, porque ese registro es el
-- indice donde se busca «quien le escribe a mis tablas».

begin;$olar_20260819162752_0$,
$olar_20260819162752_1$set local lock_timeout = '10s';$olar_20260819162752_1$,
$olar_20260819162752_2$set local statement_timeout = '120s';$olar_20260819162752_2$,
$olar_20260819162752_3$-- ── Preflight: plpgsql NO resuelve referencias al crear ──────────────────────
-- Sin esto, un renombrado de las dependencias crearia ambas funciones y solo
-- fallaria en runtime, con el vendedor delante.
do $preflight$
begin
  if to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null then
    raise exception 'PREFLIGHT: falta private.puede_gestionar_cuentas_cliente(uuid)';
  end if;
  if to_regprocedure('private.contrato_pdf_snapshot_v2_base(uuid)') is null then
    raise exception 'PREFLIGHT: falta private.contrato_pdf_snapshot_v2_base(uuid)';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'perfiles'
      and column_name = 'domicilio'
  ) then
    raise exception 'PREFLIGHT: falta public.perfiles.domicilio';
  end if;
end;
$preflight$;$olar_20260819162752_3$,
$olar_20260819162752_4$-- ── Normalizador compartido del domicilio legal ──────────────────────────────
-- Fuente UNICA del servidor, espejo de `validarDomicilioLegal` del navegador.
-- Devuelve el texto normalizado o levanta el error es-PE correspondiente.
--
-- Por que normalizar y no solo validar: `btrim` de Postgres solo quita U+0020,
-- mientras que `.trim()` de JavaScript quita todo el espacio Unicode. Sin
-- normalizar, «  Lima » lo rechaza el navegador (4 caracteres) y
-- lo acepta el servidor (7): dos varas para el mismo dato.
create or replace function crm.normalizar_domicilio_legal(p_domicilio text)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  -- Espacios exoticos que SI ocupan sitio: se convierten en espacio normal.
  v_espacios constant text := U&'\00A0\2007\202F\3000\1680\2000\2001\2002\2003\2004\2005\2006\2008\2009\200A\205F';
  -- Invisibles de ancho CERO y controles de direccion: no se normalizan, se
  -- RECHAZAN. Se escriben con escapes Unicode a proposito — pegarlos literales
  -- volveria ilegible (y no auditable) este fichero.
  v_invisibles constant text :=
    U&'[\00AD\180E\200B\200C\200D\200E\200F\2028\2029\202A\202B\202C\202D\202E\2060\2061\2062\2063\2064\FEFF]';
  v_out text;
begin
  v_out := coalesce(p_domicilio, '');
  v_out := translate(v_out, v_espacios, repeat(' ', length(v_espacios)));
  v_out := btrim(regexp_replace(v_out, '\s+', ' ', 'g'));

  if v_out = '' then
    raise exception 'Completa el domicilio legal del cliente.'
      using errcode = '22023';
  end if;
  if v_out ~ v_invisibles then
    raise exception 'El domicilio legal contiene caracteres invisibles que no se imprimirian en el contrato.'
      using errcode = '22023';
  end if;
  -- length() sobre text cuenta CARACTERES, igual que el Array.from() del
  -- navegador. Limites identicos a crm.actualizar_cliente_gerencia_con_domicilio
  -- y al CHECK vivo perfiles_domicilio_legal_valido.
  if length(v_out) not between 5 and 240 or v_out ~ '[[:cntrl:]]' then
    raise exception
      'El domicilio legal debe tener entre 5 y 240 caracteres válidos'
      using errcode = '22023';
  end if;
  return v_out;
end;
$function$;$olar_20260819162752_4$,
$olar_20260819162752_5$comment on function crm.normalizar_domicilio_legal(text) is
  'Normaliza (espacios Unicode a espacio simple, colapsa, recorta) y valida el domicilio legal: 5..240 caracteres, sin controles y sin invisibles de ancho cero. Fuente unica del servidor; espejo de validarDomicilioLegal del navegador.';$olar_20260819162752_5$,
$olar_20260819162752_6$revoke all on function crm.normalizar_domicilio_legal(text)
  from public, anon, authenticated, service_role;$olar_20260819162752_6$,
$olar_20260819162752_7$-- ── Lectura: que dato legal falta para poder emitir ──────────────────────────
-- Devuelve NOMBRES de campo, nunca valores: no es una via para leer PII.
--
-- El «analista» que valida el snapshot es `contratos.creado_por`, y
-- `public.crear_contrato` lo escribe siempre como auth.uid(): por eso aqui se
-- mira el perfil de QUIEN LLAMA. Eso la hace correcta para el ALTA (su unico
-- consumidor) y solo para el alta — para regenerar el PDF de un contrato creado
-- por otra persona, el perfil que importa es el de aquella. Anotado como deuda
-- en el ledger; el nombre no promete otra cosa.
create or replace function crm.datos_legales_contrato_fn(p_cliente_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_cliente public.perfiles%rowtype;
  v_analista public.perfiles%rowtype;
  -- Los append van con ::text explicito: `text[] || 'literal'` es AMBIGUO en
  -- Postgres (intenta castear el literal a text[]) y revienta en RUNTIME con
  -- «malformed array literal», no al crear la funcion. Compilaba y fallaba con
  -- el vendedor delante; lo caza el oraculo de comportamiento, no el catalogo.
  v_faltan_cliente text[] := '{}';
  v_faltan_analista text[] := '{}';
begin
  if v_uid is null then
    raise insufficient_privilege using message = 'Sesion no valida';
  end if;

  -- MISMO texto para «no existe» y «ajeno»: no da oraculo de existencia.
  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  select * into v_cliente
  from public.perfiles p
  where p.id = p_cliente_id
    and p.rol = 'cliente';
  if not found then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  select * into v_analista
  from public.perfiles p
  where p.id = v_uid;
  if not found then
    raise exception 'Tu perfil no esta disponible' using errcode = 'P0002';
  end if;

  if nullif(btrim(coalesce(v_cliente.nombre_completo, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'nombre_completo'::text;
  end if;
  if nullif(btrim(coalesce(v_cliente.tipo_documento, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'tipo_documento'::text;
  end if;
  if nullif(btrim(coalesce(v_cliente.dni, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'documento'::text;
  end if;
  if nullif(btrim(coalesce(v_cliente.domicilio, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'domicilio'::text;
  end if;
  if nullif(btrim(coalesce(v_cliente.correo, '')), '') is null then
    v_faltan_cliente := v_faltan_cliente || 'correo'::text;
  end if;

  if nullif(btrim(coalesce(v_analista.nombre_completo, '')), '') is null then
    v_faltan_analista := v_faltan_analista || 'nombre_completo'::text;
  end if;
  if nullif(btrim(coalesce(v_analista.dni, '')), '') is null then
    v_faltan_analista := v_faltan_analista || 'documento'::text;
  end if;
  if nullif(btrim(coalesce(v_analista.telefono, '')), '') is null then
    v_faltan_analista := v_faltan_analista || 'telefono'::text;
  end if;
  if nullif(btrim(coalesce(v_analista.correo, '')), '') is null then
    v_faltan_analista := v_faltan_analista || 'correo'::text;
  end if;

  return jsonb_build_object(
    'version', 1,
    'cliente_id', p_cliente_id,
    -- El unico que el vendedor puede resolver por su cuenta. Los demas huecos
    -- se informan para que el front diga a quien acudir, no para que los edite.
    'falta_domicilio', ('domicilio' = any (v_faltan_cliente)),
    'faltan_cliente', to_jsonb(v_faltan_cliente),
    'faltan_analista', to_jsonb(v_faltan_analista)
  );
end;
$function$;$olar_20260819162752_7$,
$olar_20260819162752_8$comment on function crm.datos_legales_contrato_fn(uuid) is
  'Que dato legal falta para poder EMITIR el contrato de este cliente: nombres de campo del cliente y del propio analista que llama, nunca valores. Espejo de private.contrato_pdf_snapshot_v2_base. Alcance: private.puede_gestionar_cuentas_cliente.';$olar_20260819162752_8$,
$olar_20260819162752_9$revoke all on function crm.datos_legales_contrato_fn(uuid)
  from public, anon, authenticated, service_role;$olar_20260819162752_9$,
$olar_20260819162752_10$grant execute on function crm.datos_legales_contrato_fn(uuid) to authenticated;$olar_20260819162752_10$,
$olar_20260819162752_11$-- ── Escritura: rellenar el domicilio VACIO ───────────────────────────────────
create or replace function crm.completar_domicilio_cliente(
  p_cliente_id uuid,
  p_domicilio text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_domicilio text;
  v_actual text;
  v_filas int;
begin
  if v_uid is null then
    raise insufficient_privilege using message = 'Sesion no valida';
  end if;

  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  v_domicilio := crm.normalizar_domicilio_legal(p_domicilio);

  -- Techo a la espera del lock: mas vale un error claro que una pantalla
  -- colgada mientras otra transaccion larga retiene la fila.
  perform set_config('lock_timeout', '3s', true);

  -- `for no key update` y no `for update`: da la misma exclusion mutua entre
  -- dos escrituras concurrentes del domicilio y sigue conflictuando con el
  -- `for share` del alta de contrato, pero NO bloquea los inserts de tablas
  -- hijas con FK a este perfil (contratos, cuentas, leads).
  select nullif(btrim(coalesce(p.domicilio, '')), '')
  into v_actual
  from public.perfiles p
  where p.id = p_cliente_id
    and p.rol = 'cliente'
  for no key update;
  if not found then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  -- El permiso se comprueba OTRA VEZ, ya con la fila bloqueada: entre la
  -- primera comprobacion y el lock pudo esperarse a otra transaccion (una
  -- reasignacion de cartera, una baja) y la autorizacion de arriba estaria
  -- caducada. Mismo patron que private.crear_job_contrato_pdf_base.
  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception 'Cliente no encontrado o fuera de tu cartera'
      using errcode = '42501';
  end if;

  -- NO se devuelve el domicilio que ya estaba: el alcance incluye al supervisor
  -- del arbol, que por RLS no puede leer public.perfiles.domicilio
  -- (perfiles_analista_select exige asesor_perfil_id = auth.uid()). Devolverlo
  -- convertiria una funcion de ESCRITURA en una via de lectura de PII.
  if v_actual is not null then
    return jsonb_build_object('version', 1, 'accion', 'conservado');
  end if;

  update public.perfiles
  set domicilio = v_domicilio
  where id = p_cliente_id
    and rol = 'cliente';

  -- Sin esto, un UPDATE que toque 0 filas (RLS forzada, trigger, la fila
  -- cambiada bajo los pies) devolveria 'completado' y el vendedor veria
  -- «Domicilio legal registrado» sobre algo que no se guardo: seguiria
  -- bloqueado, y convencido de lo contrario.
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception 'El domicilio legal no se pudo registrar (% filas afectadas)', v_filas
      using errcode = 'P0001';
  end if;

  -- Tampoco se devuelve en 'completado': es EXACTAMENTE el texto que envio
  -- quien llama, y devolverlo solo abriria la puerta a usar esta funcion como
  -- lectura disfrazada.
  return jsonb_build_object('version', 1, 'accion', 'completado');
end;
$function$;$olar_20260819162752_11$,
$olar_20260819162752_12$comment on function crm.completar_domicilio_cliente(uuid, text) is
  'Rellena public.perfiles.domicilio SOLO si esta vacio (nunca lo pisa; devuelve completado|conservado, sin el valor). Normaliza y valida via crm.normalizar_domicilio_legal. Alcance: private.puede_gestionar_cuentas_cliente, reevaluado tras el lock.';$olar_20260819162752_12$,
$olar_20260819162752_13$revoke all on function crm.completar_domicilio_cliente(uuid, text)
  from public, anon, authenticated, service_role;$olar_20260819162752_13$,
$olar_20260819162752_14$grant execute on function crm.completar_domicilio_cliente(uuid, text) to authenticated;$olar_20260819162752_14$,
$olar_20260819162752_15$-- ── Postflight ESTRUCTURAL (re-ejecutable) ───────────────────────────────────
-- Las sondas de comportamiento —las que EJECUTAN las funciones contra datos—
-- viven en supabase/scripts/test-domicilio-legal.sql, no aqui: una sonda que
-- exija «que el defecto siga existiendo» convierte la migracion en irrepetible
-- y se auto-invalida el dia en que el arreglo funciona.
do $postflight$
declare
  v_fuente text;
  v_bloque text;
  v_campo text;
  v_faltan text[] := '{}';
begin
  -- 1. El espejo sigue siendo espejo. Se mira SOLO el bloque de validacion del
  --    snapshot (desde el `if nullif(btrim(` hasta su `raise`), no la funcion
  --    entera: buscar el identificador en todo el cuerpo daba verde aunque
  --    alguien sacara el campo del `if` y lo dejara en el jsonb de salida.
  -- Sin `strict`: si la funcion no existe o esta sobrecargada, el error nativo
  -- («query returned no rows») no dice cual es el problema ni cual es la sonda.
  select pg_get_functiondef(p.oid) into v_fuente
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'contrato_pdf_snapshot_v2_base'
  limit 1;
  if v_fuente is null then
    raise exception
      'POSTFLIGHT 1: no existe private.contrato_pdf_snapshot_v2_base; el espejo no se puede comprobar';
  end if;

  v_bloque := substring(
    v_fuente
    from 'if nullif\(btrim.*?Faltan datos legales obligatorios'
  );
  if v_bloque is null then
    raise exception
      'POSTFLIGHT 1: no se encontro el bloque de validacion legal del snapshot; el espejo ya no se puede comprobar';
  end if;

  foreach v_campo in array array[
    'v_cliente.nombre_completo', 'v_cliente.tipo_documento', 'v_cliente.dni',
    'v_cliente.domicilio', 'v_cliente.correo',
    'v_analista.nombre_completo', 'v_analista.dni',
    'v_analista.telefono', 'v_analista.correo'
  ] loop
    if strpos(v_bloque, v_campo) = 0 then
      v_faltan := v_faltan || v_campo;
    end if;
  end loop;
  if cardinality(v_faltan) > 0 then
    raise exception
      'POSTFLIGHT 1: el snapshot ya no exige %; datos_legales_contrato_fn quedo desalineada',
      array_to_string(v_faltan, ', ');
  end if;

  -- Y al reves: si el snapshot exige MAS campos de perfil de los que espejamos,
  -- el vendedor volveria a chocar contra un muro sin nombre. Se cuenta.
  if (select count(*) from regexp_matches(v_bloque, 'v_(cliente|analista)\.', 'g')) <> 9 then
    raise exception
      'POSTFLIGHT 1: el snapshot exige % campos de perfil y el espejo cubre 9',
      (select count(*) from regexp_matches(v_bloque, 'v_(cliente|analista)\.', 'g'));
  end if;
  raise notice 'POSTFLIGHT 1 OK: los 9 campos legales del snapshot estan espejados (bloque de validacion, no el cuerpo entero).';

  -- 2. Las tres funciones nacen con search_path fijado y los grants exactos.
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname in (
        'datos_legales_contrato_fn', 'completar_domicilio_cliente',
        'normalizar_domicilio_legal'
      )
      -- `set search_path to ''` deja en proconfig el literal `search_path=""`
      -- CON comillas. La forma ingenua ('search_path=' = any(...)) es SIEMPRE
      -- falsa, asi que la sonda levantaba excepcion en toda ejecucion y hacia
      -- rollback de la migracion entera. Verificado en PG16 y PG17 por la
      -- auditoria adversaria del 2026-08-19; el resto del repo ya usa esta
      -- forma en 8 sitios.
      and (p.proconfig is null or not (p.proconfig @> array['search_path=""']))
  ) then
    raise exception 'POSTFLIGHT 2: alguna funcion nueva no fijo search_path';
  end if;

  -- Los dos lados del grant, no solo uno: que anon/service_role NO puedan y que
  -- authenticated SI pueda. Un grant mal escrito deja la pantalla muerta y la
  -- version anterior de esta sonda no lo habria cazado.
  --
  -- Los roles se comprueban antes: has_function_privilege() sobre un rol
  -- inexistente lanza `role "X" does not exist` y abortaria el arnes local con
  -- un error que no describe nada.
  if to_regrole('anon') is null
     or to_regrole('authenticated') is null
     or to_regrole('service_role') is null then
    raise notice 'POSTFLIGHT 2: faltan los roles de Supabase (base pelada); se omite la comprobacion de grants.';
  elsif has_function_privilege('anon', 'crm.datos_legales_contrato_fn(uuid)', 'execute')
     or has_function_privilege('anon', 'crm.completar_domicilio_cliente(uuid, text)', 'execute')
     or has_function_privilege('anon', 'crm.normalizar_domicilio_legal(text)', 'execute')
     or has_function_privilege('service_role', 'crm.datos_legales_contrato_fn(uuid)', 'execute')
     or has_function_privilege('service_role', 'crm.completar_domicilio_cliente(uuid, text)', 'execute')
     or has_function_privilege('authenticated', 'crm.normalizar_domicilio_legal(text)', 'execute') then
    raise exception 'POSTFLIGHT 2: alguna funcion nueva conserva execute para un rol que no debe';
  end if;
  if not has_function_privilege('authenticated', 'crm.datos_legales_contrato_fn(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'crm.completar_domicilio_cliente(uuid, text)', 'execute') then
    raise exception 'POSTFLIGHT 2: authenticated NO puede ejecutar las RPC; la pantalla naceria muerta';
  end if;
  if not (
    select bool_and(p.prosecdef)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname in ('datos_legales_contrato_fn', 'completar_domicilio_cliente')
  ) then
    raise exception 'POSTFLIGHT 2: alguna RPC no quedo como SECURITY DEFINER';
  end if;
  raise notice 'POSTFLIGHT 2 OK: search_path fijado, SECURITY DEFINER donde toca y grants minimos en los dos sentidos.';

  -- 3. La autoria de la escritura NO es una premisa: se ancla. Es la primera
  --    vez que esta columna se abre a decenas de personas, y el unico rastro de
  --    quien la escribio es el trigger de auditoria del portal.
  --    Los casts van por to_regclass/to_regprocedure: el cast directo revienta
  --    con `undefined_function` ANTES de llegar al raise con nombre, y la sonda
  --    nunca llega a decir lo que queria decir.
  if to_regprocedure('public.log_audit_change()') is null
     or not exists (
    select 1 from pg_trigger t
    where t.tgrelid = to_regclass('public.perfiles')
      and not t.tgisinternal
      and t.tgfoid = to_regprocedure('public.log_audit_change()')
  ) then
    raise exception
      'POSTFLIGHT 3: public.perfiles no tiene el trigger de auditoria; la escritura del domicilio quedaria sin autor';
  end if;
  raise notice 'POSTFLIGHT 3 OK: la escritura del domicilio queda auditada con su autor.';
end;
$postflight$;$olar_20260819162752_15$,
$olar_20260819162752_16$commit;$olar_20260819162752_16$
], name = coalesce(name, '20260819162752_crm_domicilio_legal_faltante')
 where version = '20260819162752' and statements is null;

-- 20260819211815 (crm_domicilio_una_sola_puerta): 13 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260819211815_0$-- El domicilio legal: UNA sola puerta, y con el liston a la altura del dato.
--
-- POR QUE. El 2026-08-19 se cerro el agujero de los caracteres INVISIBLES en la
-- ventana nueva de «+ Contrato», pero el mismo campo tiene otras TRES puertas, y
-- las tres seguian aceptandolo (comprobado EJECUTANDO las tres, no leyendo):
--   1. `crm.convertir_lead_con_domicilio`  — al convertir un lead en cliente
--   2. `_shared/domicilio.mjs`             — el alta automatica (edge)
--   3. `crm.actualizar_cliente_gerencia_con_domicilio` — la correccion de Gerencia
-- Cada una tenia su propia copia de la validacion: `length between 5 and 240` y
-- `[[:cntrl:]]`. Tres copias de una regla es tres reglas.
--
-- QUE HACE ESTA MIGRACION. Deja `crm.normalizar_domicilio_legal` como **fuente
-- unica** y hace que las otras dos funciones SQL la usen. La edge se alinea en
-- el mismo commit (`_shared/domicilio.mjs`), y el navegador tambien.
--
-- EL LISTON, DECIDIDO CON LOS DATOS REALES, no a ojo. Los 19 domicilios que hay
-- hoy en produccion:
--   · llevan numero: 19 de 19 (100 %)
--   · el mas corto: 28 caracteres
--   · el que menos palabras tiene: 5
-- Frente a lo que hoy PASA el filtro: `LIMA.` (5), `PENDIENTE` (9), `no tiene`
-- (8), `.....`. Por eso:
--   · exigir al menos un DIGITO no molesta a nadie —lo cumple el 100 %— y mata
--     de un golpe a todos los rellenos;
--   · el minimo sube de 5 a 15 caracteres, casi la mitad del mas corto real.
-- Ninguno de los 19 domicilios vivos queda por debajo del liston nuevo: subirlo
-- no rompe ninguna correccion posterior de Gerencia.
--
-- Y LA DIRECCION DE LA PROPIA AVANCE CORP se rechaza. No es hipotetico: el
-- 2026-08-19 se tecleo `Av. República de Panamá 3635` como domicilio de una
-- clienta, que es la direccion de la empresa en la cabecera del contrato. El PDF
-- habria dicho que ambas partes domicilian en el mismo sitio, y la clausula
-- decima cuarta manda ahi TODAS las notificaciones: la carta al cliente llegaria
-- a la oficina de quien se la manda.
--
-- No altera ningun objeto de `public`; reemplaza funciones de `crm` que ya
-- escriben `public.perfiles.domicilio`, como las que ya estaban vivas.

begin;$olar_20260819211815_0$,
$olar_20260819211815_1$set local lock_timeout = '10s';$olar_20260819211815_1$,
$olar_20260819211815_2$set local statement_timeout = '120s';$olar_20260819211815_2$,
$olar_20260819211815_3$do $preflight$
begin
  if to_regprocedure('crm.normalizar_domicilio_legal(text)') is null then
    raise exception 'PREFLIGHT: falta crm.normalizar_domicilio_legal(text)';
  end if;
  if to_regprocedure('crm.convertir_lead(uuid, uuid)') is null then
    raise exception 'PREFLIGHT: falta crm.convertir_lead(uuid, uuid)';
  end if;
  if to_regprocedure('crm.actualizar_cliente_gerencia(uuid, jsonb)') is null then
    raise exception 'PREFLIGHT: falta crm.actualizar_cliente_gerencia(uuid, jsonb)';
  end if;
end;
$preflight$;$olar_20260819211815_3$,
$olar_20260819211815_4$-- ── La fuente unica, con el liston nuevo ─────────────────────────────────────
create or replace function crm.normalizar_domicilio_legal(p_domicilio text)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  -- Espacios exoticos que SI ocupan sitio: se convierten en espacio normal.
  v_espacios constant text := U&'\00A0\2007\202F\3000\1680\2000\2001\2002\2003\2004\2005\2006\2008\2009\200A\205F';
  -- Invisibles de ancho CERO y controles de direccion: no se normalizan, se
  -- RECHAZAN. Escritos con escapes Unicode a proposito — pegarlos literales
  -- volveria este fichero ilegible y no auditable.
  v_invisibles constant text :=
    U&'[\00AD\180E\200B\200C\200D\200E\200F\2028\2029\202A\202B\202C\202D\202E\2060\2061\2062\2063\2064\FEFF]';
  v_min constant int := 15;
  v_max constant int := 240;
  v_out text;
  v_plano text;
begin
  v_out := coalesce(p_domicilio, '');
  v_out := translate(v_out, v_espacios, repeat(' ', length(v_espacios)));
  v_out := btrim(regexp_replace(v_out, '\s+', ' ', 'g'));

  if v_out = '' then
    raise exception 'Completa el domicilio legal del cliente.'
      using errcode = '22023';
  end if;
  if v_out ~ v_invisibles then
    raise exception 'El domicilio legal contiene caracteres invisibles que no se imprimirian en el contrato.'
      using errcode = '22023';
  end if;
  -- length() sobre text cuenta CARACTERES, igual que el Array.from() del
  -- navegador.
  if length(v_out) not between v_min and v_max or v_out ~ '[[:cntrl:]]' then
    raise exception
      'El domicilio legal debe tener entre % y % caracteres válidos; escribe la calle, el número y el distrito.',
      v_min, v_max
      using errcode = '22023';
  end if;

  -- Al menos un digito. Los 19 domicilios reales de produccion lo cumplen sin
  -- excepcion, y es lo que separa una direccion de un relleno: `LIMA.`,
  -- `PENDIENTE`, `no tiene`, `Su casa` caen todos aqui.
  if v_out !~ '[0-9]' then
    raise exception
      'El domicilio legal necesita el número de la calle, el lote o la manzana.'
      using errcode = '22023';
  end if;

  -- Un unico caracter repetido: `.....`, `xxxxxxxxxxxxxxxx`, `----------------`.
  if length(regexp_replace(v_out, '[^[:alnum:]]', '', 'g')) > 0
     and (select count(distinct c) from regexp_split_to_table(
            regexp_replace(lower(v_out), '[^[:alnum:]]', '', 'g'), '') as t(c)) = 1 then
    raise exception 'El domicilio legal no puede ser un solo carácter repetido.'
      using errcode = '22023';
  end if;

  -- La direccion de la PROPIA Avance Corp. Se compara en plano (sin tildes, sin
  -- mayusculas, sin puntuacion) para que no la salve un acento o un «N.°».
  v_plano := lower(translate(v_out,
    'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
  v_plano := regexp_replace(v_plano, '[^a-z0-9 ]', '', 'g');
  v_plano := regexp_replace(v_plano, '\s+', ' ', 'g');
  if v_plano like '%republica de panama%' and v_plano like '%3635%' then
    raise exception
      'Esa es la dirección de Avance Corp, no la del cliente: el contrato dejaría a las dos partes domiciliadas en el mismo sitio.'
      using errcode = '22023';
  end if;

  return v_out;
end;
$function$;$olar_20260819211815_4$,
$olar_20260819211815_5$comment on function crm.normalizar_domicilio_legal(text) is
  'FUENTE UNICA de validacion del domicilio legal: normaliza espacios Unicode, rechaza invisibles de ancho cero, exige 15..240 caracteres y al menos un digito, y rechaza un solo caracter repetido y la direccion de la propia Avance Corp. La usan las TRES puertas SQL; el navegador y la edge la espejan.';$olar_20260819211815_5$,
$olar_20260819211815_6$revoke all on function crm.normalizar_domicilio_legal(text)
  from public, anon, authenticated, service_role;$olar_20260819211815_6$,
$olar_20260819211815_7$-- ── Puerta 1: convertir un lead en cliente ───────────────────────────────────
-- Tenia su propia copia de la regla (5..240 + cntrl). Ahora presta la fuente
-- unica, y de paso ESCRIBE el texto normalizado en vez del `btrim` a secas.
create or replace function crm.convertir_lead_con_domicilio(
  p_lead_id uuid,
  p_perfil_id uuid,
  p_domicilio text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_domicilio text;
  v_resultado jsonb;
  v_accion text := 'conservado';
begin
  -- Se valida ANTES de convertir: si falla, todavia no se ha escrito nada.
  v_domicilio := crm.normalizar_domicilio_legal(p_domicilio);

  v_resultado := crm.convertir_lead(p_lead_id, p_perfil_id);

  update public.perfiles
     set domicilio = v_domicilio
   where id = p_perfil_id
     and rol = 'cliente'
     and domicilio is null;
  if found then v_accion := 'completado'; end if;

  return v_resultado || jsonb_build_object('domicilio_accion', v_accion);
end;
$function$;$olar_20260819211815_7$,
$olar_20260819211815_8$comment on function crm.convertir_lead_con_domicilio(uuid, uuid, text) is
  'Convierte el lead y completa el domicilio SOLO si estaba vacio. Valida con crm.normalizar_domicilio_legal (fuente unica) ANTES de convertir: un domicilio invalido no deja el lead a medias.';$olar_20260819211815_8$,
$olar_20260819211815_9$-- ── Puerta 3: la correccion de Gerencia ──────────────────────────────────────
-- Tercera copia de la misma regla, y la unica que puede SOBRESCRIBIR un
-- domicilio existente. Es justamente la que repara los errores de las otras dos:
-- con mas razon tiene que aplicar el mismo liston.
create or replace function crm.actualizar_cliente_gerencia_con_domicilio(
  p_cliente_id uuid,
  p_patch jsonb
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_domicilio text;
  v_actualizado boolean;
begin
  if private.rol_crm((select auth.uid())) is distinct from 'gerencia' then
    raise insufficient_privilege using
      message = 'Solo Gerencia puede corregir clientes fuera de cartera';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object'
     or not p_patch ? 'domicilio'
     or jsonb_typeof(p_patch->'domicilio') <> 'string' then
    raise exception 'El domicilio legal del cliente es obligatorio'
      using errcode = '22023';
  end if;

  v_domicilio := crm.normalizar_domicilio_legal(p_patch->>'domicilio');

  v_actualizado := crm.actualizar_cliente_gerencia(
    p_cliente_id,
    p_patch - 'domicilio'
  );
  if not v_actualizado then return false; end if;

  update public.perfiles
     set domicilio = v_domicilio
   where id = p_cliente_id
     and rol = 'cliente';
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;$olar_20260819211815_9$,
$olar_20260819211815_10$comment on function crm.actualizar_cliente_gerencia_con_domicilio(uuid, jsonb) is
  'Correccion de Gerencia: unica via que puede SOBRESCRIBIR un domicilio ya registrado. Valida con crm.normalizar_domicilio_legal (fuente unica).';$olar_20260819211815_10$,
$olar_20260819211815_11$-- ── Postflight ───────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puertas text[] := array[
    'crm.convertir_lead_con_domicilio',
    'crm.actualizar_cliente_gerencia_con_domicilio',
    'crm.completar_domicilio_cliente'
  ];
  v_p text;
  v_src text;
  v_huerfanas text[] := '{}';
  v_bajo_liston int;
  v_medibles int;
begin
  -- 1. Las TRES puertas prestan la fuente unica. Si alguna vuelve a llevar su
  --    copia de la regla, esto lo dice por su nombre.
  foreach v_p in array v_puertas loop
    select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname || '.' || p.proname = v_p
    limit 1;
    if v_src is null then
      raise exception 'POSTFLIGHT 1: no existe %', v_p;
    end if;
    if strpos(v_src, 'crm.normalizar_domicilio_legal') = 0 then
      v_huerfanas := v_huerfanas || v_p;
    end if;
  end loop;
  if cardinality(v_huerfanas) > 0 then
    raise exception
      'POSTFLIGHT 1: estas puertas NO usan la fuente unica y validan por su cuenta: %',
      array_to_string(v_huerfanas, ', ');
  end if;
  raise notice 'POSTFLIGHT 1 OK: las 3 puertas del domicilio prestan la misma validacion.';

  -- 2. El liston nuevo no deja fuera a ningun domicilio YA registrado: si lo
  --    hiciera, Gerencia no podria volver a guardar la ficha de ese cliente.
  --
  --    ⚠️ Esta sonda tiene HAMBRE DE DATOS y lo DICE. En un branch recien
  --    sembrado no hay ni un domicilio escrito, asi que pasaria en verde sin
  --    haber medido nada — la «rama de aviso disfrazada de OK» que este
  --    proyecto prohibe. Si no hay nada que medir, se grita en vez de aprobar:
  --    el numero real hay que mirarlo en PRODUCCION antes de aplicar alli.
  --    (Medido el 2026-08-19 contra produccion: 22 domicilios, 0 por debajo de
  --    15 caracteres, 0 sin numero, el mas corto de 28.)
  select count(*) into v_medibles
  from public.perfiles
  where rol = 'cliente'
    and nullif(btrim(coalesce(domicilio, '')), '') is not null;

  if v_medibles = 0 then
    raise warning
      'POSTFLIGHT 2 NO SE EJERCITO: esta base no tiene ni un domicilio escrito. NO cuenta como aprobado — comprueba el liston contra PRODUCCION antes de aplicarlo alli.';
  else
    select count(*) into v_bajo_liston
    from public.perfiles
    where rol = 'cliente'
      and nullif(btrim(coalesce(domicilio, '')), '') is not null
      and (length(btrim(domicilio)) < 15 or btrim(domicilio) !~ '[0-9]');
    if v_bajo_liston > 0 then
      raise exception
        'POSTFLIGHT 2: % de % domicilios YA registrados quedan por debajo del liston nuevo; Gerencia no podria reguardarlos',
        v_bajo_liston, v_medibles;
    end if;
    raise notice 'POSTFLIGHT 2 OK: los % domicilios vivos pasan el liston.', v_medibles;
  end if;

  -- 3. Y el liston hace lo que dice: se EJECUTA la funcion contra la basura y
  --    contra una direccion real. Mirar el catalogo no prueba nada.
  declare
    v_basura text[] := array[
      'LIMA.', 'PENDIENTE', 'no tiene', 'Su casa', '....................',
      'Av. República de Panamá 3635'
    ];
    v_caso text;
    v_coladas text[] := '{}';
  begin
    foreach v_caso in array v_basura loop
      begin
        perform crm.normalizar_domicilio_legal(v_caso);
        v_coladas := v_coladas || v_caso;
      exception when sqlstate '22023' then
        null; -- correcto
      end;
    end loop;
    if cardinality(v_coladas) > 0 then
      raise exception 'POSTFLIGHT 3: se colaron por el liston: %',
        array_to_string(v_coladas, ' | ');
    end if;
    -- Y una direccion REAL de produccion tiene que pasar, o el arreglo seria
    -- peor que el problema: volveria a bloquear a los vendedores.
    if crm.normalizar_domicilio_legal('AV. MAESTRO PERUANO 225 URB. CARABAYLLO, COMAS, LIMA, LIMA')
       <> 'AV. MAESTRO PERUANO 225 URB. CARABAYLLO, COMAS, LIMA, LIMA' then
      raise exception 'POSTFLIGHT 3: una direccion real de produccion no pasa el liston';
    end if;
    raise notice 'POSTFLIGHT 3 OK: los 6 rellenos se rechazan y la direccion real pasa intacta.';
  end;
end;
$postflight$;$olar_20260819211815_11$,
$olar_20260819211815_12$commit;$olar_20260819211815_12$
], name = coalesce(name, '20260819211815_crm_domicilio_una_sola_puerta')
 where version = '20260819211815' and statements is null;

-- 20260820190500 (crm_documento_regimen_por_fecha_de_firma): 17 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260820190500_0$-- El documento contractual solo existe para lo firmado del 2026-08-19 en adelante.
--
-- POR QUE. Miguel lo fijo el 2026-08-20: «el sistema me da un PDF que se usa como
-- unico contrato, pero los clientes anteriores a esto (19-08) ya tienen otro tipo
-- de contrato». La frontera la manda la FECHA DE FIRMA (`contratos.fecha_inicio`),
-- no la fecha en que el contrato se carga al sistema. Una operacion de febrero que
-- se registra hoy es del regimen ANTERIOR: ya tiene su contrato, y el sistema no
-- debe fabricarle otro.
--
-- QUE ESTABA PASANDO (medido en produccion el 2026-08-20, no supuesto):
--   · De los 31 contratos cargados desde el 18-ago, 26 se firmaron ANTES del 19 y
--     a 21 de ellos YA se les emitio documento nuevo. El mas viejo: 17 de febrero.
--   · El mecanismo no era el alta: es el boton «Ver contrato PDF» del detalle. Si
--     el contrato no tiene documento, ese boton NO muestra — FABRICA uno nuevo
--     (front → edge `ensure` → `crm.contrato_pdf_reservar`). Cualquiera que abriera
--     un contrato viejo acuñaba un contrato en el formato nuevo, fechado meses
--     atras y con el domicilio de HOY (el de notificaciones, clausula 14.ª).
--   · Efecto colateral del mismo agujero: como el documento exige el domicilio, la
--     carga del historial —que es el 97 % del trabajo real del equipo: 214 contratos
--     en 30 dias, solo 6 firmados del 19-ago en adelante— chocaba contra un muro
--     que ese contrato no necesitaba.
--
-- QUE HACE ESTA MIGRACION. `private.contrato_documental_regimen` como **fuente
-- unica** de la frontera (misma forma que `crm.normalizar_domicilio_legal` en el
-- bloque 1: una sola puerta, un solo liston) y las CUATRO funciones que pueden
-- acuñar o mover un documento la consultan:
--   1. `private.crear_job_contrato_pdf_base`      — alta y boton «Ver PDF»
--   2. `private.crear_revision_contrato_pdf_base` — correccion de contrato/numero
--   3. `crm.contrato_pdf_reclamar`                — la entrega del turno a la edge
--   4. `private.contrato_pdf_estado_base`         — lo que ve la pantalla
--
-- LO QUE NO TOCA, POR DECISION DE MIGUEL: los 21 documentos ya emitidos para
-- operaciones antiguas **se quedan como estan**. Siguen sellados, siguen
-- descargables. Esta migracion impide que nazcan mas, no borra los que hay.
--
-- LOS DOS TRABAJOS A MEDIAS. Los contratos 2026-01-000319 y 2026-01-000602
-- (RAMIREZ CARDENAS TONNY, firmados el 26-mar y el 18-may) tienen un trabajo en
-- `pendiente` desde el 19-ago con CERO intentos: nadie los reclamo nunca y nadie
-- los reclamara. No se borra ni se muta una sola fila: con la regla nueva quedan
-- INERTES (nadie puede reclamarlos) e INVISIBLES (el estado responde
-- `sin_reserva`), que es la verdad — ese contrato no lleva documento nuevo.
--
-- ORDEN DE DESPLIEGUE — LA EDGE VA PRIMERO. `parseEstado` de
-- `crm-contrato-pdf-v2` EXIGE hoy `reintentable === true` cuando el estado es
-- `sin_reserva`; devolver `false` sin actualizarla antes hace que la edge
-- descarte la respuesta entera (502) y la pantalla del contrato se rompa. La edge
-- tolerante viaja en este mismo commit y se despliega ANTES que esta migracion.
--
-- No crea, altera ni borra ningun objeto de `public`.

begin;$olar_20260820190500_0$,
$olar_20260820190500_1$set local lock_timeout = '10s';$olar_20260820190500_1$,
$olar_20260820190500_2$set local statement_timeout = '120s';$olar_20260820190500_2$,
$olar_20260820190500_3$do $preflight$
begin
  if to_regprocedure('private.crear_job_contrato_pdf_base(uuid, uuid)') is null then
    raise exception 'PREFLIGHT: falta private.crear_job_contrato_pdf_base(uuid, uuid)';
  end if;
  if to_regprocedure('private.crear_revision_contrato_pdf_base(uuid, uuid)') is null then
    raise exception 'PREFLIGHT: falta private.crear_revision_contrato_pdf_base(uuid, uuid)';
  end if;
  if to_regprocedure('private.contrato_pdf_estado_base(uuid)') is null then
    raise exception 'PREFLIGHT: falta private.contrato_pdf_estado_base(uuid)';
  end if;
  if to_regprocedure('crm.contrato_pdf_reclamar(uuid, uuid, integer)') is null then
    raise exception 'PREFLIGHT: falta crm.contrato_pdf_reclamar(uuid, uuid, integer)';
  end if;
  -- La frontera se apoya en una columna NOT NULL: si `fecha_inicio` admitiera
  -- nulos, un contrato sin fecha caeria en 'anterior' por comparacion nula y se
  -- quedaria mudo para siempre sin que nadie lo notase.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'contratos'
      and column_name = 'fecha_inicio' and is_nullable = 'NO'
  ) then
    raise exception 'PREFLIGHT: public.contratos.fecha_inicio dejo de ser NOT NULL';
  end if;
end;
$preflight$;$olar_20260820190500_3$,
$olar_20260820190500_4$-- ── La fuente unica de la frontera ───────────────────────────────────────────
-- Devuelve 'nuevo', 'anterior' o NULL (contrato inexistente). El NULL importa:
-- quien la llama NO debe tratarlo como 'anterior', sino dejar que su propio
-- camino de «contrato no encontrado» levante el error de siempre.
--
-- ⚠️ SON DOS FECHAS, Y LA SEGUNDA NO SOBRA. `fecha_inicio` es el inicio del
-- PLAZO, que no siempre coincide con la firma: medido en produccion el
-- 2026-08-20, los contratos 2026-01-000891 y 2026-01-000892 (REATEGUI PEREZ
-- PEDRO IVAN, S/ 170.000 y S/ 250.000) se cargaron el 1 de JULIO con
-- `fecha_inicio` = 2027-07-01. Con la fecha de plazo sola caerian en el regimen
-- NUEVO y el sistema les ofreceria emitir un contrato en el formato nuevo a dos
-- operaciones firmadas en julio, cuando este documento ni existia. El suelo de
-- `creado_en` lo impide sin contradecir la regla de Miguel: una operacion
-- registrada ANTES del 19-ago no pudo firmarse el 19-ago o despues. En hora de
-- Lima, que es donde se firma.
create or replace function private.contrato_documental_regimen(p_contrato_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select case
    when c.fecha_inicio >= date '2026-08-19'
         and (c.creado_en at time zone 'America/Lima')::date >= date '2026-08-19'
      then 'nuevo'
    else 'anterior'
  end
  from public.contratos c
  where c.id = p_contrato_id
$$;$olar_20260820190500_4$,
$olar_20260820190500_5$comment on function private.contrato_documental_regimen(uuid) is
  'Regimen documental de un contrato por FECHA DE FIRMA: firmado el 2026-08-19 o '
  'despues => ''nuevo'' (el sistema emite el PDF, que es el unico contrato); antes '
  '=> ''anterior'' (el cliente ya tiene su contrato en el formato previo y el '
  'sistema no le emite ninguno). NULL si el contrato no existe. Fuente unica: '
  'ninguna otra funcion repite esta fecha.';$olar_20260820190500_5$,
$olar_20260820190500_6$revoke all on function private.contrato_documental_regimen(uuid) from public;$olar_20260820190500_6$,
$olar_20260820190500_7$-- ── 1. El alta y el boton «Ver PDF»: no acuñan documento para lo antiguo ─────
create or replace function private.crear_job_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job_id uuid;
  v_snapshot jsonb;
  v_nombre text;
  v_revision integer;
begin
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  if exists (
    select 1 from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
  ) or exists (
    select 1 from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id
  ) then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  -- LA FRONTERA. Va DESPUES del permiso (no se filtra la existencia de un
  -- contrato ajeno) y ANTES de la fotografia contractual: es justo el snapshot
  -- quien exige los nueve datos —domicilio incluido—, asi que salir aqui es lo
  -- que libera la carga del historial de un requisito que ese contrato no tiene.
  if private.contrato_documental_regimen(p_contrato_id) = 'anterior' then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  v_job_id := gen_random_uuid();
  v_revision := 1;
  v_snapshot := private.contrato_pdf_snapshot_v2_base(p_contrato_id);
  v_nombre := private.nombre_archivo_contrato_pdf(p_contrato_id);
  if v_nombre is null then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  insert into private.contrato_pdf_jobs (
    id, contrato_id, revision, estado, storage_path, nombre_archivo,
    template_version, snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    'contrato-aep-17-v5',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;$olar_20260820190500_7$,
$olar_20260820190500_8$-- Mismos privilegios que ya tenía viva (`postgres=X/postgres`). `create or
-- replace` los conserva; se repiten porque un ACL que solo vive en la memoria
-- de otra migración es un ACL que nadie puede auditar aquí.
revoke all on function private.crear_job_contrato_pdf_base(uuid, uuid)
  from public, anon, authenticated, service_role;$olar_20260820190500_8$,
$olar_20260820190500_9$-- ── 2. Las correcciones: tampoco acuñan documento para lo antiguo ────────────
-- Incluye a los 21 ya emitidos: corregir uno de ellos NO genera una revision
-- nueva. Es coherente con «se quedan como estan» — y con que ese papel no es el
-- contrato de esa operacion, asi que refrescarlo no arregla nada y si acuñaria
-- un documento mas.
create or replace function private.crear_revision_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job_id uuid := gen_random_uuid();
  v_revision integer;
  v_snapshot jsonb;
  v_nombre text;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  if private.contrato_documental_regimen(p_contrato_id) = 'anterior' then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  select greatest(
    coalesce((select max(j.revision) from private.contrato_pdf_jobs j
              where j.contrato_id = p_contrato_id), 0),
    coalesce((select max(p.revision) from private.contrato_pdfs p
              where p.contrato_id = p_contrato_id), 0)
  ) + 1 into v_revision;

  v_snapshot := private.contrato_pdf_snapshot_v2_base(p_contrato_id);
  v_nombre := private.nombre_archivo_contrato_pdf(p_contrato_id);
  if v_nombre is null then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  insert into private.contrato_pdf_jobs (
    id, contrato_id, revision, estado, storage_path, nombre_archivo,
    snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;$olar_20260820190500_9$,
$olar_20260820190500_10$revoke all on function private.crear_revision_contrato_pdf_base(uuid, uuid)
  from public, anon, authenticated, service_role;$olar_20260820190500_10$,
$olar_20260820190500_11$-- ── 3. La entrega del turno: nadie trabaja un documento del regimen anterior ─
-- La guarda va DESPUES del bloque de integridad y del corte por
-- 'sellado'/'integridad_bloqueada': para los 21 ya emitidos todo sigue igual
-- (incluido el autodiagnostico de ledger incoherente). Solo muerde en
-- 'pendiente' / 'error_reintentable' / lease caducado, que es exactamente donde
-- viven los dos trabajos huerfanos del 19-ago.
create or replace function crm.contrato_pdf_reclamar(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_lease_segundos integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job private.contrato_pdf_jobs%rowtype;
  v_token uuid;
  v_adquirido boolean := false;
  v_estado_siguiente text;
  v_respuesta jsonb;
begin
  if p_lease_segundos is null
     or p_lease_segundos not between 30 and 300 then
    raise exception 'El lease debe durar entre 30 y 300 segundos'
      using errcode = '22023';
  end if;

  select * into v_job
  from private.contrato_pdf_jobs j
  where j.contrato_id = p_contrato_id
  order by j.revision desc
  limit 1;
  if not found then
    raise exception 'El contrato no tiene una reserva PDF v2'
      using errcode = 'P0002';
  end if;

  perform private.bloquear_fila_contrato_pdf(v_job.contrato_id);
  if private.contrato_en_eliminacion(v_job.contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = v_job.id
  for update;

  if not private.puede_leer_contrato_pdf_como(
    v_job.contrato_id, p_actor_id
  ) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  v_respuesta := private.contrato_pdf_estado_base(v_job.contrato_id);
  if (v_respuesta->>'estado') = 'integridad_bloqueada'
     and v_job.estado <> 'integridad_bloqueada' then
    update private.contrato_pdf_jobs
       set estado = 'integridad_bloqueada',
           lease_token = null,
           lease_expira_en = null,
           sellado_en = null,
           ultimo_error = 'LEDGER_INCOHERENTE',
           actualizado_en = statement_timestamp()
     where id = v_job.id;
    return private.contrato_pdf_estado_base(v_job.contrato_id)
      || jsonb_build_object('adquirido', false);
  end if;

  if v_job.estado in ('sellado', 'integridad_bloqueada') then
    return v_respuesta || jsonb_build_object('adquirido', false);
  end if;

  if private.contrato_documental_regimen(v_job.contrato_id) = 'anterior' then
    return v_respuesta || jsonb_build_object('adquirido', false);
  end if;

  if v_job.estado in ('pendiente', 'error_reintentable') then
    v_adquirido := true;
    v_estado_siguiente := case
      when v_job.sha256 is null then 'procesando'
      else 'subido_verificado'
    end;
  elsif v_job.estado in ('procesando', 'subido_verificado')
        and v_job.lease_expira_en <= statement_timestamp() then
    v_adquirido := true;
    v_estado_siguiente := v_job.estado;
  end if;

  if not v_adquirido then
    return v_respuesta || jsonb_build_object('adquirido', false);
  end if;

  v_token := gen_random_uuid();
  update private.contrato_pdf_jobs
     set estado = v_estado_siguiente,
         lease_token = v_token,
         lease_expira_en = statement_timestamp()
           + make_interval(secs => p_lease_segundos),
         intentos = intentos + 1,
         ultimo_error = null,
         actualizado_en = statement_timestamp()
   where id = v_job.id;

  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = v_job.id;

  return private.contrato_pdf_estado_base(v_job.contrato_id)
    || jsonb_build_object(
      'adquirido', true,
      'lease_token', v_token,
      'snapshot', v_job.snapshot,
      'renderizado_en', v_job.creado_en
    );
end;
$function$;$olar_20260820190500_11$,
$olar_20260820190500_12$-- ── 4. Lo que ve la pantalla: la verdad, no una promesa ──────────────────────
-- Un contrato del regimen anterior SIN archivo responde `sin_reserva` con
-- `reintentable=false`, tenga o no un trabajo a medias. Los 21 que si tienen
-- archivo siguen respondiendo `sellado` con su documento descargable.
create or replace function private.contrato_pdf_estado_base(p_contrato_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_job private.contrato_pdf_jobs%rowtype;
  v_archivo jsonb;
  v_reintentable boolean;
  v_ledger_coherente boolean := false;
  v_integridad boolean := false;
  v_regimen_anterior boolean;
begin
  -- Se resuelve ANTES del `select into`: una asignacion no toca `found`, pero
  -- colocarla entre el SELECT y su `if not found` es pedirle explicaciones a la
  -- proxima persona que lea esto.
  v_regimen_anterior :=
    private.contrato_documental_regimen(p_contrato_id) = 'anterior';

  select * into v_job
  from private.contrato_pdf_jobs j
  where j.contrato_id = p_contrato_id
  order by j.revision desc
  limit 1;

  v_archivo := private.contrato_pdf_archivo_base(p_contrato_id);

  if not found then
    if v_archivo is not null then
      return jsonb_build_object(
        'contrato_id', p_contrato_id,
        'job_id', null,
        'estado', 'sellado',
        'storage_bucket', v_archivo->'storage_bucket',
        'storage_path', v_archivo->'storage_path',
        'nombre_archivo', v_archivo->'nombre_archivo',
        'template_version', v_archivo->'template_version',
        'intentos', 0,
        'lease_expira_en', null,
        'reintentable', false,
        'sha256', v_archivo->'sha256',
        'bytes', v_archivo->'bytes',
        'archivo', v_archivo
      );
    end if;
    return jsonb_build_object(
      'contrato_id', p_contrato_id,
      'job_id', null,
      'estado', 'sin_reserva',
      'storage_bucket', 'contratos-generados',
      'storage_path', null,
      'nombre_archivo', null,
      'template_version', null,
      'intentos', 0,
      'lease_expira_en', null,
      'reintentable', not v_regimen_anterior,
      'sha256', null,
      'bytes', null,
      'archivo', null
    );
  end if;

  -- Hay trabajo pero el contrato es del regimen anterior y no llego a archivo:
  -- ese trabajo no lo va a tomar nadie (`crm.contrato_pdf_reclamar` lo frena),
  -- asi que la pantalla no debe anunciar un documento en camino.
  if v_regimen_anterior and v_archivo is null then
    return jsonb_build_object(
      'contrato_id', p_contrato_id,
      'job_id', null,
      'estado', 'sin_reserva',
      'storage_bucket', 'contratos-generados',
      'storage_path', null,
      'nombre_archivo', null,
      'template_version', null,
      'intentos', 0,
      'lease_expira_en', null,
      'reintentable', false,
      'sha256', null,
      'bytes', null,
      'archivo', null
    );
  end if;

  if v_job.estado = 'integridad_bloqueada' then
    v_integridad := true;
  elsif v_job.estado = 'sellado' and v_archivo is null then
    v_integridad := true;
    v_job.estado := 'integridad_bloqueada';
  elsif v_archivo is not null then
    select exists (
      select 1
      from private.contrato_pdfs p
      where p.job_id = v_job.id
        and p.contrato_id = v_job.contrato_id
        and p.revision = v_job.revision
        and p.storage_bucket = v_job.storage_bucket
        and p.storage_path = v_job.storage_path
        and p.nombre_archivo = v_job.nombre_archivo
        and p.sha256 = v_job.sha256
        and p.bytes = v_job.bytes
        and p.template_version = v_job.template_version
        and p.snapshot = v_job.snapshot
        and p.generado_por = v_job.solicitado_por
    ) into v_ledger_coherente;

    if v_job.estado <> 'sellado' or not v_ledger_coherente then
      v_integridad := true;
      v_job.estado := 'integridad_bloqueada';
    end if;
  end if;

  v_reintentable := v_job.estado in ('pendiente', 'error_reintentable')
    or (
      v_job.estado in ('procesando', 'subido_verificado')
      and coalesce(v_job.lease_expira_en, '-infinity'::timestamptz) <= now()
    );
  return jsonb_build_object(
    'contrato_id', v_job.contrato_id,
    'job_id', v_job.id,
    'estado', v_job.estado,
    'storage_bucket', v_job.storage_bucket,
    'storage_path', v_job.storage_path,
    'nombre_archivo', v_job.nombre_archivo,
    'template_version', v_job.template_version,
    'intentos', v_job.intentos,
    'lease_expira_en', v_job.lease_expira_en,
    'reintentable', case
      when v_archivo is not null or v_integridad then false
      else v_reintentable
    end,
    'sha256', coalesce(v_archivo->'sha256', to_jsonb(v_job.sha256)),
    'bytes', coalesce(v_archivo->'bytes', to_jsonb(v_job.bytes)),
    'archivo', v_archivo
  ) || case
    when v_integridad then jsonb_build_object(
      'ok', false,
      'codigo', 'PDF_INTEGRIDAD_BLOQUEADA'
    )
    else '{}'::jsonb
  end;
end;
$function$;$olar_20260820190500_12$,
$olar_20260820190500_13$-- ── POSTFLIGHT 1 · la frontera existe y clasifica con datos REALES ───────────
-- Sobre una base VACIA (el oraculo local, un banco recien creado) no hay nada
-- que medir: entonces GRITA en vez de aprobar, y no aborta. Contra produccion
-- tiene que decir OK; si dice SIN DATOS, algo va mal y hay que parar. El bloque
-- 1 enseño que una sonda que pasa en verde sin nada que contar no prueba nada.
do $postflight$
declare
  v_nuevos int;
  v_anteriores int;
  v_mal int;
begin
  if to_regprocedure('private.contrato_documental_regimen(uuid)') is null then
    raise exception 'POSTFLIGHT 1: no quedo private.contrato_documental_regimen(uuid)';
  end if;

  select
    count(*) filter (where private.contrato_documental_regimen(c.id) = 'nuevo'),
    count(*) filter (where private.contrato_documental_regimen(c.id) = 'anterior'),
    count(*) filter (where private.contrato_documental_regimen(c.id) is null)
  into v_nuevos, v_anteriores, v_mal
  from public.contratos c;

  if v_mal > 0 then
    raise exception 'POSTFLIGHT 1: % contratos sin regimen (fecha_inicio nula?)', v_mal;
  end if;
  if v_nuevos + v_anteriores = 0 then
    raise warning 'POSTFLIGHT 1 SIN DATOS · no hay contratos que clasificar. '
      'Contra produccion esto NO puede salir: si aparece, PARA.';
  elsif v_anteriores = 0 then
    raise warning 'POSTFLIGHT 1 SIN DATOS · CERO contratos del regimen anterior '
      '(nuevos=%). Contra produccion es imposible: hay historial cargado. PARA.',
      v_nuevos;
  else
    raise notice 'POSTFLIGHT 1 OK · regimen nuevo=% · anterior=%', v_nuevos, v_anteriores;
  end if;
end;
$postflight$;$olar_20260820190500_13$,
$olar_20260820190500_14$-- ── POSTFLIGHT 2 · el estado dice la verdad y lo ya emitido sigue intacto ────
do $postflight$
declare
  v_antiguos int;
  v_prometidos int;
  v_ya_emitidos int;
  v_rotos int;
begin
  select count(*) into v_antiguos
  from public.contratos c
  where private.contrato_documental_regimen(c.id) = 'anterior';

  -- Ningun contrato del regimen anterior sin archivo puede seguir anunciando
  -- documento en camino ni ofrecerse como reintentable.
  select count(*) into v_prometidos
  from public.contratos c
  where private.contrato_documental_regimen(c.id) = 'anterior'
    and not exists (
      select 1 from private.contrato_pdfs p where p.contrato_id = c.id
    )
    and (
      (private.contrato_pdf_estado_base(c.id)->>'estado') <> 'sin_reserva'
      or (private.contrato_pdf_estado_base(c.id)->>'reintentable')::boolean
    );
  if v_prometidos > 0 then
    raise exception 'POSTFLIGHT 2: % contratos antiguos siguen prometiendo documento', v_prometidos;
  end if;

  -- Y los ya emitidos siguen intactos y descargables: esta migracion no borra.
  select
    count(*),
    count(*) filter (
      where (private.contrato_pdf_estado_base(c.id)->>'estado') <> 'sellado'
    )
  into v_ya_emitidos, v_rotos
  from public.contratos c
  where private.contrato_documental_regimen(c.id) = 'anterior'
    and exists (select 1 from private.contrato_pdfs p where p.contrato_id = c.id);
  if v_rotos > 0 then
    raise exception 'POSTFLIGHT 2: % documentos antiguos ya emitidos dejaron de responder sellado', v_rotos;
  end if;

  if v_antiguos = 0 then
    raise warning 'POSTFLIGHT 2 SIN DATOS · no hay contratos del regimen anterior '
      'que medir. Contra produccion esto NO puede salir: si aparece, PARA.';
  else
    raise notice 'POSTFLIGHT 2 OK · antiguos=% · de ellos ya emitidos e intactos=%',
      v_antiguos, v_ya_emitidos;
  end if;
end;
$postflight$;$olar_20260820190500_14$,
$olar_20260820190500_15$-- ── POSTFLIGHT 3 · las cuatro puertas consultan la fuente unica ──────────────
do $postflight$
declare
  v_falta text[] := '{}';
  v_fn text;
begin
  foreach v_fn in array array[
    'private.crear_job_contrato_pdf_base',
    'private.crear_revision_contrato_pdf_base',
    'private.contrato_pdf_estado_base',
    'crm.contrato_pdf_reclamar'
  ] loop
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname || '.' || p.proname = v_fn
        -- Se busca la LLAMADA cualificada, no el nombre suelto: una mencion en
        -- un comentario aprobaria la sonda sin que nadie consulte nada. Misma
        -- familia de trampa que «en LIKE el guion bajo es comodin» (14-ago).
        and strpos(p.prosrc, 'private.contrato_documental_regimen(') > 0
    ) then
      v_falta := v_falta || v_fn::text;
    end if;
  end loop;
  if cardinality(v_falta) > 0 then
    raise exception 'POSTFLIGHT 3: no consultan la fuente unica: %',
      array_to_string(v_falta, ' | ');
  end if;

  -- `search_path` vacio deja en proconfig el literal CON COMILLAS: la sonda
  -- ingenua ('search_path=' = any(proconfig)) es SIEMPRE falsa. Bloque 1, 19-ago.
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = 'contrato_documental_regimen'
      and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'POSTFLIGHT 3: contrato_documental_regimen sin search_path blindado';
  end if;
  raise notice 'POSTFLIGHT 3 OK · las cuatro puertas consultan la fuente unica';
end;
$postflight$;$olar_20260820190500_15$,
$olar_20260820190500_16$commit;$olar_20260820190500_16$
], name = coalesce(name, '20260820190500_crm_documento_regimen_por_fecha_de_firma')
 where version = '20260820190500' and statements is null;

-- 20260826151907 (crm_cartera_pagina_telefono_alternativo): 10 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260826151907_0$-- ---------------------------------------------------------------------------
-- La pagina de la cartera devuelve el SEGUNDO numero del lead
-- ---------------------------------------------------------------------------
-- QUE ARREGLA. El 24/08 entro `crm.leads.telefono_alternativo` (migracion
-- 20260824154218) y el circuito de importacion ya lo guarda: al 26/08 hay 14
-- leads con dos numeros en produccion. Pero la pantalla Cartera no puede
-- mostrarlos: la sirve `crm.cartera_pagina_fn` por cursor keyset y esa funcion
-- NUNCA devolvio la columna. El front ya estaba listo —`LeadRowSchema` la
-- declara `optional(nullable(string))` y `aLead()` la copia— asi que en el
-- navegador llegaba `undefined` y el condicional de la ficha no dibujaba nada.
-- Resultado: el 100% de los leads se veia con UN solo numero, tambien los 14
-- que si tienen dos. Es exactamente la misma familia de fallo que ya costo tres
-- rondas con `convertido_en`, un escalon mas abajo: ahi el eslabon olvidado era
-- el mapper del front, aqui es la RPC.
--
-- QUE MAS CAMBIA. El buscador de la cartera pasa a mirar tambien el segundo
-- numero cuando lo que se escribe son digitos. Un vendedor que recibe una
-- llamada del celular alternativo escribe ese numero y hoy no encuentra nada:
-- el lead existe, esta en su cartera, y el buscador le dice que no. Va en esta
-- misma migracion a proposito — devolver la columna sin poder buscarla deja la
-- mitad del problema en pie.
--
-- QUE NO CAMBIA. Ni el orden, ni el cursor, ni el ambito, ni los filtros, ni la
-- ventana de convertidos. Sigue siendo SECURITY INVOKER: es una RPC que
-- devuelve FILAS con PII y el alcance lo pone `leads_select`, no la funcion
-- (regla de la casa, 20260810141953). Es un `drop` + `create` y no un
-- `create or replace` porque Postgres no deja cambiar el tipo de retorno de una
-- funcion: por eso el grant se vuelve a poner explicitamente abajo.
-- ---------------------------------------------------------------------------

begin;$olar_20260826151907_0$,
$olar_20260826151907_1$set local lock_timeout = '10s';$olar_20260826151907_1$,
$olar_20260826151907_2$-- ---------------------------------------------------------------------------
-- 0. Preflight — que se este reemplazando lo que se leyo
-- ---------------------------------------------------------------------------
do $preflight$
begin
  -- La columna tiene que existir: sin ella el `create` de abajo falla con un
  -- error de columna inexistente, mucho mas dificil de leer que esto.
  if not exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = 'crm.leads'::regclass
      and attname = 'telefono_alternativo'
      and not attisdropped
  ) then
    raise exception 'Falta crm.leads.telefono_alternativo: aplicar antes 20260824154218.';
  end if;

  -- Ancla del cuerpo VIVO en produccion al momento de escribir esta migracion.
  -- Si alguien toco la funcion por otro lado, este `drop` se llevaria ese
  -- cambio por delante en silencio. Mejor abortar y mirar.
  if (select md5(prosrc)
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'cartera_pagina_fn')
     is distinct from 'e52ed18ecf4a109abc09ccc3cb567b4d' then
    raise exception 'crm.cartera_pagina_fn cambio desde que se escribio esta migracion: contrastar el cuerpo vivo antes de reemplazarlo.';
  end if;
end;
$preflight$;$olar_20260826151907_2$,
$olar_20260826151907_3$-- ---------------------------------------------------------------------------
-- 1. La funcion
-- ---------------------------------------------------------------------------
drop function crm.cartera_pagina_fn(
  integer, timestamptz, uuid, text, uuid, boolean, text
);$olar_20260826151907_3$,
$olar_20260826151907_4$create function crm.cartera_pagina_fn(
  p_limite       integer     default 50,
  p_antes_de     timestamptz default null,
  p_antes_id     uuid        default null,
  p_etapa        text        default null,
  p_vendedor_id  uuid        default null,
  p_sin_asignar  boolean     default false,
  p_texto        text        default null
)
returns table (
  id                    uuid,
  nombre_completo       text,
  telefono              text,
  telefono_alternativo  text,
  correo                text,
  dni                   text,
  genero                text,
  fecha_nacimiento      date,
  distrito              text,
  origen                text,
  etapa                 text,
  motivo_descarte       text,
  monto_estimado        numeric,
  moneda                text,
  categoria_interes     text,
  vendedor_id           uuid,
  asignado_supervisor_id uuid,
  creado_en             timestamptz,
  tenencia_desde        timestamptz,
  convertido_en         timestamptz,
  contrato_id           uuid,
  actualizado_en        timestamptz,
  activo                boolean,
  nota                  text,
  no_contactar          boolean,
  ultimo_contacto_en    timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_corte timestamptz := now() - interval '45 days'; -- ventana_convertidos_dias
  v_texto text;
  v_digitos text;
  v_patron_texto text;
  v_patron_digitos text;
begin
  -- Guardia de ADMISION (el ALCANCE lo pone la RLS, ver 20260810141953).
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Se resuelve UNA vez (la policy lo evalua como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));

  if p_limite is null or p_limite < 1 or p_limite > 200 then
    raise exception 'Parametro p_limite invalido' using errcode = '22023';
  end if;

  -- Cursor A MEDIAS = paginas que se saltan filas en silencio. O los dos
  -- componentes o ninguno: el desempate por id es parte del cursor, no un extra.
  if (p_antes_de is null) <> (p_antes_id is null) then
    raise exception 'Cursor incompleto: p_antes_de y p_antes_id viajan juntos'
      using errcode = '22023';
  end if;

  if p_etapa is not null and p_etapa not in (
    'nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada',
    'convertido', 'descartado'
  ) then
    raise exception 'Parametro p_etapa invalido' using errcode = '22023';
  end if;

  -- "Sin asignar" y "de este vendedor" son mutuamente excluyentes: pedir ambos
  -- solo puede ser un bug del llamante, y devolver 0 filas lo esconderia.
  if coalesce(p_sin_asignar, false) and p_vendedor_id is not null then
    raise exception 'Filtro contradictorio: p_sin_asignar con p_vendedor_id'
      using errcode = '22023';
  end if;

  v_texto := nullif(btrim(coalesce(p_texto, '')), '');
  if v_texto is not null then
    if length(v_texto) < 2 then
      raise exception 'Parametro p_texto invalido: minimo 2 caracteres'
        using errcode = '22023';
    end if;
    v_texto := left(v_texto, 80);
    v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
    -- El texto del usuario es un LITERAL, no un patron: `\`, `%` y `_` se
    -- escapan antes de envolverlo en comodines (la barra PRIMERO, o se
    -- re-escaparian las que introducen los otros dos replace). Los `ilike` de
    -- abajo declaran `escape` explicitamente en vez de confiar en el default:
    -- asi la intencion no depende de `standard_conforming_strings`.
    v_patron_texto := '%' || replace(replace(replace(v_texto, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';
    v_patron_digitos := case when length(v_digitos) >= 3 then '%' || v_digitos || '%' end;
  end if;

  return query
  select l.id,
         l.nombre_completo,
         l.telefono,
         -- EL CAMBIO DE ESTA MIGRACION. Sin esta linea la ficha del lead no
         -- puede dibujar el segundo numero aunque la base lo tenga guardado.
         l.telefono_alternativo,
         l.correo,
         l.dni,
         l.genero,
         l.fecha_nacimiento,
         l.distrito,
         l.origen,
         l.etapa,
         l.motivo_descarte,
         l.monto_estimado,
         l.moneda,
         l.categoria_interes,
         l.vendedor_id,
         l.asignado_supervisor_id,
         l.creado_en,
         l.tenencia_desde,
         l.convertido_en,
         l.contrato_id,
         l.actualizado_en,
         l.activo,
         l.nota,
         l.no_contactar,
         uc.creado_en as ultimo_contacto_en
  from crm.leads l
  -- Ultimo CONTACTO real (semaforo del kanban): los 5 tipos de TIPOS_CONTACTO,
  -- jamas cualquier fila del timeline. Mismo criterio que cola_accion_fn — que
  -- este dato viaje YA en la pagina es lo que deja a F3 sin migraciones.
  left join lateral (
    select act.creado_en
    from crm.actividades act
    where act.lead_id = l.id
      and act.tipo in ('llamada_realizada', 'llamada_no_contestada',
                       'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
    order by act.creado_en desc
    limit 1
  ) uc on true
  -- Redundante para todos los roles menos el lector global, que es justamente a
  -- quien le mezclaba filas con sus tiles (20260810151433).
  where l.activo is true
    and (l.etapa <> 'convertido' or l.convertido_en >= v_corte)
    -- Pista de ambito: REDUNDANTE con la policy. Solo puede restar filas; lo
    -- que se ve lo sigue decidiendo `leads_select`.
    and (
      v_lector
      or v_rol = 'gerencia'
      or l.vendedor_id = any(v_visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
    )
    -- Keyset. Los sentidos del orden son MIXTOS (actualizado_en desc, id asc),
    -- asi que la comparacion NO puede escribirse como tupla `(a, b) < (x, y)`:
    -- esa forma solo es correcta cuando ambas columnas ordenan igual.
    and (
      p_antes_de is null
      or l.actualizado_en < p_antes_de
      or (l.actualizado_en = p_antes_de and l.id > p_antes_id)
    )
    and (p_etapa is null or l.etapa = p_etapa)
    and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
    and (not coalesce(p_sin_asignar, false) or l.vendedor_id is null)
    and (
      v_texto is null
      or l.nombre_completo ilike v_patron_texto escape E'\\'
      or (v_patron_digitos is not null
          and (l.telefono ilike v_patron_digitos escape E'\\'
               -- Buscar por el SEGUNDO numero. Sin esto, el vendedor que recibe
               -- una llamada del alternativo escribe ese numero y el buscador le
               -- responde que el lead no existe.
               or l.telefono_alternativo ilike v_patron_digitos escape E'\\'
               or l.dni ilike v_patron_digitos escape E'\\'))
    )
  order by l.actualizado_en desc, l.id asc
  limit p_limite;
end;
$function$;$olar_20260826151907_4$,
$olar_20260826151907_5$comment on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text) is
  'Pagina keyset de la cartera (cursor actualizado_en desc, id asc). SECURITY INVOKER: el alcance lo pone la policy leads_select; la funcion solo pone la guardia de admision al CRM. Desde 20260826 devuelve telefono_alternativo y el buscador por digitos tambien lo mira.';$olar_20260826151907_5$,
$olar_20260826151907_6$revoke all on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  from public, anon, service_role;$olar_20260826151907_6$,
$olar_20260826151907_7$grant execute on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  to authenticated;$olar_20260826151907_7$,
$olar_20260826151907_8$-- ---------------------------------------------------------------------------
-- 2. Postflight — estructural
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_oid oid := 'crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)'::regprocedure;
  v_def text := pg_get_functiondef(v_oid);
begin
  -- Que la columna viaje DE VERDAD en el contrato de salida. Declararla en el
  -- `returns table` y olvidarla en el `select` es el fallo exacto que esta
  -- migracion viene a corregir, una fila mas abajo.
  if position('telefono_alternativo' in pg_get_function_result(v_oid)) = 0 then
    raise exception 'postflight: el contrato de salida no declara telefono_alternativo';
  end if;
  if position('l.telefono_alternativo,' in v_def) = 0 then
    raise exception 'postflight: la funcion declara la columna pero no la selecciona';
  end if;
  -- Que el buscador la mire.
  if position('l.telefono_alternativo ilike v_patron_digitos' in v_def) = 0 then
    raise exception 'postflight: el buscador no mira el segundo numero';
  end if;
  -- Que NO se haya convertido en DEFINER por el camino: es una RPC con filas de
  -- PII y el alcance tiene que seguir poniendolo la RLS.
  if (select prosecdef from pg_catalog.pg_proc where oid = v_oid) then
    raise exception 'postflight: cartera_pagina_fn quedo SECURITY DEFINER';
  end if;
  -- Que la guardia de admision siga ahi.
  if position('No autorizado' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio la guardia de admision';
  end if;
  -- Y que el recorte de ambito siga siendo el PREDICADO, no solo la palabra.
  -- Buscar 'vendedor_ids_visibles' a secas no sirve: el nombre sobrevive en la
  -- asignacion de v_visibles aunque el `where` se haya sustituido por un `true`.
  -- Un mutante que reemplazaba la rama del vendedor por `or true` pasaba ese
  -- control sin despeinarse. Se ancla la expresion entera.
  if position('or l.vendedor_id = any(v_visibles)' in v_def) = 0
     or position('or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))' in v_def) = 0
     or position('v_rol = ''gerencia''' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio el recorte de ambito';
  end if;
  -- La ventana de convertidos es parte del contrato de la pantalla: sin ella la
  -- cartera se llena de cerrados viejos y los tiles dejan de cuadrar con la lista.
  if position('l.etapa <> ''convertido'' or l.convertido_en >= v_corte' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio la ventana de convertidos';
  end if;
  -- Que el grant quedara donde estaba y en NADIE mas.
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'postflight: authenticated perdio el execute';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE')
     or has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'postflight: el drop+create abrio la funcion a un rol que no la tenia';
  end if;
end;
$postflight$;$olar_20260826151907_8$,
$olar_20260826151907_9$commit;$olar_20260826151907_9$
], name = coalesce(name, '20260826151907_crm_cartera_pagina_telefono_alternativo')
 where version = '20260826151907' and statements is null;

-- 20260826154500 (crm_leads_telefono_alternativo_fijos_e_internacional): 9 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260826154500_0$-- ---------------------------------------------------------------------------
-- El segundo numero del lead: fijos peruanos y numeros del mundo
-- ---------------------------------------------------------------------------
-- DECISIONES DE MIGUEL (2026-08-26):
--   · «necesito que los leads vengan con sus dos numeros si o si»
--   · «debe reconocer formatos de numero a nivel mundial»
--
-- Hasta hoy `telefono_alternativo` solo aceptaba celular peruano
-- (`+519########`), asi que el puente tiraba en el origen todo lo demas: el fijo
-- de la oficina y el celular del peruano que ahorra desde el extranjero. Los dos
-- son canales de contacto reales y el negocio los quiere.
--
-- EL FORMATO NUEVO, en dos tramos:
--   celular peruano   +51 9XXXXXXXX      (9 + ocho digitos)
--   fijo peruano      +51 XXXXXXXX       (ocho digitos nacionales, empieza 1..8)
--   resto del mundo   +CC...             (E.164: 8 a 15 digitos, primero 1..9)
--
-- El fijo peruano tiene SIEMPRE ocho digitos nacionales, se reparta como se
-- reparta entre zona y abonado: Lima es 1 + siete (1 445 7890) y las provincias
-- dos + seis (84 234567, Cusco). Escribirlo como «siete para Lima, seis para
-- provincias» deja fuera a medio pais.
--
-- ⚠️ EL `(?!51)` NO ES ADORNO. Sin el, el tramo internacional se traga cualquier
-- cosa que empiece por 51 y con largo plausible: `+51123456789` entraria como
-- «numero internacional valido» y nadie podria llamarlo jamas. Todo lo que dice
-- ser peruano se juzga con la vara peruana o no entra. Postgres soporta
-- lookahead en su sintaxis ARE; el postflight lo comprueba EJECUTANDOLO, porque
-- una asercion sobre el motor de regex que no se ejecuta no vale nada.
--
-- QUE NO CAMBIA. `telefono` —la identidad: dedup, reparto, conversion— no tiene
-- CHECK en esta tabla y no se le pone uno aqui: quien decide que entra es la
-- capa de aplicacion (telefonos.ts en el conector, validacion.ts en el front,
-- el puente en la hoja), y el trigger `private.trg_leads_normalizar_telefono` ya
-- canoniza a `+digitos`. Esta migracion toca UN campo informativo.
--
-- El CHECK se recrea con VALIDATE porque el formato nuevo es un SUPERCONJUNTO
-- del viejo: toda fila que pasaba sigue pasando.
-- ---------------------------------------------------------------------------

begin;$olar_20260826154500_0$,
$olar_20260826154500_1$set local lock_timeout = '5s';$olar_20260826154500_1$,
$olar_20260826154500_2$-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_def text;
begin
  select pg_catalog.pg_get_constraintdef(oid) into v_def
    from pg_catalog.pg_constraint
   where conrelid = 'crm.leads'::regclass
     and conname = 'leads_telefono_alternativo_formato';
  if v_def is null then
    raise exception 'Falta el CHECK leads_telefono_alternativo_formato: aplicar antes 20260824154218.';
  end if;
  -- Que se este relajando el CHECK que se leyo, y no otro que alguien cambio
  -- por el camino.
  if position('^\+519[0-9]{8}$' in v_def) = 0 then
    raise exception 'El CHECK leads_telefono_alternativo_formato ya no es el que esta migracion viene a relajar: %', v_def;
  end if;
end;
$preflight$;$olar_20260826154500_2$,
$olar_20260826154500_3$-- ---------------------------------------------------------------------------
-- 1. El formato nuevo
-- ---------------------------------------------------------------------------
alter table crm.leads
  drop constraint leads_telefono_alternativo_formato;$olar_20260826154500_3$,
$olar_20260826154500_4$alter table crm.leads
  add constraint leads_telefono_alternativo_formato
  check (
    telefono_alternativo is null
    or telefono_alternativo ~ '^\+(51(9[0-9]{8}|[1-8][0-9]{7})|(?!51)[1-9][0-9]{7,14})$'
  ) not valid;$olar_20260826154500_4$,
$olar_20260826154500_5$alter table crm.leads
  validate constraint leads_telefono_alternativo_formato;$olar_20260826154500_5$,
$olar_20260826154500_6$comment on column crm.leads.telefono_alternativo is
  'Segundo canal de contacto del lead, si es distinto del principal: celular peruano (+519########), fijo peruano (+51 + ocho digitos nacionales) o numero internacional en E.164. Es informativo: telefono sigue siendo la identidad usada por el dedup, el reparto y la conversion.';$olar_20260826154500_6$,
$olar_20260826154500_7$-- ---------------------------------------------------------------------------
-- 2. Postflight — EJECUTANDO el CHECK, no leyendolo
-- ---------------------------------------------------------------------------
-- Un CHECK se lee bien y rechaza mal: la unica prueba honesta es meterle filas.
--
-- Pero NO se le meten a `crm.leads`. Insertar ahi dispara los triggers de
-- auditoria y de negocio, y borrar despues exige bajar los siete candados
-- nombrados que protegen la tabla en produccion — una limpieza delicada para
-- probar un formato de texto. Se usa una tabla TEMPORAL creada con
-- `including constraints`: hereda el CHECK REAL recien instalado (es el mismo
-- objeto, copiado del catalogo, no una reescritura del regex), no hereda ni un
-- trigger, y desaparece al cerrar la sesion.
do $postflight$
declare
  v_probe record;
begin
  create temp table postflight_alt
    (like crm.leads including constraints including defaults)
    on commit drop;

  for v_probe in
    select * from (values
      -- Peru: lo de siempre y lo que se gana
      ('+51987654321',   true),   -- celular de siempre
      ('+5114457890',    true),   -- fijo de Lima  (1 + siete)
      ('+5184234567',    true),   -- fijo de Cusco (84 + seis)
      ('+5144123456',    true),   -- fijo de Trujillo
      -- El mundo
      ('+14155552671',   true),   -- EE. UU.
      ('+34612345678',   true),   -- España
      ('+819012345678',  true),   -- Japón
      ('+56987654321',   true),   -- Chile
      ('+39066982',      true),   -- ocho digitos: el minimo de E.164
      ('+123456789012345', true), -- quince digitos: el maximo de E.164
      -- Lo que NO puede entrar
      ('+51123456789',   false),  -- dice ser Peru y no tiene forma peruana
      ('+511234567',     false),  -- idem, mas corto
      ('+51044123456',   false),  -- fijo con el 0 de larga distancia: no canonico
      ('+5191234567',    false),  -- celular peruano corto
      ('+1234567890123456', false), -- dieciseis digitos: pasado de E.164
      ('+0123456789',    false),  -- codigo de pais que empieza en 0
      ('+3906698',       false),  -- siete digitos: por debajo de E.164
      ('987654321',      false),  -- sin `+`: en la columna se guarda canonico
      ('+51 987654321',  false),  -- con espacio
      ('+51987654321x',  false)   -- con cola: el ancla $ tiene que morder
    ) as t(valor, debe_entrar)
  loop
    begin
      insert into postflight_alt (nombre_completo, telefono, telefono_alternativo,
                                  origen, etapa, monto_estimado, moneda)
      values ('probe', '+51900000001', v_probe.valor, 'otro', 'nuevo', 1, 'PEN');
      if not v_probe.debe_entrar then
        raise exception 'postflight: el CHECK acepto un formato invalido: %', v_probe.valor;
      end if;
    exception
      when check_violation then
        if v_probe.debe_entrar then
          raise exception 'postflight: el CHECK rechazo un formato que debe entrar: %', v_probe.valor;
        end if;
    end;
  end loop;

  -- Que el null siga siendo legal: la inmensa mayoria de leads no trae segundo.
  insert into postflight_alt (nombre_completo, telefono, telefono_alternativo,
                              origen, etapa, monto_estimado, moneda)
  values ('probe', '+51900000002', null, 'otro', 'nuevo', 1, 'PEN');

  -- Y que la copia temporal se llevara DE VERDAD el CHECK. Sin esto, si
  -- `including constraints` no lo copiara, todos los casos de arriba entrarian
  -- y el postflight cantaria verde sin haber probado nada.
  if not exists (
    select 1 from pg_catalog.pg_constraint
     where conrelid = 'postflight_alt'::regclass
       and pg_catalog.pg_get_constraintdef(oid) like '%telefono_alternativo%'
  ) then
    raise exception 'postflight: la tabla de prueba no heredo el CHECK — la prueba no probo nada';
  end if;
end;
$postflight$;$olar_20260826154500_7$,
$olar_20260826154500_8$commit;$olar_20260826154500_8$
], name = coalesce(name, '20260826154500_crm_leads_telefono_alternativo_fijos_e_internacional')
 where version = '20260826154500' and statements is null;

-- 20260826173523 (crm_leads_telefono_alternativo_crudo): 11 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260826173523_0$-- ---------------------------------------------------------------------------
-- El segundo numero que NO se pudo leer tampoco se tira
-- ---------------------------------------------------------------------------
-- DECISION DE MIGUEL (2026-08-26): «que siempre todos los leads tengan ese
-- numero alternativo, asi ese numero sea errado».
--
-- No se puede cumplir al pie de la letra —el diagnostico del origen midio que el
-- 84,2 % de las personas escribe el MISMO numero en las dos columnas, asi que en
-- esas filas no hay un segundo numero que dar— pero si se puede cumplir lo que
-- hay detras del pedido: que NADA de lo que la persona escribio se pierda en
-- silencio, y que el vendedor nunca se quede con la duda de si el CRM se comio un
-- dato o si nunca lo hubo.
--
-- Son 299 filas de 14.310 (2,1 %) las que hoy traen algo escrito en la columna
-- del segundo numero que no es un telefono reconocible: un numero a medias, con
-- un digito de mas, con una anotacion pegada. Hasta hoy se tiraban.
--
-- QUE HACE. Una columna SIN reglas de formato que guarda ese texto tal como
-- llego. La columna canonica (`telefono_alternativo`) sigue limpia, que es lo
-- que hace que los enlaces de llamar y de WhatsApp funcionen; esta otra es para
-- que un humano la lea y la corrija.
--
-- LAS DOS SON EXCLUYENTES, y hay un CHECK que lo obliga: si el numero se pudo
-- entender vive en la canonica y esta queda en null. Sin esa regla, la ficha
-- tendria que decidir cual de las dos pinta y acabaria mostrando dos «segundos
-- numeros» distintos para el mismo lead.
--
-- El tope de 40 caracteres es un guardia de cordura, no una validacion: cabe
-- cualquier cosa que alguien escriba en una casilla de telefono, y evita que un
-- parrafo entero entre por aqui.
-- ---------------------------------------------------------------------------

begin;$olar_20260826173523_0$,
$olar_20260826173523_1$set local lock_timeout = '5s';$olar_20260826173523_1$,
$olar_20260826173523_2$-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'crm.leads'::regclass
       and attname = 'telefono_alternativo'
       and not attisdropped
  ) then
    raise exception 'Falta crm.leads.telefono_alternativo: aplicar antes 20260824154218.';
  end if;
  if exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'crm.leads'::regclass
       and attname = 'telefono_alternativo_crudo'
       and not attisdropped
  ) then
    raise exception 'crm.leads.telefono_alternativo_crudo ya existe: esta migracion ya se aplico.';
  end if;
end;
$preflight$;$olar_20260826173523_2$,
$olar_20260826173523_3$-- ---------------------------------------------------------------------------
-- 1. La columna
-- ---------------------------------------------------------------------------
alter table crm.leads
  add column telefono_alternativo_crudo text;$olar_20260826173523_3$,
$olar_20260826173523_4$alter table crm.leads
  add constraint leads_telefono_alternativo_crudo_cordura
  check (
    telefono_alternativo_crudo is null
    or (
      -- Ni vacio ni solo espacios: «no hay dato» se escribe NULL, no ''. Dos
      -- formas de decir lo mismo obligan a la ficha a comprobar las dos, y
      -- tarde o temprano una se olvida.
      btrim(telefono_alternativo_crudo) <> ''
      and length(telefono_alternativo_crudo) <= 40
    )
  ) not valid;$olar_20260826173523_4$,
$olar_20260826173523_5$alter table crm.leads
  add constraint leads_telefono_alternativo_excluyentes
  check (
    telefono_alternativo is null or telefono_alternativo_crudo is null
  ) not valid;$olar_20260826173523_5$,
$olar_20260826173523_6$alter table crm.leads validate constraint leads_telefono_alternativo_crudo_cordura;$olar_20260826173523_6$,
$olar_20260826173523_7$alter table crm.leads validate constraint leads_telefono_alternativo_excluyentes;$olar_20260826173523_7$,
$olar_20260826173523_8$comment on column crm.leads.telefono_alternativo_crudo is
  'El segundo numero TAL COMO LO ESCRIBIO la persona, cuando no se pudo entender como telefono. Existe para que nada se pierda en silencio (decision de Miguel 2026-08-26). Excluyente con telefono_alternativo: si el numero se pudo canonizar vive alli y este queda null. No es marcable — la ficha lo muestra como «sin validar» para que un humano lo lea y lo corrija.';$olar_20260826173523_8$,
$olar_20260826173523_9$-- ---------------------------------------------------------------------------
-- 2. Postflight — EJECUTANDO los CHECK sobre una copia temporal
-- ---------------------------------------------------------------------------
-- Misma tecnica que 20260826154500: tabla TEMPORAL con `including constraints`,
-- que hereda los CHECK reales del catalogo y ningun trigger. Insertar en
-- `crm.leads` dispararia la auditoria y borrar despues exige bajar los siete
-- candados nombrados que protegen la tabla en produccion.
do $postflight$
declare
  v_probe record;
begin
  create temp table postflight_crudo
    (like crm.leads including constraints including defaults)
    on commit drop;

  for v_probe in
    select * from (values
      -- (canonico, crudo, debe_entrar)
      (null,            '99988 7',      true),   -- el caso que esta migracion viene a salvar
      (null,            '912-34',       true),
      (null,            'llamar al 9 8', true),  -- con anotacion pegada
      ('+51987654321',  null,           true),   -- se entendio: vive en la canonica
      (null,            null,           true),   -- el origen no dio nada
      ('+51987654321',  '99988 7',      false),  -- LAS DOS: ambiguo, prohibido
      (null,            '',             false),  -- vacio: «no hay dato» se escribe NULL
      (null,            '   ',          false),  -- solo espacios: lo mismo
      (null, repeat('9', 41),           false)   -- pasado del tope de cordura
    ) as t(canonico, crudo, debe_entrar)
  loop
    begin
      insert into postflight_crudo (nombre_completo, telefono, telefono_alternativo,
                                    telefono_alternativo_crudo,
                                    origen, etapa, monto_estimado, moneda)
      values ('probe', '+51900000001', v_probe.canonico, v_probe.crudo,
              'otro', 'nuevo', 1, 'PEN');
      if not v_probe.debe_entrar then
        raise exception 'postflight: se acepto una combinacion invalida: canonico=% crudo=%',
          coalesce(v_probe.canonico, 'NULL'), coalesce(v_probe.crudo, 'NULL');
      end if;
    exception
      when check_violation then
        if v_probe.debe_entrar then
          raise exception 'postflight: se rechazo una combinacion que debe entrar: canonico=% crudo=%',
            coalesce(v_probe.canonico, 'NULL'), coalesce(v_probe.crudo, 'NULL');
        end if;
    end;
  end loop;

  -- Que la copia temporal se llevara los DOS CHECK nuevos. Sin esto, si
  -- `including constraints` fallara, todos los casos entrarian y el postflight
  -- cantaria verde sin haber probado nada.
  if (select count(*) from pg_catalog.pg_constraint
       where conrelid = 'postflight_crudo'::regclass
         and pg_catalog.pg_get_constraintdef(oid) like '%telefono_alternativo_crudo%') < 2 then
    raise exception 'postflight: la tabla de prueba no heredo los CHECK — la prueba no probo nada';
  end if;
end;
$postflight$;$olar_20260826173523_9$,
$olar_20260826173523_10$commit;$olar_20260826173523_10$
], name = coalesce(name, '20260826173523_crm_leads_telefono_alternativo_crudo')
 where version = '20260826173523' and statements is null;

-- 20260826174500 (crm_cartera_pagina_telefono_alternativo_crudo): 10 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260826174500_0$-- ---------------------------------------------------------------------------
-- La pagina de la cartera devuelve tambien el segundo numero SIN VALIDAR
-- ---------------------------------------------------------------------------
-- Continuacion de 20260826151907 y de 20260826173523: la columna
-- `telefono_alternativo_crudo` ya existe en la tabla y el front ya la pide en
-- `COLUMNAS_LEAD`, pero la RPC de la cartera no la devolvia. La ficha del lead
-- se sirve del store (`listarLeadsDelAmbito`, que consulta la tabla directo), asi
-- que funcionaria igual sin esto — y precisamente por eso hay que hacerlo: dos
-- caminos que producen un `Lead` con forma distinta es como se pierde un dato en
-- silencio, que es la leccion entera de este ciclo.
--
-- Mismo `drop` + `create` que 20260826151907 (Postgres no deja cambiar el tipo de
-- retorno), mismo preflight anclado al md5 del cuerpo VIVO, mismos postflights.
-- El cuerpo es el de esa migracion con dos lineas mas.
-- ---------------------------------------------------------------------------

begin;$olar_20260826174500_0$,
$olar_20260826174500_1$set local lock_timeout = '10s';$olar_20260826174500_1$,
$olar_20260826174500_2$do $preflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = 'crm.leads'::regclass
      and attname = 'telefono_alternativo_crudo'
      and not attisdropped
  ) then
    raise exception 'Falta crm.leads.telefono_alternativo_crudo: aplicar antes 20260826173523.';
  end if;

  if (select md5(prosrc)
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'cartera_pagina_fn')
     is distinct from '6ce36d259520b58ea5f47574a8dd8960' then
    raise exception 'crm.cartera_pagina_fn cambio desde que se escribio esta migracion: contrastar el cuerpo vivo antes de reemplazarlo.';
  end if;
end;
$preflight$;$olar_20260826174500_2$,
$olar_20260826174500_3$drop function crm.cartera_pagina_fn(
  integer, timestamptz, uuid, text, uuid, boolean, text
);$olar_20260826174500_3$,
$olar_20260826174500_4$create function crm.cartera_pagina_fn(
  p_limite       integer     default 50,
  p_antes_de     timestamptz default null,
  p_antes_id     uuid        default null,
  p_etapa        text        default null,
  p_vendedor_id  uuid        default null,
  p_sin_asignar  boolean     default false,
  p_texto        text        default null
)
returns table (
  id                    uuid,
  nombre_completo       text,
  telefono              text,
  telefono_alternativo  text,
  telefono_alternativo_crudo text,
  correo                text,
  dni                   text,
  genero                text,
  fecha_nacimiento      date,
  distrito              text,
  origen                text,
  etapa                 text,
  motivo_descarte       text,
  monto_estimado        numeric,
  moneda                text,
  categoria_interes     text,
  vendedor_id           uuid,
  asignado_supervisor_id uuid,
  creado_en             timestamptz,
  tenencia_desde        timestamptz,
  convertido_en         timestamptz,
  contrato_id           uuid,
  actualizado_en        timestamptz,
  activo                boolean,
  nota                  text,
  no_contactar          boolean,
  ultimo_contacto_en    timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_corte timestamptz := now() - interval '45 days'; -- ventana_convertidos_dias
  v_texto text;
  v_digitos text;
  v_patron_texto text;
  v_patron_digitos text;
begin
  -- Guardia de ADMISION (el ALCANCE lo pone la RLS, ver 20260810141953).
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Se resuelve UNA vez (la policy lo evalua como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));

  if p_limite is null or p_limite < 1 or p_limite > 200 then
    raise exception 'Parametro p_limite invalido' using errcode = '22023';
  end if;

  -- Cursor A MEDIAS = paginas que se saltan filas en silencio. O los dos
  -- componentes o ninguno: el desempate por id es parte del cursor, no un extra.
  if (p_antes_de is null) <> (p_antes_id is null) then
    raise exception 'Cursor incompleto: p_antes_de y p_antes_id viajan juntos'
      using errcode = '22023';
  end if;

  if p_etapa is not null and p_etapa not in (
    'nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada',
    'convertido', 'descartado'
  ) then
    raise exception 'Parametro p_etapa invalido' using errcode = '22023';
  end if;

  -- "Sin asignar" y "de este vendedor" son mutuamente excluyentes: pedir ambos
  -- solo puede ser un bug del llamante, y devolver 0 filas lo esconderia.
  if coalesce(p_sin_asignar, false) and p_vendedor_id is not null then
    raise exception 'Filtro contradictorio: p_sin_asignar con p_vendedor_id'
      using errcode = '22023';
  end if;

  v_texto := nullif(btrim(coalesce(p_texto, '')), '');
  if v_texto is not null then
    if length(v_texto) < 2 then
      raise exception 'Parametro p_texto invalido: minimo 2 caracteres'
        using errcode = '22023';
    end if;
    v_texto := left(v_texto, 80);
    v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
    -- El texto del usuario es un LITERAL, no un patron: `\`, `%` y `_` se
    -- escapan antes de envolverlo en comodines (la barra PRIMERO, o se
    -- re-escaparian las que introducen los otros dos replace). Los `ilike` de
    -- abajo declaran `escape` explicitamente en vez de confiar en el default:
    -- asi la intencion no depende de `standard_conforming_strings`.
    v_patron_texto := '%' || replace(replace(replace(v_texto, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';
    v_patron_digitos := case when length(v_digitos) >= 3 then '%' || v_digitos || '%' end;
  end if;

  return query
  select l.id,
         l.nombre_completo,
         l.telefono,
         -- EL CAMBIO DE ESTA MIGRACION. Sin esta linea la ficha del lead no
         -- puede dibujar el segundo numero aunque la base lo tenga guardado.
         l.telefono_alternativo,
         -- EL CAMBIO DE ESTA MIGRACION. La ficha se sirve del store, no de esta
         -- pagina, asi que tecnicamente podria vivir sin la columna — pero
         -- entonces `Lead` tendria DOS formas segun de donde venga la fila, y esa
         -- divergencia es exactamente como se pierde un dato sin que nadie lo vea.
         l.telefono_alternativo_crudo,
         l.correo,
         l.dni,
         l.genero,
         l.fecha_nacimiento,
         l.distrito,
         l.origen,
         l.etapa,
         l.motivo_descarte,
         l.monto_estimado,
         l.moneda,
         l.categoria_interes,
         l.vendedor_id,
         l.asignado_supervisor_id,
         l.creado_en,
         l.tenencia_desde,
         l.convertido_en,
         l.contrato_id,
         l.actualizado_en,
         l.activo,
         l.nota,
         l.no_contactar,
         uc.creado_en as ultimo_contacto_en
  from crm.leads l
  -- Ultimo CONTACTO real (semaforo del kanban): los 5 tipos de TIPOS_CONTACTO,
  -- jamas cualquier fila del timeline. Mismo criterio que cola_accion_fn — que
  -- este dato viaje YA en la pagina es lo que deja a F3 sin migraciones.
  left join lateral (
    select act.creado_en
    from crm.actividades act
    where act.lead_id = l.id
      and act.tipo in ('llamada_realizada', 'llamada_no_contestada',
                       'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
    order by act.creado_en desc
    limit 1
  ) uc on true
  -- Redundante para todos los roles menos el lector global, que es justamente a
  -- quien le mezclaba filas con sus tiles (20260810151433).
  where l.activo is true
    and (l.etapa <> 'convertido' or l.convertido_en >= v_corte)
    -- Pista de ambito: REDUNDANTE con la policy. Solo puede restar filas; lo
    -- que se ve lo sigue decidiendo `leads_select`.
    and (
      v_lector
      or v_rol = 'gerencia'
      or l.vendedor_id = any(v_visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
    )
    -- Keyset. Los sentidos del orden son MIXTOS (actualizado_en desc, id asc),
    -- asi que la comparacion NO puede escribirse como tupla `(a, b) < (x, y)`:
    -- esa forma solo es correcta cuando ambas columnas ordenan igual.
    and (
      p_antes_de is null
      or l.actualizado_en < p_antes_de
      or (l.actualizado_en = p_antes_de and l.id > p_antes_id)
    )
    and (p_etapa is null or l.etapa = p_etapa)
    and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
    and (not coalesce(p_sin_asignar, false) or l.vendedor_id is null)
    and (
      v_texto is null
      or l.nombre_completo ilike v_patron_texto escape E'\\'
      or (v_patron_digitos is not null
          and (l.telefono ilike v_patron_digitos escape E'\\'
               -- Buscar por el SEGUNDO numero. Sin esto, el vendedor que recibe
               -- una llamada del alternativo escribe ese numero y el buscador le
               -- responde que el lead no existe.
               or l.telefono_alternativo ilike v_patron_digitos escape E'\\'
               or l.dni ilike v_patron_digitos escape E'\\'))
    )
  order by l.actualizado_en desc, l.id asc
  limit p_limite;
end;
$function$;$olar_20260826174500_4$,
$olar_20260826174500_5$comment on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text) is
  'Pagina keyset de la cartera (cursor actualizado_en desc, id asc). SECURITY INVOKER: el alcance lo pone la policy leads_select; la funcion solo pone la guardia de admision al CRM. Desde 20260826 devuelve telefono_alternativo y el buscador por digitos tambien lo mira.';$olar_20260826174500_5$,
$olar_20260826174500_6$revoke all on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  from public, anon, service_role;$olar_20260826174500_6$,
$olar_20260826174500_7$grant execute on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  to authenticated;$olar_20260826174500_7$,
$olar_20260826174500_8$-- ---------------------------------------------------------------------------
-- 2. Postflight — estructural
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_oid oid := 'crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)'::regprocedure;
  v_def text := pg_get_functiondef(v_oid);
begin
  -- Que la columna viaje DE VERDAD en el contrato de salida. Declararla en el
  -- `returns table` y olvidarla en el `select` es el fallo exacto que esta
  -- migracion viene a corregir, una fila mas abajo.
  if position('telefono_alternativo' in pg_get_function_result(v_oid)) = 0 then
    raise exception 'postflight: el contrato de salida no declara telefono_alternativo';
  end if;
  if position('l.telefono_alternativo,' in v_def) = 0 then
    raise exception 'postflight: la funcion declara la columna pero no la selecciona';
  end if;
  -- Y la columna nueva, con el mismo rasero: declararla en el `returns table` y
  -- olvidarla en el `select` es el fallo que ya se corrigio una vez aqui mismo.
  if position('telefono_alternativo_crudo' in pg_get_function_result(v_oid)) = 0 then
    raise exception 'postflight: el contrato de salida no declara telefono_alternativo_crudo';
  end if;
  if position('l.telefono_alternativo_crudo,' in v_def) = 0 then
    raise exception 'postflight: declara el crudo pero no lo selecciona';
  end if;
  -- Que el buscador la mire.
  if position('l.telefono_alternativo ilike v_patron_digitos' in v_def) = 0 then
    raise exception 'postflight: el buscador no mira el segundo numero';
  end if;
  -- Que NO se haya convertido en DEFINER por el camino: es una RPC con filas de
  -- PII y el alcance tiene que seguir poniendolo la RLS.
  if (select prosecdef from pg_catalog.pg_proc where oid = v_oid) then
    raise exception 'postflight: cartera_pagina_fn quedo SECURITY DEFINER';
  end if;
  -- Que la guardia de admision siga ahi.
  if position('No autorizado' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio la guardia de admision';
  end if;
  -- Y que el recorte de ambito siga siendo el PREDICADO, no solo la palabra.
  -- Buscar 'vendedor_ids_visibles' a secas no sirve: el nombre sobrevive en la
  -- asignacion de v_visibles aunque el `where` se haya sustituido por un `true`.
  -- Un mutante que reemplazaba la rama del vendedor por `or true` pasaba ese
  -- control sin despeinarse. Se ancla la expresion entera.
  if position('or l.vendedor_id = any(v_visibles)' in v_def) = 0
     or position('or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))' in v_def) = 0
     or position('v_rol = ''gerencia''' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio el recorte de ambito';
  end if;
  -- La ventana de convertidos es parte del contrato de la pantalla: sin ella la
  -- cartera se llena de cerrados viejos y los tiles dejan de cuadrar con la lista.
  if position('l.etapa <> ''convertido'' or l.convertido_en >= v_corte' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio la ventana de convertidos';
  end if;
  -- Que el grant quedara donde estaba y en NADIE mas.
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'postflight: authenticated perdio el execute';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE')
     or has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'postflight: el drop+create abrio la funcion a un rol que no la tenia';
  end if;
end;
$postflight$;$olar_20260826174500_8$,
$olar_20260826174500_9$commit;$olar_20260826174500_9$
], name = coalesce(name, '20260826174500_crm_cartera_pagina_telefono_alternativo_crudo')
 where version = '20260826174500' and statements is null;

-- 20260826182000 (crm_canonizar_contacto): 7 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260826182000_0$-- ---------------------------------------------------------------------------
-- `private.canonizar_contacto` — la regla del telefono, en SQL
-- ---------------------------------------------------------------------------
-- Es el SEXTO espejo de la misma regla, y el primero que vive en la base como
-- funcion (los otros: telefonos.ts del conector, validacion.ts del front,
-- reconocerTelefono() del puente, el CHECK leads_telefono_alternativo_formato y
-- el regex del alta manual). Se crea aparte, con nombre propio y probada, para
-- que la 20260826182500 pueda LLAMARLA en vez de re-escribir el criterio dentro
-- de una funcion de 200 lineas — que es como los espejos empiezan a divergir.
--
-- QUE NO ES. NO sustituye a `private.normalizar_telefono`, que sigue intacta y
-- la sigue usando el trigger de `crm.leads` y todo el resto del CRM. Aquella
-- responde «como se guarda este numero»; esta responde «es esto un telefono, y
-- de que tipo». Tocar la otra moveria la huella con la que el CRM decide que dos
-- leads son el mismo — dedup, reparto y conversion — y esa es exactamente la
-- razon por la que Miguel eligio la opcion A (2026-08-26).
--
-- DEVUELVE (canonico, clase, movil) o NULL si no hay telefono que rescatar:
--   celular_pe      +51 9XXXXXXXX
--   fijo_pe         +51 XXXXXXXX   (ocho digitos nacionales, y SOLO si viene
--                                   MARCADO: con +51/0051 o con el 0 de larga
--                                   distancia — ocho digitos pelados son un DNI)
--   internacional   +CC…           (E.164: 8 a 15 digitos, el primero 1-9)
-- ---------------------------------------------------------------------------

begin;$olar_20260826182000_0$,
$olar_20260826182000_1$set local lock_timeout = '5s';$olar_20260826182000_1$,
$olar_20260826182000_2$create or replace function private.canonizar_contacto(p text)
returns table (e164 text, clase text, movil boolean)
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_bruto text := pg_catalog.btrim(coalesce(p, ''));
  v_digitos text;
  v_internacional boolean;
  v_sin_salida text;
  v_nacional text;
  v_declara_peru boolean;
  v_n text;
  v_sin_cero text;
begin
  if v_bruto = '' then return; end if;
  -- Un correo metido en la casilla del telefono es otro dato en el sitio
  -- equivocado, no un numero roto.
  if pg_catalog.strpos(v_bruto, '@') > 0 then return; end if;

  v_digitos := pg_catalog.regexp_replace(v_bruto, '[^0-9]', '', 'g');
  if v_digitos = '' then return; end if;

  v_internacional := pg_catalog.left(v_bruto, 1) = '+'
                     or pg_catalog.left(v_digitos, 2) = '00';
  v_sin_salida := pg_catalog.regexp_replace(v_digitos, '^00', '');

  v_nacional := case when pg_catalog.left(v_sin_salida, 2) = '51'
                     then pg_catalog.substr(v_sin_salida, 3)
                     else v_sin_salida end;
  -- Todo lo que dice ser peruano se juzga con la vara peruana: si no tiene la
  -- forma exacta NO se cuela por la puerta internacional. Sin esto,
  -- '+51123456789' entraria como numero valido y nadie podria llamarlo nunca.
  v_declara_peru := pg_catalog.left(v_sin_salida, 2) = '51'
                    and pg_catalog.length(v_nacional) >= 8;

  if v_declara_peru or not v_internacional then
    v_n := case when v_declara_peru then v_nacional else v_sin_salida end;

    if v_n ~ '^9[0-9]{8}$' then
      return query select '+51' || v_n, 'celular_pe'::text, true;
      return;
    end if;

    -- ⚠️ UN FIJO EXIGE MARCA. El nacional de un fijo peruano tiene ocho digitos
    -- (Lima 1+siete, provincias 84+seis)… y el DNI peruano TAMBIEN tiene ocho.
    -- Aceptar ocho digitos pelados convertiria todo DNI en un telefono.
    v_sin_cero := case when pg_catalog.left(v_n, 1) = '0'
                       then pg_catalog.substr(v_n, 2) else v_n end;
    if (v_declara_peru or pg_catalog.left(v_n, 1) = '0')
       and v_sin_cero ~ '^[1-8][0-9]{7}$' then
      return query select '+51' || v_sin_cero, 'fijo_pe'::text, false;
      return;
    end if;

    -- Dijo ser peruano y no lo es: se acaba aqui. Y sin `+` no hay pais que
    -- suponer: no se inventa uno.
    if v_declara_peru or not v_internacional then return; end if;
  end if;

  -- E.164 puro. No se valida el codigo de pais contra una lista: mantenerla al
  -- dia en seis capas es peor deuda que aceptar un numero raro.
  if pg_catalog.length(v_sin_salida) between 8 and 15
     and v_sin_salida ~ '^[1-9][0-9]*$' then
    -- Movil o fijo es indecidible fuera de Peru sin libphonenumber. Se asume
    -- MOVIL: esconder el unico canal que hay seria peor que ofrecer uno que
    -- quiza no conteste.
    return query select '+' || v_sin_salida, 'internacional'::text, true;
  end if;
  return;
end;
$function$;$olar_20260826182000_2$,
$olar_20260826182000_3$comment on function private.canonizar_contacto(text) is
  'La regla del telefono del CRM, en SQL: devuelve (e164, clase, movil) o ninguna fila. Espejo de telefonos.ts del conector, validacion.ts del front y reconocerTelefono() del puente. NO sustituye a private.normalizar_telefono, que sigue decidiendo como se GUARDA el telefono principal y con la que el CRM deduplica.';$olar_20260826182000_3$,
$olar_20260826182000_4$revoke all on function private.canonizar_contacto(text) from public, anon, authenticated, service_role;$olar_20260826182000_4$,
$olar_20260826182000_5$-- ---------------------------------------------------------------------------
-- Postflight — EJECUTANDO la funcion, no leyendola
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_caso record;
  v_res record;
  v_e164 text;
begin
  for v_caso in
    select * from (values
      -- Peru
      ('987654321',      '+51987654321'),
      ('+51 999-888-777','+51999888777'),
      ('964,262,777',    '+51964262777'),   -- Sheets lo trato como numero
      ('p:+51910585900', '+51910585900'),   -- fila real del origen
      ('014457890',      '+5114457890'),    -- fijo de Lima con el 0
      ('084 234567',     '+5184234567'),    -- fijo de Cusco
      ('+51 1 445 7890', '+5114457890'),
      -- El mundo
      ('+1 415 555 2671','+14155552671'),
      ('0034612345678',  '+34612345678'),
      -- Lo que NO es telefono
      ('',               null),
      ('   ',            null),
      ('rosa@correo.com',null),
      ('5ooooo',         null),
      ('14457890',       null),   -- ocho digitos pelados = DNI, no telefono
      ('46736918',       null),   -- un DNI no puede parecer un telefono
      ('+51123456789',   null),   -- dice ser Peru sin forma peruana
      ('9158903210',     null),   -- diez digitos: celular peruano malo
      ('4155552671',     null),   -- sin `+` no hay pais que suponer
      -- ⚠️ Los limites de E.164 hay que probarlos CON `+`. Un numero largo sin
      -- `+` se rechaza por «no hay pais que suponer», no por el tope — un
      -- mutante que ensanchaba el rango a 6..20 pasaba con el caso anterior sin
      -- despeinarse, porque nunca llegaba a esa rama.
      ('+39066982',      '+39066982'),   -- ocho digitos: el MINIMO, entra
      ('+123456789012345', '+123456789012345'), -- quince: el MAXIMO, entra
      ('+3906698',       null),   -- siete: por debajo del minimo
      ('+1234567890123456', null),-- dieciseis: pasado del maximo
      ('+0123456789',    null)    -- codigo de pais que empieza en 0
    ) as t(entrada, esperado)
  loop
    v_e164 := null;
    for v_res in select * from private.canonizar_contacto(v_caso.entrada) loop
      v_e164 := v_res.e164;
    end loop;
    if v_e164 is distinct from v_caso.esperado then
      raise exception 'postflight: canonizar_contacto(%) dio % y se esperaba %',
        coalesce(v_caso.entrada, 'NULL'), coalesce(v_e164, 'NULL'),
        coalesce(v_caso.esperado, 'NULL');
    end if;
  end loop;

  -- Y que la CLASE distinga lo que responde WhatsApp de lo que no: de eso
  -- depende que la ficha no ofrezca un boton que escribe al vacio.
  select * into v_res from private.canonizar_contacto('987654321');
  if v_res.clase <> 'celular_pe' or not v_res.movil then
    raise exception 'postflight: un celular peruano no se reconoce como movil';
  end if;
  select * into v_res from private.canonizar_contacto('014457890');
  if v_res.clase <> 'fijo_pe' or v_res.movil then
    raise exception 'postflight: un fijo se esta marcando como movil';
  end if;
  select * into v_res from private.canonizar_contacto('+34612345678');
  if v_res.clase <> 'internacional' or not v_res.movil then
    raise exception 'postflight: un internacional no se reconoce';
  end if;

  -- Que lo que sale de aqui SIEMPRE quepa en la columna. Si un dia divergieran,
  -- el alta reventaria en el insert con un error de constraint ilegible.
  for v_caso in select * from (values
      ('987654321'), ('014457890'), ('+34612345678'), ('+14155552671')
    ) as t(entrada)
  loop
    select * into v_res from private.canonizar_contacto(v_caso.entrada);
    if v_res.e164 !~ '^\+(51(9[0-9]{8}|[1-8][0-9]{7})|(?!51)[1-9][0-9]{7,14})$' then
      raise exception 'postflight: canonizar_contacto(%) devuelve % , que el CHECK de telefono_alternativo rechaza',
        v_caso.entrada, v_res.e164;
    end if;
  end loop;
end;
$postflight$;$olar_20260826182000_5$,
$olar_20260826182000_6$commit;$olar_20260826182000_6$
], name = coalesce(name, '20260826182000_crm_canonizar_contacto')
 where version = '20260826182000' and statements is null;

-- 20260826182500 (crm_crear_lead_telefono_alternativo): 10 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260826182500_0$-- ---------------------------------------------------------------------------
-- El alta manual de un lead admite su SEGUNDO numero
-- ---------------------------------------------------------------------------
-- OPCION A, elegida por Miguel (2026-08-26): el primer numero IDENTIFICA al
-- lead y por eso sigue siendo celular peruano; el segundo es solo una forma de
-- contactarlo y admite lo que sea — otro celular, un fijo peruano o un numero
-- de cualquier pais.
--
-- POR QUE EL PRINCIPAL NO SE TOCA. `private.normalizar_telefono` es la pieza con
-- la que TODO el CRM decide que dos leads son el mismo: dedup, reparto y
-- conversion cuelgan de ella. Ensancharla movería esa huella hacia atras, sobre
-- 544 leads vivos. La opcion B queda escrita en el vault para cuando haya un
-- caso real que la justifique, no por si acaso.
--
-- QUE CAMBIA. Un parametro nuevo, `p_telefono_alternativo`, al final y con
-- DEFAULT NULL (asi ninguna llamada existente se rompe). Se canoniza con
-- `private.canonizar_contacto` — la MISMA regla del conector, del front y del
-- puente, en vez de un regex reescrito aqui dentro, que es como los espejos
-- empiezan a divergir.
--
-- Es `drop` + `create` y no `create or replace`: añadir un parametro crea una
-- SOBRECARGA, no un reemplazo, y dos funciones con el mismo nombre harian
-- ambigua cada llamada. Por eso el grant se vuelve a poner explicitamente.
--
-- ASIMETRIA CONSCIENTE, dicha para que nadie la descubra por accidente: por la
-- via automatica (hoja → conector) un lead SI puede entrar con un fijo de
-- identidad, porque alli la alternativa era perder el lead entero. Tecleando a
-- mano se exige celular. Un cliente de oficina que solo deje un fijo no se
-- podra registrar; se decidio asumirlo (Miguel, 2026-08-26).
-- ---------------------------------------------------------------------------

begin;$olar_20260826182500_0$,
$olar_20260826182500_1$set local lock_timeout = '10s';$olar_20260826182500_1$,
$olar_20260826182500_2$do $preflight$
begin
  if to_regprocedure('private.canonizar_contacto(text)') is null then
    raise exception 'Falta private.canonizar_contacto: aplicar antes 20260826182000.';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'crm.leads'::regclass
       and attname = 'telefono_alternativo' and not attisdropped
  ) then
    raise exception 'Falta crm.leads.telefono_alternativo: aplicar antes 20260824154218.';
  end if;
  -- Ancla del cuerpo VIVO: si alguien toco la funcion por otro lado, este `drop`
  -- se llevaria ese cambio por delante en silencio.
  if (select md5(prosrc) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'crear_lead_si_disponible')
     is distinct from '3c06a68dd2c9a1a7ead67cf5019c1aa8' then
    raise exception 'crm.crear_lead_si_disponible cambio desde que se escribio esta migracion: contrastar el cuerpo vivo antes de reemplazarlo.';
  end if;
end;
$preflight$;$olar_20260826182500_2$,
$olar_20260826182500_3$drop function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text
);$olar_20260826182500_3$,
$olar_20260826182500_4$create function crm.crear_lead_si_disponible(
  p_nombre_completo text,
  p_telefono text,
  p_origen text,
  p_monto_estimado numeric,
  p_moneda text,
  p_id uuid default null,
  p_correo text default null,
  p_dni text default null,
  p_genero text default null,
  p_fecha_nacimiento date default null,
  p_distrito text default null,
  p_etapa text default 'nuevo',
  p_categoria_interes text default null,
  p_vendedor_id uuid default null,
  p_nota text default null,
  p_telefono_alternativo text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_rol_actual text;
  v_id uuid := coalesce(p_id, pg_catalog.gen_random_uuid());
  v_nombre text := nullif(pg_catalog.btrim(p_nombre_completo), '');
  v_telefono text := private.normalizar_telefono(p_telefono);
  v_alt_bruto text := nullif(pg_catalog.btrim(p_telefono_alternativo), '');
  v_alt text;
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_correo text := nullif(pg_catalog.btrim(p_correo), '');
  v_genero text := nullif(pg_catalog.btrim(p_genero), '');
  v_distrito text := nullif(pg_catalog.btrim(p_distrito), '');
  v_categoria text := nullif(pg_catalog.btrim(p_categoria_interes), '');
  v_nota text := nullif(pg_catalog.btrim(p_nota), '');
  v_vendedor uuid := p_vendedor_id;
  v_supervisor uuid;
  v_disponibilidad jsonb;
  v_existente crm.leads%rowtype;
  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
begin
  v_rol := private.rol_crm(v_actor);
  if v_actor is null or v_rol is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_nombre is null then
    raise exception using errcode = '22023', message = 'El nombre es obligatorio';
  end if;
  if v_telefono is null or v_telefono !~ '^\+519[0-9]{8}$' then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  -- EL SEGUNDO NUMERO (opcion A). Admite celular, fijo peruano o cualquier pais,
  -- via la MISMA regla que el conector y el front. No participa del dedup: la
  -- identidad del lead sigue siendo `telefono`.
  if v_alt_bruto is not null then
    select c.e164 into v_alt from private.canonizar_contacto(v_alt_bruto) c;
    if v_alt is null then
      raise exception using
        errcode = '22023',
        message = 'Segundo telefono invalido: celular peruano, fijo peruano (014457890) o internacional con +codigo de pais';
    end if;
    -- Si repite al principal no aporta un canal nuevo: se guarda vacio en vez de
    -- enseñar el mismo numero dos veces en la ficha.
    if v_alt = v_telefono then
      v_alt := null;
    end if;
  end if;

  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  if p_origen not in ('referido', 'landing', 'formulario', 'oficina', 'otro', 'web', 'campania', 'whatsapp') then
    raise exception using errcode = '22023', message = 'Origen invalido';
  end if;

  -- D8 (2026-08-11) · «landing y formulario se carga solo»: los canales
  -- automáticos (y los heredados) SOLO entran por el puente. Un alta manual que
  -- los declare está suplantando a la fuente — y con T10 vivo (el referido
  -- fuera del divisor), el origen mueve el porcentaje de alguien.
  if p_origen not in ('referido', 'oficina', 'otro') then
    raise exception using
      errcode = '42501',
      message = 'Ese origen entra solo por el puente: el alta manual admite referido, oficina u otro';
  end if;

  -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
  -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
  -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
  if p_origen = 'referido' and v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
  end if;

  if p_etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead no puede nacer en etapa terminal';
  end if;
  if p_monto_estimado is null
     or p_monto_estimado <= 0
     or p_monto_estimado > 9999999999.99
     or p_monto_estimado <> pg_catalog.trunc(p_monto_estimado, 2) then
    raise exception using errcode = '22023', message = 'Capital estimado invalido';
  end if;
  if p_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda invalida';
  end if;
  if v_genero is not null and v_genero not in ('F', 'M') then
    raise exception using errcode = '22023', message = 'Genero invalido';
  end if;
  if v_categoria is not null and v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception using errcode = '22023', message = 'Categoria de interes invalida';
  end if;
  if p_fecha_nacimiento is not null
     and (
       p_fecha_nacimiento < date '1900-01-01'
       or p_fecha_nacimiento > (v_hoy_lima - interval '18 years')::date
     ) then
    raise exception using errcode = '22023', message = 'El lead debe tener al menos 18 anos';
  end if;

  -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
  -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
  -- destino operativo activo o dejar el lead en la cola global.
  if v_rol = 'vendedor' then
    if v_vendedor is not null and v_vendedor is distinct from v_actor then
      raise exception using errcode = '42501', message = 'Solo puedes crear leads asignados a ti mismo';
    end if;
    v_vendedor := v_actor;
    v_supervisor := null;
  elsif v_vendedor is null and v_rol = 'supervisor' then
    v_supervisor := v_actor;
  else
    v_supervisor := null;
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  -- La identidad optimista funciona también como llave idempotente: si el
  -- commit llegó pero la respuesta de red se perdió, repetir el MISMO payload
  -- antes de una mutación posterior confirma el alta anterior en vez de
  -- pintarla como un contacto ajeno.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('avancecrm:lead:id:' || v_id::text, 0)
  );
  perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);

  -- Un administrador puede desactivar la membresia mientras esta sesion
  -- espera un contacto. El permiso se vuelve a consultar DESPUES de todos
  -- los locks para que una sesion revocada no alcance a insertar al despertar.
  v_rol_actual := private.rol_crm(v_actor);
  if v_rol_actual is distinct from v_rol
     or v_rol_actual not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  select l.* into v_existente
  from crm.leads l
  where l.id = v_id;

  if found then
    if v_existente.creado_por is not distinct from v_actor
       and v_existente.nombre_completo is not distinct from v_nombre
       and v_existente.telefono is not distinct from v_telefono
       -- El segundo numero entra en la comparacion idempotente: sin esto, un
       -- reintento que SOLO cambia el alternativo se confirmaria como «ya
       -- creado» y el dato nuevo se perderia sin decir nada.
       and v_existente.telefono_alternativo is not distinct from v_alt
       and v_existente.correo is not distinct from v_correo
       and v_existente.dni is not distinct from v_dni
       and v_existente.genero is not distinct from v_genero
       and v_existente.fecha_nacimiento is not distinct from p_fecha_nacimiento
       and v_existente.distrito is not distinct from v_distrito
       and v_existente.origen is not distinct from p_origen
       and v_existente.etapa is not distinct from p_etapa
       and v_existente.monto_estimado is not distinct from p_monto_estimado
       and v_existente.moneda is not distinct from p_moneda
       and v_existente.categoria_interes is not distinct from v_categoria
       and v_existente.vendedor_id is not distinct from v_vendedor
       and v_existente.asignado_supervisor_id is not distinct from v_supervisor
       and v_existente.nota is not distinct from v_nota
       and v_existente.activo = true then
      return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
    end if;

    raise exception using
      errcode = '22023',
      message = 'El identificador de esta alta ya fue usado con datos distintos';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    return v_disponibilidad;
  end if;

  insert into crm.leads (
    id,
    nombre_completo,
    telefono,
    telefono_alternativo,
    correo,
    dni,
    genero,
    fecha_nacimiento,
    distrito,
    origen,
    etapa,
    monto_estimado,
    moneda,
    categoria_interes,
    vendedor_id,
    asignado_supervisor_id,
    nota,
    activo,
    creado_por
  ) values (
    v_id,
    v_nombre,
    v_telefono,
    v_alt,
    v_correo,
    v_dni,
    v_genero,
    p_fecha_nacimiento,
    v_distrito,
    p_origen,
    p_etapa,
    p_monto_estimado,
    p_moneda,
    v_categoria,
    v_vendedor,
    v_supervisor,
    v_nota,
    true,
    v_actor
  );

  return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
end;
$function$;$olar_20260826182500_4$,
$olar_20260826182500_5$comment on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) is
  'Alta atomica de lead: verifica disponibilidad y crea en la misma transaccion, con llave idempotente por p_id. El telefono PRINCIPAL sigue siendo celular peruano (es la identidad: dedup, reparto y conversion cuelgan de el). Desde 20260826182500 admite p_telefono_alternativo, que acepta celular, fijo peruano o internacional via private.canonizar_contacto y no participa del dedup.';$olar_20260826182500_5$,
$olar_20260826182500_6$revoke all on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) from public, anon, service_role;$olar_20260826182500_6$,
$olar_20260826182500_7$grant execute on function crm.crear_lead_si_disponible(
  text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text
) to authenticated;$olar_20260826182500_7$,
$olar_20260826182500_8$do $postflight$
declare
  v_oid oid := 'crm.crear_lead_si_disponible(text, text, text, numeric, text, uuid, text, text, text, date, text, text, text, uuid, text, text)'::regprocedure;
  v_def text := pg_get_functiondef(v_oid);
begin
  -- Que NO haya quedado una SOBRECARGA: dos funciones con este nombre harian
  -- ambigua cada llamada del front y el alta fallaria con un error ilegible.
  if (select count(*) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'crear_lead_si_disponible') <> 1 then
    raise exception 'postflight: quedo mas de una crear_lead_si_disponible (sobrecarga ambigua)';
  end if;
  -- Que el segundo numero se canonice con la REGLA COMPARTIDA y no con un regex
  -- reescrito aqui dentro, que es como los espejos divergen.
  if position('private.canonizar_contacto' in v_def) = 0 then
    raise exception 'postflight: el segundo numero no usa la regla compartida';
  end if;
  -- Que se INSERTE de verdad: declararlo y olvidarlo en el insert es el fallo
  -- exacto que ya mordio en esta familia.
  if position('telefono_alternativo,' in v_def) = 0 or position('v_alt,' in v_def) = 0 then
    raise exception 'postflight: el segundo numero no viaja al insert';
  end if;
  -- Que entre en la comparacion idempotente.
  if position('v_existente.telefono_alternativo is not distinct from v_alt' in v_def) = 0 then
    raise exception 'postflight: el segundo numero queda fuera de la llave idempotente';
  end if;
  -- Que el PRINCIPAL siga siendo celular peruano: la opcion A depende de esto.
  if position('v_telefono !~ ''^\+519[0-9]{8}$''' in v_def) = 0 then
    raise exception 'postflight: el telefono principal dejo de exigir celular peruano';
  end if;
  -- Que sigan las guardias de ambito y admision.
  if position('vendedor_ids_visibles' in v_def) = 0
     or position('bloquear_contactos_lead' in v_def) = 0
     or position('verificar_disponibilidad_lead_impl' in v_def) = 0
     or position('Acceso CRM revocado' in v_def) = 0 then
    raise exception 'postflight: el alta perdio una guardia';
  end if;
  if not (select prosecdef from pg_catalog.pg_proc where oid = v_oid) then
    raise exception 'postflight: el alta dejo de ser SECURITY DEFINER';
  end if;
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'postflight: authenticated perdio el execute';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE')
     or has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'postflight: el drop+create abrio el alta a un rol que no la tenia';
  end if;
end;
$postflight$;$olar_20260826182500_8$,
$olar_20260826182500_9$commit;$olar_20260826182500_9$
], name = coalesce(name, '20260826182500_crm_crear_lead_telefono_alternativo')
 where version = '20260826182500' and statements is null;

-- 20260828190000 (crm_f1_1_rastro_titulares_gestion_cuotas): 7 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260828190000_0$-- P-055 Fase 1.1 - Rastro de lo que tiene valor probatorio (Miguel, 28/08).
--
-- QUE: cuatro tablas dejan de poder cambiar sin dejar rastro.
--   1. public.contrato_titulares -> auditor NUEVO (INSERT/UPDATE/DELETE).
--      Es el unico ROTO real del inventario P-053: los co-titulares de una
--      cuenta mancomunada se agregan y se quitan por delete+reinsert desde
--      public._sync_contrato_titulares y hoy no queda una sola linea (0 filas
--      en audit_log contra 1083 del contrato al que pertenecen). Es el dato
--      con mas peso legal del sistema.
--   2. crm.actividades_cliente -> auditor NUEVO (INSERT/UPDATE/DELETE).
--      Historial de gestion del cliente: hoy sin auditor de ningun tipo.
--   3. crm.actividades -> auditor NUEVO para el cambio y el borrado (el que ya
--      existe, de solo INSERT, no se toca): se podia borrar la gestion de un
--      lead sin rastro.
--   4. public.cronograma_pagos -> auditor NUEVO solo para el ALTA y la BAJA de
--      una cuota. El auditor de UPDATE que ya existe NO SE TOCA (ver abajo).
--
-- COMO: TODO ES ADITIVO. No se borra ni se recrea un solo trigger existente, y
-- no se toca ninguna funcion de auditoria: solo se cuelgan cuatro triggers
-- nuevos. No es estilo: es la leccion de la version anterior de este mismo
-- archivo (ver el aviso de abajo), y evita tres riesgos de una vez:
--   * perder atributos que `tgtype` no codifica -clausula WHEN, `UPDATE OF`,
--     enabled/replica, deferibilidad-, porque no se recrea nada;
--   * el candado: `drop trigger` exige ACCESS EXCLUSIVE sobre una tabla viva;
--     `create trigger` se conforma con SHARE ROW EXCLUSIVE;
--   * cambiar sin querer el orden de disparo.
-- Cada trigger nuevo mira eventos que NINGUN otro auditor mira en esa tabla
-- (UPDATE/DELETE en la gestion del lead, INSERT/DELETE en las cuotas), asi que
-- no hay doble registro de una misma operacion.
--
-- AVISO: EL TRIGGER DE CUOTAS NO SE RECREA - Y ESTO ESTUVO A PUNTO DE SER UN
-- FALLO. La primera version de esta migracion hacia DROP+CREATE tambien sobre
-- `trg_audit_cronograma_pago` para anadirle INSERT y DELETE. Ese trigger tiene
-- una clausula WHEN puesta a proposito en la auditoria del portal del
-- 2026-06-13: audita SOLO los UPDATE que tocan el pago (estado, monto_pagado,
-- fecha_pago_real, registrado_por). Recrearlo la habria borrado en silencio, y
-- con ella la unica defensa contra el ruido: el cron diario de recordatorios
-- escribe `notif_pago_enviada_en` y `recordatorio_3d_enviado_en` en muchas
-- filas, y sin el WHEN cada uno de esos sellos dejaria una fila de auditoria
-- con el JSON entero del antes y el despues. Asi que el trigger de UPDATE se
-- queda EXACTAMENTE como esta, y el hueco probatorio -que era el borrado- se
-- cierra con un trigger APARTE para INSERT y DELETE, donde una clausula WHEN
-- sobre `old`/`new` ni siquiera seria valida.
--
-- CONVENCION DE AUDITORIA - decision declarada, no descuido: cada esquema
-- conserva la suya. `public` usa public.log_audit_change (la columna `tabla`
-- guarda el nombre SIN esquema, como ya lo guardan contratos, perfiles y
-- cronograma_pagos) y `crm` usa private.log_audit_crm (la guarda CON esquema).
-- Unificarlas cambiaria el significado de las 22.000 filas ya escritas y
-- romperia toda consulta que lea `tabla`; el log partido queda DECLARADO aqui.
--
-- POR QUE AHORA: la Fase 1 tiene que estar publicada antes del primer cierre
-- de mes real. El coste es cero: son triggers, no datos.
--
-- FUERA DE ALCANCE A PROPOSITO (la Fase 7 los arregla o los declara):
--   * crm.operaciones_cartera: ledger append-only deliberado, con autoria en
--     la propia fila y un trigger que lo hace cumplir. REFUTADO como roto.
--   * crm.usuario_eventos: su `id` es BIGINT y private.log_audit_crm lo
--     castea a uuid -> colgarselo tal cual ABORTARIA todo su DML. Necesita su
--     propio auditor, no este.
--   * public.audit_log: auditarse a si mismo es recursion infinita.
--   * crm.agenda_ics, public.novedades_leidas, public.suscripciones_push y las
--     tablas operativas de `private`: sin valor probatorio.
--
-- LO QUE ESTO AMPLIA Y HAY QUE DECIR EN VOZ ALTA (auditoria RLS, 28/08):
--   * `crm.actividades_cliente` tiene su lectura acotada por RLS al subarbol
--     (gerencia, lector global, o el equipo del cliente). Su AUDITORIA, en
--     cambio, se escribe en `public.audit_log`, cuya lectura la gobiernan
--     `es_admin()`/`es_superadmin()` del PORTAL. Es decir: un admin del portal
--     que no sea gerencia del CRM pasa a poder leer el `detalle` de la gestion
--     comercial y, con `contrato_titulares`, el documento de cada co-titular.
--     Es el mismo trato que ya recibe `crm.leads` (que audita ahi con DNI y
--     telefono desde los cimientos), asi que no es una excepcion nueva; pero
--     queda DECLARADO. La vista de `audit_log` recortada por ambito es tarea
--     de la Fase 7.
--   * La bandeja de actividad del portal NO se contamina: `bandeja_actividad`
--     filtra por lista blanca (`al.tabla in ('perfiles','contratos')`),
--     verificado en produccion el 28/08. Su canal en vivo se suscribe a todo
--     `audit_log` con un retardo de 500 ms, asi que un alta de contrato puede
--     provocar una recarga mas de una pantalla ya abierta: la misma que ya
--     provoca hoy el alta del contrato en si.
--
-- AUTORIZACION: toca objetos de `public` (el portal en produccion) con el OK
-- explicito de Miguel al aprobar la Fase 1 del PLAN MAESTRO del servidor
-- (P-055). Ninguna funcion, policy ni grant cambia en esta migracion.

-- Que esto no se quede esperando detras de una transaccion larga: si no consigue
-- el candado en 5 segundos, falla y se reintenta, en vez de formar cola delante
-- de las escrituras del portal.
set local lock_timeout = '5s';$olar_20260828190000_0$,
$olar_20260828190000_1$-- == Preflight: el mundo vivo tiene que ser el que este cambio describe =======
do $preflight$
declare
  v_md5_public text;
  v_md5_crm    text;
  v_tipo       smallint;
  v_trg        oid;
  v_def        text;
begin
  -- Las dos funciones de auditoria son las auditadas el 28/08. Si alguna
  -- cambio, este trigger podria estar colgando otra cosa.
  select md5(p.prosrc) into v_md5_public
  from pg_catalog.pg_proc p
  where p.oid = 'public.log_audit_change()'::regprocedure;
  if v_md5_public is distinct from '0a71bb602eddd63669dfd6993246d16e' then
    raise exception 'public.log_audit_change viva (md5 %) no es la esperada', v_md5_public;
  end if;
  -- El hash cubre el CUERPO, no los atributos: una funcion con el mismo texto
  -- pero sin SECURITY DEFINER no podria escribir en `audit_log` y abortaria todo
  -- el DML de las tablas que la cuelguen. Se comprueba aparte.
  if not (select p.prosecdef from pg_catalog.pg_proc p
          where p.oid = 'public.log_audit_change()'::regprocedure) then
    raise exception 'public.log_audit_change no es SECURITY DEFINER: colgarla abortaria el DML';
  end if;

  select md5(p.prosrc) into v_md5_crm
  from pg_catalog.pg_proc p
  where p.oid = 'private.log_audit_crm()'::regprocedure;
  if v_md5_crm is distinct from '461846328cab450929731c0ca9edd319' then
    raise exception 'private.log_audit_crm viva (md5 %) no es la esperada', v_md5_crm;
  end if;
  if not (select p.prosecdef from pg_catalog.pg_proc p
          where p.oid = 'private.log_audit_crm()'::regprocedure) then
    raise exception 'private.log_audit_crm no es SECURITY DEFINER: colgarla abortaria el DML';
  end if;

  -- Las dos tablas sin auditor siguen sin auditor.
  if exists (
    select 1 from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'public.contrato_titulares'::regclass
      and not t.tgisinternal and p.proname in ('log_audit_change','log_audit_crm')
  ) then
    raise exception 'public.contrato_titulares YA tiene auditor: re-basar antes de aplicar';
  end if;
  if exists (
    select 1 from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'crm.actividades_cliente'::regclass
      and not t.tgisinternal and p.proname in ('log_audit_change','log_audit_crm')
  ) then
    raise exception 'crm.actividades_cliente YA tiene auditor: re-basar antes de aplicar';
  end if;

  -- Los dos auditores parciales siguen siendo parciales, y son los que creemos.
  -- tgtype: 1=FOR EACH ROW, 2=BEFORE, 4=INSERT, 8=DELETE, 16=UPDATE.
  select t.tgtype into v_tipo
  from pg_catalog.pg_trigger t
  where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_audit_actividades';
  if v_tipo is null then
    raise exception 'no existe trg_audit_actividades: re-basar antes de aplicar';
  end if;
  if v_tipo <> 5 then  -- AFTER (sin bit 2) + ROW (1) + INSERT (4)
    raise exception 'trg_audit_actividades ya no es AFTER INSERT FOR EACH ROW (tgtype %)', v_tipo;
  end if;

  -- Y el trigger nuevo de la gestion del lead no puede existir ya.
  if exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_audit_actividades_cambio_baja'
  ) then
    raise exception 'trg_audit_actividades_cambio_baja ya existe: re-basar antes de aplicar';
  end if;

  -- El auditor de cuotas sigue siendo el de la auditoria del portal del 13/06,
  -- con su WHEN intacto. No se toca, pero si cambio hay que enterarse.
  select t.tgtype into v_tipo
  from pg_catalog.pg_trigger t
  where t.tgrelid = 'public.cronograma_pagos'::regclass and t.tgname = 'trg_audit_cronograma_pago';
  if v_tipo is null then
    raise exception 'no existe trg_audit_cronograma_pago: re-basar antes de aplicar';
  end if;
  if v_tipo <> 17 then  -- AFTER + ROW (1) + UPDATE (16)
    raise exception 'trg_audit_cronograma_pago ya no es AFTER UPDATE FOR EACH ROW (tgtype %)', v_tipo;
  end if;
  -- Su clausula WHEN tiene que seguir nombrando las cuatro casillas de pago.
  -- Se comprueba por contenido y no por parentesis: la forma exacta que imprime
  -- pg_get_triggerdef es cosa suya, los cuatro campos son cosa nuestra.
  select t.oid into v_trg from pg_catalog.pg_trigger t
  where t.tgrelid = 'public.cronograma_pagos'::regclass
    and t.tgname = 'trg_audit_cronograma_pago';
  v_def := pg_catalog.pg_get_triggerdef(v_trg);
  if v_def is null
     or strpos(v_def, 'WHEN (') = 0
     or strpos(v_def, 'old.estado IS DISTINCT FROM new.estado') = 0
     or strpos(v_def, 'old.monto_pagado IS DISTINCT FROM new.monto_pagado') = 0
     or strpos(v_def, 'old.fecha_pago_real IS DISTINCT FROM new.fecha_pago_real') = 0
     or strpos(v_def, 'old.registrado_por IS DISTINCT FROM new.registrado_por') = 0 then
    raise exception 'el WHEN de trg_audit_cronograma_pago no es el esperado: revisar antes de aplicar. Vivo: %', v_def;
  end if;

  -- Y el trigger nuevo de alta/baja no puede existir ya.
  if exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.cronograma_pagos'::regclass
      and t.tgname = 'trg_audit_cronograma_pago_alta_baja'
  ) then
    raise exception 'trg_audit_cronograma_pago_alta_baja ya existe: re-basar antes de aplicar';
  end if;
end
$preflight$;$olar_20260828190000_1$,
$olar_20260828190000_2$-- == 1. Co-titulares: el rastro que faltaba ==================================
create trigger trg_audit_contrato_titulares
  after insert or update or delete on public.contrato_titulares
  for each row execute function public.log_audit_change();$olar_20260828190000_2$,
$olar_20260828190000_3$-- == 2. Historial de gestion del cliente =====================================
create trigger trg_audit_actividades_cliente
  after insert or update or delete on crm.actividades_cliente
  for each row execute function private.log_audit_crm();$olar_20260828190000_3$,
$olar_20260828190000_4$-- == 3. Gestion del lead: el cambio y el borrado, que era el hueco ===========
-- Trigger APARTE, no un reemplazo del que ya audita el alta: asi no se toca un
-- objeto vivo de una tabla con 3.952 filas ni se arriesga a perder nada suyo.
-- Para UPDATE y DELETE es el unico trigger de la tabla, asi que el orden de
-- disparo del alta (`trg_audit_actividades` antes que `trg_zy_...` y
-- `trg_zz_...`) queda exactamente como estaba.
create trigger trg_audit_actividades_cambio_baja
  after update or delete on crm.actividades
  for each row execute function private.log_audit_crm();$olar_20260828190000_4$,
$olar_20260828190000_5$-- == 4. Cuotas de pago: el alta y la baja, que era el hueco =================
-- Trigger APARTE, para no tocar el de UPDATE y su WHEN (ver la cabecera). Se
-- audita tambien el alta y no solo el borrado -que es el hueco probatorio- para
-- que una cuota que aparece de la nada tenga la misma explicacion que una que
-- desaparece; ademas es lo que permite leer la regeneracion masiva del
-- cronograma (DELETE+INSERT) como lo que es. El coste es una fila por cuota
-- creada o borrada: un contrato escribe una decena, no miles.
create trigger trg_audit_cronograma_pago_alta_baja
  after insert or delete on public.cronograma_pagos
  for each row execute function public.log_audit_change();$olar_20260828190000_5$,
$olar_20260828190000_6$-- == Postflight: los cuatro auditores existen y miran los tres eventos =======
do $postflight$
declare
  v_faltan text[] := '{}';
  v_par    record;
begin
  for v_par in
    select * from (values
      ('public.contrato_titulares', 'trg_audit_contrato_titulares'),
      ('crm.actividades_cliente',   'trg_audit_actividades_cliente')
    ) as v(tabla, trigger_)
  loop
    if not exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = v_par.tabla::regclass
        and t.tgname = v_par.trigger_
        and t.tgenabled = 'O'
        and t.tgtype = 29  -- AFTER + ROW(1) + INSERT(4) + DELETE(8) + UPDATE(16)
    ) then
      v_faltan := v_faltan || (v_par.tabla || '.' || v_par.trigger_);
    end if;
  end loop;
  if array_length(v_faltan, 1) is not null then
    raise exception 'POSTFLIGHT: auditores incompletos -> %', array_to_string(v_faltan, ', ');
  end if;

  -- Gestion del lead: el nuevo mira cambio y baja (tgtype 25 = AFTER + ROW(1) +
  -- DELETE(8) + UPDATE(16)) y el que auditaba el alta sigue intacto.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_audit_actividades_cambio_baja'
      and t.tgenabled = 'O' and t.tgtype = 25
  ) then
    raise exception 'POSTFLIGHT: falta el auditor de cambio/baja de la gestion del lead';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_audit_actividades' and t.tgtype = 5
  ) then
    raise exception 'POSTFLIGHT: el auditor del alta de la gestion del lead ya no es AFTER INSERT';
  end if;

  -- Cuotas: el nuevo mira alta y baja (tgtype 13 = AFTER + ROW + INSERT +
  -- DELETE) y el viejo sigue vivo, con su WHEN.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.cronograma_pagos'::regclass
      and t.tgname = 'trg_audit_cronograma_pago_alta_baja'
      and t.tgenabled = 'O' and t.tgtype = 13
  ) then
    raise exception 'POSTFLIGHT: falta el auditor de alta/baja de cuotas';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.cronograma_pagos'::regclass
      and t.tgname = 'trg_audit_cronograma_pago'
      and t.tgqual is not null
  ) then
    raise exception 'POSTFLIGHT: el auditor de UPDATE de cuotas perdio su clausula WHEN';
  end if;

  raise notice 'POSTFLIGHT OK: 4 auditores nuevos, ninguno recreado, y el WHEN del UPDATE de cuotas intacto';
end
$postflight$;$olar_20260828190000_6$
], name = coalesce(name, '20260828190000_crm_f1_1_rastro_titulares_gestion_cuotas')
 where version = '20260828190000' and statements is null;

-- 20260828190500 (crm_f1_2_malla_anti_nan_montos): 19 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260828190500_0$-- P-055 Fase 1.2 - La malla anti-NaN de los montos (Miguel, 28/08).
--
-- EL AGUJERO, en una linea: en Postgres `NaN > 0` es VERDADERO. Un monto
-- invalido atraviesa cualquier validacion escrita como "tiene que ser mayor
-- que cero" y se queda dentro. Lo mismo hace 'Infinity'. Medido en produccion
-- el 28/08: NaN > 0 = true, Infinity > 0 = true.
--
-- QUE: se blindan las 16 casillas de dinero y de conteo del CIERRE DE MES y
-- del CRONOGRAMA DE PAGOS que hoy no tienen ninguna defensa contra eso.
--   * public.cronograma_pagos: monto_programado, monto_pagado.
--   * crm.cierre_mes_vendedor: las 7 numericas de la foto que se sella.
--   * crm.ajustes_mes_cerrado: las 6 de la deuda que arrastra de un mes a otro.
--   * crm.periodos_cerrados: la ponderacion del referido.
--
-- POR QUE AHORA Y NO DESPUES: las tres tablas del cierre estan VACIAS hoy
-- (0 filas las tres, contadas el 28/08). Blindar una tabla vacia no cuesta
-- nada. Despues del primer cierre real -que es el del 10/09- ya no.
-- `cronograma_pagos` si tiene datos: 4252 filas, minimo 10.83, ninguna <= 0 y
-- ninguna nula donde el CHECK exige valor. Medido antes de escribir esto.
--
-- LA FORMA DEL GUARDIAN: `x <> 'NaN' and x <> 'Infinity' and x <> '-Infinity'`.
-- Se lee raro y es exacto: en Postgres `NaN = NaN` es VERDADERO (asi ordena y
-- agrupa), de modo que `x <> 'NaN'` da FALSO justo cuando x es NaN, y el CHECK
-- lo rechaza. Igual con los infinitos.
--
-- SIN RANGOS DE NEGOCIO, A PROPOSITO. En el cierre solo se exige que el numero
-- sea un numero. Un tope o un suelo inventado aqui romperia el cierre del 10 en
-- vez de protegerlo: `crm.cerrar_periodo` sella `numerador` = bruto MENOS lo que
-- el mes absorbio de deudas viejas, y `conversion_pct` = 100 * ese neto /
-- divisor; ninguno de los dos tiene garantizado quedarse dentro de 0..100 ni
-- siquiera ser positivo. Los rangos, si algun dia se quieren, se deciden con la
-- foto del primer cierre delante (Fase 2 del plan), no antes de tenerla.
-- En `cronograma_pagos` si hay regla de negocio evidente y verificada contra
-- las 4252 filas: una cuota programada es mayor que cero, y un pago registrado
-- nunca es negativo.
--
-- NOTA DE TIPO, verificada en produccion: `numeric(12,2)` -el tipo de las dos
-- columnas del cronograma- RECHAZA los infinitos por si mismo ("numeric field
-- overflow") pero ACEPTA NaN sin protestar. Las clausulas de infinito ahi son
-- cinturon y tirantes; en el cierre, donde las columnas son `numeric` a secas,
-- son imprescindibles.
--
-- SOLO ANADE constraints; no modifica ni borra ninguna de las que ya existen.
--
-- FUERA DE ALCANCE A PROPOSITO (auditoria RLS, 28/08): queda UNA casilla de
-- dinero sin guardian fuera del cierre y del cronograma -
-- `crm.lead_asignaciones.monto_estimado`, cuyo CHECK es `is null or >= 0` y por
-- tanto deja pasar NaN igual que cualquier liston de un solo lado. Es una
-- estimacion del ledger de asignaciones, no dinero cobrado, y esta migracion se
-- cine a lo que el plan puso en la Fase 1; se recoge en la Fase 7 con el resto
-- del inventario de montos. Su gemela `crm.leads.monto_estimado` SI esta
-- cubierta, por casualidad afortunada: su CHECK tiene tope superior
-- (`<= 9999999999.99`) y un NaN no pasa un tope.
--
-- AUTORIZACION: toca `public.cronograma_pagos` (portal en produccion) con el OK
-- explicito de Miguel al aprobar la Fase 1 del PLAN MAESTRO P-055.

-- Que esto no forme cola delante del portal: `add constraint` toma ACCESS
-- EXCLUSIVE, y aunque validar 4252 filas es instantaneo, esperar detras de una
-- transaccion larga no lo es. Con el liston de 5 segundos, falla y se reintenta.
set local lock_timeout = '5s';$olar_20260828190500_0$,
$olar_20260828190500_1$-- == Preflight: nada de esto existe ya, y los datos aguantan el liston ========
do $preflight$
declare
  v_malas bigint;
begin
  -- Por PAR (tabla, nombre): `conname` no es unico en toda la base, y una
  -- constraint homonima en otra tabla daria un falso "ya aplicada".
  if exists (
    select 1 from pg_catalog.pg_constraint c
    where c.contype = 'c'
      and (c.conrelid, c.conname) in (
        ('public.cronograma_pagos'::regclass, 'cronograma_pagos_monto_programado_valido'),
        ('public.cronograma_pagos'::regclass, 'cronograma_pagos_monto_pagado_valido'),
        ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_numerador_finito'),
        ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_numerador_finito'),
        ('crm.periodos_cerrados'::regclass,   'periodos_cerrados_ponderacion_referido_finito'))
  ) then
    raise exception 'la malla anti-NaN ya estaba puesta: re-basar antes de aplicar';
  end if;

  -- El liston contra los datos VIVOS del cronograma, antes de intentarlo.
  select count(*) into v_malas
  from public.cronograma_pagos
  where not (monto_programado > 0 and monto_programado <> 'NaN'::numeric)
     or (monto_pagado is not null and not (monto_pagado >= 0 and monto_pagado <> 'NaN'::numeric));
  if v_malas > 0 then
    raise exception 'PREFLIGHT: % cuotas no pasarian el liston; revisarlas antes de aplicar', v_malas;
  end if;

  -- Las tres tablas del cierre siguen vacias (si no, hay que medir antes).
  if (select count(*) from crm.cierre_mes_vendedor) > 0
     or (select count(*) from crm.ajustes_mes_cerrado) > 0
     or (select count(*) from crm.periodos_cerrados) > 0 then
    raise exception 'PREFLIGHT: el cierre ya tiene datos; medir el liston contra ellos antes de aplicar';
  end if;
end
$preflight$;$olar_20260828190500_1$,
$olar_20260828190500_2$-- == 1. Cronograma de pagos: las dos casillas de dinero ======================
alter table public.cronograma_pagos
  add constraint cronograma_pagos_monto_programado_valido
  check (monto_programado > 0::numeric
         and monto_programado <> 'NaN'::numeric
         and monto_programado <> 'Infinity'::numeric
         and monto_programado <> '-Infinity'::numeric);$olar_20260828190500_2$,
$olar_20260828190500_3$alter table public.cronograma_pagos
  add constraint cronograma_pagos_monto_pagado_valido
  check (monto_pagado is null
         or (monto_pagado >= 0::numeric
             and monto_pagado <> 'NaN'::numeric
             and monto_pagado <> 'Infinity'::numeric
             and monto_pagado <> '-Infinity'::numeric));$olar_20260828190500_3$,
$olar_20260828190500_4$-- == 2. La foto que se sella cada mes ========================================
alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_numerador_finito
  check ((numerador <> 'NaN'::numeric and numerador <> 'Infinity'::numeric and numerador <> '-Infinity'::numeric));$olar_20260828190500_4$,
$olar_20260828190500_5$alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_conversion_pct_finito
  check (conversion_pct is null or (conversion_pct <> 'NaN'::numeric and conversion_pct <> 'Infinity'::numeric and conversion_pct <> '-Infinity'::numeric));$olar_20260828190500_5$,
$olar_20260828190500_6$alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_referidos_aporta_pct_finito
  check (referidos_aporta_pct is null or (referidos_aporta_pct <> 'NaN'::numeric and referidos_aporta_pct <> 'Infinity'::numeric and referidos_aporta_pct <> '-Infinity'::numeric));$olar_20260828190500_6$,
$olar_20260828190500_7$alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_ajuste_numerador_finito
  check ((ajuste_numerador <> 'NaN'::numeric and ajuste_numerador <> 'Infinity'::numeric and ajuste_numerador <> '-Infinity'::numeric));$olar_20260828190500_7$,
$olar_20260828190500_8$alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_ajuste_pen_finito
  check ((ajuste_pen <> 'NaN'::numeric and ajuste_pen <> 'Infinity'::numeric and ajuste_pen <> '-Infinity'::numeric));$olar_20260828190500_8$,
$olar_20260828190500_9$alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_ajuste_usd_finito
  check ((ajuste_usd <> 'NaN'::numeric and ajuste_usd <> 'Infinity'::numeric and ajuste_usd <> '-Infinity'::numeric));$olar_20260828190500_9$,
$olar_20260828190500_10$alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_conversion_objetivo_finito
  check (conversion_objetivo is null or (conversion_objetivo <> 'NaN'::numeric and conversion_objetivo <> 'Infinity'::numeric and conversion_objetivo <> '-Infinity'::numeric));$olar_20260828190500_10$,
$olar_20260828190500_11$-- == 3. La deuda que arrastra de un mes a otro ===============================
alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_capital_pen_finito
  check ((capital_pen <> 'NaN'::numeric and capital_pen <> 'Infinity'::numeric and capital_pen <> '-Infinity'::numeric));$olar_20260828190500_11$,
$olar_20260828190500_12$alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_capital_usd_finito
  check ((capital_usd <> 'NaN'::numeric and capital_usd <> 'Infinity'::numeric and capital_usd <> '-Infinity'::numeric));$olar_20260828190500_12$,
$olar_20260828190500_13$alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_numerador_finito
  check ((numerador <> 'NaN'::numeric and numerador <> 'Infinity'::numeric and numerador <> '-Infinity'::numeric));$olar_20260828190500_13$,
$olar_20260828190500_14$alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_pendiente_numerador_finito
  check ((pendiente_numerador <> 'NaN'::numeric and pendiente_numerador <> 'Infinity'::numeric and pendiente_numerador <> '-Infinity'::numeric));$olar_20260828190500_14$,
$olar_20260828190500_15$alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_pendiente_pen_finito
  check ((pendiente_pen <> 'NaN'::numeric and pendiente_pen <> 'Infinity'::numeric and pendiente_pen <> '-Infinity'::numeric));$olar_20260828190500_15$,
$olar_20260828190500_16$alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_pendiente_usd_finito
  check ((pendiente_usd <> 'NaN'::numeric and pendiente_usd <> 'Infinity'::numeric and pendiente_usd <> '-Infinity'::numeric));$olar_20260828190500_16$,
$olar_20260828190500_17$-- == 4. La ponderacion del referido del periodo ==============================
alter table crm.periodos_cerrados
  add constraint periodos_cerrados_ponderacion_referido_finito
  check (ponderacion_referido is null
         or (ponderacion_referido <> 'NaN'::numeric
             and ponderacion_referido <> 'Infinity'::numeric
             and ponderacion_referido <> '-Infinity'::numeric));$olar_20260828190500_17$,
$olar_20260828190500_18$-- == Postflight: los 16 guardianes estan, y el liston MUERDE de verdad =======
-- La sonda NO escribe en ninguna tabla de produccion: copia el predicado VIVO
-- de cada constraint -leido del catalogo, no reescrito aqui- a una tabla
-- temporal y le tira los valores malos. Asi prueba el liston que quedo puesto,
-- no una version de laboratorio que podria haber divergido.
do $postflight$
declare
  v_puestas int;
  v_def     text;
  v_colada  boolean;
  v_paso    boolean;
begin
  -- Contados por PAR (tabla, nombre) y exigiendo `convalidated`: un nombre
  -- suelto podria venir de otra tabla e inflar la cuenta.
  select count(*) into v_puestas
  from pg_catalog.pg_constraint c
  where c.contype = 'c' and c.convalidated
    and (c.conrelid, c.conname) in (
      ('public.cronograma_pagos'::regclass, 'cronograma_pagos_monto_programado_valido'),
      ('public.cronograma_pagos'::regclass, 'cronograma_pagos_monto_pagado_valido'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_numerador_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_conversion_pct_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_referidos_aporta_pct_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_ajuste_numerador_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_ajuste_pen_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_ajuste_usd_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_conversion_objetivo_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_capital_pen_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_capital_usd_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_numerador_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_pendiente_numerador_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_pendiente_pen_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_pendiente_usd_finito'),
      ('crm.periodos_cerrados'::regclass,   'periodos_cerrados_ponderacion_referido_finito'));
  if v_puestas <> 16 then
    raise exception 'POSTFLIGHT: se esperaban 16 guardianes y hay %', v_puestas;
  end if;

  -- ---- Sonda 1: el monto programado de una cuota ---------------------------
  select pg_catalog.pg_get_constraintdef(c.oid) into v_def
  from pg_catalog.pg_constraint c
  where c.conrelid = 'public.cronograma_pagos'::regclass
    and c.conname = 'cronograma_pagos_monto_programado_valido';
  execute format(
    'create temporary table sonda_f1_2 (monto_programado numeric(12,2), constraint sonda_cuota %s)',
    v_def);

  -- NEGATIVO: el NaN rebota.
  v_colada := true;
  begin
    execute 'insert into sonda_f1_2 values (''NaN''::numeric)';
  exception when check_violation then v_colada := false;
  end;
  if v_colada then
    raise exception 'POSTFLIGHT: un NaN atraviesa el liston del monto programado';
  end if;

  -- NEGATIVO: el cero y el negativo tambien.
  v_colada := true;
  begin
    execute 'insert into sonda_f1_2 values (0)';
  exception when check_violation then v_colada := false;
  end;
  if v_colada then
    raise exception 'POSTFLIGHT: una cuota de 0 atraviesa el liston';
  end if;

  -- POSITIVO -sin este caso la sonda no prueba nada-: un monto real pasa.
  v_paso := false;
  begin
    execute 'insert into sonda_f1_2 values (1234.56)';
    v_paso := true;
  exception when others then v_paso := false;
  end;
  if not v_paso then
    raise exception 'POSTFLIGHT: el liston del monto programado rechaza un monto valido';
  end if;
  drop table sonda_f1_2;

  -- ---- Sonda 2: el numerador de la foto del cierre -------------------------
  select pg_catalog.pg_get_constraintdef(c.oid) into v_def
  from pg_catalog.pg_constraint c
  where c.conrelid = 'crm.cierre_mes_vendedor'::regclass
    and c.conname = 'cierre_mes_vendedor_numerador_finito';
  execute format(
    'create temporary table sonda_f1_2 (numerador numeric, constraint sonda_cierre %s)',
    v_def);

  -- NEGATIVO: NaN e infinito rebotan.
  v_colada := true;
  begin
    execute 'insert into sonda_f1_2 values (''NaN''::numeric)';
  exception when check_violation then v_colada := false;
  end;
  if v_colada then
    raise exception 'POSTFLIGHT: un NaN atraviesa el liston del cierre';
  end if;

  v_colada := true;
  begin
    execute 'insert into sonda_f1_2 values (''Infinity''::numeric)';
  exception when check_violation then v_colada := false;
  end;
  if v_colada then
    raise exception 'POSTFLIGHT: un infinito atraviesa el liston del cierre';
  end if;

  -- POSITIVO: el cierre puede sellar cero, negativos y decimales. Si alguno de
  -- estos rebotara, el liston romperia el cierre en vez de protegerlo.
  v_paso := false;
  begin
    execute 'insert into sonda_f1_2 values (0), (-3.5), (17.25)';
    v_paso := true;
  exception when others then v_paso := false;
  end;
  if not v_paso then
    raise exception 'POSTFLIGHT: el liston del cierre rechaza numeros legitimos';
  end if;
  drop table sonda_f1_2;

  raise notice 'POSTFLIGHT OK: 16 guardianes puestos; NaN e infinito rebotan y los numeros legitimos pasan';
end
$postflight$;$olar_20260828190500_18$
], name = coalesce(name, '20260828190500_crm_f1_2_malla_anti_nan_montos')
 where version = '20260828190500' and statements is null;

-- 20260828191000 (crm_f1_3_puertas_baratas_anon): 6 sentencias
update supabase_migrations.schema_migrations
   set statements = array[

$olar_20260828191000_0$-- P-055 Fase 1.3 - Las puertas baratas: lo que la seguridad por filas NO mira.
--
-- QUE, en una linea: se le quita a los visitantes sin cuenta -y a cualquier
-- sesion iniciada- los cuatro permisos de fabrica que la seguridad por filas no
-- gobierna, y se le quita al visitante sin cuenta el acceso a las 5 consultas
-- de administracion. Nada de lo que el portal usa se toca.
--
-- AVISO SOBRE LA REINCIDENCIA: `alter default privileges` deja una entrada en
-- `pg_default_acl` que la plataforma puede volver a pisar -Supabase reejecuta
-- sus `grant all` en restauraciones y reseteos de esquema-. El endurecimiento
-- no se repara solo: conviene que el gate de realidad lo mire de vez en cuando.
--
-- AVISO SOBRE EL REVOKE A `public`: quitarle EXECUTE a PUBLIC se lo quita
-- tambien a cualquier rol que lo tuviera SOLO por herencia de PUBLIC -por
-- ejemplo `dashboard_user` o `supabase_read_only_user`-. Se ha verificado que
-- los dos que importan (`authenticated` para las pantallas, `service_role`
-- para las edges) tienen concesion propia y no pierden nada.
--
-- 1) VACIAR TABLAS Y TRES PRIMOS SUYOS. Las 10 tablas de `public` nacieron con
--    el permiso completo de fabrica de Supabase (arwdDxtm) para `anon` y para
--    `authenticated`. De esas ocho letras, cuatro NO pasan por la seguridad por
--    filas y por eso son las unicas peligrosas:
--      TRUNCATE   - vacia la tabla entera de un golpe; RLS no la mira.
--      REFERENCES - deja apuntar claves foraneas contra ella.
--      TRIGGER    - deja colgarle triggers.
--      MAINTAIN   - deja lanzarle VACUUM/ANALYZE/REINDEX (candados pesados).
--    Las otras cuatro (SELECT/INSERT/UPDATE/DELETE) SI las gobierna RLS y son
--    exactamente las que el portal necesita: se quedan intactas.
--
--    Se le quitan tambien a `authenticated`, no solo a `anon`, aunque el plan
--    solo hablaba del visitante sin cuenta: el agujero es el mismo para
--    cualquiera con una sesion, y ninguna pantalla del portal ni del CRM vacia
--    tablas, crea triggers, ni lanza mantenimientos. `service_role` conserva
--    todo -es quien opera de verdad-.
--
--    LO QUE ESTA MIGRACION NO TOCA, Y NO ES UN OLVIDO: `anon` conserva
--    INSERT/UPDATE/DELETE sobre esas 10 tablas, y `authenticated` los conserva
--    sobre `public.audit_log`, donde ninguna policy los respalda. Son grants
--    MUERTOS -la seguridad por filas los deja en cero- y recortarlos toca la
--    superficie viva del portal: eso es la Fase 5, que va con prueba completa
--    con cuenta real el mismo dia. Aqui solo se cierra lo que la RLS no mira.
--    El postflight, por eso, comprueba unicamente que este cambio no se lleve
--    por delante el SELECT de nadie: no exige que los grants muertos sigan ahi,
--    para no cementarlos y no hacer fallar a quien manana los recorte.
--
--    Y se corta la reincidencia: los permisos por defecto de `public` los daba
--    tambien a cualquier tabla FUTURA. A partir de aqui, una tabla nueva creada
--    por las migraciones nace sin esas cuatro letras. (Las que crea Supabase
--    por su cuenta, como rol `supabase_admin`, siguen fuera de nuestro alcance:
--    queda declarado.)
--
-- 2) LAS 5 CONSULTAS DE ADMINISTRACION. Cualquiera puede ejecutarlas hoy. No
--    filtran nada -son SECURITY INVOKER, corren como quien llama y RLS las deja
--    en cero filas-, pero no tienen ningun motivo para estar abiertas. Se
--    conservan intactas para `authenticated`, que es quien las usa desde las
--    pantallas de administracion del portal (js/admin/dashboard.js,
--    js/admin/pagos.js), y para `service_role`.
--
--    AVISO: SE REVOCA A `public`, NO SOLO A `anon` - y esto costo una sonda. La
--    primera version de esta migracion revocaba a `anon` y NO CAMBIABA NADA:
--    medido contra produccion, `anon` seguia pudiendo ejecutarlas. El permiso no
--    le venia de su nombre sino de `PUBLIC`: el ACL de las cinco empieza por
--    `{=X/postgres...}`, que es "EXECUTE para todo el mundo". Quitarselo a un rol
--    que lo hereda de PUBLIC no quita nada. Por eso aqui se revoca a `public` y
--    a `anon`, y se vuelven a conceder explicitamente los dos accesos que si
--    existen hoy. Es exactamente el patron que ya usan las funciones del CRM
--    (`crear_contrato` no tiene entrada de PUBLIC en su ACL).
--
-- AVISO: RIESGO CONOCIDO Y ACEPTADO, dicho en voz alta. En la imagen local de
--    Postgres 17.6.1.105 -misma version y mismas librerias que produccion-
--    llamar a una funcion SIN permiso de EXECUTE no da "permission denied":
--    revienta el proceso de Postgres (reproducido 4 veces el 20/08; sospechoso
--    principal `plan_filter`). Nunca se ha probado contra produccion y no debe
--    probarse. Cerrar estas 5 no crea esa exposicion: hay ya casi 300 funciones
--    en los esquemas expuestos que `anon` tampoco puede ejecutar, asi que el
--    vector -si existe en produccion- ya esta abierto y no depende de esta
--    migracion. Lo que si hay que hacer despues de aplicar: comprobar que
--    ninguna pagina PUBLICA del portal (sin sesion) llama a estas 5. Verificado
--    por lectura el 28/08: las 5 solo se invocan desde /admin, detras del login.
--
-- AVISO: PASO OBLIGATORIO EN EL BANCO ANTES DE PUBLICAR ESTA MIGRACION.
--    El riesgo del parrafo anterior no se acepta a ciegas: se COMPRUEBA, y en un
--    branch, que corre la MISMA imagen de Postgres que produccion. Despues de
--    aplicar las cuatro migraciones ahi, hay que hacer una llamada anonima real:
--
--      curl -s -o /dev/null -w '%{http_code}\n' -X POST \
--        "$SUPABASE_URL/rest/v1/rpc/dashboard_admin_metricas" \
--        -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -d '{}'
--
--    Tiene que responder **401/403 con codigo 42501** y el banco tiene que
--    SEGUIR VIVO (una segunda llamada cualquiera debe responder). Si en cambio
--    se cae la conexion o el banco entra en recuperacion, esa es la confirmacion
--    de que el fallo de la imagen tambien afecta aqui: en ese caso NO se publica
--    el bloque 2 de esta migracion -las 5 consultas se quedan como estan, que no
--    filtran nada- y se escala a soporte de Supabase.
--    Motivo de que sea obligatorio: los nombres de esas 5 funciones estan en el
--    JavaScript publicado del portal, asi que son endpoints CONOCIDOS; cerrarlos
--    sin comprobar convertiria un fallo teorico de la plataforma en cinco
--    palancas concretas al alcance de cualquiera con la clave publicable.
--
-- NO crea ni modifica ninguna funcion, policy ni tabla. Solo quita permisos.
--
-- AUTORIZACION: toca permisos de objetos de `public` (portal en produccion) con
-- el OK explicito de Miguel al aprobar la Fase 1 del PLAN MAESTRO P-055.

-- == Preflight: el mundo vivo es el que este cambio describe ==================
do $preflight$
declare
  v_tablas int;
  v_rpcs   int;
begin
  -- Las 10 tablas siguen teniendo las cuatro letras peligrosas para anon.
  select count(*) into v_tablas
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and c.relname in ('asesores','audit_log','contrato_titulares','contratos',
                      'cronograma_pagos','documentos','novedades','novedades_leidas',
                      'perfiles','suscripciones_push')
    and has_table_privilege('anon', c.oid, 'TRUNCATE');
  if v_tablas <> 10 then
    raise exception 'PREFLIGHT: se esperaban 10 tablas con TRUNCATE para anon y hay %', v_tablas;
  end if;

  -- Y que no haya aparecido una 11.a tabla en `public` igual de expuesta que
  -- esta lista no nombre. Hoy las 10 nombradas son TODAS las de `public`.
  if (select count(*) from pg_catalog.pg_class c
      where c.relnamespace = 'public'::regnamespace and c.relkind = 'r') <> 10 then
    raise exception 'PREFLIGHT: `public` ya no tiene exactamente 10 tablas; revisar la lista antes de aplicar';
  end if;

  -- Las 5 consultas de administracion siguen abiertas a TODO EL MUNDO (PUBLIC).
  -- Se mira el ACL, no has_function_privilege: esa funcion dice "si" tambien
  -- cuando el permiso viene heredado de PUBLIC, que es justo lo que enmascaro
  -- el problema la primera vez.
  select count(*) into v_rpcs
  from pg_catalog.pg_proc p
  where p.oid in (
      'public.admin_pagos_metricas()'::regprocedure,
      'public.admin_pagos_resumen()'::regprocedure,
      'public.dashboard_admin_metricas()'::regprocedure,
      'public.pagos_admin_metricas_globales()'::regprocedure,
      'public.pagos_admin_resumen_contratos(text,text,text,integer,integer)'::regprocedure)
    and exists (
      select 1 from aclexplode(p.proacl) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE');
  if v_rpcs <> 5 then
    raise exception 'PREFLIGHT: se esperaban 5 RPC de administracion abiertas a PUBLIC y hay %', v_rpcs;
  end if;
end
$preflight$;$olar_20260828191000_0$,
$olar_20260828191000_1$-- == 1. Las cuatro letras que RLS no gobierna ================================
revoke truncate, references, trigger, maintain on table
  public.asesores,
  public.audit_log,
  public.contrato_titulares,
  public.contratos,
  public.cronograma_pagos,
  public.documentos,
  public.novedades,
  public.novedades_leidas,
  public.perfiles,
  public.suscripciones_push
from anon, authenticated;$olar_20260828191000_1$,
$olar_20260828191000_2$-- Y que no vuelva a pasar con las tablas que nazcan de aqui en adelante.
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger, maintain on tables from anon, authenticated;$olar_20260828191000_2$,
$olar_20260828191000_3$-- == 2. Las 5 consultas de administracion, cerradas al visitante sin cuenta ==
revoke execute on function
  public.admin_pagos_metricas(),
  public.admin_pagos_resumen(),
  public.dashboard_admin_metricas(),
  public.pagos_admin_metricas_globales(),
  public.pagos_admin_resumen_contratos(text,text,text,integer,integer)
from public, anon;$olar_20260828191000_3$,
$olar_20260828191000_4$-- Y se devuelve, explicito, exactamente el acceso que existia hoy: nadie pierde
-- una capacidad que estuviera usando.
grant execute on function
  public.admin_pagos_metricas(),
  public.admin_pagos_resumen(),
  public.dashboard_admin_metricas(),
  public.pagos_admin_metricas_globales(),
  public.pagos_admin_resumen_contratos(text,text,text,integer,integer)
to authenticated, service_role;$olar_20260828191000_4$,
$olar_20260828191000_5$-- == Postflight: cerrado lo que tocaba y NADA de lo que el portal usa ========
do $postflight$
declare
  v_malas text[] := '{}';
  v_t     record;
  v_rpcs  int;
  v_auth  int;
begin
  for v_t in
    select c.oid, c.relname
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and c.relname in ('asesores','audit_log','contrato_titulares','contratos',
                        'cronograma_pagos','documentos','novedades','novedades_leidas',
                        'perfiles','suscripciones_push')
  loop
    -- Lo que tiene que haber desaparecido, para los dos roles.
    if has_table_privilege('anon', v_t.oid, 'TRUNCATE')
       or has_table_privilege('authenticated', v_t.oid, 'TRUNCATE')
       or has_table_privilege('anon', v_t.oid, 'REFERENCES')
       or has_table_privilege('authenticated', v_t.oid, 'REFERENCES')
       or has_table_privilege('anon', v_t.oid, 'TRIGGER')
       or has_table_privilege('authenticated', v_t.oid, 'TRIGGER')
       or has_table_privilege('anon', v_t.oid, 'MAINTAIN')
       or has_table_privilege('authenticated', v_t.oid, 'MAINTAIN') then
      v_malas := v_malas || ('sigue abierta: ' || v_t.relname);
    end if;
    -- Lo que NO se puede haber movido: el portal lee y escribe con RLS delante.
    -- Lo que NO se puede haber movido: la lectura que el portal usa de verdad,
    -- y el rol que opera. Deliberadamente NO se exige aqui que sigan los grants
    -- de escritura de `anon` ni los de `authenticated` sobre `audit_log`: estan
    -- muertos y son tarea de la Fase 5; exigirlos los cementaria.
    if not has_table_privilege('authenticated', v_t.oid, 'SELECT')
       or not has_table_privilege('anon', v_t.oid, 'SELECT')
       or not has_table_privilege('service_role', v_t.oid, 'TRUNCATE') then
      v_malas := v_malas || ('se llevo por delante permisos vivos: ' || v_t.relname);
    end if;
  end loop;
  if array_length(v_malas, 1) is not null then
    raise exception 'POSTFLIGHT: %', array_to_string(v_malas, ' | ');
  end if;

  -- Las 5 consultas: cerradas a anon, INTACTAS para authenticated.
  select count(*) filter (
           where has_function_privilege('anon', p.oid, 'EXECUTE')
              or exists (select 1 from aclexplode(p.proacl) a
                         where a.grantee = 0 and a.privilege_type = 'EXECUTE')),
         count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    into v_rpcs, v_auth
  from pg_catalog.pg_proc p
  where p.oid in (
      'public.admin_pagos_metricas()'::regprocedure,
      'public.admin_pagos_resumen()'::regprocedure,
      'public.dashboard_admin_metricas()'::regprocedure,
      'public.pagos_admin_metricas_globales()'::regprocedure,
      'public.pagos_admin_resumen_contratos(text,text,text,integer,integer)'::regprocedure);
  if v_rpcs <> 0 then
    raise exception 'POSTFLIGHT: quedan % consultas de administracion abiertas a anon o a PUBLIC', v_rpcs;
  end if;
  if not has_function_privilege('service_role',
        'public.dashboard_admin_metricas()'::regprocedure, 'EXECUTE') then
    raise exception 'POSTFLIGHT: service_role perdio la consulta de administracion';
  end if;
  if v_auth <> 5 then
    raise exception 'POSTFLIGHT: authenticated perdio acceso a las consultas de administracion (solo % de 5)', v_auth;
  end if;

  -- Y la reincidencia: el permiso por defecto de `public` ya no regala las
  -- cuatro letras a las tablas que nazcan de las migraciones.
  if exists (
    select 1 from pg_catalog.pg_default_acl d, aclexplode(d.defaclacl) a
    where d.defaclrole = 'postgres'::regrole
      and d.defaclnamespace = 'public'::regnamespace
      and d.defaclobjtype = 'r'
      and a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid)
      and a.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
  ) then
    raise exception 'POSTFLIGHT: el permiso por defecto de public sigue regalando las cuatro letras';
  end if;

  raise notice 'POSTFLIGHT OK: 4 letras cerradas en 10 tablas y en el default de public; 5 RPC cerradas a anon/PUBLIC y vivas para authenticated y service_role';
end
$postflight$;$olar_20260828191000_5$
], name = coalesce(name, '20260828191000_crm_f1_3_puertas_baratas_anon')
 where version = '20260828191000' and statements is null;


-- =====================================================================
-- 2) POSTFLIGHT: relectura POR ELEMENTO + diff-cero por contenido + guardianes.
-- =====================================================================
do $$
declare r record; v_h text; v_n int; v_txt text;
begin
  if (select count(*) from supabase_migrations.schema_migrations where statements is null) <> 0 then
    raise exception 'OLA R postflight: quedaron versiones mudas';
  end if;
  for r in select * from _olar_esperado loop
    select (select md5(string_agg(md5(u.s), '|' order by u.ord))
           from unnest(m.statements) with ordinality as u(s, ord)), array_length(m.statements, 1)
      into v_h, v_n from supabase_migrations.schema_migrations m where m.version = r.version;
    if v_h is distinct from r.huella_elems or v_n is distinct from r.n_sentencias then
      raise exception 'OLA R postflight: la relectura de % no coincide (huella %, % sentencias)', r.version, v_h, v_n;
    end if;
    if exists (select 1 from supabase_migrations.schema_migrations m, unnest(m.statements) s
                where m.version = r.version and (s is null or btrim(s) = '')) then
      raise exception 'OLA R postflight: % tiene una sentencia NULL o vacia', r.version;
    end if;
  end loop;

  if exists (select 1 from _olar_foto f, lateral (
    select
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('public','crm','private')) as fns,
    (select md5(string_agg(n.nspname || '.' || p.proname
        || '(' || pg_get_function_identity_arguments(p.oid) || ')'
        || ':' || md5(p.prosrc) || ':' || p.prorettype::regtype::text
        || ':' || p.provolatile::text || ':' || p.prosecdef::text
        || ':' || coalesce(p.proconfig::text,'-') || ':' || p.proowner::regrole::text
        || ':' || coalesce(p.proacl::text,'-'), '|'
        order by n.nspname, p.proname, p.oid))
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('public','crm','private') and p.prokind = 'f') as huella_fns,
    (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname in ('public','crm','private') and c.relkind in ('r','v','m','i')) as rels,
    -- Codex v2: CONTENIDO, no conteos
    (select md5(coalesce(string_agg(pol.polname || ':' || pol.polrelid::regclass::text
        || ':' || coalesce(pg_get_expr(pol.polqual, pol.polrelid), '-')
        || ':' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '-'), '|'
        order by pol.polrelid, pol.polname), '-')) from pg_policy pol) as policies_h,
    (select md5(coalesce(string_agg(pg_get_triggerdef(t.oid), '|' order by t.oid), '-'))
      from pg_trigger t where not t.tgisinternal) as triggers_h,
    (select md5(coalesce(string_agg(c.conname || ':' || pg_get_constraintdef(c.oid), '|'
        order by c.conrelid, c.conname), '-')) from pg_constraint c where c.contype = 'c') as checks_h,
    (select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.username || ':' || md5(j.command), '|'
        order by j.jobid), '-')) from cron.job j) as crons_h,
    (select md5(coalesce(string_agg(d.classoid::text || ':' || d.objoid::text || ':' || d.objsubid || ':' || md5(d.description), '|'
        order by d.classoid, d.objoid, d.objsubid), '-')) from pg_description d) as comments_h,
    (select md5(coalesce(string_agg(d.defaclrole::regrole::text || ':' || coalesce(d.defaclnamespace::regnamespace::text, '-')
        || ':' || d.defaclobjtype::text || ':' || d.defaclacl::text, '|'
        order by d.oid), '-')) from pg_default_acl d) as defacl_h,
    (select md5(string_agg(n.nspname || '.' || c.relname || '.' || a.attname || ':' || a.atttypid::regtype::text
        || ':' || a.attnotnull::text || ':' || coalesce(pg_get_expr(ad.adbin, ad.adrelid), '-')
        || ':' || a.attidentity::text || ':' || a.attgenerated::text
        || ':' || a.attcollation::text || ':' || coalesce(a.attacl::text, '-') || ':' || a.attstattarget::text, '|'
        order by n.nspname, c.relname, a.attnum))
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
      left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
      where n.nspname in ('public','crm','private') and c.relkind = 'r'
        and a.attnum > 0 and not a.attisdropped) as columnas_h,
    (select count(*) from public.contratos) as contratos,
    (select count(*) from crm.leads) as leads
  ) d where f is distinct from d) then
    raise exception 'OLA R postflight: el catalogo CAMBIO fuera del registro - un reparador de actas no toca el mundo';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
  v_txt := private.assert_f7_piezas_cerradas();
  if v_txt not like 'OK:%' then
    raise exception 'OLA R postflight: el vigilante F7 no da OK (%)', v_txt;
  end if;
end $$;

commit;

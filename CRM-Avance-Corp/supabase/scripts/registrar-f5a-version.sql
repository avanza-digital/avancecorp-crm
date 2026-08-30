-- Registra la version 20260830090000 en el registro de migraciones CON su cuerpo.
-- ⚠️ Se ejecuta SOLO despues de que la migracion haya hecho commit.
insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260830090000',
  'crm_f5_a_una_sola_pregunta_analista',
  array[$mig_f5_a$-- P-055 Fase 5.a - UNA SOLA PREGUNTA: "¿es analista VIGENTE?"
--
-- QUE, en una linea: se cierra la "revocacion a medias" -quien tiene la
-- membresia del CRM apagada pero sigue de alta como analista en el Portal- y se
-- cierra de la unica forma que no se vuelve a abrir sola: UNA pregunta que
-- responde por todas las puertas, y un trinquete que impide que nazca la octava
-- preguntando lo viejo.
--
-- AUTORIZACION EXPLICITA DE MIGUEL (chat del 2026-08-30, literal):
--   "El conflicto de admin, medido y escrito. ... Eso entra en la Fase 5 - y esa
--    parte se puede adelantar sola, es lo unico con efecto sobre datos reales hoy."
--   "pasalo por Codex y el auditor antes de publicar"
--   "dale, hazlo asi, y audita que quede bien"  <- sobre la forma de UNA SOLA
--    PREGUNTA + trinquete + las siete puertas, recomendada y aceptada.
-- ALCANCE SOBRE `public`, con ese OK explicito: 3 TABLAS (`contratos`,
-- `cronograma_pagos`, `perfiles`) y 2 FUNCIONES (`puede_ver_contrato`,
-- `productos_inversion_seleccion_fn`), mas un `grant` sobre una funcion de
-- `private`. Nada mas de `public` se toca.
--
-- EL PROBLEMA, MEDIDO CONTRA PRODUCCION EL 2026-08-30 (solo lectura):
--   - 31 politicas se gobiernan por el rol del Portal; solo UNA preguntaba ya
--     por la revocacion (y estaba MUERTA, ver el punto 2).
--   - De las 4 personas con `crm.equipo.activo = false`, tres tienen rol de
--     Portal `comercial` -a las que `es_analista()` no alcanza-. La cuarta es
--     analista viva del Portal, cuenta sin bloquear y con sesion iniciada este
--     mes: veia 3 contratos, 39 cuotas y 2 fichas de cliente.
--   - Y el agujero era MAS ANCHO que las 4 politicas: con los identificadores
--     que su propia pantalla le mostro seguia pudiendo pedir la ficha 360
--     completa (`crm.cliente_detalle_fn`: DNI, correo, telefono, domicilio y
--     datos BANCARIOS en PEN y USD), los co-titulares de sus contratos
--     (`public.puede_ver_contrato` -> `public.contrato_titulares` y
--     `public.contrato_tiene_pagos`) y el catalogo de productos. Cerrar solo las
--     4 politicas cerraba la ENUMERACION, no el acceso dirigido.
--
-- LO QUE ESTA MIGRACION NO TOCA, Y NO ES UN OLVIDO:
--   - `public.es_analista()` sigue igual: es la pregunta del Portal.
--   - Las politicas de `es_admin()` / `es_gestor_cartera()`: los 2 admin del
--     Portal NO tienen fila en `crm.equipo`, asi que la revocacion no les
--     aplica. Paso 2 de la Fase 5, con su propia decision de negocio.
--   - `public.proteger_campos_inmutables`: ahi `es_analista()` sirve para
--     PROHIBIR. Anadirle la vigencia RELAJARIA el candado. Queda DECLARADO.
--
-- 🔴 CONSECUENCIA DECLARADA DEL CANDADO DEL PUNTO 4: mientras exista fila en
--    `crm.equipo`, el borrado duro de la cuenta de Auth o del perfil de esa
--    persona ABORTA (las dos claves foraneas son ON DELETE CASCADE). Es
--    deliberado -borrar la fila convertiria a un REVOCADO en AJENO y le
--    devolveria los accesos-, pero cambia el comportamiento del panel para las
--    26 personas con fila. La salida declarada es `crm.purgar_membresia_crm(
--    perfil_id, motivo)`: SOLO con la llave del servidor, con motivo escrito y
--    dejando lapida en `private.membresias_purgadas`. El candado impide el
--    borrado ACCIDENTAL y silencioso, no la baja deliberada y anotada.
--
-- ORDEN DE LA TRANSACCION (importante): primero todo lo que NO bloquea tablas de
-- negocio -helper, tablas del trinquete, funciones, reemplazos-, y AL FINAL los
-- cuatro `alter policy` y el trigger. `ALTER POLICY` toma ACCESS EXCLUSIVE y no
-- lo suelta hasta el commit: cuanto mas tarde se tome, menos tiempo se retiene.
-- `lock_timeout` limita lo que se ESPERA, no lo que se RETIENE.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: anclar la PREIMAGEN por huella.
-- =====================================================================
do $$
declare
  v_esperado constant text[][] := array[
    array['public','contratos',       'contratos_analista_select', 'r','5a24688ac0b5e25e73aaf3d27d0c49d9',''],
    array['public','cronograma_pagos','cronograma_analista_select','r','e843b1a209c10f3610e6d797f188a1f8',''],
    array['public','perfiles',        'perfiles_analista_select',  'r','cb4ffa816804f998b8a3c57626d3e54a',''],
    array['public','perfiles',        'perfiles_analista_update',  'w','ecf097f78023a74f2ff66303c7c8cfdb','2911ed25bfadabb95c50dcd51fadb73a']
  ];
  v_fn constant text[][] := array[
    array['crm.cliente_detalle_fn(uuid)',                      'f1541e556beb8a1de4a4d464fa8f10cd'],
    array['public.puede_ver_contrato(uuid)',                   'c746e2e7184132e99923a463a4dcf694'],
    array['public.productos_inversion_seleccion_fn(uuid)',     'f984bd0a4d9ba86cefff2d74542c483b']
  ];
  v_fila text[]; v_using text; v_check text; v_roles text; v_cmd "char"; v_perm boolean; v_md5 text;
begin
  foreach v_fila slice 1 in array v_esperado loop
    select md5(pg_get_expr(pol.polqual, pol.polrelid)),
           coalesce(md5(pg_get_expr(pol.polwithcheck, pol.polrelid)), ''),
           pol.polroles::regrole[]::text, pol.polcmd, pol.polpermissive
      into v_using, v_check, v_roles, v_cmd, v_perm
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = v_fila[1] and c.relname = v_fila[2] and pol.polname = v_fila[3];

    if not found then
      raise exception 'F5.a preflight: no existe la politica %.%.%', v_fila[1], v_fila[2], v_fila[3];
    end if;
    -- El comando EXACTO de cada una: una SELECT recreada como UPDATE con el
    -- mismo nombre y la misma expresion pasaria un chequeo laxo.
    if v_cmd::text is distinct from v_fila[4] then
      raise exception 'F5.a preflight: %.% es de tipo % y se esperaba %', v_fila[2], v_fila[3], v_cmd, v_fila[4];
    end if;
    if v_using is distinct from v_fila[5] or v_check is distinct from v_fila[6] then
      raise exception 'F5.a preflight: %.% cambio desde la medicion (using %, check %)', v_fila[2], v_fila[3], v_using, v_check;
    end if;
    -- Si alguna fuese `to public`, una sesion anon evaluaria la expresion y se
    -- llevaria un 42501: `anon` no tiene USAGE sobre `private`.
    if v_roles is distinct from '{authenticated}' then
      raise exception 'F5.a preflight: %.% apunta a %', v_fila[2], v_fila[3], v_roles;
    end if;
    if not v_perm then
      raise exception 'F5.a preflight: %.% dejo de ser permissive', v_fila[2], v_fila[3];
    end if;
  end loop;

  -- Las 3 funciones, por IDENTIDAD exacta (regprocedure), no por nombre: una
  -- sobrecarga nueva no debe colarse por el mismo `proname`.
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_md5 is distinct from v_fila[2] then
      raise exception 'F5.a preflight: % cambio desde la medicion (huella %)', v_fila[1], v_md5;
    end if;
  end loop;
end $$;

-- =====================================================================
-- 1) LA PREGUNTA UNICA.
-- =====================================================================
-- Vive en `private` a proposito: ese esquema NO esta expuesto al Data API, asi
-- que no nace un endpoint. No acepta parametros -responde por el propio
-- llamante-, de modo que nadie puede sondear a un tercero con ella.
create or replace function private.es_analista_vigente()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  -- Analista del Portal Y con la membresia del CRM sin revocar.
  -- Quien no tiene fila en `crm.equipo` NO esta revocado: la revocacion exige
  -- una fila con `activo is false`. Los 18 analistas vivos no pierden nada.
  select public.es_analista()
     and not private.membresia_crm_revocada();
$function$;

comment on function private.es_analista_vigente() is
  'P-055 F5.a. La UNICA pregunta de autoridad para el analista: rol de Portal vigente Y membresia del CRM sin revocar. Toda puerta que dependa de "es analista" pregunta esto y no public.es_analista(); el trinquete private.assert_analista_vigencia() lo vigila.';

revoke all on function private.es_analista_vigente() from public;
-- Las politicas se evaluan como el LLAMANTE: sin este permiso reventarian con
-- 42501 para toda sesion autenticada. Igual que sus hermanas `private.rol_crm`
-- y `private.es_lector_global`: solo `authenticated`. A `anon` no, que ademas
-- careceria de USAGE sobre `private` y seria inerte.
grant execute on function private.es_analista_vigente() to authenticated;

-- =====================================================================
-- 2) EL PERMISO QUE FALTABA DESDE LA FASE 3 (bug ajeno, se repara de paso).
-- =====================================================================
-- `private.membresia_crm_revocada()` solo tenia EXECUTE para `postgres`. La
-- unica politica que ya la usaba -`reasignaciones_lee_autoridad`, de la F3.4-
-- NACIO MUERTA: la lectura directa de `crm.reasignaciones_analista` revienta hoy
-- con 42501 incluso para GERENCIA. Con el permiso, esa politica hace lo que la
-- F3 escribio. SI CAMBIA QUIEN LEE esa tabla: pasa de NADIE a gestor de cartera
-- y gerencia no revocada. Es la intencion de la F3.4, dicha en voz alta.
grant execute on function private.membresia_crm_revocada() to authenticated;

-- =====================================================================
-- 3) EL TRINQUETE (se monta ANTES de tocar tablas de negocio).
-- =====================================================================
create table if not exists private.analista_vigencia_exenciones (
  objeto       text primary key,
  tipo         text not null,
  huella       text not null,
  razon        text not null,
  declarado_en timestamptz not null default now(),
  constraint tipo_conocido check (tipo in ('funcion','vista','policy')),
  constraint razon_de_verdad check (length(btrim(razon)) >= 40)
);
alter table private.analista_vigencia_exenciones enable row level security;
comment on table private.analista_vigencia_exenciones is
  'P-055 F5.a. Sitios donde la pregunta del Portal se usa CRUDA a proposito, por IDENTIDAD exacta y con la HUELLA del cuerpo al declararlos: si el cuerpo cambia, la exencion caduca y el gate se pone rojo.';

create table if not exists private.analista_vigencia_tope (
  id             boolean primary key default true,
  tope           integer not null,
  nucleo_huella  text,
  actualizado_en timestamptz not null default now(),
  constraint una_sola_fila check (id is true),
  constraint tope_no_negativo check (tope >= 0)
);
alter table private.analista_vigencia_tope enable row level security;

create or replace function private.trg_analista_vigencia_tope_solo_baja()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- El trinquete no se burla borrando y volviendo a insertar la fila.
  if tg_op = 'DELETE' then
    raise exception 'La fila del tope no se borra: borrarla y reinsertarla reiniciaria el trinquete.'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.tope > old.tope then
    raise exception 'El tope de puertas sin vigencia solo puede BAJAR (% -> %). Subirlo es una decision de negocio, no un ajuste.', old.tope, new.tope
      using errcode = '42501';
  end if;
  new.actualizado_en := now();
  return new;
end;
$function$;

drop trigger if exists trg_analista_vigencia_tope_solo_baja on private.analista_vigencia_tope;
create trigger trg_analista_vigencia_tope_solo_baja
  before update or delete on private.analista_vigencia_tope
  for each row execute function private.trg_analista_vigencia_tope_solo_baja();

create or replace function private.trg_analista_vigencia_tope_no_truncar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception 'La tabla del tope no se vacia.' using errcode = '42501';
end;
$function$;

drop trigger if exists trg_analista_vigencia_tope_no_truncar on private.analista_vigencia_tope;
create trigger trg_analista_vigencia_tope_no_truncar
  before truncate on private.analista_vigencia_tope
  for each statement execute function private.trg_analista_vigencia_tope_no_truncar();

-- Quien pregunta lo viejo, listado. Se mide por LLAMADA, no por texto suelto:
--   · se quitan comentarios de linea y de bloque ANTES de mirar -si no, un
--     `-- ya migrado a es_analista_vigente` bastaba para desaparecer del radar-;
--   · el ancla es `\mes_analista\s*\(`: exige inicio de palabra y parentesis,
--     asi `crm.reasignaciones_analista (` deja de contar como llamada (tres
--     falsos positivos medidos el 2026-08-30) y `es_analista_vigente(` tampoco
--     casa, porque tras "es_analista" viene "_";
--   · NO se excluye por "contiene la palabra vigente": una puerta MIXTA
--     (`es_analista_vigente() or es_analista()`) tiene que salir listada;
--   · se mira tambien la comprobacion CRUDA del rol (`rol = 'analista'`), que es
--     la forma obvia de esquivar la funcion;
--   · se miran funciones Y procedimientos, TODOS los esquemas, las VISTAS y las
--     politicas.
create or replace function private.puertas_analista_sin_vigencia()
returns table (tipo text, objeto text, declarada boolean, huella_ok boolean)
language sql
stable
security definer
set search_path to ''
as $function$
  with fn as (
    select 'funcion'::text as tipo,
           p.oid::regprocedure::text as objeto,
           regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g') as cuerpo
      from pg_proc p
     where p.prokind in ('f','p')
       -- El nucleo y las dos piezas del propio trinquete se excluyen por
       -- IDENTIDAD: `es_analista()` es la pregunta del Portal, y el censo y el
       -- gate llevan el patron dentro de una expresion regular.
       and p.oid <> 'public.es_analista()'::regprocedure
       -- Las tres piezas propias se excluyen por NOMBRE dentro de `private`, no
       -- por `regprocedure`: esta funcion se crea ANTES que el gate, y resolver
       -- la identidad de algo que aun no existe aborta la migracion.
       and not (p.pronamespace = 'private'::regnamespace
                and p.proname in ('es_analista_vigente',
                                  'puertas_analista_sin_vigencia',
                                  'assert_analista_vigencia'))
  ),
  vw as (
    select 'vista'::text,
           c.relnamespace::regnamespace::text || '.' || c.relname,
           pg_get_viewdef(c.oid)
      from pg_class c
     where c.relkind in ('v','m')
  ),
  po as (
    select 'policy'::text,
           c.relnamespace::regnamespace::text || '.' || c.relname || '.' || pol.polname,
           coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') || ' '
             || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '')
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
  ),
  todo as (select * from fn union all select * from vw union all select * from po),
  crudas as (
    select t.tipo, t.objeto, md5(t.cuerpo) as huella
      from todo t
     where t.cuerpo ~ '\mes_analista\s*\('
        or t.cuerpo ~ '\mrol\s*=\s*''analista'''
  )
  select cr.tipo,
         cr.objeto,
         (e.objeto is not null) as declarada,
         (e.objeto is not null and e.huella = cr.huella) as huella_ok
    from crudas cr
    left join private.analista_vigencia_exenciones e on e.objeto = cr.objeto
   order by 3, 4, 1, 2;
$function$;

revoke all on function private.puertas_analista_sin_vigencia() from public;

-- El gate ENTERO vive aqui: el vigia por cron (`crm-vigencia-analista-vigia`,
-- 06:39), el guion del repo (`npm run gate:vigencia`), el postflight y los siete
-- filos del mutante ejecutan ESTA MISMA funcion. Asi no se puede romper el gate y
-- seguir verde (leccion de la F1.6).
create or replace function private.assert_analista_vigencia()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_sin_declarar text;
  v_caducadas text;
  v_declaradas integer;
  v_tope integer;
  v_nucleo text;
  v_nucleo_esperado text;
  v_src text;
begin
  select string_agg(tipo || ' ' || objeto, ', ' order by objeto)
    into v_sin_declarar
    from private.puertas_analista_sin_vigencia() where not declarada;
  if v_sin_declarar is not null then
    raise exception 'Puertas que preguntan por el rol del Portal a secas y NO estan declaradas: %. O preguntan por private.es_analista_vigente(), o se declaran con su razon.', v_sin_declarar;
  end if;

  select string_agg(tipo || ' ' || objeto, ', ' order by objeto)
    into v_caducadas
    from private.puertas_analista_sin_vigencia() where declarada and not huella_ok;
  if v_caducadas is not null then
    raise exception 'Puertas exentas cuyo cuerpo CAMBIO desde que se declararon (la razon ya no se puede dar por buena): %', v_caducadas;
  end if;

  select count(*) into v_declaradas from private.puertas_analista_sin_vigencia();
  select tope, nucleo_huella into v_tope, v_nucleo_esperado from private.analista_vigencia_tope where id;
  if v_tope is null then
    raise exception 'No hay tope fijado para las puertas sin vigencia';
  end if;
  if v_declaradas > v_tope then
    raise exception 'Las puertas sin vigencia subieron de % a %: el trinquete solo deja bajar.', v_tope, v_declaradas;
  end if;

  -- La pregunta unica, por HUELLA exacta y por atributos: no basta con que
  -- "contenga" las dos palabras.
  select md5(p.prosrc), p.prosrc into v_nucleo, v_src
    from pg_proc p where p.oid = 'private.es_analista_vigente()'::regprocedure;
  if v_nucleo_esperado is not null and v_nucleo is distinct from v_nucleo_esperado then
    raise exception 'private.es_analista_vigente() cambio de cuerpo (huella % en vez de %)', v_nucleo, v_nucleo_esperado;
  end if;
  if v_src !~ '\mes_analista\s*\(' or v_src !~ '\mmembresia_crm_revocada\s*\(' then
    raise exception 'private.es_analista_vigente() dejo de preguntar por las dos mitades';
  end if;
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'private.es_analista_vigente()'::regprocedure
       and p.prosecdef and p.provolatile = 's'
       -- 🔴 El search_path vacio se guarda CON COMILLAS (`search_path=""`).
       --    Comprobar `array['search_path=']` falla SIEMPRE (trampa ya pagada
       --    dos veces en este proyecto). Se aceptan las dos formas.
       and exists (select 1 from unnest(p.proconfig) c where c ~ '^search_path=(""|)$')
  ) then
    raise exception 'private.es_analista_vigente() perdio security definer, stable o el search_path vacio';
  end if;

  return 'OK: ' || v_declaradas || ' puertas declaradas y con su huella intacta, tope ' || v_tope || ', 0 sin declarar';
end;
$function$;

revoke all on function private.assert_analista_vigencia() from public;

comment on function private.assert_analista_vigencia() is
  'P-055 F5.a. El trinquete de la autoridad del analista. Devuelve una FILA con el veredicto (el canal db query NO transporta los raise notice) y revienta si nace una puerta nueva con la pregunta cruda, si una exenta cambia de cuerpo o si el nucleo se toca.';

-- Las exenciones, por IDENTIDAD exacta y con la huella del cuerpo de hoy
-- SIN comentarios (la misma normalizacion que usa el censo: si no, cambiar un
-- comentario caducaria la exencion sin motivo).
-- Las tres que un censo por texto marcaba y NO son puertas
-- (`crm.atribucion_contrato_fn`, `public.reasignar_analista_contrato`,
-- `crm.completar_domicilio_cliente`) NO estan aqui: casaban por el nombre de la
-- tabla `crm.reasignaciones_analista` y por un comentario.
insert into private.analista_vigencia_exenciones (objeto, tipo, huella, razon) values
  ('public.proteger_campos_inmutables()', 'funcion', '4727fcb810c3ec082d47b02a3bee7126',
   'Aqui la pregunta del Portal se usa para PROHIBIR, no para permitir: es el candado que impide a un analista togglear activo o blanquear el asesor de su cliente. Anadirle la vigencia RELAJARIA el candado.'),
  ('private.puede_gestionar_cuentas_cliente(uuid)', 'funcion', 'da2fdeac84cc7017615090f1c0b46c48',
   'Es la puerta P04 en persona: ya pregunta por private.membresia_crm_revocada() en su propio cuerpo, que es exactamente la mitad nueva de es_analista_vigente().'),
  ('public.actualizar_contrato(uuid,jsonb,jsonb)', 'funcion', 'ae74fcb7d0dd994e11bda80497fc7822',
   'La rama del ANALISTA cierra por private.puede_gestionar_cuentas_cliente(cliente_id), que exige la membresia sin revocar. (Su pregunta directa por membresia_crm_revocada guarda la otra rama, la de gestor de cartera y gerencia.)'),
  ('public.crear_contrato(jsonb,jsonb)', 'funcion', '4498215792dc3dd1192fe6b303871bbe',
   'Gatea por private.puede_gestionar_cuentas_cliente(), que exige la membresia del CRM sin revocar. La revocada rebota ahi antes de escribir una fila.'),
  ('public.crear_contrato_producto(uuid,jsonb,jsonb)', 'funcion', 'a6ea3a7c41c952d5365c7640fe944aeb',
   'Su primer gate es del Portal, pero delega en public.crear_contrato, que exige la membresia del CRM: la revocada rebota en la llamada interna sin crear nada.'),
  ('public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'funcion', 'a418a64e8f1273fe6dfae2606cce308e',
   'Su primer gate es del Portal, pero delega en public.actualizar_contrato, cuya rama de analista cierra por puede_gestionar_cuentas_cliente: la revocada rebota dentro.'),
  ('public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'funcion', 'f0d90f4a266a07a50f04b8d3173e597d',
   'Su primer gate es del Portal, pero delega en crm.actualizar_contrato_con_cuenta, que gatea por private.puede_gestionar_cuentas_cliente(cliente_id) y exige la membresia sin revocar.'),
  ('public.bandeja_actividad(integer,integer)', 'funcion', 'ff1bd19fed8d1d754547638ca205b12f',
   'No es una puerta de analista: compara rol = analista solo para ETIQUETAR filas de actividad, y el acceso entero esta gateado por es_admin() antes de llegar ahi.'),
  ('public.directorio_ranking_analistas()', 'funcion', 'a7802ac98df93cedb37d64c9057c0610',
   'No es una puerta de analista: usa rol = analista para SELECCIONAR a quien se rankea, y el acceso esta gateado por es_directorio() o es_admin().')
on conflict (objeto) do update set tipo = excluded.tipo, huella = excluded.huella, razon = excluded.razon;

-- =====================================================================
-- 4) LAS PUERTAS QUE SON FUNCIONES (reemplazo ANCLADO sobre el cuerpo vivo).
-- =====================================================================
-- No se re-teclea el cuerpo: se lee el vivo por IDENTIDAD exacta, se exige que
-- el ancla aparezca el numero exacto de veces y se sustituye. Asi la migracion
-- no puede perder por el camino nada que otra sesion haya anadido.
do $$
declare
  v_caso constant text[][] := array[
    array['crm.cliente_detalle_fn(uuid)',                  '(select public.es_analista())', '(select private.es_analista_vigente())', '1'],
    array['public.puede_ver_contrato(uuid)',               'public.es_analista()',          'private.es_analista_vigente()',          '1'],
    array['public.productos_inversion_seleccion_fn(uuid)', '(select public.es_analista())', '(select private.es_analista_vigente())', '2']
  ];
  v_fila text[]; v_def text; v_veces integer;
begin
  foreach v_fila slice 1 in array v_caso loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = v_fila[1]::regprocedure;
    v_veces := (length(v_def) - length(replace(v_def, v_fila[2], ''))) / length(v_fila[2]);
    if v_veces <> v_fila[4]::integer then
      raise exception 'F5.a: el ancla % aparece % veces en % y se esperaban %', v_fila[2], v_veces, v_fila[1], v_fila[4];
    end if;
    execute replace(v_def, v_fila[2], v_fila[3]);
  end loop;
end $$;

-- =====================================================================
-- 5) EL CANDADO QUE FALTABA: BORRAR LA FILA DEL EQUIPO REABRIA TODO.
-- =====================================================================
-- La revocacion se reconoce por una fila con `activo = false`. Si esa fila se
-- BORRA, la persona deja de estar revocada y pasa a ser "ajena al CRM": vuelve a
-- caer en los fallbacks del Portal. `crm.equipo` auditaba el borrado pero no lo
-- impedia. La regla P04 ("offboarding = activo=false, NUNCA DELETE") deja de ser
-- costumbre y pasa a ser candado. Corre TAMBIEN para `service_role` a proposito:
-- exceptuarlo reabriria el fallo. Ver la consecuencia declarada en la cabecera.
create or replace function private.trg_equipo_no_borrar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- UNICA salida: la puerta declarada del punto 5.1, que deja rastro y lapida.
  -- La valvula usa el mismo idioma que `crm.op_privilegiada` de la Fase 3.
  if coalesce(current_setting('crm.purgando_membresia', true), '') = 'on' then
    return old;
  end if;
  raise exception
    'Una fila de crm.equipo no se borra: el offboarding es activo=false. Borrarla convertiria a una persona REVOCADA en AJENA al CRM y le devolveria los accesos del Portal (perfil_id=%). Si de verdad hace falta purgarla, usa crm.purgar_membresia_crm(perfil_id, motivo).', old.perfil_id
    using errcode = '42501';
  return null;
end;
$function$;

-- 5.1 LA PUERTA DECLARADA PARA PURGAR (baja legal, limpieza de una base de
--     pruebas, fixture del gate). Solo `service_role` -la llave del servidor-,
--     motivo obligatorio, rastro en la auditoria y una LAPIDA que deja escrito
--     que esa persona estuvo revocada aunque su fila ya no exista.
--     🔴 DICHO EN VOZ ALTA: purgar SI devuelve los accesos del Portal a quien
--        estaba revocado. Por eso no es un borrado cualquiera: exige llave de
--        servidor, un motivo escrito y deja lapida. Lo que el candado impide es
--        el borrado ACCIDENTAL y SILENCIOSO (cascada del panel, script de
--        limpieza, `delete` suelto), que era el camino real.
create table if not exists private.membresias_purgadas (
  id            uuid primary key default gen_random_uuid(),
  perfil_id     uuid not null,
  rol_crm       text,
  activo_al_purgar boolean,
  motivo        text not null,
  purgado_en    timestamptz not null default now(),
  constraint motivo_de_verdad check (length(btrim(motivo)) >= 20)
);
alter table private.membresias_purgadas enable row level security;
comment on table private.membresias_purgadas is
  'P-055 F5.a. Lapidas de membresias de crm.equipo borradas por la puerta declarada. Si alguien vuelve a aparecer aqui, su baja se hizo purgando y no apagando.';

create or replace function crm.purgar_membresia_crm(p_perfil_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_fila crm.equipo%rowtype;
begin
  if length(btrim(coalesce(p_motivo, ''))) < 20 then
    raise exception 'Purgar una membresia exige un motivo escrito de al menos 20 caracteres.'
      using errcode = '22023';
  end if;

  select * into v_fila from crm.equipo where perfil_id = p_perfil_id;
  if not found then
    raise exception 'No hay membresia que purgar para %', p_perfil_id using errcode = 'P0002';
  end if;

  insert into private.membresias_purgadas (perfil_id, rol_crm, activo_al_purgar, motivo)
  values (v_fila.perfil_id, v_fila.rol_crm, v_fila.activo, btrim(p_motivo));

  perform set_config('crm.purgando_membresia', 'on', true);
  delete from crm.equipo where perfil_id = p_perfil_id;
  perform set_config('crm.purgando_membresia', '', true);
end;
$function$;

revoke all on function crm.purgar_membresia_crm(uuid, text) from public;
revoke all on function crm.purgar_membresia_crm(uuid, text) from anon;
revoke all on function crm.purgar_membresia_crm(uuid, text) from authenticated;
-- SOLO la llave del servidor. Ni una sesion de persona puede llamarla.
grant execute on function crm.purgar_membresia_crm(uuid, text) to service_role;

-- =====================================================================
-- 6) LAS CUATRO POLITICAS Y EL TRIGGER: lo unico que bloquea tablas calientes.
--    Va lo ultimo a proposito, para retener ACCESS EXCLUSIVE el menor tiempo.
-- =====================================================================
alter policy contratos_analista_select on public.contratos
  using (
    (select private.es_analista_vigente())
    and exists (
      select 1 from public.perfiles cli
      where cli.id = contratos.cliente_id and cli.rol = 'cliente'
        and (cli.asesor_perfil_id = (select auth.uid())
             or (cli.asesor_perfil_id is null and cli.creado_por = (select auth.uid())))
    )
  );

alter policy cronograma_analista_select on public.cronograma_pagos
  using (
    (select private.es_analista_vigente())
    and exists (
      select 1 from public.contratos c
      join public.perfiles cli on cli.id = c.cliente_id
      where c.id = cronograma_pagos.contrato_id and cli.rol = 'cliente'
        and (cli.asesor_perfil_id = (select auth.uid())
             or (cli.asesor_perfil_id is null and cli.creado_por = (select auth.uid())))
    )
  );

alter policy perfiles_analista_select on public.perfiles
  using (
    (select private.es_analista_vigente())
    and rol = 'cliente'
    and (asesor_perfil_id = (select auth.uid())
         or (asesor_perfil_id is null and creado_por = (select auth.uid())))
  );

-- La vigencia entra en las DOS mitades: la fila que se toca y como queda.
alter policy perfiles_analista_update on public.perfiles
  using (
    (select private.es_analista_vigente())
    and rol = 'cliente'
    and creado_en > (now() - '05:00:00'::interval)
    and (creado_por = (select auth.uid()) or asesor_perfil_id = (select auth.uid()))
  )
  with check (
    (select private.es_analista_vigente())
    and rol = 'cliente'
    and (creado_por = (select auth.uid()) or asesor_perfil_id = (select auth.uid()))
  );

drop trigger if exists trg_equipo_no_borrar on crm.equipo;
create trigger trg_equipo_no_borrar
  before delete on crm.equipo
  for each row execute function private.trg_equipo_no_borrar();

-- El tope se fija con lo que quede DESPUES de convertir las siete puertas, y se
-- graba la huella del nucleo recien creado.
insert into private.analista_vigencia_tope (id, tope, nucleo_huella)
select true,
       (select count(*) from private.puertas_analista_sin_vigencia()),
       (select md5(prosrc) from pg_proc where oid = 'private.es_analista_vigente()'::regprocedure)
on conflict (id) do update
  set tope = least(private.analista_vigencia_tope.tope, excluded.tope),
      nucleo_huella = excluded.nucleo_huella;

-- El VIGIA: el trinquete no sirve si nadie lo mira. Mismo molde que el de la
-- auditoria de la F1.4/F1.6 (no hay event triggers: `postgres` no es
-- superusuario aqui). Deja constancia en `crm.audit_log` cuando encuentra algo.
create or replace function private.vigia_analista_vigencia()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_veredicto text;
begin
  begin
    v_veredicto := private.assert_analista_vigencia();
  exception when others then
    insert into crm.audit_log (tabla, operacion, registro_id, datos_nuevos, usuario_id)
    values ('private.analista_vigencia', 'alerta', gen_random_uuid(),
            jsonb_build_object('motivo', sqlerrm), null);
    return;
  end;
end;
$function$;

revoke all on function private.vigia_analista_vigencia() from public;

do $$
declare v_jobid bigint;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('crm-vigencia-analista-vigia')
      where exists (select 1 from cron.job where jobname = 'crm-vigencia-analista-vigia');
    v_jobid := cron.schedule('crm-vigencia-analista-vigia', '39 6 * * *',
                             'select private.vigia_analista_vigencia()');
    if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = 'crm.purgar_membresia_crm(uuid,text)'::regprocedure
       and a.privilege_type = 'EXECUTE'
       and a.grantee in (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid)
  ) then
    raise exception 'F5.a postflight: la puerta de purga quedo al alcance de una sesion de persona';
  end if;

  if not exists (select 1 from cron.job where jobname = 'crm-vigencia-analista-vigia' and active) then
      raise exception 'F5.a: el vigia no quedo activo';
    end if;
  else
    raise exception 'F5.a: falta pg_cron y el trinquete se quedaria sin vigia';
  end if;
end $$;

-- =====================================================================
-- 7) POSTFLIGHT: por FORMA, por HUELLA y por PERMISO.
-- =====================================================================
do $$
declare
  v_esperado constant text[][] := array[
    array['public','contratos',       'contratos_analista_select', 'r'],
    array['public','cronograma_pagos','cronograma_analista_select','r'],
    array['public','perfiles',        'perfiles_analista_select',  'r'],
    array['public','perfiles',        'perfiles_analista_update',  'w']
  ];
  v_fila text[]; v_using text; v_check text; v_cmd "char"; v_perm boolean; v_roles text;
  v_veredicto text; v_n integer;
begin
  foreach v_fila slice 1 in array v_esperado loop
    select coalesce(pg_get_expr(pol.polqual, pol.polrelid), ''),
           coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), ''),
           pol.polcmd, pol.polpermissive, pol.polroles::regrole[]::text
      into v_using, v_check, v_cmd, v_perm, v_roles
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = v_fila[1] and c.relname = v_fila[2] and pol.polname = v_fila[3];
    if not found then
      raise exception 'F5.a postflight: desaparecio la politica %.%', v_fila[2], v_fila[3];
    end if;
    if v_using !~ 'es_analista_vigente' then
      raise exception 'F5.a postflight: %.% no pregunta por la vigencia', v_fila[2], v_fila[3];
    end if;
    -- Y la pregunta CRUDA tiene que haber desaparecido de las dos mitades.
    if (v_using || ' ' || v_check) ~ '\mes_analista\s*\(' then
      raise exception 'F5.a postflight: %.% conserva la pregunta cruda', v_fila[2], v_fila[3];
    end if;
    if v_fila[4] = 'w' and v_check !~ 'es_analista_vigente' then
      raise exception 'F5.a postflight: %.% no lleva la vigencia en el with check', v_fila[2], v_fila[3];
    end if;
    if v_cmd::text is distinct from v_fila[4] or not v_perm or v_roles is distinct from '{authenticated}' then
      raise exception 'F5.a postflight: %.% cambio de tipo, de permissive o de roles', v_fila[2], v_fila[3];
    end if;
  end loop;

  -- Las 3 funciones convertidas: preguntan la nueva y NO conservan la cruda.
  select count(*) into v_n
    from pg_proc p
   where p.oid in ('crm.cliente_detalle_fn(uuid)'::regprocedure,
                   'public.puede_ver_contrato(uuid)'::regprocedure,
                   'public.productos_inversion_seleccion_fn(uuid)'::regprocedure)
     and p.prosrc ~ 'es_analista_vigente\s*\('
     and regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g') !~ '\mes_analista\s*\(';
  if v_n <> 3 then
    raise exception 'F5.a postflight: solo % de 3 funciones quedaron convertidas del todo', v_n;
  end if;

  -- Permisos, por el ACL de verdad (`proacl` NULL significa "PUBLIC por
  -- defecto", no "sin permisos") y resolviendo por identidad exacta.
  if not exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = 'private.es_analista_vigente()'::regprocedure
       and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::regrole::oid
  ) then
    raise exception 'F5.a postflight: authenticated no puede ejecutar es_analista_vigente: las politicas reventarian con 42501';
  end if;

  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid in ('private.es_analista_vigente()'::regprocedure,
                     'private.membresia_crm_revocada()'::regprocedure,
                     'private.assert_analista_vigencia()'::regprocedure,
                     'private.puertas_analista_sin_vigencia()'::regprocedure)
       and a.privilege_type = 'EXECUTE'
       and a.grantee in (0, 'anon'::regrole::oid)
  ) then
    raise exception 'F5.a postflight: alguna funcion de la fase quedo abierta a PUBLIC o a anon';
  end if;

  -- Las dos tablas nuevas, con seguridad por filas (deny-by-default).
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'private'
         and c.relname in ('analista_vigencia_exenciones','analista_vigencia_tope')
         and c.relrowsecurity) <> 2 then
    raise exception 'F5.a postflight: las tablas del trinquete quedaron sin seguridad por filas';
  end if;

  -- El candado del borrado: activo, BEFORE, por fila.
  if not exists (
    select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'crm' and c.relname = 'equipo' and t.tgname = 'trg_equipo_no_borrar'
       and t.tgenabled in ('O','A') and (t.tgtype & 1) = 1 and (t.tgtype & 8) = 8
  ) then
    raise exception 'F5.a postflight: el candado del borrado de crm.equipo no quedo activo BEFORE DELETE por fila';
  end if;

  if not exists (select 1 from cron.job where jobname = 'crm-vigencia-analista-vigia' and active) then
    raise exception 'F5.a postflight: el vigia diario del trinquete no quedo activo';
  end if;

  -- Y el trinquete, ejecutado de verdad.
  select private.assert_analista_vigencia() into v_veredicto;
  if v_veredicto not like 'OK:%' then
    raise exception 'F5.a postflight: el trinquete no dio OK: %', v_veredicto;
  end if;
end $$;

commit;
$mig_f5_a$]
)
on conflict (version) do update set statements = excluded.statements, name = excluded.name;

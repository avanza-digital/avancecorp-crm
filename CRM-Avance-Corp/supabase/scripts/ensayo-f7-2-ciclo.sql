begin;
-- ENSAYO DEL CICLO COMPLETO DE LA F7.2: migracion → registrador → marcha atras.
-- Todo contra produccion, deshecho al final.
set local lock_timeout = '5s';
set local statement_timeout = '300s';

-- ACTO 1: la migracion
-- P-055 F7.2 — CERRAR EL INTERRUPTOR DE LA COMPATIBILIDAD LEGACY.
--
-- Pieza: `crm.cerrar_altas_legacy_productos(bigint)`. Decision de Miguel el
-- 2026-09-01: «si no lo necesitamos se elimina; el objetivo es ir limpiando».
-- Entra al metodo por la puerta de siempre: CERRAR con llave hoy → OBSERVAR
-- 14 dias → DERRIBAR el 15/09. No se borra de golpe.
--
-- POR QUE SOBRA — medido contra produccion el 01/09:
--  * El unico «producto» del catalogo es `HISTORICO-SIN-CATALOGO`, archivado y
--    marcado `es_legacy`, con `permite_altas_legacy = true`. Las 568
--    condiciones son TODAS legacy (cero normales) y los 492 contratos cuelgan
--    de ahi: el catalogo nunca llego a usarse de verdad, y todo el CRM crea
--    contratos en «modo compatibilidad» desde el 08/08.
--  * Esta funcion es el INTERRUPTOR que apagaria ese modo. Si se ejecutara,
--    dejarian de poder crearse contratos.
--  * Hoy NO PUEDE ejecutarse: su propio cuerpo exige una condicion no-legacy
--    publicada y vigente, y no hay ninguna. Aborta siempre con 23514.
--  * Nunca se uso (el interruptor sigue abierto: `permite_altas_legacy` true,
--    revision 1) y NINGUNA pantalla la dispara: existe el envoltorio
--    `cerrarCompatibilidadLegacyProductos` en `app/src/data/crm-config-api.ts`
--    pero ningun componente lo importa. Codigo muerto en las dos puntas.
--
-- 🔑 Y ADEMAS DESBLOQUEA LA OLA 2: esta funcion NOMBRA a tres de las siete
--    gemelas (y al selector publico) por `to_regprocedure` para comprobar que
--    existen. Cerrarla ahora la convierte en referencia INERTE — no puede
--    ejecutarse — y deja el camino limpio para demolerlas el 13/09.
--
-- Lo que NO toca esta migracion: el catalogo de condiciones, sus tres tablas,
-- la columna `producto_condicion_id`, su FK ni el trigger de snapshot. Eso es
-- infraestructura VIVA del cierre de ventas (18 personas la mueven a diario) y
-- Miguel decidio el 01/09 que no se toca.
--
-- Publicacion (Miguel, con `!`): esta migracion → registrar-f7-2-version.sql →
-- gates → advisors. Marcha atras: `scripts/rollback-f7-2-p055.sql`.

-- [ensayo]

-- =====================================================================
-- 0) PREFLIGHT.
-- =====================================================================
do $f72_pre$
declare v_h text; v_acl text; v_n int; v_permite boolean;
begin
  -- (a) Es la pieza que medi, con su cuerpo exacto.
  select md5(p.prosrc), p.proacl::text into v_h, v_acl
  from pg_proc p where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_h is null then
    raise exception 'F7.2 preflight: la funcion no existe';
  end if;
  if v_h is distinct from '9dd26612ef8efefb54db115141d923c5' then
    raise exception 'F7.2 preflight: la funcion cambio desde la medicion (huella %)', v_h;
  end if;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'F7.2 preflight: ACL inesperado: %', v_acl;
  end if;

  -- (b) EL MUNDO QUE JUSTIFICA CERRARLA: sigue sin condiciones no-legacy, asi
  --     que la funcion sigue siendo inejecutable. Si algun dia se publicara un
  --     producto de verdad, esta migracion ABORTA y se decide de nuevo.
  select count(*) into v_n from crm.producto_condiciones where not es_legacy;
  if v_n <> 0 then
    raise exception 'F7.2 preflight: hay % condicion(es) NO legacy — el catalogo empezo a usarse de verdad; decidir con Miguel antes de cerrar su interruptor', v_n;
  end if;
  select p.permite_altas_legacy into v_permite from crm.productos_inversion p where p.es_legacy;
  if v_permite is distinct from true then
    raise exception 'F7.2 preflight: la compatibilidad legacy YA esta cerrada — el mundo no es el que esta migracion asume';
  end if;

  -- (c) Nadie la llama desde el servidor.
  select count(*) into v_n from pg_proc p
   where p.oid <> 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure
     and p.pronamespace in ('crm'::regnamespace,'public'::regnamespace,'private'::regnamespace)
     and strpos(lower(p.prosrc), 'cerrar_altas_legacy_productos') > 0;
  if v_n > 0 then
    raise exception 'F7.2 preflight: % cuerpo(s) vivo(s) la llaman', v_n;
  end if;

  -- (d) STOP-THE-LINE.
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'F7.2 preflight: % alerta(s) del vigia sin resolver', v_n;
  end if;
end $f72_pre$;

-- =====================================================================
-- 1) CERRAR CON LLAVE. `authenticated` pierde el EXECUTE; queda solo su dueño.
-- =====================================================================
revoke execute on function crm.cerrar_altas_legacy_productos(bigint) from authenticated, anon, public;

-- =====================================================================
-- 2) EL ACTA: entra al libro con su ventana de 14 dias (demolible el 15/09).
-- =====================================================================
insert into private.f7_piezas_en_observacion (
  firma, huella_md5, acl_esperada, llamadores_permitidos, patron_censo,
  ola, estado, cerrada_en, drop_no_antes_de, ok_miguel, nota
) values (
  'crm.cerrar_altas_legacy_productos(bigint)',
  '9dd26612ef8efefb54db115141d923c5',
  '{postgres=X/postgres}',
  '{}',
  'cerrar_altas_legacy_productos',
  'F7.2',
  'observacion',
  (now() at time zone 'America/Lima')::date,
  (now() at time zone 'America/Lima')::date + 14,
  'Miguel el 01/09: «si no lo necesitamos se elimina; el objetivo es ir limpiando». Medido: el interruptor nunca se uso, hoy es inejecutable (cero condiciones no-legacy) y ninguna pantalla lo dispara.',
  'Interruptor de un solo uso hacia un catalogo real que nunca llego. Si se ejecutara, apagaria las altas en modo compatibilidad y NADIE podria crear contratos. Nombra 3 de las 7 gemelas por to_regprocedure: cerrarla las desbloquea para el 13/09.'
);

-- =====================================================================
-- 3) POSTFLIGHT.
-- =====================================================================
do $f72_post$
declare v_n int; v_verd text; v_acl text;
begin
  select p.proacl::text into v_acl from pg_proc p
   where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres}' then
    raise exception 'F7.2 postflight: el ACL no quedo cerrado al literal: %', v_acl;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.cerrar_altas_legacy_productos(bigint)' and estado = 'observacion';
  if v_n <> 1 then
    raise exception 'F7.2 postflight: el libro no tiene su acta (filas: %)', v_n;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion;
  if v_n <> 15 then
    raise exception 'F7.2 postflight: el libro tiene % piezas, esperaba 15', v_n;
  end if;

  -- El catalogo de condiciones sigue INTACTO: esto no lo toca.
  select count(*) into v_n from crm.producto_condiciones;
  if v_n < 568 then
    raise exception 'F7.2 postflight: las condiciones bajaron a % — esta migracion no debia tocarlas', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'F7.2 postflight: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'F7.2 postflight: analitica en rojo: %', v_verd; end if;
  select private.assert_analista_vigencia() into v_verd;
  if v_verd not like 'OK%' then raise exception 'F7.2 postflight: vigencia en rojo: %', v_verd; end if;
end $f72_post$;

-- [ensayo]

-- ACTO 2: el registrador (debe registrar la version y pasar su relectura)
-- REGISTRADOR de la F7.2 — inserta la version 20260901200000 en el registro
-- SOLO si el mundo vivo ES el post-F7.2. Patron de los registradores de ATR:
-- pines + relectura fail-closed post-insert. `!` de Miguel, tras la migracion.
-- [ensayo]

do $reg_f72$
declare v_acl text; v_n int; v_cuerpo text;
begin
  -- 1) El interruptor esta CERRADO de verdad (esto es lo que la migracion hizo).
  select p.proacl::text into v_acl from pg_proc p
   where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres}' then
    raise exception 'registrar F7.2: el interruptor NO esta cerrado (ACL %) — no se registra lo que no esta vivo', v_acl;
  end if;

  -- 2) Su acta esta en el libro, en observacion y con ventana.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.cerrar_altas_legacy_productos(bigint)'
     and estado = 'observacion' and drop_no_antes_de is not null;
  if v_n <> 1 then
    raise exception 'registrar F7.2: el libro no tiene su acta (filas %)', v_n;
  end if;

  v_cuerpo := $mig_f72$-- P-055 F7.2 — CERRAR EL INTERRUPTOR DE LA COMPATIBILIDAD LEGACY.
--
-- Pieza: `crm.cerrar_altas_legacy_productos(bigint)`. Decision de Miguel el
-- 2026-09-01: «si no lo necesitamos se elimina; el objetivo es ir limpiando».
-- Entra al metodo por la puerta de siempre: CERRAR con llave hoy → OBSERVAR
-- 14 dias → DERRIBAR el 15/09. No se borra de golpe.
--
-- POR QUE SOBRA — medido contra produccion el 01/09:
--  * El unico «producto» del catalogo es `HISTORICO-SIN-CATALOGO`, archivado y
--    marcado `es_legacy`, con `permite_altas_legacy = true`. Las 568
--    condiciones son TODAS legacy (cero normales) y los 492 contratos cuelgan
--    de ahi: el catalogo nunca llego a usarse de verdad, y todo el CRM crea
--    contratos en «modo compatibilidad» desde el 08/08.
--  * Esta funcion es el INTERRUPTOR que apagaria ese modo. Si se ejecutara,
--    dejarian de poder crearse contratos.
--  * Hoy NO PUEDE ejecutarse: su propio cuerpo exige una condicion no-legacy
--    publicada y vigente, y no hay ninguna. Aborta siempre con 23514.
--  * Nunca se uso (el interruptor sigue abierto: `permite_altas_legacy` true,
--    revision 1) y NINGUNA pantalla la dispara: existe el envoltorio
--    `cerrarCompatibilidadLegacyProductos` en `app/src/data/crm-config-api.ts`
--    pero ningun componente lo importa. Codigo muerto en las dos puntas.
--
-- 🔑 Y ADEMAS DESBLOQUEA LA OLA 2: esta funcion NOMBRA a tres de las siete
--    gemelas (y al selector publico) por `to_regprocedure` para comprobar que
--    existen. Cerrarla ahora la convierte en referencia INERTE — no puede
--    ejecutarse — y deja el camino limpio para demolerlas el 13/09.
--
-- Lo que NO toca esta migracion: el catalogo de condiciones, sus tres tablas,
-- la columna `producto_condicion_id`, su FK ni el trigger de snapshot. Eso es
-- infraestructura VIVA del cierre de ventas (18 personas la mueven a diario) y
-- Miguel decidio el 01/09 que no se toca.
--
-- Publicacion (Miguel, con `!`): esta migracion → registrar-f7-2-version.sql →
-- gates → advisors. Marcha atras: `scripts/rollback-f7-2-p055.sql`.

begin;


-- =====================================================================
-- 0) PREFLIGHT.
-- =====================================================================
do $f72_pre$
declare v_h text; v_acl text; v_n int; v_permite boolean;
begin
  -- (a) Es la pieza que medi, con su cuerpo exacto.
  select md5(p.prosrc), p.proacl::text into v_h, v_acl
  from pg_proc p where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_h is null then
    raise exception 'F7.2 preflight: la funcion no existe';
  end if;
  if v_h is distinct from '9dd26612ef8efefb54db115141d923c5' then
    raise exception 'F7.2 preflight: la funcion cambio desde la medicion (huella %)', v_h;
  end if;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'F7.2 preflight: ACL inesperado: %', v_acl;
  end if;

  -- (b) EL MUNDO QUE JUSTIFICA CERRARLA: sigue sin condiciones no-legacy, asi
  --     que la funcion sigue siendo inejecutable. Si algun dia se publicara un
  --     producto de verdad, esta migracion ABORTA y se decide de nuevo.
  select count(*) into v_n from crm.producto_condiciones where not es_legacy;
  if v_n <> 0 then
    raise exception 'F7.2 preflight: hay % condicion(es) NO legacy — el catalogo empezo a usarse de verdad; decidir con Miguel antes de cerrar su interruptor', v_n;
  end if;
  select p.permite_altas_legacy into v_permite from crm.productos_inversion p where p.es_legacy;
  if v_permite is distinct from true then
    raise exception 'F7.2 preflight: la compatibilidad legacy YA esta cerrada — el mundo no es el que esta migracion asume';
  end if;

  -- (c) Nadie la llama desde el servidor.
  select count(*) into v_n from pg_proc p
   where p.oid <> 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure
     and p.pronamespace in ('crm'::regnamespace,'public'::regnamespace,'private'::regnamespace)
     and strpos(lower(p.prosrc), 'cerrar_altas_legacy_productos') > 0;
  if v_n > 0 then
    raise exception 'F7.2 preflight: % cuerpo(s) vivo(s) la llaman', v_n;
  end if;

  -- (d) STOP-THE-LINE.
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'F7.2 preflight: % alerta(s) del vigia sin resolver', v_n;
  end if;
end $f72_pre$;

-- =====================================================================
-- 1) CERRAR CON LLAVE. `authenticated` pierde el EXECUTE; queda solo su dueño.
-- =====================================================================
revoke execute on function crm.cerrar_altas_legacy_productos(bigint) from authenticated, anon, public;

-- =====================================================================
-- 2) EL ACTA: entra al libro con su ventana de 14 dias (demolible el 15/09).
-- =====================================================================
insert into private.f7_piezas_en_observacion (
  firma, huella_md5, acl_esperada, llamadores_permitidos, patron_censo,
  ola, estado, cerrada_en, drop_no_antes_de, ok_miguel, nota
) values (
  'crm.cerrar_altas_legacy_productos(bigint)',
  '9dd26612ef8efefb54db115141d923c5',
  '{postgres=X/postgres}',
  '{}',
  'cerrar_altas_legacy_productos',
  'F7.2',
  'observacion',
  (now() at time zone 'America/Lima')::date,
  (now() at time zone 'America/Lima')::date + 14,
  'Miguel el 01/09: «si no lo necesitamos se elimina; el objetivo es ir limpiando». Medido: el interruptor nunca se uso, hoy es inejecutable (cero condiciones no-legacy) y ninguna pantalla lo dispara.',
  'Interruptor de un solo uso hacia un catalogo real que nunca llego. Si se ejecutara, apagaria las altas en modo compatibilidad y NADIE podria crear contratos. Nombra 3 de las 7 gemelas por to_regprocedure: cerrarla las desbloquea para el 13/09.'
);

-- =====================================================================
-- 3) POSTFLIGHT.
-- =====================================================================
do $f72_post$
declare v_n int; v_verd text; v_acl text;
begin
  select p.proacl::text into v_acl from pg_proc p
   where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres}' then
    raise exception 'F7.2 postflight: el ACL no quedo cerrado al literal: %', v_acl;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.cerrar_altas_legacy_productos(bigint)' and estado = 'observacion';
  if v_n <> 1 then
    raise exception 'F7.2 postflight: el libro no tiene su acta (filas: %)', v_n;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion;
  if v_n <> 15 then
    raise exception 'F7.2 postflight: el libro tiene % piezas, esperaba 15', v_n;
  end if;

  -- El catalogo de condiciones sigue INTACTO: esto no lo toca.
  select count(*) into v_n from crm.producto_condiciones;
  if v_n < 568 then
    raise exception 'F7.2 postflight: las condiciones bajaron a % — esta migracion no debia tocarlas', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'F7.2 postflight: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'F7.2 postflight: analitica en rojo: %', v_verd; end if;
  select private.assert_analista_vigencia() into v_verd;
  if v_verd not like 'OK%' then raise exception 'F7.2 postflight: vigencia en rojo: %', v_verd; end if;
end $f72_post$;

-- [ensayo]
$mig_f72$;

  -- 3) Si ya existe: muda => abortar; cuerpo distinto => abortar.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260901200000' and statements is null;
  if v_n > 0 then
    raise exception 'registrar F7.2: la version existe MUDA — repararla, no pisarla';
  end if;
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260901200000' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar F7.2: la version existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260901200000', 'crm_f7_2_cerrar_el_interruptor_legacy', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260901200000'
     and name = 'crm_f7_2_cerrar_el_interruptor_legacy'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar F7.2: la relectura no encontro la fila exacta';
  end if;
end $reg_f72$;

select '20260901200000 registrada: el interruptor legacy cerrado y en el libro' as resultado,
       (select count(*) from supabase_migrations.schema_migrations) as versiones,
       (select count(*) from private.f7_piezas_en_observacion) as piezas_en_el_libro;
-- [ensayo]

do $v1$
declare v_n int;
begin
  select count(*) into v_n from supabase_migrations.schema_migrations where version='20260901200000';
  if v_n <> 1 then raise exception 'ENSAYO: la version no quedo registrada'; end if;
  raise notice 'ACTO 2 OK: registrada';
end $v1$;

-- ACTO 3: la marcha atras
-- MARCHA ATRAS de la F7.2 — reabre el interruptor legacy y retira su acta.
--
-- ⚠️ La fila 20260901200000 del registro NO se borra aqui: retirarla A MANO.
-- ⚠️ Reabrir el interruptor NO lo vuelve peligroso: sigue siendo inejecutable
--    mientras no exista una condicion de producto no-legacy publicada.

-- [ensayo]

do $rb_pre$
declare v_acl text; v_n int;
begin
  select p.proacl::text into v_acl from pg_proc p
   where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres}' then
    raise exception 'rollback F7.2: el interruptor no esta como lo dejo la F7.2 (ACL %)', v_acl;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.cerrar_altas_legacy_productos(bigint)' and estado = 'observacion';
  if v_n <> 1 then
    raise exception 'rollback F7.2: su acta no esta en observacion — el mundo no es el que este guion revierte';
  end if;
end $rb_pre$;

grant execute on function crm.cerrar_altas_legacy_productos(bigint) to authenticated;

-- Retirar el acta: el trigger `no_borrar` lo prohibe salvo con el candado
-- NOMBRADO bajado (doctrina limpieza-leads), y se vuelve a subir aqui mismo.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_01_no_borrar;
delete from private.f7_piezas_en_observacion
 where firma = 'crm.cerrar_altas_legacy_productos(bigint)';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_01_no_borrar;

do $rb_post$
declare v_acl text; v_n int; v_verd text;
begin
  select p.proacl::text into v_acl from pg_proc p
   where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'rollback F7.2: el ACL no volvio al original (%)', v_acl;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion;
  if v_n <> 14 then
    raise exception 'rollback F7.2: el libro tiene % piezas, esperaba 14', v_n;
  end if;
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F7.2: vigilante F7 en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-F7.2-OK: interruptor reabierto y acta retirada' as resultado;
-- [ensayo]

-- ACTO 4: veredicto — el mundo volvio a como estaba (salvo la fila del
-- registro, que por doctrina se retira A MANO).
do $v2$
declare v_acl text; v_n int;
begin
  select p.proacl::text into v_acl from pg_proc p
   where p.oid='crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'ENSAYO: el ACL no volvio (%)' , v_acl;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion;
  if v_n <> 14 then raise exception 'ENSAYO: el libro tiene % piezas, esperaba 14', v_n; end if;
end $v2$;

select 'F7.2-CICLO-VERDE' as resultado;
rollback;

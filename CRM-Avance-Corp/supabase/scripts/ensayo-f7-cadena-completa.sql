begin;
-- =====================================================================
-- ENSAYO DE LA FASE 7 COMPLETA — contra PRODUCCION, deshecho al final.
-- =====================================================================
-- ACTO 1  cerrar el interruptor legacy (F7.2), con fechas REALES.
-- ACTO 2  MUTANTE DEL CANDADO: la Ola 2 debe ABORTAR hoy (01/09) porque las
--         gemelas no cumplen su ventana. Si NO aborta, el trinquete no sirve.
-- ACTO 3  viaje en el tiempo, declarado: se retira el CHECK de la ventana SOLO
--         dentro de esta transaccion que aborta. En produccion queda intacto.
-- ACTOS 4-5  demoler las 7 gemelas y los 3 tableros.
-- ACTOS 6-7  las dos marchas atras recrean todo AL BYTE.
-- Nada persiste: termina en rollback.
set local lock_timeout = '5s';
set local statement_timeout = '600s';

-- ---------- ACTO 1 ----------
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

-- [ensayo] begin

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

-- [ensayo] commit

-- ---------- ACTO 2: el candado DEBE abortar hoy ----------
do $mutante$
declare v_hoy date; v_n int;
begin
  v_hoy := (now() at time zone 'America/Lima')::date;
  select count(*) into v_n
  from private.f7_piezas_en_observacion f
  where f.estado='observacion' and f.ola='F5.d'
    and (f.drop_no_antes_de is null or f.drop_no_antes_de::date > v_hoy);
  if v_n <> 7 then
    raise exception 'MUTANTE FALLIDO: hoy (%) las 7 gemelas deberian estar DENTRO de su ventana; el preflight de la Ola 2 no las frenaria (fuera de ventana: %)', v_hoy, v_n;
  end if;
  raise notice 'ACTO 2 OK: el candado frena las 7 gemelas hoy (%). El trinquete sirve.', v_hoy;
end $mutante$;

-- ---------- ACTO 3: viaje en el tiempo, solo aqui ----------
alter table private.f7_piezas_en_observacion drop constraint f7_obs_ventana;
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set drop_no_antes_de = (now() at time zone 'America/Lima')::date - 1
 where estado = 'observacion' and ola in ('F5.d','F7.1');
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- ---------- ACTO 4: demoler las 7 gemelas ----------
-- P-055 F7 · OLA 2 — DEMOLER LAS SIETE GEMELAS DEL CATALOGO VIEJO.
--
-- Tercer paso del metodo de Miguel: CERRAR (F5.d, 30/08, registro 186) →
-- OBSERVAR (14 dias) → DERRIBAR. Las siete llevan revocadas desde el 30/08:
-- nadie puede llamarlas, y su intento muere en 42501 antes del cuerpo.
--
-- ⛔ NO SE PUEDE APLICAR ANTES DEL 2026-09-13. No es disciplina: el libro
--    guarda `drop_no_antes_de` por fila y el preflight lo exige. Si se corre
--    antes, ABORTA — y esta bien que aborte.
--
-- MATERIAL DE MARCHA ATRAS: `scripts/rollback-f7-ola2-gemelas.sql` recrea las
-- siete con su DEFINICION VIVA capturada de produccion el 01/09 (owner, ACL y
-- atributos incluidos). El repo tiene 167 de 193 archivos y la F5.d cambio sus
-- cuerpos despues de nacer: la fuente es el REGISTRO y el catalogo vivo, jamas
-- la carpeta local.
--
-- ARTEFACTOS (leccion de la auditoria de Codex del 01/09): el oraculo
-- `scripts/test-productos-inversion.sql` NO se retira — es parte de
-- `gate:config` y prueba tambien snapshots, inmutabilidad, seleccion y ACL. Se
-- PODA aparte. Los mocks e2e comparten ramas con los endpoints PDF VIVOS.
--
-- Publicacion (Miguel, con `!`): esta migracion → registrar-f7-ola2-version.sql
-- → gates → advisors.

-- [ensayo] begin

-- =====================================================================
-- 0) PREFLIGHT: la ventana, el libro, el vigia y las huellas.
-- =====================================================================
do $ola2_pre$
declare
  v_fn constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', '8640b1246f620ab40558cec2875ada23'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', '4156191492c25479be73b0365263d946'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', '06f79b07b4d65dcf50cd4359fb598723'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)', '1148d0ca1beb33797995eeff3c579bd4'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'b7e0de18b559ec7fd650619cd22b9cb5'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'f0e519cc4ee79c9334ae59a23844b23b'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)', '893c857e27ec6405a3ac6e291458c346']
  ];
  v_fila text[]; v_h text; v_n int; v_hoy date;
  v_firmas constant text[] := array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', 'crm.crear_contrato_producto(uuid,jsonb,jsonb)', 'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'public.crear_contrato_producto(uuid,jsonb,jsonb)'];
begin
  -- (a) LA VENTANA. Cada pieza trae su fecha en el libro; ninguna se adelanta.
  v_hoy := (now() at time zone 'America/Lima')::date;
  select count(*) into v_n
  from private.f7_piezas_en_observacion f
  where f.estado = 'observacion' and f.ola = 'F5.d'
    and (f.drop_no_antes_de is null or f.drop_no_antes_de::date > v_hoy);
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % pieza(s) todavia en su ventana de observacion (hoy % en Lima). NO se adelanta el trinquete.', v_n, v_hoy;
  end if;

  -- (b) EL LIBRO: las 7, en observacion, con su OK escrito.
  select count(*) into v_n
  from private.f7_piezas_en_observacion f
  where f.ola = 'F5.d' and f.estado = 'observacion' and length(f.ok_miguel) >= 20;
  if v_n <> 7 then
    raise exception 'OLA 2 preflight: esperaba 7 gemelas en observacion con OK, hay %', v_n;
  end if;

  -- (c) STOP-THE-LINE: ninguna alerta abierta del vigia. Si hay una, se PARA
  --     y se atiende FUERA de este paquete destructivo (nunca dentro).
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: hay % alerta(s) del vigia sin resolver. Stop-the-line: se atienden ANTES y en otro paquete.', v_n;
  end if;

  -- (d) SON LAS QUE CREO: huella viva == huella capturada el 01/09.
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is null then
      raise exception 'OLA 2 preflight: % ya no existe — investigar antes de seguir', v_fila[1];
    end if;
    if v_h is distinct from v_fila[2] then
      raise exception 'OLA 2 preflight: % cambio de cuerpo desde la captura (huella %)', v_fila[1], v_h;
    end if;
  end loop;

  -- (e) SIGUEN CERRADAS: ni una tiene EXECUTE fuera de postgres.
  select count(*) into v_n
  from pg_proc p, aclexplode(p.proacl) a
  where p.oid = any (array(select f::regprocedure from unnest(v_firmas) f))
    and a.grantee <> 'postgres'::regrole and a.privilege_type = 'EXECUTE';
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % permiso(s) EXECUTE reaparecieron — alguien las reabrio', v_n;
  end if;

  -- (f) NADIE VIVO LAS NOMBRA. `cerrar_altas_legacy_productos` las nombraba por
  --     `to_regprocedure`, y por eso se cerro antes en la F7.2 (01/09) con su
  --     propia acta: una pieza CERRADA CON LLAVE no puede ejecutarse, asi que su
  --     referencia es INERTE y no bloquea. Lo que si bloquea es un cuerpo vivo
  --     y alcanzable — eso es lo que se cuenta aqui.
  select count(*) into v_n
  from pg_proc p, unnest(v_firmas) f
  where p.oid <> f::regprocedure
    and p.pronamespace in ('crm'::regnamespace,'public'::regnamespace,'private'::regnamespace)
    and strpos(lower(p.prosrc), lower(split_part(f,'(',1))) > 0
    -- exentas: las que ya estan en el libro cerradas o demolidas (inertes)
    and not exists (
      select 1 from private.f7_piezas_en_observacion lib
      where lib.firma = p.oid::regprocedure::text
        and lib.estado in ('observacion','cerrada_permanente','demolida'))
  ;
  if v_n > 0 then
    raise exception 'OLA 2 preflight: % cuerpo(s) VIVO(s) y alcanzable(s) todavia nombran a las gemelas — resolverlos primero', v_n;
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
-- =====================================================================
update private.f7_piezas_en_observacion
   set estado = 'demolida',
       -- El trigger `solo_crece` EXIGE rastro al cambiar de estado: quien y por que.
       nota = coalesce(nota,'') || ' | DEMOLIDA por la OLA 2 (migracion '
              || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || ', `!` de Miguel): ventana de observacion cumplida, cero alertas del vigia,'
              || ' huella verificada contra la captura del 01/09 y marcha atras recreadora ensayada.'
 where ola = 'F5.d' and estado = 'observacion';

-- =====================================================================
-- 3) POSTFLIGHT: se fueron las 7, no se fue nada mas, y el libro cuadra.
-- =====================================================================
do $ola2_post$
declare v_n int; v_verd text;
begin
  select count(*) into v_n from pg_proc p
   where p.pronamespace in ('crm'::regnamespace,'public'::regnamespace)
     and p.proname in ('crear_contrato_producto','actualizar_contrato_producto',
                       'crear_contrato_con_cuenta_producto','actualizar_contrato_con_cuenta_producto');
  if v_n <> 0 then
    raise exception 'OLA 2 postflight: quedan % gemelas vivas', v_n;
  end if;

  -- Las piezas VIVAS del contrato siguen en pie (no se llevo nada por delante).
  if to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)') is null
     and to_regprocedure('crm.crear_contrato_con_cuenta_pdf(jsonb,jsonb,jsonb)') is null then
    raise exception 'OLA 2 postflight: no encuentro la puerta VIVA de alta de contratos';
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and estado = 'demolida';
  if v_n <> 7 then
    raise exception 'OLA 2 postflight: el libro marca % demolidas, esperaba 7', v_n;
  end if;
  -- Nada de la F5.d queda en observacion (se cuenta POR OLA a proposito: el
  -- libro crece con cohortes nuevas y un total fijo se rompe solo).
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and estado = 'observacion';
  if v_n <> 0 then
    raise exception 'OLA 2 postflight: quedan % gemelas en observacion', v_n;
  end if;
  -- Y no se toco ninguna otra cohorte.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola <> 'F5.d' and estado = 'demolida';
  if v_n <> 0 then
    raise exception 'OLA 2 postflight: % pieza(s) de OTRA ola quedaron marcadas demolidas', v_n;
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

-- [ensayo] commit

-- ---------- ACTO 5: demoler los 3 tableros ----------
-- P-055 F7 · OLA 2b — DEMOLER EL TABLERO DE ALTAS POR ANALISTA.
--
-- Cierre parcial de la cohorte de la Ola 1 (F7.1, cerrada el 31/08, registro
-- 191). ⛔ NO ANTES DEL 2026-09-14 (su `drop_no_antes_de`).
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
--    cerradas y en observacion; su demolicion queda como DEUDA DECLARADA hasta
--    tener una via con permisos para restaurar el dueño (panel de Supabase o
--    conexion directa con superusuario).
--
-- 🔴 `metricas_altas_analista_fn` NO tiene archivo en el repo: su partida de
--    nacimiento vive en el registro remoto (version 20260716203331). El
--    material de marcha atras es la CAPTURA VIVA del 01/09, en
--    `scripts/rollback-f7-ola2b-tableros.sql`.
--
-- Publicacion (Miguel, con `!`): migracion → registrar-f7-ola2b-version.sql →
-- gates → advisors.

-- [ensayo] begin

do $ola2b_pre$
declare
  v_firma constant text := 'crm.metricas_altas_analista_fn(integer)';
  v_huella constant text := 'df8a99e0dfc4e1d94794073787aa84d7';
  v_h text; v_n int; v_hoy date;
begin
  v_hoy := (now() at time zone 'America/Lima')::date;
  select f.drop_no_antes_de::date into v_hoy
  from private.f7_piezas_en_observacion f where f.firma = v_firma;
  if v_hoy is null or v_hoy > (now() at time zone 'America/Lima')::date then
    raise exception 'OLA 2b preflight: % sigue en su ventana (demolible desde %)', v_firma, v_hoy;
  end if;

  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = v_firma and estado = 'observacion' and length(ok_miguel) >= 20;
  if v_n <> 1 then
    raise exception 'OLA 2b preflight: % no esta en observacion con su OK', v_firma;
  end if;

  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % alerta(s) del vigia sin resolver — stop-the-line', v_n;
  end if;

  select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_firma::regprocedure;
  if v_h is distinct from v_huella then
    raise exception 'OLA 2b preflight: % cambio de cuerpo desde la captura (huella %)', v_firma, v_h;
  end if;

  select count(*) into v_n from pg_proc p, aclexplode(p.proacl) a
   where p.oid = v_firma::regprocedure
     and a.grantee <> 'postgres'::regrole and a.privilege_type = 'EXECUTE';
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % permiso(s) EXECUTE reaparecieron', v_n;
  end if;

  select count(*) into v_n from pg_proc p
   where p.oid <> v_firma::regprocedure
     and p.pronamespace in ('crm'::regnamespace,'public'::regnamespace,'private'::regnamespace)
     and strpos(lower(p.prosrc), 'metricas_altas_analista_fn') > 0
     and not exists (select 1 from private.f7_piezas_en_observacion lib
                     where lib.firma = p.oid::regprocedure::text
                       and lib.estado in ('observacion','cerrada_permanente','demolida'));
  if v_n > 0 then
    raise exception 'OLA 2b preflight: % cuerpo(s) vivo(s) la nombran', v_n;
  end if;
end $ola2b_pre$;

drop function crm.metricas_altas_analista_fn(integer);

update private.f7_piezas_en_observacion
   set estado = 'demolida',
       nota = coalesce(nota,'') || ' | DEMOLIDA por la OLA 2b (migracion '
              || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || ', `!` de Miguel): ventana cumplida, cero alertas, huella verificada'
              || ' contra la captura del 01/09 y marcha atras recreadora ensayada.'
 where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'observacion';

do $ola2b_post$
declare v_n int; v_verd text;
begin
  if to_regprocedure('crm.metricas_altas_analista_fn(integer)') is not null then
    raise exception 'OLA 2b postflight: la funcion sigue viva';
  end if;
  -- Las dos del bridge NO se tocan (deuda declarada): siguen vivas y cerradas.
  if to_regprocedure('crm.metricas_distribucion_leads_fn(date,date)') is null
     or to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)') is null then
    raise exception 'OLA 2b postflight: se demolieron las del bridge y NO debia tocarlas';
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'OLA 2b postflight: el acta no quedo escrita';
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'OLA 2b postflight: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'OLA 2b postflight: analitica en rojo: %', v_verd; end if;
  select count(*) into v_n from private.vigia_alertas where resuelta_en is null;
  if v_n > 0 then raise exception 'OLA 2b postflight: la demolicion levanto % alerta(s)', v_n; end if;
end $ola2b_post$;

-- [ensayo] commit

-- ---------- ACTO 6: marcha atras de las gemelas ----------
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

-- [ensayo] begin

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

-- Verificacion: volvieron las 7, AL BYTE, y los guardianes quedan verdes.
do $rb_post$
declare
  v_fn constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', '8640b1246f620ab40558cec2875ada23'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', '4156191492c25479be73b0365263d946'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', '06f79b07b4d65dcf50cd4359fb598723'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)', '1148d0ca1beb33797995eeff3c579bd4'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'b7e0de18b559ec7fd650619cd22b9cb5'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'f0e519cc4ee79c9334ae59a23844b23b'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)', '893c857e27ec6405a3ac6e291458c346']
  ];
  v_fila text[]; v_h text; v_verd text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'rollback F5.d: % no volvio al byte (huella %)', v_fila[1], v_h;
    end if;
  end loop;
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F5.d: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F5.d: analitica en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-F5.d-OK: las 7 piezas recreadas al byte y cerradas como estaban' as resultado;
-- [ensayo] commit

-- ---------- ACTO 7: marcha atras de los tableros ----------
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

-- [ensayo] begin

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
declare v_h text; v_verd text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'rollback OLA 2b: no volvio al byte (huella %)', v_h;
  end if;
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback OLA 2b: vigilante F7 en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-OLA2b-OK: metricas_altas_analista_fn recreada al byte y cerrada' as resultado;
-- [ensayo] commit

-- ---------- ACTO 8: veredicto ----------
do $veredicto$
declare v_n int; v_verd text;
begin
  select count(*) into v_n from private.f7_piezas_en_observacion where estado='observacion';
  if v_n <> 11 then
    raise exception 'ENSAYO: esperaba 11 en observacion tras las marchas atras (10 + el interruptor), hay %', v_n;
  end if;
  -- Las dos del bridge NUNCA se tocaron (deuda declarada).
  if to_regprocedure('crm.metricas_distribucion_leads_v2_fn(date,date)') is null then
    raise exception 'ENSAYO: se demolio una pieza del bridge y no debia tocarse';
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace in ('crm'::regnamespace,'public'::regnamespace)
     and p.proname in ('crear_contrato_producto','actualizar_contrato_producto',
                       'crear_contrato_con_cuenta_producto','actualizar_contrato_con_cuenta_producto',
                       'metricas_altas_analista_fn','metricas_distribucion_leads_fn','metricas_distribucion_leads_v2_fn');
  if v_n <> 10 then
    raise exception 'ENSAYO: tras recrear esperaba las 10 piezas vivas, hay %', v_n;
  end if;
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'ENSAYO: vigilante F7 en rojo al final: %', v_verd; end if;
  raise notice 'ENSAYO F7 OK';
end $veredicto$;

select 'F7-ENSAYO-COMPLETO-VERDE' as resultado,
       (select count(*) from private.f7_piezas_en_observacion) as piezas_en_el_libro;
rollback;

-- REGISTRO en supabase_migrations.schema_migrations de 20261013233000_crm_f7_redeclarar_huella_metricas_cartera (F7: re-declarar la huella de crm.metricas_cartera_fn).
-- GENERADO por generar_registrador.py: no editar a mano. Desde `CRM-Avance-Corp/`, en este orden:
--   1. supabase db query --linked --file supabase/migrations/20261013233000_crm_f7_redeclarar_huella_metricas_cartera.sql
--   2. supabase db query --linked --file supabase/scripts/f7-huella-metricas-cartera/registrar.sql
-- Registrado = sin error y la última fila «20261013233000 | ebf5af00995fa5816d779ae596cba8be». Un error = no registró nada (una transacción).
-- Idempotente. Se NIEGA, sin escribir, si la migración no está aplicada (huella del libro F7 distinta de 869853c2…), si el nombre
-- ya está con otra versión o si la versión ya está con otro nombre u otro contenido. statements = el archivo entero (md5 ebf5af00995fa5816d779ae596cba8be).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f7_redeclarar_huella_metricas_cartera_registro'));
create temp table registro_20261013233000 on commit drop as
select $mig$-- P-055 F7 · RE-DECLARAR LA HUELLA DE crm.metricas_cartera_fn(date)
--
-- QUE HACE. Actualiza DOS campos de UNA sola fila del libro
-- `private.f7_piezas_en_observacion` —la `huella_md5` y el rastro en `nota`— de
-- `crm.metricas_cartera_fn(date)`, de
-- 0b4ede547cf7079be1e56073311453b3 (la declarada al cerrarla, 31/08) a
-- 869853c25e903fe2f79245b8176c09b9 (la viva). No toca su estado, su ACL, su
-- ventana, su patron de censo, sus llamadores permitidos ni ninguna otra fila.
-- Mismo esqueleto que 20260924161110 (crear_contrato_con_cuenta).
--
-- POR QUE. El cuerpo de esa funcion cambio estando CERRADA y el cambio es
-- LEGITIMO: lo hizo UNA migracion aplicada, 20261012165115
-- crm_coordinacion_reportes_lectura (en produccion 20261012223850, 12/10/2026;
-- «Coordinacion: Facturacion y Ranking generales, exclusivamente lectura»,
-- aprobada por Miguel el 12/10). Medido en produccion el 13/10 (solo lectura):
--   · es la UNICA migracion desde el cierre (20260831060000) cuyos `statements`
--     nombran `function crm.metricas_cartera_fn(`;
--   · 0b4ede54… es EXACTAMENTE md5(prosrc) del cuerpo anterior (el de su reversa,
--     supabase/scripts/coordinacion-reportes/reversa.sql, definicion 0bfcc0d4…);
--   · el diff entre los dos cuerpos es UNA linea:
--       v_lector boolean := private.es_lector_global();
--     → v_lector boolean := private.es_lector_global() or private.es_coordinador_reportes();
--   · ACL {postgres=X/postgres} (sigue cerrada), dueño postgres, sin cambios.
-- Nadie actualizo la huella declarada, asi que desde el 13/10 01:59 el vigia de
-- la F7 levanta una alerta nueva cada noche (`private.vigia_alertas`, fase
-- f7_piezas_cerradas). Como el assert recorre las piezas por firma y lanza en el
-- primer fallo, este rojo puede ocultar un fallo REAL de una pieza evaluada despues
-- (Codex, 13/10, P3); el postflight corre el assert entero, asi que si hubiera otro
-- la migracion abortaria.
--
-- LO QUE NO ES. No reabre nada, no cambia permisos y no demuele. La pieza sigue
-- `cerrada_permanente` («organo interno de conversion_mensual_fn - JAMAS se
-- derriba») y su unico llamador permitido sigue siendo crm.conversion_mensual_fn.
--
-- 🔑 LA HUELLA VA EN CRUDO: `assert_f7_piezas_cerradas()` compara md5(p.prosrc).
--
-- DIFERENCIA CON EL PRECEDENTE. El postflight de 20260924161110 llamaba tambien a
-- `private.assert_analitica_leads_citas()`; hoy ese trinquete esta en ROJO en
-- produccion por otra causa (alertas f6a abiertas desde el 01/10: contadores sin
-- declarar), asi que llamarlo abortaria una migracion que no lo empeora ni lo
-- arregla. Aqui no se llama.
--
-- COMO SE REVIERTE (Codex, 13/10, P3). Solo tiene sentido si el cuerpo vivo NO
-- fuera legitimo: primero se restaura el cuerpo anterior (reversa de
-- coordinacion-reportes: prosrc 0b4ede54…, definicion 0bfcc0d4…) y despues una
-- migracion con este esqueleto re-declara la huella al reves (869853c2… →
-- 0b4ede54…) cambiando TAMBIEN las dos anclas de definicion (v_defin y la de
-- (b3): 67cdc767… → 0bfcc0d4…). Así el vigilante termina en verde, que es lo que
-- su postflight exige.
--
-- APLICACION (Codex, 13/10, P2). Las anclas del cuerpo se comprueban dos veces,
-- pero el SQL no impide que otra sesion altere la funcion (p. ej. su search_path)
-- entre (b3) y el COMMIT: aplicar sin otra publicacion de servidor simultanea.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- =====================================================================
-- 0) PREFLIGHT: la fila es la que creo, el mundo es el que creo, y no hay
--    una SEGUNDA deriva que este cambio estaria tapando.
-- =====================================================================
do $pre$
declare
  v_firma    constant text := 'crm.metricas_cartera_fn(date)';
  v_vieja    constant text := '0b4ede547cf7079be1e56073311453b3';
  v_nueva    constant text := '869853c25e903fe2f79245b8176c09b9';
  v_defin    constant text := '67cdc767f0d38277a920b2ec5aebf2ae';
  v_acl      constant text := '{postgres=X/postgres}';
  v_oid oid; v_n int; v_detalle text;
  v_estado text; v_ola text; v_huella text; v_acl_viva text; v_dueno text;
  v_llamadores text[];
begin
  v_oid := to_regprocedure(v_firma);
  if v_oid is null then
    raise exception 'F7 re-declaracion: % no existe — el mundo no es el que esta migracion asume', v_firma;
  end if;

  select f.estado, f.ola, f.huella_md5, f.llamadores_permitidos
    into v_estado, v_ola, v_huella, v_llamadores
  from private.f7_piezas_en_observacion f
   where f.firma = v_firma;
  if v_estado is null then
    raise exception 'F7 re-declaracion: % no esta en el libro', v_firma;
  end if;
  if v_estado <> 'cerrada_permanente' or v_ola <> 'F7.1' then
    raise exception 'F7 re-declaracion: % esta como %/% y se esperaba cerrada_permanente/F7.1', v_firma, v_estado, v_ola;
  end if;
  if v_huella is distinct from v_vieja then
    raise exception 'F7 re-declaracion: la huella declarada de % es % y se esperaba % — alguien ya la toco; revisar antes de reescribirla', v_firma, v_huella, v_vieja;
  end if;
  if v_llamadores is distinct from array['crm.conversion_mensual_fn(date)'] then
    raise exception 'F7 re-declaracion: los llamadores permitidos de % son % y se esperaba {crm.conversion_mensual_fn(date)}', v_firma, v_llamadores;
  end if;

  -- El cuerpo VIVO es exactamente el que se midio, por las DOS anclas: el
  -- `prosrc` que el assert compara y la definicion COMPLETA (firma, lenguaje,
  -- volatilidad, SECURITY DEFINER y search_path).
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)), p.proacl::text, pg_get_userbyid(p.proowner)
    into v_huella, v_detalle, v_acl_viva, v_dueno
  from pg_proc p where p.oid = v_oid;
  if v_huella is distinct from v_nueva then
    raise exception 'F7 re-declaracion: el cuerpo vivo de % tiene huella % y se midio % — volver a medir antes de sellar', v_firma, v_huella, v_nueva;
  end if;
  if v_detalle is distinct from v_defin then
    raise exception 'F7 re-declaracion: la DEFINICION completa de % cambio (huella %) — el cuerpo cuadra pero los atributos no', v_firma, v_detalle;
  end if;
  if v_acl_viva is distinct from v_acl then
    raise exception 'F7 re-declaracion: % SE REABRIO (ACL %, se esperaba %) — esto ya no es una huella desfasada', v_firma, v_acl_viva, v_acl;
  end if;
  if v_dueno is distinct from 'postgres' then
    raise exception 'F7 re-declaracion: % cambio de dueño a «%»', v_firma, v_dueno;
  end if;

  -- NINGUNA otra pieza vigilada puede estar derivada.
  select count(*), string_agg(o.firma, ' | ')
    into v_n, v_detalle
  from private.f7_piezas_en_observacion o
  join pg_proc p on p.oid = to_regprocedure(o.firma)
   where o.estado in ('observacion','cerrada_permanente')
     and o.firma <> v_firma
     and (md5(p.prosrc) is distinct from o.huella_md5
          or p.proacl::text is distinct from o.acl_esperada);
  if v_n > 0 then
    raise exception 'F7 re-declaracion: hay % pieza(s) MAS con huella o ACL derivada — resolverlas en el mismo paquete o el vigilante sigue en rojo: %', v_n, v_detalle;
  end if;

  -- Y el vigilante esta en rojo HOY por esta causa exacta (mensaje COMPLETO).
  declare
    v_esperado constant text := format(
      'F7: el cuerpo de %s cambio estando cerrada (huella %s)', v_firma, v_nueva);
  begin
    perform private.assert_f7_piezas_cerradas();
    raise exception 'F7 re-declaracion: el vigilante ya esta VERDE — nada que re-declarar';
  exception
    when others then
      if sqlerrm like '%re-declaracion%' then raise; end if;
      if sqlerrm is distinct from v_esperado then
        raise exception 'F7 re-declaracion: el vigilante esta en rojo por OTRA causa. Esperaba «%», recibi «%»', v_esperado, sqlerrm;
      end if;
  end;
end $pre$;

-- Foto de la fila ANTES de tocarla (para acreditar que solo se movieron los dos campos).
create temporary table f7_foto_previa on commit drop as
select * from private.f7_piezas_en_observacion
 where firma = 'crm.metricas_cartera_fn(date)';

-- =====================================================================
-- 1) LA RE-DECLARACION. `trg_f7_obs_00_solo_crece` congela `huella_md5` a
--    proposito; se baja SOLO este candado, por nombre, y se re-activa en la
--    MISMA transaccion (como en 20260924161110).
-- =====================================================================
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;

do $acta$
declare v_n int;
begin
  update private.f7_piezas_en_observacion
     set huella_md5 = '869853c25e903fe2f79245b8176c09b9',
         nota = coalesce(nota, '') || E'\n'
                || 'Huella RE-DECLARADA el '
                || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
                || ' (0b4ede54… → 869853c2…): el cuerpo cambio estando cerrada por una'
                || ' migracion aplicada y legitima (20261012165115 / prod 20261012223850,'
                || ' Coordinacion: reportes en lectura; una linea: v_lector incluye'
                || ' private.es_coordinador_reportes()) y nadie actualizo el retrato.'
                || ' Estado, ACL, ventana, patron de censo y llamadores INTACTOS.'
   where firma = 'crm.metricas_cartera_fn(date)'
     and estado = 'cerrada_permanente'
     and huella_md5 = '0b4ede547cf7079be1e56073311453b3';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'F7 re-declaracion: el UPDATE toco % filas, esperaba exactamente 1', v_n;
  end if;
end $acta$;

alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- =====================================================================
-- 2) POSTFLIGHT: el vigilante en verde, el candado MORDIENDO otra vez, y
--    ninguna otra fila ni campo movido.
-- =====================================================================
do $post$
declare
  v_firma constant text := 'crm.metricas_cartera_fn(date)';
  v_verd text; v_n int; v_mordio boolean := false; v_msg text;
begin
  -- (a) El vigilante F7 vuelve a devolver texto en vez de lanzar (no-nulo explicito).
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd is null or v_verd not like 'OK%' then
    raise exception 'F7 re-declaracion postflight: el vigilante sigue en rojo: %', coalesce(v_verd, '(NULL)');
  end if;

  -- (b) EL CANDADO MUERDE: un UPDATE que DEBE rebotar con 42501 y el mensaje del
  --     candado, y el trigger habilitado. Las tres cosas.
  begin
    update private.f7_piezas_en_observacion
       set acl_esperada = acl_esperada || ' '
     where firma = v_firma;
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      v_mordio := v_msg like '%no se reescribe%';
      if not v_mordio then
        raise exception 'F7 re-declaracion postflight: rebota 42501 pero NO es el candado: «%»', v_msg;
      end if;
  end;
  if not v_mordio then
    raise exception 'F7 re-declaracion postflight: trg_f7_obs_00_solo_crece NO rebota — el candado quedo suelto';
  end if;
  select count(*) into v_n from pg_trigger
   where tgrelid = 'private.f7_piezas_en_observacion'::regclass
     and tgname = 'trg_f7_obs_00_solo_crece' and not tgisinternal and tgenabled <> 'D';
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: el candado no quedo HABILITADO (coincidencias %)', v_n;
  end if;

  -- (b2) Solo se movieron los DOS campos previstos.
  select count(*) into v_n
  from private.f7_piezas_en_observacion a
  join f7_foto_previa b on b.firma = a.firma
   where a.firma = v_firma
     and a.estado is not distinct from b.estado
     and a.ola is not distinct from b.ola
     and a.cerrada_en is not distinct from b.cerrada_en
     and a.drop_no_antes_de is not distinct from b.drop_no_antes_de
     and a.acl_esperada is not distinct from b.acl_esperada
     and a.patron_censo is not distinct from b.patron_censo
     and a.llamadores_permitidos is not distinct from b.llamadores_permitidos
     and a.ok_miguel is not distinct from b.ok_miguel;
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: algun campo AJENO a huella_md5/nota cambio en la fila de %', v_firma;
  end if;

  -- (b3) Las anclas del cuerpo vivo, OTRA VEZ al final.
  select count(*) into v_n from pg_proc p
   where p.oid = to_regprocedure(v_firma)
     and md5(p.prosrc) = '869853c25e903fe2f79245b8176c09b9'
     and md5(pg_get_functiondef(p.oid)) = '67cdc767f0d38277a920b2ec5aebf2ae'
     and pg_get_userbyid(p.proowner) = 'postgres'
     and p.proacl::text = '{postgres=X/postgres}';
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: el cuerpo o los atributos de % cambiaron DURANTE la transaccion', v_firma;
  end if;

  -- (c) La fila quedo como se queria.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = v_firma
     and huella_md5 = '869853c25e903fe2f79245b8176c09b9'
     and estado = 'cerrada_permanente'
     and acl_esperada = '{postgres=X/postgres}'
     and drop_no_antes_de is null;
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: la fila de % no quedo como se esperaba', v_firma;
  end if;
end $post$;

commit;

-- DESPUES DE APLICAR: el vigia de la F7 (01:59 Lima) cierra solo la alerta abierta de su fase cuando
-- su assert vuelve verde (20260922182454). Para cerrarla ya: select private.vigia_f7_piezas();
$mig$::text as contenido;
do $chk$
declare v_otras text;
begin
  if md5((select contenido from pg_temp.registro_20261013233000)) is distinct from 'ebf5af00995fa5816d779ae596cba8be' then
    raise exception 'REGISTRO: el contenido incrustado no es el archivo de la migración';
  end if;
  if (select huella_md5 from private.f7_piezas_en_observacion where firma = 'crm.metricas_cartera_fn(date)')
     is distinct from '869853c25e903fe2f79245b8176c09b9' then
    raise exception 'REGISTRO: la migración 20261013233000 no está aplicada (la huella del libro F7 de crm.metricas_cartera_fn no es 869853c2…): no se registra';
  end if;
  select string_agg(s.version, ', ' order by s.version) into v_otras
    from supabase_migrations.schema_migrations s where s.name = 'crm_f7_redeclarar_huella_metricas_cartera' and s.version <> '20261013233000';
  if v_otras is not null then
    raise exception 'REGISTRO: el nombre crm_f7_redeclarar_huella_metricas_cartera ya está registrado con otra versión (%)', v_otras;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations s cross join pg_temp.registro_20261013233000 r
             where s.version = '20261013233000' and (coalesce(s.name, '') <> 'crm_f7_redeclarar_huella_metricas_cartera' or s.statements is distinct from array[r.contenido])) then
    raise exception 'REGISTRO: la versión 20261013233000 ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
select '20261013233000', 'crm_f7_redeclarar_huella_metricas_cartera', array[r.contenido] from pg_temp.registro_20261013233000 r
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261013233000' and name = 'crm_f7_redeclarar_huella_metricas_cartera' and cardinality(statements) = 1 and md5(statements[1]) = 'ebf5af00995fa5816d779ae596cba8be') then
    raise exception 'REGISTRO: la fila 20261013233000 / crm_f7_redeclarar_huella_metricas_cartera no quedó como se esperaba';
  end if;
end $post$;
commit;
-- Última fila, tras el COMMIT, para que `db query` muestre algo.
select '20261013233000' as version_registrada, 'ebf5af00995fa5816d779ae596cba8be' as md5_del_archivo;

-- P-055 F7 · RE-DECLARAR LA HUELLA DE crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)
--
-- QUE HACE. Actualiza DOS campos de UNA sola fila del libro
-- `private.f7_piezas_en_observacion` —la `huella_md5` y el rastro en `nota`— de
-- `crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)`, de
-- 0de7a130ae366cde54035e2c50f213e2 (la original) a
-- 802c0318fd3ec5636e174b4f98b3c965 (la viva). No toca su estado, su ACL, su
-- ventana, su patron de censo ni ninguna otra fila.
--
-- POR QUE. El cuerpo de esa funcion cambio estando CERRADA, y el cambio es
-- LEGITIMO: la recrearon TRES migraciones ya aplicadas, medido en
-- `supabase_migrations.schema_migrations` el 2026-09-22 buscando
-- `%function crm.crear_contrato_con_cuenta(%` en sus `statements`:
--   · 20260905140000  crm_f2b_e4_contrato_reconoce_persona_y_candado_documento
--   · 20260906200000  crm_f2b_d19_toda_escritura_lee_la_bandera_bajo_su_candado
--   · 20260908211349  crm_f4_publicacion_compatible_rentabilidad
-- Nadie actualizo la huella declarada, asi que desde el 2026-09-05
-- `private.assert_f7_piezas_cerradas()` LANZA y el vigia de las 06:59 levanta una
-- alerta nueva cada dia. Al 2026-09-24 van 18 alertas abiertas, todas de esta
-- misma causa (comprobado motivo POR DIA, no atribuido en bloque).
--
-- QUE SE GANA. `private.vigia_alertas` es infraestructura COMPARTIDA y es la
-- alarma de todo el proyecto. Con 18 falsos positivos permanentes nadie puede
-- distinguir una alerta nueva y real del ruido de fondo; las fases `f5a` y `f6a`
-- ya limpiaron las suyas y esta es la unica que queda. Desde el
-- 20260922182454 los vigias CIERRAN las alertas de su propia fase cuando su
-- assert vuelve verde, asi que en cuanto esto se aplique el vigia (o una
-- ejecucion manual de `private.vigia_f7_piezas()`) las cierra las 18 solo.
-- Efecto lateral: destraba el stop-the-line de las olas 2 y 2b de la F7, cuyo
-- preflight exige CERO alertas abiertas de CUALQUIER fase.
--
-- LO QUE NO ES. No reabre nada, no cambia permisos y no demuele. La pieza sigue
-- `cerrada_permanente` y su propia nota dice «organo interno del alta pdf_v2 -
-- JAMAS se derriba». Esta migracion solo pone al dia el retrato que el vigilante
-- compara.
--
-- 🔑 LA HUELLA VA EN CRUDO. `assert_f7_piezas_cerradas()` compara
-- `md5(p.prosrc)` TAL CUAL. La normalizacion que aparece en ese mismo cuerpo
-- (quitar comentarios, `lower`, sin comillas) es SOLO para el `patron_censo`.
-- El trinquete de la F5.a si normaliza: cada trinquete sella a su manera y hay
-- que leer la fuente del assert antes de calcular una huella.
--
-- COMO SE REVIERTE. Una migracion nueva que repita este mismo esqueleto con la
-- huella al reves (802c0318… → 0de7a130…). Volveria a dejar al vigilante en
-- rojo, asi que solo tiene sentido si se descubre que el cuerpo vivo NO es
-- legitimo y se restaura el original.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- =====================================================================
-- 0) PREFLIGHT: la fila es la que creo, el mundo es el que creo, y no hay
--    una SEGUNDA deriva que este cambio estaria tapando.
-- =====================================================================
do $pre$
declare
  v_firma    constant text := 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)';
  v_vieja    constant text := '0de7a130ae366cde54035e2c50f213e2';
  v_nueva    constant text := '802c0318fd3ec5636e174b4f98b3c965';
  v_defin    constant text := 'e52e632b340992c18d09e8aad18ed67e';
  v_acl      constant text := '{postgres=X/postgres}';
  v_oid oid; v_n int; v_detalle text;
  v_estado text; v_ola text; v_huella text; v_acl_viva text; v_dueno text;
begin
  v_oid := to_regprocedure(v_firma);
  if v_oid is null then
    raise exception 'F7 re-declaracion: % no existe — el mundo no es el que esta migracion asume', v_firma;
  end if;

  select f.estado, f.ola, f.huella_md5
    into v_estado, v_ola, v_huella
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

  -- El cuerpo VIVO es exactamente el que se midio, por las DOS anclas: el
  -- `prosrc` que el assert compara y la definicion COMPLETA, que ademas
  -- arrastra firma, lenguaje, volatilidad, SECURITY DEFINER y search_path.
  -- Un cuerpo identico con otro `search_path` seria otra funcion a efectos de
  -- seguridad y cuadraria solo la primera ancla.
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

  -- NINGUNA otra pieza vigilada puede estar derivada. Si la hubiera, poner al
  -- dia solo esta dejaria al vigilante en rojo por otra causa y el arreglo
  -- pareceria no haber funcionado.
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

  -- Y el vigilante esta en rojo HOY por esta causa y no por otra: si ya
  -- estuviera verde, esta migracion no tendria nada que arreglar.
  -- Codex P2 (24/09): `strpos(sqlerrm, firma)` es demasiado laxo — el error de OTRA
  -- pieza que nombrara esta firma (como llamador permitido, por ejemplo) colaria.
  -- Se exige el MENSAJE COMPLETO que el assert produce para esta causa exacta.
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

-- Foto de la fila ANTES de tocarla, para poder acreditar despues que solo se
-- movieron los dos campos previstos (Codex P3: el postflight afirmaba «nada mas
-- se movio» sin compararlo). Temporal: muere con la sesion.
create temporary table f7_foto_previa on commit drop as
select * from private.f7_piezas_en_observacion
 where firma = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)';

-- =====================================================================
-- 1) LA RE-DECLARACION. `trg_f7_obs_00_solo_crece` congela `huella_md5` a
--    proposito; su propio comentario manda bajar este candado NOMBRADO en un
--    DO de migracion (doctrina limpieza-leads) y volver a subirlo. Se baja
--    SOLO este trigger, por nombre, y se re-activa en la MISMA transaccion.
-- =====================================================================
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;

do $acta$
declare v_n int;
begin
  update private.f7_piezas_en_observacion
     set huella_md5 = '802c0318fd3ec5636e174b4f98b3c965',
         nota = coalesce(nota, '') || E'\n'
                || 'Huella RE-DECLARADA el '
                || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
                || ' (0de7a130… → 802c0318…): el cuerpo cambio estando cerrada por tres'
                || ' migraciones aplicadas y legitimas (20260905140000 F2.b E4, 20260906200000'
                || ' F2.b D19, 20260908211349 F4 rentabilidad) y nadie actualizo el retrato.'
                || ' Estado, ACL, ventana y patron de censo INTACTOS: no se reabre ni se demuele.'
   where firma = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'
     and estado = 'cerrada_permanente'
     and huella_md5 = '0de7a130ae366cde54035e2c50f213e2';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'F7 re-declaracion: el UPDATE toco % filas, esperaba exactamente 1', v_n;
  end if;
end $acta$;

alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- =====================================================================
-- 2) POSTFLIGHT: el vigilante en verde, el candado MORDIENDO otra vez, y
--    ninguna otra fila movida.
-- =====================================================================
do $post$
declare
  v_firma constant text := 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)';
  v_verd text; v_n int; v_mordio boolean := false; v_msg text;
begin
  -- (a) El vigilante F7 vuelve a devolver texto en vez de lanzar.
  --     Codex P2 (24/09): `not like` con NULL da NULL y NO entra en el if — un
  --     veredicto nulo pasaria por verde. Se exige no-nulo explicitamente.
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd is null or v_verd not like 'OK%' then
    raise exception 'F7 re-declaracion postflight: el vigilante sigue en rojo: %', coalesce(v_verd, '(NULL)');
  end if;

  -- (b) EL CANDADO MUERDE. Comprobar `tgenabled` solo acredita que el trigger
  --     esta colgado, no que funcione: «puesto» no es «funciona». Se intenta un
  --     UPDATE que DEBE rebotar con 42501; si pasa, el candado quedo suelto.
  --     Codex P2 (24/09): un 42501 de OTRO origen (otro trigger, un permiso)
  --     tambien daria verde, asi que ademas se exige el MENSAJE del candado y
  --     que el trigger este habilitado. Las tres cosas, no una.
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

  -- (b2) Solo se movieron los DOS campos previstos. Codex P3: el comentario
  --      afirmaba «nada mas se movio» y nadie lo comparaba.
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

  -- (b3) Las anclas del cuerpo vivo, OTRA VEZ al final. Codex las señala como
  --      riesgo: se comprobaban solo en el preflight, y un `ALTER FUNCTION`
  --      concurrente que cambiara `search_path` conservaria `prosrc` y se
  --      colaria por el assert. Repetirlas no sustituye serializar el DDL, pero
  --      estrecha la ventana.
  select count(*) into v_n from pg_proc p
   where p.oid = to_regprocedure(v_firma)
     and md5(p.prosrc) = '802c0318fd3ec5636e174b4f98b3c965'
     and md5(pg_get_functiondef(p.oid)) = 'e52e632b340992c18d09e8aad18ed67e'
     and pg_get_userbyid(p.proowner) = 'postgres'
     and p.proacl::text = '{postgres=X/postgres}';
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: el cuerpo o los atributos de % cambiaron DURANTE la transaccion', v_firma;
  end if;

  -- (c) La fila quedo como se queria y NADA mas se movio.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = v_firma
     and huella_md5 = '802c0318fd3ec5636e174b4f98b3c965'
     and estado = 'cerrada_permanente'
     and acl_esperada = '{postgres=X/postgres}'
     and drop_no_antes_de is null;
  if v_n <> 1 then
    raise exception 'F7 re-declaracion postflight: la fila de % no quedo como se esperaba', v_firma;
  end if;

  -- (d) La analitica, en la misma transaccion (mismo reparo del NULL).
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd is null or v_verd not like 'OK%' then
    raise exception 'F7 re-declaracion postflight: analitica en rojo: %', coalesce(v_verd, '(NULL)');
  end if;
end $post$;

commit;

-- DESPUES DE APLICAR (paso del operador, fuera de esta transaccion):
--   select private.vigia_f7_piezas();     -- cierra las 18 alertas de la fase
--   select count(*) from private.vigia_alertas where resuelta_en is null;  -- debe dar 0

-- REVERSA de 20261009210000_crm_anular_venta_mes_sellado.sql («No se puede anular una venta de un mes sellado»).
--
-- FALLA CERRADA. CONTRATO: antes de tocar nada exige, y si algo difiere se niega sin dejar rastro,
--   (a) de las DOS PUERTAS: `md5(prosrc)` (`1bb2bfd1…` avance, `4b01f805…` externo) Y `md5(pg_get_functiondef)` (`03b67308…` y
--       `906372fe…`) exactamente los que dejó la migración, Y su ficha auditada: dueño `postgres`, `security definer`,
--       `search_path` vacío y ACL EXACTA con opción de concesión (EXECUTE solo para el dueño y `authenticated`, sin `GRANT
--       OPTION`; la misma que fija el preflight de la migración). `pg_get_functiondef` no incluye dueño ni ACL: un `GRANT
--       EXECUTE … TO service_role` posterior pasaría las huellas y `create or replace` lo conservaría en silencio;
--   (b) del DETECTOR `private.mes_sellado_de_venta(uuid)`: que exista, `md5(prosrc)` (`8e22b2d6…`) Y `md5(pg_get_functiondef)`
--       (`ba2cfaaa…`) exactamente los que dejó la migración, Y su ficha INVOKER (dueño `postgres`, `security invoker`,
--       `search_path` vacío, sin EXECUTE para nadie salvo el dueño). Un `CREATE OR REPLACE` posterior con otro cuerpo, o un
--       GRANT sobre él, haría que el `DROP` borrase algo que nadie auditó;
--   (c) de los COMENTARIOS (`obj_description`) de las dos puertas y del detector: exactamente los que dejó la migración. Esta
--       reversa REPONE los dos primeros y BORRA el tercero: un `COMMENT ON FUNCTION … IS 'otro'` posterior se sobrescribiría o
--       se perdería sin que nadie lo viera, y ni las huellas ni la ficha lo delatan.
-- Esa lista es TODO lo que exige —cuerpos (`md5(prosrc)`), definiciones (`md5(pg_get_functiondef)`), ficha (dueño, `security
-- definer`/`invoker`, `search_path`), ACL con `is_grantable`, comentarios, y existencia y huellas del detector— y no promete
-- detectar nada fuera de ella. Se niega, por tanto, si la migración no está aplicada, si alguien cambió un CUERPO después, si
-- alguien cambió un ATRIBUTO después sin tocar el cuerpo (p. ej. `ALTER FUNCTION … SET lock_timeout`), si alguien cambió el
-- DUEÑO o la ACL de una puerta o del detector, o si alguien cambió un COMENTARIO: en todos esos casos NO se revierte nada —ni
-- siquiera a medias— y se revisa a mano (o se corrige hacia delante con otra migración). Una reversa que «arreglase» por el
-- camino lo que no sabe que está ahí sería otra deriva. (Ensayado: `armar-ensayo.mjs --reversa-con-set`, `--reversa-con-grant`,
-- `--reversa-con-detector-alterado` y `--reversa-con-comentario` aplican la migración, instalan esa deriva e intentan esta
-- reversa: aborta en el preflight y la foto —cuerpos, dueño, ACL, comentarios y detector— queda idéntica, deriva incluida.)
--
-- QUÉ RESTAURA: los dos cuerpos anteriores, deshaciendo UNA A UNA las cuatro sustituciones de la migración sobre el cuerpo vivo
-- (cada fragmento tiene que aparecer EXACTAMENTE una vez o la reversa aborta): `md5(prosrc)` vuelve a `8556d0bd…` (avance) y
-- `09a47896…` (externo), y `md5(pg_get_functiondef)` a `23e3be19…` y `f568b78f…`. Repone sus dos comentarios y BORRA el
-- detector `private.mes_sellado_de_venta(uuid)`. El postflight vuelve a exigir esas huellas originales.
--
-- QUÉ CONSERVA: firma, dueño y ACL de las puertas (`create or replace` no los toca). Con el preflight de arriba, la ACL y el
-- dueño que encuentra son EXACTAMENTE los auditados (no «los que hubiera»): si no lo son, no revierte.
--
-- NO DES-ANULA NADA: lo que el exento (admin + Gerencia) anuló en un mes sellado (o de mes desconocido) queda anulado, sin
-- ajuste y con su rastro `excepcion_*` en la actividad; los ajustes que existieran siguen su curso. Tras revertir, el servidor
-- vuelve a dejar anular una venta de un mes sellado creando ajuste (o, si la venta no pesa, sin ajuste): es el defecto que la
-- migración cerraba. Se aplica por el mismo ciclo que la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  v_oid oid;
  v_pa  text;
  v_pe  text;
  v_c   record;
begin
  -- (b1) El detector existe: si no, la migración no está aplicada y no hay nada que revertir.
  if to_regprocedure('private.mes_sellado_de_venta(uuid)') is null then
    raise exception 'REVERSA anular_venta_mes_sellado: el detector no existe (la migración no está aplicada); nada que revertir';
  end if;
  -- (a1) Los cuerpos de las puertas son los que dejó la migración.
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure)
       is distinct from '1bb2bfd1cef0d1a0dc201c698f6ae120'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure)
       is distinct from '4b01f805b24e0b95a8dd49c7cbef8409' then
    raise exception 'REVERSA anular_venta_mes_sellado: el cuerpo de una puerta no es el que dejó la migración (no está aplicada o cambió después); revisar antes de revertir';
  end if;
  -- (a2) Y su definición entera (atributos incluidos: un SET añadido con ALTER FUNCTION cambia pg_get_functiondef y no prosrc).
  if md5(pg_get_functiondef('crm.anular_cierre_avance(uuid,text)'::regprocedure))
       is distinct from '03b673084dbbbbff7aef21c12e7f30b5'
     or md5(pg_get_functiondef('crm.anular_cierre_externo(uuid,text)'::regprocedure))
       is distinct from '906372fe41ed37a2892e181bf8b9663f' then
    raise exception 'REVERSA anular_venta_mes_sellado: una puerta no tiene exactamente la definición que dejó la migración (un atributo cambió después sin tocar el cuerpo, p. ej. un SET lock_timeout): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  -- (a3) Y su ficha auditada: dueño, security definer, search_path vacío y ACL EXACTA con opción de concesión (la misma que
  --      fija el preflight de la migración). pg_get_functiondef no incluye dueño ni ACL: sin esto, un GRANT posterior
  --      sobreviviría al `create or replace` sin que nadie lo viera.
  for v_oid in
    select unnest(array['crm.anular_cierre_avance(uuid,text)'::regprocedure::oid,
                        'crm.anular_cierre_externo(uuid,text)'::regprocedure::oid])
  loop
    if not exists (
         select 1 from pg_proc p
         where p.oid = v_oid
           and p.proowner = 'postgres'::regrole::oid
           and p.prosecdef
           and p.proconfig = array['search_path=""'])
       or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
             from pg_proc p
             cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where p.oid = v_oid)
          is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false'] then
      raise exception 'REVERSA anular_venta_mes_sellado: la ficha de % no es la que dejó la migración (dueño postgres, security definer, search_path vacío, EXECUTE solo para el dueño y authenticated, sin opción de concesión): alguien cambió el dueño o la ACL después; la reversa falla cerrada; revisar a mano antes de revertir', v_oid::regprocedure;
    end if;
  end loop;
  -- (b2) El detector es, byte a byte, el que dejó la migración (cuerpo Y definición): el DROP no borra nada que nadie auditó.
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_pa, v_pe
    from pg_proc p where p.oid = 'private.mes_sellado_de_venta(uuid)'::regprocedure;
  if v_pa is distinct from '8e22b2d65bb35be0551c190cfcf28e75'
     or v_pe is distinct from 'ba2cfaaa3337a05a6cd7c32cd6af8e8c' then
    raise exception 'REVERSA anular_venta_mes_sellado: el detector private.mes_sellado_de_venta(uuid) no es el que dejó la migración (medidos: prosrc %, definición %; esperados 8e22b2d65bb35be0551c190cfcf28e75 y ba2cfaaa3337a05a6cd7c32cd6af8e8c): alguien lo cambió después; la reversa falla cerrada; revisar a mano antes de revertir', v_pa, v_pe;
  end if;
  -- (b3) Y su ficha INVOKER: dueño postgres, security invoker, search_path vacío y NINGÚN rol con EXECUTE salvo el dueño.
  if not exists (
       select 1 from pg_proc p
       where p.oid = 'private.mes_sellado_de_venta(uuid)'::regprocedure
         and p.proowner = 'postgres'::regrole::oid
         and not p.prosecdef
         and p.proconfig = array['search_path=""'])
     or exists (
       select 1 from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
       where p.oid = 'private.mes_sellado_de_venta(uuid)'::regprocedure
         and a.grantee <> 'postgres'::regrole::oid)
     or has_function_privilege('authenticated', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')
     or has_function_privilege('anon', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')
     or has_function_privilege('service_role', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE') then
    raise exception 'REVERSA anular_venta_mes_sellado: la ficha del detector private.mes_sellado_de_venta(uuid) no es la que dejó la migración (dueño postgres, security invoker, search_path vacío, sin EXECUTE para nadie salvo el dueño): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  -- (c) Los COMENTARIOS de las dos puertas y del detector son los que dejó la migración (ronda 4, R3-3). Esta reversa repone
  --     los dos primeros y borra el tercero: una deriva de comentario posterior (COMMENT ON FUNCTION) se sobrescribiría o se
  --     perdería sin que nadie la viera, y ni pg_get_functiondef ni la ficha la cubren. Textos: los de la migración, literales.
  for v_c in
    select * from (values
      ('crm.anular_cierre_avance(uuid,text)',
       'Anula un cierre de Avance (error de gestion o mala practica), SOLO gerencia y con motivo obligatorio. El cierre deja de acreditarle al vendedor en la CUOTA y en la CONVERSION a la vez. NO mueve dinero real: el contrato y el cliente siguen intactos en public. El lead NO se reabre (un convertido es terminal por diseno) y el episodio del ledger no se toca (es inmutable). De una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo. UN MES SELLADO NO SE REESCRIBE (bloque 2.6): si el mes de la venta tiene fila en crm.periodos_cerrados, o no se puede determinar, rechaza con P0409 y no escribe nada, salvo para quien es admin del Portal Y Gerencia del CRM, que anula SIN ajuste y deja en la actividad excepcion_mes_sellado (AAAA-MM o desconocido), excepcion_por y excepcion_en; mes_cerrado queda en false por compatibilidad y no es el rastro.'),
      ('crm.anular_cierre_externo(uuid,text)',
       'Anula un cierre en cooperativa (fraude o error), SOLO gerencia y con motivo obligatorio. El cierre deja de contar en la cuota Y en la conversion mensual; la fila NO se borra (es el ancla de legalidad del lead convertido) y el lead NO se reabre (un convertido es terminal por diseno). Es de una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo y la foto de lo anulado. UN MES SELLADO NO SE REESCRIBE (bloque 2.6): si es el cierre inicial y el mes de la venta tiene fila en crm.periodos_cerrados, o no se puede determinar, rechaza con P0409 y no escribe nada, salvo para quien es admin del Portal Y Gerencia del CRM, que anula SIN ajuste y deja en la actividad excepcion_mes_sellado (AAAA-MM o desconocido), excepcion_por y excepcion_en; mes_cerrado queda en false por compatibilidad y no es el rastro. Los cierres no iniciales no cambian.'),
      ('private.mes_sellado_de_venta(uuid)',
       'Dada una venta (lead), dice el mes de la venta (p_mes), si ese mes tiene fila en crm.periodos_cerrados (p_sellado) y si el mes no se pudo determinar (p_desconocido). Mes de la venta (politica propia, mas estricta que la de registrar_ajuste_si_mes_cerrado, que volvia antes): con la politica de septiembre activa y la venta convertida desde el 01/09, el periodo_comercial de su acreditacion (UNIQUE lead_id); si no, el episodio de cierre del ledger (mas de uno: error de integridad, como registrar_ajuste_si_mes_cerrado); si no, el mes de leads.convertido_en en hora de Lima; si tampoco, desconocido (decidido al final). Un mes nulo o que no sea primer dia de mes es error de integridad (P0001), nunca abierto. Toma el cerrojo del mes (el de crm.cerrar_periodo) ANTES de mirar periodos_cerrados. Solo READ COMMITTED (0A000 en otro modo; 20261002163158). SECURITY INVOKER: solo la usan crm.anular_cierre_avance y crm.anular_cierre_externo (DEFINER, corre como su dueno); sin EXECUTE para ningun otro rol. Plan AVANCE-BACKEND-0610, bloque 2.6.')
    ) as c(firma, comentario)
  loop
    if obj_description(v_c.firma::regprocedure, 'pg_proc') is distinct from v_c.comentario then
      raise exception 'REVERSA anular_venta_mes_sellado: el comentario de % no es el que dejó la migración (alguien lo cambió o lo quitó después): la reversa lo sobrescribiría o lo borraría sin verlo; la reversa falla cerrada; revisar a mano antes de revertir', v_c.firma;
    end if;
  end loop;
end
$preflight$;

do $reemplazo$
declare
  v_def    text;
  v_anclas text[];
  v_nuevos text[];
  v_i      integer;
  v_veces  integer;
begin
  -- ===== crm.anular_cierre_avance ==========================================================================
  v_def := pg_get_functiondef('crm.anular_cierre_avance(uuid,text)'::regprocedure);
  v_nuevos := array[
    -- 1. variables (se quitan las del bloque 2.6)
    $n1$  v_ajuste uuid;
begin
$n1$,
    -- 2. se quita la guarda
    $n2$  -- Los contratos afectados se calculan ANTES de insertar la anulacion: despues,
$n2$,
    -- 3. vuelve la llamada a registrar_ajuste_si_mes_cerrado
    $n3$  -- Si el mes de ese cierre YA ESTA CERRADO, el mes no se reescribe: nace la
  -- deuda que el vendedor arrastrara al mes vivo hasta saldarla.
  v_ajuste := private.registrar_ajuste_si_mes_cerrado(p_lead_id, v_motivo, v_uid);
$n3$,
    -- 4. se quita el rastro del exento
    $n4$        'contrato_id', v_lead.contrato_id)
    ),
$n4$];
  v_anclas := array[
    $a1$  v_ajuste uuid;
  v_mes_sellado date;
  v_sellado boolean := false;
  v_desconocido boolean := false;
  v_excepcion boolean := false;
  v_excepcion_marca text;
begin
$a1$,
    $a2$  -- MES SELLADO (plan AVANCE-BACKEND-0610, bloque 2.6; D-09, D-14, D-17): un mes sellado no se reescribe.
  -- Se pregunta ANTES de escribir nada y DESPUES de «ya estaba anulado». El detector distingue mes sellado, mes no
  -- sellado y mes DESCONOCIDO (sin acreditacion, sin episodio y sin fecha de conversion): desconocido falla cerrado,
  -- como sellado. Solo pasa quien es a la vez admin del Portal y Gerencia del CRM (excepcion D-17), y entonces la
  -- anulacion NO crea ajuste y deja rastro abajo (excepcion_mes_sellado = AAAA-MM, o 'desconocido').
  select d.p_mes, d.p_sellado, d.p_desconocido
    into v_mes_sellado, v_sellado, v_desconocido
    from private.mes_sellado_de_venta(p_lead_id) d;
  if v_desconocido or v_sellado then
    if public.es_admin() and private.es_gerencia_crm_activa() then
      v_excepcion := true;
      v_excepcion_marca := case when v_desconocido then 'desconocido'
                                else pg_catalog.to_char(v_mes_sellado, 'YYYY-MM') end;
    elsif v_desconocido then
      raise exception using
        errcode = 'P0409',
        message = 'No se puede anular: no se puede determinar el mes de esta venta',
        hint    = 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
    else
      raise exception using
        errcode = 'P0409',
        message = pg_catalog.format('No se puede anular: el mes de esta venta (%s) ya está sellado',
                                    pg_catalog.to_char(v_mes_sellado, 'YYYY-MM')),
        hint    = 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
    end if;
  end if;

  -- Los contratos afectados se calculan ANTES de insertar la anulacion: despues,
$a2$,
    $a3$  -- (2.6) Ya no nace deuda: un mes sellado (o desconocido) rechaza la anulacion mas arriba y solo el exento llega
  -- aqui con el, sin ajuste. `v_ajuste` queda nulo a proposito: `mes_cerrado` y `ajuste_id` conservan su forma; el
  -- rastro fiable del exento son las claves excepcion_* de la actividad, no `mes_cerrado`.
$a3$,
    $a4$        'contrato_id', v_lead.contrato_id)
    ) || case when v_excepcion then pg_catalog.jsonb_build_object(
           'excepcion_mes_sellado', v_excepcion_marca,
           'excepcion_por', v_uid,
           'excepcion_en', pg_catalog.now())
         else '{}'::jsonb end,
$a4$];
  for v_i in 1..cardinality(v_anclas) loop
    v_veces := (length(v_def) - length(replace(v_def, v_anclas[v_i], ''))) / length(v_anclas[v_i]);
    if v_veces <> 1 then
      raise exception 'REVERSA anular_venta_mes_sellado: el fragmento % de crm.anular_cierre_avance aparece % veces (debe ser 1)', v_i, v_veces;
    end if;
    v_def := replace(v_def, v_anclas[v_i], v_nuevos[v_i]);
  end loop;
  execute v_def;

  -- ===== crm.anular_cierre_externo =========================================================================
  v_def := pg_get_functiondef('crm.anular_cierre_externo(uuid,text)'::regprocedure);
  v_nuevos := array[
    $m1$  v_ajuste uuid;
begin
$m1$,
    $m2$  perform set_config('crm.op_privilegiada', 'on', true);
$m2$,
    $m3$  -- Si el mes de ese cierre YA ESTA CERRADO, el mes no se reescribe: nace la
  -- deuda que el vendedor arrastrara al mes vivo.
  if v_cierre.es_cierre_inicial then
    v_ajuste := private.registrar_ajuste_si_mes_cerrado(v_cierre.lead_id, v_motivo, v_uid);
  end if;
$m3$,
    $m4$        'vendedor_id', v_cierre.vendedor_id)
    ),
$m4$];
  v_anclas := array[
    $b1$  v_ajuste uuid;
  v_mes_sellado date;
  v_sellado boolean := false;
  v_desconocido boolean := false;
  v_excepcion boolean := false;
  v_excepcion_marca text;
begin
$b1$,
    $b2$  -- MES SELLADO (plan AVANCE-BACKEND-0610, bloque 2.6; D-09, D-14, D-17): un mes sellado no se reescribe.
  -- Solo la CONVERSION (cierre inicial): renovacion, upgrade y reinversion no entran (D-14). Se pregunta ANTES de
  -- escribir nada y DESPUES de «ya estaba anulado». El detector distingue mes sellado, mes no sellado y mes
  -- DESCONOCIDO (sin acreditacion, sin episodio y sin fecha de conversion): desconocido falla cerrado, como sellado.
  -- Solo pasa quien es a la vez admin del Portal y Gerencia del CRM (excepcion D-17), y entonces la anulacion NO crea
  -- ajuste y deja rastro abajo (excepcion_mes_sellado = AAAA-MM, o 'desconocido').
  if v_cierre.es_cierre_inicial then
    select d.p_mes, d.p_sellado, d.p_desconocido
      into v_mes_sellado, v_sellado, v_desconocido
      from private.mes_sellado_de_venta(v_cierre.lead_id) d;
    if v_desconocido or v_sellado then
      if public.es_admin() and private.es_gerencia_crm_activa() then
        v_excepcion := true;
        v_excepcion_marca := case when v_desconocido then 'desconocido'
                                  else pg_catalog.to_char(v_mes_sellado, 'YYYY-MM') end;
      elsif v_desconocido then
        raise exception using
          errcode = 'P0409',
          message = 'No se puede anular: no se puede determinar el mes de esta venta',
          hint    = 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
      else
        raise exception using
          errcode = 'P0409',
          message = pg_catalog.format('No se puede anular: el mes de esta venta (%s) ya está sellado',
                                      pg_catalog.to_char(v_mes_sellado, 'YYYY-MM')),
          hint    = 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
      end if;
    end if;
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
$b2$,
    $b3$  -- (2.6) Ya no nace deuda: un mes sellado (o desconocido) rechaza la anulacion mas arriba y solo el exento llega
  -- aqui con el, sin ajuste. `v_ajuste` queda nulo a proposito: `mes_cerrado` y `ajuste_id` conservan su forma; el
  -- rastro fiable del exento son las claves excepcion_* de la actividad, no `mes_cerrado`.
$b3$,
    $b4$        'vendedor_id', v_cierre.vendedor_id)
    ) || case when v_excepcion then pg_catalog.jsonb_build_object(
           'excepcion_mes_sellado', v_excepcion_marca,
           'excepcion_por', v_uid,
           'excepcion_en', pg_catalog.now())
         else '{}'::jsonb end,
$b4$];
  for v_i in 1..cardinality(v_anclas) loop
    v_veces := (length(v_def) - length(replace(v_def, v_anclas[v_i], ''))) / length(v_anclas[v_i]);
    if v_veces <> 1 then
      raise exception 'REVERSA anular_venta_mes_sellado: el fragmento % de crm.anular_cierre_externo aparece % veces (debe ser 1)', v_i, v_veces;
    end if;
    v_def := replace(v_def, v_anclas[v_i], v_nuevos[v_i]);
  end loop;
  execute v_def;
end
$reemplazo$;

comment on function crm.anular_cierre_avance(uuid, text) is
  'Anula un cierre de Avance (error de gestion o mala practica), SOLO gerencia y con motivo obligatorio. El cierre deja de acreditarle al vendedor en la CUOTA y en la CONVERSION a la vez. NO mueve dinero real: el contrato y el cliente siguen intactos en public. El lead NO se reabre (un convertido es terminal por diseno) y el episodio del ledger no se toca (es inmutable). De una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo.';
comment on function crm.anular_cierre_externo(uuid, text) is
  'Anula un cierre en cooperativa (fraude o error), SOLO gerencia y con motivo obligatorio. El cierre deja de contar en la cuota Y en la conversion mensual; la fila NO se borra (es el ancla de legalidad del lead convertido) y el lead NO se reabre (un convertido es terminal por diseno). Es de una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo y la foto de lo anulado.';

drop function private.mes_sellado_de_venta(uuid);

do $postflight$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure)
       is distinct from '8556d0bde6dd80fd58e673f563c87005'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure)
       is distinct from '23e3be1974e08a1ec8aa61abe53242c3'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure)
       is distinct from '09a4789692b40df642cece433475e9fa'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure)
       is distinct from 'f568b78fc917d56cb00b5f88efd85deb' then
    raise exception 'REVERSA anular_venta_mes_sellado: una puerta no quedó como estaba antes de la migración';
  end if;
  if to_regprocedure('private.mes_sellado_de_venta(uuid)') is not null then
    raise exception 'REVERSA anular_venta_mes_sellado: el detector sigue existiendo';
  end if;
end
$postflight$;

commit;

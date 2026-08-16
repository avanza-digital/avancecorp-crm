-- ---------------------------------------------------------------------------
-- Candado GLOBAL publicar↔cerrar: la carrera entre PERIODOS DISTINTOS, cerrada
-- ---------------------------------------------------------------------------
-- 20260815223000 serializó publicar y cerrar EL MISMO mes (misma clave
-- por-mes). Quedaba dicho su residuo: publicar un mes P mientras se sella OTRO
-- mes M > P no contendía (claves por-mes distintas) y las metas de P nacían
-- muertas bajo el suelo del último sello — inertes, pero silenciosas. Miguel
-- exigió cerrarlo al 100 % (2026-08-15, revisión externa, observación #2).
--
-- EL ARREGLO: un candado GLOBAL —la familia de UN argumento,
-- pg_advisory_xact_lock(bigint), keyspace DISJUNTO de la familia de dos— que
-- toman AMBAS puertas ANTES de su candado por-mes:
--   · el trigger del candado de metas (cualquier INSERT a crm.meta_periodos);
--   · crm.cerrar_periodo (la única vía de sellado: ciclo y manual).
-- Con eso, una publicación concurrente a CUALQUIER sellado espera; al entrar,
-- su SELECT (snapshot nuevo en READ COMMITTED) ve el sello nuevo y el mes P
-- por debajo muere con el 22023 de negocio EN VEZ de parir metas muertas.
--
-- ORDEN DE CANDADOS (auditado, sin ciclo):
--   publicar:  (meta_periodos, P) → equipo SHARE → GLOBAL → (pc, P)
--   cerrar:    GLOBAL → (pc, M)          [el ciclo lo retiene todo su txn: las
--                                         publicaciones esperan los segundos
--                                         del sellado nocturno — asumido.
--                                         ⚠️ M1 del auditor: la publicacion
--                                         encolada tras el GLOBAL espera ya
--                                         sosteniendo equipo SHARE y FOR SHARE
--                                         sobre ~21 filas de public.perfiles →
--                                         esos segundos tambien frenan a la
--                                         jerarquia y a UPDATEs del portal
--                                         sobre esas filas. Acotado por la
--                                         duracion del ciclo de las 09:20.]
--   anulación: FOR UPDATE lead → (pc, mes)   [nunca toma GLOBAL ni meta_… →
--                                             sin ciclo posible]
-- El único recurso que dos transacciones pueden querer en orden cruzado sigue
-- siendo imposible: nadie adquiere GLOBAL después de (pc, mes).
--
-- `cerrar_periodo` NO se copia a mano (cientos de líneas = deriva segura): se
-- parchea DESDE SU FUENTE VIVA (pg_get_functiondef anclada por md5) insertando
-- el candado global justo antes del por-mes. El preflight aborta si la fuente
-- no es EXACTAMENTE la esperada.
--
-- Y LOS CHECKS APRENDEN LA LECCIÓN DEL FALSO POSITIVO (observación #7,
-- demostrada: un `-- perform pg_advisory…` COMENTADO pasaba los cuatro strpos
-- en verde): todo strpos de este postflight corre sobre el prosrc SIN
-- comentarios (`regexp_replace('--[^\n]*')`). El bloque 17 del oráculo se
-- endurece igual en este mismo cambio.
-- ---------------------------------------------------------------------------

begin;
set local lock_timeout = '10s';

do $preflight$
declare
  v_huella text;
begin
  select md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = 'private.trg_metas_no_bajo_mes_sellado()'::regprocedure;
  if v_huella is distinct from '4038c5a02f63742856bb247c630392cf' then
    raise exception 'trg_metas_no_bajo_mes_sellado no es la fuente esperada (md5 %). Revisar antes de aplicar.', v_huella;
  end if;

  select md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cerrar_periodo(date)'::regprocedure;
  if v_huella is distinct from '67a1fc6911d0b82835be5cf05abb80e9' then
    raise exception 'crm.cerrar_periodo no es la fuente esperada (md5 %). Revisar antes de aplicar.', v_huella;
  end if;
end
$preflight$;

-- 1) El trigger, con el candado GLOBAL delante del por-mes.
create or replace function private.trg_metas_no_bajo_mes_sellado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ultimo date;
begin
  -- GLOBAL primero: serializa esta publicación con CUALQUIER sellado en vuelo
  -- (también el de OTRO mes — la carrera del residuo de 20260815223000).
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados')::bigint
  );
  -- Y el por-mes de siempre: mismo recurso que cerrar_periodo y que las
  -- anulaciones (que NO toman el global) para el mes concreto.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (new.periodo - date '2000-01-01')::integer
  );

  select max(pc.periodo) into v_ultimo from crm.periodos_cerrados pc;

  if v_ultimo is not null and new.periodo <= v_ultimo then
    raise exception using
      errcode = '22023',
      message = format('No se publican metas de %s: %s ya esta cerrado',
                       to_char(new.periodo, 'YYYY-MM'), to_char(v_ultimo, 'YYYY-MM')),
      hint    = 'Un mes cerrado no se reescribe, y uno anterior ya no se puede sellar. Lo que haya que corregir se descuenta en el mes vivo.';
  end if;

  return new;
end;
$function$;

comment on function private.trg_metas_no_bajo_mes_sellado() is
  'Impide publicar metas de un mes igual o anterior al ultimo sellado. Doble candado, en orden: GLOBAL (serializa con CUALQUIER sellado en vuelo, tambien de otro mes) y por-mes (el de cerrar_periodo y las anulaciones). Sin el global, publicar P mientras se sella M>P paria metas muertas bajo el suelo en vez de este 22023.';

revoke all on function private.trg_metas_no_bajo_mes_sellado() from public, anon, authenticated;

-- 2) cerrar_periodo: el candado GLOBAL se INSERTA desde la fuente viva.
do $parche$
declare
  v_def   text;
  v_ancla constant text := '  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(''crm.periodos_cerrados''),
    (p_periodo - date ''2000-01-01'')::integer
  );';
  v_global constant text := '  -- CANDADO GLOBAL primero (20260815235500): serializa este sellado con
  -- CUALQUIER publicacion de metas en vuelo — tambien la de OTRO mes. El
  -- trigger del candado toma el mismo global antes de mirar; sin esto,
  -- publicar P durante el sellado de M>P paria metas muertas bajo el suelo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(''crm.periodos_cerrados'')::bigint
  );
';
begin
  select pg_catalog.pg_get_functiondef(p.oid) into v_def
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cerrar_periodo(date)'::regprocedure;
  -- strpos, no LIKE (el guion bajo es comodin), y el ancla debe ser UNICA.
  if (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'El punto de insercion del candado global no es unico o no existe en cerrar_periodo: reescribir esta migracion mirando la fuente.';
  end if;
  v_def := replace(v_def, v_ancla, v_global || v_ancla);
  execute v_def;
end
$parche$;

do $postflight$
declare
  v_trg text;
  v_cerrar text;
begin
  -- ⚠️ SIN COMENTARIOS: la leccion del falso positivo. Un candado comentado
  -- (`-- perform …`) dejaba los strpos en verde con la carrera abierta.
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_trg
  from pg_catalog.pg_proc p
  where p.oid = 'private.trg_metas_no_bajo_mes_sellado()'::regprocedure;
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_cerrar
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cerrar_periodo(date)'::regprocedure;

  -- 1) Las DOS puertas toman el GLOBAL (codigo real, no comentario)…
  if strpos(v_trg, $$hashtext('crm.periodos_cerrados')::bigint$$) = 0 then
    raise exception 'El trigger quedo sin el candado GLOBAL.';
  end if;
  if strpos(v_cerrar, $$hashtext('crm.periodos_cerrados')::bigint$$) = 0 then
    raise exception 'cerrar_periodo quedo sin el candado GLOBAL.';
  end if;
  -- 2) …ANTES de su candado por-mes…
  if strpos(v_trg, $$hashtext('crm.periodos_cerrados')::bigint$$)
     > strpos(v_trg, $$(new.periodo - date '2000-01-01')::integer$$) then
    raise exception 'En el trigger, el global quedo DESPUES del por-mes.';
  end if;
  if strpos(v_cerrar, $$hashtext('crm.periodos_cerrados')::bigint$$)
     > strpos(v_cerrar, $$(p_periodo - date '2000-01-01')::integer$$) then
    raise exception 'En cerrar_periodo, el global quedo DESPUES del por-mes.';
  end if;
  -- 3) …y el trigger sigue mirando DESPUES de candarse, con su rechazo vivo.
  if strpos(v_trg, 'pg_advisory_xact_lock') > strpos(v_trg, 'select max(pc.periodo)') then
    raise exception 'El candado del trigger quedo DESPUES de la lectura.';
  end if;
  if strpos(v_trg, 'ya esta cerrado') = 0 then
    raise exception 'El trigger perdio su rechazo de negocio.';
  end if;
  -- 4) El parche quirurgico no toco nada mas de cerrar_periodo: mismo cuerpo
  -- salvo el bloque insertado (se verifica quitando la insercion exacta).
  -- 4bis) El HEADER y las ACL sobreviven al render de functiondef (M2 del
  -- auditor): el md5-restore de abajo solo mira el CUERPO — un render que
  -- perdiera un atributo seria silencioso.
  if not (select p.prosecdef from pg_catalog.pg_proc p
          where p.oid = 'crm.cerrar_periodo(date)'::regprocedure) then
    raise exception 'cerrar_periodo perdio SECURITY DEFINER en el parche.';
  end if;
  if (select count(*) from pg_catalog.pg_proc p, unnest(p.proconfig) c
      where p.oid = 'crm.cerrar_periodo(date)'::regprocedure
        and strpos(c, 'search_path=') = 1) <> 1 then
    raise exception 'cerrar_periodo perdio su search_path fijado en el parche.';
  end if;
  if has_function_privilege('anon', 'crm.cerrar_periodo(date)', 'EXECUTE') then
    raise exception 'cerrar_periodo quedo ejecutable por anon tras el parche.';
  end if;
  if md5(replace((select p.prosrc from pg_catalog.pg_proc p
        where p.oid = 'crm.cerrar_periodo(date)'::regprocedure),
      '  -- CANDADO GLOBAL primero (20260815235500): serializa este sellado con
  -- CUALQUIER publicacion de metas en vuelo — tambien la de OTRO mes. El
  -- trigger del candado toma el mismo global antes de mirar; sin esto,
  -- publicar P durante el sellado de M>P paria metas muertas bajo el suelo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(''crm.periodos_cerrados'')::bigint
  );
', ''))
     is distinct from '67a1fc6911d0b82835be5cf05abb80e9' then
    raise exception 'cerrar_periodo cambio en algo MAS que la insercion del global: revisar.';
  end if;
end
$postflight$;

-- Vuelta atrás (manual): reinstalar el trigger de 20260815223000 y
-- cerrar_periodo desde 20260815102000. Reabriria la carrera entre periodos
-- distintos: solo si el candado global causa un problema mayor que el que
-- cierra (p. ej. esperas inaceptables de publicacion durante el ciclo).

commit;

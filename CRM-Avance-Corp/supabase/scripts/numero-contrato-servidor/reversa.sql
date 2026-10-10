-- REVERSA de 20261009210100_crm_numero_contrato_servidor.sql («El servidor exige el número de contrato»).
--
-- FALLA CERRADA. Antes de revertir exige que `public.crear_contrato(jsonb,jsonb)` tenga EXACTAMENTE la definición que dejó
-- la migración: `md5(prosrc)` = `dee13ad8e1e16e066ba1ba623c0dda6b` Y `md5(pg_get_functiondef)` = `6e5a01540300b385799743b4a5b47701`.
-- Se niega si la migración no está aplicada, si alguien cambió el CUERPO después, o si alguien cambió un ATRIBUTO después sin
-- tocar el cuerpo (p. ej. `ALTER FUNCTION … SET lock_timeout`, otro `SET`, INVOKER o algo que entre en la definición): en todos
-- esos casos NO se revierte nada y se revisa a mano (o se corrige hacia delante con otra migración). No se promete tolerancia
-- a derivas. (Ensayado: `armar-ensayo.mjs --reversa-con-set` aplica, añade un `SET lock_timeout` e intenta esta reversa:
-- aborta en el preflight y la foto queda idéntica, SET incluido.)
--
-- QUÉ RESTAURA: el cuerpo anterior, quitando del cuerpo vivo el bloque de la guarda que la migración insertó delante de la rama
-- de autogeneración (el bloque tiene que aparecer EXACTAMENTE una vez o la reversa aborta); lo que queda es, byte a byte, el
-- cuerpo vigente antes de la migración: `md5(prosrc)` vuelve a `1adfbe1a72739a1863c7321c3fd20439` y `md5(pg_get_functiondef)`
-- a `dce8f0dd6d6776b960096c56bdc29173` (los que registran el vigía de tasa-baja y los scripts de F8/F9). Repone el comentario
-- anterior. El postflight exige esas huellas originales.
--
-- QUÉ CONSERVA: firma, dueño, `security definer`, `search_path` vacío y ACL (`create or replace` no los toca; con el preflight
-- de arriba, los que encuentra son los que dejó la migración, que a su vez exigió que fueran los auditados).
--
-- NO DESHACE DATOS: la guarda solo rechazaba. Los contratos creados antes de la migración, o por el exento (admin del Portal +
-- Gerencia del CRM) con números libres o autogenerados `AC-AAAA-NNNN`, siguen como están. Tras revertir, el servidor vuelve a
-- autogenerar `AC-AAAA-NNNN` cuando el número va vacío y a aceptar cualquier número no duplicado: es el defecto que la
-- migración cerraba. Se aplica por el mismo ciclo que la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if to_regprocedure('public.crear_contrato(jsonb,jsonb)') is null then
    raise exception 'REVERSA numero_contrato_servidor: falta public.crear_contrato(jsonb,jsonb); nada que revertir';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure)
       is distinct from 'dee13ad8e1e16e066ba1ba623c0dda6b' then
    raise exception 'REVERSA numero_contrato_servidor: el cuerpo de public.crear_contrato no es el que dejó la migración (no está aplicada o cambió después); revisar antes de revertir';
  end if;
  if md5(pg_get_functiondef('public.crear_contrato(jsonb,jsonb)'::regprocedure))
       is distinct from '6e5a01540300b385799743b4a5b47701' then
    raise exception 'REVERSA numero_contrato_servidor: public.crear_contrato no tiene exactamente la definición que dejó la migración (un atributo cambió después sin tocar el cuerpo, p. ej. un SET lock_timeout): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
end
$preflight$;

do $reemplazo$
declare
  v_def   text;
  v_ancla text;
  v_veces integer;
begin
  v_def := pg_get_functiondef('public.crear_contrato(jsonb,jsonb)'::regprocedure);
  -- El bloque que insertó la migración (comentario + guarda), tal como lo devuelve pg_get_functiondef. Detrás de él la
  -- migración dejó intacta la rama `if v_numero is null then … end if;` original, que aquí se conserva.
  v_ancla := $guarda$  -- EL NUMERO DE CONTRATO LO EXIGE EL SERVIDOR (plan AVANCE-BACKEND-0610, bloque 2.3; D-11, D-12, D-16, D-17).
  -- Sobre el numero ya recortado: tiene que ser 2024-01-, 2025-01- o 2026-01- seguido de exactamente 6 digitos ASCII
  -- (el 01 es fijo, no es el mes; la lista de series es fija, no depende del año actual). Nulo, vacio o fuera de forma:
  -- se rechaza en vez de inventar AC-AAAA-NNNN. Unica excepcion: quien es a la vez admin/superadmin del Portal y
  -- Gerencia del CRM conserva el comportamiento anterior (autogenera si va vacio y acepta cualquier numero no
  -- duplicado). Sin sesion de usuario (auth.uid() nulo) es_admin() da falso: no hay excepcion. El duplicado conserva
  -- su error de siempre, mas abajo.
  if v_numero is null or v_numero !~ '^(2024|2025|2026)-01-[0-9]{6}$' then
    if not (public.es_admin() and private.es_gerencia_crm_activa()) then
      raise exception 'Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos'
        using errcode = '22023';
    end if;
  end if;
$guarda$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA numero_contrato_servidor: el bloque de la guarda aparece % veces en public.crear_contrato (debe ser 1)', v_veces;
  end if;
  execute replace(v_def, v_ancla, '');
end
$reemplazo$;

comment on function public.crear_contrato(jsonb, jsonb) is
  'Alta atómica de contrato y cronograma; renovaciones/upgrades conservan su ledger. La numeración automática usa private.siguiente_numero_contrato y es segura ante concurrencia.';

do $postflight$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure)
       is distinct from '1adfbe1a72739a1863c7321c3fd20439'
     or md5(pg_get_functiondef('public.crear_contrato(jsonb,jsonb)'::regprocedure))
       is distinct from 'dce8f0dd6d6776b960096c56bdc29173' then
    raise exception 'REVERSA numero_contrato_servidor: public.crear_contrato no quedó como estaba antes de la migración';
  end if;
  if (select position('^(2024|2025|2026)-01-[0-9]{6}$' in p.prosrc) from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure) <> 0 then
    raise exception 'REVERSA numero_contrato_servidor: la guarda sigue en public.crear_contrato';
  end if;
end
$postflight$;

commit;

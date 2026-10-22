-- REVERSA de 20261022170300_crm_cliente_por_telefono.sql («El cliente ya convertido también se reconoce por teléfono», bloque 2.7).
--
-- FALLA CERRADA. Antes de revertir exige que el núcleo `private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)`
-- sea EXACTAMENTE el que dejó la migración: `md5(prosrc)` = `f74838f274a8db971952eb9c09c7387e` Y `md5(pg_get_functiondef)` =
-- `c56e4abd191b947177a9179a7d558dbd` (cuerpo y atributos que entran en la definición: DEFINER, `SET`, volatilidad, firma) Y, como
-- eso no incluye el dueño, los permisos ni el comentario (ronda 3: Codex P1, auditor F4), su FICHA: dueño `postgres`, DEFINER,
-- `proconfig` exactamente `{search_path="", lock_timeout=5s}`, ACL exactamente `postgres:EXECUTE` sin opción de concesión, ningún
-- EXECUTE para anon, authenticated ni service_role, y el comentario que dejó la 2.7 (`md5` del comentario = 31159d826a407c91173e3870b5711352).
-- Se niega si la migración no está aplicada, si alguien cambió el CUERPO después, un ATRIBUTO (p. ej. `ALTER FUNCTION … SET
-- statement_timeout` o INVOKER), un PERMISO (p. ej. `GRANT EXECUTE … TO authenticated`), el DUEÑO o el COMENTARIO: en esos casos
-- NO se revierte nada y se revisa a mano (o se corrige hacia delante con otra migración). No se promete tolerancia a derivas.
-- (Ensayado: `armar-ensayo.mjs --reversa-con-set` y `--reversa-deriva` aplican, añaden la deriva —un `SET statement_timeout`, un
-- GRANT a authenticated, un cambio de dueño— e intentan esta reversa: aborta en el preflight y la foto queda idéntica.)
--
-- QUÉ RESTAURA: el núcleo del 2.4, quitando del cuerpo vivo los DOS bloques que la migración insertó (la variable
-- `v_convertido` en las declaraciones y la regla 1b —teléfono y DNI— entre el filtro del veredicto y el candidato; cada uno tiene que aparecer
-- EXACTAMENTE una vez o la reversa aborta); lo que queda es, byte a byte, el cuerpo del 2.4: `md5(prosrc)` vuelve a
-- `bf0a7531ea589a52ba75680b44ef348e` y `md5(pg_get_functiondef)` a `65b400ec8f0607a3111ed03b851b3877`. Repone el comentario del
-- 2.4 (`md5` `e744b3fd7628b9bafb2ab1647a607a58`). El postflight exige esas huellas, el comentario del 2.4 y la ficha y la ACL EXACTAS
-- del 2.4 (las mismas que exige el preflight de la migración), no una foto tomada justo antes de revertir.
--
-- QUÉ CONSERVA: firma, dueño, `security definer`, `search_path` vacío, `lock_timeout` y ACL del núcleo (`create or replace` no los
-- toca; con el preflight de arriba, los que encuentra son los que dejó la migración, que a su vez exigió que fueran los auditados).
-- No toca el alta, el verificador ni nada más.
--
-- NO DESHACE DATOS: la regla no escribe ninguno. Tras revertir, el alta vuelve a crear un SEGUNDO lead de un cliente registrado solo
-- por teléfono (H-28) o por el DNI de un cliente sin persona (D-27): es el defecto que la migración cerraba. Se aplica por el mismo
-- ciclo que la migración. (Ronda 2: huellas y bloque de la regla con la búsqueda por DNI.)
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
begin
  if v_nucleo is null then
    raise exception 'REVERSA cliente_por_telefono: falta el núcleo private.alta_reactivar_retirado; nada que revertir';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo) is distinct from 'f74838f274a8db971952eb9c09c7387e' then
    raise exception 'REVERSA cliente_por_telefono: el cuerpo del núcleo no es el que dejó la migración (no está aplicada o cambió después); revisar antes de revertir';
  end if;
  if md5(pg_get_functiondef(v_nucleo)) is distinct from 'c56e4abd191b947177a9179a7d558dbd' then
    raise exception 'REVERSA cliente_por_telefono: el núcleo no tiene exactamente la definición que dejó la migración (un atributo cambió después sin tocar el cuerpo, p. ej. un SET statement_timeout): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  -- Ronda 3 (Codex P1 / auditor F4): lo que la definición no incluye. Dueño, DEFINER, configuración exacta, ACL exacta (con la opción
  -- de concesión), nadie más con EXECUTE y el comentario que dejó la 2.7: si algo de eso cambió después, no se revierte a ciegas.
  if not exists (select 1 from pg_proc p
                  where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = v_nucleo)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE')
     or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    raise exception 'REVERSA cliente_por_telefono: la ficha del núcleo no es la que dejó la migración (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres sin opción de concesión): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  if md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from '31159d826a407c91173e3870b5711352' then
    raise exception 'REVERSA cliente_por_telefono: el comentario del núcleo no es el que dejó la migración: la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
end
$preflight$;

do $reemplazo$
declare
  v_firma regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_def   text;
  v_ancla text;
  v_orig  text;
  v_veces integer;
begin
  v_def := pg_get_functiondef(v_firma);

  -- Bloque 1: la variable de la regla, tal como la devuelve pg_get_functiondef.
  v_ancla := $r1$  v_respuesta jsonb;
  v_convertido record;
begin
$r1$;
  v_orig := $o1$  v_respuesta jsonb;
begin
$o1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_por_telefono: el bloque de las declaraciones aparece % veces en el núcleo (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 2: la regla 1b entre el filtro del veredicto y el candidato.
  v_ancla := $r2$  -- 1b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR TELÉFONO Y POR DNI (bloque 2.7; D-22, D-25 y D-27 de Miguel,
  --     08/10/2026; hallazgo H-28). Solo en un alta NUEVA: un reintento con rastro previo sigue fijado a la ficha de su rastro
  --     (R2-1…R4-1). Si el teléfono tecleado —o, si con él no casa ninguno, el DNI tecleado (D-27)— es el de un lead CONVERTIDO
  --     (activo o retirado), el alta no crea, no reactiva y no escribe nada: enlazado a una persona ⇒ el mismo juicio de
  --     identidad que da el DNI («ya es cliente» con su asesor, o «no contactar» si la persona está vetada; el respaldo de D-21 si
  --     el juicio no dice nada); sin persona ⇒ «ya es cliente» a nombre del dueño de esa ficha (formato del verificador, sin via).
  --     El teléfono manda sobre el DNI (también con OTRO DNI tecleado, D-25) y los dos van antes que cualquier retirado no
  --     convertido que case por teléfono o DNI (el candidato de abajo ya no llega a mirarse).
  if not v_reintento then
    select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
      into v_convertido
    from crm.leads l
    left join public.perfiles pv on pv.id = l.vendedor_id
    left join public.perfiles ps on ps.id = l.asignado_supervisor_id
    where l.etapa = 'convertido'
      and l.telefono = p_telefono
    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
    limit 1;
    if not found and p_dni is not null then
      select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
        into v_convertido
      from crm.leads l
      left join public.perfiles pv on pv.id = l.vendedor_id
      left join public.perfiles ps on ps.id = l.asignado_supervisor_id
      where l.etapa = 'convertido'
        and l.dni = p_dni
      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
      limit 1;
    end if;
    if found then
      if v_convertido.inversionista_id is not null then
        v_fresco := private.juicio_persona(private.inversionista_canonica(v_convertido.inversionista_id), null);
        return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
      end if;
      return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_convertido.tenedor, 'sin asesor asignado'));
    end if;
  end if;

  <<rama>>
$r2$;
  v_orig := $o2$  <<rama>>
$o2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_por_telefono: el bloque de la regla aparece % veces en el núcleo (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  execute v_def;
end
$reemplazo$;

comment on function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb) is
  'Nucleo de crm.crear_lead_si_disponible (bloque 2.4, D-11/Q1, D-15, D-21): si la persona ya tuvo un lead RETIRADO (activo=false, no convertido, sin veto) y ningun lead activo, veto ni identidad coinciden con lo tecleado ni con lo que esa ficha conserva, reactiva esa ficha a nombre del destino del alta (FOR UPDATE, candados de persona, valvulas solo alrededor del UPDATE), conserva sus datos, deja la actividad reactivacion_alta con id = p_id (idempotencia por actor y huella sin DNI) y responde estado reutilizado; un reintento tras un segundo retiro reactiva LA MISMA ficha del primer rastro (nunca otra del mismo contacto); un reintento con rastro previo nunca crea otra ficha: si su ficha ya no existe responde 22023, si quedo vetada no contactar, si esta enlazada o convertida ya es cliente (R3-1), y si otro lead activo coincide con lo tecleado sin que el verificador lo califique responde tomado o en bolsa para ese lead, o 22023 (R4-1); un retirado enlazado a persona bloquea (ya es cliente) tambien por telefono, y tambien otro retirado enlazado que casa por el DNI tecleado; un lead activo por un dato conservado bloquea con el veredicto del verificador; solo los indices de contacto vivo (23505) y el CHECK del capital (23514) son veredicto fresco, cualquier otro error se propaga; devuelve NULL cuando no actua. Exige p_actor = auth.uid(). Solo lo llama el alta.';

do $postflight$
declare
  v_nucleo regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo) is distinct from 'bf0a7531ea589a52ba75680b44ef348e'
     or md5(pg_get_functiondef(v_nucleo)) is distinct from '65b400ec8f0607a3111ed03b851b3877' then
    raise exception 'REVERSA cliente_por_telefono: el núcleo no quedó como lo dejó el bloque 2.4';
  end if;
  if position('v_convertido' in (select p.prosrc from pg_proc p where p.oid = v_nucleo)) <> 0 then
    raise exception 'REVERSA cliente_por_telefono: la regla sigue en el núcleo';
  end if;
  if md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from 'e744b3fd7628b9bafb2ab1647a607a58' then
    raise exception 'REVERSA cliente_por_telefono: el comentario del núcleo no volvió al del 2.4';
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = v_nucleo)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE')
     or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    raise exception 'REVERSA cliente_por_telefono: el núcleo no quedó con la ficha y la ACL exactas del 2.4 (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres sin opción de concesión)';
  end if;
end
$postflight$;

commit;

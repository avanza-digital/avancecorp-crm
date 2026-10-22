-- REVERSA de 20261022170700_crm_alternativo_cliente_no_toma_lead.sql («El teléfono alternativo de un CLIENTE no puede ser el número de
-- un lead que ya existe», bloque 2.13). GENERADA desde la migración (sus anclas y su comentario, byte a byte; generador en
-- fase-2/bloque-2.13/salidas/trabajo/generadores/generar-reversa.py): no editar a mano sin volver a ensayarla.
--
-- FALLA CERRADA. Antes de revertir exige EXACTAMENTE lo que deja la migración, también lo que la definición no incluye:
--   · la pieza `private.juicio_lead_vivo_por_numero(text,uuid)`: cuerpo y definición (`md5` 2ade8f1b7f020b8aca16de0361f4d5c0/18d344cd251b79b3fcc851c2ac6114ce), INVOKER de postgres,
--     STABLE, `search_path` vacío y nada más, EXECUTE solo para postgres sin opción de concesión, nadie más con EXECUTE, y su comentario
--     (`md5` cf8d4141b2e4d225796250c56b8ee498);
--   · el disparador `private.trg_leads_disponibilidad_atomica()`: 9bb6fb76c3715364c6adca8401ade0b6/d882780ca2449f7fbcadf4b0ce84cdf2, su ficha (dueño postgres, DEFINER, `proconfig`
--     exacto, ACL `postgres:EXECUTE` sin opción de concesión, nadie más) y su comentario (`md5` 7ba4e553c1543c070ac1754f8e2dd6d0);
--   · los disparadores de tabla de disponibilidad como los deja el 2.8 (`md5` de su definición a585ac769d92cd1f2aba0c4cf49ca83a y
--     fd430e026c17ce4ca3ed0d74b48ba0e1), habilitados;
--   · y que NADIE MÁS use la pieza: ni otra función por su cuerpo (búsqueda de texto SIN distinguir mayúsculas: PL/pgSQL no registra
--     dependencias, y `PRIVATE.JUICIO_LEAD_VIVO_POR_NUMERO(…)` llama a la misma función), ni un trabajo programado (`cron.job.command`,
--     si la tabla existe), ni una vista, una policy, un default, un CHECK, un disparador o una función SQL `BEGIN ATOMIC` (dependencias
--     registradas en `pg_depend`). Es una búsqueda TEXTUAL Y CONSERVADORA: un comentario o una cadena con ese nombre también la
--     bloquean («posible llamador: inspeccionar antes de revertir»). LÍMITE DECLARADO: una llamada construida en tiempo de ejecución o
--     hecha desde fuera de la base no se ve; por eso el DROP va SIN CASCADE (RESTRICT).
-- Si algo de eso cambió después (un cuerpo, un SET, un permiso, un dueño, un comentario, un disparador deshabilitado), NO se revierte
-- nada y se revisa a mano (o se corrige hacia delante con otra migración).
--
-- QUÉ RESTAURA: el disparador del 2.8 (ronda 4) quitando del cuerpo vivo los dos bloques que la migración puso (cada uno tiene que
-- aparecer EXACTAMENTE una vez); su comentario de antes (se quita el añadido del 2.13, exactamente una vez y al final); y BORRA la
-- pieza. El postflight exige las huellas del 2.8 (50a6ff4365ffa6bedfd77d215ce31666 / 418b097675753ed9f81931a485b17c94, comentario
-- 4a3fee01861a0fc10af38eb3fc338eb2), la misma ficha y ACL, los disparadores de tabla intactos (mismo oid) y que la pieza ya no exista.
--
-- NO DESHACE DATOS: la regla no escribe ninguno. Tras revertir, el alternativo de un cliente vuelve a poder ser el número de un lead
-- vivo que no es cliente. Se aplica por el mismo ciclo que la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  v_pieza regprocedure := to_regprocedure('private.juicio_lead_vivo_por_numero(text,uuid)');
  v_disp regprocedure := to_regprocedure('private.trg_leads_disponibilidad_atomica()');
  v_mal text;
  v_cron text;
begin
  if v_pieza is null or v_disp is null then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: falta la pieza o el disparador: la migración no está aplicada; nada que revertir';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza)
       is distinct from '2ade8f1b7f020b8aca16de0361f4d5c0/18d344cd251b79b3fcc851c2ac6114ce'
     or not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                      and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_pieza, 'EXECUTE') or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE')
     or md5(coalesce(obj_description(v_pieza, 'pg_proc'), '')) is distinct from 'cf8d4141b2e4d225796250c56b8ee498' then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: la pieza private.juicio_lead_vivo_por_numero no es la que dejó la migración (cuerpo, ficha, permisos o comentario): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  -- Nadie más usa la pieza: otros cuerpos de función (texto, en minúsculas), los comandos de los trabajos programados (`cron.job`, si
  -- la tabla existe) y las dependencias registradas. Búsqueda conservadora; lo dinámico no se ve (límite declarado en la cabecera).
  select string_agg(u.quien, ', ' order by u.quien) into v_mal
  from (select 'función ' || p.oid::regprocedure::text || ' (texto del cuerpo)' as quien
          from pg_proc p
         where p.oid not in (v_pieza, v_disp)
           and position('juicio_lead_vivo_por_numero' in lower(coalesce(p.prosrc, ''))) > 0
        union
        select pg_describe_object(d.classid, d.objid, d.objsubid) || ' (dependencia registrada)'
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_pieza) u;
  if to_regclass('cron.job') is not null then
    execute $cron$select string_agg('cron.job ' || j.jobid::text || coalesce(' «' || j.jobname || '»', '') || ' (texto del comando)', ', ' order by j.jobid)
                    from cron.job j where position('juicio_lead_vivo_por_numero' in lower(coalesce(j.command, ''))) > 0$cron$
      into v_cron;
    v_mal := nullif(concat_ws(', ', v_mal, v_cron), '');
  end if;
  if v_mal is not null then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: posible llamador de la pieza private.juicio_lead_vivo_por_numero (%): inspeccionar antes de revertir; la reversa falla cerrada (el DROP va sin CASCADE). La búsqueda es textual y conservadora: un comentario o una cadena con ese nombre también la bloquean', v_mal;
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_disp)
       is distinct from '9bb6fb76c3715364c6adca8401ade0b6/d882780ca2449f7fbcadf4b0ce84cdf2' then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: el disparador no tiene exactamente la definición que dejó la migración (cuerpo o atributo, p. ej. un SET): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_disp)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_disp, 'EXECUTE') or has_function_privilege('authenticated', v_disp, 'EXECUTE')
     or has_function_privilege('service_role', v_disp, 'EXECUTE')
     or md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '7ba4e553c1543c070ac1754f8e2dd6d0' then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: la ficha o el comentario del disparador no son los que dejó la migración (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update') is distinct from 'a585ac769d92cd1f2aba0c4cf49ca83a|O'
     or (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O' then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: los disparadores de tabla de disponibilidad no son los que dejó la migración (definición o estado): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  perform set_config('alternativo_cliente.reversa_trg_oid',
    (select t.oid::text from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'), true);
end
$preflight$;

-- El disparador del 2.8: se quitan los dos bloques del 2.13 (cada uno EXACTAMENTE una vez).
do $reemplazo$
declare
  v_firma regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_orig text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;

  v_ancla := $r1$        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);
        -- Bloque 2.13 (D-49 de Miguel, 09/10/2026; ronda 2, auditor P3-1). Si la ficha es de un CLIENTE —ya era `convertido`, o lo
        -- queda bajo la válvula privilegiada (la conversión real); una conversión ilegal sin válvula no llega aquí: la para después la
        -- guarda de la conversión, sin veredicto— y su alternativo nuevo no es el número de otro cliente (el 2.8, arriba, manda),
        -- tampoco puede ser el teléfono ni el alternativo de OTRO lead VIVO (`private.juicio_lead_vivo_por_numero`: en forma canónica,
        -- nunca contra la propia ficha): el veredicto que la disponibilidad da hoy a ese lead («tomado» con su asesor, «en_bolsa», su
        -- veto o «ya_es_cliente» por su perfil del Portal), con el rol primero y el mismo P0481 de abajo.
        if v_cliente is null and new.etapa = 'convertido' and (old.etapa = 'convertido' or v_priv) then
          v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);
        end if;
        if v_cliente is not null then
          v_rol := private.rol_crm(v_actor);
$r1$;
  v_orig := $o1$        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);
        if v_cliente is not null then
          v_rol := private.rol_crm(v_actor);
$o1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: el bloque del 2.13 en la rama del alternativo aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  v_ancla := $r2$      case when not v_priv and new.dni is distinct from old.dni then new.dni end,
      old.id);
    -- Bloque 2.13 (D-49; ronda 2, auditor P3-1): con el teléfono o el DNI, el alternativo nuevo de un CLIENTE (ya convertido, o que lo
    -- queda bajo la válvula privilegiada) tampoco puede ser el número de OTRO lead vivo (la misma pieza y el mismo veredicto que en la
    -- rama del alternativo; el rol ya se comprobó al entrar en esta rama).
    if v_cliente is null and new.etapa = 'convertido' and (old.etapa = 'convertido' or v_priv)
       and new.telefono_alternativo is distinct from old.telefono_alternativo then
      v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);
    end if;
    if v_cliente is not null then
      raise exception using
$r2$;
  v_orig := $o2$      case when not v_priv and new.dni is distinct from old.dni then new.dni end,
      old.id);
    if v_cliente is not null then
      raise exception using
$o2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: el bloque del 2.13 en la rama del teléfono aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: los permisos del disparador cambiaron al revertir';
  end if;
end
$reemplazo$;

-- El comentario de antes: se quita el añadido del 2.13 (exactamente una vez y al final).
do $comentario$
declare
  v_com text := obj_description('private.trg_leads_disponibilidad_atomica()'::regprocedure, 'pg_proc');
  v_sufijo text := $sufijo$ Bloque 2.13 (D-49, D-64, D-67; ronda 2): con sesion, si el lead es cliente (ya era convertido, o lo queda bajo la valvula privilegiada: la conversion) y su telefono alternativo cambia, el nuevo no puede ser el telefono ni el alternativo de otro lead vivo que no es cliente (private.juicio_lead_vivo_por_numero, en forma canonica; nunca contra el propio lead): P0481 Contacto no disponible con el veredicto de la disponibilidad de hoy para el telefono de ese lead (tomado con su asesor, en_bolsa, no_contactar o ya_es_cliente), despues de los veredictos de hoy y de la regla del 2.8; si solo cambia el alternativo, primero el rol. Una conversion sin valvula no llega a esta regla. Sin sesion, la regla no se aplica.$sufijo$;
begin
  if v_com is null or (length(v_com) - length(replace(v_com, v_sufijo, ''))) / length(v_sufijo) <> 1
     or right(v_com, length(v_sufijo)) is distinct from v_sufijo then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead: el comentario del disparador no termina en el añadido del 2.13 (exactamente una vez)';
  end if;
  execute pg_catalog.format('comment on function private.trg_leads_disponibilidad_atomica() is %L', left(v_com, length(v_com) - length(v_sufijo)));
end
$comentario$;

-- La pieza, SIN CASCADE: si algo registrado la usa, PostgreSQL lo para.
drop function private.juicio_lead_vivo_por_numero(text, uuid);

do $postflight$
declare
  v_disp regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
begin
  if to_regprocedure('private.juicio_lead_vivo_por_numero(text,uuid)') is not null
     or exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'juicio_lead_vivo_por_numero') then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead (postflight): la pieza sigue existiendo';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_disp)
       is distinct from '50a6ff4365ffa6bedfd77d215ce31666/418b097675753ed9f81931a485b17c94'
     or md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '4a3fee01861a0fc10af38eb3fc338eb2' then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead (postflight): el disparador no volvió exactamente al del 2.8 (cuerpo, definición o comentario)';
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_disp)
        is distinct from array['postgres:EXECUTE:false'] then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead (postflight): la ficha del disparador no es la del 2.8';
  end if;
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text || '|' || t.oid::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update')
       is distinct from 'a585ac769d92cd1f2aba0c4cf49ca83a|O|' || current_setting('alternativo_cliente.reversa_trg_oid', true)
     or (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O' then
    raise exception 'REVERSA alternativo_cliente_no_toma_lead (postflight): los disparadores de tabla de disponibilidad cambiaron';
  end if;
  raise notice 'REVERSA alternativo_cliente_no_toma_lead: disparador del 2.8 (50a6ff43… / 418b0976…, comentario 4a3fee01…) repuesto, pieza borrada, disparadores de tabla intactos';
end
$postflight$;

commit;

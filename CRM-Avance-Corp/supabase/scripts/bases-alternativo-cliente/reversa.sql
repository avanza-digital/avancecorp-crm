-- REVERSA de 20261022170500_crm_bases_alternativo_cliente.sql («La carga de bases también mira el teléfono alternativo de los
-- clientes», bloque 2.9). GENERADA desde la migración (su ancla, su bloque y su frase, byte a byte; sus huellas y su lista de
-- dependencias; generador en fase-2/bloque-2.9/salidas/ronda2/trabajo/generadores/generar-reversa-r2.py): no editar a mano sin
-- volver a ensayarla.
--
-- FALLA CERRADA. Antes de revertir exige EXACTAMENTE lo que deja la migración:
--   · el envoltorio `private.bases_carga_contacto_existente(text,text)`: cuerpo y definición (`md5` bcb6a83abdd7225bc048bfa4713ed8cf /
--     76773d711c6c317153833456c1ed6bdb), INVOKER de postgres, STABLE, `search_path` vacío y nada más, EXECUTE solo para postgres sin
--     opción de concesión y nadie más con EXECUTE, y su comentario (`md5` bfe5c84dce3ec76d854e6edc72d13ef9);
--   · las doce funciones que fija la migración (sus dos llamadores, la puerta, los dos verificadores, la normalización, la cadena del
--     ámbito y del id, la función del candado), intactas (definición, dueño y ACL);
--   · y (ronda 2, Codex P2-2) que NADIE MÁS consuma el envoltorio (salvo el núcleo y el ámbito), la regla del ámbito (salvo el núcleo)
--     ni el núcleo (salvo la puerta): volver a B8 le quitaría a ese consumidor el alternativo de los clientes en silencio. Referencias
--     LITERALES en los cuerpos (sin distinguir mayúsculas), dependencias registradas en pg_depend y comandos de cron.job visibles para
--     quien revierte; conservadora (un comentario con el nombre también bloquea: se inspecciona) y sin ver el SQL dinámico.
-- Si algo de eso cambió después (un cuerpo, un SET, un permiso, un dueño, un comentario, un consumidor nuevo), NO se revierte nada y se
-- revisa a mano (o se corrige hacia delante con otra migración). No se promete tolerancia a derivas (ensayado: `armar-ensayo.mjs
-- --reversa-deriva`).
--
-- QUÉ RESTAURA: el cuerpo de B8, quitando del WHERE lo que la migración puso (el bloque tiene que aparecer EXACTAMENTE una vez), y el
-- comentario de B8 (se quita el añadido del 2.9, que tiene que estar exactamente al final). El postflight exige las huellas de B8
-- (cf6489ee72122a33fd9c1da9b5e9446c / 563274f8186a7b8a186ec27322d69eb0, comentario 1e1052db90104b21bef5b9a1c6267f38), la misma ficha
-- y ACL, y las doce funciones intactas.
--
-- NO DESHACE DATOS: la regla no escribe ninguno. Tras revertir, una fila de una base con el alternativo de un cliente vuelve a
-- cargarse como contacto dormido. Se aplica por el mismo ciclo que la migración. Orden: la reversa del 2.8 entra con el 2.9 aplicado
-- (ensayado), pero se recomienda revertir en orden inverso al de aplicación (LIFO).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  v_env regprocedure := to_regprocedure('private.bases_carga_contacto_existente(text,text)');
  v_nucleo regprocedure := to_regprocedure('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)');
  v_ambito regprocedure := to_regprocedure('private.bases_carga_fuera_de_ambito(uuid,text,text,text)');
  v_puerta regprocedure := to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)');
  v_mal text;
  v_cron text;
begin
  if v_env is null or v_nucleo is null or v_ambito is null or v_puerta is null then
    raise exception 'REVERSA bases_alternativo_cliente: falta el envoltorio, el núcleo, la regla del ámbito o la puerta de la carga; nada que revertir';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_env)
       is distinct from 'bcb6a83abdd7225bc048bfa4713ed8cf/76773d711c6c317153833456c1ed6bdb' then
    raise exception 'REVERSA bases_alternativo_cliente: el envoltorio no es el que deja la migración (md5 del cuerpo / de la definición %): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_env);
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_env and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_env)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_env, 'EXECUTE') or has_function_privilege('authenticated', v_env, 'EXECUTE')
     or has_function_privilege('service_role', v_env, 'EXECUTE') then
    raise exception 'REVERSA bases_alternativo_cliente: la ficha del envoltorio no es la esperada (dueño postgres, security invoker, stable, search_path vacío, EXECUTE solo para postgres sin opción de concesión): revisar a mano';
  end if;
  if md5(coalesce(obj_description(v_env, 'pg_proc'), '')) is distinct from 'bfe5c84dce3ec76d854e6edc72d13ef9' then
    raise exception 'REVERSA bases_alternativo_cliente: el comentario del envoltorio no es el que deja la migración: revisar a mano';
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.cargar_base_lote(uuid,uuid,jsonb)', 'b03d2e9d4500ca54fb8aec014786653a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)', 'e5f25344437c0c54b289d4ae294b5e39', 'postgres:EXECUTE:false'),
    ('private.bases_carga_fuera_de_ambito(uuid,text,text,text)', '7341099506af3a2f2af3eeb9ec0862e4', 'postgres:EXECUTE:false'),
    ('private.bases_carga_lead_ref(uuid,text,uuid)', 'db760dd5ae42b06a886b9420fa927be8', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.es_lector_global()', 'c8be602f84348a0125617995802db618', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'REVERSA bases_alternativo_cliente: cambió un llamador del envoltorio, la puerta o una pieza que decide su efecto: revisar a mano (%)', v_mal;
  end if;
  -- Nadie más consume el envoltorio (salvo el núcleo y el ámbito), la regla del ámbito (salvo el núcleo) ni el núcleo (salvo la puerta)
  -- (ronda 2, Codex P2-2): si alguien los usara, volver a B8 le quitaría el alternativo de los clientes EN SILENCIO (revertir no
  -- necesita borrar un objeto para romper su contrato). Referencias LITERALES en los cuerpos (sin distinguir mayúsculas), objetos
  -- registrados en pg_depend y comandos de cron.job visibles; conservadora (un comentario con el nombre también bloquea); no ve el SQL
  -- dinámico.
  select string_agg(x.quien, ', ' order by x.quien) into v_mal
  from (select p.oid::regprocedure::text || ' → ' || o.nombre as quien
          from (values ('bases_carga_contacto_existente', array[v_env::oid, v_nucleo::oid, v_ambito::oid]),
                       ('bases_carga_fuera_de_ambito', array[v_ambito::oid, v_nucleo::oid]),
                       ('bases_carga_cargar_lote_core', array[v_nucleo::oid, v_puerta::oid])) o(nombre, permitidos)
          join pg_proc p on pg_catalog.strpos(pg_catalog.lower(coalesce(p.prosrc, '')), o.nombre) > 0
         where p.oid <> all (o.permitidos)
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid) || ' → ' || d.refobjid::regprocedure::text
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_env, v_ambito, v_nucleo)) x;
  if to_regclass('cron.job') is not null then
    execute $cron$select string_agg(j.jobid::text, ', ' order by j.jobid) from cron.job j
                   where pg_catalog.strpos(pg_catalog.lower(coalesce(j.command, '')), 'bases_carga_contacto_existente') > 0
                      or pg_catalog.strpos(pg_catalog.lower(coalesce(j.command, '')), 'bases_carga_fuera_de_ambito') > 0
                      or pg_catalog.strpos(pg_catalog.lower(coalesce(j.command, '')), 'bases_carga_cargar_lote_core') > 0$cron$
      into v_cron;
  end if;
  if v_mal is not null or v_cron is not null then
    raise exception 'REVERSA bases_alternativo_cliente: posible consumidor del envoltorio, de la regla del ámbito o del núcleo (%; cron.job: %): revertir le quitaría el alternativo en silencio; inspeccionar antes de revertir',
      coalesce(v_mal, '-'), coalesce(v_cron, '-');
  end if;
end
$preflight$;

-- ── 1. El envoltorio vuelve al cuerpo de B8: se quita del WHERE el bloque del 2.9 (exactamente una vez) ───────────────────
do $envoltorio$
declare
  v_firma regprocedure := 'private.bases_carga_contacto_existente(text,text)'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;
  v_ancla := $n29$   where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)
      -- Bloque 2.9 (D-37 de Miguel, 09/10/2026): también el TELÉFONO ALTERNATIVO de un cliente ya convertido (lead en etapa
      -- convertido, activo o retirado), dentro del mismo conjunto: la misma categoría y el mismo orden de relevancia que cualquier
      -- otra coincidencia (gana la más relevante). El alternativo de un lead que no es cliente no cuenta (D-37). Comparación literal
      -- de formas canónicas, como la regla del 2.8 (D-30): el alternativo se guarda en E.164 (CHECK leads_telefono_alternativo_formato)
      -- y el teléfono de la fila llega normalizado.
      or (l.etapa = 'convertido' and l.telefono_alternativo = p_telefono)
$n29$;
  v_nuevo := $b8$   where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)
$b8$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA bases_alternativo_cliente: el bloque del 2.9 en el WHERE del envoltorio aparece % veces (debe ser 1)', v_veces;
  end if;
  execute replace(v_def, v_ancla, v_nuevo);
  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'REVERSA bases_alternativo_cliente: los permisos del envoltorio cambiaron al revertir';
  end if;
end
$envoltorio$;

-- ── 2. El comentario vuelve al de B8: se quita la frase del 2.9 (exactamente al final) ───────────────────────────────────
do $comentario$
declare
  v_com text := obj_description('private.bases_carga_contacto_existente(text,text)'::regprocedure, 'pg_proc');
  v_frase text := $f29$ Bloque 2.9 (D-37): tambien el telefono alternativo de un cliente ya convertido (lead en etapa convertido, activo o retirado), dentro del mismo conjunto: la misma categoria y el mismo orden de relevancia que cualquier otra coincidencia (gana la mas relevante; si alguna es de otro equipo, la regla del ambito oculta motivo e id); el alternativo de un lead que no es cliente no cuenta. Comparacion literal de formas canonicas, como la regla del 2.8 (D-30).$f29$;
begin
  if v_com is null or right(v_com, length(v_frase)) is distinct from v_frase then
    raise exception 'REVERSA bases_alternativo_cliente: el comentario del envoltorio no termina con la frase del 2.9';
  end if;
  execute pg_catalog.format('comment on function private.bases_carga_contacto_existente(text, text) is %L',
    left(v_com, length(v_com) - length(v_frase)));
end
$comentario$;

-- ── Postflight: las huellas de B8 ────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_env regprocedure := 'private.bases_carga_contacto_existente(text,text)'::regprocedure;
  v_mal text;
begin
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_env)
       is distinct from 'cf6489ee72122a33fd9c1da9b5e9446c/563274f8186a7b8a186ec27322d69eb0'
     or md5(coalesce(obj_description(v_env, 'pg_proc'), '')) is distinct from '1e1052db90104b21bef5b9a1c6267f38' then
    raise exception 'REVERSA bases_alternativo_cliente: el envoltorio no volvió exactamente a B8 (md5 %, comentario %)',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_env),
      md5(coalesce(obj_description(v_env, 'pg_proc'), ''));
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_env and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_env)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_env, 'EXECUTE') or has_function_privilege('authenticated', v_env, 'EXECUTE')
     or has_function_privilege('service_role', v_env, 'EXECUTE') then
    raise exception 'REVERSA bases_alternativo_cliente: la ficha del envoltorio no es la esperada (dueño postgres, security invoker, stable, search_path vacío, EXECUTE solo para postgres sin opción de concesión): revisar a mano';
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.cargar_base_lote(uuid,uuid,jsonb)', 'b03d2e9d4500ca54fb8aec014786653a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)', 'e5f25344437c0c54b289d4ae294b5e39', 'postgres:EXECUTE:false'),
    ('private.bases_carga_fuera_de_ambito(uuid,text,text,text)', '7341099506af3a2f2af3eeb9ec0862e4', 'postgres:EXECUTE:false'),
    ('private.bases_carga_lead_ref(uuid,text,uuid)', 'db760dd5ae42b06a886b9420fa927be8', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.es_lector_global()', 'c8be602f84348a0125617995802db618', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'REVERSA bases_alternativo_cliente: cambió algo que la reversa no toca (%)', v_mal;
  end if;
  raise notice 'REVERSA bases_alternativo_cliente: el envoltorio de B8 repuesto (cuerpo, definición, ficha y comentario) · las doce funciones intactas';
end
$postflight$;

commit;

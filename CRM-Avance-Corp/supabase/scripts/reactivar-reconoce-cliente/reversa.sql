-- REVERSA de 20261022170600_crm_reactivar_reconoce_cliente.sql («Reactivar una ficha retirada —o un lead de la base para gestión—
-- también reconoce al cliente», bloque 2.11). GENERADA desde la migración (sus anclas y sus frases, byte a byte; generador en
-- fase-2/bloque-2.11/salidas/trabajo/generadores/generar-reversa.py): no editar a mano sin volver a ensayarla.
--
-- FALLA CERRADA. Antes de revertir exige EXACTAMENTE lo que deja la migración:
--   · la pieza `private.juicio_cliente_conservado(uuid)`: cuerpo y definición (`md5` 78208791362fa74fda4b67de6dd6d259 / f5206895fbbd995a52b27cf5c80167bb), INVOKER de postgres,
--     volátil, `search_path` vacío y nada más, EXECUTE solo para postgres sin opción de concesión, y su comentario (4aa74d7ea8a98da72df1ddb5c4e0176c);
--   · el núcleo del alta (`md5` 9f26e7f962d21170b2c35e113442d026 / 9c09cca28fd81fa29f16133b2b57c328, comentario 40cf4271eed96a9119cfeb8433aceac8) y el de la base (c7bad703b3fd9e4d0c13372fdf2ba579 /
--     4d0841a94d320a985e4e6ec48d28f90f, comentario 38d94622c7a051548efb7cf3aa88fb06), con su ficha (dueño postgres, DEFINER, su SET, EXECUTE solo para postgres);
--   · que NADIE MÁS use la pieza: ni otra función por su cuerpo (sin distinguir mayúsculas), ni un objeto registrado en `pg_depend`, ni
--     un trabajo programado (`cron.job.command`, si existe). Un «posible llamador» bloquea de forma conservadora (un comentario o una
--     cadena con ese nombre también): se inspecciona antes de revertir;
--   · la pieza del 2.8 y lo que llama a los núcleos o decide su efecto, intactos (la misma lista de la migración).
-- Si algo de eso cambió después (un cuerpo, un SET, un permiso, un dueño, un comentario, otro llamador), NO se revierte nada y se revisa
-- a mano (o se corrige hacia delante con otra migración). No se promete tolerancia a derivas (ensayado: `armar-ensayo.mjs --reversa-deriva`).
--
-- QUÉ RESTAURA: los dos núcleos, quitando por ancla única lo que la migración puso (cada bloque tiene que aparecer EXACTAMENTE una vez),
-- y sus comentarios (se quita el añadido del 2.11, que tiene que estar exactamente al final); después borra la pieza, sin CASCADE. El
-- postflight exige las huellas de antes: el núcleo del alta del 2.8 ronda 4 (2fe5fdac50150d7429da2e422f43b92d /
-- 8d598eb4d0df994388337480e71e8005, comentario 8870de7f9d82c44b1a1f965f1e6d3ef0) y el de la base de B10 (479683a99720d554ff419752f3da7876
-- / 7b7818427c6e526152027bdea95b5c51, comentario 21f3e2c424b4ec59502af01ad775896f), la misma ficha y ACL, la pieza borrada y lo demás
-- intacto.
--
-- NO DESHACE DATOS: la regla no escribe ninguno. Tras revertir, reactivar una ficha retirada o un lead de la base que conserva el
-- contacto de un cliente vuelve a dejar un segundo lead activo del cliente. Se aplica por el mismo ciclo que la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_pieza regprocedure := to_regprocedure('private.juicio_cliente_conservado(uuid)');
  v_nucleo regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_nbase regprocedure := 'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure;
  v_mal text;
begin
  if v_pieza is null then
    raise exception 'REVERSA reactivar_reconoce_cliente: no existe private.juicio_cliente_conservado: la migración no está aplicada (nada que revertir)';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza) is distinct from '78208791362fa74fda4b67de6dd6d259/f5206895fbbd995a52b27cf5c80167bb' then
    raise exception 'REVERSA reactivar_reconoce_cliente: la pieza no es la que deja la migración (md5 del cuerpo / de la definición %): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza);
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.provolatile = 'v' and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_pieza, 'EXECUTE') or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE') then
    raise exception 'REVERSA reactivar_reconoce_cliente: la ficha de la pieza no es la esperada antes de revertir (dueño postgres, security invoker, volátil, search_path vacío, EXECUTE solo para postgres sin opción de concesión): revisar a mano';
  end if;
  if md5(coalesce(obj_description(v_pieza, 'pg_proc'), '')) is distinct from '4aa74d7ea8a98da72df1ddb5c4e0176c' then
    raise exception 'REVERSA reactivar_reconoce_cliente: el comentario de la pieza no es el que deja la migración: revisar a mano';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo) is distinct from '9f26e7f962d21170b2c35e113442d026/9c09cca28fd81fa29f16133b2b57c328'
     or (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nbase) is distinct from 'c7bad703b3fd9e4d0c13372fdf2ba579/4d0841a94d320a985e4e6ec48d28f90f' then
    raise exception 'REVERSA reactivar_reconoce_cliente: un núcleo no es el que deja la migración (alta %, base %): revisar a mano',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo),
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nbase);
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                   and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from 'postgres:EXECUTE:false'
     or not exists (select 1 from pg_proc p where p.oid = v_nbase and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nbase)
        is distinct from 'postgres:EXECUTE:false' then
    raise exception 'REVERSA reactivar_reconoce_cliente: la ficha de un núcleo no es la esperada (dueño postgres, security definer, su SET, EXECUTE solo para postgres): revisar a mano';
  end if;
  if md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from '40cf4271eed96a9119cfeb8433aceac8'
     or md5(coalesce(obj_description(v_nbase, 'pg_proc'), '')) is distinct from '38d94622c7a051548efb7cf3aa88fb06' then
    raise exception 'REVERSA reactivar_reconoce_cliente: el comentario de un núcleo no es el que deja la migración: revisar a mano';
  end if;
  -- Nadie más usa la pieza (su borrado lo rompería): cuerpos de función sin distinguir mayúsculas, pg_depend y cron.job.
  select string_agg(x.f, ', ' order by x.f) into v_mal
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where strpos(lower(p.prosrc), 'juicio_cliente_conservado') > 0 and p.oid not in (v_pieza, v_nucleo, v_nbase)
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_pieza) x;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'juicio_cliente_conservado') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'REVERSA reactivar_reconoce_cliente: otro posible llamador de la pieza (%): borrarla lo rompería; inspeccionar a mano', v_mal;
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.crear_lead_documento_fn(jsonb,text,text)', 'f6dfdc2907a1c3069e4988bf038d04c1', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)', 'e06eca2333bb11869d00913a004c8261', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reabrir_lead_fn(uuid)', '9cdac9e10f2efde549bbcbdf810b95d3', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reactivar_lead_base(uuid,uuid,text)', 'cf44c73e6326573dfbcb5defdb07fcf7', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', 'a8c982fb500bdc42b11032d4576ed953', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)', '2c360e0e2536096713059a9dbbcd1ef8', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)', '6f5971c0bf6f68285fadae5e30099ee2', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.alta_reactivar_bloqueo_conservado(uuid)', '2186e7c4b4e3ac4bcf23636cb951d9ba', 'postgres:EXECUTE:false'),
    ('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)', 'a4a0638e4ca2c8a89ad9909c522b4a92', 'postgres:EXECUTE:false'),
    ('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)', '83d99939149bbf445b5c77c33787f1cf', 'postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', 'c9e90784de512cc4c8e694a0465bc80c', 'postgres:EXECUTE:false'),
    ('private.base_gestion_rol(uuid)', '3c2d5feefd68589cfe82fc1fe2e95180', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.juicio_reapertura(uuid,text,text)', '47277cd689ad0e1713e436d3373e3521', 'postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.persona_vetada(uuid)', 'a70efe776fc56fd34d47e364e2e55571', 'postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'REVERSA reactivar_reconoce_cliente: cambió algo que llama a los núcleos o decide su efecto: revisar a mano (%)', v_mal;
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || coalesce(p.proacl::text, '-') || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
        from pg_proc p where p.oid = 'private.juicio_cliente_convertido(text,text,text,uuid)'::regprocedure)
       is distinct from '346f48a8648248b308628301d41bc4c0/a2b38faf42a875c7dffb7968b106e36f/{postgres=X/postgres}/e23707e521c5878f056c0b99b02a9651' then
    raise exception 'REVERSA reactivar_reconoce_cliente: cambió algo que llama a los núcleos o decide su efecto: revisar a mano (private.juicio_cliente_convertido)';
  end if;
  perform set_config('reversa_reconoce_cliente.nucleo_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_nucleo), true);
  perform set_config('reversa_reconoce_cliente.nbase_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_nbase), true);
end
$preflight$;

-- ── Los dos núcleos, por ancla única: se quita lo que puso la migración ─────────────────────────────────────────────
do $revertir$
declare
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  -- El núcleo del alta: el paso 7b fuera.
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_ancla := $r1$    -- 7. Veto de la persona (también la hallada solo por documento o puente).
    if private.persona_vetada(v_lead.id) then
      return pg_catalog.jsonb_build_object('estado', 'no_contactar');
    end if;

    -- 7b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR LO QUE LA FICHA CONSERVA (bloque 2.11; D-42 de Miguel, 09/10/2026; R2 y
    --     R3b de la ronda 3 del 2.8). Su teléfono, su teléfono alternativo y su DNI no pueden ser de un cliente ya convertido (activo
    --     o retirado), sin contarla a ella: la pieza `private.juicio_cliente_conservado` toma antes los candados de contacto de esos
    --     datos (la misma clave que tomará el disparador de disponibilidad al reactivar) y los juzga con la regla del 2.7/2.8. Si son
    --     de un cliente, no se reactiva ni se escribe nada y el alta responde ese veredicto («ya es cliente de X»: el formato y los
    --     datos del alta, D-29). También en un REINTENTO con rastro previo (D-61 de Miguel, 09/10/2026): la ficha es la misma y lo que
    --     se juzga es lo que ELLA conserva, no lo tecleado (que en el reintento sigue fuera de la regla 1b: R1 del 2.8). Va después de
    --     los veredictos de hoy (lo tecleado, 1b y 3a; lo conservado contra leads activos, 3b, que es lo que para R3a; la persona
    --     enlazada, D-21; la identidad, 6; el veto, 7), justo antes del UPDATE.
    v_fresco := private.juicio_cliente_conservado(v_lead.id);
    if v_fresco is not null then
      return v_fresco;
    end if;
$r1$;
  v_nuevo := $s1$    -- 7. Veto de la persona (también la hallada solo por documento o puente).
    if private.persona_vetada(v_lead.id) then
      return pg_catalog.jsonb_build_object('estado', 'no_contactar');
    end if;
$s1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA reactivar_reconoce_cliente: el bloque del 2.11 aparece % veces en el núcleo del alta (debe ser 1)', v_veces;
  end if;
  execute replace(v_def, v_ancla, v_nuevo);
  if (select p.proacl from pg_proc p where p.oid = 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure) is distinct from v_acl then
    raise exception 'REVERSA reactivar_reconoce_cliente: los permisos del núcleo del alta cambiaron al revertir';
  end if;
  -- El núcleo de la base: la regla y su variable fuera.
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = 'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure;
  v_ancla := $r2$  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  -- Bloque 2.11 (D-55 de Miguel, 09/10/2026; como D-42 en el alta; H-1 del 2.9): lo que el lead CONSERVA —su teléfono, su teléfono
  -- alternativo y su DNI— no puede ser de un cliente ya convertido (activo o retirado), sin contarlo a él: la pieza
  -- `private.juicio_cliente_conservado` (candados de contacto y la regla del 2.7/2.8). Si lo es, no se reactiva ni se escribe nada: el
  -- MISMO `P0481` «Contacto no disponible» con el que la edición y el INSERT responden esa regla (2.8), con el veredicto del alta
  -- («ya es cliente de X»; D-29) en el detalle. Después del ámbito (quien no ve el lead recibe P0002 y nunca el veredicto), del
  -- estado y del No contactar; antes del capital y de la reapertura. Lo heredan las tres reactivaciones de la base:
  -- crm.reactivar_lead_base_v2, crm.reactivar_lead_base y el intento «agendó cita».
  v_cliente := private.juicio_cliente_conservado(v_lead.id);
  if v_cliente is not null then
    raise exception using errcode = 'P0481', message = 'Contacto no disponible', detail = v_cliente::text;
  end if;
$r2$;
  v_nuevo := $s2$  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
$s2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA reactivar_reconoce_cliente: el bloque del 2.11 aparece % veces en el núcleo de la base (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);
  v_ancla := $r3$  v_resp jsonb;
  v_reabrir jsonb;
  v_cliente jsonb;
begin
$r3$;
  v_nuevo := $s3$  v_resp jsonb;
  v_reabrir jsonb;
begin
$s3$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA reactivar_reconoce_cliente: la variable del 2.11 aparece % veces en el núcleo de la base (debe ser 1)', v_veces;
  end if;
  execute replace(v_def, v_ancla, v_nuevo);
  if (select p.proacl from pg_proc p where p.oid = 'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure) is distinct from v_acl then
    raise exception 'REVERSA reactivar_reconoce_cliente: los permisos del núcleo de la base cambiaron al revertir';
  end if;
end
$revertir$;

-- ── Los comentarios: se quita el añadido del 2.11 (exactamente al final) ───────────────────────────────────────────
do $comentarios$
declare
  v_com text;
begin
  v_com := obj_description('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure, 'pg_proc');
  if right(v_com, length($f1$ Bloque 2.11 (D-42, D-61): antes de reactivar una ficha retirada (tambien en un reintento), lo que la ficha CONSERVA (telefono, alternativo y DNI) no puede ser de un cliente ya convertido, activo o retirado (private.juicio_cliente_conservado, bajo los candados de contacto de esos datos; nunca contra la propia ficha): si lo es, el alta responde ese veredicto (ya es cliente de X, formato del alta) y no reactiva ni escribe nada; va despues de los veredictos de hoy.$f1$)) is distinct from $f1$ Bloque 2.11 (D-42, D-61): antes de reactivar una ficha retirada (tambien en un reintento), lo que la ficha CONSERVA (telefono, alternativo y DNI) no puede ser de un cliente ya convertido, activo o retirado (private.juicio_cliente_conservado, bajo los candados de contacto de esos datos; nunca contra la propia ficha): si lo es, el alta responde ese veredicto (ya es cliente de X, formato del alta) y no reactiva ni escribe nada; va despues de los veredictos de hoy.$f1$ then
    raise exception 'REVERSA reactivar_reconoce_cliente: el comentario del núcleo del alta no termina con el añadido del 2.11';
  end if;
  execute pg_catalog.format('comment on function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb) is %L',
    left(v_com, length(v_com) - length($f1$ Bloque 2.11 (D-42, D-61): antes de reactivar una ficha retirada (tambien en un reintento), lo que la ficha CONSERVA (telefono, alternativo y DNI) no puede ser de un cliente ya convertido, activo o retirado (private.juicio_cliente_conservado, bajo los candados de contacto de esos datos; nunca contra la propia ficha): si lo es, el alta responde ese veredicto (ya es cliente de X, formato del alta) y no reactiva ni escribe nada; va despues de los veredictos de hoy.$f1$)));
  v_com := obj_description('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure, 'pg_proc');
  if right(v_com, length($f2$ Bloque 2.11 (D-55): antes de reactivar, lo que el lead CONSERVA (telefono, alternativo y DNI) no puede ser de un cliente ya convertido, activo o retirado (private.juicio_cliente_conservado; nunca contra el propio lead): si lo es, P0481 Contacto no disponible con el veredicto del alta (ya es cliente de X) en el detalle, y nada se escribe; despues del ambito, del estado y del No contactar, antes del capital y de la reapertura.$f2$)) is distinct from $f2$ Bloque 2.11 (D-55): antes de reactivar, lo que el lead CONSERVA (telefono, alternativo y DNI) no puede ser de un cliente ya convertido, activo o retirado (private.juicio_cliente_conservado; nunca contra el propio lead): si lo es, P0481 Contacto no disponible con el veredicto del alta (ya es cliente de X) en el detalle, y nada se escribe; despues del ambito, del estado y del No contactar, antes del capital y de la reapertura.$f2$ then
    raise exception 'REVERSA reactivar_reconoce_cliente: el comentario del núcleo de la base no termina con el añadido del 2.11';
  end if;
  execute pg_catalog.format('comment on function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text) is %L',
    left(v_com, length(v_com) - length($f2$ Bloque 2.11 (D-55): antes de reactivar, lo que el lead CONSERVA (telefono, alternativo y DNI) no puede ser de un cliente ya convertido, activo o retirado (private.juicio_cliente_conservado; nunca contra el propio lead): si lo es, P0481 Contacto no disponible con el veredicto del alta (ya es cliente de X) en el detalle, y nada se escribe; despues del ambito, del estado y del No contactar, antes del capital y de la reapertura.$f2$)));
end
$comentarios$;

-- ── La pieza, sin CASCADE (si algo la usara, el borrado fallaría) ───────────────────────────────────────────────────
drop function private.juicio_cliente_conservado(uuid);

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_nucleo regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_nbase regprocedure := 'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure;
  v_mal text;
begin
  if to_regprocedure('private.juicio_cliente_conservado(uuid)') is not null
     or exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'juicio_cliente_conservado') then
    raise exception 'REVERSA reactivar_reconoce_cliente: la pieza sigue existiendo';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
        from pg_proc p where p.oid = v_nucleo)
       is distinct from '2fe5fdac50150d7429da2e422f43b92d/8d598eb4d0df994388337480e71e8005/8870de7f9d82c44b1a1f965f1e6d3ef0' then
    raise exception 'REVERSA reactivar_reconoce_cliente: el núcleo del alta no volvió al del 2.8 ronda 4 (%)',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) from pg_proc p where p.oid = v_nucleo);
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
        from pg_proc p where p.oid = v_nbase)
       is distinct from '479683a99720d554ff419752f3da7876/7b7818427c6e526152027bdea95b5c51/21f3e2c424b4ec59502af01ad775896f' then
    raise exception 'REVERSA reactivar_reconoce_cliente: el núcleo de la base no volvió al de B10 (%)',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) from pg_proc p where p.oid = v_nbase);
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_nucleo) is distinct from current_setting('reversa_reconoce_cliente.nucleo_antes', true)
     or (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_nbase) is distinct from current_setting('reversa_reconoce_cliente.nbase_antes', true) then
    raise exception 'REVERSA reactivar_reconoce_cliente: la ficha de un núcleo cambió al revertir';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                   and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from 'postgres:EXECUTE:false'
     or not exists (select 1 from pg_proc p where p.oid = v_nbase and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nbase)
        is distinct from 'postgres:EXECUTE:false' then
    raise exception 'REVERSA (postflight) reactivar_reconoce_cliente: la ficha de un núcleo no es la esperada (dueño postgres, security definer, su SET, EXECUTE solo para postgres): revisar a mano';
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.crear_lead_documento_fn(jsonb,text,text)', 'f6dfdc2907a1c3069e4988bf038d04c1', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)', 'e06eca2333bb11869d00913a004c8261', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reabrir_lead_fn(uuid)', '9cdac9e10f2efde549bbcbdf810b95d3', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reactivar_lead_base(uuid,uuid,text)', 'cf44c73e6326573dfbcb5defdb07fcf7', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', 'a8c982fb500bdc42b11032d4576ed953', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)', '2c360e0e2536096713059a9dbbcd1ef8', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)', '6f5971c0bf6f68285fadae5e30099ee2', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.alta_reactivar_bloqueo_conservado(uuid)', '2186e7c4b4e3ac4bcf23636cb951d9ba', 'postgres:EXECUTE:false'),
    ('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)', 'a4a0638e4ca2c8a89ad9909c522b4a92', 'postgres:EXECUTE:false'),
    ('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)', '83d99939149bbf445b5c77c33787f1cf', 'postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', 'c9e90784de512cc4c8e694a0465bc80c', 'postgres:EXECUTE:false'),
    ('private.base_gestion_rol(uuid)', '3c2d5feefd68589cfe82fc1fe2e95180', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.juicio_reapertura(uuid,text,text)', '47277cd689ad0e1713e436d3373e3521', 'postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.persona_vetada(uuid)', 'a70efe776fc56fd34d47e364e2e55571', 'postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'REVERSA (postflight) reactivar_reconoce_cliente: cambió algo que la reversa no toca (%)', v_mal;
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || coalesce(p.proacl::text, '-') || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
        from pg_proc p where p.oid = 'private.juicio_cliente_convertido(text,text,text,uuid)'::regprocedure)
       is distinct from '346f48a8648248b308628301d41bc4c0/a2b38faf42a875c7dffb7968b106e36f/{postgres=X/postgres}/e23707e521c5878f056c0b99b02a9651' then
    raise exception 'REVERSA (postflight) reactivar_reconoce_cliente: cambió algo que la reversa no toca (private.juicio_cliente_convertido)';
  end if;
  raise notice 'REVERSA reactivar_reconoce_cliente: los dos núcleos y sus comentarios de antes, su ficha intacta, la pieza borrada';
end
$postflight$;

commit;

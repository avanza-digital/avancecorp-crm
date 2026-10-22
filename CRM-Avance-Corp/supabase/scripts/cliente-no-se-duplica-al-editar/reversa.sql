-- REVERSA de 20261022170400_crm_cliente_no_se_duplica_al_editar.sql («El cliente ya convertido tampoco se duplica al editar un lead
-- ni por su teléfono alternativo», bloque 2.8). GENERADA desde la migración (sus anclas, byte a byte; generador en
-- fase-2/bloque-2.8/salidas/ronda4/trabajo/generadores/generar-reversa-r4.py): no editar a mano sin volver a ensayarla.
--
-- FALLA CERRADA. Antes de revertir exige EXACTAMENTE lo que deja la migración, también lo que la definición no incluye:
--   · la pieza `private.juicio_cliente_convertido(text,text,text,uuid)`: cuerpo y definición (`md5` 346f48a8648248b308628301d41bc4c0 /
--     a2b38faf42a875c7dffb7968b106e36f), INVOKER de postgres, STABLE, `search_path` vacío y nada más, EXECUTE solo para postgres sin
--     opción de concesión, nadie más con EXECUTE, y su comentario (`md5` e23707e521c5878f056c0b99b02a9651);
--   · el núcleo `private.alta_reactivar_retirado(…)`: 2fe5fdac50150d7429da2e422f43b92d / 8d598eb4d0df994388337480e71e8005, su ficha
--     (dueño postgres, DEFINER, `proconfig` exacto, ACL `postgres:EXECUTE` sin opción de concesión, nadie más) y su comentario
--     (`md5` 8870de7f9d82c44b1a1f965f1e6d3ef0);
--   · el disparador `private.trg_leads_disponibilidad_atomica()`: 50a6ff4365ffa6bedfd77d215ce31666 / 418b097675753ed9f81931a485b17c94,
--     su ficha y su comentario (`md5` 4a3fee01861a0fc10af38eb3fc338eb2);
--   · los disparadores de tabla: `trg_leads_00_disponibilidad_update` con la lista que deja la migración (`md5` de su definición
--     a585ac769d92cd1f2aba0c4cf49ca83a) y `trg_leads_00_disponibilidad_insert` intacto (fd430e026c17ce4ca3ed0d74b48ba0e1), habilitados;
--   · y que NADIE MÁS use la pieza (ronda 3: auditor F2, Codex F4): ni otra función por su cuerpo (búsqueda de texto: PL/pgSQL no
--     registra dependencias; ronda 4, Codex R2-F1 + auditor P3-1: SIN distinguir mayúsculas, porque un identificador sin comillas
--     como `PRIVATE.JUICIO_CLIENTE_CONVERTIDO(…)` llama a la misma función), ni un trabajo programado (ronda 4: `cron.job.command`,
--     si la tabla existe; con pg_cron, solo los trabajos que el rol que revierte puede ver), ni una vista, una policy, un default, un
--     CHECK, un disparador o una función SQL `BEGIN ATOMIC` (dependencias registradas en `pg_depend`). Es una búsqueda TEXTUAL Y
--     CONSERVADORA: un comentario, una cadena informativa o el nombre de otra función que contenga esa subcadena también la bloquean
--     («posible llamador: inspeccionar antes de revertir»: se mira la referencia y, si no es un llamador, se quita o se revierte a
--     mano; nunca se borra a ciegas lo señalado). LÍMITE DECLARADO: una llamada construida en tiempo de ejecución (EXECUTE con el
--     nombre partido o leído de una tabla) o hecha desde fuera de la base (Edge Functions, clientes) no se ve; por eso el DROP va SIN
--     CASCADE (RESTRICT): lo que sí está registrado lo para PostgreSQL, y lo dinámico fallaría al llamarse (ensayado: `derivas.sh`,
--     «llamador dinámico»).
-- Si algo de eso cambió después (un cuerpo, un SET, un permiso, un dueño, un comentario, un disparador deshabilitado), NO se revierte
-- nada y se revisa a mano (o se corrige hacia delante con otra migración). No se promete tolerancia a derivas (ensayado:
-- `armar-ensayo.mjs --reversa-deriva`).
--
-- QUÉ RESTAURA: el núcleo del 2.7 y el disparador de B8 quitando del cuerpo vivo lo que la migración puso (cada bloque tiene que
-- aparecer EXACTAMENTE una vez; ronda 4: también las dos llamadas de candado con el alternativo vuelven a ser las de B8); la lista de columnas de hoy en `trg_leads_00_disponibilidad_update` (`create or replace trigger`:
-- mismo nombre, mismo oid); los comentarios de antes (se quita el añadido del 2.8, exactamente una vez); y BORRA la pieza. El
-- postflight exige las huellas del 2.7 (f74838f274a8db971952eb9c09c7387e / c56e4abd191b947177a9179a7d558dbd, comentario
-- 31159d826a407c91173e3870b5711352) y de B8 (5543c41f89dd49b8b267b7b274b12814 / bfd4679b1d15bb2147ef78705a9d9aff, comentario
-- 5d0717955781d7c48794d240b021a148), la definición de hoy del disparador de tabla (5aef4753210080c9bcf5d7b16b2d4b54), las fichas y
-- ACL exactas y que la pieza ya no exista.
--
-- NO DESHACE DATOS: la regla no escribe ninguno. Tras revertir, editar el teléfono, el alternativo o el DNI hacia los de un cliente
-- vuelve a dejar un segundo lead, el INSERT con sesión vuelve a juzgarse solo con el verificador y el alta vuelve a ignorar el
-- alternativo. Se aplica por el mismo ciclo que la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  v_pieza regprocedure := to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)');
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_disp regprocedure := to_regprocedure('private.trg_leads_disponibilidad_atomica()');
  v_mal text;
  v_cron text;
begin
  if v_pieza is null or v_nucleo is null or v_disp is null then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: falta la pieza, el núcleo o el disparador: la migración no está aplicada; nada que revertir';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza)
       is distinct from '346f48a8648248b308628301d41bc4c0/a2b38faf42a875c7dffb7968b106e36f'
     or not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                      and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_pieza, 'EXECUTE') or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE')
     or md5(coalesce(obj_description(v_pieza, 'pg_proc'), '')) is distinct from 'e23707e521c5878f056c0b99b02a9651' then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: la pieza private.juicio_cliente_convertido no es la que dejó la migración (cuerpo, ficha, permisos o comentario): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  -- Nadie más usa la pieza (ronda 3; ronda 4: sin distinguir mayúsculas y también en cron.job): otros cuerpos de función (texto,
  -- en minúsculas), los comandos de los trabajos programados (`cron.job.command`, si la tabla existe) y las dependencias registradas
  -- (vistas, policies, defaults, CHECK, disparadores, funciones SQL BEGIN ATOMIC). Búsqueda conservadora: un comentario o una cadena
  -- con ese nombre también bloquea (se inspecciona antes de revertir). Lo dinámico no se ve (límite declarado en la cabecera).
  select string_agg(u.quien, ', ' order by u.quien) into v_mal
  from (select 'función ' || p.oid::regprocedure::text || ' (texto del cuerpo)' as quien
          from pg_proc p
         where p.oid not in (v_pieza, v_nucleo, v_disp)
           and position('juicio_cliente_convertido' in lower(coalesce(p.prosrc, ''))) > 0
        union
        select pg_describe_object(d.classid, d.objid, d.objsubid) || ' (dependencia registrada)'
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_pieza) u;
  if to_regclass('cron.job') is not null then
    execute $cron$select string_agg('cron.job ' || j.jobid::text || coalesce(' «' || j.jobname || '»', '') || ' (texto del comando)', ', ' order by j.jobid)
                    from cron.job j where position('juicio_cliente_convertido' in lower(coalesce(j.command, ''))) > 0$cron$
      into v_cron;
    v_mal := nullif(concat_ws(', ', v_mal, v_cron), '');
  end if;
  if v_mal is not null then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: posible llamador de la pieza private.juicio_cliente_convertido (%): inspeccionar antes de revertir; la reversa falla cerrada (el DROP va sin CASCADE). La búsqueda es textual y conservadora: un comentario o una cadena con ese nombre también la bloquean', v_mal;
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo)
       is distinct from '2fe5fdac50150d7429da2e422f43b92d/8d598eb4d0df994388337480e71e8005' then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el núcleo no tiene exactamente la definición que dejó la migración (cuerpo o atributo, p. ej. un SET): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE')
     or md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from '8870de7f9d82c44b1a1f965f1e6d3ef0' then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: la ficha o el comentario del núcleo no son los que dejó la migración (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_disp)
       is distinct from '50a6ff4365ffa6bedfd77d215ce31666/418b097675753ed9f81931a485b17c94' then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el disparador no tiene exactamente la definición que dejó la migración (cuerpo o atributo, p. ej. un SET): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_disp)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_disp, 'EXECUTE') or has_function_privilege('authenticated', v_disp, 'EXECUTE')
     or has_function_privilege('service_role', v_disp, 'EXECUTE')
     or md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '4a3fee01861a0fc10af38eb3fc338eb2' then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: la ficha o el comentario del disparador no son los que dejó la migración (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update') is distinct from 'a585ac769d92cd1f2aba0c4cf49ca83a|O'
     or (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O' then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: los disparadores de tabla de disponibilidad no son los que dejó la migración (definición o estado): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  perform set_config('cliente_no_se_duplica.reversa_trg_oid',
    (select t.oid::text from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'), true);
end
$preflight$;

do $reemplazo_nucleo$
declare
  v_firma regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_def text;
  v_ancla text;
  v_orig text;
  v_veces integer;
begin
  v_def := pg_get_functiondef(v_firma);

  -- Bloque 1: lo que puso la migración (núcleo, su ancla 1) vuelve a ser lo de antes.
  v_ancla := $r1$  v_respuesta jsonb;
  v_convertido jsonb;
begin
$r1$;
  v_orig := $o1$  v_respuesta jsonb;
  v_convertido record;
begin
$o1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 1 del núcleo aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 2: lo que puso la migración (núcleo, su ancla 2) vuelve a ser lo de antes.
  v_ancla := $r2$  -- 1b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR TELÉFONO Y POR DNI (bloque 2.7; D-22, D-25 y D-27 de Miguel,
  --     08/10/2026; hallazgo H-28) Y POR SU TELÉFONO ALTERNATIVO, EN LAS DOS DIRECCIONES (bloque 2.8; D-30 de Miguel, 08/10/2026).
  --     Solo en un alta NUEVA: un reintento con rastro previo sigue fijado a la ficha de su rastro (R2-1…R4-1). La regla vive en
  --     la pieza común de solo lectura `private.juicio_cliente_convertido` (la misma que juzga la edición y el INSERT en el
  --     disparador de disponibilidad): si lo tecleado —el teléfono, el teléfono alternativo o, si con ellos no casa ninguno, el DNI
  --     (D-27)— es de un lead CONVERTIDO (activo o retirado), el alta no crea, no reactiva y no escribe nada y responde su
  --     veredicto: enlazado a una persona ⇒ el mismo juicio de identidad que da el DNI («ya es cliente» con su asesor, o «no
  --     contactar» si la persona está vetada; el respaldo de D-21 si el juicio no dice nada); sin persona ⇒ «ya es cliente» a
  --     nombre del dueño de esa ficha (formato del verificador, sin via). El teléfono manda sobre el DNI (también con OTRO DNI
  --     tecleado, D-25) y todo va antes que cualquier retirado no convertido que case por teléfono o DNI (el candidato de abajo
  --     ya no llega a mirarse). `v_convertido` guarda el veredicto (el caso 3d del oráculo del 2.4 reconoce la regla por ese nombre).
  if not v_reintento then
    v_convertido := private.juicio_cliente_convertido(p_telefono, v_tecleado ->> 'telefono_alternativo', p_dni, null);
    if v_convertido is not null then
      return v_convertido;
    end if;
  end if;

  <<rama>>
$r2$;
  v_orig := $o2$  -- 1b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR TELÉFONO Y POR DNI (bloque 2.7; D-22, D-25 y D-27 de Miguel,
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
$o2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 2 del núcleo aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  execute v_def;
end
$reemplazo_nucleo$;

do $reemplazo_disparador$
declare
  v_firma regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
  v_def text;
  v_ancla text;
  v_orig text;
  v_veces integer;
begin
  v_def := pg_get_functiondef(v_firma);

  -- Bloque 1: lo que puso la migración (disparador, su ancla 1) vuelve a ser lo de antes.
  v_ancla := $r1$  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
  v_cliente jsonb;
begin
  if tg_op = 'UPDATE' then
    -- Bloque 2.8, ronda 3 (auditor F1, Codex F1). Con sesión —también bajo cualquier válvula—, el teléfono alternativo SIN VALIDAR
    -- (`telefono_alternativo_crudo`: lo pone solo la importación, sin sesión) no puede pasar a un valor no nulo ni cambiar de un
    -- valor a otro: no es un teléfono canónico y la regla no podría juzgarlo. Conservarlo sin tocarlo o borrarlo (NULL) sigue como
    -- hoy. Va antes que todo, también que la salida de la corrección de documento.
    if v_actor is not null and new.telefono_alternativo_crudo is not null
       and new.telefono_alternativo_crudo is distinct from old.telefono_alternativo_crudo then
      raise exception using errcode = '42501', message = 'El alternativo sin validar solo lo pone la importación';
    end if;
$r1$;
  v_orig := $o1$  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if tg_op = 'UPDATE' then
$o1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 1 del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 2: lo que puso la migración (disparador, su ancla 2) vuelve a ser lo de antes.
  v_ancla := $r2$    if not v_cambio_identidad or v_actor is null then
      -- Bloque 2.8 (D-28, D-30 de Miguel, 08/10/2026). Con sesión —desde la ronda 3 también bajo la válvula privilegiada (auditor
      -- F3: bajo ella nadie escribe el alternativo)—, si SOLO cambia el teléfono ALTERNATIVO: el nuevo no puede ser un teléfono de
      -- un cliente ya convertido (`private.juicio_cliente_convertido`, la regla del 2.7 con el alternativo; nunca contra el propio
      -- lead). El veredicto solo lo ve quien puede registrar leads (el resto, 42501 como en todo el disparador); si no hay cliente,
      -- todo sigue como hoy (ni rol, ni vetos, ni verificador).
      if v_actor is not null
         and new.telefono_alternativo is distinct from old.telefono_alternativo then
        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);
        if v_cliente is not null then
          v_rol := private.rol_crm(v_actor);
          if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
            raise exception using errcode = '42501', message = 'Acceso CRM revocado';
          end if;
          raise exception using
            errcode = 'P0481',
            message = 'Contacto no disponible',
            detail = v_cliente::text;
        end if;
      end if;
      return new;
    end if;
$r2$;
  v_orig := $o2$    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;
$o2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 2 del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 3: lo que puso la migración (disparador, su ancla 3) vuelve a ser lo de antes.
  v_ancla := $r3$    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
      new.telefono,
      new.dni,
      old.id
    );
    if v_disponibilidad ->> 'estado' is distinct from 'libre' then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_disponibilidad::text;
    end if;
    -- Bloque 2.8 (D-28, D-30). Lo que el verificador dejó pasar, con sesión: lo que la edición PONE —el teléfono, el alternativo y el
    -- DNI que cambian; lo que el lead ya tenía no se juzga: los duplicados que ya existen se dejan, D-23/D-25— no puede ser de un
    -- cliente ya convertido (`private.juicio_cliente_convertido`, nunca contra el propio lead) ⇒ el mismo P0481 con su veredicto.
    -- Ronda 3 (auditor F3, Codex F3): bajo la válvula privilegiada se juzgan igual el teléfono y el alternativo; SOLO el DNI queda
    -- fuera (la conversión fija el documento de la persona y conserva su juicio propio, hasta D-38).
    v_cliente := private.juicio_cliente_convertido(
      case when new.telefono is distinct from old.telefono then new.telefono end,
      case when new.telefono_alternativo is distinct from old.telefono_alternativo then new.telefono_alternativo end,
      case when not v_priv and new.dni is distinct from old.dni then new.dni end,
      old.id);
    if v_cliente is not null then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
    return new;
  end if;
$r3$;
  v_orig := $o3$    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
      new.telefono,
      new.dni,
      old.id
    );
    if v_disponibilidad ->> 'estado' is distinct from 'libre' then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_disponibilidad::text;
    end if;
    return new;
  end if;
$o3$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 3 del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 4: lo que puso la migración (disparador, su ancla 4) vuelve a ser lo de antes.
  v_ancla := $r4$  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  -- Bloque 2.8 (D-30: «el INSERT directo, si sigue concedido, lo juzga la misma regla»). Un lead que nace CON SESIÓN —salvo el
  -- contacto de base cargada que nace dormido bajo su válvula: la carga de bases no cambia— no puede llevar el teléfono, el
  -- alternativo ni el DNI de un cliente ya convertido. (El alta ya lo respondió en su núcleo: aquí es la defensa del INSERT.)
  if not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then
    v_cliente := private.juicio_cliente_convertido(new.telefono, new.telefono_alternativo, new.dni, null);
    if v_cliente is not null then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
  end if;

  return new;
end;
$r4$;
  v_orig := $o4$  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  return new;
end;
$o4$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 4 del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 5: lo que puso la migración (disparador, su ancla 5) vuelve a ser lo de antes.
  v_ancla := $r5$       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id
       -- Bloque 2.8, ronda 3 (Codex F3): la excepción vale solo para la forma que escribe la corrección —cambia el DNI y nada de
       -- contacto—: ni el alternativo ni el alternativo sin validar se cuelan por ella (si cambian, sigue el juicio de abajo).
       and new.telefono_alternativo is not distinct from old.telefono_alternativo
       and new.telefono_alternativo_crudo is not distinct from old.telefono_alternativo_crudo then
      return new;
    end if;
$r5$;
  v_orig := $o5$       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id then
      return new;
    end if;
$o5$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 5 del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 6: lo que puso la migración (disparador, su ancla 6) vuelve a ser lo de antes.
  v_ancla := $r6$  if v_actor is null then
    return new;
  end if;

  -- Bloque 2.8, ronda 3 (auditor F1, Codex F1): con sesión —también bajo cualquier válvula—, un lead no nace con el teléfono
  -- alternativo SIN VALIDAR (solo lo pone la importación, sin sesión).
  if new.telefono_alternativo_crudo is not null then
    raise exception using errcode = '42501', message = 'El alternativo sin validar solo lo pone la importación';
  end if;
$r6$;
  v_orig := $o6$  if v_actor is null then
    return new;
  end if;
$o6$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 6 del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 7: lo que puso la migración (disparador, su ancla 7) vuelve a ser lo de antes.
  v_ancla := $r7$    -- Bloque 2.8, ronda 4 (auditor P3-4): el candado de contacto incluye también el teléfono alternativo VIEJO y el NUEVO, en la
    -- lista de TELÉFONOS: la misma clave que toma el teléfono principal para el mismo número (`telefono:` + la forma de
    -- `private.normalizar_telefono`, dentro de `private.bloquear_contactos_lead`). Así quien pone X como alternativo o como teléfono
    -- espera a quien está poniendo X como alternativo (y al revés), y la regla de abajo juzga con lo que el otro confirmó.
    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],
      array[old.dni, new.dni]
    );
$r7$;
  v_orig := $o7$    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono],
      array[old.dni, new.dni]
    );
$o7$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 7 del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 8: lo que puso la migración (disparador, su ancla 8) vuelve a ser lo de antes.
  v_ancla := $r8$  -- Bloque 2.8, ronda 4 (auditor P3-4): también el alternativo, con la misma clave que el teléfono principal (ver el UPDATE).
  perform private.bloquear_contactos_lead(array[new.telefono, new.telefono_alternativo], array[new.dni]);
$r8$;
  v_orig := $o8$  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni]);
$o8$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el bloque 8 del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  execute v_def;
end
$reemplazo_disparador$;

create or replace trigger trg_leads_00_disponibilidad_update
  before update of telefono, dni, no_contactar, etapa, activo, motivo_descarte on crm.leads
  for each row execute function private.trg_leads_disponibilidad_atomica();

-- Los comentarios de antes: se quita EXACTAMENTE una vez el añadido del 2.8.
do $comentarios$
declare
  v_c text;
  v_sufijo text;
begin
  v_sufijo := $s1$ Bloque 2.8 (D-28, D-30): la regla del 2.7 vive en la pieza comun private.juicio_cliente_convertido, que cuenta tambien el telefono alternativo tecleado en las dos direcciones (contra el telefono y el alternativo de cada convertido); el resto del nucleo no cambia.$s1$;
  v_c := obj_description('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure, 'pg_proc');
  if (length(v_c) - length(replace(v_c, v_sufijo, ''))) / length(v_sufijo) <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el añadido del 2.8 no aparece exactamente una vez en el comentario del núcleo';
  end if;
  execute pg_catalog.format('comment on function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb) is %L',
    replace(v_c, v_sufijo, ''));
  v_sufijo := $s2$ Bloque 2.8 (D-28, D-30): con sesion, al cambiar el telefono, el alternativo o el DNI (UPDATE: lo que cambia, no lo que el lead ya tenia) y al nacer un lead (INSERT, salvo el contacto de base cargada que nace dormido), lo que se pone no puede ser de un cliente ya convertido (private.juicio_cliente_convertido): P0481 Contacto no disponible con el veredicto en el detalle, despues de los veredictos de hoy; bajo la valvula privilegiada solo el DNI queda fuera (hasta D-38). Con sesion, el alternativo sin validar (telefono_alternativo_crudo) no nace ni pasa a un valor no nulo (42501; conservarlo o borrarlo sigue igual) y la salida de la correccion de documento solo vale si cambia unicamente el DNI. Ronda 4: el candado de contacto (private.bloquear_contactos_lead, con o sin sesion) incluye el telefono alternativo viejo y el nuevo, con la misma clave que el telefono principal para el mismo numero. Sin sesion, la regla no se aplica.$s2$;
  v_c := obj_description('private.trg_leads_disponibilidad_atomica()'::regprocedure, 'pg_proc');
  if (length(v_c) - length(replace(v_c, v_sufijo, ''))) / length(v_sufijo) <> 1 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el añadido del 2.8 no aparece exactamente una vez en el comentario del disparador';
  end if;
  execute pg_catalog.format('comment on function private.trg_leads_disponibilidad_atomica() is %L', replace(v_c, v_sufijo, ''));
end
$comentarios$;

-- SIN CASCADE: si algo registrado la usara (una vista, una policy…), PostgreSQL se niega y nada se revierte.
drop function private.juicio_cliente_convertido(text, text, text, uuid) restrict;

do $postflight$
declare
  v_nucleo regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_disp regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
begin
  if exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'juicio_cliente_convertido') then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: la pieza sigue existiendo';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo)
       is distinct from 'f74838f274a8db971952eb9c09c7387e/c56e4abd191b947177a9179a7d558dbd'
     or md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from '31159d826a407c91173e3870b5711352'
     or not exists (select 1 from pg_proc p
                  where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el núcleo no quedó como lo dejó el bloque 2.7 (cuerpo, comentario, ficha o ACL)';
  end if;
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_disp)
       is distinct from '5543c41f89dd49b8b267b7b274b12814/bfd4679b1d15bb2147ef78705a9d9aff'
     or md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '5d0717955781d7c48794d240b021a148'
     or not exists (select 1 from pg_proc p
                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_disp)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_disp, 'EXECUTE') or has_function_privilege('authenticated', v_disp, 'EXECUTE')
     or has_function_privilege('service_role', v_disp, 'EXECUTE') then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el disparador no quedó como lo dejó B8 (cuerpo, comentario, ficha o ACL)';
  end if;
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text || '|' || t.oid::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update')
       is distinct from '5aef4753210080c9bcf5d7b16b2d4b54|O|' || current_setting('cliente_no_se_duplica.reversa_trg_oid', true)
     or (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O' then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: los disparadores de tabla no volvieron a su definición de hoy';
  end if;
  if position('juicio_cliente_convertido' in (select p.prosrc from pg_proc p where p.oid = v_nucleo)) > 0
     or position('juicio_cliente_convertido' in (select p.prosrc from pg_proc p where p.oid = v_disp)) > 0 then
    raise exception 'REVERSA cliente_no_se_duplica_al_editar: la regla del 2.8 sigue en el núcleo o en el disparador';
  end if;
end
$postflight$;

commit;

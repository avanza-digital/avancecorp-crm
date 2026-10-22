-- 20261022170300_crm_cliente_por_telefono.sql — bloque 2.7 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261008174055_crm_cliente_por_telefono.sql; integrado el 2026/10/22, C2 del grupo C)
-- El cliente ya convertido también se reconoce por teléfono y por DNI (plan AVANCE-BACKEND-0710-P3, fase 2, bloque 2.7; decisiones
-- D-22, D-25 y D-27 de Miguel, 08/10/2026; hallazgo H-28 de la ronda del banco, caso L9f-tel). Ronda 2 (08/10): la regla del DNI
-- (D-27). Ronda 3 (08/10): revisiones de Codex y del auditor de permisos (reversa con ficha y ACL exactas; barrido de trinquetes
-- sin `*_mutantes`); D-28 y D-29 declarados abajo. Va DESPUÉS de 20261007210152_crm_alta_reactiva_lead_retirado.sql (bloque 2.4):
-- cambia solo su núcleo.
--
-- QUÉ HACE. Hoy, si un asesor registra como lead nuevo a alguien que YA ES CLIENTE (su lead está `convertido`, activo o
-- retirado) y escribe SOLO el teléfono —o el teléfono con OTRO DNI—, `crm.crear_lead_si_disponible` responde «creado» e inserta
-- un SEGUNDO lead del cliente a nombre de ese asesor: el verificador `private.verificar_disponibilidad_lead_impl` dice «libre»
-- (solo el documento vincula a la persona y su paso de lead vivo excluye `etapa = 'convertido'`; la cuenta del Portal solo
-- protege a quien tiene perfil `cliente` con ese teléfono) y la rama del 2.4 elige candidatos con `etapa <> 'convertido'`. Con el
-- cliente retirado y otro retirado no convertido del mismo teléfono (o del DNI tecleado), la rama del 2.4 incluso REACTIVA esa
-- otra ficha. Lo mismo con el DNI tecleado de un cliente convertido SIN persona (cliente antiguo sin identidad registrada) y
-- otro teléfono: el verificador solo reconoce el DNI a través de las identidades de persona, así que nace otro lead (D-27). Esta
-- migración añade una regla al principio del camino NORMAL del núcleo del 2.4, `private.alta_reactivar_retirado(…)` (el alta lo
-- llama tras el verificador y solo actúa con «libre» o «enfriamiento»): si el teléfono tecleado —o, si con él no casa ninguno, el
-- DNI tecleado (D-27)— es el de un lead CONVERTIDO (activo o retirado), el alta no crea, no reactiva y no escribe nada, y responde:
--   · enlazado a una persona ⇒ el MISMO juicio de identidad que da el DNI,
--     `private.juicio_persona(private.inversionista_canonica(<persona>), null)`: `ya_es_cliente` con su asesor (responsable de
--     relación, o quien reservó la conversión) y `via = identidad`, o `no_contactar` si la persona está vetada; si el juicio
--     devolviera nulo, el mismo respaldo que ya usa el núcleo (D-21): `ya_es_cliente`, `sin asesor asignado`, `via = identidad`;
--   · sin persona (convertidos heredados) ⇒ `ya_es_cliente` a nombre del dueño de esa ficha (vendedor o bandeja; si no tiene,
--     `sin asesor asignado`), en el formato del verificador SIN `via`: como el `ya_es_cliente` que el núcleo del 2.4 ya sintetiza
--     para un convertido sin persona (R3-1 y la pieza del dato conservado); en el contrato de la app `via = identidad` significa
--     «reconocido por su documento» y la pantalla pinta lo mismo con o sin ella.
-- PRECEDENCIA: teléfono → DNI → candidato retirado del 2.4. D-25: el teléfono manda, también con OTRO DNI tecleado (evita el
-- rodeo de teclear un DNI cualquiera; con el teléfono de un cliente y el DNI de otro, responde por el del teléfono). El convertido
-- gana a cualquier retirado no convertido que case por teléfono o DNI (las dos búsquedas van antes que el candidato del 2.4) y
-- también al «enfriamiento» de un descartado que comparta el teléfono (los dos bloquean). Con varios convertidos de ese teléfono
-- (o de ese DNI), primero el enlazado a persona, luego el activo, luego el convertido más reciente. Con el DNI de un cliente CON
-- persona y la identidad unificada encendida, el verificador ya bloquea antes (camino de identidad): la regla del DNI solo actúa
-- cuando el verificador no lo hizo (bandera apagada, documento sin identidad verificada o cliente sin persona).
-- NO CAMBIA: el camino del REINTENTO del 2.4 (mismo p_id con rastro previo, R2-1…R4-1: fijado a la ficha de su rastro, nunca llega
-- al INSERT); cualquier otro veredicto del verificador, que manda antes (un lead activo vivo ⇒ `tomado`/`en_bolsa`; la cuenta del
-- Portal ⇒ `ya_es_cliente` por el Portal; el teléfono con el DNI del cliente ⇒ el camino de identidad; el veto ⇒ `no_contactar`);
-- los roles (quien no puede registrar sigue recibiendo 42501 antes de mirar nada; D-17 no aplica: es un alta y nadie gana ni pierde
-- permisos); el verificador (huella sellada por la carga de bases), `crm.crear_lead_si_disponible` (ni cuerpo, ni ficha, ni
-- comentario), la pieza `private.alta_reactivar_bloqueo_conservado`, `crm.tomar_lead_libre`, `crm.reactivar_lead_base`,
-- `crm.reabrir_lead_fn`, `crm.crear_lead_documento_fn` (con CE/pasaporte y el teléfono de un cliente devuelve el `ya_es_cliente`
-- del alta sin fijar documento ni crear identidad), la carga de bases, tablas, grants, policies ni nada de `public`. Los duplicados
-- que ya existen (D-23: 2 leads activos comparten teléfono con un cliente) se dejan como están (D-25): la regla solo impide los
-- nuevos. Las otras puertas de alta (carga de bases, formulario web, tomar un lead libre) y el aviso previo de la pantalla no
-- cambian: el servidor manda al confirmar (la pantalla ya pinta `ya_es_cliente`: `app/src/lib/store.tsx` lo presenta con
-- `presentarDisponibilidadLead`).
-- ABIERTO HASTA EL BLOQUE 2.8 (D-28, solo se declara aquí): la EDICIÓN del teléfono o del DNI de un lead existente
-- (`crm.editar_lead_fn` → disparador de disponibilidad, que juzga con el verificador sellado), el INSERT directo en `crm.leads` si
-- sigue concedido a authenticated, y el TELÉFONO ALTERNATIVO de un cliente no pasan por esta regla: pueden dejar un segundo lead de
-- un cliente ya convertido. ACEPTADO (D-29): el alta responde «ya es cliente» y el nombre del asesor sin asentar la consulta (el
-- pre-chequeo sí la asienta en `crm.verificaciones_lead`); es la misma clase de dato que ya revelaba el camino del DNI, para los
-- mismos roles (vendedor, supervisor y Gerencia activos; el resto recibe 42501).
-- CONSECUENCIA DECLARADA: el caso 3d del oráculo del 2.4 (`supabase/scripts/reactivar-lead-retirado/pruebas.sql`: convertido
-- retirado SIN persona registrado con su teléfono y su DNI) esperaba `creado` («como hoy», D-15); con esta migración responde
-- `ya_es_cliente` (D-22). Desde la ronda 2 ese caso detecta la regla (el cuerpo del núcleo declara `v_convertido`) y, desde la
-- ronda 3, exige además que coincida con el modo que le pasa el armador (con o sin esta migración); su subcaso de reintento mantiene
-- muerto al mutante «la rama reactiva convertidos» con y sin esta migración.
--
-- CÓMO. Parche por ANCLA ÚNICA sobre el cuerpo vivo del núcleo (`pg_get_functiondef` + `replace`; cada ancla tiene que aparecer
-- exactamente una vez o la migración aborta): (1) una variable nueva (`v_convertido record`) al final de las declaraciones; (2) la
-- regla (búsqueda por teléfono y, si no casa ninguno y hay DNI, por DNI), entre el filtro del veredicto (paso 1) y el bloque
-- `<<rama>>` del candidato (paso 2), solo cuando `not v_reintento`.
-- `create or replace` conserva firma, dueño (`postgres`), DEFINER, `search_path` vacío, `lock_timeout 5s` y ACL (EXECUTE solo
-- para `postgres`: solo lo llama el alta); el postflight lo comprueba. El comentario del núcleo suma la regla.
--
-- PREFLIGHT (falla cerrada; si algo no coincide no se instala nada): el núcleo con las huellas del 2.4 (`md5(prosrc)` =
-- bf0a7531ea589a52ba75680b44ef348e, `md5(pg_get_functiondef)` = 65b400ec8f0607a3111ed03b851b3877), su ficha (dueño postgres,
-- DEFINER, `search_path=""` y `lock_timeout=5s` y nada más, EXECUTE solo para postgres sin opción de concesión) y su comentario
-- (`md5` = e744b3fd7628b9bafb2ab1647a607a58); si ya lleva la regla, «ya está aplicada»; el alta con las huellas que deja el 2.4
-- (01ebf089b8428a02c6df387a9b4e899e / 94ec2bd71eca8ab1663e75841723b6a5) y su ficha (EXECUTE solo para postgres y authenticated,
-- sin opción de concesión); el verificador con las MISMAS huellas que fija la carga de bases (`20261004184501:178-183`: compuestas
-- a78247a515be78b145fec439fc299458 y e144f7d020269c61258b4d3980ac88c6; `md5(prosrc)` 683c16fdcb08377af860f1aa0a18f3a1 y
-- 48c51531ebc8db1a41f5a816241920da); las piezas que la regla llama (`private.juicio_persona` 2570f6eab5ae8b076e6f759b43b9b659,
-- `private.inversionista_canonica` 6c7ff6001df2cb047967fa61b3ceb763) y la pieza del 2.4 que no se toca
-- (`private.alta_reactivar_bloqueo_conservado` a9ac3a87a7707e98c7cc8afbf9c663c3). Fotografía la ficha del núcleo, la del alta y
-- los `private.assert_*()` sin argumentos. POSTFLIGHT: la regla presente una sola vez (con sus dos búsquedas); el núcleo con su
-- cuerpo nuevo EXACTO (`md5(prosrc)` = f74838f274a8db971952eb9c09c7387e, `md5(pg_get_functiondef)` = c56e4abd191b947177a9179a7d558dbd, medidos en el laboratorio el
-- 08/10/2026, ronda 2; los de la ronda 1 —solo teléfono— eran 0bfd14d0e1a9809bde6413941f05ec59 / 1d1d1e7f56bf2db7457fc656889220cb), la
-- misma ficha que antes (dueño, DEFINER, volatilidad, configuración, ACL, firma) y EXECUTE solo para postgres; el comentario nuevo;
-- el alta, el verificador y las piezas intactos; y la FOTO de los `private.assert_*()` sin argumentos, SIN los `*_mutantes` (30 de 36
-- en el laboratorio; ronda 3, auditor F2: varios `*_mutantes` aplican sin guarda DDL de permisos sobre tablas calientes y en la base
-- real tomarían candados ACCESS EXCLUSIVE; el ensayo `--trinquetes` sigue barriendo los 36), EXACTAMENTE igual que antes (estado y
-- texto íntegro del primer error: se exige que no cambie, no que pasen).
--
-- CÓMO SE REVIERTE: `supabase/scripts/cliente-por-telefono/reversa.sql` (falla cerrada: exige que el núcleo tenga EXACTAMENTE la
-- definición que deja esta migración; quita los dos bloques insertados —el cuerpo vuelve a bf0a7531…/65b400ec…— y repone el
-- comentario del 2.4). No deshace datos (la regla no escribe ninguno). Tras revertir, el alta vuelve a crear un segundo lead de un
-- cliente registrado solo por teléfono (H-28) o por el DNI de un cliente sin persona (D-27). Mismo ciclo que la migración. Ensayo: `supabase/scripts/cliente-por-telefono/`
-- (oráculo ROJO/VERDE, mutantes, derivas, reversa, reversa con SET, trinquetes y el oráculo del 2.4 encima).
-- RESELLE C2 (22/10/2026, plan AVANCE-BACKEND-1310-C2): el alta que deja el 2.4 re-asentado contra producción del 22/10 se fija por 30109c53…/e06eca23… (antes 01ebf089…/94ec2bd7…; cambió por 20261015171407 y 20261016183308, el parche del 2.4 es el mismo); solo esas huellas, en preflight y postflight; regla, mensajes y candados sin cambio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_alta regprocedure := to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)');
  r record;
  v text;
  v_foto text := '';
begin
  if v_nucleo is null then
    raise exception 'PREFLIGHT cliente_por_telefono: falta el núcleo private.alta_reactivar_retirado (bloque 2.4, 20261007210152): esta migración va después de él';
  end if;
  if v_alta is null then
    raise exception 'PREFLIGHT cliente_por_telefono: falta crm.crear_lead_si_disponible (16 parámetros)';
  end if;
  if position('v_convertido' in (select p.prosrc from pg_proc p where p.oid = v_nucleo)) > 0 then
    raise exception 'PREFLIGHT cliente_por_telefono: el núcleo ya reconoce al cliente convertido por teléfono: esta migración ya está aplicada';
  end if;
  -- El núcleo del 2.4, exacto: cuerpo, definición, ficha y comentario.
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo) is distinct from 'bf0a7531ea589a52ba75680b44ef348e'
     or md5(pg_get_functiondef(v_nucleo)) is distinct from '65b400ec8f0607a3111ed03b851b3877' then
    raise exception 'PREFLIGHT cliente_por_telefono: el núcleo private.alta_reactivar_retirado cambió desde que se auditó (md5 del cuerpo %, de la definición %; se esperaban bf0a7531ea589a52ba75680b44ef348e y 65b400ec8f0607a3111ed03b851b3877): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), md5(pg_get_functiondef(v_nucleo));
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
    raise exception 'PREFLIGHT cliente_por_telefono: la ficha del núcleo no es la auditada (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres sin opción de concesión)';
  end if;
  if md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from 'e744b3fd7628b9bafb2ab1647a607a58' then
    raise exception 'PREFLIGHT cliente_por_telefono: el comentario del núcleo cambió; revisar antes de reescribirlo (la reversa repone el del 2.4)';
  end if;
  -- El alta que deja el 2.4, exacta (esta migración no la toca: el postflight exige que siga igual).
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_alta) is distinct from '30109c536ef0a73a85da1eb3465b8ed2'
     or md5(pg_get_functiondef(v_alta)) is distinct from 'e06eca2333bb11869d00913a004c8261' then
    raise exception 'PREFLIGHT cliente_por_telefono: crm.crear_lead_si_disponible cambió desde que se auditó (md5 del cuerpo %, de la definición %; se esperaba el que deja el 2.4: 30109c536ef0a73a85da1eb3465b8ed2 y e06eca2333bb11869d00913a004c8261): revisar antes de seguir',
      (select md5(p.prosrc) from pg_proc p where p.oid = v_alta), md5(pg_get_functiondef(v_alta));
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_alta and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = v_alta)
        is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']
     or has_function_privilege('anon', v_alta, 'EXECUTE')
     or has_function_privilege('service_role', v_alta, 'EXECUTE') then
    raise exception 'PREFLIGHT cliente_por_telefono: la ficha de crm.crear_lead_si_disponible no es la auditada (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres y authenticated sin opción de concesión)';
  end if;
  -- El verificador no se toca y tiene que ser EXACTAMENTE el que fija la carga de bases (misma huella compuesta).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from '683c16fdcb08377af860f1aa0a18f3a1'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from '48c51531ebc8db1a41f5a816241920da'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    raise exception 'PREFLIGHT cliente_por_telefono: el verificador private.verificar_disponibilidad_lead_impl no es el fijado por la carga de bases (20261004184501); lo ensayado no valdría';
  end if;
  -- Las piezas que la regla llama y la pieza del 2.4 que no se toca.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.juicio_persona(uuid,uuid)')) is distinct from '2570f6eab5ae8b076e6f759b43b9b659'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.inversionista_canonica(uuid)')) is distinct from '6c7ff6001df2cb047967fa61b3ceb763'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)')) is distinct from 'a9ac3a87a7707e98c7cc8afbf9c663c3' then
    raise exception 'PREFLIGHT cliente_por_telefono: cambió una pieza de la que depende la regla (private.juicio_persona, private.inversionista_canonica o private.alta_reactivar_bloqueo_conservado); lo ensayado no valdría';
  end if;
  -- Fotos para el postflight: la ficha del núcleo, la del alta y los private.assert_*() sin argumentos (estado y texto íntegro del
  -- primer error: se exige que NO cambien, no que pasen), SIN los `*_mutantes` (ronda 3, auditor F2): varios de ellos aplican, sin
  -- guarda propia, DDL de permisos sobre tablas calientes (revoke de SELECT en crm.leads, `disable row level security` en crm.tareas
  -- y crm.leads, grants a anon, policies nuevas: `20260920045202`, `20260919185718`, `20260920014500`) dentro de subtransacciones que
  -- se deshacen; en la base real eso toma candados ACCESS EXCLUSIVE en preflight y postflight (hasta el `lock_timeout` de 5 s) y
  -- puede dar un postflight no determinista si un candado caduca. Esos mutantes se siguen ensayando en el laboratorio
  -- (`armar-ensayo.mjs --trinquetes` barre los 36), no en la migración.
  perform set_config('cliente_por_telefono.nucleo_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_nucleo), true);
  perform set_config('cliente_por_telefono.alta_antes',
    (select md5(pg_get_functiondef(p.oid)) || '|' || coalesce(p.proacl::text, '-') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-')
       from pg_proc p where p.oid = v_alta), true);
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  perform set_config('cliente_por_telefono.trinquetes_antes', v_foto, true);
end
$preflight$;

-- ── El parche del núcleo, por ancla única ────────────────────────────────────────────────────────────────────────────
do $parche$
declare
  v_firma regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;

  -- Ancla 1 (declaraciones): la variable de la regla.
  v_ancla := $a1$  v_respuesta jsonb;
begin
$a1$;
  v_nuevo := $n1$  v_respuesta jsonb;
  v_convertido record;
begin
$n1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_por_telefono: el ancla de las declaraciones aparece % veces en el núcleo (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 2 (cuerpo): entre el filtro del veredicto (paso 1) y el bloque del candidato (paso 2).
  v_ancla := $a2$  -- 1. Solo con «libre» o «enfriamiento» (D-15: la espera de un RETIRADO no bloquea). Cualquier otro veredicto manda.
  if coalesce(p_disponibilidad ->> 'estado', '') not in ('libre', 'enfriamiento') then
    return null;
  end if;

  <<rama>>
$a2$;
  v_nuevo := $n2$  -- 1. Solo con «libre» o «enfriamiento» (D-15: la espera de un RETIRADO no bloquea). Cualquier otro veredicto manda.
  if coalesce(p_disponibilidad ->> 'estado', '') not in ('libre', 'enfriamiento') then
    return null;
  end if;

  -- 1b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR TELÉFONO Y POR DNI (bloque 2.7; D-22, D-25 y D-27 de Miguel,
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
$n2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_por_telefono: el ancla del cuerpo (filtro del veredicto → candidato) aparece % veces en el núcleo (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT cliente_por_telefono: los permisos del núcleo cambiaron al parchear';
  end if;
end
$parche$;

comment on function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb) is
  'Nucleo de crm.crear_lead_si_disponible (bloque 2.4, D-11/Q1, D-15, D-21): si la persona ya tuvo un lead RETIRADO (activo=false, no convertido, sin veto) y ningun lead activo, veto ni identidad coinciden con lo tecleado ni con lo que esa ficha conserva, reactiva esa ficha a nombre del destino del alta (FOR UPDATE, candados de persona, valvulas solo alrededor del UPDATE), conserva sus datos, deja la actividad reactivacion_alta con id = p_id (idempotencia por actor y huella sin DNI) y responde estado reutilizado; un reintento tras un segundo retiro reactiva LA MISMA ficha del primer rastro (nunca otra del mismo contacto); un reintento con rastro previo nunca crea otra ficha: si su ficha ya no existe responde 22023, si quedo vetada no contactar, si esta enlazada o convertida ya es cliente (R3-1), y si otro lead activo coincide con lo tecleado sin que el verificador lo califique responde tomado o en bolsa para ese lead, o 22023 (R4-1); un retirado enlazado a persona bloquea (ya es cliente) tambien por telefono, y tambien otro retirado enlazado que casa por el DNI tecleado; un lead activo por un dato conservado bloquea con el veredicto del verificador; solo los indices de contacto vivo (23505) y el CHECK del capital (23514) son veredicto fresco, cualquier otro error se propaga; devuelve NULL cuando no actua. Exige p_actor = auth.uid(). Solo lo llama el alta. Bloque 2.7 (D-22, D-25, D-27): en un alta nueva (no en el reintento), si el telefono tecleado -o, si con el no casa ninguno, el DNI tecleado- es el de un lead convertido (activo o retirado) responde ya es cliente sin crear, reactivar ni escribir nada: el juicio de identidad de su persona (ya_es_cliente con su asesor, o no_contactar si esta vetada) o, sin persona, ya_es_cliente a nombre del dueno de esa ficha; el telefono manda (tambien con otro DNI tecleado) y los dos van antes que cualquier retirado no convertido.';

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_nucleo regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_alta regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  v_src text;
  v_prosrc text;
  v_def text;
  r record;
  v text;
  v_foto text := '';
  v_gates integer := 0;
begin
  select p.prosrc, md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_src, v_prosrc, v_def from pg_proc p where p.oid = v_nucleo;
  if (length(v_src) - length(replace(v_src, 'v_convertido record;', ''))) / length('v_convertido record;') <> 1
     or (length(v_src) - length(replace(v_src, '1b. EL CLIENTE YA CONVERTIDO', ''))) / length('1b. EL CLIENTE YA CONVERTIDO') <> 1
     or (length(v_src) - length(replace(v_src, 'into v_convertido', ''))) / length('into v_convertido') <> 2 then
    raise exception 'POSTFLIGHT cliente_por_telefono: la regla no quedó exactamente una vez en el núcleo';
  end if;
  if v_prosrc <> 'f74838f274a8db971952eb9c09c7387e' or v_def <> 'c56e4abd191b947177a9179a7d558dbd' then
    raise exception 'POSTFLIGHT cliente_por_telefono: el núcleo no quedó exactamente como se ensayó (md5 del cuerpo %, de la definición %; se esperaban f74838f274a8db971952eb9c09c7387e y c56e4abd191b947177a9179a7d558dbd)',
      v_prosrc, v_def;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_nucleo) is distinct from current_setting('cliente_por_telefono.nucleo_antes', true)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = v_nucleo) is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE')
     or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    raise exception 'POSTFLIGHT cliente_por_telefono: la ficha del núcleo cambió (dueño, DEFINER, volatilidad, configuración, ACL o firma) o alguien distinto de postgres puede ejecutarlo';
  end if;
  if position('Bloque 2.7 (D-22, D-25, D-27)' in coalesce(obj_description(v_nucleo, 'pg_proc'), '')) = 0 then
    raise exception 'POSTFLIGHT cliente_por_telefono: el comentario nuevo del núcleo no quedó';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) || '|' || coalesce(p.proacl::text, '-') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-')
        from pg_proc p where p.oid = v_alta) is distinct from current_setting('cliente_por_telefono.alta_antes', true)
     or (select md5(p.prosrc) from pg_proc p where p.oid = v_alta) is distinct from '30109c536ef0a73a85da1eb3465b8ed2' then
    raise exception 'POSTFLIGHT cliente_por_telefono: crm.crear_lead_si_disponible cambió (cuerpo, ACL o comentario) y esta migración no la toca';
  end if;
  if (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
        from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    raise exception 'POSTFLIGHT cliente_por_telefono: el verificador cambió';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.juicio_persona(uuid,uuid)')) is distinct from '2570f6eab5ae8b076e6f759b43b9b659'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.inversionista_canonica(uuid)')) is distinct from '6c7ff6001df2cb047967fa61b3ceb763'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)')) is distinct from 'a9ac3a87a7707e98c7cc8afbf9c663c3' then
    raise exception 'POSTFLIGHT cliente_por_telefono: cambió una pieza que esta migración no toca';
  end if;
  -- La foto de los private.assert_*() sin argumentos (sin los `*_mutantes`: ver el preflight) —estado (pasa) o SQLSTATE + texto
  -- ÍNTEGRO del primer error— es EXACTAMENTE la misma que antes de la migración. Garantiza eso y solo eso: no acredita PASS de un
  -- gate que ya caía.
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    v_gates := v_gates + 1;
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  if v_foto is distinct from current_setting('cliente_por_telefono.trinquetes_antes', true) then
    raise exception E'POSTFLIGHT cliente_por_telefono: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('cliente_por_telefono.trinquetes_antes', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT cliente_por_telefono: núcleo % / % · alta y verificador intactos · % trinquetes idénticos a los previos',
    v_prosrc, v_def, v_gates;
end
$postflight$;

commit;

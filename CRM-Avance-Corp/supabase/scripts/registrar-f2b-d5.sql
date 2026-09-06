-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-5]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.
-- Idempotente; toma el MISMO advisory que la migración y la reversa; exige las dos firmas transformadas y la herramienta con su
-- cuerpo, definer, dueño, search_path y grants exactos, y se niega si la versión ya está registrada con OTRO contenido.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d5_rpc_un_argumento_cerradas_con_on'));
do $chk$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reservar_conversion_lead(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '1a95dfd21b7306dd32464b9a13b61bd3') then
    raise exception 'REGISTRO D-5: crm.reservar_conversion_lead(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'f04bd6873e2e193f4b3e1d31eb3d0198') then
    raise exception 'REGISTRO D-5: crm.marcar_efectos_conversion(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '78c301d2a208a25b3cb8fb1849307f0e') then
    raise exception 'REGISTRO D-5: crm.marcar_efectos_conversion(uuid,uuid,text) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.abandonar_conversion_gerencia_fn(uuid,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '8d52df269b43040e43f73d61789321d7') then
    raise exception 'REGISTRO D-5: crm.abandonar_conversion_gerencia_fn no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid where t.tgrelid = 'crm.multiempresa_flags'::regclass and t.tgname = 'trg_multiempresa_flags_00_serializa_puertas' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16 and p.prosecdef and p.proconfig @> array['search_path=""'])
     or has_function_privilege('authenticated', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE') or has_function_privilege('anon', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE') or has_function_privilege('service_role', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE') then
    raise exception 'REGISTRO D-5: el trigger que serializa el cambio de bandera (crm.multiempresa_flags) falta, está deshabilitado, no es BEFORE UPDATE o su función tiene EXECUTE para la API';
  end if;
  if exists (select 1 from unnest(array['crm.reservar_conversion_lead(uuid)','crm.marcar_efectos_conversion(uuid)','crm.marcar_efectos_conversion(uuid,uuid,text)','crm.abandonar_conversion_gerencia_fn(uuid,text)']) f(firma)
             where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('crm.reservar_conversion_lead(uuid)'::regprocedure, 'crm.marcar_efectos_conversion(uuid)'::regprocedure, 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure, 'crm.abandonar_conversion_gerencia_fn(uuid,text)'::regprocedure) and a.grantee = 0) then
    raise exception 'REGISTRO D-5: los grants no son «solo authenticated» (ni anon, ni service_role, ni PUBLIC)';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version='20260906140000' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '38dc5033c3a0f3a27aacd7aaefb071de')) then
    raise exception 'REGISTRO D-5: la versión 20260906140000 ya está registrada con otro contenido (o incompleto)';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260906140000', 'crm_f2b_d5_rpc_de_un_argumento_cerradas_con_on', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-5] — LAS RPC DE UN ARGUMENTO DE LA CONVERSIÓN
-- SE CIERRAN CON LA IDENTIDAD ENCENDIDA, Y GERENCIA PUEDE ABANDONAR UNA CONVERSIÓN SELLADA SIN CUENTA (bloque 4, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE: la conversión Avance de hoy (edge crm-convertir-lead, bandera apagada) reserva POR LEAD (reservar_conversion_lead de
-- 1 argumento) y sella sin persona (marcar_efectos_conversion de 1 argumento). b4 trajo las sobrecargas POR PERSONA
-- (reserva con documento + datos, sellado con claim + token) vigiladas por la saga de Auth, y dejó las firmas viejas para la
-- bandera apagada (paridad). Con la bandera ENCENDIDA esas firmas viejas seguían abiertas: un cliente viejo del edge (o
-- cualquier sesión con puede_gestionar_contratos) podía reservar y sellar SIN persona y crear una cuenta que la saga no ve
-- (b4 M3 / Codex #8: «la garantía sin cuentas huérfanas vale solo tras D-5»). Ahora, ENCENDIDA, las dos responden P0409
-- («la conversión va por persona: actualiza el CRM»); APAGADA no cambian ni un byte de comportamiento (guarda al entrar,
-- tras la autorización de siempre). Salvedad necesaria: el sellado por persona (3 argumentos) DELEGA en la firma de un
-- argumento para escribir efectos_iniciados_en; ese paso viaja marcado con el GUC transaccional crm.sellado_por_persona
-- (mismo patrón que crm.reapertura_identidad / crm.dni_por_puerta en D-13) y es el único que la guarda deja pasar encendida. Y Gerencia gana crm.abandonar_conversion_gerencia_fn(lead, motivo) (Codex E2 #12):
-- una reserva SELLADA cuyo edge murió antes de crear la cuenta dejaba a la persona «en conversión» para siempre; con
-- claim en `reclamado` (nada externo) y la ejecución vencida, Gerencia borra reserva y claim con motivo (nota en el lead,
-- audit_log por los triggers de las dos tablas). Con cuenta o ficha creadas, el camino sigue siendo RETOMAR (b4).
-- Transformación anclada al texto VIVO de producción (vivas/d5/, huellas-d5-prod.txt); reversa byte a byte.
-- Ensayo: scripts/oraculo-f2b-d5.sh. Reversa: scripts/rollback-f2b-d5.sql. Registro: scripts/registrar-f2b-d5.sql.
-- ENCENDIDO SERIALIZADO (Codex v3 #3/#4): las firmas de un argumento y crm.reabrir_lead_fn (D-15) leen la bandera bajo el
-- advisory COMPARTIDO crm_flag_resolver_en_puertas y el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO (trigger nuevo):
-- una llamada que entró apagada termina apagada; el encendido espera a las llamadas en vuelo y frena a las nuevas hasta confirmar.
-- CAPAS: D-5 transforma el sellado por persona (texto de D-13) y la reserva de 1 argumento (texto que D-10/D-13/E2/E3 anclan):
-- mientras D-5 esté aplicada, las reversas y registros de D-13/D-10/E2/E3 rehúsan (correcto). Orden de reversa: D-15 → D-5 → D-13.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d5_rpc_un_argumento_cerradas_con_on'));

do $guard$
begin
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-5: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reservar_conversion_lead(uuid)')), '') not in ('6312a17af8c5af75ea04ae649d50896f', '1a95dfd21b7306dd32464b9a13b61bd3') then
    raise exception 'F2.b D-5: crm.reservar_conversion_lead(uuid) no es ni el texto vivo de producción (6312a17a…) ni el de D-5';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.marcar_efectos_conversion(uuid)')), '') not in ('098bc79771ac5acae28a0b5f7ff91a1e', 'f04bd6873e2e193f4b3e1d31eb3d0198') then
    raise exception 'F2.b D-5: crm.marcar_efectos_conversion(uuid) no es ni el texto vivo de producción (098bc797…) ni el de D-5';
  end if;
  if to_regprocedure('crm.reservar_conversion_lead(uuid,text,text,jsonb)') is null or to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)') is null then
    raise exception 'F2.b D-5: faltan las sobrecargas por persona de b4 (reserva de 4 argumentos / sellado de 3)';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)')), '') not in ('dac3606741accbc1ea96362440405bbf', '78c301d2a208a25b3cb8fb1849307f0e') then
    raise exception 'F2.b D-5: crm.marcar_efectos_conversion(uuid,uuid,text) no es ni el texto vivo de producción (D-13, dac36067…) ni el de D-5';
  end if;
  if to_regprocedure('private.es_gerencia_crm_activa()') is null or left(md5(pg_get_functiondef('private.es_gerencia_crm_activa()'::regprocedure)), 8) <> 'ca6f82ba' then
    raise exception 'F2.b D-5: private.es_gerencia_crm_activa() falta o no es el texto vivo de producción (esperado ca6f82ba…)';
  end if;
  if to_regprocedure('private.persona_en_conversion(uuid,uuid)') is null or left(md5(pg_get_functiondef('private.persona_en_conversion(uuid,uuid)'::regprocedure)), 8) <> 'cc7e1e04' then
    raise exception 'F2.b D-5: private.persona_en_conversion(uuid,uuid) falta o no es el texto vivo de producción (esperado cc7e1e04…)';
  end if;
  if to_regprocedure('crm.retomar_conversion_gerencia_fn(uuid)') is null or left(md5(pg_get_functiondef('crm.retomar_conversion_gerencia_fn(uuid)'::regprocedure)), 8) <> 'c6aa6301' then
    raise exception 'F2.b D-5: crm.retomar_conversion_gerencia_fn(uuid) falta o no es el texto vivo de producción (esperado c6aa6301…)';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='crm' and table_name='conversion_reservas' and column_name in ('inversionista_id','claim_id','efectos_iniciados_en','vence_absoluto_en') having count(*) = 4)
     or to_regclass('crm.multiempresa_idempotencia') is null then
    raise exception 'F2.b D-5: crm.conversion_reservas no tiene las columnas de b4 o falta crm.multiempresa_idempotencia';
  end if;
end
$guard$;

-- ============================================================================
-- 1. crm.reservar_conversion_lead(uuid): la reserva por lead se cierra con la bandera encendida
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.reservar_conversion_lead(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_lead     crm.leads%rowtype;
  v_expira   timestamptz;
  v_ahora    timestamptz := now();
  v_ventana  interval := interval '5 minutes';
  -- Tope absoluto: más allá de esto, ni el propio dueño renueva. Holgado para
  -- cualquier conversión real (que tarda segundos) y corto para un secuestro.
  v_tope     interval := interval '30 minutes';
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-5] (b4 M3, Codex #8): con la identidad unificada ENCENDIDA la conversión Avance reserva y sella POR PERSONA
  -- (sobrecargas de b4: reserva con documento + datos, sellado con claim + token, saga de Auth vigilada). Esta firma de UN
  -- argumento —la reserva por lead, sin persona— queda SOLO para la bandera apagada: encendida, se cierra, para que ningún cliente
  -- viejo del edge abra una conversión que la saga no vigila (la cuenta de portal huérfana que b4 vino a impedir).
  -- Codex v3 #3: la guarda se serializa con el CAMBIO de la bandera (candado compartido por bandera; el UPDATE de
  -- crm.multiempresa_flags toma el exclusivo en su trigger): una llamada que entró apagada termina apagada, y una que entre
  -- después del encendido lo ve. Sin esto, una llamada que esperaba por el lead podía escribir sin persona ya encendida.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Con la identidad unificada encendida, la conversión a cliente va por persona (documento y datos): actualiza el CRM y vuelve a intentarlo'
      using errcode = 'P0409', hint = 'crm.reservar_conversion_lead(p_lead_id, p_tipo_documento, p_documento, p_payload)';
  end if;

  -- El FOR UPDATE serializa contra el cierre externo DENTRO de esta
  -- transacción: si el externo va ganando, aquí se espera y luego se ve el lead
  -- ya convertido → la edge se entera ANTES de crear nada.
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;

  -- Alias explícito `r`: en el WHERE del DO UPDATE hay que nombrar la fila que
  -- YA existe, y `crm.conversion_reservas.expira_en` ahí se lee peor de lo que
  -- se ejecuta. Si el WHERE no se cumple no se actualiza nada y el RETURNING no
  -- devuelve fila: eso es la señal de «hay una conversión en vuelo».
  --
  -- Se puede tomar/renovar SOLO si la anterior está caducada, o si es del mismo
  -- actor Y no ha pasado su tope absoluto. Las dos condiciones exigen además
  -- que NADIE haya iniciado efectos: una vez creada la cuenta de Auth, esa
  -- reserva es definitiva y ni su propio dueño la reinicia.
  -- Quién puede tomar o retomar la reserva:
  --   · nadie, si hay efectos iniciados y la reserva es DE OTRO (esa conversión
  --     ya creó una cuenta: solo su dueño puede terminarla);
  --   · SU DUEÑO, siempre que no se haya pasado el tope absoluto — incluso con
  --     efectos ya iniciados. Esto es lo que hace posible el REINTENTO: si la
  --     conversión Avance falla en el último paso, la pantalla dice «reintenta»
  --     y ese reintento tiene que poder entrar. Sin esta rama, un fallo de red
  --     en la última llamada dejaba el lead trabado PARA SIEMPRE.
  --   · cualquiera, si la reserva caducó y nunca hubo efectos.
  -- `efectos_iniciados_en` NO se limpia al retomar: el cierre en cooperativa
  -- sigue vetado, que es la garantía que importa.
  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,
         -- El tope absoluto MANDA sobre la ventana: sin este `least`, renovar a
         -- los 29 minutos daba 5 más y el tope no era un tope.
         expira_en     = least(excluded.expira_en,
                               case when r.reservado_por = v_uid
                                    then r.vence_absoluto_en
                                    else excluded.vence_absoluto_en end),
         vence_absoluto_en = case
           -- Retomar la propia reserva NO reinicia el tope.
           when r.reservado_por = v_uid then r.vence_absoluto_en
           else excluded.vence_absoluto_en
         end
   where (r.reservado_por = v_uid and r.vence_absoluto_en > v_ahora)
      or (r.efectos_iniciados_en is null and r.expira_en <= v_ahora)
  returning r.expira_en into v_expira;

  if v_expira is null then
    -- Distinguir los motivos importa: uno se resuelve esperando y el otro no.
    if exists (select 1 from crm.conversion_reservas r2
               where r2.lead_id = p_lead_id and r2.efectos_iniciados_en is not null) then
      raise exception using
        errcode = 'P0409',
        message = 'Este lead ya tiene una conversion a cliente de Avance empezada por otra persona',
        hint    = 'Ya existe una cuenta de portal a su nombre: quien la empezo tiene que terminarla.';
    end if;
    raise exception using
      errcode = 'P0409',
      message = 'Otra persona esta convirtiendo este lead en este momento',
      hint    = 'Espera unos minutos y vuelve a intentarlo.';
  end if;

  return jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira);
end;
$function$;

-- ============================================================================
-- 2. crm.marcar_efectos_conversion(uuid): el sellado sin persona se cierra con la bandera encendida
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.marcar_efectos_conversion(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_ok  boolean;
  v_inv0 uuid; v_inv1 uuid;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-5] (b4 M3, Codex #8): con la identidad unificada ENCENDIDA la conversión Avance sella POR PERSONA (claim + token,
  -- crm.marcar_efectos_conversion(lead, claim, token), que valida y luego DELEGA aquí bajo la marca crm.sellado_por_persona).
  -- Esta firma de UN argumento —el sellado sin claim ni token— queda SOLO para la bandera apagada y para ese paso: una
  -- llamada directa con la bandera encendida se cierra, para que ningún cliente viejo del edge selle una conversión que la
  -- saga no vigila (la cuenta de portal huérfana que b4 vino a impedir).
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));   -- Codex v3 #3: serializa con el cambio de bandera
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and coalesce(pg_catalog.current_setting('crm.sellado_por_persona', true), 'off') <> 'on' then
    raise exception 'Con la identidad unificada encendida, la conversión a cliente va por persona (documento y datos): actualiza el CRM y vuelve a intentarlo'
      using errcode = 'P0409', hint = 'crm.marcar_efectos_conversion(p_lead_id, p_claim_id, p_token)';
  end if;

  -- El tope absoluto también manda AQUÍ: si ya pasó, esta reserva no vale para
  -- sellar nada, y la edge muere antes de crear la cuenta.
  -- F2.b (b4): si la reserva es por PERSONA, se bloquea la identidad antes de sellar
  -- (orden identidad -> reserva; la conversión coop lee las reservas bajo ese mismo lock).
  select r.inversionista_id into v_inv0 from crm.conversion_reservas r where r.lead_id = p_lead_id;
  perform 1 from crm.inversionistas i
   where i.id = v_inv0
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
   for update;
  -- F2.b (b5) [E3-12]: tras esperar, la persona reservada pudo fusionarse (la reserva ya apunta a la canónica): reintentar.
  if v_inv0 is not null and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    select r.inversionista_id into v_inv1 from crm.conversion_reservas r where r.lead_id = p_lead_id;
    if v_inv1 is distinct from v_inv0 or exists (select 1 from crm.inversionistas i where i.id = v_inv0 and i.estado = 'fusionado') then
      raise exception 'La persona de esta reserva fue fusionada mientras se sellaba; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  update crm.conversion_reservas r
     set efectos_iniciados_en = coalesce(r.efectos_iniciados_en, now())
   where r.lead_id = p_lead_id
     and r.reservado_por = v_uid
     and r.vence_absoluto_en > now()
     and (r.expira_en > now() or r.efectos_iniciados_en is not null)
  returning true into v_ok;

  if not coalesce(v_ok, false) then
    raise exception using
      errcode = 'P0409',
      message = 'La reserva de esta conversion ya no esta viva',
      hint    = 'Vuelve a empezar la conversion desde la ficha del lead.';
  end if;

  return jsonb_build_object('ok', true, 'lead_id', p_lead_id);
end;
$function$;

-- ============================================================================
-- 2b. crm.marcar_efectos_conversion(uuid,uuid,text): el sellado por persona (b4/D-13) marca su paso al delegar
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.marcar_efectos_conversion(p_lead_id uuid, p_claim_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_loc record; v_previo_d5 text; v_res_d5 jsonb;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token)
     or (v_loc.estado->>'lead_id')::uuid is distinct from p_lead_id then
    raise exception 'Saga: claim o token inválidos para este lead' using errcode = '42501';
  end if;
  -- La reserva de este lead debe ser de este claim y de su identidad (Codex E2 #5).
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead no corresponde a este claim' using errcode = 'P0409';
  end if;
  -- F2.b [D-13]: los documentos vigentes de la persona ANTES de su lock (orden documento -> persona, el de la reserva, la toma
  -- y la fusión): una toma/reapertura por ese documento en vuelo termina antes o después de este sellado, nunca en medio.
  perform private.identidad_bloquear_documentos_de(array[v_loc.inversionista_id]);
  -- Veto revalidado bajo el lock de la identidad, ANTES del punto de no retorno (Codex E2 #11).
  perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
  -- F2.b (b5) [E3-12]: tras esperar, la persona del claim pudo fusionarse: reintentar (la fusión exige claims terminales).
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.estado = 'fusionado') then
    raise exception 'La persona de este claim fue fusionada mientras se sellaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.no_contactar) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (Codex #4, auditor v3 M1): el lead FOR SHARE tras la persona y ANTES de la reserva (orden persona -> lead ->
  -- reserva, el mismo de la reserva por persona, la conversión coop y la fusión: sin arista nueva).
  perform 1 from crm.leads l where l.id = p_lead_id for share;
  -- F2.b [D-13] (Codex #5): la pareja (lead, claim, persona) se revalida bajo el lock de la RESERVA: tras esperar, otra reserva
  -- del mismo lead para otra persona no se sella con este claim.
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead cambió mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex v3 B3): el token se relee tras los locks: una reanudación de la reserva mientras se esperaba rota el
  -- token del mismo claim, y esa ejecución vieja no debe autorizar efectos.
  perform 1 from crm.multiempresa_idempotencia m where m.clave = v_loc.clave for share;   -- orden reserva -> claim (b4)
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token) then
    raise exception 'El claim cambió (token rotado) mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex #4): el lead debe seguir vivo y sin otra persona (una conversión directa para otra persona, o un
  -- descarte, mientras la reserva esperaba, no se sella).
  if not exists (select 1 from crm.leads l where l.id = p_lead_id and l.activo
                  and l.etapa not in ('convertido', 'descartado')
                  and (l.inversionista_id is null or private.inversionista_canonica(l.inversionista_id) = v_loc.inversionista_id)
                  and (l.dni is null or private.inversionista_por_documento('DNI', l.dni) = v_loc.inversionista_id)) then   -- Codex v3 B2
    raise exception 'El lead ya no está disponible para esta conversión (convertido, descartado, con otro documento o de otra persona): no se sella'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1/#3): «un solo lead» revalidado bajo el lock de la persona ANTES del punto de no retorno, contando
  -- enlace, puente y sueltos vivos con su documento: un lead de esta persona nacido, reabierto o tomado mientras la reserva
  -- esperaba (o ya vencida) no deja cuentas de portal huérfanas; Gerencia revisa o fusiona.
  if exists (select 1 from private.leads_de_personas(array[v_loc.inversionista_id]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene otro lead: no se sella la conversión (revisión o fusión de Gerencia)'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-5]: la firma de un argumento queda cerrada con la identidad encendida salvo para ESTE paso (b4 M3): aquí ya se
  -- validaron claim, token, veto, pareja y «un solo lead». La marca es transaccional y se restaura al salir.
  v_previo_d5 := coalesce(pg_catalog.current_setting('crm.sellado_por_persona', true), 'off');
  perform pg_catalog.set_config('crm.sellado_por_persona', 'on', true);
  v_res_d5 := crm.marcar_efectos_conversion(p_lead_id);
  perform pg_catalog.set_config('crm.sellado_por_persona', v_previo_d5, true);
  return v_res_d5;
end;
$function$;

-- ============================================================================
-- 2c. crm.multiempresa_flags: el cambio de bandera se serializa con las puertas (candado exclusivo por bandera)
-- ============================================================================
create or replace function private.trg_multiempresa_flags_serializa_puertas()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- F2.b [D-5] (Codex v3 #3/#4): encender o apagar una bandera espera a que terminen las puertas que la leyeron bajo el
  -- candado compartido (pg_advisory_xact_lock_shared('crm_flag_<nombre>')) y bloquea a las que lleguen hasta que el cambio
  -- se confirme. Así ninguna llamada termina con una bandera distinta de la que leyó. Candado por bandera, transaccional.
  if new.activo is distinct from old.activo then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_flag_' || new.nombre));
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_multiempresa_flags_serializa_puertas() from public, anon, authenticated, service_role;
drop trigger if exists trg_multiempresa_flags_00_serializa_puertas on crm.multiempresa_flags;
create trigger trg_multiempresa_flags_00_serializa_puertas
  before update of activo on crm.multiempresa_flags
  for each row execute function private.trg_multiempresa_flags_serializa_puertas();
comment on trigger trg_multiempresa_flags_00_serializa_puertas on crm.multiempresa_flags is
  'F2.b [D-5]: el cambio de una bandera toma el advisory exclusivo crm_flag_<nombre>; las puertas que leen resolver_en_puertas bajo el compartido terminan con la bandera que leyeron.';

-- ============================================================================
-- 3. crm.abandonar_conversion_gerencia_fn(uuid, text): Gerencia abandona una conversión sellada sin cuenta
-- ============================================================================
create or replace function crm.abandonar_conversion_gerencia_fn(p_lead_id uuid, p_motivo text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare
  v_uid    uuid := (select auth.uid());
  v_inv    uuid;
  v_r      crm.conversion_reservas%rowtype;
  v_lead   crm.leads%rowtype;
  v_est    jsonb;
  v_clave  text;
  v_motivo text := nullif(pg_catalog.btrim(p_motivo), '');
  v_previo text;
begin
  -- F2.b [D-5] (Codex E2 #12): una reserva SELLADA (punto de no retorno) cuyo edge murió ANTES de crear la cuenta de Auth
  -- deja a la persona «en conversión» para siempre (persona_en_conversion: sellada y sin convertir): nadie puede darle un
  -- lead, tomarla, reabrirla ni convertirla. Gerencia la ABANDONA con motivo: solo si NADA externo existe (claim en
  -- `reclamado`: sin cuenta de acceso ni ficha) y la ejecución ya no está viva (reserva o lease vencidos): se borran la
  -- reserva y el claim (bitácora en audit_log por sus triggers) y queda una nota en el lead. Con cuenta o ficha creadas
  -- el camino es RETOMAR (crm.retomar_conversion_gerencia_fn); consumada (perfil enlazado) no hay nada que abandonar.
  -- Orden de candados, el de retomar: persona → reserva → lead → claim.
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia abandona una conversión' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if p_lead_id is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;
  if v_motivo is null or pg_catalog.length(v_motivo) < 5 or pg_catalog.length(v_motivo) > 300 then
    raise exception 'El motivo es obligatorio (entre 5 y 300 caracteres)' using errcode = '22023';
  end if;
  select r.inversionista_id into v_inv from crm.conversion_reservas r where r.lead_id = p_lead_id;
  if v_inv is null then
    raise exception 'Este lead no tiene una reserva por persona' using errcode = 'P0002';
  end if;
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
  select * into v_r from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  -- Revalidación tras los candados (auditor v1 #3): la reserva pudo borrarse (doble clic) o cambiar de persona mientras se esperaba.
  if not found then
    raise exception 'Este lead ya no tiene una reserva por persona' using errcode = 'P0002';
  end if;
  if v_r.inversionista_id is distinct from v_inv then
    raise exception 'La reserva cambió de persona mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if v_r.efectos_iniciados_en is null then
    raise exception 'La reserva no está sellada: caduca sola a los pocos minutos, no hay nada que abandonar' using errcode = 'P0409';
  end if;
  select * into v_lead from crm.leads l where l.id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  if v_lead.etapa = 'convertido' then
    raise exception 'El lead ya está convertido: la conversión se consumó, no se abandona' using errcode = 'P0409';
  end if;
  v_clave := 'auth_persona:' || v_inv::text;
  select i.resultado into v_est from crm.multiempresa_idempotencia i where i.clave = v_clave for update;
  if v_est is not null then
    if (v_est->>'lead_id')::uuid is distinct from p_lead_id or v_r.claim_id is distinct from (v_est->>'claim_id')::uuid then
      raise exception 'La reserva y el claim de esta persona no corresponden a este lead' using errcode = 'P0409';
    end if;
    if v_est->>'estado' = 'enlazado' then
      raise exception 'La conversión ya se consumó (ficha enlazada): no se abandona' using errcode = 'P0409';
    end if;
    if v_est->>'estado' in ('auth_creado', 'perfil_creado') then
      raise exception 'Ya existe la cuenta de acceso (o la ficha) de esta persona: retoma la conversión en vez de abandonarla'
        using errcode = 'P0409', hint = 'crm.retomar_conversion_gerencia_fn(p_lead_id)';
    end if;
    if v_est->>'estado' <> 'reclamado' then
      raise exception 'Estado de saga desconocido (%): revisar antes de abandonar', v_est->>'estado' using errcode = 'P0409';
    end if;
  end if;
  -- Nunca expulsa a una ejecución viva (Codex E2 #10): abandonar es destructivo, así que exige los DOS plazos vencidos
  -- (el tope de la reserva Y el lease del claim; sin lease escrito se trata como vivo). Codex v3 #2: un reintento del dueño
  -- renueva el lease diez minutos aunque el tope original haya pasado; con «uno u otro» se le borraba el claim en vuelo.
  if v_r.vence_absoluto_en > pg_catalog.now()
     or (v_est is not null and coalesce((v_est->>'lease_hasta')::timestamptz, 'infinity'::timestamptz) > pg_catalog.now()) then
    raise exception 'La conversión sigue viva (reserva o claim vigentes): espera a que venzan los dos antes de abandonarla' using errcode = 'P0409';
  end if;
  -- Auditor v1 #1 (ALTO): el edge crea el usuario de Auth ANTES de registrar el paso (createUser con app_metadata.claim_id
  -- → registrar_auth). Si murió entre medias, el claim sigue en «reclamado» pero la cuenta EXISTE con la marca de este claim;
  -- borrar el claim la dejaría huérfana para siempre (el reintento la adopta por la marca). Con la marca viva: retomar.
  if v_r.claim_id is not null and exists (select 1 from auth.users u where u.raw_app_meta_data->>'claim_id' = v_r.claim_id::text) then
    raise exception 'Ya existe la cuenta de acceso creada por esta conversión (aún sin registrar en la saga): retoma la conversión en vez de abandonarla'
      using errcode = 'P0409', hint = 'crm.retomar_conversion_gerencia_fn(p_lead_id)';
  end if;
  delete from crm.multiempresa_idempotencia where clave = v_clave;
  delete from crm.conversion_reservas where lead_id = p_lead_id;
  -- Nota administrativa en el lead (no es contacto). La válvula es PREVISIÓN (hoy ningún trigger de crm.actividades veta una
  -- «nota» ni mira la válvula; trg_gestion_lead_serializada exige creado_por = auth.uid(), lead activo y rol, que se cumplen).
  if v_lead.activo then
    v_previo := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off');
    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (p_lead_id, 'nota', 'Conversión abandonada por Gerencia: ' || v_motivo,
            pg_catalog.jsonb_build_object('evento', 'conversion_abandonada', 'inversionista_id', v_inv, 'claim_id', v_r.claim_id,
              'estado_previo', coalesce(v_est->>'estado', 'sin_claim'), 'reservado_por', v_r.reservado_por,
              'sellada_en', v_r.efectos_iniciados_en, 'motivo', v_motivo),
            v_uid);
    perform pg_catalog.set_config('crm.op_privilegiada', v_previo, true);
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', v_inv, 'claim_id', v_r.claim_id,
    'estado_previo', coalesce(v_est->>'estado', 'sin_claim'), 'abandonada_por', v_uid, 'abandonada_en', pg_catalog.now());
end;
$function$;
revoke all on function crm.abandonar_conversion_gerencia_fn(uuid,text) from public, anon, service_role;
grant execute on function crm.abandonar_conversion_gerencia_fn(uuid,text) to authenticated;
comment on function crm.abandonar_conversion_gerencia_fn(uuid,text) is 'F2.b [D-5]: Gerencia abandona (con motivo) una conversión Avance SELLADA que nunca creó la cuenta (claim en reclamado, ejecución vencida): borra reserva y claim, deja nota en el lead y libera a la persona. Con cuenta o ficha creadas: retomar_conversion_gerencia_fn. Solo con la identidad encendida.';

do $post$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reservar_conversion_lead(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '1a95dfd21b7306dd32464b9a13b61bd3') then
    raise exception 'POSTFLIGHT D-5: crm.reservar_conversion_lead(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'f04bd6873e2e193f4b3e1d31eb3d0198') then
    raise exception 'POSTFLIGHT D-5: crm.marcar_efectos_conversion(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '78c301d2a208a25b3cb8fb1849307f0e') then
    raise exception 'POSTFLIGHT D-5: crm.marcar_efectos_conversion(uuid,uuid,text) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.abandonar_conversion_gerencia_fn(uuid,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '8d52df269b43040e43f73d61789321d7') then
    raise exception 'POSTFLIGHT D-5: crm.abandonar_conversion_gerencia_fn no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid where t.tgrelid = 'crm.multiempresa_flags'::regclass and t.tgname = 'trg_multiempresa_flags_00_serializa_puertas' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16 and p.prosecdef and p.proconfig @> array['search_path=""'])
     or has_function_privilege('authenticated', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE') or has_function_privilege('anon', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE') or has_function_privilege('service_role', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE') then
    raise exception 'POSTFLIGHT D-5: el trigger que serializa el cambio de bandera (crm.multiempresa_flags) falta, está deshabilitado, no es BEFORE UPDATE o su función tiene EXECUTE para la API';
  end if;
  if exists (select 1 from unnest(array['crm.reservar_conversion_lead(uuid)','crm.marcar_efectos_conversion(uuid)','crm.marcar_efectos_conversion(uuid,uuid,text)','crm.abandonar_conversion_gerencia_fn(uuid,text)']) f(firma)
             where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('crm.reservar_conversion_lead(uuid)'::regprocedure, 'crm.marcar_efectos_conversion(uuid)'::regprocedure, 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure, 'crm.abandonar_conversion_gerencia_fn(uuid,text)'::regprocedure) and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-5: los grants no son «solo authenticated» (ni anon, ni service_role, ni PUBLIC)';
  end if;
  raise notice 'F2.b D-5 OK: reserva y sellado de 1 argumento cerrados con la bandera encendida (apagada: intactos); abandonar_conversion_gerencia_fn creada.';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
commit;

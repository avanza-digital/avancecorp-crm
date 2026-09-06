-- ============================================================================
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
-- ENCENDIDO SERIALIZADO (Codex v3 #3/#4, auditor v4 #1): las firmas de un argumento, el sellado por persona, las cuatro puertas
-- de D-13 (fijar DNI, tomar, rescatar, deshacer) y crm.reabrir_lead_fn / crm.editar_lead_fn (D-15) leen la bandera bajo el
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
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reservar_conversion_lead(uuid)')), '') not in ('6312a17af8c5af75ea04ae649d50896f', '55bf3300a940729b08f36b1db93075b6') then
    raise exception 'F2.b D-5: crm.reservar_conversion_lead(uuid) no es ni el texto vivo de producción (6312a17a…) ni el de D-5';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.marcar_efectos_conversion(uuid)')), '') not in ('098bc79771ac5acae28a0b5f7ff91a1e', 'b8f9cbc6b5e5ae697c0e9cbad32abbc8') then
    raise exception 'F2.b D-5: crm.marcar_efectos_conversion(uuid) no es ni el texto vivo de producción (098bc797…) ni el de D-5';
  end if;
  if to_regprocedure('crm.reservar_conversion_lead(uuid,text,text,jsonb)') is null or to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)') is null then
    raise exception 'F2.b D-5: faltan las sobrecargas por persona de b4 (reserva de 4 argumentos / sellado de 3)';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.fijar_dni_lead_fn(uuid,text)')), '') not in ('13acdb73eb3c9208370f27b0f4c70ffb', '3b92916944a76fb7bcbc3bce603e4788') then
    raise exception 'F2.b D-5: crm.fijar_dni_lead_fn(uuid,text) no es ni el texto vivo de producción (D-13, 13acdb73…) ni el de D-5';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.tomar_lead_libre(text,text)')), '') not in ('cf17acb39feaf24b8ad8254006b70469', 'f755d63f59dfc0e8959fefb83c7b9f9a') then
    raise exception 'F2.b D-5: crm.tomar_lead_libre(text,text) no es ni el texto vivo de producción (D-13, cf17acb3…) ni el de D-5';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.rescatar_descartes(uuid[],uuid[],boolean)')), '') not in ('33c9033eb6981aed68faec99ee09ee01', '5f4f5ca115f535f6ab8a1209dda19a0f') then
    raise exception 'F2.b D-5: crm.rescatar_descartes(uuid[],uuid[],boolean) no es ni el texto vivo de producción (D-13, 33c9033e…) ni el de D-5';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.deshacer_descarte_implementacion(uuid)')), '') not in ('0818f0b0f82eb8e3bd891b0c1e76dc28', '241c65a8da53c98ec12027692d7724a4') then
    raise exception 'F2.b D-5: private.deshacer_descarte_implementacion(uuid) no es ni el texto vivo de producción (D-13, 0818f0b0…) ni el de D-5';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.retomar_conversion_gerencia_fn(uuid)')), '') not in ('5791cfd76a0b6ff6013d321c768e41a6', 'cff6d812b0385a52d86700507bdb33c2') then
    raise exception 'F2.b D-5: crm.retomar_conversion_gerencia_fn(uuid) no es ni el texto vivo de producción (D-13, 5791cfd7…) ni el de D-5';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)')), '') not in ('dac3606741accbc1ea96362440405bbf', '801d4262f24c43e9f5ca41a9ecb36e76') then
    raise exception 'F2.b D-5: crm.marcar_efectos_conversion(uuid,uuid,text) no es ni el texto vivo de producción (D-13, dac36067…) ni el de D-5';
  end if;
  if to_regprocedure('private.es_gerencia_crm_activa()') is null or left(md5(pg_get_functiondef('private.es_gerencia_crm_activa()'::regprocedure)), 8) <> 'ca6f82ba' then
    raise exception 'F2.b D-5: private.es_gerencia_crm_activa() falta o no es el texto vivo de producción (esperado ca6f82ba…)';
  end if;
  if to_regprocedure('private.persona_en_conversion(uuid,uuid)') is null or left(md5(pg_get_functiondef('private.persona_en_conversion(uuid,uuid)'::regprocedure)), 8) <> 'cc7e1e04' then
    raise exception 'F2.b D-5: private.persona_en_conversion(uuid,uuid) falta o no es el texto vivo de producción (esperado cc7e1e04…)';
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
  -- Codex v4 #2: READ COMMITTED SIEMPRE antes de leer la bandera (una foto REPEATABLE READ anterior al encendido seguiría
  -- viendo la bandera vieja aunque tome el candado). PostgREST nunca usa otro aislamiento.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La conversión requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
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
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then   -- Codex v4 #2
    raise exception 'La conversión requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));   -- Codex v3 #3: serializa con el cambio de bandera (reentrante desde el sellado por persona)
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
  -- F2.b [D-5] (Codex v4 #3, auditor v4 #2): READ COMMITTED y el candado COMPARTIDO de la bandera AL ENTRAR, antes de tomar
  -- documentos y filas: así el sellado nunca retiene candados de negocio mientras espera por un cambio de bandera, y el
  -- compartido que la firma de un argumento vuelve a tomar al delegar es reentrante (misma transacción).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La conversión requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
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
-- 2d. Las cuatro puertas de D-13 (fijar DNI, tomar, rescatar, deshacer) leen la bandera bajo el compartido, y la retoma de
--     Gerencia (b4) adopta el criterio de «ejecución viva» de abandonar (ambos plazos vencidos; sin lease = anomalía)
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.fijar_dni_lead_fn(p_lead_id uuid, p_dni text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_lead crm.leads%rowtype; v_inv uuid; v_v jsonb; v_previo text; v_k text; v_claves text[] := '{}';
  v_flag boolean;
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'Acceso CRM revocado' using errcode = '42501';
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception 'El DNI debe tener exactamente 8 digitos' using errcode = '22023';
  end if;
  -- Ámbito ANTES de cualquier candado (auditor v4 M1): un lead ajeno o inexistente muere aquí sin sondear a nadie.
  if not exists (select 1 from crm.leads l
                  where l.id = p_lead_id and l.activo = true
                    and (v_rol = 'gerencia'
                         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  -- F2.b [D-5] (auditor v4 #1): la bandera se lee bajo el candado COMPARTIDO crm_flag_resolver_en_puertas (el cambio de
  -- bandera toma el exclusivo): esta llamada termina con la bandera que leyó, aunque espere por una fila.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
  if v_flag then
    -- Candados del documento ANTERIOR y del nuevo, en orden de texto (Codex v4.1): una toma o reapertura en vuelo que
    -- bloqueó el documento anterior termina antes de que este cambio lo deje obsoleto; y quien llegue después ve el nuevo.
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    for v_k in select k from (select l.dni as k from crm.leads l where l.id = p_lead_id and l.dni is not null
                              union select v_dni where v_dni is not null) s order by k loop
      perform private.identidad_bloquear_documento('DNI', v_k);
      v_claves := v_claves || v_k;
    end loop;
    if v_dni is not null then
      v_inv := private.inversionista_por_documento('DNI', v_dni);
      if v_inv is not null then
        perform 1 from crm.inversionistas i where i.id = v_inv for share;
      end if;
    end if;
  end if;
  select * into v_lead
  from crm.leads l
  where l.id = p_lead_id and l.activo = true
    and (v_rol = 'gerencia'
         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.dni is not distinct from v_dni then
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'sin_cambios', true);
  end if;
  if v_flag then
    -- Codex v4.3 [1]: si la bandera se apagó en medio, los candados de documento fueron no-ops: no se escribe con una lista vacía.
    if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
      raise exception 'La identidad unificada se apagó durante la operación; vuelve a intentarlo' using errcode = '40001';
    end if;
    -- El documento anterior ACTUAL debe ser uno de los bloqueados (Codex v4.2: otra llamada pudo cambiarlo mientras se esperaba).
    if v_lead.dni is not null and not (v_lead.dni = any(v_claves)) then
      raise exception 'El documento de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    if v_lead.inversionista_id is not null or exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id) then
      raise exception 'El documento de un lead ya reconocido solo lo corrige Gerencia (corrección de documento)' using errcode = 'P0409';
    end if;
    if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))) then
      raise exception 'Este lead tiene una conversión en curso: no se cambia su documento' using errcode = 'P0409';
    end if;
    if v_inv is not null then
      v_v := private.juicio_persona(v_inv, p_lead_id);
      if v_v is not null then
        if v_v->>'estado' = 'no_contactar' then
          raise exception 'La persona de ese documento tiene la restricción «No insistir»' using errcode = 'P0429';
        end if;
        raise exception 'La persona de ese documento ya es cliente o ya tiene su lead: no se puede asignar a este'
          using errcode = 'P0409', detail = v_v::text;
      end if;
    end if;
  end if;
  v_previo := coalesce(pg_catalog.current_setting('crm.dni_por_puerta', true), 'off');
  perform pg_catalog.set_config('crm.dni_por_puerta', 'on', true);
  update crm.leads set dni = v_dni where id = p_lead_id;
  perform pg_catalog.set_config('crm.dni_por_puerta', v_previo, true);
  if v_flag and v_inv is not null then
    perform private.enlazar_lead_reabierto(p_lead_id, v_inv);
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'dni', v_dni,
    'inversionista_id', case when v_flag then v_inv end, 'enlazado', v_flag and v_inv is not null);
end;
$function$;

CREATE OR REPLACE FUNCTION crm.tomar_lead_libre(p_telefono text, p_dni text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_tel text := private.normalizar_telefono(p_telefono);
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_veredicto_identidad jsonb;
  v_flag_d13 boolean;
  v_candidato uuid;
  v_bloqueo jsonb;
  v_previo_reab text;
  v_lead crm.leads%rowtype;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_quedo_libre_en timestamptz;
  v_ultima_conv timestamptz;
  v_propietario_anterior uuid;
  v_modo text;
  v_previo text;
begin
  v_rol := private.rol_crm(v_actor);
  if v_actor is null or v_rol is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La toma directa es del VENDEDOR para sí mismo (spec §7). Supervisor y
  -- gerencia ya tienen su puerta con destino elegible: el reparto.
  if v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'La toma directa es solo para vendedores; supervisión asigna por el reparto';
  end if;
  -- F2.b [D-5] (auditor v4 #1): la bandera se lee bajo el candado COMPARTIDO crm_flag_resolver_en_puertas (el cambio de
  -- bandera toma el exclusivo): esta llamada termina con la bandera que leyó, aunque espere por una fila.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag_d13 := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);

  if v_tel is null or v_tel !~ '^\+519[0-9]{8}$' then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      pg_catalog.jsonb_build_object(
        'estado', 'error',
        'detalle', 'telefono_invalido'
      ));
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  -- F2.b [D-13]: los candados de PERSONA van ANTES de la fila (orden total documento -> persona -> lead, el de la reserva,
  -- el sellado y la fusión). El blanco se localiza SIN lock con el mismo criterio de abajo (teléfono manda; si no, DNI),
  -- se bloquean sus documentos y su persona (y los del DNI tecleado), y después se toma la fila; si la fila ya no es la
  -- misma o su persona cambió, manda el veredicto fresco. Inerte con la bandera apagada.
  if v_flag_d13 then
    select l.id into v_candidato
    from crm.leads l
    where l.telefono = v_tel
      and l.no_contactar = false
      and not private.persona_vetada(l.id)
      and (
        (l.activo = true
          and l.etapa not in ('convertido', 'descartado')
          and l.vendedor_id is null
          and l.asignado_supervisor_id is null)
        or (l.etapa = 'descartado' and l.descartado_en is not null)
      )
    order by (l.etapa = 'descartado'), l.descartado_en desc, l.id
    limit 1;
    if v_candidato is null and v_dni is not null then
      select l.id into v_candidato
      from crm.leads l
      where l.dni = v_dni
        and l.no_contactar = false
        and not private.persona_vetada(l.id)
        and (
          (l.activo = true
            and l.etapa not in ('convertido', 'descartado')
            and l.vendedor_id is null
            and l.asignado_supervisor_id is null)
          or (l.etapa = 'descartado' and l.descartado_en is not null)
        )
      order by (l.etapa = 'descartado'), l.descartado_en desc nulls last, l.id
      limit 1;
    end if;
    v_bloqueo := private.bloquear_personas_de_leads(case when v_candidato is null then '{}'::uuid[] else array[v_candidato] end, v_dni);
  end if;

  -- Vetos de contacto ANTES de bloquear filas: baratos, y el veredicto que
  -- devuelven es el mismo que daría la verificación.
  if exists (
    select 1
    from crm.leads l
    where (l.no_contactar = true or private.persona_vetada(l.id))  -- F2.b (b2): veto de la persona
      and (l.telefono = v_tel or (v_dni is not null and l.dni = v_dni))
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      pg_catalog.jsonb_build_object('estado', 'no_contactar'));
  end if;

  if exists (
    select 1
    from public.perfiles per
    where per.rol = 'cliente'
      and per.activo = true
      and (
        private.normalizar_telefono(per.telefono) = v_tel
        or (v_dni is not null and per.dni = v_dni)
      )
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- El blanco, POR CONTACTO y el TELÉFONO manda (adenda 16/08-b del ledger):
  -- solo si el número no casa con nada se cae al DNI. FILA primero — el orden
  -- advisory→fila se abraza con «Deshacer descarte» (refutador del plan); las
  -- llaves advisory las toman los triggers del propio UPDATE, en el orden de
  -- los caminos vivos. ORDER BY determinista: la bolsa viva antes que los
  -- descartes, el descarte más reciente primero, id como desempate.
  select l.* into v_lead
  from crm.leads l
  where l.telefono = v_tel
    -- Codex R4: el veto DENTRO del predicado — EvalPlanQual lo re-evalúa
    -- sobre la versión nueva tras esperar la fila; el pre-chequeo solo no
    -- veía un no_contactar en vuelo.
    and l.no_contactar = false
    and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
    and (
      (l.activo = true
        and l.etapa not in ('convertido', 'descartado')
        and l.vendedor_id is null
        and l.asignado_supervisor_id is null)
      -- Espejo del impl: un descarte sin fecha es anomalía y no se toma.
      or (l.etapa = 'descartado' and l.descartado_en is not null)
    )
  order by (l.etapa = 'descartado'), l.descartado_en desc, l.id
  limit 1
  for update;

  if not found and v_dni is not null then
    select l.* into v_lead
    from crm.leads l
    where l.dni = v_dni
      and l.no_contactar = false
      and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
      and (
        (l.activo = true
          and l.etapa not in ('convertido', 'descartado')
          and l.vendedor_id is null
          and l.asignado_supervisor_id is null)
        -- Espejo EXACTO del brazo telefónico (auditor M1): sin este filtro un
        -- descarte-anomalía sin fecha entraba por el DNI saltándose
        -- enfriamiento y carencia.
        or (l.etapa = 'descartado' and l.descartado_en is not null)
      )
    order by (l.etapa = 'descartado'), l.descartado_en desc nulls last, l.id
    limit 1
    for update;
  end if;

  if not found then
    -- Nada tomable con ese contacto: el veredicto fresco explica qué pasa
    -- (tomado por otro, libre → alta nueva, etc.).
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- P-048: el permiso se re-consulta DESPUÉS del lock — una membresía
  -- revocada mientras esperaba la fila no alcanza a tomar al despertar. El
  -- FOR SHARE ancla la fila de equipo (Codex, carrera de offboarding): la
  -- desactivación la toma FOR UPDATE, así que o ella terminó (y aquí se ve
  -- inactivo) o espera a que esta toma termine (y su chequeo de dependencias
  -- verá el lead nuevo). Sin ciclo: la desactivación no bloquea crm.leads.
  perform 1
  from crm.equipo e
  where e.perfil_id = v_actor
  for share;
  if private.rol_crm(v_actor) is distinct from 'vendedor'
     or not private.es_destino_crm_activo(v_actor, array['vendedor']::text[]) then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- F2.b [D-13]: la fila tomada debe ser el candidato bloqueado y seguir DENTRO de lo bloqueado: su documento actual entre las
  -- claves y su persona entre las personas (Codex v4.1/v4.2: un cambio de DNI en medio, incluso A->B->A, dejaría obsoleto el
  -- candado); si no, veredicto fresco.
  if v_flag_d13 and (v_lead.id is distinct from v_candidato or not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo)) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, coalesce(v_dni, v_lead.dni)));
  end if;
  -- F2.b [D-13]: el JUICIO único de reapertura/toma (documento tecleado, documento del blanco, puente, enlace; otro lead de la
  -- persona, conversión en curso, ya cliente): con veredicto asentado y sin escribir nada.
  if v_flag_d13 then
    v_veredicto_identidad := private.juicio_reapertura(v_lead.id, v_tel, v_dni);
    if v_veredicto_identidad is not null then
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni, v_veredicto_identidad);
    end if;
  end if;

  -- Si OTRO lead vivo del mismo contacto tiene DUEÑO, el contacto está tomado
  -- aunque nuestro blanco sea un descarte viejo: manda el veredicto fresco.
  -- El filtro de dueño es deliberado: una bolsa viva que casa solo por el OTRO
  -- dato no estorba (el teléfono manda) — sin él, el veredicto diría «en
  -- bolsa» y la toma rebotaría en bucle contra su propio blanco telefónico.
  if exists (
    select 1
    from crm.leads l
    where l.id <> v_lead.id
      and l.activo = true
      and l.etapa not in ('convertido', 'descartado')
      and (l.vendedor_id is not null or l.asignado_supervisor_id is not null)
      and (l.telefono = v_tel or (v_dni is not null and l.dni = v_dni))
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  v_propietario_anterior := coalesce(v_lead.vendedor_id, v_lead.asignado_supervisor_id);
  v_ultima_conv := (
    select pg_catalog.max(a.creado_en)
    from crm.actividades a
    where a.lead_id = v_lead.id
      and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
  );

  if v_lead.activo = true
     and v_lead.etapa not in ('convertido', 'descartado')
     and v_lead.vendedor_id is null
     and v_lead.asignado_supervisor_id is null then
    v_modo := 'bolsa';
    v_quedo_libre_en := null;
  elsif v_lead.etapa = 'descartado' then
    if v_lead.activo = false then
      -- Un soft-borrado no se revive por esta puerta (regla del plan).
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    select ep.dias into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;
    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);
    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    if v_dias = 0
       and v_lead.descartado_en + pg_catalog.make_interval(hours => 24) > pg_catalog.now() then
      -- Carencia de Miguel: un descarte de 0 días espera 24 h para TOMARSE.
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    v_modo := 'reutilizable';
    v_quedo_libre_en := case
      when v_dias > 0 then v_disponible_desde
      else v_lead.descartado_en + pg_catalog.make_interval(hours => 24)
    end;
  else
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- La válvula, SOLO alrededor del UPDATE, y quien la enciende la apaga.
  v_previo := coalesce(pg_catalog.current_setting('crm.toma_directa', true), 'off');
  perform pg_catalog.set_config('crm.toma_directa', 'on', true);
  v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);

  if v_modo = 'bolsa' then
    update crm.leads l
       set vendedor_id = v_actor
     where l.id = v_lead.id
       and l.activo = true
       and l.no_contactar = false
       and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
       and l.etapa not in ('convertido', 'descartado')
       and l.vendedor_id is null
       and l.asignado_supervisor_id is null;
  else
    begin
      update crm.leads l
         set etapa = 'nuevo',
             vendedor_id = v_actor,
             asignado_supervisor_id = null,
             motivo_descarte = null
       where l.id = v_lead.id
         and l.activo = true
         and l.no_contactar = false
         and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
         and l.etapa = 'descartado';
    exception
      when unique_violation then
        -- Los índices de dedup (solo vivos) cazaron un vivo del mismo
        -- contacto: nadie roba, se responde la verdad fresca. El DNI del
        -- BLANCO entra en la consulta a propósito: el choque pudo venir por
        -- un dato que el vendedor no tecleó, y sin él el veredicto repetiría
        -- 'reutilizable' e invitaría a un bucle de reintentos.
        perform pg_catalog.set_config('crm.toma_directa', v_previo, true);
        perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);
        return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
          private.verificar_disponibilidad_lead_impl(v_tel, coalesce(v_dni, v_lead.dni)));
    end;
  end if;

  perform pg_catalog.set_config('crm.toma_directa', v_previo, true);
  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);

  if not found then
    -- CAS en 0 filas: el estado cambió entre el veredicto y la escritura.
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;
  -- F2.b [D-13] (Codex #5): un lead con DNI (o puente) de una persona reconocida queda ENLAZADO al tomarse, como al nacer:
  -- así la reserva, el sellado y las conversiones lo ven por identidad. La persona ya está bloqueada FOR SHARE (arriba).
  if v_flag_d13 and v_lead.inversionista_id is null then
    perform private.enlazar_lead_reabierto(v_lead.id, private.lead_persona_reabrir(v_lead.id));
  end if;

  -- Traza §9 (además de la cascada, que ya asentó 'reasignacion' + ledger):
  -- la nota rica del evento, firmada por quien tomó.
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por, creado_en)
  values (
    v_lead.id,
    'nota',
    case v_modo
      when 'bolsa' then 'Lead tomado desde la bolsa tras verificación de disponibilidad'
      else 'Lead tomado después de liberación por enfriamiento vencido'
    end,
    pg_catalog.jsonb_build_object(
      'evento', 'toma_directa',
      'modo', v_modo,
      'propietario_anterior', v_propietario_anterior,
      'ultima_conversacion', v_ultima_conv,
      'quedo_libre_en', v_quedo_libre_en,
      'motivo', case v_modo when 'bolsa' then 'toma_de_bolsa' else 'enfriamiento_vencido' end
    ),
    v_actor,
    pg_catalog.statement_timestamp()
  );

  -- La fila FINAL (los BEFORE ya subieron ciclo y renacieron tenencia).
  select l.* into v_lead from crm.leads l where l.id = v_lead.id;

  return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
    pg_catalog.jsonb_build_object(
      'estado', 'tomado_ok',
      'lead_id', v_lead.id,
      'modo', v_modo,
      'etapa', v_lead.etapa,
      'ciclo_actual', v_lead.ciclo_actual,
      'tenencia_desde', v_lead.tenencia_desde
    ));
end;
$function$;

CREATE OR REPLACE FUNCTION crm.rescatar_descartes(p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_destinos_validos uuid[];
  v_total_episodios integer;
  v_total_destinos integer;
  v_candidatos integer := 0;
  v_orden integer := 0;
  v_intento integer;
  v_destino uuid;
  v_fila record;
  v_flag boolean;
  v_veredicto jsonb;
  v_bloqueo jsonb;
  v_previo_reab text;
begin
  if p_episodios is null
     or pg_catalog.array_length(p_episodios, 1) is null
     or pg_catalog.array_length(p_episodios, 1) = 0
     or pg_catalog.array_length(p_episodios, 1) > 100
     or pg_catalog.array_position(p_episodios, null) is not null then
    raise exception 'Selecciona entre 1 y 100 descartes válidos'
      using errcode = '22023';
  end if;

  if (select pg_catalog.count(*) from (
    select distinct id from pg_catalog.unnest(p_episodios) as u(id)
  ) episodios_unicos) <> pg_catalog.array_length(p_episodios, 1) then
    raise exception 'Un descarte no se puede enviar dos veces en el mismo reparto'
      using errcode = '22023';
  end if;

  if p_analistas_destino is null
     or pg_catalog.array_length(p_analistas_destino, 1) is null
     or pg_catalog.array_length(p_analistas_destino, 1) = 0
     or pg_catalog.array_length(p_analistas_destino, 1) > 30
     or pg_catalog.array_position(p_analistas_destino, null) is not null then
    raise exception 'Selecciona al menos un asesor destino'
      using errcode = '22023';
  end if;

  if (select pg_catalog.count(*) from (
    select distinct id from pg_catalog.unnest(p_analistas_destino) as u(id)
  ) destinos_unicos) <> pg_catalog.array_length(p_analistas_destino, 1) then
    raise exception 'No repitas un asesor destino'
      using errcode = '22023';
  end if;

  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede rescatar descartes'
      using errcode = '42501';
  end if;
  -- F2.b [D-5] (auditor v4 #1): la bandera se lee bajo el candado COMPARTIDO crm_flag_resolver_en_puertas (el cambio de
  -- bandera toma el exclusivo): esta llamada termina con la bandera que leyó, aunque espere por una fila.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);

  select pg_catalog.array_agg(destino.id order by destino.orden)
    into v_destinos_validos
  from (
    select u.id, u.orden
    from pg_catalog.unnest(p_analistas_destino) with ordinality as u(id, orden)
    join crm.equipo e on e.perfil_id = u.id
    join public.perfiles p on p.id = e.perfil_id
    where e.activo = true
      and p.activo = true
      and e.rol_crm = 'vendedor'
      and (
        v_rol = 'gerencia'
        or e.perfil_id in (
          select private.vendedor_ids_visibles(v_actor)
        )
      )
  ) destino;

  v_total_destinos := coalesce(pg_catalog.array_length(v_destinos_validos, 1), 0);  -- F2.b (b2): pg_catalog.coalesce no existe (bug desde 20/08)
  if v_total_destinos <> pg_catalog.array_length(p_analistas_destino, 1) then
    raise exception 'Uno de los asesores destino no está activo o no pertenece a tu equipo'
      using errcode = '22023';
  end if;

  -- F2.b [D-13]: candados de PERSONA antes de las filas (documento -> persona -> lead): documentos y personas de todos los
  -- leads del lote, en orden; luego las filas. Si tras tomarlas la persona de un lead no está entre las bloqueadas -> 40001.
  v_bloqueo := private.bloquear_personas_de_leads(
    (select pg_catalog.array_agg(la.lead_id) from crm.lead_asignaciones la where la.id = any(p_episodios)), null);
  -- Se bloquean los leads antes de modificar alguno. Si una carrera ya los
  -- reabrió, toda la operación falla y no deja un reparto parcial.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id,
      (l.no_contactar or (v_flag and coalesce(inv.no_contactar, false))) as no_contactar,  -- veto de la PERSONA
      l.telefono, l.dni, l.inversionista_id
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
    left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
    where la.id = any(p_episodios)
      and la.resultado = 'descartado'
      and la.resultado_en is not null
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and (
        v_rol = 'gerencia'
        or la.analista_id in (
          select private.vendedor_ids_visibles(v_actor)
        )
      )
    order by la.resultado_en, la.id
    for update of l
  loop
    v_candidatos := v_candidatos + 1;
    if v_fila.no_contactar then
      raise exception 'Uno de los leads tiene la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
    -- F2.b (b2): también por documento exacto (lead suelto de una persona vetada).
    if private.persona_vetada(v_fila.lead_id) then
      raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
    -- F2.b [D-13] (auditor M1 / Codex #6): con la identidad encendida, el JUICIO único de reapertura por lead; todo el lote
    -- falla, como con el veto. La persona debe ser una de las bloqueadas antes de las filas (si no, 40001).
    if v_flag then
      if not private.lead_dentro_de_bloqueo(v_fila.lead_id, v_bloqueo) then
        raise exception 'El documento o la persona de uno de los leads cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
      end if;
      v_veredicto := private.juicio_reapertura(v_fila.lead_id, v_fila.telefono, null);
      if v_veredicto->>'estado' = 'no_contactar' then
        raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
          using errcode = 'P0429';
      end if;
      if v_veredicto is not null then
        raise exception 'Uno de los leads pertenece a una persona que ya es cliente o ya tiene su lead y no puede reactivarse'
          using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_fila.lead_id)::text;
      end if;
    end if;
  end loop;

  v_total_episodios := pg_catalog.array_length(p_episodios, 1);
  if v_candidatos <> v_total_episodios then
    raise exception 'Uno de los descartes ya no está disponible para rescate'
      using errcode = 'P0002';
  end if;

  -- F2.b [D-13]: la reapertura pasa por la puerta (trigger «solo por RPC»).
  v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);
  -- Una segunda pasada usa los mismos locks. La vuelta redonda conserva el
  -- orden seleccionado y, si se pidió, salta al asesor que lo descartó.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
    where la.id = any(p_episodios)
      and la.resultado = 'descartado'
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
    order by la.resultado_en, la.id
  loop
    v_destino := null;
    for v_intento in 0..(v_total_destinos - 1) loop
      v_destino := v_destinos_validos[((v_orden + v_intento) % v_total_destinos) + 1];
      exit when not p_evitar_asesor_origen or v_destino is distinct from v_fila.asesor_origen_id;
    end loop;

    if v_destino is null
       or (p_evitar_asesor_origen and v_destino = v_fila.asesor_origen_id) then
      raise exception 'No hay otro asesor destino para uno de los descartes seleccionados'
        using errcode = '22023';
    end if;

    update crm.leads
       set etapa = 'nuevo',
           motivo_descarte = null,
           vendedor_id = v_destino,
           asignado_supervisor_id = null
     where id = v_fila.lead_id;
    -- F2.b [D-13] (auditor M1 / Codex #6): el lead reabierto queda ENLAZADO a su persona (como al nacer), ya bloqueada FOR SHARE.
    if v_flag then
      perform private.enlazar_lead_reabierto(v_fila.lead_id, private.lead_persona_reabrir(v_fila.lead_id));
    end if;

    v_orden := v_orden + 1;
  end loop;
  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);

  return pg_catalog.jsonb_build_object(
    'rescatados', v_candidatos,
    'asesores_destino', v_total_destinos
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.deshacer_descarte_implementacion(p_lead uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor   uuid := (select auth.uid());
  v_ventana interval := interval '24 hours';
  v_lead    crm.leads%rowtype;
  v_veredicto jsonb;
  v_bloqueo jsonb;
  v_previo_reab text;
  v_flag_d13 boolean;
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede deshacer un descarte'
      using errcode = '42501';
  end if;

  if p_lead is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;
  -- F2.b [D-5] (auditor v4 #1): la bandera se lee bajo el candado COMPARTIDO crm_flag_resolver_en_puertas (el cambio de
  -- bandera toma el exclusivo): esta llamada termina con la bandera que leyó, aunque espere por una fila.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag_d13 := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);

  -- F2.b [D-13]: candados de PERSONA antes de la fila (documento -> persona -> lead); inerte con la bandera apagada.
  v_bloqueo := private.bloquear_personas_de_leads(array[p_lead], null);
  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa = 'descartado'
    and l.descartado_por = v_actor
    and l.descartado_en > (statement_timestamp() - v_ventana)
  for update;
  if not found then
    raise exception 'Solo puedes deshacer tus propios descartes de las últimas 24 horas, y solo si el lead sigue sin dueño'
      using errcode = 'P0002';
  end if;
  -- F2.b (b2): gemela de rescatar_descartes: una persona vetada no se reabre.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (auditor M1 / Codex #6): gemela de rescatar_descartes: el JUICIO único de reapertura con la identidad encendida.
  if v_flag_d13 then
    if not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
      raise exception 'El documento o la persona de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    v_veredicto := private.juicio_reapertura(v_lead.id, v_lead.telefono, null);
    if v_veredicto->>'estado' = 'no_contactar' then
      raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»' using errcode = 'P0429';
    end if;
    if v_veredicto is not null then
      raise exception 'La persona ya es cliente o ya tiene su lead: no se puede reabrir'
        using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_lead.id)::text;
    end if;
  end if;

  v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);
  begin
    update crm.leads
       set etapa = 'nuevo', motivo_descarte = null
     where id = p_lead and activo = true and etapa = 'descartado'
       and vendedor_id is null and asignado_supervisor_id is null;
    if not found then
      raise exception 'El descarte ya no se puede deshacer (carrera)'
        using errcode = 'P0002';
    end if;
  exception
    when unique_violation then
      raise exception 'Ya existe otro lead vivo con ese mismo teléfono o documento: no se puede reabrir'
        using errcode = '22023';
  end;

  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);
  -- F2.b [D-13]: el lead reabierto queda ENLAZADO a su persona (como al nacer), ya bloqueada FOR SHARE.
  if v_flag_d13 and v_lead.inversionista_id is null then
    perform private.enlazar_lead_reabierto(p_lead, private.lead_persona_reabrir(p_lead));
  end if;
  select * into v_lead from crm.leads where id = p_lead;

  return jsonb_build_object(
    'lead_id', p_lead,
    'etapa', v_lead.etapa,
    'ciclo_actual', v_lead.ciclo_actual,
    'reabierto_por', v_actor,
    'reabierto_en', statement_timestamp());
end;
$function$;

CREATE OR REPLACE FUNCTION crm.retomar_conversion_gerencia_fn(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid()); v_inv uuid; v_r crm.conversion_reservas%rowtype; v_est jsonb; v_token text; v_clave text;
begin
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia retoma una conversión' using errcode = '42501';
  end if;
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then   -- F2.b [D-5]
    raise exception 'Retomar requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  select r.inversionista_id into v_inv from crm.conversion_reservas r where r.lead_id = p_lead_id;
  if v_inv is null then
    raise exception 'Este lead no tiene una reserva por persona' using errcode = 'P0002';
  end if;
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
  select * into v_r from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if v_r.efectos_iniciados_en is null then
    raise exception 'La reserva no está sellada: basta con volver a reservar' using errcode = 'P0409';
  end if;
  v_clave := 'auth_persona:' || v_inv::text;
  select i.resultado into v_est from crm.multiempresa_idempotencia i where i.clave = v_clave for update;
  if v_est is null or v_est->>'estado' = 'enlazado' then
    raise exception 'No hay una conversión a medias que retomar' using errcode = 'P0409';
  end if;
  if (v_est->>'lead_id')::uuid is distinct from p_lead_id or v_r.claim_id is distinct from (v_est->>'claim_id')::uuid then
    raise exception 'La reserva y el claim de esta persona no corresponden a este lead' using errcode = 'P0409';
  end if;
  -- Nunca expulsa a una ejecución viva: solo pasado el tope de la reserva o con el lease del claim vencido (Codex E2 #10).
  if v_est->>'lease_hasta' is null then
    raise exception 'El claim de esta conversión no tiene lease (anomalía de datos): revisar antes de retomar' using errcode = 'P0409';
  end if;
  -- F2.b [D-5] (Codex v5 #2): mismo criterio que abandonar. Retomar rota el token del claim: nunca expulsa a una ejecución
  -- viva. Exige el tope de la reserva Y el lease del claim vencidos (un reintento del dueño renueva el lease aunque el tope pase).
  if v_r.vence_absoluto_en > pg_catalog.now() or (v_est->>'lease_hasta')::timestamptz > pg_catalog.now() then
    raise exception 'La conversión sigue viva (reserva y claim vigentes): no hay nada que retomar todavía' using errcode = 'P0409';
  end if;
  v_token := pg_catalog.encode(extensions.gen_random_bytes(24), 'hex');
  v_est := v_est || pg_catalog.jsonb_build_object('token_hash', private.saga_token_hash(v_token), 'owner', v_uid,
    'lease_hasta', pg_catalog.now() + interval '10 minutes', 'actualizado_en', pg_catalog.now(), 'retomado_por_gerencia', true);
  update crm.multiempresa_idempotencia set resultado = v_est, version = version + 1 where clave = v_clave;
  update crm.conversion_reservas r
     set reservado_por = v_uid, reservado_en = pg_catalog.now(),
         expira_en = pg_catalog.now() + interval '5 minutes', vence_absoluto_en = pg_catalog.now() + interval '30 minutes'
   where r.lead_id = p_lead_id;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', v_inv,
    'claim_id', (v_est->>'claim_id')::uuid, 'token', v_token, 'estado', v_est->>'estado',
    'version', (select i.version from crm.multiempresa_idempotencia i where i.clave = v_clave),
    'auth_user_id', (v_est->>'auth_user_id')::uuid, 'perfil_id', (v_est->>'perfil_id')::uuid, 'reanudar', true);
end;
$function$;

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
  -- Orden de candados: persona → lead → reserva → claim (el de la conversión en cooperativa y del sellado).
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia abandona una conversión' using errcode = '42501';
  end if;
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Abandonar requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
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
  -- Orden de candados (Codex v5 #3): persona → lead → reserva → claim, el de la conversión en cooperativa y del sellado
  -- (lead antes que reserva); las revalidaciones van después de cada candado.
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
  select * into v_lead from crm.leads l where l.id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
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
  if v_lead.etapa = 'convertido' then
    raise exception 'El lead ya está convertido: la conversión se consumó, no se abandona' using errcode = 'P0409';
  end if;
  v_clave := 'auth_persona:' || v_inv::text;
  select i.resultado into v_est from crm.multiempresa_idempotencia i where i.clave = v_clave for update;
  if v_est is null and v_r.claim_id is not null then
    raise exception 'La reserva apunta a un claim que ya no existe (anomalía de datos): revisar antes de abandonar' using errcode = 'P0409';
  end if;
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
  if v_est is not null and v_est->>'lease_hasta' is null then
    raise exception 'El claim de esta conversión no tiene lease (anomalía de datos): revisar antes de abandonar' using errcode = 'P0409';
  end if;
  if v_r.vence_absoluto_en > pg_catalog.now()
     or (v_est is not null and (v_est->>'lease_hasta')::timestamptz > pg_catalog.now()) then
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
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reservar_conversion_lead(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '55bf3300a940729b08f36b1db93075b6') then
    raise exception 'POSTFLIGHT D-5: crm.reservar_conversion_lead(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'b8f9cbc6b5e5ae697c0e9cbad32abbc8') then
    raise exception 'POSTFLIGHT D-5: crm.marcar_efectos_conversion(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '801d4262f24c43e9f5ca41a9ecb36e76') then
    raise exception 'POSTFLIGHT D-5: crm.marcar_efectos_conversion(uuid,uuid,text) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.abandonar_conversion_gerencia_fn(uuid,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '9b225b5aa9a10ddd4ae276fa56db3982') then
    raise exception 'POSTFLIGHT D-5: crm.abandonar_conversion_gerencia_fn no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid where t.tgrelid = 'crm.multiempresa_flags'::regclass and t.tgname = 'trg_multiempresa_flags_00_serializa_puertas' and t.tgenabled = 'O'
                   and pg_get_triggerdef(t.oid) = 'CREATE TRIGGER trg_multiempresa_flags_00_serializa_puertas BEFORE UPDATE OF activo ON crm.multiempresa_flags FOR EACH ROW EXECUTE FUNCTION private.trg_multiempresa_flags_serializa_puertas()'
                   and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'e84b1a60804bd0d4f6b6b79aeb2e9016')
     or has_function_privilege('authenticated', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE') or has_function_privilege('anon', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE') or has_function_privilege('service_role', 'private.trg_multiempresa_flags_serializa_puertas()', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'private.trg_multiempresa_flags_serializa_puertas()'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-5: el trigger que serializa el cambio de bandera (crm.multiempresa_flags) falta o no es exactamente BEFORE UPDATE OF activo FOR EACH ROW con la función de gen-d5.py (dueño postgres, sin EXECUTE para la API)';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.fijar_dni_lead_fn(uuid,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '3b92916944a76fb7bcbc3bce603e4788') then
    raise exception 'POSTFLIGHT D-5: crm.fijar_dni_lead_fn(uuid,text) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.tomar_lead_libre(text,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'f755d63f59dfc0e8959fefb83c7b9f9a') then
    raise exception 'POSTFLIGHT D-5: crm.tomar_lead_libre(text,text) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.rescatar_descartes(uuid[],uuid[],boolean)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '5f4f5ca115f535f6ab8a1209dda19a0f') then
    raise exception 'POSTFLIGHT D-5: crm.rescatar_descartes(uuid[],uuid[],boolean) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.deshacer_descarte_implementacion(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '241c65a8da53c98ec12027692d7724a4') then
    raise exception 'POSTFLIGHT D-5: private.deshacer_descarte_implementacion(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.retomar_conversion_gerencia_fn(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'cff6d812b0385a52d86700507bdb33c2') then
    raise exception 'POSTFLIGHT D-5: crm.retomar_conversion_gerencia_fn(uuid) no quedó como la genera gen-d5.py';
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

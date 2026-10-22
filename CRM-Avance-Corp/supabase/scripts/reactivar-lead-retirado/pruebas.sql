-- ORÁCULO de «Registrar a una persona con lead retirado reactiva su ficha» — se ejecuta en el LABORATORIO (banco Docker
-- local), NUNCA contra producción, y no escribe nada.
--
-- La regla (decisiones D-11/Q1, D-15 y D-17 de Miguel; plan AVANCE-BACKEND-0710-P1, bloque 2.4): si alguien registra a mano a
-- una persona cuyo lead fue RETIRADO (`crm.leads.activo = false`, no convertido, sin enlace a persona) y no hay ningún lead
-- ACTIVO con su teléfono o DNI, `crm.crear_lead_si_disponible` reactiva ESA ficha a nombre del destino del alta (vendedor que
-- se autoasigna, bandeja del supervisor o destino elegido por Gerencia) en vez de crear un segundo lead, y responde
-- `{estado:'reutilizado', lead_id}`. También cuando el verificador dice «enfriamiento» y su único causante es un retirado
-- (D-15: sin esperar la espera ni la carencia de 24 h). Se conservan los datos de la ficha; lo tecleado va a la actividad de
-- rastro (`evento = 'reactivacion_alta'`, con `id = p_id` del alta: un reintento con el mismo id no repite). Si estaba
-- `descartado` pasa a `nuevo` con ciclo +1; en otra etapa queda igual. Un lead activo del mismo contacto, un retirado enlazado
-- a persona, un convertido y «no contactar» siguen EXACTAMENTE como hoy. Nadie gana permisos.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la migración real (a la que quita su
-- `begin;`/`commit;`) dentro de una única transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y
-- entonces TIENE que salir ROJO porque el alta crea un SEGUNDO lead de la misma persona (caso 1), no por un error de montaje.
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT (las puertas son `security definer` y
-- deciden por `auth.uid()`), fijada en las DOS formas (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de rol
-- con `set role`: llamar bajo `set role` a una función sin EXECUTE tumba el Postgres del banco, así que los permisos se leen
-- del catálogo (sección 10) y nunca se prueban llamando. Los fixtures nacen por la PUERTA REAL del alta (como VEND1) y se
-- retiran con un UPDATE `activo = false` con la sesión de Gerencia (así se retira hoy: por API, sin pantalla). Algunos fixtures
-- («retirado junto a un lead activo del mismo contacto», imposible de fabricar por la puerta una vez instalada la regla;
-- «convertido retirado sin persona»; «retirado de base cargada con capital vacío») se siembran con los triggers apagados, como
-- los contratos históricos del ensayo 2.3.
--
-- RONDA 2 (revisión de Codex y del auditor de permisos, `fase-2/bloque-2.4/revision/CONCILIACION.md`; D-21 de Miguel): además,
-- C-1 un lead ACTIVO (o un veto, o una identidad) que coincide con el teléfono o el DNI que CONSERVA la ficha retirada —aunque
-- no coincidan con lo tecleado— bloquea con el veredicto del verificador para ese dato (nunca se llega al INSERT); C-2/A-1 la
-- huella de idempotencia lleva el teléfono normalizado y el tipo de documento, y NO el DNI, el género ni la fecha de nacimiento;
-- C-3 el replay repite el `aviso`; C-4 el rastro lleva `etapa_anterior` y `activo_anterior=false`; C-5 solo los dos índices de
-- contacto vivo se tratan como carrera (otro 23505 se propaga); A-2 un retirado de base cargada con capital vacío se reactiva con
-- el capital tecleado; A-4/D-21 un retirado ENLAZADO a persona bloquea («ya_es_cliente») también cuando solo se tecleó el
-- teléfono; A-5 el núcleo exige `p_actor = auth.uid()`; A-6 el reintento solo confirma una ficha que sigue activa; A-7 el rastro
-- guarda solo capital, moneda, origen y tipo de documento tecleados (ni nombre, ni correo, ni teléfono alternativo); A-8 el
-- rastro dice `otro_retirado=true` sin el id ajeno. Casos nuevos: Gerencia sin destino, `reunion_agendada`, veto asociado solo
-- al DNI conservado.
--
-- RONDA 3 (validación de Codex y del auditor a la ronda 2, `fase-2/bloque-2.4/revision/CONCILIACION-R2.md`): R2-1 el reintento
-- con el mismo `p_id` tras un segundo retiro reactiva LA FICHA DEL PRIMER RASTRO (fijada por `v_act.lead_id`), nunca otra
-- retirada del mismo contacto (dos retirados del mismo teléfono: los índices únicos son de leads vivos); R2-2 solo el CHECK
-- `leads_monto_estimado_valido` se captura como veredicto fresco: cualquier otro 23514 del UPDATE se propaga (fixture: un CHECK
-- ajeno sembrado al empezar el oráculo); AR2-1 otro retirado ENLAZADO a persona que casa solo por el DNI tecleado bloquea con el
-- juicio de identidad (`ya_es_cliente`) también con la bandera `resolver_en_puertas` APAGADA (se apaga y se vuelve a encender
-- dentro de esta transacción); bordes B1 (convertido ACTIVO que casa solo por lo conservado ⇒ `ya_es_cliente`) y B2 (descartado
-- ACTIVO de 0 días dentro de sus 24 h que casa solo por lo conservado ⇒ `tomado`/`en_bolsa`).
--
-- RONDA 4 (validación de Codex a la ronda 3, `fase-2/bloque-2.4/revision/CONCILIACION-R3.md`): R3-1 un reintento con rastro
-- previo (actividad con `id = p_id`, mismo actor y huella) NUNCA llega al INSERT: si la ficha del primer rastro ya no se puede
-- reactivar, el núcleo responde un veredicto bloqueante y nunca nulo: (a) retirada y CONVERTIDA con el verificador en «libre» ⇒
-- `ya_es_cliente` (formato del verificador, a nombre del tenedor de la ficha), nada escrito, un solo lead; (b) ficha INEXISTENTE
-- (borrada dentro del rollback con los disparadores apagados) ⇒ 22023 «el alta original ya no existe»; (c) VETADA ⇒ `no_contactar`.
--
-- RONDA 5 (validación de Codex a la ronda 4, `fase-2/bloque-2.4/revision/CONCILIACION-R4.md`): R4-1 el paso 3a del núcleo (otro lead
-- ACTIVO coincide con el teléfono o el DNI TECLEADOS) nunca devuelve nulo en un reintento con rastro previo: si el verificador no
-- calificó a ese lead activo (un DESCARTADO ACTIVO con motivo de 0 días dentro de sus 24 h ⇒ «libre»), el núcleo responde el veredicto
-- que el verificador daría para él (`tomado` con su tenedor / `en_bolsa`) o 22023; nada escrito, ni una ficha más con ese contacto.

set local statement_timeout = '300s';

-- Identidad de la sesión, en las DOS formas de los claims.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Acumulador del informe: un caso que pasa suma una línea «ok»; uno que falla, un fallo con su texto.
create function pg_temp.reg(p_caso text, p_txt text) returns void language plpgsql as $f$
begin
  if p_txt = '' then
    perform set_config('ensayo.oks', coalesce(current_setting('ensayo.oks', true), '') || 'ok ' || p_caso || E'\n', true);
  else
    perform set_config('ensayo.fallos',
      (coalesce(nullif(current_setting('ensayo.fallos', true), ''), '0')::integer + 1)::text, true);
    perform set_config('ensayo.informe', coalesce(current_setting('ensayo.informe', true), '') || p_txt, true);
  end if;
end;
$f$;

create function pg_temp.medida(p_txt text) returns void language sql as $$
  select set_config('ensayo.medidas', coalesce(current_setting('ensayo.medidas', true), '') || 'medida ' || p_txt || E'\n', true);
$$;

-- Contactos del ensayo: un bloque propio (+51 924 00xxxx / 7524xxxx) que el montaje exige LIBRE.
create function pg_temp.tel(n integer) returns text language sql immutable as $$ select '92400' || lpad(n::text, 4, '0') $$;
create function pg_temp.teln(n integer) returns text language sql immutable as $$ select '+51' || pg_temp.tel(n) $$;
create function pg_temp.dni(n integer) returns text language sql immutable as $$ select '7524' || lpad(n::text, 4, '0') $$;

create temp table ens_actores (nombre text primary key, id uuid not null);

create function pg_temp.actor(p_nombre text) returns uuid language sql as $$
  select a.id from ens_actores a where a.nombre = p_nombre
$$;

-- Foto COMPLETA de una ficha (para «sigue intacta») y foto de los datos que la reactivación debe conservar.
create function pg_temp.ficha(p_id uuid) returns jsonb language sql as $$
  select to_jsonb(l) from crm.leads l where l.id = p_id
$$;

-- Alta por la puerta real, como el actor. 'ok|<respuesta>' o 'SQLSTATE|mensaje'. El bloque con EXCEPTION es una
-- subtransacción: un rechazo deshace TODO lo que la llamada había hecho.
create function pg_temp.alta(p_actor uuid, p_id uuid, p_nombre text, p_tel text, p_dni text,
                             p_etapa text default 'nuevo', p_vendedor uuid default null, p_nota text default null,
                             p_correo text default null, p_monto numeric default 5000)
returns text language plpgsql as $f$
declare v_r jsonb;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.crear_lead_si_disponible(
    p_nombre_completo => p_nombre, p_telefono => p_tel, p_origen => 'formulario', p_monto_estimado => p_monto,
    p_moneda => 'PEN', p_id => p_id, p_correo => p_correo, p_dni => p_dni, p_etapa => p_etapa,
    p_vendedor_id => p_vendedor, p_nota => p_nota);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Alta por la puerta del documento (CE/pasaporte/DNI), como el actor.
create function pg_temp.alta_doc(p_actor uuid, p_datos jsonb, p_tipo text, p_documento text)
returns text language plpgsql as $f$
declare v_r jsonb;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.crear_lead_documento_fn(p_datos, p_tipo, p_documento);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- El núcleo llamado DIRECTAMENTE (el banco corre como postgres, su único ejecutor) con una sesión y un p_actor dados y un
-- veredicto bloqueante: sirve para medir el gate interno (A-5) sin que nada más pueda actuar. 'ok|<respuesta o null>' o 'SQLSTATE|mensaje'.
create function pg_temp.nucleo_directo(p_sesion uuid, p_actor uuid, p_tel text, p_dni text) returns text language plpgsql as $f$
declare v_r jsonb;
begin
  perform pg_temp.sesion(p_sesion);
  v_r := private.alta_reactivar_retirado(gen_random_uuid(), p_actor, p_tel, p_dni, p_actor, null,
                                         '{"estado":"tomado"}'::jsonb, '{}'::jsonb);
  perform pg_temp.sesion(null);
  return 'ok|' || coalesce(v_r::text, 'null');
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Retirar como lo hace Gerencia/supervisión hoy: UPDATE activo=false por API, con su sesión. '1' si retiró una fila.
create function pg_temp.retirar(p_actor uuid, p_id uuid) returns text language plpgsql as $f$
declare v_n integer;
begin
  perform pg_temp.sesion(p_actor);
  update crm.leads set activo = false where id = p_id and activo;
  get diagnostics v_n = row_count;
  perform pg_temp.sesion(null);
  return v_n::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Descartar como lo hacía la pantalla: UPDATE de etapa y motivo con la sesión del dueño (los triggers sellan descartado_en).
create function pg_temp.descartar(p_actor uuid, p_id uuid, p_motivo text) returns text language plpgsql as $f$
declare v_n integer;
begin
  perform pg_temp.sesion(p_actor);
  update crm.leads set etapa = 'descartado', motivo_descarte = p_motivo where id = p_id and activo and etapa <> 'descartado';
  get diagnostics v_n = row_count;
  perform pg_temp.sesion(null);
  return v_n::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Fixture: una ficha nacida por la puerta real (VEND1) y luego RETIRADA por Gerencia. Aborta el ensayo si el montaje falla.
create function pg_temp.retirado(p_n integer, p_etapa text, p_con_dni boolean, p_nombre text,
                                 p_correo text default null, p_monto numeric default 5000, p_motivo_descarte text default null)
returns uuid language plpgsql as $f$
declare v_res text; v_id uuid := gen_random_uuid(); v_r text;
begin
  v_res := pg_temp.alta(pg_temp.actor('VEND1'), v_id, p_nombre, pg_temp.tel(p_n),
                        case when p_con_dni then pg_temp.dni(p_n) end, p_etapa, null, null, p_correo, p_monto);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el fixture % por la puerta real (%)', p_n, v_res;
  end if;
  if p_motivo_descarte is not null then
    v_r := pg_temp.descartar(pg_temp.actor('VEND1'), v_id, p_motivo_descarte);
    if v_r <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo descartar el fixture % (%)', p_n, v_r; end if;
  end if;
  v_r := pg_temp.retirar(pg_temp.actor('GERENCIA'), v_id);
  if v_r <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar el fixture % (%)', p_n, v_r; end if;
  if (select l.activo from crm.leads l where l.id = v_id) then
    raise exception 'ENSAYO ABORTADO: el fixture % no quedó retirado', p_n;
  end if;
  return v_id;
end;
$f$;

-- Un retirado sembrado SIN triggers (ya existe un lead activo del mismo contacto: la puerta real ya no permite montarlo).
-- Con `p_dni` conserva un DNI; con `p_origen = 'base_cargada'` nace como lo deja la carga de bases (descartado con motivo
-- `base_cargada`, SIN capital, sin dueño) y luego retirado.
create function pg_temp.retirado_sintetico(p_n integer, p_nombre text, p_dni text default null, p_origen text default 'formulario')
returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid(); v_base boolean := p_origen = 'base_cargada';
begin
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, motivo_descarte, descartado_en, descartado_por,
                         monto_estimado, moneda, vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual,
                         ciclo_actual, creado_en, actualizado_en, sla_global_iniciado_en)
  values (v_id, p_nombre, pg_temp.teln(p_n), p_dni, p_origen,
          case when v_base then 'descartado' else 'contactado' end,
          case when v_base then 'base_cargada' end,
          case when v_base then now() - interval '1 hour' end,
          case when v_base then pg_temp.actor('GERENCIA') end,
          case when v_base then null else 1000 end, 'PEN',
          case when v_base then null else pg_temp.actor('VEND1') end,
          null, false, case when v_base then pg_temp.actor('GERENCIA') else pg_temp.actor('VEND1') end, not v_base, 1,
          now() - interval '30 days', now() - interval '10 days', now() - interval '30 days');
  -- Su ciclo SLA, como lo habría dejado el alta real: sin él, una reactivación (la del mutante que debe morir) chocaría con
  -- la FK de lead_sla_etapas en vez de contarse como «reutilizado».
  insert into crm.lead_sla_ciclos (lead_id, ciclo_n, politica_id, iniciado_en, primera_gestion_limite_en, primer_contacto_limite_en)
  select v_id, 1, p.id, now() - interval '30 days',
         now() - interval '30 days' + p.primera_gestion_minutos * interval '1 minute',
         now() - interval '30 days' + p.primer_contacto_minutos * interval '1 minute'
  from crm.sla_politicas p
  where p.id = coalesce(private.sla_politica_vigente(now() - interval '30 days'), private.sla_politica_vigente(now()));
  set local session_replication_role = origin;
  if not exists (select 1 from crm.lead_sla_ciclos c where c.lead_id = v_id) then
    raise exception 'ENSAYO ABORTADO: el retirado sintético % no pudo recibir su ciclo SLA (sin política vigente)', p_n;
  end if;
  return v_id;
end;
$f$;

-- Un DESCARTADO ACTIVO con motivo de 0 días (`pide_credito`) dentro de sus 24 h, a nombre de VEND1, sembrado SIN triggers (ronda 5,
-- R4-1): con la regla instalada la puerta real REACTIVARÍA la ficha retirada del mismo contacto en vez de crear este lead, y los
-- índices vivos no cubren descartados. En esa ventana el verificador dice «libre» (la carencia de 24 h es solo para tomar).
create function pg_temp.descartado_activo_sintetico(p_n integer, p_nombre text, p_dni text default null)
returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid();
begin
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, motivo_descarte, descartado_en, descartado_por,
                         monto_estimado, moneda, vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual,
                         ciclo_actual, creado_en, actualizado_en, sla_global_iniciado_en)
  values (v_id, p_nombre, pg_temp.teln(p_n), p_dni, 'formulario', 'descartado', 'pide_credito', clock_timestamp(), pg_temp.actor('VEND1'),
          1000, 'PEN', pg_temp.actor('VEND1'), null, true, pg_temp.actor('VEND1'), true, 1,
          now() - interval '2 days', clock_timestamp(), now() - interval '2 days');
  insert into crm.lead_sla_ciclos (lead_id, ciclo_n, politica_id, iniciado_en, primera_gestion_limite_en, primer_contacto_limite_en)
  select v_id, 1, p.id, now() - interval '2 days',
         now() - interval '2 days' + p.primera_gestion_minutos * interval '1 minute',
         now() - interval '2 days' + p.primer_contacto_minutos * interval '1 minute'
  from crm.sla_politicas p
  where p.id = coalesce(private.sla_politica_vigente(now() - interval '2 days'), private.sla_politica_vigente(now()));
  set local session_replication_role = origin;
  if not exists (select 1 from crm.lead_sla_ciclos c where c.lead_id = v_id) then
    raise exception 'ENSAYO ABORTADO: el descartado activo sintético % no pudo recibir su ciclo SLA (sin política vigente)', p_n;
  end if;
  if (select l.activo and l.etapa = 'descartado' and l.descartado_en is not null from crm.leads l where l.id = v_id) is distinct from true then
    raise exception 'ENSAYO ABORTADO: el descartado activo sintético % no quedó activo, descartado y sellado', p_n;
  end if;
  return v_id;
end;
$f$;

-- Lo que debe cumplir una reactivación: respuesta, misma ficha, dueño, etapa, ciclo, un solo lead por contacto, rastro y
-- episodio. Devuelve '' o las líneas FALLO.
create function pg_temp.exigir_reactivado(p_caso text, p_res text, p_lead uuid, p_pid uuid, p_actor uuid,
                                          p_dueno uuid, p_sup uuid, p_etapa text, p_ciclo integer,
                                          p_prop_anterior uuid, p_etapa_anterior text, p_teln text, p_dni text)
returns text language plpgsql as $f$
declare
  v_r jsonb; v_l crm.leads%rowtype; v_a crm.actividades%rowtype; v_ep crm.lead_asignaciones%rowtype;
  v_m text[] := '{}'; v_n integer;
begin
  if p_res not like 'ok|%' then
    return format(E'FALLO %s: el alta falló en vez de reactivar la ficha (%s)\n', p_caso, p_res);
  end if;
  v_r := substr(p_res, 4)::jsonb;
  if v_r ->> 'estado' is distinct from 'reutilizado' then
    return format(E'FALLO %s: el alta no reutilizó la ficha retirada: estado=%s%s; %s lead(s) con el teléfono %s%s\n',
      p_caso, v_r ->> 'estado',
      case when v_r ->> 'estado' = 'creado' then ' → creó un SEGUNDO lead de la misma persona' else '' end,
      (select count(*) from crm.leads l where l.telefono = p_teln), p_teln,
      case when p_dni is not null then format(' y %s con el DNI', (select count(*) from crm.leads l where l.dni = p_dni)) else '' end);
  end if;
  if (v_r ->> 'lead_id')::uuid is distinct from p_lead then
    v_m := v_m || format('lead_id devuelto %s ≠ ficha retirada %s', v_r ->> 'lead_id', p_lead);
  end if;
  select * into v_l from crm.leads l where l.id = p_lead;
  if not v_l.activo then v_m := array_append(v_m, 'la ficha sigue activo=false'); end if;
  if v_l.vendedor_id is distinct from p_dueno then v_m := v_m || format('dueño %s, se esperaba %s', v_l.vendedor_id, p_dueno); end if;
  if v_l.asignado_supervisor_id is distinct from p_sup then v_m := v_m || format('bandeja %s, se esperaba %s', v_l.asignado_supervisor_id, p_sup); end if;
  if v_l.etapa is distinct from p_etapa then v_m := v_m || format('etapa %s, se esperaba %s', v_l.etapa, p_etapa); end if;
  if v_l.ciclo_actual is distinct from p_ciclo then v_m := v_m || format('ciclo %s, se esperaba %s', v_l.ciclo_actual, p_ciclo); end if;
  if v_l.etapa <> 'descartado' and (v_l.motivo_descarte is not null or v_l.descartado_en is not null or v_l.descartado_por is not null) then
    v_m := array_append(v_m, 'conserva motivo o sello de descarte fuera de la etapa descartado');
  end if;
  if (select count(*) from crm.leads l where l.telefono = p_teln) <> 1 then
    v_m := v_m || format('%s leads con el teléfono %s (debe ser 1)', (select count(*) from crm.leads l where l.telefono = p_teln), p_teln);
  end if;
  if p_dni is not null and (select count(*) from crm.leads l where l.dni = p_dni) <> 1 then
    v_m := v_m || format('%s leads con el DNI (debe ser 1)', (select count(*) from crm.leads l where l.dni = p_dni));
  end if;
  select * into v_a from crm.actividades a where a.id = p_pid;
  if not found then
    v_m := array_append(v_m, 'sin actividad de rastro con id = p_id');
  else
    if v_a.lead_id is distinct from p_lead or v_a.tipo <> 'nota' or v_a.metadata ->> 'evento' is distinct from 'reactivacion_alta' then
      v_m := v_m || format('la actividad con id = p_id no es el rastro esperado (lead %s, tipo %s, evento %s)', v_a.lead_id, v_a.tipo, v_a.metadata ->> 'evento');
    end if;
    if v_a.creado_por is distinct from p_actor then v_m := v_m || format('rastro firmado por %s, no por quien registró', v_a.creado_por); end if;
    if (v_a.metadata ->> 'propietario_anterior')::uuid is distinct from p_prop_anterior then
      v_m := v_m || format('propietario_anterior %s, se esperaba %s', v_a.metadata ->> 'propietario_anterior', p_prop_anterior);
    end if;
    if v_a.metadata ->> 'etapa_anterior' is distinct from p_etapa_anterior then
      v_m := v_m || format('etapa_anterior %s, se esperaba %s', v_a.metadata ->> 'etapa_anterior', p_etapa_anterior);
    end if;
    if (v_a.metadata ->> 'ciclo')::integer is distinct from p_ciclo then
      v_m := v_m || format('ciclo del rastro %s, se esperaba %s', v_a.metadata ->> 'ciclo', p_ciclo);
    end if;
    -- C-4: rastro inequívoco de la reactivación (el ledger puede abrir «reabierto» si venía de descartado).
    if v_a.metadata ->> 'activo_anterior' is distinct from 'false' then
      v_m := v_m || format('el rastro no dice activo_anterior=false (lleva %s)', coalesce(v_a.metadata ->> 'activo_anterior', 'nada'));
    end if;
    -- A-7: lo tecleado se reduce a capital, moneda, origen y tipo de documento (nada de nombre, correo, teléfono alternativo,
    -- documento, género ni fecha de nacimiento). A-8: el otro retirado se anota como booleano, sin su id.
    if v_a.metadata -> 'tecleado' is null or jsonb_typeof(v_a.metadata -> 'tecleado') <> 'object' then
      v_m := array_append(v_m, 'el rastro no lleva el objeto tecleado');
    elsif exists (select 1 from jsonb_object_keys(v_a.metadata -> 'tecleado') k where k not in ('monto_estimado', 'moneda', 'origen', 'tipo_documento')) then
      v_m := v_m || format('el rastro guarda más que capital, moneda, origen y tipo de documento: %s', (select string_agg(k, ',') from jsonb_object_keys(v_a.metadata -> 'tecleado') k));
    end if;
    if not (v_a.metadata ? 'otro_retirado') or jsonb_typeof(v_a.metadata -> 'otro_retirado') <> 'boolean' or v_a.metadata ? 'otro_retirado_dni' then
      v_m := array_append(v_m, 'el rastro no lleva otro_retirado como booleano (o lleva el id ajeno otro_retirado_dni)');
    end if;
  end if;
  select count(*) into v_n from crm.actividades a where a.lead_id = p_lead and a.metadata ->> 'evento' = 'reactivacion_alta';
  if v_n <> 1 then v_m := v_m || format('%s actividades de rastro (debe ser 1)', v_n); end if;
  if p_dueno is not null then
    select * into v_ep from crm.lead_asignaciones la where la.lead_id = p_lead and la.finalizado_en is null;
    if not found then
      v_m := array_append(v_m, 'sin episodio abierto en el ledger de asignaciones');
    elsif v_ep.analista_id is distinct from p_dueno then
      v_m := v_m || format('episodio abierto para %s, no para el dueño nuevo', v_ep.analista_id);
    elsif v_ep.motivo_apertura not in ('reactivado', 'reabierto') then
      v_m := v_m || format('episodio abierto con motivo %s', v_ep.motivo_apertura);
    end if;
  elsif exists (select 1 from crm.lead_asignaciones la where la.lead_id = p_lead and la.finalizado_en is null) then
    v_m := array_append(v_m, 'episodio abierto sin analista (bandeja o cola)');
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

-- Lo que debe cumplir un caso que NO cambia: la respuesta de hoy (ok:<estado> | err:<sqlstate> | nulo = «cualquiera menos
-- reutilizado») y la ficha retirada INTACTA byte a byte.
create function pg_temp.exigir_intacto(p_caso text, p_res text, p_lead uuid, p_ficha_antes jsonb, p_esperado text)
returns text language plpgsql as $f$
declare v_m text[] := '{}'; v_estado text;
begin
  v_estado := case when p_res like 'ok|%' then substr(p_res, 4)::jsonb ->> 'estado' end;
  if p_esperado like 'err:%' then
    if p_res like 'ok|%' then
      v_m := v_m || format('debía rechazar con %s y devolvió estado=%s', substr(p_esperado, 5), v_estado);
    elsif split_part(p_res, '|', 1) <> substr(p_esperado, 5) then
      v_m := v_m || format('rechazó con otro error: %s', p_res);
    end if;
  elsif p_esperado like 'ok:%' then
    if p_res not like 'ok|%' then
      v_m := v_m || format('falló: %s', p_res);
    elsif v_estado is distinct from substr(p_esperado, 4) then
      v_m := v_m || format('estado %s, se esperaba %s (el veredicto de hoy)', v_estado, substr(p_esperado, 4));
    end if;
  elsif v_estado = 'reutilizado' then
    v_m := array_append(v_m, 'reactivó la ficha retirada y no debía');
  end if;
  if pg_temp.ficha(p_lead) is distinct from p_ficha_antes then
    v_m := v_m || format('la ficha retirada cambió: activo %s→%s, etapa %s→%s, dueño %s→%s', p_ficha_antes ->> 'activo',
      pg_temp.ficha(p_lead) ->> 'activo', p_ficha_antes ->> 'etapa', pg_temp.ficha(p_lead) ->> 'etapa',
      p_ficha_antes ->> 'vendedor_id', pg_temp.ficha(p_lead) ->> 'vendedor_id');
  end if;
  if cardinality(v_m) = 0 then return ''; end if;
  return format(E'FALLO %s: %s\n', p_caso, array_to_string(v_m, '; '));
end;
$f$;

insert into ens_actores (nombre, id)
select n.nombre, p.id
from (values ('VEND1'), ('VEND2'), ('VEND3'), ('SUP1'), ('SUP2'), ('GERENCIA'), ('COORD'), ('INACTIVO'), ('ADMIN')) n(nombre)
join public.perfiles p on p.nombre_completo = 'PASO08 ' || n.nombre;

do $ensayo$
declare
  v_vend1 uuid; v_vend2 uuid; v_vend3 uuid; v_sup1 uuid; v_ger uuid; v_coord uuid; v_inactivo uuid; v_admin uuid;
  v_l1 uuid; v_l2 uuid; v_l3 uuid; v_b4 uuid; v_a4 uuid; v_b5 uuid; v_a5 uuid; v_l6 uuid; v_p6 uuid; v_l7 uuid; v_l8 uuid;
  v_l10 uuid; v_l11 uuid; v_a12 uuid; v_b13 uuid; v_l15 uuid; v_l16 uuid; v_l17 uuid;
  v_pid uuid; v_pid1 uuid; v_res text; v_r jsonb; v_a crm.actividades%rowtype; v_l crm.leads%rowtype;
  v_ficha jsonb; v_ficha2 jsonb; v_txt text; v_n integer; v_n2 integer; v_cnt_inv bigint; v_cnt_idf bigint;
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_alta regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  v_tecleado jsonb; v_ahora timestamptz; v_sup2 uuid; v_l19a uuid; v_b19 uuid; v_pid10 uuid;
  v_a20 uuid; v_b20 uuid; v_a22 uuid; v_b22 uuid; v_w24 uuid; v_b24 uuid; v_l26 uuid; v_l27 uuid; v_l28 uuid; v_l29 uuid;
  v_l30 uuid; v_pid12 uuid; v_l31 uuid; v_b32 uuid;
  v_helper regprocedure := to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)');
  -- Ronda 3.
  v_l33 uuid; v_pid33 uuid; v_b33 uuid; v_l34 uuid; v_p35 uuid; v_r35 uuid; v_r36 uuid; v_a37 uuid; v_b38 uuid; v_a39 uuid;
  v_b40 uuid; v_esperado text;
  -- Ronda 4.
  v_l41 uuid; v_pid41 uuid; v_l42 uuid; v_pid42 uuid; v_l43 uuid; v_pid43 uuid; v_tenedor text; v_r41 boolean; v_r42 boolean;
  -- Ronda 5.
  v_l44 uuid; v_pid44 uuid; v_a44 uuid; v_r44 boolean;
  -- Bloque 2.7, ronda 2 (D-22): el caso 3d con y sin la regla del 2.7.
  v_27 boolean; v_l45 uuid; v_pid45 uuid; v_r45 boolean; v_ret text; v_modo text;
begin
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.informe', '', true);
  perform set_config('ensayo.medidas', '', true);

  -- ── Actores reales del banco (OBLIGATORIOS: sin ellos un caso se saltaría en silencio) ──────────────────────────
  v_vend1 := pg_temp.actor('VEND1'); v_vend2 := pg_temp.actor('VEND2'); v_vend3 := pg_temp.actor('VEND3');
  v_sup1 := pg_temp.actor('SUP1'); v_ger := pg_temp.actor('GERENCIA'); v_coord := pg_temp.actor('COORD');
  v_inactivo := pg_temp.actor('INACTIVO'); v_admin := pg_temp.actor('ADMIN'); v_sup2 := pg_temp.actor('SUP2');
  if v_vend1 is null or v_vend2 is null or v_vend3 is null or v_sup1 is null or v_sup2 is null or v_ger is null or v_coord is null
     or v_inactivo is null or v_admin is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (vend1=%, vend2=%, vend3=%, sup1=%, sup2=%, gerencia=%, coord=%, inactivo=%, admin=%)',
      v_vend1, v_vend2, v_vend3, v_sup1, v_sup2, v_ger, v_coord, v_inactivo, v_admin;
  end if;
  if private.rol_crm(v_vend1) is distinct from 'vendedor' or private.rol_crm(v_vend2) is distinct from 'vendedor'
     or private.rol_crm(v_vend3) is distinct from 'vendedor' or private.rol_crm(v_sup1) is distinct from 'supervisor'
     or private.rol_crm(v_sup2) is distinct from 'supervisor'
     or private.rol_crm(v_ger) is distinct from 'gerencia' or private.rol_crm(v_coord) is distinct from 'coordinador'
     or private.rol_crm(v_inactivo) is not null or private.rol_crm(v_admin) is not null
     or (select e.supervisor_id from crm.equipo e where e.perfil_id = v_vend2) is distinct from v_sup1 then
    raise exception 'ENSAYO ABORTADO: un actor del banco no tiene el rol esperado (vend1/vend2/vend3 vendedor, vend2 bajo sup1; sup1 y sup2 supervisores; gerencia; coord coordinador; inactivo y admin sin rol CRM)';
  end if;
  -- La identidad unificada tiene que estar encendida (la puerta del documento la exige y la rama juzga a la persona con ella).
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'ENSAYO ABORTADO: la bandera resolver_en_puertas está apagada en este laboratorio';
  end if;
  -- El bloque de contactos del ensayo tiene que estar libre.
  if exists (select 1 from crm.leads l where l.telefono like '+5192400%' or l.dni like '7524%')
     or exists (select 1 from public.perfiles p where p.telefono like '%92400%' or p.dni like '7524%') then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene contactos del bloque +51 924 00xxxx / 7524xxxx';
  end if;
  -- Fixture R2-2 (ronda 3): un CHECK AJENO a leads_monto_estimado_valido sobre crm.leads, sembrado ANTES de cualquier escritura en
  -- la tabla (un ALTER TABLE a mitad del oráculo chocaría con los eventos diferidos pendientes de sus disparadores) y que vive y
  -- muere en esta transacción, como el fixture B7. Solo lo viola una ficha llamada «FICHA CHECK 23514» ACTIVA a nombre de VEND2:
  -- la ficha nace a nombre de VEND1 (pasa) y el UPDATE de la reactivación pone vendedor_id = VEND2 con activo = true (23514
  -- `ens_23514_ajeno`). NOT VALID: no revisa las filas que ya hay; sí las que se escriban.
  if exists (select 1 from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'ens_23514_ajeno') then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene la restricción ens_23514_ajeno (sobra el fixture R2-2)';
  end if;
  execute format('alter table crm.leads add constraint ens_23514_ajeno check (not (activo and vendedor_id = %L::uuid and nombre_completo = %L)) not valid',
                 v_vend2, 'FICHA CHECK 23514');

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 1, 4 y 5. Retirado en etapa operativa, sin enlace, dueño VEND1; VEND2 registra a la misma persona (teléfono y DNI).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l1 := pg_temp.retirado(1, 'contactado', true, 'FICHA UNO', 'uno@ensayo.local', 5000);
  if not exists (select 1 from crm.lead_asignaciones la where la.lead_id = v_l1 and la.finalizado_en is not null and la.motivo_cierre = 'desactivado')
     or exists (select 1 from crm.lead_asignaciones la where la.lead_id = v_l1 and la.finalizado_en is null) then
    raise exception 'ENSAYO ABORTADO: el retiro del fixture 1 no cerró su episodio como «desactivado»';
  end if;
  perform pg_temp.medida(format('0 (veredicto del verificador sobre el retirado 1, teléfono+DNI): %s',
    private.verificar_disponibilidad_lead_impl(pg_temp.teln(1), pg_temp.dni(1)) ->> 'estado'));
  v_pid1 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid1, 'NOMBRE TECLEADO POR VEND2', pg_temp.tel(1), pg_temp.dni(1), 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  perform pg_temp.reg('1-reactiva (VEND2 sobre el retirado de VEND1)',
    pg_temp.exigir_reactivado('1-reactiva', v_res, v_l1, v_pid1, v_vend2, v_vend2, null, 'contactado', 1, v_vend1, 'contactado',
                              pg_temp.teln(1), pg_temp.dni(1)));
  -- 4. Dueño anterior distinto: rastro (propietario_anterior) y episodio del ledger (se mide el motivo que abre el trigger).
  select la.motivo_apertura into v_txt from crm.lead_asignaciones la where la.lead_id = v_l1 and la.finalizado_en is null;
  perform pg_temp.medida(format('4 (episodio abierto por el ledger tras reactivar el retirado 1, etapa operativa): motivo_apertura=%s', coalesce(v_txt, 'ninguno')));
  if v_txt is not null and v_txt <> 'reactivado' then
    perform pg_temp.reg('4-episodio-reactivado', format(E'FALLO 4-episodio-reactivado: el ledger abrió el episodio como «%s», no como «reactivado»\n', v_txt));
  elsif v_txt = 'reactivado' then
    perform pg_temp.reg('4-episodio-reactivado', '');
  end if;
  -- 5. Datos de la ficha conservados; lo tecleado va a la actividad (sin el documento ni los datos sensibles en claro).
  select * into v_l from crm.leads l where l.id = v_l1;
  select * into v_a from crm.actividades a where a.id = v_pid1;
  if v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado' then
    v_txt := '';
    if v_l.nombre_completo <> 'FICHA UNO' or v_l.correo is distinct from 'uno@ensayo.local' or v_l.monto_estimado <> 5000 then
      v_txt := v_txt || format('la ficha fue pisada (nombre %s, correo %s, capital %s); ', v_l.nombre_completo, v_l.correo, v_l.monto_estimado);
    end if;
    if v_a.id is null then
      v_txt := v_txt || 'sin actividad de rastro; ';
    else
      -- A-7: capital, moneda, origen y tipo de documento tecleados; la nota en el detalle; NADA más de lo tecleado.
      if (v_a.metadata -> 'tecleado' ->> 'monto_estimado')::numeric is distinct from 7777
         or v_a.metadata -> 'tecleado' ->> 'moneda' is distinct from 'PEN'
         or v_a.metadata -> 'tecleado' ->> 'origen' is distinct from 'formulario'
         or v_a.metadata -> 'tecleado' ->> 'tipo_documento' is distinct from 'DNI' then
        v_txt := v_txt || format('lo tecleado (capital, moneda, origen, tipo de documento) no quedó en la actividad (%s); ', v_a.metadata -> 'tecleado');
      end if;
      if v_a.detalle not like '%nota tecleada por vend2%' then
        v_txt := v_txt || 'la nota tecleada no quedó en el detalle; ';
      end if;
      if v_a.metadata -> 'tecleado' ? 'dni' or v_a.metadata -> 'tecleado' ? 'fecha_nacimiento' or v_a.metadata -> 'tecleado' ? 'genero'
         or v_a.metadata -> 'tecleado' ? 'nombre_completo' or v_a.metadata -> 'tecleado' ? 'correo'
         or v_a.metadata -> 'tecleado' ? 'telefono_alternativo' or v_a.metadata -> 'tecleado' ? 'telefono'
         or v_a.metadata::text like '%tecleado@ensayo.local%' or v_a.metadata::text like '%NOMBRE TECLEADO POR VEND2%' then
        v_txt := v_txt || 'el rastro guarda documento, datos sensibles o datos de contacto en claro (A-7); ';
      end if;
      -- A-1: la huella existe pero no es el md5 de un payload que incluya el DNI (se mide con el caso 6e).
      if v_a.metadata ->> 'tecleado_md5' is null then
        v_txt := v_txt || 'sin huella tecleado_md5; ';
      end if;
    end if;
    perform pg_temp.reg('5-ficha-conservada-y-tecleado-en-actividad', case when v_txt = '' then '' else format(E'FALLO 5-ficha-conservada: %s\n', v_txt) end);
  else
    perform pg_temp.reg('5-ficha-conservada-y-tecleado-en-actividad', E'FALLO 5-ficha-conservada: no se pudo medir porque el alta no reutilizó la ficha (ver 1-reactiva)\n');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 6. Idempotencia: el mismo p_id repite la misma respuesta sin segunda actividad ni segundo cambio; otro payload u
  --    otro actor con ese id se rechazan como hoy (22023).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_ficha := pg_temp.ficha(v_l1);
  v_res := pg_temp.alta(v_vend2, v_pid1, 'NOMBRE TECLEADO POR VEND2', pg_temp.tel(1), pg_temp.dni(1), 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  v_txt := '';
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_l1 then
    v_txt := v_txt || format('el reintento con el mismo p_id no devolvió «reutilizado» con la misma ficha (%s); ', v_res);
  end if;
  if pg_temp.ficha(v_l1) is distinct from v_ficha then v_txt := v_txt || 'el reintento volvió a cambiar la ficha; '; end if;
  select count(*) into v_n from crm.actividades a where a.lead_id = v_l1 and a.metadata ->> 'evento' = 'reactivacion_alta';
  if v_n <> 1 then v_txt := v_txt || format('%s actividades de rastro tras el reintento (debe seguir 1); ', v_n); end if;
  perform pg_temp.reg('6-idempotencia-mismo-p_id', case when v_txt = '' then '' else format(E'FALLO 6-idempotencia: %s\n', v_txt) end);
  v_res := pg_temp.alta(v_vend2, v_pid1, 'OTRO NOMBRE CON EL MISMO ID', pg_temp.tel(1), pg_temp.dni(1), 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  perform pg_temp.reg('6b-mismo-p_id-otro-payload', case when v_res like '22023|%' then ''
    else format(E'FALLO 6b-mismo-p_id-otro-payload: se esperaba 22023 «identificador ya usado» y llegó %s\n', v_res) end);
  v_res := pg_temp.alta(v_vend3, v_pid1, 'NOMBRE TECLEADO POR VEND2', pg_temp.tel(1), pg_temp.dni(1), 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  perform pg_temp.reg('6c-mismo-p_id-otro-actor', case when v_res like '22023|%' then ''
    else format(E'FALLO 6c-mismo-p_id-otro-actor: se esperaba 22023 y llegó %s\n', v_res) end);
  -- C-2 (P1): el mismo p_id con OTRO TELÉFONO no es el mismo alta: 22023, nunca «reutilizado» con la ficha anterior.
  v_ficha := pg_temp.ficha(v_l1);
  v_res := pg_temp.alta(v_vend2, v_pid1, 'NOMBRE TECLEADO POR VEND2', pg_temp.tel(90), pg_temp.dni(1), 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  perform pg_temp.reg('C2-mismo-p_id-otro-telefono', case when v_res like '22023|%' and pg_temp.ficha(v_l1) = v_ficha then ''
    else format(E'FALLO C2-mismo-p_id-otro-telefono: se esperaba 22023 (la huella debe llevar el teléfono) y llegó %s%s\n', v_res,
                case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado'
                     then ' → confirmó la ficha de OTRO contacto como si fuera el mismo alta' else '' end) end);
  -- A-1: la huella NO depende del DNI (ni del género ni de la fecha): el mismo p_id con otro DNI es el mismo alta (no altera
  -- datos). 6f: el TIPO de documento sí entra: sin DNI tecleado, la huella cambia ⇒ 22023.
  v_res := pg_temp.alta(v_vend2, v_pid1, 'NOMBRE TECLEADO POR VEND2', pg_temp.tel(1), pg_temp.dni(91), 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  v_txt := '';
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_l1 then
    v_txt := v_txt || format('el reintento con otro DNI no se trató como el mismo alta (%s); ', v_res);
  end if;
  if pg_temp.ficha(v_l1) is distinct from v_ficha then v_txt := v_txt || 'el reintento con otro DNI cambió la ficha; '; end if;
  if (select count(*) from crm.leads l where l.dni = pg_temp.dni(91)) <> 0 then v_txt := v_txt || 'nació un lead con el otro DNI; '; end if;
  perform pg_temp.reg('6e-huella-no-depende-del-dni', case when v_txt = '' then '' else format(E'FALLO 6e-huella-no-depende-del-dni: %s\n', v_txt) end);
  v_res := pg_temp.alta(v_vend2, v_pid1, 'NOMBRE TECLEADO POR VEND2', pg_temp.tel(1), null, 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  perform pg_temp.reg('6f-tipo-de-documento-en-la-huella', case when v_res like '22023|%' and pg_temp.ficha(v_l1) = v_ficha then ''
    else format(E'FALLO 6f-tipo-de-documento-en-la-huella: sin DNI tecleado se esperaba 22023 y llegó %s\n', v_res) end);
  -- A-6: el reintento solo confirma una ficha que SIGUE ACTIVA. Si Gerencia la retiró otra vez, el mismo p_id con el mismo
  -- payload vuelve a reactivarla (D-15) —su rastro lleva otro id y alta_id = p_id— y un tercer reintento repite la respuesta.
  -- (Sin la migración —ROJO— la ficha 1 nunca se reactivó y ya está retirada: no es un error de montaje, es el defecto.)
  v_txt := pg_temp.retirar(v_ger, v_l1);
  if v_txt <> '1' and (select l.activo from crm.leads l where l.id = v_l1) then
    raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha 1 (A-6): %', v_txt;
  end if;
  v_res := pg_temp.alta(v_vend2, v_pid1, 'NOMBRE TECLEADO POR VEND2', pg_temp.tel(1), pg_temp.dni(1), 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  v_txt := '';
  select * into v_l from crm.leads l where l.id = v_l1;
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_l1 then
    v_txt := v_txt || format('el reintento tras el segundo retiro no reutilizó la ficha (%s); ', v_res);
  elsif not v_l.activo or v_l.vendedor_id is distinct from v_vend2 then
    v_txt := v_txt || format('confirmó «reutilizado» con la ficha activo=%s dueño=%s (debía reactivarla de nuevo a nombre de VEND2); ', v_l.activo, v_l.vendedor_id);
  end if;
  select count(*) into v_n from crm.actividades a where a.lead_id = v_l1 and a.metadata ->> 'evento' = 'reactivacion_alta';
  if v_n <> 2 then v_txt := v_txt || format('%s rastros de reactivación (se esperaban 2: el del alta y el del reintento tras el retiro); ', v_n); end if;
  if not exists (select 1 from crm.actividades a where a.lead_id = v_l1 and a.id <> v_pid1
                  and a.metadata ->> 'evento' = 'reactivacion_alta' and (a.metadata ->> 'alta_id')::uuid = v_pid1) then
    v_txt := v_txt || 'el segundo rastro no lleva alta_id = p_id; ';
  end if;
  perform pg_temp.reg('A6-reintento-tras-segundo-retiro-reactiva-de-nuevo', case when v_txt = '' then '' else format(E'FALLO A6-reintento-tras-segundo-retiro: %s\n', v_txt) end);
  v_ficha := pg_temp.ficha(v_l1);
  v_res := pg_temp.alta(v_vend2, v_pid1, 'NOMBRE TECLEADO POR VEND2', pg_temp.tel(1), pg_temp.dni(1), 'nuevo', null,
                        'nota tecleada por vend2', 'tecleado@ensayo.local', 7777);
  perform pg_temp.reg('A6-tercer-reintento-repite-sin-cambios', case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado'
         and (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid = v_l1 and pg_temp.ficha(v_l1) = v_ficha
         and (select count(*) from crm.actividades a where a.lead_id = v_l1 and a.metadata ->> 'evento' = 'reactivacion_alta') = 2 then ''
    else format(E'FALLO A6-tercer-reintento: se esperaba la misma respuesta sin cambios y llegó %s\n', v_res) end);
  -- R2-1 (Codex r2, P2; ronda 3): DOS retirados del MISMO teléfono (los índices únicos son de leads vivos). VEND2 reactiva el
  -- primero con p_id; Gerencia lo retira otra vez; aparece OTRO retirado del mismo número, MÁS RECIENTE (actualizado_en posterior).
  -- El reintento con el mismo p_id tiene que reactivar LA FICHA DEL PRIMER RASTRO y dejar la otra como está: la identidad del
  -- reintento no se elige por contacto. (Sin la corrección, el núcleo vuelve a elegir por teléfono y actualizado_en, reactiva la
  -- otra ficha y devuelve otro lead_id.)
  v_l33 := pg_temp.retirado(33, 'contactado', true, 'FICHA TREINTA Y TRES');
  v_pid33 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid33, 'REINGRESO TREINTA Y TRES', pg_temp.tel(33), pg_temp.dni(33));
  perform pg_temp.reg('R2-1-primera-reactivacion',
    pg_temp.exigir_reactivado('R2-1-primera-reactivacion', v_res, v_l33, v_pid33, v_vend2, v_vend2, null, 'contactado', 1, v_vend1, 'contactado',
                              pg_temp.teln(33), pg_temp.dni(33)));
  v_txt := pg_temp.retirar(v_ger, v_l33);
  if v_txt <> '1' and (select l.activo from crm.leads l where l.id = v_l33) then
    raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha 33 (R2-1): %', v_txt;
  end if;
  v_b33 := pg_temp.retirado_sintetico(33, 'RETIRADO SINTETICO TREINTA Y TRES');
  -- (la otra retirada queda como la MÁS RECIENTE del número: si el reintento eligiera por contacto, la elegiría a ella)
  set local session_replication_role = replica;
  update crm.leads set actualizado_en = now() + interval '1 hour' where id = v_b33;
  set local session_replication_role = origin;
  v_ficha := pg_temp.ficha(v_b33);
  v_res := pg_temp.alta(v_vend2, v_pid33, 'REINGRESO TREINTA Y TRES', pg_temp.tel(33), pg_temp.dni(33));
  v_txt := '';
  select * into v_l from crm.leads l where l.id = v_l33;
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado' then
    v_txt := v_txt || format('el reintento tras el segundo retiro no reutilizó (%s); ', v_res);
  elsif (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_l33 then
    v_txt := v_txt || format('el reintento reactivó OTRA ficha del mismo teléfono (lead_id %s ≠ ficha del primer rastro %s); ',
      substr(v_res, 4)::jsonb ->> 'lead_id', v_l33);
  elsif not v_l.activo or v_l.vendedor_id is distinct from v_vend2 then
    v_txt := v_txt || format('la ficha del primer rastro quedó activo=%s dueño=%s (debía reactivarse a nombre de VEND2); ', v_l.activo, v_l.vendedor_id);
  end if;
  if pg_temp.ficha(v_b33) is distinct from v_ficha then
    v_txt := v_txt || format('la otra ficha retirada del mismo teléfono cambió (activo %s→%s); ', v_ficha ->> 'activo', pg_temp.ficha(v_b33) ->> 'activo');
  end if;
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(33) and l.activo) <> 1 then
    v_txt := v_txt || format('%s leads ACTIVOS con el teléfono 33 (debe ser 1); ', (select count(*) from crm.leads l where l.telefono = pg_temp.teln(33) and l.activo));
  end if;
  if not exists (select 1 from crm.actividades a where a.lead_id = v_l33 and a.id <> v_pid33
                  and a.metadata ->> 'evento' = 'reactivacion_alta' and (a.metadata ->> 'alta_id')::uuid = v_pid33) then
    v_txt := v_txt || 'la ficha del primer rastro no recibió el segundo rastro con alta_id = p_id; ';
  end if;
  if exists (select 1 from crm.actividades a where a.lead_id = v_b33 and a.metadata ->> 'evento' = 'reactivacion_alta') then
    v_txt := v_txt || 'la otra ficha recibió un rastro de reactivación; ';
  end if;
  perform pg_temp.reg('R2-1-reintento-fija-la-ficha-del-primer-rastro', case when v_txt = '' then '' else format(E'FALLO R2-1-reintento-fija-la-ficha: %s\n', v_txt) end);
  perform pg_temp.medida(format('R2-1 (reintento con dos retirados del mismo teléfono): %s; ficha del primer rastro=%s; la otra retirada=%s',
    case when v_res like 'ok|%' then substr(v_res, 4) else v_res end, v_l33, v_b33));
  -- Un tercer reintento repite la respuesta sin cambios en ninguna de las dos fichas.
  v_ficha := pg_temp.ficha(v_l33);
  v_ficha2 := pg_temp.ficha(v_b33);
  v_res := pg_temp.alta(v_vend2, v_pid33, 'REINGRESO TREINTA Y TRES', pg_temp.tel(33), pg_temp.dni(33));
  perform pg_temp.reg('R2-1-tercer-reintento-repite-sin-cambios', case when v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado'
         and (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid = v_l33 and pg_temp.ficha(v_l33) = v_ficha and pg_temp.ficha(v_b33) = v_ficha2 then ''
    else format(E'FALLO R2-1-tercer-reintento: se esperaba la misma respuesta (ficha del primer rastro) sin cambios y llegó %s\n', v_res) end);
  -- R3-1 (Codex r3, P2; ronda 4): un reintento con rastro previo NUNCA llega al INSERT. Si la ficha del primer rastro ya no se
  -- puede reactivar, el núcleo responde un veredicto bloqueante y nunca nulo (nulo dejaría que el alta insertara OTRA ficha con
  -- el mismo p_id). (Sin la corrección el núcleo cae al veredicto fresco: el verificador dice «libre», el núcleo devuelve nulo y
  -- el alta INSERTA una segunda ficha de la misma persona con `estado = creado`.)
  -- (a) La ficha quedó retirada y CONVERTIDA (sin persona: sembrada con los triggers apagados, como 3d) y el verificador dice
  --     «libre» ⇒ `ya_es_cliente` en el formato del verificador (a nombre del tenedor de la ficha, sin `via`), nada escrito, un
  --     solo lead por teléfono y por DNI, sin segundo rastro.
  v_l41 := pg_temp.retirado(41, 'contactado', true, 'FICHA CUARENTA Y UNO');
  v_pid41 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid41, 'REINGRESO CUARENTA Y UNO', pg_temp.tel(41), pg_temp.dni(41));
  perform pg_temp.reg('R3-1a-primera-reactivacion',
    pg_temp.exigir_reactivado('R3-1a-primera-reactivacion', v_res, v_l41, v_pid41, v_vend2, v_vend2, null, 'contactado', 1, v_vend1, 'contactado',
                              pg_temp.teln(41), pg_temp.dni(41)));
  -- (sin la migración —ROJO— la primera alta ya creó un segundo lead y el verificador dejará de decir «libre»: no es montaje, es el
  --  defecto, y el caso cae por él; las guardas de abajo solo exigen el escenario cuando la primera reactivación ocurrió)
  v_r41 := v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado';
  v_txt := pg_temp.retirar(v_ger, v_l41);
  if v_txt <> '1' and (select l.activo from crm.leads l where l.id = v_l41) then
    raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha 41 (R3-1a): %', v_txt;
  end if;
  v_ahora := clock_timestamp();
  set local session_replication_role = replica;
  update crm.leads set etapa = 'convertido', activo = false, convertido_en = v_ahora where id = v_l41;
  update crm.lead_asignaciones set finalizado_en = v_ahora, finalizado_por = v_vend2, motivo_cierre = 'convertido',
         resultado = 'convertido', resultado_en = v_ahora where lead_id = v_l41 and finalizado_en is null;
  update crm.lead_sla_etapas set finalizado_en = v_ahora, motivo_cierre = 'cierre_terminal' where lead_id = v_l41 and finalizado_en is null;
  set local session_replication_role = origin;
  v_txt := private.verificar_disponibilidad_lead_impl(pg_temp.teln(41), pg_temp.dni(41)) ->> 'estado';
  perform pg_temp.medida(format('R3-1a (veredicto del verificador sobre la ficha 41 retirada y CONVERTIDA, teléfono+DNI): %s', v_txt));
  if v_r41 and v_txt <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» sobre la ficha retirada y convertida (dice %): el caso R3-1a no mide lo que dice', v_txt;
  end if;
  v_tenedor := (select coalesce(pv.nombre_completo, ps.nombre_completo, 'sin asesor asignado')
                  from crm.leads l
                  left join public.perfiles pv on pv.id = l.vendedor_id
                  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
                 where l.id = v_l41);
  v_ficha := pg_temp.ficha(v_l41);
  v_res := pg_temp.alta(v_vend2, v_pid41, 'REINGRESO CUARENTA Y UNO', pg_temp.tel(41), pg_temp.dni(41));
  v_txt := pg_temp.exigir_intacto('R3-1a-convertida', v_res, v_l41, v_ficha, 'ok:ya_es_cliente');
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(41)) <> 1 or (select count(*) from crm.leads l where l.dni = pg_temp.dni(41)) <> 1 then
    v_txt := v_txt || format(E'FALLO R3-1a-convertida: %s leads con el teléfono 41 y %s con el DNI (debe ser 1 y 1): el reintento con rastro previo llegó al INSERT y creó OTRA ficha con el mismo p_id\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(41)), (select count(*) from crm.leads l where l.dni = pg_temp.dni(41)));
  end if;
  if (select count(*) from crm.actividades a where a.lead_id = v_l41 and a.metadata ->> 'evento' = 'reactivacion_alta') <> 1 then
    v_txt := v_txt || E'FALLO R3-1a-convertida: el reintento dejó otro rastro de reactivación sobre la ficha convertida\n';
  end if;
  if v_txt = '' and ((substr(v_res, 4)::jsonb ->> 'asesor') is distinct from v_tenedor or (substr(v_res, 4)::jsonb) ? 'via') then
    v_txt := format(E'FALLO R3-1a-convertida: «ya_es_cliente» no va en el formato del verificador a nombre del tenedor de la ficha (%s; se esperaba asesor=%s sin via)\n', substr(v_res, 4), v_tenedor);
  end if;
  perform pg_temp.reg('R3-1a-reintento-sobre-ficha-convertida-ya-es-cliente', v_txt);
  perform pg_temp.medida(format('R3-1a (reintento con el mismo p_id sobre la ficha retirada y convertida, verificador «libre»): %s; leads con el teléfono 41=%s',
    case when v_res like 'ok|%' then substr(v_res, 4) else v_res end, (select count(*) from crm.leads l where l.telefono = pg_temp.teln(41))));
  -- (b) La ficha del primer rastro YA NO EXISTE (borrada dentro del rollback con los disparadores apagados, como las siembras; el
  --     rastro con id = p_id sigue ahí) ⇒ 22023 «el alta original ya no existe» y no nace ninguna ficha con ese contacto.
  v_l42 := pg_temp.retirado(42, 'contactado', true, 'FICHA CUARENTA Y DOS');
  v_pid42 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid42, 'REINGRESO CUARENTA Y DOS', pg_temp.tel(42), pg_temp.dni(42));
  perform pg_temp.reg('R3-1b-primera-reactivacion',
    pg_temp.exigir_reactivado('R3-1b-primera-reactivacion', v_res, v_l42, v_pid42, v_vend2, v_vend2, null, 'contactado', 1, v_vend1, 'contactado',
                              pg_temp.teln(42), pg_temp.dni(42)));
  -- (la guarda de abajo solo vigila que el rastro que EXISTÍA sobreviva al borrado de la ficha: si no hubo rastro —el mutante
  --  «sin rastro»— el caso ya cae por R3-1b-primera-reactivacion y no es un error de montaje)
  v_r42 := v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado'
           and exists (select 1 from crm.actividades a where a.id = v_pid42 and a.metadata ->> 'evento' = 'reactivacion_alta');
  v_txt := pg_temp.retirar(v_ger, v_l42);
  if v_txt <> '1' and (select l.activo from crm.leads l where l.id = v_l42) then
    raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha 42 (R3-1b): %', v_txt;
  end if;
  set local session_replication_role = replica;
  delete from crm.leads where id = v_l42;
  set local session_replication_role = origin;
  if exists (select 1 from crm.leads l where l.id = v_l42) then
    raise exception 'ENSAYO ABORTADO: no se pudo borrar la ficha 42 (R3-1b)';
  end if;
  if v_r42 and not exists (select 1 from crm.actividades a where a.id = v_pid42 and a.metadata ->> 'evento' = 'reactivacion_alta') then
    raise exception 'ENSAYO ABORTADO: el rastro del alta 42 no sobrevivió al borrado de la ficha (el caso R3-1b no mide lo que dice)';
  end if;
  v_txt := private.verificar_disponibilidad_lead_impl(pg_temp.teln(42), pg_temp.dni(42)) ->> 'estado';
  perform pg_temp.medida(format('R3-1b (veredicto del verificador sobre el contacto 42 tras borrar la ficha): %s', v_txt));
  v_res := pg_temp.alta(v_vend2, v_pid42, 'REINGRESO CUARENTA Y DOS', pg_temp.tel(42), pg_temp.dni(42));
  v_txt := '';
  if v_res like 'ok|%' then
    v_txt := v_txt || format('debía rechazar con 22023 «el alta original ya no existe» y devolvió estado=%s; ', substr(v_res, 4)::jsonb ->> 'estado');
  elsif split_part(v_res, '|', 1) <> '22023' or position('ya no existe' in v_res) = 0 then
    v_txt := v_txt || format('rechazó con otro error: %s; ', v_res);
  end if;
  if exists (select 1 from crm.leads l where l.telefono = pg_temp.teln(42) or l.dni = pg_temp.dni(42)) then
    v_txt := v_txt || format('%s lead(s) con el contacto 42 (debe ser 0): el reintento con rastro previo llegó al INSERT y creó OTRA ficha con el mismo p_id; ',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(42) or l.dni = pg_temp.dni(42)));
  end if;
  perform pg_temp.reg('R3-1b-reintento-sobre-ficha-inexistente-22023', case when v_txt = '' then '' else format(E'FALLO R3-1b-inexistente: %s\n', v_txt) end);
  perform pg_temp.medida(format('R3-1b (reintento con el mismo p_id tras borrar la ficha): %s; leads con el contacto 42=%s',
    case when v_res like 'ok|%' then substr(v_res, 4) else v_res end,
    (select count(*) from crm.leads l where l.telefono = pg_temp.teln(42) or l.dni = pg_temp.dni(42))));
  -- (c) La ficha del primer rastro quedó retirada y VETADA («No contactar», sembrado con los disparadores apagados: la puerta
  --     `crm.marcar_no_contactar` exige la ficha activa y en el ámbito de quien marca, y en el ROJO la ficha nunca se reactivó) ⇒
  --     `no_contactar` (lo da ya el verificador por el teléfono; el núcleo lo garantiza también si no lo viera), nada escrito,
  --     un solo lead, sin segundo rastro.
  v_l43 := pg_temp.retirado(43, 'contactado', true, 'FICHA CUARENTA Y TRES');
  v_pid43 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid43, 'REINGRESO CUARENTA Y TRES', pg_temp.tel(43), pg_temp.dni(43));
  perform pg_temp.reg('R3-1c-primera-reactivacion',
    pg_temp.exigir_reactivado('R3-1c-primera-reactivacion', v_res, v_l43, v_pid43, v_vend2, v_vend2, null, 'contactado', 1, v_vend1, 'contactado',
                              pg_temp.teln(43), pg_temp.dni(43)));
  v_txt := pg_temp.retirar(v_ger, v_l43);
  if v_txt <> '1' and (select l.activo from crm.leads l where l.id = v_l43) then
    raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha 43 (R3-1c): %', v_txt;
  end if;
  set local session_replication_role = replica;
  update crm.leads set no_contactar = true where id = v_l43;
  set local session_replication_role = origin;
  if not (select l.no_contactar and not l.activo from crm.leads l where l.id = v_l43) then
    raise exception 'ENSAYO ABORTADO: la ficha 43 no quedó vetada y retirada (R3-1c)';
  end if;
  v_txt := private.verificar_disponibilidad_lead_impl(pg_temp.teln(43), pg_temp.dni(43)) ->> 'estado';
  perform pg_temp.medida(format('R3-1c (veredicto del verificador sobre la ficha 43 vetada y retirada): %s', v_txt));
  v_ficha := pg_temp.ficha(v_l43);
  v_res := pg_temp.alta(v_vend2, v_pid43, 'REINGRESO CUARENTA Y TRES', pg_temp.tel(43), pg_temp.dni(43));
  v_txt := pg_temp.exigir_intacto('R3-1c-vetada', v_res, v_l43, v_ficha, 'ok:no_contactar');
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(43)) <> 1 then
    v_txt := v_txt || format(E'FALLO R3-1c-vetada: %s leads con el teléfono 43 (debe ser 1): el reintento creó OTRA ficha\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(43)));
  end if;
  if (select count(*) from crm.actividades a where a.lead_id = v_l43 and a.metadata ->> 'evento' = 'reactivacion_alta') <> 1 then
    v_txt := v_txt || E'FALLO R3-1c-vetada: el reintento dejó otro rastro de reactivación sobre la ficha vetada\n';
  end if;
  perform pg_temp.reg('R3-1c-reintento-sobre-ficha-vetada-no-contactar', v_txt);
  perform pg_temp.medida(format('R3-1c (reintento con el mismo p_id sobre la ficha vetada y retirada): %s',
    case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));
  -- R4-1 (Codex r4, P2; ronda 5): el paso 3a del núcleo NUNCA devuelve nulo en un reintento con rastro previo. Reintento con el
  -- mismo p_id sobre la ficha del primer rastro (retirada otra vez) cuando OTRO lead ACTIVO coincide con lo TECLEADO y el verificador
  -- no lo califica: un DESCARTADO ACTIVO con motivo de 0 días (pide_credito) dentro de sus 24 h, a nombre de VEND1 (en esa ventana el
  -- verificador dice «libre»: la carencia es solo para tomar). ⇒ el veredicto que el verificador daría para ese lead activo («tomado»
  -- nombrando a su tenedor, o «en_bolsa» si no lo tiene), nada escrito: la ficha retirada y el descartado activo intactos, los mismos
  -- leads con ese teléfono que antes del reintento, sin segundo rastro. (Con el núcleo de la ronda 4 el paso 3a devuelve nulo, el alta
  -- sigue al INSERT —los índices vivos no cubren descartados— y nace OTRA ficha con el mismo p_id: tres leads con el teléfono.)
  v_l44 := pg_temp.retirado(44, 'contactado', true, 'FICHA CUARENTA Y CUATRO');
  v_pid44 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid44, 'REINGRESO CUARENTA Y CUATRO', pg_temp.tel(44), pg_temp.dni(44));
  perform pg_temp.reg('R4-1-primera-reactivacion',
    pg_temp.exigir_reactivado('R4-1-primera-reactivacion', v_res, v_l44, v_pid44, v_vend2, v_vend2, null, 'contactado', 1, v_vend1, 'contactado',
                              pg_temp.teln(44), pg_temp.dni(44)));
  -- (sin la migración —ROJO— la primera alta ya creó un segundo lead ACTIVO del número: el descartado activo no se siembra (chocaría
  --  con el índice vivo y sería un error de montaje) y el caso cae por R4-1-primera-reactivacion y por el reintento, nunca por
  --  montaje; el escenario completo solo se exige cuando la primera reactivación ocurrió y dejó su rastro)
  v_r44 := v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado'
           and exists (select 1 from crm.actividades a where a.id = v_pid44 and a.metadata ->> 'evento' = 'reactivacion_alta');
  v_txt := pg_temp.retirar(v_ger, v_l44);
  if v_txt <> '1' and (select l.activo from crm.leads l where l.id = v_l44) then
    raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha 44 (R4-1): %', v_txt;
  end if;
  v_a44 := null;
  v_esperado := 'ok:tomado';
  if v_r44 then
    v_a44 := pg_temp.descartado_activo_sintetico(44, 'DESCARTADO ACTIVO CERO DIAS CUARENTA Y CUATRO', pg_temp.dni(44));
    v_esperado := (select case when l.vendedor_id is null and l.asignado_supervisor_id is null then 'ok:en_bolsa' else 'ok:tomado' end
                     from crm.leads l where l.id = v_a44);
  end if;
  v_txt := private.verificar_disponibilidad_lead_impl(pg_temp.teln(44), pg_temp.dni(44)) ->> 'estado';
  perform pg_temp.medida(format('R4-1 (veredicto del verificador sobre el contacto 44: ficha retirada otra vez + descartado ACTIVO de 0 días en sus 24 h): %s; se espera %s', v_txt, v_esperado));
  if v_r44 and v_txt <> 'libre' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» con el descartado activo de 0 días en sus 24 h (dice %): el caso R4-1 no mide lo que dice', v_txt;
  end if;
  v_ficha := pg_temp.ficha(v_l44);
  v_ficha2 := case when v_a44 is not null then pg_temp.ficha(v_a44) end;
  select count(*) into v_n from crm.leads l where l.telefono = pg_temp.teln(44);
  v_res := pg_temp.alta(v_vend2, v_pid44, 'REINGRESO CUARENTA Y CUATRO', pg_temp.tel(44), pg_temp.dni(44));
  v_txt := pg_temp.exigir_intacto('R4-1-activo-por-lo-tecleado', v_res, v_l44, v_ficha, v_esperado);
  select count(*) into v_n2 from crm.leads l where l.telefono = pg_temp.teln(44);
  if v_n2 <> v_n then
    v_txt := v_txt || format(E'FALLO R4-1-activo-por-lo-tecleado: %s leads con el teléfono 44 (había %s antes del reintento: la ficha retirada y el descartado activo): el reintento con rastro previo llegó al INSERT y creó OTRA ficha con el mismo p_id\n', v_n2, v_n);
  end if;
  if v_a44 is not null and pg_temp.ficha(v_a44) is distinct from v_ficha2 then
    v_txt := v_txt || E'FALLO R4-1-activo-por-lo-tecleado: el descartado activo cambió\n';
  end if;
  if (select count(*) from crm.actividades a where a.lead_id = v_l44 and a.metadata ->> 'evento' = 'reactivacion_alta') > 1 then
    v_txt := v_txt || E'FALLO R4-1-activo-por-lo-tecleado: el reintento dejó otro rastro de reactivación sobre la ficha retirada\n';
  end if;
  if v_txt = '' and v_esperado = 'ok:tomado' and (substr(v_res, 4)::jsonb ->> 'vendedor') is distinct from (select p.nombre_completo from public.perfiles p where p.id = v_vend1) then
    v_txt := format(E'FALLO R4-1-activo-por-lo-tecleado: el veredicto «tomado» no nombra al tenedor VEND1 del descartado activo (%s)\n', substr(v_res, 4));
  end if;
  perform pg_temp.reg('R4-1-reintento-con-descartado-activo-de-0-dias-por-lo-tecleado-bloquea', v_txt);
  perform pg_temp.medida(format('R4-1 (reintento con el mismo p_id: ficha retirada otra vez + descartado activo de 0 días por lo tecleado, verificador «libre»): %s; leads con el teléfono 44=%s',
    case when v_res like 'ok|%' then substr(v_res, 4) else v_res end, v_n2));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 2. Retirado + descartado con la espera SIN vencer (sin_fondos, 90 días) ⇒ se reactiva igual (D-15): nuevo, ciclo 2.
  --    2b. Retirado + descartado con motivo de 0 días dentro de las 24 h ⇒ se reactiva sin esperar la carencia.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l2 := pg_temp.retirado(2, 'nuevo', true, 'FICHA DOS', null, 5000, 'sin_fondos');
  v_txt := private.verificar_disponibilidad_lead_impl(pg_temp.teln(2), pg_temp.dni(2)) ->> 'estado';
  perform pg_temp.medida(format('2 (veredicto del verificador sobre el retirado descartado sin_fondos hace un instante): %s', v_txt));
  if v_txt <> 'enfriamiento' then
    raise exception 'ENSAYO ABORTADO: el verificador no dice «enfriamiento» sobre el retirado descartado (dice %): el caso 2 no mide lo que dice', v_txt;
  end if;
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO DOS', pg_temp.tel(2), pg_temp.dni(2));
  perform pg_temp.reg('2-enfriamiento-vigente-se-reactiva',
    pg_temp.exigir_reactivado('2-enfriamiento-vigente', v_res, v_l2, v_pid, v_vend2, v_vend2, null, 'nuevo', 2, v_vend1, 'descartado',
                              pg_temp.teln(2), pg_temp.dni(2)));
  select la.motivo_apertura into v_txt from crm.lead_asignaciones la where la.lead_id = v_l2 and la.finalizado_en is null;
  perform pg_temp.medida(format('2 (episodio abierto por el ledger tras reactivar un retirado DESCARTADO): motivo_apertura=%s', coalesce(v_txt, 'ninguno')));

  v_l3 := pg_temp.retirado(3, 'nuevo', true, 'FICHA TRES', null, 5000, 'pide_credito');
  perform pg_temp.medida(format('2b (veredicto del verificador sobre el retirado descartado pide_credito, 0 días, hace un instante): %s',
    private.verificar_disponibilidad_lead_impl(pg_temp.teln(3), pg_temp.dni(3)) ->> 'estado'));
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO TRES', pg_temp.tel(3), pg_temp.dni(3));
  perform pg_temp.reg('2b-cero-dias-dentro-de-24h-se-reactiva',
    pg_temp.exigir_reactivado('2b-cero-dias', v_res, v_l3, v_pid, v_vend2, v_vend2, null, 'nuevo', 2, v_vend1, 'descartado',
                              pg_temp.teln(3), pg_temp.dni(3)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3. NEGATIVOS que no cambian (la ficha retirada queda intacta byte a byte y la respuesta es la de hoy).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3a. Un lead ACTIVO (operativo, de VEND1) con el mismo teléfono y DNI, junto a un retirado del mismo número ⇒ «tomado».
  v_b4 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_b4, 'ACTIVO CUATRO', pg_temp.tel(4), pg_temp.dni(4));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead activo del caso 3a (%)', v_res;
  end if;
  v_a4 := pg_temp.retirado_sintetico(4, 'RETIRADO SINTETICO CUATRO');
  v_ficha := pg_temp.ficha(v_a4);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO CUATRO', pg_temp.tel(4), pg_temp.dni(4));
  perform pg_temp.reg('3a-activo-del-mismo-contacto-tomado', pg_temp.exigir_intacto('3a-activo-tomado', v_res, v_a4, v_ficha, 'ok:tomado'));
  if (select l.vendedor_id from crm.leads l where l.id = v_b4) is distinct from v_vend1 then
    perform pg_temp.reg('3a-activo-sigue-de-vend1', E'FALLO 3a-activo-sigue-de-vend1: el lead activo cambió de dueño\n');
  else
    perform pg_temp.reg('3a-activo-sigue-de-vend1', '');
  end if;
  -- 3b. Un lead DESCARTADO ACTIVO con la espera vigente, junto a un retirado del mismo número ⇒ «enfriamiento» (sigue bloqueando).
  v_b5 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_b5, 'DESCARTADO ACTIVO CINCO', pg_temp.tel(5), pg_temp.dni(5));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 3b (%)', v_res;
  end if;
  if pg_temp.descartar(v_vend1, v_b5, 'sin_fondos') <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo descartar el lead del caso 3b';
  end if;
  v_a5 := pg_temp.retirado_sintetico(5, 'RETIRADO SINTETICO CINCO');
  v_ficha := pg_temp.ficha(v_a5);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO CINCO', pg_temp.tel(5), pg_temp.dni(5));
  perform pg_temp.reg('3b-descartado-activo-en-enfriamiento-bloquea', pg_temp.exigir_intacto('3b-enfriamiento-activo', v_res, v_a5, v_ficha, 'ok:enfriamiento'));
  if (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = v_b5) is distinct from 'descartado|true' then
    perform pg_temp.reg('3b-descartado-activo-intacto', E'FALLO 3b-descartado-activo-intacto: el descartado activo cambió\n');
  else
    perform pg_temp.reg('3b-descartado-activo-intacto', '');
  end if;
  -- 3c. Retirado ENLAZADO a una persona (nació con el DNI de una identidad reconocida) ⇒ «ya_es_cliente» con el DNI; con solo
  --     el teléfono, lo de hoy (se mide) y la ficha intacta.
  v_p6 := private.inversionista_resolver('DNI', pg_temp.dni(6), true, 'ensayo-bloque-2.4');
  v_l6 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_l6, 'ENLAZADO SEIS', pg_temp.tel(6), pg_temp.dni(6));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado'
     or (select l.inversionista_id from crm.leads l where l.id = v_l6) is distinct from v_p6 then
    raise exception 'ENSAYO ABORTADO: el lead del caso 3c no nació enlazado a la persona % (%)', v_p6, v_res;
  end if;
  if pg_temp.retirar(v_ger, v_l6) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar el enlazado del caso 3c'; end if;
  v_ficha := pg_temp.ficha(v_l6);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO SEIS', pg_temp.tel(6), pg_temp.dni(6));
  perform pg_temp.reg('3c-enlazado-con-dni-ya-es-cliente', pg_temp.exigir_intacto('3c-enlazado-con-dni', v_res, v_l6, v_ficha, 'ok:ya_es_cliente'));
  -- D-21 (ronda 2): con SOLO el teléfono, el retirado enlazado también bloquea («ya es cliente», el mismo juicio de identidad
  -- que con el DNI) y no nace un segundo lead de una persona reconocida.
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO SEIS SOLO TELEFONO', pg_temp.tel(6), null);
  v_txt := pg_temp.exigir_intacto('3c-enlazado-solo-telefono', v_res, v_l6, v_ficha, 'ok:ya_es_cliente');
  if v_txt = '' and (select count(*) from crm.leads l where l.telefono = pg_temp.teln(6)) <> 1 then
    v_txt := format(E'FALLO 3c-enlazado-solo-telefono: %s leads con el teléfono del enlazado (debe seguir 1)\n', (select count(*) from crm.leads l where l.telefono = pg_temp.teln(6)));
  end if;
  if v_txt = '' and v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'via') is distinct from 'identidad' then
    v_txt := format(E'FALLO 3c-enlazado-solo-telefono: el juicio no es el de identidad (%s)\n', substr(v_res, 4));
  end if;
  perform pg_temp.reg('3c-enlazado-solo-telefono-bloquea (D-21)', v_txt);
  perform pg_temp.medida(format('3c (retirado enlazado, alta solo con teléfono — D-21): %s; leads con ese teléfono=%s',
    case when v_res like 'ok|%' then substr(v_res, 4) else v_res end,
    (select count(*) from crm.leads l where l.telefono = pg_temp.teln(6))));
  -- 3d. CONVERTIDO retirado (sin persona; sembrado con los triggers apagados), alta con su teléfono y su DNI ⇒ la ficha intacta (la
  --     rama de este bloque nunca reactiva un convertido) y la respuesta según el bloque 2.7 (D-22 de Miguel, 08/10/2026: «si el
  --     teléfono es de un cliente ya convertido, el alta responde ya_es_cliente y no crea nada»; adaptado en la ronda 2 del 2.7):
  --     · el núcleo lleva la regla del 2.7 —lo dice su propio cuerpo: declara `v_convertido` (migración
  --       20261022170300_crm_cliente_por_telefono.sql)— ⇒ `ya_es_cliente` a nombre del dueño de la ficha (VEND1), sin `via`, y ningún
  --       lead más con ese teléfono;
  --     · no la lleva (el núcleo de este bloque, `md5(prosrc)` bf0a7531…) ⇒ lo de hoy: `creado` (un segundo lead).
  --     El subcaso «3d (reintento)» de abajo mide lo mismo (la rama no reactiva convertidos) por el único camino que la regla del 2.7
  --     no intercepta, para que el mutante «la rama reactiva convertidos» muera con y sin el 2.7.
  --     Ronda 3 del 2.7 (Codex): el MODO esperado lo fija quien arma el ensayo (`ensayo.modo_2_7` = 'con' | 'sin'; el armador del 2.7
  --     lo pone; sin él —el armador de este bloque, que nunca incluye el 2.7— es 'sin') y tiene que coincidir con lo que dice el cuerpo
  --     del núcleo: si no coinciden, FALLO (así, si la regla y su marca desaparecieran juntas, 3d no puede quedar verde esperando
  --     `creado`). La respuesta esperada sale del modo, no de la detección.
  v_27 := position('v_convertido' in coalesce((select p.prosrc from pg_proc p where p.oid = v_nucleo), '')) > 0;
  v_modo := coalesce(nullif(current_setting('ensayo.modo_2_7', true), ''), 'sin');
  v_l7 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_l7, 'CONVERTIDO SIETE', pg_temp.tel(7), pg_temp.dni(7));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 3d (%)', v_res;
  end if;
  -- (clock_timestamp: el ledger exige finalizado_en >= asignado_en y el alta selló asignado_en después del inicio de la transacción)
  v_ahora := clock_timestamp();
  set local session_replication_role = replica;
  update crm.leads set etapa = 'convertido', activo = false, convertido_en = v_ahora where id = v_l7;
  update crm.lead_asignaciones set finalizado_en = v_ahora, finalizado_por = v_vend1, motivo_cierre = 'convertido',
         resultado = 'convertido', resultado_en = v_ahora where lead_id = v_l7 and finalizado_en is null;
  update crm.lead_sla_etapas set finalizado_en = v_ahora, motivo_cierre = 'cierre_terminal' where lead_id = v_l7 and finalizado_en is null;
  set local session_replication_role = origin;
  v_ficha := pg_temp.ficha(v_l7);
  -- (sin el 2.7, hoy el alta CREA otro lead sobre un convertido retirado; se exige lo de hoy para que un mutante que intente
  --  reactivarlo —y falle en los triggers— no pase por «intacto»; con el 2.7, «ya_es_cliente» exacto y un solo lead)
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO SIETE', pg_temp.tel(7), pg_temp.dni(7));
  if v_modo not in ('con', 'sin') or (v_modo = 'con') is distinct from v_27 then
    v_txt := format(E'FALLO 3d-convertido-retirado: el armador esperaba el modo «%s» del bloque 2.7 y el cuerpo del núcleo dice «%s» (núcleo md5(prosrc) = %s)\n',
      v_modo, case when v_27 then 'con' else 'sin' end, coalesce((select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), 'ausente'));
  elsif v_modo = 'con' then
    v_txt := pg_temp.exigir_intacto('3d-convertido-retirado', v_res, v_l7, v_ficha, 'ok:ya_es_cliente');
    if v_txt = '' and ((substr(v_res, 4)::jsonb) is distinct from pg_catalog.jsonb_build_object('estado', 'ya_es_cliente',
                         'asesor', (select p.nombre_completo from public.perfiles p where p.id = v_vend1))
                       or (select count(*) from crm.leads l where l.telefono = pg_temp.teln(7)) <> 1) then
      v_txt := format(E'FALLO 3d-convertido-retirado: con el bloque 2.7 se esperaba «ya_es_cliente» a nombre de VEND1 (sin via) y un solo lead con ese teléfono (%s; %s leads)\n',
        substr(v_res, 4), (select count(*) from crm.leads l where l.telefono = pg_temp.teln(7)));
    end if;
  else
    v_txt := pg_temp.exigir_intacto('3d-convertido-retirado', v_res, v_l7, v_ficha, 'ok:creado');
  end if;
  perform pg_temp.reg('3d-convertido-retirado-no-se-reactiva', v_txt);
  perform pg_temp.medida(format('3d (convertido retirado sin persona, teléfono + DNI; modo esperado %s; regla del bloque 2.7 %s; núcleo md5(prosrc) = %s): %s; leads con ese teléfono=%s',
    v_modo, case when v_27 then 'PRESENTE' else 'ausente' end, coalesce((select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), 'ausente'),
    case when v_res like 'ok|%' then 'estado=' || (substr(v_res, 4)::jsonb ->> 'estado') else v_res end,
    (select count(*) from crm.leads l where l.telefono = pg_temp.teln(7))));
  -- 3d (reintento) — la rama de este bloque nunca reactiva un convertido, con o sin el bloque 2.7. Con el 2.7, el alta NUEVA sobre un
  --     convertido ya no llega a esta rama (su regla del teléfono/DNI responde antes), así que se mide por el único camino que el 2.7
  --     no intercepta: el reintento con el mismo p_id sobre una ficha que, tras su primera reactivación, quedó retirada y CONVERTIDA
  --     (sin persona; sembrado como arriba) ⇒ `ya_es_cliente` a nombre de su tenedor (R3-1), sin reactivarla. Es el caso que mata al
  --     mutante «la rama reactiva convertidos» (M4 de mutantes.sh, que nombra «3d-convertido-retirado:») con y sin el 2.7. (Sin la
  --     migración de este bloque —su ROJO— la primera alta crea un segundo lead y el subcaso cae por ese defecto.)
  v_l45 := pg_temp.retirado(45, 'contactado', true, 'FICHA CUARENTA Y CINCO');
  v_pid45 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid45, 'REINGRESO CUARENTA Y CINCO', pg_temp.tel(45), pg_temp.dni(45));
  v_r45 := v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'estado') = 'reutilizado';
  v_txt := case when v_r45 then '' else format(E'FALLO 3d-convertido-retirado: (reintento) la primera reactivación no ocurrió (%s)\n', v_res) end;
  if v_r45 then
    v_ret := pg_temp.retirar(v_ger, v_l45);
    if v_ret <> '1' then
      raise exception 'ENSAYO ABORTADO: no se pudo retirar otra vez la ficha 45 (3d reintento): %', v_ret;
    end if;
    v_ahora := clock_timestamp();
    set local session_replication_role = replica;
    update crm.leads set etapa = 'convertido', activo = false, convertido_en = v_ahora where id = v_l45;
    update crm.lead_asignaciones set finalizado_en = v_ahora, finalizado_por = v_vend2, motivo_cierre = 'convertido',
           resultado = 'convertido', resultado_en = v_ahora where lead_id = v_l45 and finalizado_en is null;
    update crm.lead_sla_etapas set finalizado_en = v_ahora, motivo_cierre = 'cierre_terminal' where lead_id = v_l45 and finalizado_en is null;
    set local session_replication_role = origin;
    if private.verificar_disponibilidad_lead_impl(pg_temp.teln(45), pg_temp.dni(45)) ->> 'estado' <> 'libre' then
      raise exception 'ENSAYO ABORTADO: el verificador no dice «libre» sobre la ficha 45 retirada y convertida: el subcaso 3d (reintento) no mediría lo que dice';
    end if;
    v_ficha := pg_temp.ficha(v_l45);
    v_res := pg_temp.alta(v_vend2, v_pid45, 'REINGRESO CUARENTA Y CINCO', pg_temp.tel(45), pg_temp.dni(45));
    v_txt := pg_temp.exigir_intacto('3d-convertido-retirado', v_res, v_l45, v_ficha, 'ok:ya_es_cliente');
    if v_txt = '' and ((select count(*) from crm.leads l where l.telefono = pg_temp.teln(45)) <> 1
                       or (substr(v_res, 4)::jsonb ->> 'asesor') is distinct from (select p.nombre_completo from public.perfiles p where p.id = v_vend2)) then
      v_txt := format(E'FALLO 3d-convertido-retirado: (reintento) se esperaba «ya_es_cliente» a nombre de VEND2 y un solo lead con ese teléfono (%s)\n', substr(v_res, 4));
    end if;
  end if;
  perform pg_temp.reg('3d-reintento-la-rama-no-reactiva-convertidos', v_txt);
  -- 3e. Retirado marcado «No contactar» (por su puerta, como su dueño) ⇒ «no_contactar», intacto.
  v_l8 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_l8, 'VETADO OCHO', pg_temp.tel(8), pg_temp.dni(8));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso 3e (%)', v_res;
  end if;
  begin
    perform pg_temp.sesion(v_vend1);
    perform crm.marcar_no_contactar(v_l8, null);
    perform pg_temp.sesion(null);
  exception when others then
    raise exception 'ENSAYO ABORTADO: no se pudo marcar No contactar en el caso 3e (% %)', sqlstate, sqlerrm;
  end;
  if pg_temp.retirar(v_ger, v_l8) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar el vetado del caso 3e'; end if;
  v_ficha := pg_temp.ficha(v_l8);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO OCHO', pg_temp.tel(8), pg_temp.dni(8));
  perform pg_temp.reg('3e-no-contactar-sigue-bloqueando', pg_temp.exigir_intacto('3e-no-contactar', v_res, v_l8, v_ficha, 'ok:no_contactar'));
  -- 3g. El veto de OTRO lead del mismo número manda sobre un retirado reutilizable: A (vetado, luego retirado) y B (retirado
  --     sintético del mismo teléfono, con DNI, sin veto) ⇒ «no_contactar» y B intacto (la rama no puede saltarse el veredicto).
  v_l19a := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_l19a, 'VETADO DIECINUEVE', pg_temp.tel(19), null);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead A del caso 3g (%)', v_res;
  end if;
  begin
    perform pg_temp.sesion(v_vend1);
    perform crm.marcar_no_contactar(v_l19a, null);
    perform pg_temp.sesion(null);
  exception when others then
    raise exception 'ENSAYO ABORTADO: no se pudo marcar No contactar en el caso 3g (% %)', sqlstate, sqlerrm;
  end;
  if pg_temp.retirar(v_ger, v_l19a) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar el vetado del caso 3g'; end if;
  v_b19 := pg_temp.retirado_sintetico(19, 'RETIRADO SINTETICO DIECINUEVE');
  v_ficha := pg_temp.ficha(v_b19);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO DIECINUEVE', pg_temp.tel(19), pg_temp.dni(19));
  perform pg_temp.reg('3g-veto-de-otro-retirado-del-mismo-numero', pg_temp.exigir_intacto('3g-veto-de-otro-retirado', v_res, v_b19, v_ficha, 'ok:no_contactar'));
  -- 3i. El veto de OTRO lead que casa solo por el DNI TECLEADO (no por nada de la ficha): A (tel 31, DNI 31) vetado y retirado;
  --     retirado sintético B (tel 32, DNI 32); alta (tel 32, DNI 31) ⇒ el verificador dice «no_contactar» y la rama NO puede
  --     saltárselo (su filtro del veredicto); B intacto. (Es el caso que mata al mutante «la rama no filtra el veredicto».)
  v_l31 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_l31, 'VETADO TREINTA Y UNO', pg_temp.tel(31), pg_temp.dni(31));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead A del caso 3i (%)', v_res;
  end if;
  begin
    perform pg_temp.sesion(v_vend1);
    perform crm.marcar_no_contactar(v_l31, null);
    perform pg_temp.sesion(null);
  exception when others then
    raise exception 'ENSAYO ABORTADO: no se pudo marcar No contactar en el caso 3i (% %)', sqlstate, sqlerrm;
  end;
  if pg_temp.retirar(v_ger, v_l31) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar el vetado del caso 3i'; end if;
  v_b32 := pg_temp.retirado_sintetico(32, 'RETIRADO SINTETICO TREINTA Y DOS', pg_temp.dni(32));
  v_ficha := pg_temp.ficha(v_b32);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO TREINTA Y DOS', pg_temp.tel(32), pg_temp.dni(31));
  perform pg_temp.reg('3i-veto-por-el-dni-tecleado-de-otro-lead-manda', pg_temp.exigir_intacto('3i-veto-por-dni-tecleado', v_res, v_b32, v_ficha, 'ok:no_contactar'));
  -- C-1 (P1, ronda 2): un lead ACTIVO que coincide con un dato que CONSERVA la ficha retirada (no con lo tecleado) bloquea con
  -- el veredicto del verificador para ese dato; nunca se llega al INSERT (un solo lead por contacto; nada escrito).
  -- C-1a: activo (U=21, A=20) en la BOLSA (Gerencia sin destino) + retirado sintético (T=20, A=20); alta (T=20, B=92) ⇒ en_bolsa.
  v_a20 := gen_random_uuid();
  v_res := pg_temp.alta(v_ger, v_a20, 'ACTIVO EN BOLSA VEINTIUNO', pg_temp.tel(21), pg_temp.dni(20));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado'
     or (select l.vendedor_id is null and l.asignado_supervisor_id is null and l.activo from crm.leads l where l.id = v_a20) is distinct from true then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el activo en bolsa del caso C-1a (%)', v_res;
  end if;
  v_b20 := pg_temp.retirado_sintetico(20, 'RETIRADO SINTETICO VEINTE', pg_temp.dni(20));
  v_ficha := pg_temp.ficha(v_b20);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO VEINTE OTRO DNI', pg_temp.tel(20), pg_temp.dni(92));
  v_txt := pg_temp.exigir_intacto('C1a-activo-por-dni-conservado', v_res, v_b20, v_ficha, 'ok:en_bolsa');
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(20)) <> 1 or exists (select 1 from crm.leads l where l.dni = pg_temp.dni(92)) then
    v_txt := v_txt || format(E'FALLO C1a-activo-por-dni-conservado: %s leads con el teléfono del retirado (debe ser 1) y %s con el DNI tecleado (debe ser 0): el alta creó un SEGUNDO lead de la persona\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(20)), (select count(*) from crm.leads l where l.dni = pg_temp.dni(92)));
  end if;
  perform pg_temp.reg('C1a-activo-por-el-dni-conservado-bloquea', v_txt);
  perform pg_temp.medida(format('C-1a (activo en bolsa por el DNI conservado): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));
  -- C-1b: activo (T=22, sin DNI) de VEND1 + retirado sintético (T=22, A=22); alta (V=23, A=22) ⇒ tomado (por el teléfono conservado).
  v_a22 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_a22, 'ACTIVO VEINTIDOS', pg_temp.tel(22), null);
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el activo del caso C-1b (%)', v_res;
  end if;
  v_b22 := pg_temp.retirado_sintetico(22, 'RETIRADO SINTETICO VEINTIDOS', pg_temp.dni(22));
  v_ficha := pg_temp.ficha(v_b22);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO VEINTITRES', pg_temp.tel(23), pg_temp.dni(22));
  v_txt := pg_temp.exigir_intacto('C1b-activo-por-telefono-conservado', v_res, v_b22, v_ficha, 'ok:tomado');
  if exists (select 1 from crm.leads l where l.telefono = pg_temp.teln(23)) or (select count(*) from crm.leads l where l.dni = pg_temp.dni(22)) <> 1 then
    v_txt := v_txt || format(E'FALLO C1b-activo-por-telefono-conservado: %s leads con el teléfono tecleado (debe ser 0) y %s con el DNI (debe ser 1): el alta creó un SEGUNDO lead de la persona\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(23)), (select count(*) from crm.leads l where l.dni = pg_temp.dni(22)));
  end if;
  if v_txt = '' and v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'vendedor') is distinct from (select p.nombre_completo from public.perfiles p where p.id = v_vend1) then
    v_txt := format(E'FALLO C1b-activo-por-telefono-conservado: el veredicto «tomado» no nombra al tenedor VEND1 (%s)\n', substr(v_res, 4));
  end if;
  perform pg_temp.reg('C1b-activo-por-el-telefono-conservado-bloquea', v_txt);
  perform pg_temp.medida(format('C-1b (activo tomado por el teléfono conservado): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));
  -- B1 (borde sin caso, ronda 3): un CONVERTIDO ACTIVO (sin enlace a persona ni perfil de portal: sembrado con los triggers
  -- apagados, como el 3d pero vivo) que casa SOLO por el DNI que conserva la ficha retirada (T=38, A=37): el verificador no lo
  -- cuenta (su «tomado» excluye convertido) y dice «libre»; la pieza del veredicto conservado tiene que responder «ya_es_cliente»
  -- y nunca llegar al INSERT. Alta (T=38, B=93).
  v_a37 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_a37, 'CONVERTIDO ACTIVO TREINTA Y SIETE', pg_temp.tel(37), pg_temp.dni(37));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso B1 (%)', v_res;
  end if;
  v_ahora := clock_timestamp();
  set local session_replication_role = replica;
  update crm.leads set etapa = 'convertido', convertido_en = v_ahora where id = v_a37;
  update crm.lead_asignaciones set finalizado_en = v_ahora, finalizado_por = v_vend1, motivo_cierre = 'convertido',
         resultado = 'convertido', resultado_en = v_ahora where lead_id = v_a37 and finalizado_en is null;
  update crm.lead_sla_etapas set finalizado_en = v_ahora, motivo_cierre = 'cierre_terminal' where lead_id = v_a37 and finalizado_en is null;
  set local session_replication_role = origin;
  perform pg_temp.medida(format('B1 (veredicto del verificador sobre el convertido ACTIVO 37 por su DNI, con otro teléfono): %s',
    private.verificar_disponibilidad_lead_impl(pg_temp.teln(38), pg_temp.dni(37)) ->> 'estado'));
  v_b38 := pg_temp.retirado_sintetico(38, 'RETIRADO SINTETICO TREINTA Y OCHO', pg_temp.dni(37));
  v_ficha := pg_temp.ficha(v_b38);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO TREINTA Y OCHO OTRO DNI', pg_temp.tel(38), pg_temp.dni(93));
  v_txt := pg_temp.exigir_intacto('B1-convertido-activo-por-dni-conservado', v_res, v_b38, v_ficha, 'ok:ya_es_cliente');
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(38)) <> 1 or exists (select 1 from crm.leads l where l.dni = pg_temp.dni(93)) then
    v_txt := v_txt || format(E'FALLO B1-convertido-activo-por-dni-conservado: %s leads con el teléfono 38 (debe ser 1) y %s con el DNI tecleado (debe ser 0): nació un SEGUNDO lead\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(38)), (select count(*) from crm.leads l where l.dni = pg_temp.dni(93)));
  end if;
  if (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = v_a37) is distinct from 'convertido|true' then
    v_txt := v_txt || E'FALLO B1-convertido-activo-por-dni-conservado: el convertido activo cambió\n';
  end if;
  perform pg_temp.reg('B1-convertido-activo-por-el-dni-conservado-bloquea', v_txt);
  perform pg_temp.medida(format('B1 (convertido activo por el DNI conservado): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));
  -- B2 (borde sin caso, ronda 3): un DESCARTADO ACTIVO con motivo de 0 días (pide_credito) dentro de sus 24 h, que casa SOLO por
  -- el DNI conservado (T=40, A=39): en esa ventana el verificador dice «libre» (la carencia es solo para tomar); la pieza tiene
  -- que responder «tomado» (nombrando al tenedor) o «en_bolsa» si el descarte lo dejó sin tenedor. Alta (T=40, B=94).
  v_a39 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_a39, 'DESCARTADO CERO DIAS TREINTA Y NUEVE', pg_temp.tel(39), pg_temp.dni(39));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead del caso B2 (%)', v_res;
  end if;
  if pg_temp.descartar(v_vend1, v_a39, 'pide_credito') <> '1' then
    raise exception 'ENSAYO ABORTADO: no se pudo descartar el lead del caso B2';
  end if;
  v_esperado := (select case when l.vendedor_id is null and l.asignado_supervisor_id is null then 'ok:en_bolsa' else 'ok:tomado' end
                   from crm.leads l where l.id = v_a39);
  perform pg_temp.medida(format('B2 (veredicto del verificador sobre el descartado ACTIVO de 0 días por su DNI, con otro teléfono): %s; se espera %s',
    private.verificar_disponibilidad_lead_impl(pg_temp.teln(40), pg_temp.dni(39)) ->> 'estado', v_esperado));
  v_b40 := pg_temp.retirado_sintetico(40, 'RETIRADO SINTETICO CUARENTA', pg_temp.dni(39));
  v_ficha := pg_temp.ficha(v_b40);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO CUARENTA OTRO DNI', pg_temp.tel(40), pg_temp.dni(94));
  v_txt := pg_temp.exigir_intacto('B2-descartado-activo-0-dias-por-dni-conservado', v_res, v_b40, v_ficha, v_esperado);
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(40)) <> 1 or exists (select 1 from crm.leads l where l.dni = pg_temp.dni(94)) then
    v_txt := v_txt || format(E'FALLO B2-descartado-activo-0-dias-por-dni-conservado: %s leads con el teléfono 40 (debe ser 1) y %s con el DNI tecleado (debe ser 0): nació un SEGUNDO lead\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(40)), (select count(*) from crm.leads l where l.dni = pg_temp.dni(94)));
  end if;
  if v_txt = '' and v_esperado = 'ok:tomado' and (substr(v_res, 4)::jsonb ->> 'vendedor') is distinct from (select p.nombre_completo from public.perfiles p where p.id = v_vend1) then
    v_txt := format(E'FALLO B2-descartado-activo-0-dias-por-dni-conservado: el veredicto «tomado» no nombra al tenedor VEND1 (%s)\n', substr(v_res, 4));
  end if;
  if (select l.etapa || '|' || l.activo::text from crm.leads l where l.id = v_a39) is distinct from 'descartado|true' then
    v_txt := v_txt || E'FALLO B2-descartado-activo-0-dias-por-dni-conservado: el descartado activo cambió\n';
  end if;
  perform pg_temp.reg('B2-descartado-activo-de-0-dias-por-el-dni-conservado-bloquea', v_txt);
  perform pg_temp.medida(format('B2 (descartado activo de 0 días por el DNI conservado): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));
  -- Veto asociado SOLO al DNI conservado: W (tel 24, DNI 24) marcado «No contactar» y retirado; retirado sintético (tel 25, DNI 24,
  -- sin veto); alta solo con el teléfono 25 ⇒ «no_contactar», la ficha intacta (el veto de la persona manda aunque no se tecleara su DNI).
  v_w24 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_w24, 'VETADO VEINTICUATRO', pg_temp.tel(24), pg_temp.dni(24));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el lead W del veto por DNI conservado (%)', v_res;
  end if;
  begin
    perform pg_temp.sesion(v_vend1);
    perform crm.marcar_no_contactar(v_w24, null);
    perform pg_temp.sesion(null);
  exception when others then
    raise exception 'ENSAYO ABORTADO: no se pudo marcar No contactar en W (% %)', sqlstate, sqlerrm;
  end;
  if pg_temp.retirar(v_ger, v_w24) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar W (veto por DNI conservado)'; end if;
  v_b24 := pg_temp.retirado_sintetico(25, 'RETIRADO SINTETICO VEINTICINCO', pg_temp.dni(24));
  v_ficha := pg_temp.ficha(v_b24);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO VEINTICINCO SOLO TELEFONO', pg_temp.tel(25), null);
  perform pg_temp.reg('3h-veto-asociado-solo-al-dni-conservado-bloquea', pg_temp.exigir_intacto('3h-veto-por-dni-conservado', v_res, v_b24, v_ficha, 'ok:no_contactar'));
  -- AR2-1 (auditor r2, P3-1; ronda 3): D-21 por la letra. Tecleado (T=35, A=DNI 35). R1 (T=35, SIN DNI, no enlazado, retirado) casa
  -- por el teléfono y sería el candidato; R2 (T=36, A, ENLAZADO a la persona P, retirado) casa solo por el DNI tecleado. Con la
  -- bandera de identidad APAGADA el verificador no ve a R2 (su bloque por identidad está gateado por la bandera) y dice «libre»:
  -- el núcleo tiene que dar el mismo juicio de identidad («ya_es_cliente», via identidad) y NO reactivar a R1 (P recibiría un
  -- lead activo mientras su ficha enlazada sigue retirada). La bandera se apaga y se vuelve a encender DENTRO de esta transacción
  -- (su trigger toma el candado exclusivo crm_flag_resolver_en_puertas, reentrante para esta misma sesión; todo se deshace).
  v_p35 := private.inversionista_resolver('DNI', pg_temp.dni(35), true, 'ensayo-bloque-2.4');
  v_r36 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_r36, 'ENLAZADO TREINTA Y SEIS', pg_temp.tel(36), pg_temp.dni(35));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado'
     or (select l.inversionista_id from crm.leads l where l.id = v_r36) is distinct from v_p35 then
    raise exception 'ENSAYO ABORTADO: el lead R2 del caso AR2-1 no nació enlazado a la persona % (%)', v_p35, v_res;
  end if;
  if pg_temp.retirar(v_ger, v_r36) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar el enlazado R2 del caso AR2-1'; end if;
  v_r35 := pg_temp.retirado(35, 'contactado', false, 'FICHA TREINTA Y CINCO SIN DNI');
  perform pg_temp.sesion(v_ger);
  update crm.multiempresa_flags set activo = false where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if private.resolver_en_puertas_bajo_candado() then
    raise exception 'ENSAYO ABORTADO: no se pudo apagar la bandera resolver_en_puertas dentro del ensayo (caso AR2-1)';
  end if;
  v_txt := private.verificar_disponibilidad_lead_impl(pg_temp.teln(35), pg_temp.dni(35)) ->> 'estado';
  perform pg_temp.medida(format('AR2-1 (bandera APAGADA; veredicto del verificador sobre T=35 + el DNI del enlazado R2): %s', v_txt));
  v_ficha := pg_temp.ficha(v_r35);
  v_ficha2 := pg_temp.ficha(v_r36);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'INTENTO TREINTA Y CINCO', pg_temp.tel(35), pg_temp.dni(35));
  v_txt := pg_temp.exigir_intacto('AR2-1-enlazado-por-dni-tecleado', v_res, v_r35, v_ficha, 'ok:ya_es_cliente');
  if pg_temp.ficha(v_r36) is distinct from v_ficha2 then
    v_txt := v_txt || E'FALLO AR2-1-enlazado-por-dni-tecleado: la ficha enlazada R2 cambió\n';
  end if;
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(35)) <> 1 then
    v_txt := v_txt || format(E'FALLO AR2-1-enlazado-por-dni-tecleado: %s leads con el teléfono 35 (debe seguir 1)\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(35)));
  end if;
  if v_txt = '' and (substr(v_res, 4)::jsonb ->> 'via') is distinct from 'identidad' then
    v_txt := format(E'FALLO AR2-1-enlazado-por-dni-tecleado: el juicio no es el de identidad (%s)\n', substr(v_res, 4));
  end if;
  perform pg_temp.reg('AR2-1-enlazado-por-el-dni-tecleado-bloquea-con-la-bandera-apagada', v_txt);
  perform pg_temp.medida(format('AR2-1 (bandera APAGADA; R1 por teléfono, R2 enlazado por el DNI tecleado): %s; leads con el teléfono 35=%s',
    case when v_res like 'ok|%' then substr(v_res, 4) else v_res end, (select count(*) from crm.leads l where l.telefono = pg_temp.teln(35))));
  perform pg_temp.sesion(v_ger);
  update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas';
  perform pg_temp.sesion(null);
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'ENSAYO ABORTADO: no se pudo volver a encender la bandera resolver_en_puertas (caso AR2-1)';
  end if;
  -- 3f (medida, no caso): el par que dejó el banco (L9: SOFTDEL retirado + REINGRESO activo del mismo número), si está.
  if exists (select 1 from crm.leads l where l.telefono = '+51910000020' and l.activo = false)
     and exists (select 1 from crm.leads l where l.telefono = '+51910000020' and l.activo = true) then
    v_ficha := (select to_jsonb(l) from crm.leads l where l.telefono = '+51910000020' and l.activo = false limit 1);
    v_res := pg_temp.alta(v_vend3, gen_random_uuid(), 'INTENTO SOBRE EL PAR DEL BANCO', '910000020', '98100020');
    perform pg_temp.medida(format('3f (par L9 del banco: retirado + activo del mismo número): %s; el retirado %s',
      case when v_res like 'ok|%' then 'estado=' || (substr(v_res, 4)::jsonb ->> 'estado') else v_res end,
      case when (select to_jsonb(l) from crm.leads l where l.id = (v_ficha ->> 'id')::uuid) = v_ficha then 'sigue intacto' else 'CAMBIÓ' end));
  else
    perform pg_temp.medida('3f (par L9 del banco): ausente en este laboratorio');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 4b/4c/4d. El destino que el alta ya calcula: la bandeja del supervisor, el analista elegido por Gerencia; dos retirados.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l10 := pg_temp.retirado(10, 'propuesta_enviada', true, 'FICHA DIEZ');
  v_pid10 := gen_random_uuid();
  v_res := pg_temp.alta(v_sup1, v_pid10, 'REINGRESO DIEZ POR SUP1', pg_temp.tel(10), pg_temp.dni(10));
  perform pg_temp.reg('4b-supervisor-parquea-en-su-bandeja',
    pg_temp.exigir_reactivado('4b-supervisor-parquea', v_res, v_l10, v_pid10, v_sup1, null, v_sup1, 'propuesta_enviada', 1, v_vend1, 'propuesta_enviada',
                              pg_temp.teln(10), pg_temp.dni(10)));
  -- 6d. OTRO supervisor reintenta con el MISMO p_id y el MISMO payload (los dos parquean: lo tecleado coincide byte a byte):
  --     solo el actor distingue el reintento legítimo del ajeno ⇒ 22023, y la ficha no cambia.
  v_ficha := pg_temp.ficha(v_l10);
  v_res := pg_temp.alta(v_sup2, v_pid10, 'REINGRESO DIEZ POR SUP1', pg_temp.tel(10), pg_temp.dni(10));
  perform pg_temp.reg('6d-mismo-p_id-otro-supervisor', case when v_res like '22023|%' and pg_temp.ficha(v_l10) = v_ficha then ''
    else format(E'FALLO 6d-mismo-p_id-otro-supervisor: se esperaba 22023 con la ficha intacta y llegó %s (ficha %s)\n', v_res,
                case when pg_temp.ficha(v_l10) = v_ficha then 'intacta' else 'CAMBIADA' end) end);
  v_l11 := pg_temp.retirado(11, 'nuevo', true, 'FICHA ONCE');
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_ger, v_pid, 'REINGRESO ONCE POR GERENCIA', pg_temp.tel(11), pg_temp.dni(11), 'nuevo', v_vend3);
  perform pg_temp.reg('4c-gerencia-asigna-a-vend3',
    pg_temp.exigir_reactivado('4c-gerencia-asigna', v_res, v_l11, v_pid, v_ger, v_vend3, null, 'nuevo', 1, v_vend1, 'nuevo',
                              pg_temp.teln(11), pg_temp.dni(11)));
  -- 4e (ronda 2): Gerencia SIN destino ⇒ la ficha reactivada va a la cola global (sin vendedor ni bandeja, sin episodio abierto),
  -- con su etapa y ciclo conservados.
  v_l29 := pg_temp.retirado(29, 'contactado', true, 'FICHA VEINTINUEVE');
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_ger, v_pid, 'REINGRESO VEINTINUEVE POR GERENCIA SIN DESTINO', pg_temp.tel(29), pg_temp.dni(29), 'nuevo', null);
  perform pg_temp.reg('4e-gerencia-sin-destino-cola-global',
    pg_temp.exigir_reactivado('4e-gerencia-sin-destino', v_res, v_l29, v_pid, v_ger, null, null, 'contactado', 1, v_vend1, 'contactado',
                              pg_temp.teln(29), pg_temp.dni(29)));
  -- 4f (ronda 2): un retirado en `reunion_agendada` conserva la etapa (D-15: «en otra etapa queda igual») y el ciclo.
  v_l30 := pg_temp.retirado(30, 'reunion_agendada', true, 'FICHA TREINTA');
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO TREINTA', pg_temp.tel(30), pg_temp.dni(30));
  perform pg_temp.reg('4f-reunion-agendada-conserva-la-etapa',
    pg_temp.exigir_reactivado('4f-reunion-agendada', v_res, v_l30, v_pid, v_vend2, v_vend2, null, 'reunion_agendada', 1, v_vend1, 'reunion_agendada',
                              pg_temp.teln(30), pg_temp.dni(30)));
  -- 4d. Dos retirados: uno casa por el teléfono (DNI 12) y otro por el DNI tecleado (DNI 14, teléfono 13): manda el del teléfono;
  --     el otro queda retirado y se AVISA (clave `aviso` en la respuesta e id del otro en el rastro).
  v_a12 := pg_temp.retirado(12, 'nuevo', true, 'FICHA DOCE');
  v_b13 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend1, v_b13, 'FICHA TRECE', pg_temp.tel(13), pg_temp.dni(14));
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') <> 'creado' then
    raise exception 'ENSAYO ABORTADO: no se pudo crear el segundo retirado del caso 4d (%)', v_res;
  end if;
  if pg_temp.retirar(v_ger, v_b13) <> '1' then raise exception 'ENSAYO ABORTADO: no se pudo retirar el segundo retirado del caso 4d'; end if;
  v_ficha := pg_temp.ficha(v_b13);
  v_pid12 := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid12, 'REINGRESO DOCE', pg_temp.tel(12), pg_temp.dni(14));
  perform pg_temp.reg('4d-dos-retirados-manda-el-telefono',
    pg_temp.exigir_reactivado('4d-telefono-manda', v_res, v_a12, v_pid12, v_vend2, v_vend2, null, 'nuevo', 1, v_vend1, 'nuevo',
                              pg_temp.teln(12), pg_temp.dni(12)));
  v_txt := '';
  if pg_temp.ficha(v_b13) is distinct from v_ficha then v_txt := v_txt || 'el otro retirado (por DNI) cambió; '; end if;
  select * into v_a from crm.actividades a where a.id = v_pid12;
  -- A-8: el rastro dice que había otro retirado (booleano), sin exponer su id.
  if v_a.id is null or (v_a.metadata ->> 'otro_retirado')::boolean is distinct from true or v_a.metadata ? 'otro_retirado_dni' then
    v_txt := v_txt || format('el rastro no avisa del otro retirado como otro_retirado=true sin id (otro_retirado=%s, otro_retirado_dni=%s); ',
      v_a.metadata ->> 'otro_retirado', v_a.metadata ->> 'otro_retirado_dni');
  end if;
  if v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'aviso') is distinct from 'otro_lead_retirado_con_ese_dni' then v_txt := v_txt || 'la respuesta no trae el aviso; '; end if;
  perform pg_temp.reg('4d-aviso-del-otro-retirado', case when v_txt = '' then '' else format(E'FALLO 4d-aviso: %s\n', v_txt) end);
  perform pg_temp.medida(format('4d (respuesta con dos retirados): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));
  -- C-3: el replay (mismo p_id, mismo payload) repite la MISMA respuesta, aviso incluido, sin segundo cambio ni segundo rastro.
  v_ficha := pg_temp.ficha(v_a12);
  v_ficha2 := pg_temp.ficha(v_b13);
  v_res := pg_temp.alta(v_vend2, v_pid12, 'REINGRESO DOCE', pg_temp.tel(12), pg_temp.dni(14));
  v_txt := '';
  if v_res not like 'ok|%' or (substr(v_res, 4)::jsonb ->> 'estado') is distinct from 'reutilizado'
     or (substr(v_res, 4)::jsonb ->> 'lead_id')::uuid is distinct from v_a12 then
    v_txt := v_txt || format('el replay no devolvió «reutilizado» con la misma ficha (%s); ', v_res);
  elsif (substr(v_res, 4)::jsonb ->> 'aviso') is distinct from 'otro_lead_retirado_con_ese_dni' then
    v_txt := v_txt || format('el replay perdió el aviso (%s); ', substr(v_res, 4));
  end if;
  if pg_temp.ficha(v_a12) is distinct from v_ficha or pg_temp.ficha(v_b13) is distinct from v_ficha2 then v_txt := v_txt || 'el replay cambió una ficha; '; end if;
  if (select count(*) from crm.actividades a where a.lead_id = v_a12 and a.metadata ->> 'evento' = 'reactivacion_alta') <> 1 then v_txt := v_txt || 'el replay dejó otro rastro; '; end if;
  perform pg_temp.reg('4d-replay-repite-el-aviso (C-3)', case when v_txt = '' then '' else format(E'FALLO 4d-replay: %s\n', v_txt) end);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 8. Un rol sin permiso sigue recibiendo 42501 (y la ficha retirada no se toca); después VEND2 sí la reactiva.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l15 := pg_temp.retirado(15, 'nuevo', true, 'FICHA QUINCE');
  v_ficha := pg_temp.ficha(v_l15);
  v_res := pg_temp.alta(v_coord, gen_random_uuid(), 'INTENTO COORD', pg_temp.tel(15), pg_temp.dni(15));
  perform pg_temp.reg('8-coordinador-42501', pg_temp.exigir_intacto('8-coordinador', v_res, v_l15, v_ficha, 'err:42501'));
  v_res := pg_temp.alta(v_inactivo, gen_random_uuid(), 'INTENTO INACTIVO', pg_temp.tel(15), pg_temp.dni(15));
  perform pg_temp.reg('8-membresia-inactiva-42501', pg_temp.exigir_intacto('8-inactivo', v_res, v_l15, v_ficha, 'err:42501'));
  v_res := pg_temp.alta(v_admin, gen_random_uuid(), 'INTENTO ADMIN SIN CRM', pg_temp.tel(15), pg_temp.dni(15));
  perform pg_temp.reg('8-admin-sin-rol-crm-42501', pg_temp.exigir_intacto('8-admin-sin-crm', v_res, v_l15, v_ficha, 'err:42501'));
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO QUINCE', pg_temp.tel(15), pg_temp.dni(15));
  perform pg_temp.reg('8-luego-vend2-reactiva',
    pg_temp.exigir_reactivado('8-luego-vend2', v_res, v_l15, v_pid, v_vend2, v_vend2, null, 'nuevo', 1, v_vend1, 'nuevo',
                              pg_temp.teln(15), pg_temp.dni(15)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 9. Por la puerta del documento (crm.crear_lead_documento_fn): CE/pasaporte no se fija sobre la ficha reactivada
  --    (se conservan sus datos; decisión del ensayo); con DNI, igual que el alta directa.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l16 := pg_temp.retirado(16, 'nuevo', false, 'FICHA DIECISEIS SIN DOCUMENTO');
  select count(*) into v_cnt_inv from crm.inversionistas;
  select count(*) into v_cnt_idf from crm.inversionista_identificadores;
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta_doc(v_vend2, jsonb_build_object('id', v_pid, 'nombre_completo', 'REINGRESO DIECISEIS CE',
             'telefono', pg_temp.tel(16), 'origen', 'formulario', 'monto_estimado', 5000, 'moneda', 'PEN'), 'CE', '001234567');
  perform pg_temp.reg('9-documento-ce-reactiva',
    pg_temp.exigir_reactivado('9-documento-ce', v_res, v_l16, v_pid, v_vend2, v_vend2, null, 'nuevo', 1, v_vend1, 'nuevo',
                              pg_temp.teln(16), null));
  v_txt := '';
  select * into v_l from crm.leads l where l.id = v_l16;
  if v_l.dni is not null or v_l.inversionista_id is not null then v_txt := v_txt || 'la ficha recibió documento o enlace; '; end if;
  if (select count(*) from crm.inversionistas) <> v_cnt_inv or (select count(*) from crm.inversionista_identificadores) <> v_cnt_idf then
    v_txt := v_txt || 'nació una identidad o un identificador; ';
  end if;
  perform pg_temp.reg('9-ce-no-fija-documento-sobre-la-ficha', case when v_txt = '' then '' else format(E'FALLO 9-ce-no-fija: %s\n', v_txt) end);
  -- (medida, declarado) el tipo de documento CE no llega al alta (crear_lead_documento_fn pasa p_dni nulo y nada más): el
  -- rastro no puede anotarlo y el replay con OTRO número de CE se trata como el mismo alta. Cambio mínimo propuesto para la fase 4
  -- en el informe.
  select * into v_a from crm.actividades a where a.id = v_pid;
  v_ficha := pg_temp.ficha(v_l16);
  v_res := pg_temp.alta_doc(v_vend2, jsonb_build_object('id', v_pid, 'nombre_completo', 'REINGRESO DIECISEIS CE',
             'telefono', pg_temp.tel(16), 'origen', 'formulario', 'monto_estimado', 5000, 'moneda', 'PEN'), 'CE', '001234568');
  perform pg_temp.medida(format('9 (CE): tipo_documento en el rastro=%s; replay con OTRO número de CE y el mismo p_id ⇒ %s; ficha %s',
    coalesce(v_a.metadata -> 'tecleado' ->> 'tipo_documento', 'null'),
    case when v_res like 'ok|%' then 'estado=' || (substr(v_res, 4)::jsonb ->> 'estado') else v_res end,
    case when pg_temp.ficha(v_l16) = v_ficha then 'intacta' else 'CAMBIÓ' end));
  v_l17 := pg_temp.retirado(17, 'nuevo', true, 'FICHA DIECISIETE');
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta_doc(v_vend2, jsonb_build_object('id', v_pid, 'nombre_completo', 'REINGRESO DIECISIETE DNI',
             'telefono', pg_temp.tel(17), 'origen', 'formulario', 'monto_estimado', 5000, 'moneda', 'PEN'), 'DNI', pg_temp.dni(17));
  perform pg_temp.reg('9-documento-dni-reactiva',
    pg_temp.exigir_reactivado('9-documento-dni', v_res, v_l17, v_pid, v_vend2, v_vend2, null, 'nuevo', 1, v_vend1, 'nuevo',
                              pg_temp.teln(17), pg_temp.dni(17)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- C-5 (ronda 2). Solo los índices de contacto vivo (uq_leads_telefono_vivo / uq_leads_dni_vivo) se tratan como carrera; otro
  -- 23505 nacido del UPDATE o de sus disparadores se PROPAGA (el alta falla y no inserta nada). Fixture: un índice único temporal
  -- (vive y muere en esta transacción) sobre el nombre de dos retirados descartados homónimos, que solo afecta a filas activas
  -- con ciclo >= 2 (lo que deja una reactivación desde «descartado», nunca un INSERT nuevo): la primera reactivación entra; la
  -- segunda choca con ese índice ajeno ⇒ 23505 al llamador, ficha intacta, un solo lead por contacto.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l26 := pg_temp.retirado(26, 'nuevo', true, 'FICHA HOMONIMA 23505', null, 5000, 'pide_credito');
  v_l27 := pg_temp.retirado(27, 'nuevo', true, 'FICHA HOMONIMA 23505', null, 5000, 'pide_credito');
  create unique index ens_23505_ajeno on crm.leads (nombre_completo)
    where activo = true and ciclo_actual >= 2 and nombre_completo = 'FICHA HOMONIMA 23505';
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO VEINTISEIS', pg_temp.tel(26), pg_temp.dni(26));
  perform pg_temp.reg('C5-primera-homonima-reactiva',
    pg_temp.exigir_reactivado('C5-primera-homonima', v_res, v_l26, v_pid, v_vend2, v_vend2, null, 'nuevo', 2, v_vend1, 'descartado',
                              pg_temp.teln(26), pg_temp.dni(26)));
  v_ficha := pg_temp.ficha(v_l27);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO VEINTISIETE', pg_temp.tel(27), pg_temp.dni(27));
  v_txt := pg_temp.exigir_intacto('C5-23505-ajeno-se-propaga', v_res, v_l27, v_ficha, 'err:23505');
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(27)) <> 1 then
    v_txt := v_txt || format(E'FALLO C5-23505-ajeno-se-propaga: %s leads con el teléfono 27 (debe ser 1): el 23505 ajeno se tragó como carrera de contacto y el alta insertó un segundo lead\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(27)));
  end if;
  if v_txt = '' and position('ens_23505_ajeno' in v_res) = 0 then
    v_txt := format(E'FALLO C5-23505-ajeno-se-propaga: el 23505 no es el del índice ajeno (%s)\n', v_res);
  end if;
  perform pg_temp.reg('C5-23505-ajeno-se-propaga', v_txt);
  drop index crm.ens_23505_ajeno;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- R2-2 (Codex r2 hipótesis / auditor r2 P3-2; ronda 3). Solo el CHECK leads_monto_estimado_valido (A-2) se trata como «la ficha
  -- no puede salir así del retiro»; cualquier otro 23514 nacido del UPDATE de la reactivación se PROPAGA al llamador: el alta
  -- falla, la ficha queda intacta y hay un solo lead por contacto. Fixture: la restricción ens_23514_ajeno sembrada al empezar
  -- el oráculo (la viola una ficha «FICHA CHECK 23514» activa a nombre de VEND2; nace a nombre de VEND1). (Sin la corrección, el
  -- núcleo lo captura como veredicto fresco, el verificador dice «libre» sobre el retirado y el alta INSERTA un segundo lead.)
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l34 := pg_temp.retirado(34, 'contactado', true, 'FICHA CHECK 23514');
  v_ficha := pg_temp.ficha(v_l34);
  v_res := pg_temp.alta(v_vend2, gen_random_uuid(), 'REINGRESO TREINTA Y CUATRO', pg_temp.tel(34), pg_temp.dni(34));
  v_txt := pg_temp.exigir_intacto('R2-2-check-ajeno-se-propaga', v_res, v_l34, v_ficha, 'err:23514');
  if (select count(*) from crm.leads l where l.telefono = pg_temp.teln(34)) <> 1 then
    v_txt := v_txt || format(E'FALLO R2-2-check-ajeno-se-propaga: %s leads con el teléfono 34 (debe ser 1): el 23514 ajeno se tragó como veredicto fresco y el alta insertó un SEGUNDO lead\n',
      (select count(*) from crm.leads l where l.telefono = pg_temp.teln(34)));
  end if;
  if v_txt = '' and position('ens_23514_ajeno' in v_res) = 0 then
    v_txt := format(E'FALLO R2-2-check-ajeno-se-propaga: el 23514 no es el de la restricción ajena (%s)\n', v_res);
  end if;
  perform pg_temp.reg('R2-2-check-ajeno-se-propaga', v_txt);
  perform pg_temp.medida(format('R2-2 (CHECK ajeno en el UPDATE de la reactivación): %s', case when v_res like 'ok|%' then substr(v_res, 4) else v_res end));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- A-2 (ronda 2). Retirado de BASE CARGADA (origen base_cargada, descartado con motivo base_cargada, capital VACÍO) ⇒ se
  -- reactiva como «nuevo» con ciclo 2 y el capital TECLEADO (el CHECK leads_monto_estimado_valido solo admite capital nulo en un
  -- descartado de base); el origen de la ficha no cambia.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_l28 := pg_temp.retirado_sintetico(28, 'FICHA DE BASE VEINTIOCHO', pg_temp.dni(28), 'base_cargada');
  perform pg_temp.medida(format('A-2 (veredicto del verificador sobre el retirado de base cargada sin capital): %s',
    private.verificar_disponibilidad_lead_impl(pg_temp.teln(28), pg_temp.dni(28)) ->> 'estado'));
  v_pid := gen_random_uuid();
  v_res := pg_temp.alta(v_vend2, v_pid, 'REINGRESO VEINTIOCHO', pg_temp.tel(28), pg_temp.dni(28), 'nuevo', null, null, null, 7777);
  v_txt := pg_temp.exigir_reactivado('A2-base-cargada-sin-capital', v_res, v_l28, v_pid, v_vend2, v_vend2, null, 'nuevo', 2, null, 'descartado',
                                     pg_temp.teln(28), pg_temp.dni(28));
  select * into v_l from crm.leads l where l.id = v_l28;
  if v_txt = '' and (v_l.monto_estimado is distinct from 7777 or v_l.origen <> 'base_cargada') then
    v_txt := format(E'FALLO A2-base-cargada-sin-capital: capital %s (se esperaba el tecleado 7777) u origen %s (debe seguir base_cargada)\n', v_l.monto_estimado, v_l.origen);
  end if;
  perform pg_temp.reg('A2-base-cargada-sin-capital-se-reactiva-con-el-capital-tecleado', v_txt);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 7. Concurrencia: NO EJECUTADO con dos conexiones (el ensayo corre en una sola sesión y sin credenciales para abrir
  --    otra). Lo que sí se mide: el núcleo toma la fila del retirado con FOR UPDATE (lectura del cuerpo, no de la conducta).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  if v_nucleo is null then
    perform pg_temp.reg('7-for-update', E'FALLO 7-for-update: el núcleo private.alta_reactivar_retirado no existe\n');
  else
    -- Solo la sentencia real (`for update;`), no los comentarios que la mencionan.
    select (length(p.prosrc) - length(replace(lower(p.prosrc), 'for update;', ''))) / length('for update;') into v_n from pg_proc p where p.oid = v_nucleo;
    perform pg_temp.reg('7-for-update', case when v_n >= 1 then ''
      else format(E'FALLO 7-for-update: el núcleo no toma la fila del retirado con FOR UPDATE (sentencias «for update;»=%s)\n', v_n) end);
  end if;
  perform pg_temp.medida('7 (dos altas simultáneas): NO EJECUTADO — una sola conexión en el ensayo; el alta serializa por bloquear_contactos_lead y el núcleo toma FOR UPDATE y recomprueba activo=false');

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 10. Catálogo: lo que la migración tiene que conservar, lo que no puede tocar y la ficha del núcleo nuevo.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  if not exists (select 1 from pg_proc p where p.oid = v_alta and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                   and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_alta)
        is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']
     or has_function_privilege('anon', v_alta, 'EXECUTE') or has_function_privilege('service_role', v_alta, 'EXECUTE') then
    perform pg_temp.reg('10a', E'FALLO 10a: crm.crear_lead_si_disponible cambió de dueño, de atributos (DEFINER, search_path vacío, lock_timeout) o de permisos (anon/service_role con EXECUTE, falta authenticated o EXECUTE con opción de concesión)\n');
  else
    perform pg_temp.reg('10a crm.crear_lead_si_disponible: ficha y ACL', '');
  end if;
  if v_nucleo is null then
    perform pg_temp.reg('10b', E'FALLO 10b: el núcleo private.alta_reactivar_retirado no existe\n');
  elsif not exists (select 1 from pg_proc p where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.proconfig @> array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    perform pg_temp.reg('10b', E'FALLO 10b: el núcleo no es DEFINER de postgres con search_path vacío y EXECUTE solo para postgres\n');
  else
    perform pg_temp.reg('10b private.alta_reactivar_retirado: ficha y ACL', '');
  end if;
  -- 10b2 (ronda 2): la pieza del veredicto por lo conservado, con la misma ficha y ACL que el núcleo.
  if v_helper is null then
    perform pg_temp.reg('10b2', E'FALLO 10b2: la pieza private.alta_reactivar_bloqueo_conservado no existe\n');
  elsif not exists (select 1 from pg_proc p where p.oid = v_helper and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.proconfig @> array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_helper)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_helper, 'EXECUTE') or has_function_privilege('authenticated', v_helper, 'EXECUTE')
     or has_function_privilege('service_role', v_helper, 'EXECUTE') then
    perform pg_temp.reg('10b2', E'FALLO 10b2: private.alta_reactivar_bloqueo_conservado no es DEFINER de postgres con search_path vacío y EXECUTE solo para postgres\n');
  else
    perform pg_temp.reg('10b2 private.alta_reactivar_bloqueo_conservado: ficha y ACL', '');
  end if;
  -- 10c. El verificador no se toca: huella del cuerpo y la compuesta que fija la carga de bases (20261004184501:178-183).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from '683c16fdcb08377af860f1aa0a18f3a1'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from '48c51531ebc8db1a41f5a816241920da'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    perform pg_temp.reg('10c', E'FALLO 10c: el verificador private.verificar_disponibilidad_lead_impl cambió (la carga de bases dejaría de instalarse)\n');
  else
    perform pg_temp.reg('10c verificador intacto (huella de la carga de bases)', '');
  end if;
  -- 10d. Lo que NO se toca (puertas y piezas reutilizadas), con su huella.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.tomar_lead_libre(text,text)')) is distinct from 'f755d63f59dfc0e8959fefb83c7b9f9a'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reabrir_lead_fn(uuid)')) is distinct from '65b4b0924da38eaa2c6b7dc42f44ee79'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)')) is distinct from 'bf59d77929877e7a5eb46704d934363e'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_lead_documento_fn(jsonb,text,text)')) is distinct from '3ca9432b3d83061adfda6314633bdc3e'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_tenencia()')) is distinct from '763323f5f4ecaa735ce78cbccabad894'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_reapertura_solo_rpc()')) is distinct from 'ec1e53826887925cad0c41c319e967fb'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_asignaciones()')) is distinct from '188bb4c9fd7fc571a959023e1abec444'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.juicio_reapertura(uuid,text,text)')) is distinct from '020f3792076f0c756b1cc12c5f1d5116'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.enlazar_lead_reabierto(uuid,uuid)')) is distinct from '891aa806bff7cd422013d95ab2d88d11'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.bloquear_personas_de_leads(uuid[],text)')) is distinct from '14727d8ae95fe727f5ddc81f9a92c9fd'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.es_destino_crm_activo(uuid,text[])')) is distinct from 'c53747fcaf5fd17072669f85decf4546' then
    perform pg_temp.reg('10d', E'FALLO 10d: cambió algo que no se toca (tomar_lead_libre, reabrir_lead_fn, reactivar_lead_base, crear_lead_documento_fn, guard de tenencia, reapertura solo por RPC, ledger de asignaciones, juicio_reapertura, enlazar_lead_reabierto, bloquear_personas_de_leads o es_destino_crm_activo)\n');
  else
    perform pg_temp.reg('10d huellas de lo que no se toca', '');
  end if;
  -- 10f (A-5, ronda 2): el núcleo exige p_actor = auth.uid() (defensa en profundidad: su ACL ya lo reserva a postgres). Con un
  -- actor ajeno ⇒ 42501 antes de mirar nada; con el propio y un veredicto bloqueante ⇒ null (el gate no es «siempre 42501»).
  if v_nucleo is null then
    perform pg_temp.reg('10f', E'FALLO 10f: el núcleo private.alta_reactivar_retirado no existe\n');
  else
    v_res := pg_temp.nucleo_directo(v_vend2, v_vend3, pg_temp.tel(1), pg_temp.dni(1));
    v_txt := case when v_res like '42501|%' then '' else format('con p_actor ajeno a la sesión se esperaba 42501 y llegó %s; ', v_res) end;
    v_res := pg_temp.nucleo_directo(v_vend2, v_vend2, pg_temp.tel(1), pg_temp.dni(1));
    if v_res <> 'ok|null' then v_txt := v_txt || format('con el propio actor y veredicto «tomado» se esperaba null y llegó %s; ', v_res); end if;
    perform pg_temp.reg('10f el núcleo exige p_actor = auth.uid()', case when v_txt = '' then '' else format(E'FALLO 10f: %s\n', v_txt) end);
  end if;
  perform pg_temp.medida(format('10e: md5(prosrc) del alta = %s · md5(definición) = %s · núcleo md5(prosrc) = %s · md5(definición) = %s · pieza conservado md5(prosrc) = %s · md5(definición) = %s',
    (select md5(p.prosrc) from pg_proc p where p.oid = v_alta),
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_alta),
    coalesce((select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), 'ausente'),
    coalesce((select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo), 'ausente'),
    coalesce((select md5(p.prosrc) from pg_proc p where p.oid = v_helper), 'ausente'),
    coalesce((select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_helper), 'ausente')));

  -- ── Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ───────────────────────────────────────────────
  begin
    set constraints all immediate;
  exception when others then
    perform pg_temp.reg('11', format(E'FALLO 11: algo de lo escrito no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
  end;

  -- ── Veredicto, y rollback SIEMPRE ───────────────────────────────────────────────────────────────────────────────
  raise exception E'ENSAYO %:\n%\n%\n%(rollback a propósito — nada queda escrito)',
    case when current_setting('ensayo.fallos')::integer = 0 then 'VERDE — 0 fallos'
         else format('ROJO — %s fallo(s)', current_setting('ensayo.fallos')) end,
    current_setting('ensayo.informe'),
    current_setting('ensayo.medidas'),
    current_setting('ensayo.oks');
end;
$ensayo$;

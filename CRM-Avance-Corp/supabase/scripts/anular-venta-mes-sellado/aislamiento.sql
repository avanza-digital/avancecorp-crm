-- ENSAYO DE AISLAMIENTO de «No se puede anular una venta de un mes sellado» — el detector solo admite READ COMMITTED.
--
-- `armar-ensayo.mjs --aislamiento` pega este archivo detrás de la migración real dentro de UNA transacción que empieza con
-- `begin isolation level repeatable read;` y termina en `rollback`. En otro modo de transacción el detector
-- `private.mes_sellado_de_venta` tiene que negarse con SQLSTATE 0A000 ANTES de resolver nada (patrón de 20261002163158):
-- con una fotografía fija, esperar el cerrojo del mes no renovaría lo leído y un sello recién hecho se vería «abierto».
--
-- Se siembra una venta de un mes ABIERTO (el guardián se evalúa antes de mirar el mes: da igual cuál sea) por cada puerta,
-- se llama a cada una como la `gerencia` histórica del banco y se exige 0A000 con su mensaje y la foto intacta. Sin la
-- migración (o con la guarda quitada) la puerta ACEPTA en repeatable read: eso es lo que este ensayo mide.
--
-- El oráculo principal (`pruebas.sql`) corre en READ COMMITTED y comprueba al empezar que lo está: allí la guarda no salta.

set local statement_timeout = '120s';

do $aislamiento$
declare
  v_aisl    text := current_setting('transaction_isolation');
  v_ger     uuid;
  v_vend    uuid;
  v_lead_a  uuid := gen_random_uuid();
  v_lead_e  uuid := gen_random_uuid();
  v_cierre  uuid := gen_random_uuid();
  v_cuando  timestamptz := now();
  v_fallos  text := '';
  v_oks     text := '';
  v_antes   text;
  v_despues text;
  v_estado  text;
  v_msg     text;
begin
  if v_aisl <> 'repeatable read' then
    raise exception 'ENSAYO ABORTADO: esta transacción debía ir en repeatable read y va en %', v_aisl;
  end if;
  select p.id into v_ger  from public.perfiles p where p.nombre_completo = 'PASO08 GERENCIA';
  select p.id into v_vend from public.perfiles p where p.nombre_completo = 'PASO08 VEND1';
  if v_ger is null or v_vend is null or private.rol_crm(v_ger) is distinct from 'gerencia' then
    raise exception 'ENSAYO ABORTADO: faltan actores (gerencia=%, vend1=%) o la gerencia no es gerencia', v_ger, v_vend;
  end if;

  -- Siembra con los triggers apagados solo aquí: una venta de Avance y una venta con cierre externo inicial, del mes en curso.
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, origen, etapa, convertido_en, vendedor_id, contrato_id, activo, monto_estimado)
  values (v_lead_a, 'ENSAYO aislamiento avance', '99980000001', 'landing', 'convertido', v_cuando, v_vend, null, true, 1000),
         (v_lead_e, 'ENSAYO aislamiento externo', '99980000002', 'landing', 'convertido', v_cuando, v_vend, null, true, 1000);
  insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
      sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado,
      resultado_en, finalizado_en, finalizado_por, motivo_cierre)
  select l, 1, 1, v_vend, 'asignado', v_cuando - interval '5 days', 'PEN', 'landing', v_cuando - interval '5 days', gen_random_uuid(),
         v_cuando, v_cuando, 'convertido', v_cuando, v_cuando, v_vend, 'convertido'
  from unnest(array[v_lead_a, v_lead_e]) l;
  insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
      numero_transaccion, vendedor_id, creado_por, es_cierre_inicial, lead_id, fecha_comercial, fecha_imputacion)
  values (v_cierre, 'qorilazo', 1000, 'PEN', 'DNI', '70999001', 'PERSONA ENSAYO AISLAMIENTO', 'ENS-AISL', v_vend, v_vend, true, v_lead_e,
          (v_cuando at time zone 'America/Lima')::date, (v_cuando at time zone 'America/Lima')::date);
  set local session_replication_role = origin;

  -- Sesión de la gerencia (las dos formas de los claims).
  perform set_config('request.jwt.claim.sub', v_ger::text, true),
          set_config('request.jwt.claims', json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);

  v_antes := format('%s|%s|%s|%s',
    (select md5(coalesce(string_agg(a::text, ',' order by a.id), '-')) from crm.cierres_avance_anulados a where a.lead_id = v_lead_a),
    (select md5(ce::text) from crm.cierres_externos ce where ce.id = v_cierre),
    (select md5(coalesce(string_agg(a::text, ',' order by a.id), '-')) from crm.actividades a where a.lead_id in (v_lead_a, v_lead_e)),
    (select md5(coalesce(string_agg(j::text, ',' order by j.id), '-')) from crm.ajustes_mes_cerrado j));

  begin
    perform crm.anular_cierre_avance(v_lead_a, 'Ensayo de aislamiento');
    v_fallos := v_fallos || E'FALLO AISLAMIENTO (avance): la puerta ACEPTÓ anular en repeatable read\n';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_estado <> '0A000' or v_msg <> 'La anulación de una venta no admite este modo de transacción' then
      v_fallos := v_fallos || format(E'FALLO AISLAMIENTO (avance): rechazó, pero no con 0A000 y su mensaje: %s|%s\n', v_estado, v_msg);
    else
      v_oks := v_oks || E'ok aislamiento avance → 0A000\n';
    end if;
  end;
  begin
    perform crm.anular_cierre_externo(v_cierre, 'Ensayo de aislamiento');
    v_fallos := v_fallos || E'FALLO AISLAMIENTO (externo): la puerta ACEPTÓ anular en repeatable read\n';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_estado <> '0A000' or v_msg <> 'La anulación de una venta no admite este modo de transacción' then
      v_fallos := v_fallos || format(E'FALLO AISLAMIENTO (externo): rechazó, pero no con 0A000 y su mensaje: %s|%s\n', v_estado, v_msg);
    else
      v_oks := v_oks || E'ok aislamiento externo → 0A000\n';
    end if;
  end;

  v_despues := format('%s|%s|%s|%s',
    (select md5(coalesce(string_agg(a::text, ',' order by a.id), '-')) from crm.cierres_avance_anulados a where a.lead_id = v_lead_a),
    (select md5(ce::text) from crm.cierres_externos ce where ce.id = v_cierre),
    (select md5(coalesce(string_agg(a::text, ',' order by a.id), '-')) from crm.actividades a where a.lead_id in (v_lead_a, v_lead_e)),
    (select md5(coalesce(string_agg(j::text, ',' order by j.id), '-')) from crm.ajustes_mes_cerrado j));
  if v_despues is distinct from v_antes then
    v_fallos := v_fallos || E'FALLO AISLAMIENTO (foto): algo quedó escrito tras las llamadas en repeatable read\n';
  else
    v_oks := v_oks || E'ok aislamiento foto intacta\n';
  end if;

  raise exception E'ENSAYO % (aislamiento):\n%\n%(rollback a propósito — nada queda escrito)',
    case when v_fallos = '' then 'VERDE — 0 fallos' else format('ROJO — %s fallo(s)', (length(v_fallos) - length(replace(v_fallos, E'\n', '')))) end,
    v_fallos, v_oks;
end;
$aislamiento$;

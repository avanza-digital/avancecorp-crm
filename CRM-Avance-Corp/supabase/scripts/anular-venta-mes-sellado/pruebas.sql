-- ORÁCULO de «No se puede anular una venta de un mes sellado» — se ejecuta en el LABORATORIO (banco Docker
-- local), NUNCA contra producción, y no escribe nada.
--
-- La regla (decisiones D-09, D-14 y D-17 de Miguel, 2026-10-06): anular la conversión (el cierre inicial) cuyo mes
-- de venta tiene fila en `crm.periodos_cerrados` se rechaza con P0409 y no escribe nada, por `crm.anular_cierre_avance`
-- y por `crm.anular_cierre_externo` (solo si es cierre inicial); la única excepción es quien es a la vez admin o
-- superadmin del Portal y Gerencia del CRM, que anula SIN ajuste y dejando rastro en la actividad. Si el mes de la
-- venta NO se puede determinar (sin acreditación, sin episodio y sin fecha de conversión), se rechaza igual (falla
-- cerrado) con su propio mensaje; el exento pasa con rastro 'desconocido'.
--
-- El escenario se levanta contra la FORMA real del esquema (sus CHECK, sus triggers, la jerarquía y los actores del
-- banco) y las puertas se llaman de verdad. Para SELLAR un mes dentro del ensayo se sigue `supabase/scripts/test-cierre-mes.sql`
-- (bloques 4-7): `crm.cerrar_periodo` real para junio y julio de 2026 (ya pasada su ventana, sin mover el reloj). El
-- sello de septiembre de 2026 NO se puede pedir a `cerrar_periodo` (su ventana abre el 10/10): se inserta la fila en
-- `crm.periodos_cerrados` con los triggers apagados, como hace `supabase/scripts/eliminar-inversion/test-eliminar-inversion.sql`
-- (la política de septiembre solo existe desde el 01/09). El bloque termina SIEMPRE en `raise`: Postgres deshace los leads,
-- los sellos, las anulaciones y hasta la migración.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la migración real (a la que quita su
-- `begin;`/`commit;`) dentro de una única transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y
-- entonces TIENE que salir ROJO: es la medición del defecto (el servidor deja anular, y crea ajuste, en un mes sellado).
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT (las puertas son `security definer`
-- y deciden por `auth.uid()`), fijada en las DOS formas (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de
-- rol con `set role`: llamar bajo `set role` a una función sin EXECUTE tumba el Postgres del banco, así que los permisos
-- se leen del catálogo (sección 9) y nunca se prueban llamando.
--
-- Cada rechazo compara una foto de antes y de después (lead, anulaciones, cierres externos, actividades, ajustes), POR
-- CONTENIDO (md5 de las filas), no por cantidad: si la puerta acepta o modifica algo existente, el fallo sale ahí. Y cada
-- caso usa SU venta: una anulación aceptada no arrastra a las demás.

set local statement_timeout = '300s';

create temp sequence ens_seq;

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

-- Siembra UNA venta ya convertida, con los triggers apagados solo aquí. p_tipo:
--   'avance'      lead convertido, sin cierre externo (se anula por crm.anular_cierre_avance)
--   'externo'     lead convertido con su cierre externo INICIAL (crm.anular_cierre_externo)
--   'no_inicial'  lead convertido con un cierre externo NO inicial colgado de él (renovación/upgrade/reinversión)
-- p_episodio = false: venta sin episodio de cierre en el ledger. p_episodio_cuando: instante del episodio si no es el de
-- `convertido_en`. p_sin_fecha = true: el lead queda convertido SIN `convertido_en` (p_cuando sigue fechando el episodio y
-- el cierre). p_episodio2_cuando: un SEGUNDO episodio de cierre (solo posible si el índice único del ledger no está).
-- Devuelve {lead, cierre}.
create function pg_temp.sembrar(p_clave text, p_tipo text, p_cuando timestamptz, p_episodio boolean default true,
                                 p_episodio_cuando timestamptz default null, p_sin_fecha boolean default false,
                                 p_episodio2_cuando timestamptz default null)
returns jsonb language plpgsql as $f$
declare
  v_n      integer := nextval('pg_temp.ens_seq');
  v_lead   uuid := gen_random_uuid();
  v_cierre uuid := gen_random_uuid();
  v_vend   uuid;
  v_inv    uuid := gen_random_uuid();
  v_dia    date := (p_cuando at time zone 'America/Lima')::date;
  v_obj    uuid;
  v_ep     timestamptz := coalesce(p_episodio_cuando, p_cuando);
begin
  select p.id into v_vend from public.perfiles p where p.nombre_completo = 'PASO08 VEND1';
  if v_vend is null then raise exception 'ENSAYO ABORTADO: falta el vendedor PASO08 VEND1'; end if;
  -- El comprobante de un cierre no inicial apunta a un objeto de storage que EXISTA: la FK se comprueba al anular
  -- (la fila se sembró en esta misma transacción). Se usa uno que ya está en el laboratorio; no se escribe en storage.
  select o.id into v_obj from storage.objects o order by o.id limit 1;
  if p_tipo = 'no_inicial' and v_obj is null then raise exception 'ENSAYO ABORTADO: el laboratorio no tiene ningún objeto en storage.objects para el comprobante'; end if;
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, origen, etapa, convertido_en, vendedor_id, contrato_id, activo, monto_estimado)
  values (v_lead, 'ENSAYO ' || p_clave, '9990' || lpad(v_n::text, 5, '0'), 'landing', 'convertido',
          case when p_sin_fecha then null else p_cuando end, v_vend, null, true, 1000);
  if p_episodio then
    insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
        sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado,
        resultado_en, finalizado_en, finalizado_por, motivo_cierre)
    values (v_lead, 1, 1, v_vend, 'asignado', v_ep - interval '5 days', 'PEN', 'landing',
        v_ep - interval '5 days', gen_random_uuid(), v_ep, v_ep, 'convertido', v_ep, v_ep, v_vend, 'convertido');
  end if;
  if p_episodio2_cuando is not null then
    insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
        sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado,
        resultado_en, finalizado_en, finalizado_por, motivo_cierre)
    values (v_lead, 2, 1, v_vend, 'reabierto', p_episodio2_cuando - interval '5 days', 'PEN', 'landing',
        p_episodio2_cuando - interval '5 days', gen_random_uuid(), p_episodio2_cuando, p_episodio2_cuando, 'convertido',
        p_episodio2_cuando, p_episodio2_cuando, v_vend, 'convertido');
  end if;
  if p_tipo = 'externo' then
    insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
        numero_transaccion, vendedor_id, creado_por, es_cierre_inicial, lead_id, fecha_comercial, fecha_imputacion)
    values (v_cierre, 'qorilazo', 1000, 'PEN', 'DNI', '70' || lpad(v_n::text, 6, '0'), 'PERSONA ENSAYO ' || v_n,
        'ENS-' || v_n, v_vend, v_vend, true, v_lead, v_dia, v_dia);
  elsif p_tipo = 'no_inicial' then
    insert into crm.inversionistas (id, estado) values (v_inv, 'activo');
    insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
        numero_transaccion, vendedor_id, creado_por, es_cierre_inicial, lead_id, inversionista_id, fecha_comercial,
        fecha_imputacion, comprobante_objeto_id, referencia_externa)
    values (v_cierre, 'prodelco', 500, 'USD', 'DNI', '71' || lpad(v_n::text, 6, '0'), 'PERSONA ENSAYO ' || v_n,
        'ENS-' || v_n, v_vend, v_vend, false, v_lead, v_inv, v_dia, v_dia, v_obj, 'REF-ENS-' || v_n);
  end if;
  set local session_replication_role = origin;
  return jsonb_build_object('lead', v_lead, 'cierre', case when p_tipo = 'avance' then null else v_cierre end);
end;
$f$;

-- Hecho de acreditación de una venta de septiembre (política de septiembre). p_periodo fuerza OTRO `periodo_comercial` (p. ej.
-- uno no canónico, solo posible con los CHECK quitados: caso 3-N1); p_periodo_nulo lo deja NULO (solo posible sin el NOT NULL:
-- caso 3-N2). El plazo se calcula siempre sobre un primer día de mes: `private.conversion_plazo_hasta` es STRICT y rechaza
-- (22023) cualquier otro día.
create function pg_temp.acreditar(p_lead uuid, p_origen text, p_estado text, p_incluida boolean, p_fecha date default date '2026-09-10',
                                   p_periodo date default null, p_periodo_nulo boolean default false)
returns void language plpgsql as $f$
declare
  v_vend uuid;
  v_periodo date := case when p_periodo_nulo then null else coalesce(p_periodo, date_trunc('month', p_fecha::timestamp)::date) end;
  v_plazo timestamptz := private.conversion_plazo_hasta(date_trunc('month', coalesce(p_periodo, p_fecha)::timestamp)::date);
  v_sello timestamptz := (select pc.cerrado_en from crm.periodos_cerrados pc where pc.periodo = date_trunc('month', p_fecha::timestamp)::date);
begin
  select p.id into v_vend from public.perfiles p where p.nombre_completo = 'PASO08 VEND1';
  set local session_replication_role = replica;
  insert into crm.conversion_acreditaciones (lead_id, episodio_id, inversionista_id, analista_id, origen, fuente_tipo, fuente_id,
      fecha_comercial, confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, sellado_en,
      incluida_en_sello, motivo)
  values (p_lead, (select la.id from crm.lead_asignaciones la where la.lead_id = p_lead limit 1), null, v_vend, p_origen,
      'contrato', gen_random_uuid(), p_fecha, (p_fecha + time '15:00') at time zone 'America/Lima',
      (p_fecha + time '15:00') at time zone 'America/Lima', (p_fecha + time '15:00') at time zone 'America/Lima',
      v_periodo, v_plazo, p_estado,
      v_sello, case when v_sello is null then null else p_incluida end,
      'Acreditación de ensayo');
  set local session_replication_role = origin;
end;
$f$;

-- Llama a UNA puerta como el actor de la sesión. 'ok|<respuesta>' o 'SQLSTATE|mensaje|pista'. p_puerta: 'avance' | 'externo'.
create function pg_temp.puerta(p_puerta text, p_actor uuid, p_id uuid, p_motivo text default 'Ensayo: anulación de venta')
returns text language plpgsql as $f$
declare
  v_r    jsonb;
  v_hint text;
begin
  perform pg_temp.sesion(p_actor);
  if p_puerta = 'avance' then
    v_r := crm.anular_cierre_avance(p_id, p_motivo);
  else
    v_r := crm.anular_cierre_externo(p_id, p_motivo);
  end if;
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_hint, '');
end;
$f$;

-- Foto de todo lo que una anulación puede tocar alrededor de una venta, POR CONTENIDO: md5 de las filas (no su número).
-- `ajustes_total` es el contenido de TODA la tabla de ajustes: una anulación no puede tocar la deuda de nadie.
create function pg_temp.foto(p_lead uuid) returns text language sql as $$
  select format('lead=%s anulaciones=%s cierres=%s actividades=%s ajustes_lead=%s ajustes_total=%s',
           coalesce((select md5(l::text) from crm.leads l where l.id = p_lead), '-'),
           coalesce((select md5(string_agg(a::text, ',' order by a.id)) from crm.cierres_avance_anulados a where a.lead_id = p_lead), '-'),
           coalesce((select md5(string_agg(ce::text, ',' order by ce.id)) from crm.cierres_externos ce where ce.lead_id = p_lead), '-'),
           coalesce((select md5(string_agg(a::text, ',' order by a.id)) from crm.actividades a where a.lead_id = p_lead), '-'),
           coalesce((select md5(string_agg(j::text, ',' order by j.id)) from crm.ajustes_mes_cerrado j where j.lead_id = p_lead), '-'),
           coalesce((select md5(string_agg(j::text, ',' order by j.id)) from crm.ajustes_mes_cerrado j), '-'));
$$;

create function pg_temp.claves(p jsonb) returns text language sql as $$
  select string_agg(k, ',' order by k) from jsonb_object_keys(p) k;
$$;

-- ¿Tiene ESTA sesión tomado el cerrojo del mes (el de crm.cerrar_periodo)? Presencia, no exclusión: la carrera con
-- dos conexiones no se puede probar con la herramienta de una sola conexión.
create function pg_temp.cerrojo_del_mes(p_mes date) returns boolean language sql as $$
  select exists (
    select 1 from pg_locks l
    where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.objsubid = 2
      and l.classid::bigint = (hashtext('crm.periodos_cerrados')::bigint & 4294967295)
      and l.objid::bigint = (p_mes - date '2000-01-01')::bigint);
$$;

-- Exige el RECHAZO de la regla: SQLSTATE, mensaje y pista exactos, y la foto intacta. p_mes = 'AAAA-MM' (mes sellado) o
-- NULL (mes DESCONOCIDO: el mensaje de «no se puede determinar»).
create function pg_temp.exigir_rechazo(p_caso text, p_puerta text, p_actor uuid, p_id uuid, p_lead uuid, p_mes text)
returns text language plpgsql as $f$
declare
  v_esperado text := 'P0409|' || case when p_mes is null then 'No se puede anular: no se puede determinar el mes de esta venta'
                                      else 'No se puede anular: el mes de esta venta (' || p_mes || ') ya está sellado' end
    || '|Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
  v_antes text := pg_temp.foto(p_lead);
  v_res text;
  v_despues text;
  v_motivos text[] := '{}';
begin
  v_res := pg_temp.puerta(p_puerta, p_actor, p_id);
  v_despues := pg_temp.foto(p_lead);
  if v_res like 'ok|%' then
    v_motivos := v_motivos || case when p_mes is null then 'el servidor ACEPTÓ anular una venta cuyo mes no se puede determinar'
                                   else 'el servidor ACEPTÓ anular una venta de un mes sellado' end;
  elsif v_res <> v_esperado then
    v_motivos := v_motivos || ('rechazó, pero no con la regla: ' || v_res);
  end if;
  if v_despues is distinct from v_antes then
    v_motivos := v_motivos || format('no quedó como estaba: [%s] → [%s]', v_antes, v_despues);
  end if;
  if cardinality(v_motivos) = 0 then return ''; end if;
  return format(E'FALLO %s (%s): %s\n', p_caso, p_puerta, array_to_string(v_motivos, '; '));
end;
$f$;

-- Exige un rechazo de SIEMPRE (42501 «Solo gerencia…», «ya estaba anulado», el error de integridad…): texto exacto y foto intacta.
create function pg_temp.exigir_texto(p_caso text, p_puerta text, p_actor uuid, p_id uuid, p_lead uuid, p_esperado text)
returns text language plpgsql as $f$
declare
  v_antes text := pg_temp.foto(p_lead);
  v_res text;
  v_despues text;
  v_motivos text[] := '{}';
begin
  v_res := pg_temp.puerta(p_puerta, p_actor, p_id);
  v_despues := pg_temp.foto(p_lead);
  if v_res like 'ok|%' then
    v_motivos := v_motivos || 'el servidor ACEPTÓ la anulación'::text;
  elsif v_res <> p_esperado then
    v_motivos := v_motivos || ('rechazó, pero no como siempre: ' || v_res);
  end if;
  if v_despues is distinct from v_antes then
    v_motivos := v_motivos || format('no quedó como estaba: [%s] → [%s]', v_antes, v_despues);
  end if;
  if cardinality(v_motivos) = 0 then return ''; end if;
  return format(E'FALLO %s (%s): %s\n', p_caso, p_puerta, array_to_string(v_motivos, '; '));
end;
$f$;

-- Exige que la anulación ENTRE, como entra hoy (mes abierto, mes terminado sin sellar, cierre no inicial) o como entra el
-- exento (p_mes_exento no nulo: 'AAAA-MM' o 'desconocido'): respuesta con sus claves, mes_cerrado false y ajuste_id nulo,
-- sin ajuste nuevo y sin tocar los ajustes de nadie, anulación registrada, actividad con (o sin) el rastro de la excepción
-- y, si procede, el cerrojo del mes tomado.
create function pg_temp.exigir_entra(p_caso text, p_puerta text, p_actor uuid, p_id uuid, p_lead uuid,
                                     p_mes_exento text, p_mes_cerrojo date)
returns text language plpgsql as $f$
declare
  v_motivo constant text := 'Ensayo: anulación de venta';
  v_claves text := case p_puerta when 'avance' then 'afecta_cuota,ajuste_id,contratos_afectados,lead_id,mes_cerrado,ok'
                                 else 'ajuste_id,cierre_id,lead_id,mes_cerrado,ok' end;
  v_accion text := case p_puerta when 'avance' then 'anulacion_cierre_avance' else 'anulacion_cierre_externo' end;
  v_antes_actividades integer := (select count(*) from crm.actividades a where a.lead_id = p_lead);
  v_ajustes_antes text := coalesce((select md5(string_agg(j::text, ',' order by j.id)) from crm.ajustes_mes_cerrado j), '-');
  v_res text;
  v_r jsonb;
  v_meta jsonb;
  v_n integer;
  v_pref text := case when p_mes_exento is null then '' else 'exento: ' end;
  v_out text := '';
begin
  v_res := pg_temp.puerta(p_puerta, p_actor, p_id, v_motivo);
  if v_res not like 'ok|%' then
    return format(E'FALLO %s (%s): %sdebía poder anular y se rechazó (%s)\n', p_caso, p_puerta, v_pref, v_res);
  end if;
  v_r := substr(v_res, 4)::jsonb;
  -- La respuesta conserva sus claves y dice «sin ajuste».
  if pg_temp.claves(v_r) is distinct from v_claves
     or v_r -> 'ok' is distinct from 'true'::jsonb
     or v_r -> 'mes_cerrado' is distinct from 'false'::jsonb
     or v_r -> 'ajuste_id' is distinct from 'null'::jsonb then
    v_out := v_out || format(E'FALLO %s (%s): %sla respuesta no conserva sus claves o dice que hubo ajuste (claves %s; mes_cerrado=%s; ajuste_id=%s)\n',
      p_caso, p_puerta, v_pref, coalesce(pg_temp.claves(v_r), '-'), v_r -> 'mes_cerrado', v_r -> 'ajuste_id');
  end if;
  -- Sin ajuste nuevo, y los ajustes que había, byte a byte iguales.
  if exists (select 1 from crm.ajustes_mes_cerrado j where j.lead_id = p_lead)
     or coalesce((select md5(string_agg(j::text, ',' order by j.id)) from crm.ajustes_mes_cerrado j), '-') <> v_ajustes_antes then
    v_out := v_out || format(E'FALLO %s (%s): %sdejó un ajuste en crm.ajustes_mes_cerrado (o tocó uno existente)\n', p_caso, p_puerta, v_pref);
  end if;
  -- La anulación quedó registrada.
  if p_puerta = 'avance' then
    select count(*) into v_n from crm.cierres_avance_anulados a
     where a.lead_id = p_lead and a.anulado_por = p_actor and a.motivo = v_motivo;
  else
    select count(*) into v_n from crm.cierres_externos ce
     where ce.id = p_id and ce.anulado_en is not null and ce.anulado_por = p_actor and ce.motivo_anulacion = v_motivo;
  end if;
  if v_n <> 1 then
    v_out := v_out || format(E'FALLO %s (%s): %sla anulación no quedó registrada\n', p_caso, p_puerta, v_pref);
  end if;
  -- La actividad: una sola, con el motivo, y con el rastro de la excepción SOLO si es el exento.
  select a.metadata into v_meta from crm.actividades a
   where a.lead_id = p_lead and a.metadata ->> 'accion' = v_accion and a.creado_por = p_actor
   order by a.creado_en desc limit 1;
  if (select count(*) from crm.actividades a where a.lead_id = p_lead) <> v_antes_actividades + 1
     or v_meta is null
     or v_meta ->> 'motivo' is distinct from v_motivo
     or v_meta -> 'mes_cerrado' is distinct from 'false'::jsonb then
    v_out := v_out || format(E'FALLO %s (%s): %sla actividad de la anulación no quedó como siempre (metadatos %s)\n',
      p_caso, p_puerta, v_pref, coalesce(v_meta::text, 'sin actividad'));
  elsif p_mes_exento is not null then
    if v_meta ->> 'excepcion_mes_sellado' is distinct from p_mes_exento
       or (v_meta ->> 'excepcion_por')::uuid is distinct from p_actor
       or (v_meta ->> 'excepcion_en') is null
       or (v_meta ->> 'excepcion_en')::timestamptz is null then
      v_out := v_out || format(E'FALLO %s (%s): exento: anuló SIN rastro en la actividad (metadatos %s)\n', p_caso, p_puerta, v_meta);
    end if;
  elsif v_meta ?| array['excepcion_mes_sellado', 'excepcion_por', 'excepcion_en'] then
    v_out := v_out || format(E'FALLO %s (%s): una anulación común quedó marcada como excepción (metadatos %s)\n', p_caso, p_puerta, v_meta);
  end if;
  -- El cerrojo del mes, tomado (presencia).
  if p_mes_cerrojo is not null and not pg_temp.cerrojo_del_mes(p_mes_cerrojo) then
    v_out := v_out || format(E'FALLO %s (%s): la anulación no tomó el cerrojo del mes %s (crm.periodos_cerrados)\n', p_caso, p_puerta, p_mes_cerrojo);
  end if;
  return v_out;
end;
$f$;

do $ensayo$
declare
  v_jun constant date := date '2026-06-01';
  v_jul constant date := date '2026-07-01';
  v_ago constant date := date '2026-08-01';
  v_sep constant date := date '2026-09-01';
  v_m0  constant date := (date_trunc('month', now() at time zone 'America/Lima'))::date;
  v_ger_admin uuid;
  v_ger_super uuid;
  v_ger_hist uuid;
  v_admin uuid;
  v_superadmin uuid;
  v_vend uuid;
  v_sup uuid;
  v_actor uuid;
  v_nombre text;
  v_puerta text;
  v_venta jsonb;
  v_lead uuid;
  v_cierre uuid;
  v_id uuid;
  v_texto text;
  v_esperado text;
  v_res text;
  v_r jsonb;
  v_selladas text;
  v_i integer;
  v_otros text;
  v_deuda_lead uuid;
  v_deuda_foto text;
  v_det record;
begin
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.informe', '', true);

  -- ── El oráculo va en READ COMMITTED (como la API): la guarda 0A000 del detector se ensaya aparte (aislamiento.sql) ──
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'ENSAYO ABORTADO: este oráculo debe correr en read committed y va en %', current_setting('transaction_isolation');
  end if;

  -- ── Actores reales del banco (OBLIGATORIOS: sin ellos un caso se saltaría en silencio) ──────────────────────────
  select p.id into v_ger_admin  from public.perfiles p where p.nombre_completo = 'PASO08 GER_ADMIN';
  select p.id into v_ger_super  from public.perfiles p where p.nombre_completo = 'PASO08 GER_SUPER';
  select p.id into v_ger_hist   from public.perfiles p where p.nombre_completo = 'PASO08 GERENCIA';
  select p.id into v_admin      from public.perfiles p where p.nombre_completo = 'PASO08 ADMIN';
  select p.id into v_superadmin from public.perfiles p where p.nombre_completo = 'PASO08 SUPERADMIN';
  select p.id into v_vend       from public.perfiles p where p.nombre_completo = 'PASO08 VEND1';
  select p.id into v_sup        from public.perfiles p where p.nombre_completo = 'PASO08 SUP1';
  if v_ger_admin is null or v_ger_super is null or v_ger_hist is null or v_admin is null
     or v_superadmin is null or v_vend is null or v_sup is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (ger_admin=%, ger_super=%, gerencia=%, admin=%, superadmin=%, vend1=%, sup1=%)',
      v_ger_admin, v_ger_super, v_ger_hist, v_admin, v_superadmin, v_vend, v_sup;
  end if;
  -- Y cada uno es el par que se declaró (rol del Portal + rol del CRM): si el banco derivó, el ensayo no prueba lo que dice.
  if (select p.rol from public.perfiles p where p.id = v_ger_admin) is distinct from 'admin'
     or private.rol_crm(v_ger_admin) is distinct from 'gerencia'
     or (select p.rol from public.perfiles p where p.id = v_ger_super) is distinct from 'superadmin'
     or private.rol_crm(v_ger_super) is distinct from 'gerencia'
     or (select p.rol from public.perfiles p where p.id = v_ger_hist) is distinct from 'comercial'
     or private.rol_crm(v_ger_hist) is distinct from 'gerencia'
     or (select p.rol from public.perfiles p where p.id = v_admin) is distinct from 'admin'
     or private.rol_crm(v_admin) is not null
     or (select p.rol from public.perfiles p where p.id = v_superadmin) is distinct from 'superadmin'
     or private.rol_crm(v_superadmin) is not null
     or private.rol_crm(v_vend) is distinct from 'vendedor'
     or private.rol_crm(v_sup) is distinct from 'supervisor' then
    raise exception 'ENSAYO ABORTADO: un actor del banco no es el par esperado (ger_admin admin+gerencia, ger_super superadmin+gerencia, gerencia comercial+gerencia, admin y superadmin sin ficha, vend1, sup1)';
  end if;

  -- ── Las dos mitades de la excepción, leídas de las funciones de la casa, por sesión ─────────────────────────────
  -- es_admin() y es_gerencia_crm_activa(): solo ger_admin y ger_super cumplen las DOS. Sin sesión de usuario es_admin()
  -- da falso (D-17). Se mide aquí porque la puerta ya filtra por «Solo gerencia» ANTES de preguntar por la excepción.
  v_otros := '';
  foreach v_actor in array array[v_ger_admin, v_ger_super, v_ger_hist, v_admin, v_superadmin, v_vend, v_sup, null::uuid] loop
    perform pg_temp.sesion(v_actor);
    v_otros := v_otros || format('%s=%s/%s ', coalesce((select p.nombre_completo from public.perfiles p where p.id = v_actor), 'SIN SESIÓN'),
                                 public.es_admin(), private.es_gerencia_crm_activa());
    if coalesce(v_actor in (v_ger_admin, v_ger_super), false) is distinct from (public.es_admin() and private.es_gerencia_crm_activa()) then
      perform pg_temp.reg('5-pares', format(E'FALLO 5-pares: la excepción (es_admin y es_gerencia_crm_activa) no da %s para %s\n',
        v_actor in (v_ger_admin, v_ger_super), coalesce((select p.nombre_completo from public.perfiles p where p.id = v_actor), 'SIN SESIÓN')));
    end if;
  end loop;
  perform pg_temp.sesion(null);
  perform set_config('ensayo.medidas', E'medida 5-pares (es_admin/es_gerencia_crm_activa): ' || v_otros || E'\n', true);

  -- ── Configuración que el banco sin datos no trae, y estado de partida ───────────────────────────────────────────
  -- Una versión del peso SOLO si el banco no trae ninguna (`private.peso_referido_conversion` lanza 55000 con la tabla vacía).
  -- F4.2 (09/10/2026): el laboratorio igual a producción ya trae 2026-07-01 y 2026-10-01, y desde 20261007160937 un peso de
  -- referido mayor que 0,150 exige tope (CHECK `conversion_pesos_referido_con_tope`): la siembra de antes (0,5 sin tope)
  -- abortaba el ensayo. Ningún caso de este oráculo es un referido: el peso no decide nada de lo que se mide.
  insert into crm.conversion_pesos (vigente_desde, peso_referido)
  select date '2026-01-01', 0.150 where not exists (select 1 from crm.conversion_pesos);
  if exists (select 1 from crm.periodos_cerrados where periodo in (v_jun, v_jul, v_ago, v_sep) or periodo >= v_jun) then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene meses sellados desde junio de 2026 (%): el ensayo sella los suyos',
      (select string_agg(periodo::text, ',' order by periodo) from crm.periodos_cerrados);
  end if;
  if v_m0 <= v_sep then
    raise exception 'ENSAYO ABORTADO: el mes en curso (%) no es posterior a septiembre de 2026: no hay mes abierto ni terminado sin sellar que probar', v_m0;
  end if;

  -- ── JUNIO: se sella con la función de la casa (test-cierre-mes.sql, bloque 4) ───────────────────────────────────
  perform pg_temp.sesion(null);   -- sin uid = ciclo automático
  perform crm.cerrar_periodo(v_jun);

  -- ── 6-antes. Frontera: una venta de JULIO se anula ANTES de sellar julio, y entra como hoy ───────────────────────
  v_venta := pg_temp.sembrar('julio-antes', 'avance', timestamptz '2026-07-12 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('6-antes', pg_temp.exigir_entra('6-antes', 'avance', v_ger_hist, v_lead, v_lead, null, v_jul));
  declare v_lead_julio_anulada uuid := v_lead; begin
    perform set_config('ensayo.lead_julio_anulada', v_lead_julio_anulada::text, true);
  end;

  -- ── JULIO: se sella con la función de la casa ────────────────────────────────────────────────────────────────────
  perform crm.cerrar_periodo(v_jul);

  -- ── SEPTIEMBRE: la política de septiembre y su sello (solo para el ensayo; ver la cabecera) ──────────────────────
  set local session_replication_role = replica;
  insert into crm.periodos_cerrados (periodo, ponderacion_referido, meta_revision, cobertura)
  values (v_sep, 0.5, 1, '{}'::jsonb);
  update crm.conversion_politica
     set activada_en = timestamptz '2026-09-01 00:00-05', manifiesto_huella = 'ensayo', resultado = '{}'::jsonb
   where unica;
  set local session_replication_role = origin;
  select string_agg(pc.periodo::text, ',' order by pc.periodo) into v_selladas from crm.periodos_cerrados pc;
  if v_selladas is distinct from '2026-06-01,2026-07-01,2026-09-01' then
    raise exception 'ENSAYO ABORTADO: los meses sellados del ensayo no son los esperados (%)', v_selladas;
  end if;
  if exists (select 1 from crm.periodos_cerrados where periodo in (v_ago, v_m0)) then
    raise exception 'ENSAYO ABORTADO: agosto de 2026 o el mes en curso aparecen sellados';
  end if;
  perform set_config('ensayo.medidas', current_setting('ensayo.medidas') || format(E'medida 8 (meses del ensayo): sellados %s (junio y julio con crm.cerrar_periodo; septiembre insertado), sin sellar y terminado 2026-08, abierto %s; sin mover el reloj\n', v_selladas, v_m0), true);

  -- ── DEUDA PREVIA (caso 4g): una venta de junio anulada ANTES de la regla que dejó su ajuste pendiente. Nada de lo que ─
  --    hagan las demás anulaciones (entren o se rechacen) puede tocar esta fila ni su saldo.
  v_venta := pg_temp.sembrar('4g-deuda-previa', 'avance', timestamptz '2026-06-11 15:00-05');
  v_deuda_lead := (v_venta ->> 'lead')::uuid;
  set local session_replication_role = replica;
  insert into crm.cierres_avance_anulados (lead_id, acreditado_a, motivo, anulado_por) values (v_deuda_lead, v_vend, 'anulada antes de la regla (ensayo)', v_ger_hist);
  insert into crm.ajustes_mes_cerrado (vendedor_id, periodo_origen, lead_id, motivo, creado_por, numerador, capital_pen, capital_usd, detalle,
                                       pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle)
  values (v_vend, v_jun, v_deuda_lead, 'Deuda previa (ensayo): anterior a la regla del mes sellado', v_ger_hist, 1, 0, 0, '[]'::jsonb, 1, 0, 0, '[]'::jsonb);
  set local session_replication_role = origin;
  v_deuda_foto := (select md5(j::text) from crm.ajustes_mes_cerrado j where j.lead_id = v_deuda_lead);
  if v_deuda_foto is null or (select j.pendiente_numerador from crm.ajustes_mes_cerrado j where j.lead_id = v_deuda_lead) <> 1 then
    raise exception 'ENSAYO ABORTADO: no se pudo sembrar la deuda previa';
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 1 y 2. RECHAZO en mes sellado con un Gerencia NO exento (la `gerencia` histórica del banco, comercial+gerencia)
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_venta := pg_temp.sembrar('1-avance-junio', 'avance', timestamptz '2026-06-12 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('1', pg_temp.exigir_rechazo('1', 'avance', v_ger_hist, v_lead, v_lead, '2026-06'));

  v_venta := pg_temp.sembrar('2-externo-junio', 'externo', timestamptz '2026-06-13 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('2', pg_temp.exigir_rechazo('2', 'externo', v_ger_hist, v_cierre, v_lead, '2026-06'));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3. Mes sellado con una venta que HOY no habría generado ajuste: igualmente rechazada
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3-S1 control: septiembre, acreditada e incluida en el sello, origen que pesa (hoy SÍ nace ajuste).
  v_venta := pg_temp.sembrar('3-sept-acreditada', 'avance', timestamptz '2026-09-10 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'acreditada', true);
  perform pg_temp.reg('3-sept-acreditada', pg_temp.exigir_rechazo('3-sept-acreditada', 'avance', v_ger_hist, v_lead, v_lead, '2026-09'));
  -- 3-S2 fuera de plazo (la acreditación no entró en el sello): hoy NO nace ajuste.
  v_venta := pg_temp.sembrar('3-sept-fuera-de-plazo', 'avance', timestamptz '2026-09-10 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'fuera_de_plazo', false);
  perform pg_temp.reg('3-fuera-de-plazo', pg_temp.exigir_rechazo('3-fuera-de-plazo', 'avance', v_ger_hist, v_lead, v_lead, '2026-09'));
  -- 3-S3 origen que no pesa (acreditada e incluida, pero el origen vale 0): hoy NO nace ajuste.
  v_venta := pg_temp.sembrar('3-sept-origen-que-no-pesa', 'avance', timestamptz '2026-09-10 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'otro', 'acreditada', true);
  perform pg_temp.reg('3-origen-que-no-pesa', pg_temp.exigir_rechazo('3-origen-que-no-pesa', 'avance', v_ger_hist, v_lead, v_lead, '2026-09'));
  -- 3-S4 sin acreditación (la política está activa y la venta es de septiembre, pero no hay fila): hoy NO nace ajuste.
  v_venta := pg_temp.sembrar('3-sept-sin-acreditacion', 'avance', timestamptz '2026-09-10 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('3-sin-acreditacion', pg_temp.exigir_rechazo('3-sin-acreditacion', 'avance', v_ger_hist, v_lead, v_lead, '2026-09'));
  -- 3-S5 sin episodio de cierre en el ledger (junio): hoy NO nace ajuste (numerador 0). Por las dos puertas.
  v_venta := pg_temp.sembrar('3-junio-sin-episodio', 'avance', timestamptz '2026-06-14 15:00-05', false);
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('3-sin-episodio', pg_temp.exigir_rechazo('3-sin-episodio', 'avance', v_ger_hist, v_lead, v_lead, '2026-06'));
  v_venta := pg_temp.sembrar('3-junio-sin-episodio-externo', 'externo', timestamptz '2026-06-14 16:00-05', false);
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('3-sin-episodio-externo', pg_temp.exigir_rechazo('3-sin-episodio-externo', 'externo', v_ger_hist, v_cierre, v_lead, '2026-06'));

  -- 3-E: el EPISODIO del ledger manda sobre `convertido_en`: convertida el 01/08 (Lima) pero con el episodio de cierre en
  -- julio (sellado) → el mes de la venta es julio. (Hoy `registrar_ajuste…` mira primero el mes de `convertido_en`, que
  -- está abierto, y devuelve nada.)
  v_venta := pg_temp.sembrar('3-episodio-manda', 'avance', timestamptz '2026-08-01 02:00-05', true, timestamptz '2026-07-31 23:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('3-episodio-manda', pg_temp.exigir_rechazo('3-episodio-manda', 'avance', v_ger_hist, v_lead, v_lead, '2026-07'));
  -- 3-F: la FECHA COMERCIAL de la acreditación manda sobre `convertido_en` (septiembre): convertida ahora (mes abierto), pero
  -- acreditada con fecha comercial de septiembre (sellado) → el mes de la venta es septiembre.
  v_venta := pg_temp.sembrar('3-sept-fecha-comercial', 'avance', now());
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'acreditada', true, date '2026-09-10');
  perform pg_temp.reg('3-fecha-comercial', pg_temp.exigir_rechazo('3-fecha-comercial', 'avance', v_ger_hist, v_lead, v_lead, '2026-09'));

  -- ⚠️ Los cerrojos son de la TRANSACCIÓN: un mes ya cerrojeado por una anulación anterior que entró no discrimina (y
  -- `crm.cerrar_periodo` ya cerrojeó junio y julio al sellarlos). Por eso cada comprobación de cerrojo se hace la PRIMERA vez que
  -- ese mes se cerrojea con éxito: julio (6-antes), septiembre (aquí, ANTES de 4f, que convierte en septiembre) y agosto (4d).
  -- Un rechazo no cuenta: su subtransacción se deshace y suelta el cerrojo.
  -- 3-G (exento): el exento sobre una venta cuyo mes (septiembre, por la fecha comercial) no es el de `convertido_en` (mes
  -- abierto): el cerrojo que toma es el del mes de la VENTA, no el de la conversión.
  v_venta := pg_temp.sembrar('5-ger_admin-fecha-comercial', 'avance', now());
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'acreditada', true, date '2026-09-10');
  perform pg_temp.reg('5-ger_admin-fecha-comercial', pg_temp.exigir_entra('5-ger_admin-fecha-comercial', 'avance', v_ger_admin, v_lead, v_lead, '2026-09', v_sep));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3-D. FECHA DE CONVERSIÓN AUSENTE (ronda 2, hallazgo #1). `crm.anular_cierre_avance` ya rechaza un lead sin
  --      `convertido_en` con 22023 ANTES de llegar al detector; `crm.anular_cierre_externo` no: estos casos entran por la
  --      puerta externa (cierre inicial). El orden de resolución es acreditación → episodio → fecha → desconocido.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3-D1: sin fecha, CON acreditación de septiembre (sellado) y episodio en el mes abierto: manda la acreditación → P0409 2026-09
  -- (no «desconocido», no el mes abierto del episodio).
  v_venta := pg_temp.sembrar('3-D1-sin-fecha-acreditada', 'externo', now(), true, null, true);
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'acreditada', true, date '2026-09-10');
  perform pg_temp.reg('3-D1-sin-fecha-acreditada', pg_temp.exigir_rechazo('3-D1-sin-fecha-acreditada', 'externo', v_ger_hist, v_cierre, v_lead, '2026-09'));
  -- 3-D2: sin fecha, sin acreditación, con episodio de cierre en junio (sellado): manda el episodio → P0409 2026-06.
  v_venta := pg_temp.sembrar('3-D2-sin-fecha-episodio', 'externo', timestamptz '2026-06-20 15:00-05', true, null, true);
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('3-D2-sin-fecha-episodio', pg_temp.exigir_rechazo('3-D2-sin-fecha-episodio', 'externo', v_ger_hist, v_cierre, v_lead, '2026-06'));
  -- 3-D3: sin fecha, sin acreditación y SIN episodio: mes DESCONOCIDO. No exento → P0409 «no se puede determinar» y nada escrito.
  v_venta := pg_temp.sembrar('3-D3-desconocido', 'externo', timestamptz '2026-06-21 15:00-05', false, null, true);
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('3-D3-desconocido', pg_temp.exigir_rechazo('3-D3-desconocido', 'externo', v_ger_hist, v_cierre, v_lead, null));
  -- 3-D4: mes DESCONOCIDO y EXENTO → anula sin ajuste, con rastro excepcion_mes_sellado = 'desconocido' (sin cerrojo: no hay mes).
  v_venta := pg_temp.sembrar('3-D4-desconocido-exento', 'externo', timestamptz '2026-06-22 15:00-05', false, null, true);
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('3-D4-desconocido-exento', pg_temp.exigir_entra('3-D4-desconocido-exento', 'externo', v_ger_admin, v_cierre, v_lead, 'desconocido', null));
  -- 3-D5: por la puerta de Avance, un lead sin fecha ni choca con la regla: la puerta lo rechaza ANTES con su 22023 de siempre.
  v_venta := pg_temp.sembrar('3-D5-sin-fecha-avance', 'avance', timestamptz '2026-06-23 15:00-05', false, null, true);
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('3-D5-sin-fecha-avance', pg_temp.exigir_texto('3-D5-sin-fecha-avance', 'avance', v_ger_hist, v_lead, v_lead,
    '22023|Ese lead esta convertido pero sin fecha de conversion: no se puede saber que contratos trajo|'));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3-B. ANALISTA DADO DE BAJA CON HEREDERO (F4.2-bis, 09/10/2026). Producción aplicó `20261009200000` (baja de analista): lo
  --      que produjo un analista dado de baja (`crm.equipo.activo = false`) pasa, en las lecturas vivas, a su responsable
  --      ACTUAL activo (`private.analista_efectivo_cierre` / `private.analista_efectivo_contrato`), y el ledger usa esa regla en
  --      su pierna de operaciones. El mes de la venta NO depende del analista: el detector no lo lee y la pierna de cierres del
  --      ledger no pasa por la regla de baja. VEND1 (el vendedor de todas las ventas del ensayo) se da de baja SOLO durante
  --      estos casos, con la persona del cierre externo a cargo de SUP1 (activo): la regla de baja tiene que ACTUAR (el analista
  --      efectivo del cierre es SUP1; si no, el caso no probaría nada) y el rechazo tiene que ser el mismo, por las dos puertas.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  if to_regprocedure('private.analista_dado_de_baja(uuid)') is null or to_regprocedure('private.analista_efectivo_cierre(uuid)') is null then
    perform pg_temp.reg('3-B-heredero', E'FALLO 3-B-heredero: el laboratorio no tiene la regla de baja de producción (20261009200000): el caso no se puede montar\n');
  else
    v_venta := pg_temp.sembrar('3-B-baja-externo', 'externo', timestamptz '2026-06-24 15:00-05');
    v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
    v_id := gen_random_uuid();
    set local session_replication_role = replica;
    insert into crm.inversionistas (id, estado, responsable_relacion_id) values (v_id, 'activo', v_sup);
    update crm.cierres_externos set inversionista_id = v_id where id = v_cierre;
    update crm.equipo set activo = false where perfil_id = v_vend;
    set local session_replication_role = origin;
    if private.analista_dado_de_baja(v_vend) is distinct from true
       or private.analista_efectivo_cierre(v_cierre) is distinct from v_sup then
      perform pg_temp.reg('3-B-heredero', format(E'FALLO 3-B-heredero: la regla de baja no actúa en el montaje (VEND1 de baja: %s; analista efectivo del cierre: %s, se esperaba SUP1 %s)\n',
        private.analista_dado_de_baja(v_vend), private.analista_efectivo_cierre(v_cierre), v_sup));
    else
      perform pg_temp.reg('3-B-heredero (VEND1 de baja: su cierre externo lo hereda SUP1)', '');
    end if;
    perform pg_temp.reg('3-B-baja-externo', pg_temp.exigir_rechazo('3-B-baja-externo', 'externo', v_ger_hist, v_cierre, v_lead, '2026-06'));
    v_venta := pg_temp.sembrar('3-B-baja-avance', 'avance', timestamptz '2026-06-25 15:00-05');
    v_lead := (v_venta ->> 'lead')::uuid;
    perform pg_temp.reg('3-B-baja-avance', pg_temp.exigir_rechazo('3-B-baja-avance', 'avance', v_ger_hist, v_lead, v_lead, '2026-06'));
    -- VEND1 vuelve a estar activo para el resto del ensayo.
    set local session_replication_role = replica;
    update crm.equipo set activo = true where perfil_id = v_vend;
    set local session_replication_role = origin;
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 4. Lo que debe seguir ENTRANDO, igual que hoy
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 4a. Mes ABIERTO (el mes en curso), por las dos puertas, con un Gerencia no exento.
  v_venta := pg_temp.sembrar('4a-avance-abierto', 'avance', now());
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('4a-avance', pg_temp.exigir_entra('4a-avance', 'avance', v_ger_hist, v_lead, v_lead, null, null));
  v_venta := pg_temp.sembrar('4a-externo-abierto', 'externo', now());
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('4a-externo', pg_temp.exigir_entra('4a-externo', 'externo', v_ger_hist, v_cierre, v_lead, null, null));
  -- 4b. Cierre externo NO inicial colgado de una venta de un mes SELLADO: anula como hoy (D-14).
  v_venta := pg_temp.sembrar('4b-no-inicial-sellado', 'no_inicial', timestamptz '2026-06-15 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('4b-no-inicial', pg_temp.exigir_entra('4b-no-inicial', 'externo', v_ger_hist, v_cierre, v_lead, null, null));
  -- 4c. Conversión YA anulada en un mes sellado: el mensaje de siempre, no el del sello.
  v_venta := pg_temp.sembrar('4c-avance-ya-anulada', 'avance', timestamptz '2026-06-16 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.sesion(null);
  set local session_replication_role = replica;
  insert into crm.cierres_avance_anulados (lead_id, acreditado_a, motivo, anulado_por) values (v_lead, v_vend, 'anulada antes (ensayo)', v_ger_hist);
  set local session_replication_role = origin;
  perform pg_temp.reg('4c-avance', pg_temp.exigir_texto('4c-avance', 'avance', v_ger_hist, v_lead, v_lead, 'P0409|Ese cierre ya estaba anulado|'));
  v_venta := pg_temp.sembrar('4c-externo-ya-anulado', 'externo', timestamptz '2026-06-16 16:00-05');
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  set local session_replication_role = replica;
  update crm.cierres_externos set anulado_en = now(), anulado_por = v_ger_hist, motivo_anulacion = 'anulado antes (ensayo)' where id = v_cierre;
  set local session_replication_role = origin;
  perform pg_temp.reg('4c-externo', pg_temp.exigir_texto('4c-externo', 'externo', v_ger_hist, v_cierre, v_lead, 'P0409|Ese cierre ya estaba anulado|'));
  -- 4d. Mes TERMINADO pero NO sellado (agosto): anula como hoy, por las dos puertas.
  v_venta := pg_temp.sembrar('4d-avance-agosto', 'avance', timestamptz '2026-08-12 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('4d-avance', pg_temp.exigir_entra('4d-avance', 'avance', v_ger_hist, v_lead, v_lead, null, v_ago));
  v_venta := pg_temp.sembrar('4d-externo-agosto', 'externo', timestamptz '2026-08-13 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('4d-externo', pg_temp.exigir_entra('4d-externo', 'externo', v_ger_hist, v_cierre, v_lead, null, v_ago));
  -- 4e. El episodio manda, al revés: convertida en julio (sellado) pero con el episodio de cierre ya en agosto (abierto) → entra.
  v_venta := pg_temp.sembrar('4e-episodio-abierto', 'avance', timestamptz '2026-07-31 23:30-05', true, timestamptz '2026-08-01 00:30-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('4e-episodio-abierto', pg_temp.exigir_entra('4e-episodio-abierto', 'avance', v_ger_hist, v_lead, v_lead, null, v_ago));
  -- 4f. La acreditación manda, al revés: convertida en septiembre (sellado) pero acreditada con fecha comercial de agosto
  -- (abierto) → entra.
  v_venta := pg_temp.sembrar('4f-acreditacion-agosto', 'avance', timestamptz '2026-09-10 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'acreditada', true, date '2026-08-28');
  perform pg_temp.reg('4f-acreditacion-agosto', pg_temp.exigir_entra('4f-acreditacion-agosto', 'avance', v_ger_hist, v_lead, v_lead, null, v_ago));
  -- 4g. DEUDA PREVIA CONSERVADA: tras todo lo anterior (anulaciones que entraron en mes abierto y terminado, rechazos en mes
  -- sellado y el exento), la fila del ajuste previo y su saldo están byte a byte como se sembraron. No se condona nada.
  if (select md5(j::text) from crm.ajustes_mes_cerrado j where j.lead_id = v_deuda_lead) is distinct from v_deuda_foto
     or (select j.pendiente_numerador from crm.ajustes_mes_cerrado j where j.lead_id = v_deuda_lead) is distinct from 1
     or (select j.saldado_en from crm.ajustes_mes_cerrado j where j.lead_id = v_deuda_lead) is not null then
    perform pg_temp.reg('4g', format(E'FALLO 4g: la deuda previa cambió con las anulaciones (fila %s; pendiente %s)\n',
      (select j::text from crm.ajustes_mes_cerrado j where j.lead_id = v_deuda_lead),
      (select j.pendiente_numerador from crm.ajustes_mes_cerrado j where j.lead_id = v_deuda_lead)));
  else
    perform pg_temp.reg('4g-deuda-previa-intacta (tras mes abierto, rechazos y exento)', '');
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 5. EXENTO (D-17): admin+gerencia (ger_admin) y superadmin+gerencia (ger_super) anulan en mes sellado SIN ajuste,
  --    con rastro. Y los negativos de la excepción.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  foreach v_nombre in array array['ger_admin', 'ger_super'] loop
    v_actor := case v_nombre when 'ger_admin' then v_ger_admin else v_ger_super end;
    v_venta := pg_temp.sembrar('5-' || v_nombre || '-avance', 'avance', timestamptz '2026-06-17 15:00-05');
    v_lead := (v_venta ->> 'lead')::uuid;
    perform pg_temp.reg('5-' || v_nombre || '-avance',
      pg_temp.exigir_entra('5-' || v_nombre || '-avance', 'avance', v_actor, v_lead, v_lead, '2026-06', v_jun));
    v_venta := pg_temp.sembrar('5-' || v_nombre || '-externo', 'externo', timestamptz '2026-06-18 15:00-05');
    v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
    perform pg_temp.reg('5-' || v_nombre || '-externo',
      pg_temp.exigir_entra('5-' || v_nombre || '-externo', 'externo', v_actor, v_cierre, v_lead, '2026-06', v_jun));
  end loop;
  -- Y el exento que anula una venta que SÍ habría generado ajuste hoy (septiembre acreditada): sin ajuste igualmente.
  v_venta := pg_temp.sembrar('5-ger_admin-sept', 'avance', timestamptz '2026-09-10 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'acreditada', true);
  perform pg_temp.reg('5-ger_admin-sept', pg_temp.exigir_entra('5-ger_admin-sept', 'avance', v_ger_admin, v_lead, v_lead, '2026-09', v_sep));
  -- La deuda previa, otra vez intacta tras los exentos (que anulan SIN ajuste y sin tocar los de otros).
  if (select md5(j::text) from crm.ajustes_mes_cerrado j where j.lead_id = v_deuda_lead) is distinct from v_deuda_foto then
    perform pg_temp.reg('4g', E'FALLO 4g: la deuda previa cambió tras las anulaciones del exento\n');
  else
    perform pg_temp.reg('4g-deuda-previa-intacta (tras los exentos)', '');
  end if;

  -- Negativos: la `gerencia` histórica (comercial+gerencia, par no declarado) NO es exenta (rechazo del sello);
  -- vendedor, supervisor, admin sin ficha, superadmin puro y la llamada SIN sesión de usuario ya chocan con «Solo gerencia».
  foreach v_puerta in array array['avance', 'externo'] loop
    for v_i in 1..6 loop
      v_actor := case v_i when 1 then v_ger_hist when 2 then v_admin when 3 then v_superadmin
                          when 4 then v_vend when 5 then v_sup else null end;
      v_nombre := case v_i when 1 then 'gerencia-historica' when 2 then 'admin-sin-ficha' when 3 then 'superadmin-puro'
                           when 4 then 'vendedor' when 5 then 'supervisor' else 'sin-sesion' end;
      v_venta := pg_temp.sembrar('5n-' || v_nombre || '-' || v_puerta, v_puerta, timestamptz '2026-06-19 15:00-05');
      v_lead := (v_venta ->> 'lead')::uuid; v_id := coalesce((v_venta ->> 'cierre')::uuid, v_lead);
      if v_i = 1 then
        perform pg_temp.reg('5n-' || v_nombre, pg_temp.exigir_rechazo('5n-' || v_nombre, v_puerta, v_actor, v_id, v_lead, '2026-06'));
      else
        v_esperado := '42501|' || case v_puerta when 'avance' then 'Solo gerencia anula cierres' else 'Solo gerencia anula cierres externos' end || '|';
        perform pg_temp.reg('5n-' || v_nombre, pg_temp.exigir_texto('5n-' || v_nombre, v_puerta, v_actor, v_id, v_lead, v_esperado));
      end if;
    end loop;
  end loop;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 6. FRONTERA: antes de sellar julio entró (6-antes, arriba); después de sellarlo, se rechaza. La carrera con
  --    `crm.cerrar_periodo` necesita DOS conexiones: aquí solo se mide que cada anulación toma el cerrojo del mes.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_venta := pg_temp.sembrar('6-avance-julio-despues', 'avance', timestamptz '2026-07-20 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('6-despues', pg_temp.exigir_rechazo('6-despues', 'avance', v_ger_hist, v_lead, v_lead, '2026-07'));
  v_venta := pg_temp.sembrar('6-externo-julio-despues', 'externo', timestamptz '2026-07-21 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('6-despues-externo', pg_temp.exigir_rechazo('6-despues-externo', 'externo', v_ger_hist, v_cierre, v_lead, '2026-07'));
  -- La venta que se anuló ANTES del sello sigue «ya anulada» (el mensaje de siempre), sellado o no el mes.
  v_lead := current_setting('ensayo.lead_julio_anulada')::uuid;
  perform pg_temp.reg('6-ya-anulada', pg_temp.exigir_texto('6-ya-anulada', 'avance', v_ger_hist, v_lead, v_lead, 'P0409|Ese cierre ya estaba anulado|'));
  perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
    || format(E'medida 6 (carrera con crm.cerrar_periodo): NO EJECUTADO con dos conexiones; medido por sesión única: el cerrojo del mes queda tomado tras anular (6-antes, 4d, 5-*). Ajustes en la base de ensayo al final: %s (la deuda previa sembrada en 4g)\n',
              (select count(*) from crm.ajustes_mes_cerrado)), true);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 7. crm.eliminar_inversion_fn
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  if to_regprocedure('crm.eliminar_inversion_fn(uuid,text)') is null then
    perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
      || E'medida 7 (crm.eliminar_inversion_fn): NO EJECUTADO — la función NO existe en este laboratorio (corte anterior a 20261005200945)\n', true);
  else
    perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
      || E'medida 7 (crm.eliminar_inversion_fn): EXISTE en este laboratorio pero este oráculo no la ejerce: correr supabase/scripts/eliminar-inversion/test-eliminar-inversion.sql\n', true);
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3-M. VARIOS EPISODIOS DE CIERRE (ronda 2, hallazgo #1). El ledger NO lo permite (índice único parcial
  --      `crm.lead_asignaciones_una_conversion_por_lead_idx`): el estado es imposible con el esquema puesto. Para ejercer la
  --      rama de integridad del detector se quita ese índice SOLO dentro de esta transacción (se deshace con el rollback) y
  --      se siembran dos episodios (junio sellado y agosto abierto). Esperado: el MISMO error de integridad que lanza
  --      `registrar_ajuste_si_mes_cerrado` (P0001 «Integridad: el lead … tiene 2 episodios de cierre en el ledger»), y nada
  --      escrito. Un detector que tomara el mes más antiguo respondería P0409 (2026-06): no es lo mismo. Va al final para que
  --      la ausencia del índice no afecte a ningún otro caso.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  if to_regclass('crm.lead_asignaciones_una_conversion_por_lead_idx') is null then
    raise exception 'ENSAYO ABORTADO: no existe el índice único crm.lead_asignaciones_una_conversion_por_lead_idx que este caso espera';
  end if;
  drop index crm.lead_asignaciones_una_conversion_por_lead_idx;
  v_venta := pg_temp.sembrar('3-M-dos-episodios-avance', 'avance', timestamptz '2026-06-14 15:00-05', true, null, false, timestamptz '2026-08-20 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.reg('3-M-dos-episodios', pg_temp.exigir_texto('3-M-dos-episodios', 'avance', v_ger_hist, v_lead, v_lead,
    format('P0001|Integridad: el lead %s tiene 2 episodios de cierre en el ledger|', v_lead)));
  v_venta := pg_temp.sembrar('3-M-dos-episodios-externo', 'externo', timestamptz '2026-06-14 16:00-05', true, null, false, timestamptz '2026-08-20 16:00-05');
  v_lead := (v_venta ->> 'lead')::uuid; v_cierre := (v_venta ->> 'cierre')::uuid;
  perform pg_temp.reg('3-M-dos-episodios-externo', pg_temp.exigir_texto('3-M-dos-episodios-externo', 'externo', v_ger_hist, v_cierre, v_lead,
    format('P0001|Integridad: el lead %s tiene 2 episodios de cierre en el ledger|', v_lead)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 3-N. MES NO CANÓNICO O NULO (ronda 3, R2-2). El esquema lo impide: `periodo_comercial` es NOT NULL, tiene el CHECK
  --      `periodo_comercial = date_trunc('month', fecha_comercial)::date` y, además, el CHECK de `plazo_hasta` llama a
  --      `private.conversion_plazo_hasta(periodo_comercial)`, que es STRICT y rechaza (22023) cualquier día que no sea el
  --      primero del mes. El estado es IMPOSIBLE con el esquema puesto, y el preflight exige el NOT NULL y el primer CHECK.
  --      Para ejercer la defensa en profundidad del detector se quitan, SOLO dentro de esta transacción (se deshacen con el
  --      rollback) y al final: los dos CHECK (3-N1) y el NOT NULL (3-N2). Esperado: P0001 «Integridad: el mes de la venta …
  --      no es un primer día de mes» por la puerta y nada escrito. Un detector que lo tratara como «abierto» ACEPTARÍA: el
  --      día 10 (o un nulo) no casa con el sello del día 1.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  select c.conname into v_texto from pg_constraint c
   where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'c'
     and pg_get_constraintdef(c.oid) = 'CHECK ((periodo_comercial = (date_trunc(''month''::text, (fecha_comercial)::timestamp without time zone))::date))';
  if v_texto is null then
    raise exception 'ENSAYO ABORTADO: no existe el CHECK periodo_comercial = date_trunc(month, fecha_comercial)::date que este caso espera';
  end if;
  execute format('alter table crm.conversion_acreditaciones drop constraint %I', v_texto);
  select c.conname into v_texto from pg_constraint c
   where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'c'
     and pg_get_constraintdef(c.oid) = 'CHECK ((plazo_hasta = private.conversion_plazo_hasta(periodo_comercial)))';
  if v_texto is null then
    raise exception 'ENSAYO ABORTADO: no existe el CHECK plazo_hasta = private.conversion_plazo_hasta(periodo_comercial) que este caso espera';
  end if;
  execute format('alter table crm.conversion_acreditaciones drop constraint %I', v_texto);
  alter table crm.conversion_acreditaciones alter column periodo_comercial drop not null;
  -- 3-N1: periodo_comercial = 2026-09-10 (septiembre está sellado, pero el día 10 no casa con el sello del día 1).
  v_venta := pg_temp.sembrar('3-N1-periodo-no-canonico', 'avance', timestamptz '2026-09-10 15:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'acreditada', true, date '2026-09-10', date '2026-09-10');
  perform pg_temp.reg('3-N1-periodo-no-canonico', pg_temp.exigir_texto('3-N1-periodo-no-canonico', 'avance', v_ger_hist, v_lead, v_lead,
    format('P0001|Integridad: el mes de la venta 2026-09-10 (lead %s) no es un primer día de mes|', v_lead)));
  -- 3-N2: periodo_comercial NULO.
  v_venta := pg_temp.sembrar('3-N2-periodo-nulo', 'avance', timestamptz '2026-09-10 16:00-05');
  v_lead := (v_venta ->> 'lead')::uuid;
  perform pg_temp.acreditar(v_lead, 'landing', 'acreditada', true, date '2026-09-10', null, true);
  perform pg_temp.reg('3-N2-periodo-nulo', pg_temp.exigir_texto('3-N2-periodo-nulo', 'avance', v_ger_hist, v_lead, v_lead,
    format('P0001|Integridad: el mes de la venta NULL (lead %s) no es un primer día de mes|', v_lead)));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 9. Catálogo: lo que la migración tiene que dejar, y lo que no puede tocar
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 9a. Las dos puertas: dueño, security definer, search_path vacío, EXECUTE solo para el dueño y authenticated, SIN opción
  --     de concesión.
  foreach v_texto in array array['crm.anular_cierre_avance(uuid,text)', 'crm.anular_cierre_externo(uuid,text)'] loop
    if not exists (
         select 1 from pg_proc p
         where p.oid = v_texto::regprocedure and p.proowner = 'postgres'::regrole::oid and p.prosecdef
           and p.proconfig = array['search_path=""'])
       or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
             from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where p.oid = v_texto::regprocedure)
          is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false'] then
      perform pg_temp.reg('9a', format(E'FALLO 9a: %s cambió de dueño, de atributos o de permisos\n', v_texto));
    else
      perform pg_temp.reg('9a ' || v_texto, '');
    end if;
  end loop;
  -- 9b. El detector, si existe: dueño postgres, SECURITY INVOKER (lo invocan puertas DEFINER: corre como su dueño), search_path
  --     vacío, volátil, devuelve record (tres OUT) y NINGÚN rol con EXECUTE salvo el dueño: ni authenticated, ni anon, ni
  --     service_role, ni authenticator. (Sin la migración no existe: no se cuenta como fallo aquí; los casos de comportamiento
  --     ya lo delatan.) En el laboratorio todo corre como `postgres`, así que «nadie más puede ejecutarlo» se prueba por
  --     catálogo (has_function_privilege), nunca llamando bajo `set role`.
  if to_regprocedure('private.mes_sellado_de_venta(uuid)') is null then
    perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
      || E'medida 9b: private.mes_sellado_de_venta(uuid) NO existe (la base no tiene la migración)\n', true);
  elsif not exists (
         select 1 from pg_proc p
         where p.oid = 'private.mes_sellado_de_venta(uuid)'::regprocedure and p.proowner = 'postgres'::regrole::oid
           and not p.prosecdef and p.provolatile = 'v' and p.prorettype = 'record'::regtype
           and p.proconfig = array['search_path=""'])
       or exists (
         select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = 'private.mes_sellado_de_venta(uuid)'::regprocedure and a.grantee <> 'postgres'::regrole::oid)
       or not has_function_privilege('postgres', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')
       or has_function_privilege('authenticated', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')
       or has_function_privilege('anon', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')
       or has_function_privilege('service_role', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')
       or has_function_privilege('authenticator', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE') then
    perform pg_temp.reg('9b', E'FALLO 9b: el detector private.mes_sellado_de_venta no tiene la ficha esperada (dueño postgres, SECURITY INVOKER, search_path vacío, volátil, record) o alguien más que el dueño tiene EXECUTE\n');
  else
    perform pg_temp.reg('9b detector: ficha INVOKER y ACL (solo el dueño ejecuta)', '');
  end if;
  -- 9e. El detector, llamado directamente (como su dueño, que es quien lo llama desde las puertas): las tres respuestas.
  --     Lead inexistente → desconocido; venta de junio (sellado) → sellado; venta del mes en curso → no sellado. Junio y el
  --     mes en curso ya están cerrojeados por casos anteriores: estas llamadas no estorban a las comprobaciones de cerrojo.
  --     Cada llamada va en su propia subtransacción: un detector que REVIENTE al llamarlo (p. ej. uno que escriba) es un fallo
  --     con nombre, no un ensayo sin veredicto.
  if to_regprocedure('private.mes_sellado_de_venta(uuid)') is not null then
    begin
      v_det := private.mes_sellado_de_venta(gen_random_uuid());
      if v_det.p_desconocido is distinct from true or v_det.p_sellado is distinct from false or v_det.p_mes is not null then
        perform pg_temp.reg('9e', format(E'FALLO 9e: para un lead inexistente el detector no dice «desconocido» (%s)\n', v_det::text));
      else
        perform pg_temp.reg('9e detector directo: lead inexistente → desconocido', '');
      end if;
    exception when others then
      perform pg_temp.reg('9e', format(E'FALLO 9e: el detector reventó con un lead inexistente (%s %s)\n', sqlstate, sqlerrm));
    end;
    begin
      v_venta := pg_temp.sembrar('9e-junio', 'avance', timestamptz '2026-06-24 15:00-05');
      v_det := private.mes_sellado_de_venta((v_venta ->> 'lead')::uuid);
      if v_det.p_mes is distinct from v_jun or v_det.p_sellado is distinct from true or v_det.p_desconocido is distinct from false then
        perform pg_temp.reg('9e', format(E'FALLO 9e: para una venta de junio el detector no dice «2026-06 sellado» (%s)\n', v_det::text));
      else
        perform pg_temp.reg('9e detector directo: venta de junio → 2026-06, sellado', '');
      end if;
    exception when others then
      perform pg_temp.reg('9e', format(E'FALLO 9e: el detector reventó con una venta de junio (%s %s)\n', sqlstate, sqlerrm));
    end;
    begin
      v_venta := pg_temp.sembrar('9e-abierto', 'avance', now());
      v_det := private.mes_sellado_de_venta((v_venta ->> 'lead')::uuid);
      if v_det.p_mes is distinct from v_m0 or v_det.p_sellado is distinct from false or v_det.p_desconocido is distinct from false then
        perform pg_temp.reg('9e', format(E'FALLO 9e: para una venta del mes en curso el detector no dice «%s, no sellado» (%s)\n', v_m0, v_det::text));
      else
        perform pg_temp.reg('9e detector directo: venta del mes en curso → no sellado', '');
      end if;
    exception when others then
      perform pg_temp.reg('9e', format(E'FALLO 9e: el detector reventó con una venta del mes en curso (%s %s)\n', sqlstate, sqlerrm));
    end;
  end if;
  -- 9c. Lo que NO se toca, con su huella: el ajuste (declarado en el vigía analítico), el saldo, el sello, la excepción y el
  --     ledger del que el detector saca el mes del episodio, en sus DOS funciones (`conversion_episodios` delega los cierres
  --     desde septiembre en `conversion_cierres`; la versión auditada de cada una; otra versión obliga a re-auditar el detector).
  --     F4.2 (09/10/2026): las huellas son las de PRODUCCIÓN (ledger con bases cargadas y tope de referidos; registrar_ajuste
  --     con bases cargadas; cerrar_periodo con el tope en la foto), re-auditadas: ver la cabecera de la migración. F4.2-bis
  --     (09/10/2026, tarde): `conversion_episodios` otra vez, por la baja de analista de producción (20261009200000: solo la
  --     pierna de operaciones), re-auditada.
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)'::regprocedure) is distinct from '125b4046f513657ac57ec676a0d52e87'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.conversion_cierres(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric,uuid[])'::regprocedure) is distinct from '155ce2b12754718388c8ca1644c84c90'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure) is distinct from 'fec614f0df11c6d411bf132c776cce6e'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure) is distinct from '3af3eb46396edfc550b1fb040245f1aa'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.saldar_ajustes(uuid,numeric,numeric,numeric)'::regprocedure) is distinct from '791a53a154348be349887c07a82a6414'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.cerrar_periodo(date)'::regprocedure) is distinct from '79840e5af7ef355126fcc11dfd461ff1'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'public.es_admin()'::regprocedure) is distinct from 'f4e01285f0b006f72b984213a6a95310'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.es_gerencia_crm_activa()'::regprocedure) is distinct from 'e2e84b58044078e40e506f623985e86d'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.rol_crm(uuid)'::regprocedure) is distinct from 'd2878a210be96ac85973d51dfcfb27a5' then
    perform pg_temp.reg('9c', E'FALLO 9c: cambió conversion_episodios, conversion_cierres, registrar_ajuste_si_mes_cerrado, saldar_ajustes, cerrar_periodo, es_admin, es_gerencia_crm_activa o rol_crm\n');
  else
    perform pg_temp.reg('9c huellas de lo que no se toca', '');
  end if;
  -- 9d. El censo analítico (vigía de leads y citas) queda como estaba al empezar el ensayo.
  if current_setting('ensayo.censo_previo', true) is not null
     and (select md5(coalesce(string_agg(t::text, ' ;; ' order by t::text), '')) from private.contadores_crudos_leads_citas() t)
         is distinct from current_setting('ensayo.censo_previo', true) then
    perform pg_temp.reg('9d', E'FALLO 9d: el censo analítico de leads y citas (private.contadores_crudos_leads_citas) cambió con la migración\n');
  else
    perform pg_temp.reg('9d censo analítico', '');
  end if;

  -- ── Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ───────────────────────────────────────────────
  begin
    set constraints all immediate;
  exception when others then
    perform pg_temp.reg('11', format(E'FALLO 11: algo de lo aceptado no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
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

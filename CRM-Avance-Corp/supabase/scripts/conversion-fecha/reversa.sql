-- REVERSA COMPATIBLE. Exige aprobación del SQL exacto; no ejecutar automáticamente.
-- Conserva los hechos y su auditoría. No borrar tablas ni reconstruir fotos.
-- Con un mes de la política nueva sellado, detenerse y preparar reversa específica.
begin;
set local lock_timeout='5s';
set local statement_timeout='45s';
do $guardia$
declare r record;
begin
  for r in select * from (values
    ('private.cierre_mes_ventana_desde(date)','fe15a998e777c4b92d643879b4a73e5f'),
    ('private.conversion_cierres(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric,uuid[])','b2f35b3fe1c319892c7aa254ccfc4b8f'),
    ('crm.corregir_fecha_cierre_comercial(uuid,date,text)','d56f800dc5e279c3d4d5e08625856fc7'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)','1f85397dd87fd73e282990238f151742')
  ) esperado(firma,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'La definicion de % cambio; no revertir encima de otra entrega',r.firma;
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),(date '2026-09-01'-date '2000-01-01')::integer);
  if exists(select 1 from crm.periodos_cerrados where periodo>=date '2026-09-01') then
    raise exception 'Hay meses de la politica nueva sellados; requiere reversa especifica';
  end if;
end;
$guardia$;

drop trigger trg_conversion_acreditacion_episodio on crm.lead_asignaciones;
drop trigger trg_zz_conversion_acreditacion_lead on crm.leads;
drop trigger trg_conversion_acreditacion_solicitud on crm.inversion_solicitudes;
drop trigger trg_conversion_acreditacion_cooperativa on crm.cierres_externos;
drop trigger trg_conversion_fijar_sello on crm.periodos_cerrados;
drop trigger trg_conversion_bloquear_retiro on crm.contratos_eliminados_auditoria;

CREATE OR REPLACE FUNCTION private.conversion_cierres(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric, p_leads uuid[])
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select 'cierre'::text, la.analista_id, la.lead_id, null::uuid,
  l.origen = 'referido', null::boolean, null::text,
  private.cierre_externo_anulado(la.lead_id), l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, null::timestamptz,
  coalesce(la.resultado_en, la.finalizado_en), 0,
  case when private.cierre_externo_anulado(la.lead_id) then 0
    when l.origen = 'referido' then
      case when p_periodo is not null then p_factor else
        private.peso_referido_conversion(date_trunc('month',
          coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima')::date) end
    when l.origen in ('landing', 'formulario') then 1
    else 0 end
from crm.lead_asignaciones la
join crm.leads l on l.id = la.lead_id
where la.resultado = 'convertido'
  and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
  and coalesce(la.resultado_en, la.finalizado_en) < p_fin
  and (p_global or la.analista_id = any(p_visibles))
  and (p_leads is null or la.lead_id in (select id from unnest(p_leads) seleccion(id)));
$function$;

CREATE OR REPLACE FUNCTION private.registrar_ajuste_si_mes_cerrado(p_lead_id uuid, p_motivo text, p_por uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- ⚠️ EL CERROJO, antes de mirar si el mes esta cerrado. Sin el, una anulacion
  -- concurrente con el sellado de ESE mes lee «abierto» —porque el sello aun no
  -- ha commiteado—, devuelve NULL, y el cierre anulado se queda pagado para
  -- siempre. Misma clave que en `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  -- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
  -- caballo del mes (convertido_en usa now() de transaccion y el ledger
  -- statement_timestamp(), caso documentado): se localiza el episodio canonico
  -- del lead SIN depender del mes de leads.convertido_en, y de el salen el
  -- PERIODO real, el referido y el peso. Cero episodios => la sancion de
  -- conversion vale CERO (nunca 1 en silencio) y queda alerta; mas de uno =>
  -- excepcion de integridad (el ledger solo permite una conversion por lead).
  select count(*),
         coalesce(bool_or(e.fue_referido), false),
         min(date_trunc('month', (e.fecha_numerador at time zone 'America/Lima'))::date)
    into v_n_episodios, v_referido, v_periodo_episodio
  from private.conversion_episodios(
         '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
         null::date, true, '{}'::uuid[], 1) e
  where e.lead_id = p_lead_id and e.tipo = 'cierre';

  if v_n_episodios > 1 then
    raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, v_n_episodios;
  end if;
  if v_n_episodios = 1 and v_periodo_episodio is distinct from v_periodo then
    -- El mes REAL del cierre es el del episodio: el cerrojo y la foto del mes
    -- sellado se toman sobre ese periodo (se re-toma el candado por si acaso).
    v_periodo := v_periodo_episodio;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo - date '2000-01-01')::integer);
    if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
      return null;
    end if;
  end if;
  if v_n_episodios = 0 then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6c_ajuste_sin_episodio',
            format('lead %s: sin episodio de cierre en el ledger; la sancion de conversion vale 0', p_lead_id));
  end if;

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_n_episodios = 0 then 0
                       when v_referido then v_peso else 1 end;

  -- ATR-4 (Miguel 31/08): «solo la conversion, siempre». La deuda de un mes
  -- sellado ya NO carga capital: el capital del analista se queda en su
  -- produccion y el de la empresa en el AUM. Solo se descuenta la conversion.
  v_pen := 0; v_usd := 0; v_detalle := '[]'::jsonb;

  -- Con capital siempre 0, la deuda existe SOLO si la conversion valia algo.
  -- numerador 0 (cierre sin episodio) => NULL POR DISENO declarado: el rastro
  -- queda en la alerta del vigia (f6c_ajuste_sin_episodio) y en la anulacion
  -- misma; no se fabrica una deuda vacia.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;

$function$;

CREATE OR REPLACE FUNCTION private.cierre_mes_ventana_desde(p_periodo date)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select ((p_periodo + interval '1 month' + interval '9 days')::timestamp
          at time zone 'America/Lima')
$function$;

CREATE OR REPLACE FUNCTION crm.corregir_fecha_cierre_comercial(p_contrato_id uuid, p_fecha date, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_motivo text := nullif(btrim(p_motivo), '');
  v_hoy_lima date := (clock_timestamp() at time zone 'America/Lima')::date;
  v_contrato public.contratos%rowtype;
  v_periodo_anterior date;
  v_periodo_nuevo date;
  v_lock_primero date;
  v_lock_segundo date;
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede corregir el cierre comercial'
      using errcode = '42501';
  end if;

  if p_contrato_id is null then
    raise exception 'El contrato es obligatorio' using errcode = '22023';
  end if;
  if p_fecha is null or not isfinite(p_fecha) or p_fecha > v_hoy_lima then
    raise exception 'La fecha de cierre comercial es invalida o futura'
      using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300 then
    raise exception 'El motivo debe tener entre 5 y 300 caracteres'
      using errcode = '22023';
  end if;

  select c.* into v_contrato
  from public.contratos c
  where c.id = p_contrato_id
  for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  if v_contrato.fecha_cierre_comercial = p_fecha then
    return jsonb_build_object(
      'ok', true,
      'cambio', false,
      'contrato_id', p_contrato_id,
      'fecha_cierre_comercial', p_fecha
    );
  end if;

  v_periodo_anterior := date_trunc(
    'month', v_contrato.fecha_cierre_comercial
  )::date;
  v_periodo_nuevo := date_trunc('month', p_fecha)::date;
  v_lock_primero := least(v_periodo_anterior, v_periodo_nuevo);
  v_lock_segundo := greatest(v_periodo_anterior, v_periodo_nuevo);

  -- Mismas llaves del sello mensual, siempre en orden para no crear deadlocks.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_lock_primero - date '2000-01-01')::integer
  );
  if v_lock_segundo is distinct from v_lock_primero then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_lock_segundo - date '2000-01-01')::integer
    );
  end if;

  if exists (
    select 1 from crm.periodos_cerrados pc
    where pc.periodo in (v_periodo_anterior, v_periodo_nuevo)
  ) then
    raise exception 'No se puede reescribir un mes comercial sellado'
      using errcode = 'P0409',
            hint = 'La correccion debe hacerse antes del sello mensual.';
  end if;

  perform pg_catalog.set_config(
    'crm.correccion_periodo_comercial', 'on', true
  );
  update public.contratos c
     set fecha_cierre_comercial = p_fecha,
         fuente_cierre_comercial = 'correccion_manual'
   where c.id = p_contrato_id;
  perform pg_catalog.set_config(
    'crm.correccion_periodo_comercial', 'off', true
  );

  -- El trigger general conserva la fila completa. Esta segunda entrada agrega
  -- el motivo de negocio que audit_log no tiene como columna propia.
  insert into public.audit_log (
    tabla, operacion, fila_id, usuario_id, data_antes, data_despues
  ) values (
    'contratos.fecha_cierre_comercial',
    'UPDATE',
    p_contrato_id::text,
    v_uid,
    jsonb_build_object(
      'fecha_cierre_comercial', v_contrato.fecha_cierre_comercial,
      'fuente', v_contrato.fuente_cierre_comercial
    ),
    jsonb_build_object(
      'fecha_cierre_comercial', p_fecha,
      'fuente', 'correccion_manual',
      'motivo', v_motivo
    )
  );

  return jsonb_build_object(
    'ok', true,
    'cambio', true,
    'contrato_id', p_contrato_id,
    'fecha_anterior', v_contrato.fecha_cierre_comercial,
    'fecha_cierre_comercial', p_fecha
  );
end;
$function$;

update crm.conversion_politica set activada_en=null,manifiesto_huella=null,resultado=null
  where unica and activada_en is not null;
-- La puerta visible sigue disponible y anuncia política pendiente/anterior:
-- el bundle nuevo no queda roto. No dejar reactivar sobre los lectores viejos.
drop function private.conversion_conciliar_y_activar(jsonb);
-- Si se instaló el complemento de declaraciones, la deuda vuelve a su
-- definición anterior y debe recuperar también su huella. Se conserva la
-- clase analítica y el techo; los dos registros operativos no se borran.
update private.analitica_leads_citas_exenciones e
set huella = md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc,pg_get_functiondef(p.oid))),
      '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
    razon = split_part(e.razon,' Desde septiembre de 2026, la deuda toma el mes comercial',1)
from pg_proc p
where e.objeto='private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'
  and p.oid=to_regprocedure(e.objeto);
update private.analitica_lc_sello
set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
commit;

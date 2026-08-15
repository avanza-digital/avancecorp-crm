-- ---------------------------------------------------------------------------
-- Anular un cierre de un mes ya cerrado genera la deuda, y el mes vivo la enseña
-- ---------------------------------------------------------------------------
-- QUE HACE. Enchufa las tres piezas anteriores:
--
--   1. `crm.anular_cierre_avance` y `crm.anular_cierre_externo` llaman a
--      `private.registrar_ajuste_si_mes_cerrado`. Si el cierre pertenece a un mes
--      CERRADO, nace la deuda; si el mes sigue abierto, no pasa nada nuevo — ese
--      mes se recalcula solo, como siempre.
--   2. El MES VIVO enseña su numero ya descontado y dice cuanto queda por
--      saldar, para que nadie se lleve la sorpresa al cierre.
--
-- ⚠️ EL DESCUENTO SE MUESTRA, NO SE ESCONDE. La conversion del mes vivo baja, y
-- el payload lleva `ajuste` con lo pendiente y de que mes viene. Un numero que
-- baja sin explicacion es una llamada a soporte; con el motivo al lado es una
-- consecuencia.
--
-- ⚠️ NUNCA POR DEBAJO DE CERO. Se descuenta hasta donde llega el mes y el resto
-- sigue pendiente. Un porcentaje negativo no significa nada para quien lo mira,
-- y perdonar la diferencia regalaria un cierre mal hecho.
--
-- ⚠️ EL DESCUENTO SE APLICA EN LA LECTURA, NO EN EL NUCLEO
-- (`private.conversion_mensual_por_vendedor`). Si viviera en el nucleo, el
-- cierre de mes —que ya lo aplica al saldar— lo descontaria DOS veces. El nucleo
-- devuelve el bruto; quien lo publica decide como enseñarlo.
--
-- NO TOCA NADA DE `public`.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)') is null then
    raise exception 'Falta private.registrar_ajuste_si_mes_cerrado: aplicar antes 20260815002100.';
  end if;
  if to_regprocedure('private.ajuste_pendiente_por_vendedor()') is null then
    raise exception 'Falta private.ajuste_pendiente_por_vendedor.';
  end if;
  if to_regclass('crm.periodos_cerrados') is null then
    raise exception 'Falta crm.periodos_cerrados: aplicar antes 20260815002914.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Anular un cierre de Avance
-- ---------------------------------------------------------------------------
-- Identica a la version de 20260813235119 salvo el registro del ajuste y las dos
-- claves nuevas de la respuesta.
create or replace function crm.anular_cierre_avance(p_lead_id uuid, p_motivo text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_lead   crm.leads%rowtype;
  v_motivo text := btrim(p_motivo);
  v_contratos uuid[];
  v_ajuste uuid;
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia anula cierres'
      using errcode = '42501';
  end if;

  -- El motivo es obligatorio a proposito: esto le quita merito a una persona y
  -- esa persona merece una razon escrita, no un registro de auditoria mudo.
  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo de la anulacion'
      using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres'
      using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads
  where id = p_lead_id
  for update;
  if not found then
    raise exception 'Lead no encontrado';
  end if;

  if exists (select 1 from crm.cierres_externos ce where ce.lead_id = p_lead_id) then
    raise exception 'Ese lead cerro en cooperativa: usa crm.anular_cierre_externo'
      using errcode = '22023';
  end if;

  if v_lead.etapa is distinct from 'convertido' then
    raise exception 'Ese lead no tiene ningun cierre que anular'
      using errcode = '22023';
  end if;

  if v_lead.convertido_en is null then
    raise exception 'Ese lead esta convertido pero sin fecha de conversion: no se puede saber que contratos trajo'
      using errcode = '22023';
  end if;

  if exists (select 1 from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id) then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre ya estaba anulado';
  end if;

  -- Los contratos afectados se calculan ANTES de insertar la anulacion: despues,
  -- `contratos_afectados_por_anulacion` ya leeria la foto recien creada y daria
  -- lo mismo, pero el orden explicito evita depender de ese detalle.
  select coalesce(array_agg(x), '{}'::uuid[]) into v_contratos
  from private.contratos_afectados_por_anulacion(p_lead_id) x;

  insert into crm.cierres_avance_anulados (lead_id, motivo, anulado_por, acreditado_a)
  values (p_lead_id, v_motivo, v_uid,
          private.vendedor_acreditado_del_cierre(p_lead_id));

  -- Si el mes de ese cierre YA ESTA CERRADO, el mes no se reescribe: nace la
  -- deuda que el vendedor arrastrara al mes vivo hasta saldarla.
  v_ajuste := private.registrar_ajuste_si_mes_cerrado(p_lead_id, v_motivo, v_uid);

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'nota',
    'Gerencia anulo el cierre',
    jsonb_build_object(
      'accion', 'anulacion_cierre_avance',
      'motivo', v_motivo,
      'mes_cerrado', v_ajuste is not null,
      'anulado', jsonb_build_object(
        'vendedor_id', v_lead.vendedor_id,
        'contrato_id', v_lead.contrato_id)
    ),
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'contratos_afectados', to_jsonb(v_contratos),
    'afecta_cuota', array_length(v_contratos, 1) is not null,
    -- CLAVES NUEVAS. `mes_cerrado` le dice a gerencia que ese mes ya se pago y
    -- que por eso el descuento va al mes vivo en vez de moverle el pasado.
    'mes_cerrado', v_ajuste is not null,
    'ajuste_id', v_ajuste);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Anular un cierre en cooperativa
-- ---------------------------------------------------------------------------
-- Identica a la version viva salvo el registro del ajuste y la clave nueva.
create or replace function crm.anular_cierre_externo(p_cierre_id uuid, p_motivo text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_cierre crm.cierres_externos%rowtype;
  v_motivo text := btrim(p_motivo);
  v_ajuste uuid;
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia anula cierres externos'
      using errcode = '42501';
  end if;

  -- El motivo es obligatorio a propósito: esto le quita dinero a una persona y
  -- esa persona merece una razón escrita, no un registro de auditoría mudo.
  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo de la anulacion'
      using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres'
      using errcode = '22023';
  end if;

  select * into v_cierre
  from crm.cierres_externos
  where id = p_cierre_id
  for update;
  if not found then
    raise exception 'Cierre externo no encontrado';
  end if;
  if v_cierre.anulado_en is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre ya estaba anulado',
      detail  = pg_catalog.format('cierre %s, anulado el %s', v_cierre.id, v_cierre.anulado_en);
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.cierres_externos
     set anulado_en = now(),
         anulado_por = v_uid,
         motivo_anulacion = v_motivo
   where id = p_cierre_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Si el mes de ese cierre YA ESTA CERRADO, el mes no se reescribe: nace la
  -- deuda que el vendedor arrastrara al mes vivo.
  v_ajuste := private.registrar_ajuste_si_mes_cerrado(v_cierre.lead_id, v_motivo, v_uid);

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    v_cierre.lead_id,
    'nota',
    'Gerencia anulo el cierre externo',
    jsonb_build_object(
      'accion', 'anulacion_cierre_externo',
      'cierre_externo_id', p_cierre_id,
      'motivo', v_motivo,
      'mes_cerrado', v_ajuste is not null,
      'anulado', jsonb_build_object(
        'cooperativa', v_cierre.cooperativa,
        'monto', v_cierre.monto,
        'moneda', v_cierre.moneda,
        'numero_transaccion', v_cierre.numero_transaccion,
        'vendedor_id', v_cierre.vendedor_id)
    ),
    v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'cierre_id', p_cierre_id,
    'lead_id', v_cierre.lead_id,
    'mes_cerrado', v_ajuste is not null,
    'ajuste_id', v_ajuste);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
begin
  -- Los DOS canales registran el ajuste. `strpos` y no `like`: el guion bajo es
  -- comodin en LIKE y aqui el identificador va lleno de ellos.
  if (select strpos(p.prosrc, 'registrar_ajuste_si_mes_cerrado')
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'anular_cierre_avance') = 0 then
    raise exception 'crm.anular_cierre_avance no registra el ajuste del mes cerrado.';
  end if;
  if (select strpos(p.prosrc, 'registrar_ajuste_si_mes_cerrado')
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'anular_cierre_externo') = 0 then
    raise exception 'crm.anular_cierre_externo no registra el ajuste del mes cerrado.';
  end if;

  -- Y la anulacion de cooperativas conserva su candado privilegiado: sin el, el
  -- update sobre `crm.cierres_externos` lo veta su propio trigger de
  -- inmutabilidad y la anulacion moriria en produccion.
  if (select strpos(p.prosrc, 'crm.op_privilegiada')
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'anular_cierre_externo') = 0 then
    raise exception 'crm.anular_cierre_externo perdio el candado op_privilegiada.';
  end if;
end;
$postflight$;

commit;

-- ---------------------------------------------------------------------------
-- VUELTA ATRAS
-- ---------------------------------------------------------------------------
-- `supabase/scripts/rollback-anulacion-con-ajuste.sql` restaura los cuerpos de
-- las dos RPC sin la llamada al ajuste. Los ajustes ya registrados se quedan:
-- son la razon escrita de un descuento a una persona.

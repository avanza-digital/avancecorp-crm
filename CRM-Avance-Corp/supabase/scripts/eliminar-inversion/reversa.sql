-- REVERSA de 20261005200945_crm_eliminar_inversion.sql («Eliminar inversión»).
-- Deja las cinco funciones reemplazadas EXACTAMENTE como estaban (huellas de producción del 05/10/2026) y retira lo nuevo.
-- Se NIEGA si ya hay copias en crm.inversiones_eliminadas: borrar la tabla perdería la auditoría de lo eliminado y, con
-- ella, la anulación que private.cierre_anulado recuerda (la conversión volvería a contar). En ese caso no se revierte:
-- se corrige hacia delante con otra migración.
-- Aplicar como la migración: un solo mensaje (`supabase db query --linked --file`), nunca sentencia a sentencia.
begin;
set local lock_timeout = '5s';

do $preflight$
begin
  set local search_path = '';
  if to_regclass('crm.inversiones_eliminadas') is null then
    raise exception 'REVERSA eliminar_inversion: la migración no está aplicada';
  end if;
  if exists (select 1 from crm.inversiones_eliminadas) then
    raise exception 'REVERSA eliminar_inversion: ya hay inversiones eliminadas con copia; no se revierte (corregir hacia delante)';
  end if;
  if md5(pg_catalog.pg_get_functiondef('private.trg_cierres_externos_inmutables()'::regprocedure)) <> '34fd3c383e636353038acca2b42e0535'
     or md5(pg_catalog.pg_get_functiondef('private.trg_depositos_reclamados_append_only()'::regprocedure)) <> '0d7eb68419c9c31bd42552b5d08d45a4'
     or md5(pg_catalog.pg_get_functiondef('private.f4_fuente_inmutable()'::regprocedure)) <> '808b1ac3481ee180f5060bd4e0bc6fa1'
     or md5(pg_catalog.pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) <> 'df71c2b1e3cd44b97c3ad84e00637266'
     or md5(pg_catalog.pg_get_functiondef('private.conversion_bloquear_retiro_trg()'::regprocedure)) <> '823bf82cc20e4e4ca95381e4ce683ea1'
     or md5(pg_catalog.pg_get_functiondef('private.leads_before_update()'::regprocedure)) <> '4ae909f2d56ca650b5595b505e6aa51d' then
    raise exception 'REVERSA eliminar_inversion: alguna función cambió después de la migración; revisar antes de revertir';
  end if;
end
$preflight$;

-- 1 · Las funciones vuelven a su texto original (primero las que leen la tabla nueva).
CREATE OR REPLACE FUNCTION private.trg_cierres_externos_inmutables()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo no se elimina: gerencia lo corrige via crm.corregir_cierre_externo',
      hint    = 'El cierre respalda una conversion ya contada; borrar la fila dejaria un convertido sin perfil ni cierre (invariante P4).';
  end if;

  if not v_priv then
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo solo se corrige via crm.corregir_cierre_externo',
      detail  = pg_catalog.format('cierre %s (lead %s)', old.id, old.lead_id);
  end if;

  -- Con la válvula encendida, las columnas de identidad se restauran en
  -- silencio (no con excepción): la RPC de corrección no las manda, así que
  -- esto es un cinturón contra bugs futuros de rutas DEFINER, no una rama que
  -- un usuario pueda pisar.
  new.id := old.id;
  new.lead_id := old.lead_id;
  new.vendedor_id := old.vendedor_id;
  new.documento_tipo := old.documento_tipo;
  new.documento := old.documento;
  new.nombre_completo := old.nombre_completo;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;

  -- La anulación es de UNA SOLA DIRECCIÓN. Des-anular sería volver a pagar un
  -- cierre que ya se declaró falso, y eso no se hace en silencio desde una ruta
  -- DEFINER: aquí se restaura y punto. (Aquí SÍ con excepción y no en silencio:
  -- si una RPC futura intentara resucitar un cierre anulado, el error tiene que
  -- salir a la superficie, no perderse en un 200 mudo.)
  if old.anulado_en is not null
     and (new.anulado_en is null
          or new.anulado_por is distinct from old.anulado_por
          or new.anulado_en is distinct from old.anulado_en) then
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo anulado no se restablece',
      detail  = pg_catalog.format('cierre %s (lead %s), anulado el %s',
                                  old.id, old.lead_id, old.anulado_en);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.trg_depositos_reclamados_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  raise exception using
    errcode = 'P0409',
    message = 'Un numero de operacion reclamado no se edita ni se borra',
    hint    = 'Esta tabla existe para no olvidar: si se pudiera limpiar, el mismo deposito se podria cobrar dos veces.';
end;
$function$;

CREATE OR REPLACE FUNCTION private.f4_fuente_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_table_schema='crm' and tg_table_name='inversion_eventos' and tg_op='DELETE' then
    if old.tipo='registro' and exists (
      select 1 from crm.contratos_eliminados_auditoria a
      join private.contrato_eliminaciones r on r.contrato_id=a.contrato_id
      where r.token::text=current_setting('crm.contrato_registro_eliminacion',true)
        and r.solicitado_por=(select auth.uid()) and a.eliminado_por=r.solicitado_por
        and a.snapshot->>'version' in ('3','4')
        and a.snapshot#>>'{inversion,id}'=old.inversion_id::text
        and a.snapshot->'inversion_eventos' @> jsonb_build_array(to_jsonb(old))
    ) then return old; end if;
  end if;
  if tg_table_name in ('inversion_ajustes_mes_cerrado','inversion_eventos','inversion_solicitud_revisiones','inversion_solicitud_correcciones') then
    raise exception 'El historial de una inversión no se modifica ni se elimina' using errcode='P0409';
  end if;
  if new.es_cierre_inicial is distinct from old.es_cierre_inicial
     or new.fecha_comercial is distinct from old.fecha_comercial
     or new.fecha_imputacion is distinct from old.fecha_imputacion
     or new.comprobante_objeto_id is distinct from old.comprobante_objeto_id then
    raise exception 'La clase, las fechas y el comprobante del cierre conservan su registro original' using errcode='P0409';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.cierre_anulado(p_lead_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id and ce.es_cierre_inicial
      and ce.anulado_en is not null
  ) or exists (
    select 1
    from crm.cierres_avance_anulados ca
    where ca.lead_id = p_lead_id
  )
$function$;

CREATE OR REPLACE FUNCTION private.conversion_bloquear_retiro_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_periodo date;
begin
  if not exists(select 1 from crm.conversion_acreditaciones
      where fuente_tipo='contrato' and fuente_id=new.contrato_id) then return new; end if;
  -- La eliminación ya posee el contrato. NOWAIT evita un ciclo con otra
  -- puerta que posea el lead y espere el contrato; el caller debe reintentar.
  perform 1 from crm.leads l where l.contrato_id=new.contrato_id or l.id in
    (select ca.lead_id from crm.conversion_acreditaciones ca
     where ca.fuente_tipo='contrato' and ca.fuente_id=new.contrato_id)
    order by l.id for update nowait;
  for v_periodo in select distinct periodo_comercial from crm.conversion_acreditaciones
      where fuente_tipo='contrato' and fuente_id=new.contrato_id order by periodo_comercial loop
    perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
  end loop;
  return new;
exception when lock_not_available then
  raise exception 'El lead tiene otra operacion en curso; reintenta la retirada' using errcode='PT409';
end;
$function$;

-- P4 vuelve a su texto de producción (sin el ancla copiada).
CREATE OR REPLACE FUNCTION private.leads_before_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'crm', 'public'
AS $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Columnas inmutables: restaurar siempre desde OLD.
  new.id := old.id;
  new.creado_por := old.creado_por;
  new.alta_manual := old.alta_manual;
  new.creado_en := old.creado_en;
  new.actualizado_en := now();

  -- Conversión y enlace al portal: SOLO desde una RPC privilegiada
  -- (que fija crm.op_privilegiada='on'). Un cliente API no puede convertir
  -- ni enlazar perfil_id/contrato_id a mano.
  if not v_priv then
    if new.etapa = 'convertido' and old.etapa <> 'convertido' then
      raise exception 'La conversión a cliente solo se hace vía la operación de conversión';
    end if;
    new.perfil_id := old.perfil_id;
    new.contrato_id := old.contrato_id;
    new.convertido_en := old.convertido_en;

    -- ── SELLO DEL ORIGEN (migración D, 2026-08-11) ────────────────────────
    -- El origen se elige al ALTA y no se vuelve a mover. Lo que esto protege
    -- NO es un mes ya contado —el snapshot `lead_asignaciones.origen` ya era
    -- inmutable por `trg_lead_asignaciones_00_inmutables`— sino dos cosas del
    -- presente y del futuro:
    --   · el origen que copiará `private.trg_leads_asignaciones` al abrir el
    --     PRÓXIMO episodio de este lead (y ése sí sale del divisor del mes en
    --     curso si dice 'referido');
    --   · el bloque `referidos.dados_de_alta`, único número del payload que
    --     lee esta columna viva, agrupado por el mes de ALTA del lead.
    -- Se avisa con EXCEPCIÓN en vez de restaurar en silencio porque el store
    -- del front es optimista: un 200 mudo dejaría al usuario convencido de
    -- que corrigió.
    -- Va DENTRO de `if not v_priv`, a propósito: encima del gate el dato
    -- quedaría incorregible para siempre y el único remedio sería
    -- `disable trigger` en producción, que CLAUDE.md prohíbe.
    -- `is distinct from` (y no `<>`) hace que un UPDATE de payload completo que
    -- reenvía el MISMO valor no lance nada: es el caso de seed-demo.mjs y de
    -- test-rls.mjs, los dos únicos escritores que mandan `origen` en un UPDATE.
    if new.origen is distinct from old.origen then
      raise exception using
        errcode = 'P0409',
        message = 'El origen de un lead no se cambia despues del alta',
        detail  = pg_catalog.format(
          'lead %s: origen actual %L, intento %L',
          old.id, old.origen, new.origen),
        hint    = 'El origen se elige al crear el lead (crm.crear_lead_si_disponible). '
                  'La conversion mensual lee la FOTO del episodio, que ya es inmutable: '
                  'cambiar la ficha no mueve ningun mes ya contado, pero si moveria el '
                  'origen de los episodios FUTUROS de este lead y el bloque de referidos '
                  'dados de alta de su mes de creacion.';
    end if;
  end if;

  -- ── P4 RELAJADA (migración cierres externos, 2026-08-12) ────────────────
  -- Invariante de negocio en la transición (no como CHECK de tabla). Antes:
  -- «convertido ⇒ perfil_id no nulo». Ahora un convertido puede carecer de
  -- perfil SI Y SOLO SI tiene cierre externo (invirtió en una cooperativa y
  -- el portal no lo conoce). El EXISTS corre solo en la rama rara (convertido
  -- sin perfil) y lo sirve el UNIQUE de lead_id. Nótese que P2 sigue intacta:
  -- sin válvula no hay transición a convertido, con o sin cierre.
  if new.etapa = 'convertido' and new.perfil_id is null
     and not exists (
       select 1 from crm.cierres_externos ce where ce.lead_id = new.id and ce.es_cierre_inicial
     ) then
    raise exception 'Un lead convertido debe estar enlazado a un perfil de cliente';
  end if;

  return new;
end;
$function$

;

-- 2 · Se retira lo nuevo.
drop function crm.eliminar_inversion_fn(uuid, text);
drop function private.registrar_inversion_eliminada_avance(jsonb, uuid, uuid, text, text, jsonb);
drop function private.eliminar_inversion_cooperativa(jsonb, uuid, text, text, jsonb);
drop function private.inversion_eliminacion_dependencias_conocidas();
drop function private.inversion_motivo_no_eliminable(text, uuid, uuid);
drop function private.eliminar_inversion_contexto(uuid);
drop function private.eliminar_inversion_roles(uuid);
drop function private.conversion_coordinar_retiro_fuente(text, uuid);
drop function private.inversion_eliminacion_autoriza(text, uuid, jsonb);
drop table crm.inversiones_eliminadas;
drop function private.motivo_normalizado(text);
drop function private.proteger_inversion_eliminada();

do $postflight$
begin
  set local search_path = '';
  if md5(pg_catalog.pg_get_functiondef('private.trg_cierres_externos_inmutables()'::regprocedure)) <> '668e5d25885fe5227f32cb3e05200c01'
     or md5(pg_catalog.pg_get_functiondef('private.trg_depositos_reclamados_append_only()'::regprocedure)) <> 'd4a77574fb58d58cefdc9a008b22b2ea'
     or md5(pg_catalog.pg_get_functiondef('private.f4_fuente_inmutable()'::regprocedure)) <> '014b8e701d2219a53f88d4e42376edd7'
     or md5(pg_catalog.pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) <> '8427218ba089192bd9702e052492f70b'
     or md5(pg_catalog.pg_get_functiondef('private.conversion_bloquear_retiro_trg()'::regprocedure)) <> '4704dfb4b9602178445971a2dbaa7820'
     or md5(pg_catalog.pg_get_functiondef('private.leads_before_update()'::regprocedure)) <> 'e0b68ad528a15ddfe80197bdac1c180b' then
    raise exception 'REVERSA eliminar_inversion: las funciones no quedaron como en producción antes de la migración';
  end if;
  if to_regclass('crm.inversiones_eliminadas') is not null or to_regprocedure('crm.eliminar_inversion_fn(uuid,text)') is not null then
    raise exception 'REVERSA eliminar_inversion: quedaron objetos nuevos';
  end if;
end
$postflight$;

commit;

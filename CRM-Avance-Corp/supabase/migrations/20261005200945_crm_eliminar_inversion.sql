-- 20261005200945_crm_eliminar_inversion.sql
--
-- «Eliminar inversión» para admin y gerencia en las tres empresas (Avance, Prodelco, Qorilazo).
-- Pedido de Miguel (05/10/2026): «mi usuario admin y gerencia deben poder eliminar cualquier inversión en las tres
-- empresas que hay para registrar inversiones». Decisiones del mismo día (AskUserQuestion):
--   D1 · ELIMINAR CON COPIA: la inversión desaparece del capital, la cartera y la conversión; queda una copia inmutable con
--        motivo (obligatorio) y autor. No es la anulación ATR-4 (que conserva el capital).
--   D2 · CONVERSIÓN: si la inversión es la conversión de un lead y no está anulada, la ANULA (por la puerta de gerencia de
--        siempre, con su ajuste si el mes está cerrado) y la elimina en un solo paso; SOLO gerencia. Respeta la regla
--        «la anulación de gerencia es la única puerta que mueve la conversión».
--   D3 · CON HISTORIA PROPIA NO SE ELIMINA: renovación, upgrade, reinversión, retiro, ajuste de mes cerrado, cotitulares
--        históricos, cambios de analista o solicitudes posteriores → mensaje claro (P0409). Eliminar es para registros
--        equivocados.
--
-- QUÉ HACE
--   1. crm.inversiones_eliminadas: copia inmutable (RLS sin políticas, sin grants; trigger de auditoría que enmascara la
--      copia; UPDATE/DELETE/TRUNCATE prohibidos). Una fila por fuente eliminada (contrato o cierre externo).
--   2. Puerta crm.eliminar_inversion_fn(p_fuente_id, p_motivo) — DEFINER (justificación: las tablas de inversiones,
--      cierres y su auditoría no tienen grants para authenticated; el actor y su rol se resuelven SIEMPRE en el servidor
--      con auth.uid(), nunca se reciben). La fuente es lo que la ficha conoce de cada inversión (InversionFuente.fuente_id):
--      el contrato (Avance) o el cierre externo (cooperativas), tenga o no fila en crm.inversiones.
--        · Rol: admin/superadmin del portal (perfil activo) o gerencia del CRM (private.rol_crm). Otro → 42501.
--        · Avance: lo elimina crm.contrato_eliminar_auditado (copia v4 de contrato, cuotas, documentos, inversión, eventos y
--          solicitudes; 15/09). Esa función NO se toca: está DECLARADA en el vigía analítico y cambiar su cuerpo caducaría su
--          huella (alerta f6a). Por eso, en Avance, la puerta exige admin/superadmin del portal, igual que ella (hoy los dos
--          perfiles de gerencia lo son). La copia de esta tabla enlaza la del contrato (contrato_auditoria_id).
--        · Cooperativas: núcleo nuevo private.eliminar_inversion_cooperativa (copia + borrado en la misma transacción).
--   3. Válvula de un solo uso para tres candados que hoy prohíben SIEMPRE el DELETE (cierre externo, depósito reclamado y
--      evento de inversión): solo abren si la fila es IDÉNTICA a la copiada, en la MISMA transacción (pg_current_xact_id),
--      con la llave (valvula) de ESA copia en crm.inversion_eliminacion y el actor de la copia (auth.uid()). Una sola
--      definición: private.inversion_eliminacion_autoriza. UPDATE sigue igual que hoy.
--   4. private.cierre_anulado(lead) recuerda también la conversión anulada y ELIMINADA. Sin esto, la rama de conversión
--      anterior a septiembre (lead_asignaciones, que pone peso 0 si cierre_anulado) volvería a contar la conversión de una
--      cooperativa cuyo cierre anulado ya no existe. En Avance la anulación vive en crm.cierres_avance_anulados y no se pierde.
--   5. Coordinación con el sellado de conversión al retirar una fuente: private.conversion_coordinar_retiro_fuente (UNA
--      definición: el trigger de contratos private.conversion_bloquear_retiro_trg pasa a llamarla con la misma lógica).
--
-- CAPAS: puerta (crm.eliminar_inversion_fn) → núcleo (private.*) → tablas. La puerta llama además a otras dos puertas
--   (crm.anular_cierre_externo / crm.anular_cierre_avance) y a crm.contrato_eliminar_auditado: misma capa, sin saltos ni
--   inversiones; así se reutilizan tal cual, sin copiarlas.
-- CENSO ANALÍTICO: ninguna función nueva combina `crm.leads`/«reunion» con count(/sum(1) (no entra al censo).
-- negocio_id: como las 101 tablas crm (el CRM es de un solo negocio), la tabla nueva no lo lleva (deuda conocida).
-- NO toca objetos de public. Los archivos de Storage (PDF, comprobantes) se conservan como evidencia (igual que el 15/09).
-- REVERSA: supabase/scripts/eliminar-inversion/reversa.sql (se niega si ya hay copias: no se pierde auditoría).
-- r2 (Codex r1, CHANGES_REQUESTED): P1 Avance clasificaba sin bloquear el contrato → ahora se bloquea antes (mismo candado
--   consultivo y orden que contrato_eliminar_auditado) junto con TODOS sus leads; prueba de dos conexiones en
--   supabase/scripts/eliminar-inversion/carrera-avance.sh. P1 eventos de cooperativa: D3 de Miguel enumera operaciones de
--   NEGOCIO (renovación, upgrade, reinversión, retiro, ajuste de mes cerrado); la corrección y la anulación son
--   administrativas del mismo registro y D2 elimina justamente conversiones ya anuladas: se permiten (quedan en la copia),
--   pero con lista explícita — un tipo de evento futuro cuenta como historia. En Avance el rechazo de eventos distintos de
--   «registro» es de crm.contrato_eliminar_auditado (congelada por el vigía). Riesgos: el rol CRM del actor también se
--   bloquea (crm.equipo FOR SHARE); el depósito reclamado se LIBERA a propósito con la eliminación (para que el registro
--   correcto pueda usarlo; el número queda en la copia); pruebas añadidas de conversión de septiembre (rama de
--   acreditaciones), solicitud con lead de origen, cierre sin fila de inversión y corrección previa.
-- r3 (auditor-rls r2, CHANGES_REQUESTED, sin P0): P1 la solicitud de alta de una cooperativa guarda fuente.cierre_id (no
--   fuente.id; verificado en producción: 16/16): D3 rechazaba TODA cooperativa F4 → clave real por tipo + misma persona y
--   empresa (0 discrepancias en producción). P1 invariante P4: el cierre inicial es el ancla del lead convertido sin perfil;
--   borrarlo lo dejaba imposible de editar → private.leads_before_update acepta como ancla la copia de una conversión
--   anulada y eliminada (misma función de producción + una condición; preflight con su huella). P2 la conversión también la
--   decide la acreditación por fuente (62 acreditaciones sobre contratos que el lead no enlaza) y su lead manda; si discrepa
--   del enlazado → P0409. P3: op_privilegiada solo si hay leads enlazados; rol_actor = el que habilitó; un CHECK fallido de la
--   copia se relanza sin la fila; postflight con dueños. Mes cerrado: la ruta es la anulación de gerencia de siempre, sin
--   cambios; no se ensaya en el banco (exige toda la maquinaria del sellado).
-- CANDADOS (convención de la casa, B10): la exclusión de migraciones (candado consultivo crm_migracion_funciones) se toma
--   ANTES de la instantánea, a nivel de SESIÓN y en una transacción previa del mismo mensaje; el preflight exige que ESTA
--   sesión lo tenga y se suelta al final. La transacción principal va en REPEATABLE READ (preflight y postflight ven la
--   misma instantánea). Aplicar en UN mensaje: `supabase db query --linked --file` (nunca sentencia a sentencia).
-- PRUEBAS: supabase/scripts/eliminar-inversion/test-eliminar-inversion.sql (banco, 12 bloques, ROLLBACK) y mutantes.sh.

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  -- Esta sesión tiene el candado de migraciones (tomado ANTES de la instantánea); pg_locks no es MVCC: es el estado de hoy.
  if not exists (select 1 from pg_catalog.pg_locks l
                 where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid() and l.granted
                   and l.mode = 'ExclusiveLock' and l.objsubid = 1
                   and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'PREFLIGHT eliminar_inversion: esta sesión no tiene el candado de migraciones (crm_migracion_funciones)';
  end if;
  -- Lo que se reemplaza, exactamente como está en producción (05/10/2026).
  if md5(pg_catalog.pg_get_functiondef('private.trg_cierres_externos_inmutables()'::regprocedure)) <> '668e5d25885fe5227f32cb3e05200c01'
     or md5(pg_catalog.pg_get_functiondef('private.trg_depositos_reclamados_append_only()'::regprocedure)) <> 'd4a77574fb58d58cefdc9a008b22b2ea'
     or md5(pg_catalog.pg_get_functiondef('private.f4_fuente_inmutable()'::regprocedure)) <> '014b8e701d2219a53f88d4e42376edd7'
     or md5(pg_catalog.pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) <> '8427218ba089192bd9702e052492f70b'
     or md5(pg_catalog.pg_get_functiondef('private.conversion_bloquear_retiro_trg()'::regprocedure)) <> '4704dfb4b9602178445971a2dbaa7820'
     or md5(pg_catalog.pg_get_functiondef('private.leads_before_update()'::regprocedure)) <> 'e0b68ad528a15ddfe80197bdac1c180b' then
    raise exception 'PREFLIGHT eliminar_inversion: cambió una de las funciones que se reemplazan; revisar antes de aplicar';
  end if;
  -- Lo que se llama sin tocar: si cambia, cambian las garantías de esta puerta.
  if md5(pg_catalog.pg_get_functiondef('crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure)) <> 'c954f109757ccfa18692d0bff54f903c'
     or md5(pg_catalog.pg_get_functiondef('crm.anular_cierre_externo(uuid,text)'::regprocedure)) <> 'f568b78fc917d56cb00b5f88efd85deb'
     or md5(pg_catalog.pg_get_functiondef('crm.anular_cierre_avance(uuid,text)'::regprocedure)) <> '23e3be1974e08a1ec8aa61abe53242c3'
     or md5(pg_catalog.pg_get_functiondef('private.rol_crm(uuid)'::regprocedure)) <> '99827f3fe2fbc3cfae5668c30015c758' then
    raise exception 'PREFLIGHT eliminar_inversion: cambió una función que la puerta llama; revisar antes de aplicar';
  end if;
  if to_regclass('crm.inversiones_eliminadas') is not null
     or to_regprocedure('crm.eliminar_inversion_fn(uuid,text)') is not null
     or to_regprocedure('private.inversion_eliminacion_autoriza(text,uuid,jsonb)') is not null then
    raise exception 'PREFLIGHT eliminar_inversion: los objetos nuevos ya existen';
  end if;
  -- Los tres candados están en su modo normal sobre sus tablas.
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgenabled = 'O' and (
        (t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_externos_00_inmutables')
        or (t.tgrelid = 'crm.depositos_reclamados'::regclass and t.tgname = 'trg_depositos_reclamados_00_append_only')
        or (t.tgrelid = 'crm.inversion_eventos'::regclass and t.tgname = 'trg_inversion_eventos_inmutables'))) <> 3 then
    raise exception 'PREFLIGHT eliminar_inversion: los candados de cierres, depósitos o eventos no están en su modo normal';
  end if;
end
$preflight$;

-- ── 1 · Tabla: la copia inmutable ──────────────────────────────────────────────────────────────────────────────────────
create table crm.inversiones_eliminadas (
  id uuid primary key default gen_random_uuid(),
  fuente_tipo text not null check (fuente_tipo in ('contrato', 'cierre_externo')),
  fuente_id uuid not null,
  inversion_id uuid,
  empresa text not null check (empresa in ('avance', 'prodelco', 'qorilazo')),
  inversionista_id uuid,
  lead_id uuid,
  es_conversion boolean not null,
  conversion_anulada boolean not null,
  anulacion jsonb check (anulacion is null or jsonb_typeof(anulacion) = 'object'),
  motivo text not null check (length(btrim(motivo)) between 5 and 300),
  eliminado_por uuid not null,
  rol_actor text not null check (rol_actor in ('admin', 'superadmin', 'gerencia')),
  eliminado_en timestamptz not null default statement_timestamp(),
  contrato_auditoria_id uuid references crm.contratos_eliminados_auditoria (id),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  archivos jsonb not null default '[]'::jsonb check (jsonb_typeof(archivos) = 'array'),
  valvula uuid not null default gen_random_uuid() unique,
  transaccion xid8 not null default pg_current_xact_id(),
  unique (fuente_tipo, fuente_id),
  check ((fuente_tipo = 'contrato') = (contrato_auditoria_id is not null)),
  check ((fuente_tipo = 'contrato') = (empresa = 'avance')),
  check (not conversion_anulada or es_conversion),
  check (not es_conversion or lead_id is not null)
);
alter table crm.inversiones_eliminadas enable row level security;
create index inversiones_eliminadas_lead_anulada_idx on crm.inversiones_eliminadas (lead_id) where conversion_anulada;

create function private.proteger_inversion_eliminada()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'La copia de una inversión eliminada es inmutable' using errcode = '42501';
end $$;

create trigger trg_audit_inversiones_eliminadas after insert on crm.inversiones_eliminadas
  for each row execute function private.log_audit_sin_secretos('snapshot', 'archivos', 'valvula', 'anulacion');
create trigger trg_inversiones_eliminadas_inmutables before update or delete on crm.inversiones_eliminadas
  for each row execute function private.proteger_inversion_eliminada();
create trigger trg_inversiones_eliminadas_no_truncate before truncate on crm.inversiones_eliminadas
  for each statement execute function private.proteger_inversion_eliminada();

-- ── 2 · Núcleo: válvula única de los tres candados ─────────────────────────────────────────────────────────────────────
create function private.inversion_eliminacion_autoriza(p_parte text, p_clave uuid, p_fila jsonb)
returns boolean language sql stable set search_path = '' as $$
  select coalesce(current_setting('crm.inversion_eliminacion', true), '') <> ''
    and (select auth.uid()) is not null
    and exists (
      select 1 from crm.inversiones_eliminadas a
      where a.valvula::text = current_setting('crm.inversion_eliminacion', true)
        and a.transaccion = pg_current_xact_id_if_assigned()
        and a.eliminado_por = (select auth.uid())
        and a.fuente_tipo = 'cierre_externo'
        and case p_parte
              when 'cierre' then a.fuente_id = p_clave and a.snapshot -> 'cierre' = p_fila
              when 'deposito' then a.fuente_id = p_clave and a.snapshot -> 'depositos' @> jsonb_build_array(p_fila)
              when 'evento' then a.inversion_id = p_clave and a.snapshot -> 'eventos' @> jsonb_build_array(p_fila)
              else false
            end)
$$;

-- Los tres candados: idénticos a producción salvo la válvula del DELETE.
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
    -- Única excepción (05/10/2026): la eliminación auditada de una inversión (crm.eliminar_inversion_fn), con la
    -- llave de un solo uso de SU copia, en SU transacción, del actor de la copia y la fila idéntica a la copiada.
    if private.inversion_eliminacion_autoriza('cierre', old.id, pg_catalog.to_jsonb(old)) then
      return old;
    end if;
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
  -- Única excepción (05/10/2026): el depósito de un cierre que se elimina con copia auditada (crm.eliminar_inversion_fn).
  if tg_op = 'DELETE' and private.inversion_eliminacion_autoriza('deposito', old.cierre_id, pg_catalog.to_jsonb(old)) then
    return old;
  end if;
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
    -- 05/10/2026: el evento de una inversión de cooperativa que se elimina con copia auditada (crm.eliminar_inversion_fn).
    if private.inversion_eliminacion_autoriza('evento', old.inversion_id, to_jsonb(old)) then return old; end if;
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

-- ── 3 · Núcleo: la anulación sobrevive a la eliminación ────────────────────────────────────────────────────────────────
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
  ) or exists (
    -- 05/10/2026: una conversión anulada cuyo registro se eliminó después (crm.eliminar_inversion_fn) sigue anulada.
    select 1
    from crm.inversiones_eliminadas ie
    where ie.lead_id = p_lead_id and ie.conversion_anulada
  )
$function$;

-- P4: el lead convertido de una cooperativa conserva su ancla cuando su cierre se elimina con copia. Idéntica a producción
-- salvo la segunda condición NOT EXISTS (preflight con su huella; la reversa la deja como estaba).
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
     )
     -- 05/10/2026 (P4, auditor-rls r2): la conversión de cooperativa anulada y ELIMINADA con copia (crm.eliminar_inversion_fn)
     -- sigue siendo el ancla del lead convertido: sin esto el lead quedaría imposible de editar para siempre.
     and not exists (
       select 1 from crm.inversiones_eliminadas ie
       where ie.lead_id = new.id and ie.fuente_tipo = 'cierre_externo' and ie.conversion_anulada
     ) then
    raise exception 'Un lead convertido debe estar enlazado a un perfil de cliente';
  end if;

  return new;
end;
$function$;

-- ── 4 · Núcleo: coordinación con el sellado al retirar una fuente (una sola definición) ────────────────────────────────
create function private.conversion_coordinar_retiro_fuente(p_tipo text, p_fuente uuid)
returns void language plpgsql set search_path = '' as $$
declare v_periodo date;
begin
  if not exists(select 1 from crm.conversion_acreditaciones
      where fuente_tipo=p_tipo and fuente_id=p_fuente) then return; end if;
  -- La eliminación ya posee la fuente. NOWAIT evita un ciclo con otra
  -- puerta que posea el lead y espere la fuente; el caller debe reintentar.
  perform 1 from crm.leads l where (p_tipo='contrato' and l.contrato_id=p_fuente) or l.id in
    (select ca.lead_id from crm.conversion_acreditaciones ca
     where ca.fuente_tipo=p_tipo and ca.fuente_id=p_fuente)
    order by l.id for update nowait;
  for v_periodo in select distinct periodo_comercial from crm.conversion_acreditaciones
      where fuente_tipo=p_tipo and fuente_id=p_fuente order by periodo_comercial loop
    perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
  end loop;
exception when lock_not_available then
  raise exception 'El lead tiene otra operacion en curso; reintenta la retirada' using errcode='PT409';
end $$;

CREATE OR REPLACE FUNCTION private.conversion_bloquear_retiro_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- Misma lógica de siempre; desde el 05/10/2026 vive en private.conversion_coordinar_retiro_fuente.
  perform private.conversion_coordinar_retiro_fuente('contrato', new.contrato_id);
  return new;
end;
$function$;

-- ── 5 · Núcleo: rol, contexto, historia y dependencias ─────────────────────────────────────────────────────────────────
create function private.eliminar_inversion_roles(p_actor uuid)
returns jsonb language plpgsql set search_path = '' as $$
declare v_portal text;
begin
  -- Se bloquean el perfil y su membresía del CRM: una baja o un cambio de rol (portal o gerencia) no se intercala entre
  -- autorizar y eliminar (Codex r1: private.rol_crm lee crm.equipo, que el candado del perfil no cubría).
  select p.rol into v_portal from public.perfiles p where p.id = p_actor and p.activo for share;
  perform 1 from crm.equipo e where e.perfil_id = p_actor order by e.perfil_id for share;
  return jsonb_build_object(
    'portal', case when v_portal in ('admin', 'superadmin') then v_portal end,
    'gerencia', coalesce(private.rol_crm(p_actor) = 'gerencia', false));
end $$;

create function private.eliminar_inversion_contexto(p_fuente uuid)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_ce crm.cierres_externos%rowtype;
  v_inv crm.inversiones%rowtype;
  v_lead uuid;
  v_tipo text;
  v_empresa text;
  v_es_conversion boolean := false;
  v_anulada boolean := false;
  v_lead_acreditado uuid;
  v_enlazados boolean := false;
begin
  if p_fuente is null then return null; end if;
  select * into v_ce from crm.cierres_externos where id = p_fuente for update;
  if found then
    v_tipo := 'cierre_externo';
    v_empresa := v_ce.cooperativa;
    select * into v_inv from crm.inversiones where cierre_externo_id = p_fuente for update;
    v_es_conversion := v_ce.es_cierre_inicial or coalesce(v_inv.es_primera_conversion, false);
    if v_es_conversion then v_lead := v_ce.lead_id; end if;
  else
    -- Avance (Codex r1, P1): el contrato se bloquea ANTES de clasificarlo, con el mismo candado consultivo y en el mismo
    -- orden que crm.contrato_eliminar_auditado. Con la fila bloqueada nadie le enlaza un lead ni le crea una inversión
    -- (sus FKs piden FOR KEY SHARE) mientras se decide si es una conversión; y los leads que ya lo apuntan se bloquean
    -- TODOS antes de mirar su etapa, para que ninguno se convierta a mitad.
    perform pg_advisory_xact_lock(hashtextextended('contrato_eliminar_auditado:' || p_fuente::text, 0));
    perform 1 from public.contratos c where c.id = p_fuente for update;
    if not found then return null; end if;
    v_tipo := 'contrato';
    v_empresa := 'avance';
    select * into v_inv from crm.inversiones where contrato_id = p_fuente for update;
    perform 1 from crm.leads l where l.contrato_id = p_fuente order by l.id for update;
    select l.id into v_lead from crm.leads l
      where l.contrato_id = p_fuente and l.etapa = 'convertido'
      order by l.id limit 1;
    v_es_conversion := v_lead is not null or coalesce(v_inv.es_primera_conversion, false);
    v_enlazados := exists (select 1 from crm.leads l where l.contrato_id = p_fuente);
  end if;
  -- Desde septiembre la conversión la decide el hecho de acreditación (único por fuente), que puede apuntar a un contrato
  -- distinto del leads.contrato_id del lead (auditor-rls r2, P2: 62 casos en producción). Si la fuente está acreditada
  -- (cuenta, está en un mes sellado o contará), es conversión y su lead manda; si discrepa del lead enlazado, no se decide aquí.
  select ca.lead_id into v_lead_acreditado from crm.conversion_acreditaciones ca
    where ca.fuente_tipo = v_tipo and ca.fuente_id = p_fuente and ca.estado in ('acreditada', 'mes_sellado', 'fecha_futura')
    for update;
  if v_lead_acreditado is not null then
    if v_lead is not null and v_lead is distinct from v_lead_acreditado then
      raise exception 'La conversión de esta inversión no coincide con su lead; requiere revisión' using errcode = 'P0409';
    end if;
    v_lead := v_lead_acreditado;
    v_es_conversion := true;
    perform 1 from crm.leads l where l.id = v_lead for update;
  end if;
  v_anulada := v_lead is not null and private.cierre_anulado(v_lead);
  return jsonb_build_object(
    'tipo', v_tipo, 'fuente_id', p_fuente, 'empresa', v_empresa,
    'inversion_id', v_inv.id, 'inversionista_id', coalesce(v_inv.inversionista_id, v_ce.inversionista_id),
    'es_conversion', v_es_conversion, 'lead_id', v_lead,
    'conversion_anulada', v_es_conversion and v_anulada,
    'leads_enlazados', v_enlazados);
end $$;

create function private.inversion_motivo_no_eliminable(p_tipo text, p_fuente uuid, p_inversion uuid)
returns text language sql stable set search_path = '' as $$
  select case
    when p_tipo = 'contrato' and exists (select 1 from public.contratos c
           where c.id = p_fuente and (c.estado = 'renovado' or c.renovado_a_id is not null))
      then 'Este contrato ya se renovó: tiene historia propia y no se elimina'
    when p_tipo = 'contrato' and exists (select 1 from public.contratos c where c.renovado_a_id = p_fuente)
      then 'Este contrato es la renovación de otro: tiene historia propia y no se elimina'
    when p_tipo = 'contrato' and exists (select 1 from crm.operaciones_cartera o
           where o.contrato_origen_id = p_fuente or o.contrato_nuevo_id = p_fuente)
      then 'Este contrato es parte de un upgrade o una renovación registrados: no se elimina'
    when p_tipo = 'contrato' and exists (select 1 from crm.reasignaciones_analista r where r.contrato_id = p_fuente)
      then 'Este contrato tiene cambios de analista registrados: no se elimina'
    when p_tipo = 'cierre_externo' and exists (select 1 from crm.inversion_solicitud_origenes o where o.fuente_id = p_fuente)
      then 'Esta inversión dio origen a otra (reinversión): tiene historia propia y no se elimina'
    when p_tipo = 'cierre_externo' and exists (select 1 from crm.postventa_retiros r where r.fuente_id = p_fuente)
      then 'Esta inversión tiene una solicitud de retiro registrada: no se elimina'
    when p_inversion is not null and exists (select 1 from crm.inversion_ajustes_mes_cerrado a where a.inversion_id = p_inversion)
      then 'Esta inversión tiene ajustes de un mes cerrado: no se elimina'
    when p_inversion is not null and exists (select 1 from crm.inversion_cotitular_origenes o
           where o.inversion_id = p_inversion and (o.origen_registro <> 'alta' or p_tipo = 'cierre_externo'))
      then 'Esta inversión tiene vínculos históricos de cotitulares: no se elimina'
    -- La solicitud de ALTA no es historia: la reconoce la clave real de su fuente (Avance guarda fuente.id; las cooperativas
    -- guardan fuente.cierre_id — auditor-rls r2, verificado en producción) y la misma persona y empresa de la inversión.
    when p_inversion is not null and exists (select 1 from crm.inversion_solicitudes s
           join crm.inversiones i on i.id = p_inversion
           where s.inversion_id = p_inversion
             and (s.estado <> 'confirmada'
                  or s.resultado #>> (case when p_tipo = 'contrato' then array['fuente', 'id'] else array['fuente', 'cierre_id'] end)
                       is distinct from p_fuente::text
                  or s.inversionista_id is distinct from i.inversionista_id
                  or s.empresa_id is distinct from i.empresa_id))
      then 'Esta inversión tiene solicitudes posteriores registradas: no se elimina'
    when p_inversion is not null and exists (select 1 from crm.inversion_solicitudes s
           join crm.inversion_solicitud_origenes o on o.solicitud_id = s.id
           where s.inversion_id = p_inversion)
      then 'Esta inversión nació de una reinversión: tiene historia propia y no se elimina'
    when p_tipo = 'contrato' and p_inversion is not null and exists (select 1 from crm.inversion_eventos e
           where e.inversion_id = p_inversion and e.tipo <> 'registro')
      then 'Esta inversión tiene correcciones o anulaciones registradas: no se elimina'
    -- Cooperativas (Codex r1): solo eventos ADMINISTRATIVOS del mismo registro (alta, corrección, anulación). Cualquier tipo
    -- que se añada en el futuro cuenta como historia propia hasta que se decida lo contrario.
    when p_tipo = 'cierre_externo' and p_inversion is not null and exists (select 1 from crm.inversion_eventos e
           where e.inversion_id = p_inversion and e.tipo not in ('registro', 'correccion', 'anulacion'))
      then 'Esta inversión tiene movimientos registrados: tiene historia propia y no se elimina'
    else null
  end
$$;

-- Fail-closed: si alguien añade una tabla que apunta a inversiones o cierres, el borrado se niega hasta revisar la copia.
create function private.inversion_eliminacion_dependencias_conocidas()
returns boolean language sql stable set search_path = '' as $$
  with fk as (
    select c.confrelid::regclass::text as padre,
           c.conrelid::regclass::text || ':' || a.attname || ':' || c.confdeltype::text as hijo,
           cardinality(c.conkey) as columnas
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.confrelid in ('crm.inversiones'::regclass, 'crm.cierres_externos'::regclass,
        'crm.inversion_titulares'::regclass, 'crm.inversion_eventos'::regclass, 'crm.depositos_reclamados'::regclass)
  )
  select coalesce((select array_agg(f.hijo order by f.hijo) from fk f where f.padre = 'crm.inversiones'), '{}')
           = array['crm.inversion_ajustes_mes_cerrado:inversion_id:a', 'crm.inversion_cotitular_origenes:inversion_id:a',
                   'crm.inversion_eventos:inversion_id:a', 'crm.inversion_solicitudes:inversion_id:a',
                   'crm.inversion_titulares:inversion_id:a']
     and coalesce((select array_agg(f.hijo order by f.hijo) from fk f where f.padre = 'crm.cierres_externos'), '{}')
           = array['crm.depositos_reclamados:cierre_id:r', 'crm.inversion_solicitud_origenes:fuente_id:a',
                   'crm.inversiones:cierre_externo_id:r', 'crm.postventa_retiros:fuente_id:a']
     and not exists (select 1 from fk f where f.padre in ('crm.inversion_titulares', 'crm.inversion_eventos',
                                                         'crm.depositos_reclamados'))
     and not exists (select 1 from fk f where f.columnas <> 1)
$$;

-- ── 6 · Núcleo: eliminar una inversión de cooperativa con su copia ─────────────────────────────────────────────────────
create function private.eliminar_inversion_cooperativa(p_ctx jsonb, p_actor uuid, p_rol text, p_motivo text, p_anulacion jsonb)
returns uuid language plpgsql set search_path = '' as $$
declare
  v_cierre uuid := (p_ctx ->> 'fuente_id')::uuid;
  v_inv uuid := (p_ctx ->> 'inversion_id')::uuid;
  v_es_conversion boolean := coalesce((p_ctx ->> 'es_conversion')::boolean, false);
  v_ce crm.cierres_externos%rowtype;
  v_id uuid;
  v_valvula uuid;
  v_previa text := current_setting('crm.inversion_eliminacion', true);
  v_no text;
begin
  if p_ctx ->> 'tipo' is distinct from 'cierre_externo' then
    raise exception 'Fuente no válida para una inversión de cooperativa' using errcode = '22023';
  end if;
  if not private.inversion_eliminacion_dependencias_conocidas() then
    raise exception 'La inversión tiene dependencias nuevas; requiere revisión antes de eliminarla' using errcode = '55000';
  end if;
  -- Todo lo que se copia queda bloqueado antes de copiarlo: nada cambia entre la copia y el borrado.
  select * into strict v_ce from crm.cierres_externos where id = v_cierre for update;
  perform 1 from crm.inversiones where id = v_inv for update;
  perform 1 from crm.depositos_reclamados where cierre_id = v_cierre order by id for update;
  perform 1 from crm.inversion_eventos where inversion_id = v_inv order by id for update;
  perform 1 from crm.inversion_titulares where inversion_id = v_inv order by id for update;
  perform 1 from crm.inversion_solicitudes where inversion_id = v_inv order by id for update;
  v_no := private.inversion_motivo_no_eliminable('cierre_externo', v_cierre, v_inv);
  if v_no is not null then raise exception '%', v_no using errcode = 'P0409'; end if;
  if v_inv is not null and exists (select 1 from crm.inversiones i where i.id = v_inv and i.cierre_externo_id is distinct from v_cierre) then
    raise exception 'La inversión no corresponde a este cierre; requiere revisión' using errcode = 'P0409';
  end if;
  -- La conversión solo se elimina ya anulada (la puerta de gerencia la anuló en esta misma transacción, o antes).
  if v_es_conversion and v_ce.anulado_en is null then
    raise exception 'La conversión debe anularse antes de eliminarla' using errcode = 'P0409';
  end if;
  perform private.conversion_coordinar_retiro_fuente('cierre_externo', v_cierre);

  -- (auditor-rls r2, P3) Un CHECK fallido traería «Failing row contains (...)» con la copia y la llave: se relanza sin detalle.
  begin
  insert into crm.inversiones_eliminadas (fuente_tipo, fuente_id, inversion_id, empresa, inversionista_id, lead_id,
    es_conversion, conversion_anulada, anulacion, motivo, eliminado_por, rol_actor, snapshot, archivos)
  values ('cierre_externo', v_cierre, v_inv, v_ce.cooperativa,
    coalesce((p_ctx ->> 'inversionista_id')::uuid, v_ce.inversionista_id),
    case when v_es_conversion then v_ce.lead_id end,
    v_es_conversion, v_es_conversion, p_anulacion, p_motivo, p_actor, p_rol,
    jsonb_build_object(
      'version', 1,
      'actor', jsonb_build_object('id', p_actor, 'rol', p_rol),
      'cierre', to_jsonb(v_ce),
      'inversion', (select to_jsonb(i) from crm.inversiones i where i.id = v_inv),
      'depositos', coalesce((select jsonb_agg(to_jsonb(d) order by d.id) from crm.depositos_reclamados d
                             where d.cierre_id = v_cierre), '[]'::jsonb),
      'eventos', coalesce((select jsonb_agg(to_jsonb(e) order by e.id) from crm.inversion_eventos e
                           where e.inversion_id = v_inv), '[]'::jsonb),
      'titulares', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from crm.inversion_titulares t
                             where t.inversion_id = v_inv), '[]'::jsonb),
      'solicitudes', coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from crm.inversion_solicitudes s
                               where s.inversion_id = v_inv), '[]'::jsonb),
      'acreditaciones', coalesce((select jsonb_agg(to_jsonb(a) order by a.id) from crm.conversion_acreditaciones a
                                  where a.fuente_tipo = 'cierre_externo' and a.fuente_id = v_cierre), '[]'::jsonb)),
    case when v_ce.comprobante_objeto_id is null then '[]'::jsonb
      else jsonb_build_array(jsonb_build_object('tipo', 'comprobante', 'objeto_id', v_ce.comprobante_objeto_id)) end)
  returning id, valvula into v_id, v_valvula;
  exception when check_violation or not_null_violation or foreign_key_violation then
    raise exception 'La copia de la inversión no es válida; requiere revisión' using errcode = '55000';
  end;

  perform set_config('crm.inversion_eliminacion', v_valvula::text, true);
  -- Hijos antes que padres. La solicitud de alta se CONSERVA cancelada (igual que en Avance: cierra replays).
  delete from crm.depositos_reclamados where cierre_id = v_cierre;
  delete from crm.inversion_eventos where inversion_id = v_inv;
  update crm.inversion_solicitudes set estado = 'cancelada', inversion_id = null, actualizado_en = statement_timestamp()
    where inversion_id = v_inv;
  delete from crm.inversion_titulares where inversion_id = v_inv;
  delete from crm.inversiones where id = v_inv;
  delete from crm.cierres_externos where id = v_cierre;
  perform set_config('crm.inversion_eliminacion', coalesce(v_previa, ''), true);
  return v_id;
exception when others then
  perform set_config('crm.inversion_eliminacion', coalesce(v_previa, ''), true);
  raise;
end $$;

-- ── 7 · Núcleo: registrar la eliminación de Avance (la copia completa ya está en contratos_eliminados_auditoria) ────────
create function private.registrar_inversion_eliminada_avance(p_ctx jsonb, p_contrato_auditoria uuid, p_actor uuid,
  p_rol text, p_motivo text, p_anulacion jsonb)
returns uuid language plpgsql set search_path = '' as $$
declare
  v_fuente uuid := (p_ctx ->> 'fuente_id')::uuid;
  v_lead uuid := (p_ctx ->> 'lead_id')::uuid;
  v_es_conversion boolean := coalesce((p_ctx ->> 'es_conversion')::boolean, false);
  v_a crm.contratos_eliminados_auditoria%rowtype;
  v_id uuid;
begin
  if p_ctx ->> 'tipo' is distinct from 'contrato' then
    raise exception 'Fuente no válida para una inversión de Avance' using errcode = '22023';
  end if;
  select * into v_a from crm.contratos_eliminados_auditoria a where a.id = p_contrato_auditoria and a.contrato_id = v_fuente;
  if not found or exists (select 1 from public.contratos c where c.id = v_fuente) then
    raise exception 'La eliminación del contrato no se confirmó; requiere revisión' using errcode = '55000';
  end if;
  if v_es_conversion and (v_lead is null or not private.cierre_anulado(v_lead)) then
    raise exception 'La conversión debe anularse antes de eliminarla' using errcode = 'P0409';
  end if;
  begin
  insert into crm.inversiones_eliminadas (fuente_tipo, fuente_id, inversion_id, empresa, inversionista_id, lead_id,
    es_conversion, conversion_anulada, anulacion, motivo, eliminado_por, rol_actor, contrato_auditoria_id, snapshot, archivos)
  values ('contrato', v_fuente, (p_ctx ->> 'inversion_id')::uuid, 'avance', (p_ctx ->> 'inversionista_id')::uuid,
    case when v_es_conversion then v_lead end, v_es_conversion, v_es_conversion, p_anulacion, p_motivo, p_actor, p_rol,
    v_a.id,
    jsonb_build_object(
      'version', 1,
      'actor', jsonb_build_object('id', p_actor, 'rol', p_rol),
      'contrato_auditoria_id', v_a.id,
      'contrato', jsonb_build_object('id', v_fuente, 'numero_contrato', v_a.snapshot #>> '{contrato,numero_contrato}'),
      'inversion', v_a.snapshot -> 'inversion'),
    v_a.archivos)
  returning id into v_id;
  exception when check_violation or not_null_violation or foreign_key_violation then
    raise exception 'La copia de la inversión no es válida; requiere revisión' using errcode = '55000';
  end;
  return v_id;
end $$;

-- ── 8 · Puerta ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create function crm.eliminar_inversion_fn(p_fuente_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_portal text;
  v_gerencia boolean;
  v_rol text;
  v_motivo text := btrim(p_motivo);
  v_ctx jsonb;
  v_no text;
  v_anulacion jsonb;
  v_res jsonb;
  v_aud uuid;
  v_priv_previa text;
begin
  if v_uid is null then
    raise exception 'Inicia sesión para eliminar inversiones' using errcode = '42501';
  end if;
  v_roles := private.eliminar_inversion_roles(v_uid);
  v_portal := v_roles ->> 'portal';
  v_gerencia := coalesce((v_roles ->> 'gerencia')::boolean, false);
  v_rol := case when v_gerencia then 'gerencia' else v_portal end;
  if v_rol is null then
    raise exception 'Solo admin o gerencia pueden eliminar inversiones' using errcode = '42501';
  end if;
  if v_motivo is null or length(v_motivo) < 5 then
    raise exception 'Escribe el motivo de la eliminación (al menos 5 caracteres)' using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como máximo 300 caracteres' using errcode = '22023';
  end if;

  v_ctx := private.eliminar_inversion_contexto(p_fuente_id);
  if v_ctx is null then
    raise exception 'La inversión no existe o ya fue eliminada' using errcode = 'P0002';
  end if;
  -- Avance: crm.contrato_eliminar_auditado exige admin/superadmin del portal (y no se toca: está declarada).
  if v_ctx ->> 'tipo' = 'contrato' and v_portal is null then
    raise exception 'Una inversión de Avance la elimina un admin del portal' using errcode = '42501';
  end if;
  v_no := private.inversion_motivo_no_eliminable(v_ctx ->> 'tipo', p_fuente_id, (v_ctx ->> 'inversion_id')::uuid);
  if v_no is not null then
    raise exception '%', v_no using errcode = 'P0409';
  end if;

  -- D2: la conversión se anula por la puerta de gerencia de siempre (con su ajuste si el mes está cerrado).
  if (v_ctx ->> 'es_conversion')::boolean and not (v_ctx ->> 'conversion_anulada')::boolean then
    if not v_gerencia then
      raise exception 'Esta inversión es la conversión de un lead: solo gerencia puede anularla y eliminarla'
        using errcode = '42501';
    end if;
    if v_ctx ->> 'lead_id' is null then
      raise exception 'No se encuentra el lead de esta conversión; requiere revisión' using errcode = 'P0409';
    end if;
    if v_ctx ->> 'tipo' = 'cierre_externo' then
      v_anulacion := crm.anular_cierre_externo(p_fuente_id, v_motivo);
    else
      v_anulacion := crm.anular_cierre_avance((v_ctx ->> 'lead_id')::uuid, v_motivo);
    end if;
  end if;
  -- (auditor-rls r2, P3) La copia registra el rol que HABILITÓ la operación: gerencia si hizo falta anular; si no, el del portal.
  v_rol := case when v_anulacion is not null then 'gerencia' else coalesce(v_portal, 'gerencia') end;

  if v_ctx ->> 'tipo' = 'contrato' then
    -- El lead que apunta al contrato pierde el enlace por su FK (ON DELETE SET NULL). private.leads_before_update solo
    -- deja mover leads.contrato_id con la válvula privilegiada; sin ella revierte el SET NULL y la FK rechaza el borrado
    -- (así falla hoy «Eliminar contrato» con un contrato que es conversión). Se enciende SOLO durante esta llamada,
    -- como hacen las anulaciones de gerencia.
    -- (auditor-rls r2, P3) solo si algún lead apunta al contrato (ya bloqueados por el contexto).
    if coalesce((v_ctx ->> 'leads_enlazados')::boolean, false) then
      v_priv_previa := current_setting('crm.op_privilegiada', true);
      perform set_config('crm.op_privilegiada', 'on', true);
    end if;
    v_res := crm.contrato_eliminar_auditado(p_fuente_id, v_uid);
    if coalesce((v_ctx ->> 'leads_enlazados')::boolean, false) then
      perform set_config('crm.op_privilegiada', coalesce(nullif(v_priv_previa, ''), 'off'), true);
    end if;
    v_aud := private.registrar_inversion_eliminada_avance(v_ctx, (v_res ->> 'auditoria_id')::uuid, v_uid, v_rol,
      v_motivo, v_anulacion);
  else
    v_aud := private.eliminar_inversion_cooperativa(v_ctx, v_uid, v_rol, v_motivo, v_anulacion);
  end if;

  return jsonb_build_object(
    'ok', true,
    'fuente_id', p_fuente_id,
    'empresa', v_ctx ->> 'empresa',
    'auditoria_id', v_aud,
    'conversion_anulada', v_anulacion is not null,
    'mes_cerrado', coalesce((v_anulacion ->> 'mes_cerrado')::boolean, false));
end $$;

-- ── 9 · Permisos ───────────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on table crm.inversiones_eliminadas from public, anon, authenticated, service_role;
revoke all on function private.proteger_inversion_eliminada() from public, anon, authenticated, service_role;
revoke all on function private.inversion_eliminacion_autoriza(text, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.conversion_coordinar_retiro_fuente(text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.eliminar_inversion_roles(uuid) from public, anon, authenticated, service_role;
revoke all on function private.eliminar_inversion_contexto(uuid) from public, anon, authenticated, service_role;
revoke all on function private.inversion_motivo_no_eliminable(text, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.inversion_eliminacion_dependencias_conocidas() from public, anon, authenticated, service_role;
revoke all on function private.eliminar_inversion_cooperativa(jsonb, uuid, text, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.registrar_inversion_eliminada_avance(jsonb, uuid, uuid, text, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.eliminar_inversion_fn(uuid, text) from public, anon, service_role;
grant execute on function crm.eliminar_inversion_fn(uuid, text) to authenticated;

-- ── 10 · Comentarios ───────────────────────────────────────────────────────────────────────────────────────────────────
comment on table crm.inversiones_eliminadas is
  'Copia privada e inmutable de cada inversión eliminada por admin o gerencia (crm.eliminar_inversion_fn, 05/10/2026). '
  'Una fila por fuente (contrato de Avance o cierre externo de cooperativa). Sin políticas ni grants: solo la leen funciones '
  'del servidor. Contiene datos personales (documento y nombre del cliente en la copia). Los archivos referenciados se '
  'conservan en Storage como evidencia.';
comment on column crm.inversiones_eliminadas.id is 'Identificador de la copia (acuse que recibe la pantalla).';
comment on column crm.inversiones_eliminadas.fuente_tipo is 'contrato (Avance) o cierre_externo (Prodelco, Qorilazo).';
comment on column crm.inversiones_eliminadas.fuente_id is 'Id del contrato o del cierre eliminado (sin FK: ya no existe).';
comment on column crm.inversiones_eliminadas.inversion_id is 'Id de crm.inversiones si la fuente tenía inversión (sin FK: ya no existe).';
comment on column crm.inversiones_eliminadas.empresa is 'Empresa de la inversión: avance, prodelco o qorilazo.';
comment on column crm.inversiones_eliminadas.inversionista_id is 'Persona de la cartera a la que pertenecía la inversión, si se conocía.';
comment on column crm.inversiones_eliminadas.lead_id is 'Lead cuya conversión era esta inversión (solo si es_conversion).';
comment on column crm.inversiones_eliminadas.es_conversion is 'La inversión era la conversión (cierre inicial) de un lead.';
comment on column crm.inversiones_eliminadas.conversion_anulada is
  'La conversión quedó anulada. private.cierre_anulado lo consulta: la anulación sobrevive a la eliminación del cierre.';
comment on column crm.inversiones_eliminadas.anulacion is 'Respuesta de la puerta de anulación si esta operación anuló la conversión; NULL si no hizo falta.';
comment on column crm.inversiones_eliminadas.motivo is 'Motivo escrito por quien elimina (5 a 300 caracteres).';
comment on column crm.inversiones_eliminadas.eliminado_por is 'Perfil que eliminó (auth.uid() resuelto en el servidor).';
comment on column crm.inversiones_eliminadas.rol_actor is 'Rol con el que eliminó: gerencia (CRM), admin o superadmin (portal).';
comment on column crm.inversiones_eliminadas.eliminado_en is 'Momento de la eliminación.';
comment on column crm.inversiones_eliminadas.contrato_auditoria_id is 'Avance: copia completa en crm.contratos_eliminados_auditoria.';
comment on column crm.inversiones_eliminadas.snapshot is
  'Copia de lo eliminado. Cooperativas: cierre, inversión, depósitos, eventos, titulares, solicitudes y acreditaciones. '
  'Avance: referencia a la copia del contrato y la inversión. Dato personal: no sale de la base.';
comment on column crm.inversiones_eliminadas.archivos is 'Objetos de Storage que se conservan como evidencia (comprobante, PDF).';
comment on column crm.inversiones_eliminadas.valvula is
  'Llave de un solo uso con la que los candados dejaron borrar las filas de ESTA copia; tras el commit no abre nada '
  '(exige además la misma transacción y filas idénticas a la copia).';
comment on column crm.inversiones_eliminadas.transaccion is 'Transacción que creó la copia; la válvula solo vale dentro de ella.';
comment on function private.proteger_inversion_eliminada() is 'Candado: la copia de una inversión eliminada no se edita, borra ni vacía.';
comment on function private.inversion_eliminacion_autoriza(text, uuid, jsonb) is
  'Válvula ÚNICA de los candados de cierres externos, depósitos reclamados y eventos de inversión para la eliminación '
  'auditada: llave de su copia, misma transacción, mismo actor y fila idéntica a la copiada.';
comment on function private.conversion_coordinar_retiro_fuente(text, uuid) is
  'Retirar una fuente de conversión (contrato o cierre): bloquea sus leads (NOWAIT) y los meses de sus acreditaciones '
  'frente al sellado. Una sola definición para contratos (trigger) y cierres (eliminación de inversiones).';
comment on function private.eliminar_inversion_roles(uuid) is 'Rol efectivo para eliminar inversiones: portal admin/superadmin y si es gerencia del CRM. Bloquea el perfil.';
comment on function private.eliminar_inversion_contexto(uuid) is
  'Bloquea la fuente (cierre o contrato), su inversión y su lead de conversión, y devuelve el camino de la eliminación.';
comment on function private.inversion_motivo_no_eliminable(text, uuid, uuid) is
  'NULL si la inversión se puede eliminar; si tiene historia propia (D3), el mensaje para la pantalla.';
comment on function private.inversion_eliminacion_dependencias_conocidas() is
  'Fail-closed: las tablas que apuntan a inversiones y cierres son exactamente las que la copia conoce.';
comment on function private.eliminar_inversion_cooperativa(jsonb, uuid, text, text, jsonb) is
  'Núcleo: copia y elimina en la misma transacción una inversión de cooperativa (cierre, inversión, depósitos, eventos, '
  'titulares); la solicitud de alta se conserva cancelada. La conversión debe llegar ya anulada.';
comment on function private.registrar_inversion_eliminada_avance(jsonb, uuid, uuid, text, text, jsonb) is
  'Núcleo: registra la eliminación de una inversión de Avance ya eliminada por crm.contrato_eliminar_auditado.';
comment on function crm.eliminar_inversion_fn(uuid, text) is
  'Elimina una inversión (contrato de Avance o cierre de cooperativa) con copia inmutable y motivo. Admin/superadmin del '
  'portal o gerencia (Avance: admin del portal). Si es una conversión no anulada, solo gerencia: la anula y la elimina. '
  'Con historia propia no se elimina (P0409). DEFINER: las tablas no tienen grants; el actor sale de auth.uid().';
comment on function private.cierre_anulado(uuid) is
  'El cierre (conversión) del lead está anulado: cierre externo inicial anulado, anulación de Avance, o conversión anulada '
  'y eliminada (crm.inversiones_eliminadas).';
comment on function private.conversion_bloquear_retiro_trg() is
  'Al archivar un contrato eliminado: coordina el retiro de la fuente con el sellado (private.conversion_coordinar_retiro_fuente).';

-- ── 11 · Postflight (solo catálogo) ────────────────────────────────────────────────────────────────────────────────────
do $postflight$
begin
  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'crm.inversiones_eliminadas'::regclass) then
    raise exception 'POSTFLIGHT: crm.inversiones_eliminadas sin RLS';
  end if;
  if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = 'crm.inversiones_eliminadas'::regclass) then
    raise exception 'POSTFLIGHT: crm.inversiones_eliminadas no debe tener políticas';
  end if;
  if has_table_privilege('authenticated', 'crm.inversiones_eliminadas', 'select')
     or has_table_privilege('anon', 'crm.inversiones_eliminadas', 'select')
     or has_table_privilege('service_role', 'crm.inversiones_eliminadas', 'select') then
    raise exception 'POSTFLIGHT: la copia es legible por un rol de la API';
  end if;
  if not has_function_privilege('authenticated', 'crm.eliminar_inversion_fn(uuid,text)', 'execute')
     or has_function_privilege('anon', 'crm.eliminar_inversion_fn(uuid,text)', 'execute') then
    raise exception 'POSTFLIGHT: permisos de la puerta incorrectos';
  end if;
  if has_function_privilege('authenticated', 'private.eliminar_inversion_cooperativa(jsonb,uuid,text,text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'private.inversion_eliminacion_autoriza(text,uuid,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'private.registrar_inversion_eliminada_avance(jsonb,uuid,uuid,text,text,jsonb)', 'execute') then
    raise exception 'POSTFLIGHT: un núcleo quedó ejecutable por authenticated';
  end if;
  -- (auditor-rls r2, P3) El modelo de permisos depende de que todo sea de postgres.
  if (select c.relowner from pg_catalog.pg_class c where c.oid = 'crm.inversiones_eliminadas'::regclass) <> 'postgres'::regrole
     or exists (select 1 from pg_catalog.pg_proc p
                where p.oid in ('crm.eliminar_inversion_fn(uuid,text)'::regprocedure, 'private.proteger_inversion_eliminada()'::regprocedure,
                  'private.inversion_eliminacion_autoriza(text,uuid,jsonb)'::regprocedure, 'private.conversion_coordinar_retiro_fuente(text,uuid)'::regprocedure,
                  'private.eliminar_inversion_roles(uuid)'::regprocedure, 'private.eliminar_inversion_contexto(uuid)'::regprocedure,
                  'private.inversion_motivo_no_eliminable(text,uuid,uuid)'::regprocedure, 'private.inversion_eliminacion_dependencias_conocidas()'::regprocedure,
                  'private.eliminar_inversion_cooperativa(jsonb,uuid,text,text,jsonb)'::regprocedure,
                  'private.registrar_inversion_eliminada_avance(jsonb,uuid,uuid,text,text,jsonb)'::regprocedure,
                  'private.leads_before_update()'::regprocedure, 'private.cierre_anulado(uuid)'::regprocedure)
                  and p.proowner <> 'postgres'::regrole) then
    raise exception 'POSTFLIGHT: la copia o alguna función no es de postgres';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t where t.tgrelid = 'crm.inversiones_eliminadas'::regclass and not t.tgisinternal) <> 3 then
    raise exception 'POSTFLIGHT: faltan los candados o la auditoría de la copia';
  end if;
  if not private.inversion_eliminacion_dependencias_conocidas() then
    raise exception 'POSTFLIGHT: el censo de dependencias no coincide con el esquema';
  end if;
  -- Ninguna función nueva entra al censo analítico (no combina crm.leads/reunion con count/sum(1)).
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto in ('crm.eliminar_inversion_fn(uuid,text)', 'private.eliminar_inversion_contexto(uuid)',
                                'private.conversion_coordinar_retiro_fuente(text,uuid)',
                                'private.eliminar_inversion_cooperativa(jsonb,uuid,text,text,jsonb)')) then
    raise exception 'POSTFLIGHT: una función nueva entró al censo analítico';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgenabled = 'O' and (
        (t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_externos_00_inmutables')
        or (t.tgrelid = 'crm.depositos_reclamados'::regclass and t.tgname = 'trg_depositos_reclamados_00_append_only')
        or (t.tgrelid = 'crm.inversion_eventos'::regclass and t.tgname = 'trg_inversion_eventos_inmutables'))) <> 3 then
    raise exception 'POSTFLIGHT: los candados no siguen en su modo normal';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));

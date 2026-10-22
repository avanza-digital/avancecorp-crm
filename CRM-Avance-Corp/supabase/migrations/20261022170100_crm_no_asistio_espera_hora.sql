-- 20261022170100_crm_no_asistio_espera_hora.sql — bloque 2.1 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261006152203_crm_no_asistio_espera_hora.sql; integrado el 2026/10/22, C2 del grupo C)
-- «NO ASISTIÓ» ESPERA A LA HORA DE LA CITA — una inasistencia no se registra
-- antes de la hora pactada.
--
-- Regla de Miguel (2026-10-05): «una reunión realizada antes de la hora pactada
-- puede marcarse realizada inmediatamente y debe ser evaluable. Solo "No
-- asistió" debe esperar a que haya pasado la hora pactada». La hora pactada es
-- `crm.tareas.vence_en`.
--
-- QUÉ PASABA. Ninguna entrada comparaba contra `vence_en`: una cita de las
-- cinco de la tarde podía quedar como «No asistió» a las diez de la mañana, y
-- Gerencia veía inasistencias que todavía no habían podido ocurrir. Medido en
-- el laboratorio el 06/10 (banco comercial, casos R2 y R4a, y el ensayo de
-- `supabase/scripts/no-asistio-espera-hora/`): lo aceptaban las SEIS entradas
-- —`crm.cerrar_reunion_v3`, `crm.cerrar_reunion_v2`, `crm.cerrar_reunion`,
-- `crm.cerrar_tarea_v2`, `crm.cerrar_tarea` y `crm.postventa_tarea_fn`— al
-- vendedor dueño, y la puerta de la pantalla también al supervisor de su
-- equipo y a gerencia.
--
-- QUÉ HACE. `private.trg_tareas_before_update()` —el candado BEFORE UPDATE de
-- `crm.tareas`— rechaza pasar una REUNIÓN a `no_show` mientras su hora pactada
-- sea posterior al reloj. Errcode `22023` y un mensaje en idioma de negocio y
-- sin datos personales, escrito para mostrarse tal cual: el front enseña el
-- texto de los RAISE 22023 de las puertas de agenda sin traducirlo.
--
-- POR QUÉ EN EL CANDADO DE LA TABLA Y NO EN LOS WRITERS. Los cuerpos de
-- `crm.cerrar_reunion` y `crm.cerrar_tarea` están SELLADOS por md5 en
-- `private.assert_sla_comandos` y en `private.assert_entrevista_al_asistir`
-- porque de ellos depende el orden de bloqueos lead→tarea; tocarlos obligaría
-- a re-sellar y a re-auditar ese orden. Y una guarda puesta solo en la puerta
-- nueva se salta por las viejas, que siguen concedidas a `authenticated`. El
-- candado, en cambio, corre en TODO UPDATE de `crm.tareas` (BEFORE UPDATE por
-- fila, sin WHEN y sin lista de columnas), que hoy es por donde entran las
-- seis entradas; y una regla que no debe romperse vive en la base.
--
-- LA FRONTERA. Se rechaza mientras `vence_en > reloj`; se acepta desde el
-- instante de la hora (`vence_en <= reloj`). Es el mismo criterio con el que
-- el núcleo de citas decide que una reunión «debió ocurrir»
-- (`private.citas_episodios`), para que escritura y métricas no discrepen en
-- el borde. El reloj es `clock_timestamp()` y no `now()`: la hora llega en
-- tiempo real aunque la transacción haya esperado un candado.
--
-- QUÉ NO CAMBIA. «Se realizó» antes de la hora se acepta en el acto; cancelar
-- y reprogramar antes de la hora siguen como hoy; las tareas que no son
-- reunión no se tocan; recibos idempotentes, candados y retroceso por
-- anulación, intactos. No se corrige nada hacia atrás: las citas que ya estén
-- en «No asistió» desde antes de su hora se quedan como están. No se toca
-- ningún writer, ni `crm.postventa_tarea_fn`, ni los `assert_*`, ni tablas,
-- grants o policies, ni nada de `public`. La función conserva firma, dueño,
-- `security definer`, `search_path` y ACL; el resto de su cuerpo es, byte a
-- byte, el vigente.
--
-- LÍMITES CONOCIDOS (lo que este cambio NO garantiza).
--   1. La regla compara contra la hora GUARDADA de la cita; no impide que esa
--      hora nazca o se mueva al pasado. Medido en el laboratorio el 06/10: el
--      dueño reprograma una cita futura a «hace un minuto» por
--      `crm.reprogramar_reunion_v2` y marca «No asistió» en la cita nueva; y
--      una reunión de lead creada con la hora ya pasada también se deja
--      marcar. Era así antes de esta migración y sigue igual con ella.
--      (Postventa sí exige hora futura al agendar y al reprogramar.) Queda
--      fuera de este cambio: Miguel decidió el 06/10/2026 dejarlo como está
--      (D-05); deja rastro —la cita original figura como reprogramada— y lo
--      vigila Gerencia.
--   2. La regla vive en BEFORE UPDATE: un INSERT con `crm.op_tarea = on` no
--      pasa por ella. Hoy ninguna función inserta una tarea en `no_show`
--      (censo por catálogo del 06/10: insertan en `crm.tareas` solo
--      `private.crear_siguiente_tarea`, `private.registrar_solicitud_cliente_fn`,
--      `crm.reprogramar_reunion` y `private.postventa_insertar_tarea`, y
--      ninguna menciona `no_show`). Una entrada futura que escriba `no_show`
--      con un UPDATE pasará por la regla; una que lo inserte, no.
--
-- PRECONDICIONES (fail-closed). La migración solo se instala sobre lo que se
-- auditó: el cuerpo anterior, por su huella; la ficha del candado —dueño
-- `postgres`, `security definer`, `search_path` vacío como única configuración
-- y ningún rol con EXECUTE salvo el dueño—; el trigger colgado como BEFORE
-- UPDATE por fila, habilitado en modo normal (`tgenabled = 'O'`), sin WHEN y
-- sin lista de columnas; y `crm.tareas.vence_en` NOT NULL. Se exige IDENTIDAD
-- con lo auditado: una configuración distinta, aunque fuera más estricta,
-- aborta para que alguien la mire antes. El postflight vuelve a exigirlo y
-- además compara la ficha con la de antes.
--
-- A QUÉ PLAN RESPONDE. Plan de mantenibilidad del backend del CRM, fase 2,
-- bloque 2.1 (decisión D-04 de Miguel, 2026-10-06). Causa C-REU-1 de la fase 1.
--
-- VERIFICACIÓN. `supabase/scripts/no-asistio-espera-hora/`: el oráculo sale
-- ROJO sin esta migración y VERDE con ella, sus mutantes mueren por su fallo,
-- las derivas previas de catálogo la hacen abortar en el preflight y la
-- reversa devuelve la huella original. Verificada solo en el laboratorio local.
--
-- REVERSIÓN: `supabase/scripts/no-asistio-espera-hora/reversa.sql` restaura el
-- cuerpo anterior (su `md5(prosrc)` vuelve a `ded27e36f21f4cf34263ce10c8731f5d`)
-- y quita el comentario. Solo comprueba la huella del cuerpo; su cabecera dice
-- qué sobrescribiría si alguien cambiara atributos o el comentario después de
-- esta migración. Nada de lo que esta regla deja pasar necesita deshacerse:
-- solo rechaza, no escribe.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $preflight$
begin
  if to_regprocedure('private.trg_tareas_before_update()') is null then
    raise exception 'Instalar primero la agenda de tareas y la inteligencia comercial de reuniones';
  end if;
  -- Fail-closed: solo se reemplaza el cuerpo que se auditó. Si la huella no
  -- coincide, alguien cambió el candado (o esta regla ya está instalada) y
  -- reemplazarlo a ciegas borraría ese cambio.
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'private.trg_tareas_before_update()'::regprocedure)
     is distinct from 'ded27e36f21f4cf34263ce10c8731f5d' then
    raise exception 'El candado de crm.tareas cambió desde que se auditó: revisar antes de añadir la regla de «No asistió»';
  end if;
  -- La FICHA del candado tiene que ser la auditada ANTES de reemplazarlo.
  -- `create or replace` conserva dueño y ACL: una deriva previa (otro dueño, un
  -- EXECUTE concedido) sobreviviría al cambio, y la comparación del postflight
  -- —antes = después— la daría por buena. Mismo criterio que el caso 9a del
  -- oráculo.
  if not exists (
    select 1 from pg_proc p
    where p.oid = 'private.trg_tareas_before_update()'::regprocedure
      and p.proowner = 'postgres'::regrole::oid
      and p.prosecdef
      and p.proconfig = array['search_path=""']
  ) then
    raise exception 'El candado de crm.tareas no tiene la ficha auditada (dueño postgres, security definer y search_path vacío como única configuración): revisar antes de añadir la regla';
  end if;
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'private.trg_tareas_before_update()'::regprocedure
      and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'Algún rol distinto del dueño tiene EXECUTE sobre el candado de crm.tareas: revisar antes de añadir la regla';
  end if;
  -- La regla compara `old.vence_en > reloj`: con una hora NULL esa comparación
  -- no se cumple y «No asistió» pasaría. La columna tiene que ser NOT NULL.
  if not exists (
    select 1 from pg_attribute a
    where a.attrelid = 'crm.tareas'::regclass
      and a.attname = 'vence_en'
      and not a.attisdropped
      and a.attnotnull
  ) then
    raise exception 'crm.tareas.vence_en no es NOT NULL: una cita sin hora esquivaría la regla de «No asistió»';
  end if;
  -- La regla solo sirve si el candado sigue colgado de la tabla y con la
  -- forma que se auditó: BEFORE UPDATE por fila (`tgtype` 19), habilitado, sin
  -- cláusula WHEN y sin lista de columnas. Con cualquiera de esas dos habría
  -- UPDATE que no pasarían por la regla.
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'crm.tareas'::regclass
      and t.tgname = 'trg_tareas_00_before_update'
      and t.tgfoid = 'private.trg_tareas_before_update()'::regprocedure
      and t.tgenabled = 'O'
      and t.tgtype = 19
      and t.tgqual is null
      and cardinality(t.tgattr::int2[]) = 0
  ) then
    raise exception 'El candado ya no cuelga de crm.tareas como se auditó (BEFORE UPDATE por fila, sin WHEN ni lista de columnas): la regla no protegería todo UPDATE';
  end if;
  -- Foto de dueño, atributos y ACL para compararla en el postflight.
  perform set_config('crm.no_asistio_ficha_previa', (
    select row(p.proowner, p.prosecdef, p.provolatile, p.proleakproof, p.proisstrict,
               p.proparallel, p.proconfig, p.proacl, p.prorettype, p.prolang)::text
    from pg_proc p
    where p.oid = 'private.trg_tareas_before_update()'::regprocedure), true);
end;
$preflight$;

create or replace function private.trg_tareas_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_op      boolean := coalesce(current_setting('crm.op_tarea', true), 'off') = 'on';
  v_sistema boolean := coalesce(current_setting('crm.cancela_sistema', true), 'off') = 'on';
  v_uid     uuid    := (select auth.uid());
  v_asesor  boolean;
  v_cambio_vencimiento boolean;
begin
  v_cambio_vencimiento := new.vence_en is distinct from old.vence_en;

  if old.estado <> 'pendiente' then
    raise exception 'La tarea ya esta cerrada; una reunion reprogramada conserva su historia'
      using errcode = '22023';
  end if;
  if new.estado in ('completada','no_show','reprogramada') and not v_op then
    raise exception 'Cerrar o reprogramar una reunion va por la RPC de agenda'
      using errcode = '22023';
  end if;
  if new.estado = 'cancelada' and not v_op and not v_sistema and v_uid is not null then
    raise exception 'Anular una tarea va por crm.cerrar_tarea()'
      using errcode = '22023';
  end if;
  if new.resultado_actividad_id is distinct from old.resultado_actividad_id and not v_op then
    raise exception 'El resultado lo escribe la RPC de cierre'
      using errcode = '22023';
  end if;
  if (
    new.resultado_reunion is distinct from old.resultado_reunion
    or new.motivo_no_realizada is distinct from old.motivo_no_realizada
    or new.detalle_cierre_reunion is distinct from old.detalle_cierre_reunion
  ) and not v_op then
    raise exception 'El resultado de la reunion lo escribe la RPC de cierre'
      using errcode = '22023';
  end if;
  if old.tipo = 'reunion' and v_cambio_vencimiento and not v_op then
    raise exception 'Reprogramar una reunion va por crm.reprogramar_reunion()'
      using errcode = '22023';
  end if;

  -- «No asistió» espera a la hora pactada: una inasistencia no puede existir
  -- antes de que la cita debiera ocurrir. Va en este candado porque por aquí
  -- pasan todas las entradas que cierran una reunión. Reloj real, no el de la
  -- transacción: la hora llega aunque el UPDATE haya esperado un candado.
  if old.tipo = 'reunion' and new.estado = 'no_show'
     and old.vence_en > clock_timestamp() then
    raise exception 'Aún no llega la hora de la cita: «No asistió» se registra cuando pase la hora pactada'
      using errcode = '22023';
  end if;

  if new.estado = 'cancelada' then
    v_asesor := (not v_sistema) and v_op and v_uid is not null;
    new.cancelada_por    := case when v_asesor then 'asesor' else 'sistema' end;
    new.cancelada_por_id := case when v_asesor then v_uid else null end;
  else
    new.cancelada_por    := old.cancelada_por;
    new.cancelada_por_id := old.cancelada_por_id;
  end if;

  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.lead_id := old.lead_id;
  new.perfil_id := old.perfil_id;
  new.reagendada_de := old.reagendada_de;
  new.tipo := old.tipo;
  new.modalidad_reunion := old.modalidad_reunion;
  new.ubicacion_reunion := old.ubicacion_reunion;
  new.enlace_reunion := old.enlace_reunion;

  if v_cambio_vencimiento then
    new.reprogramaciones := old.reprogramaciones + 1;
  else
    new.reprogramaciones := old.reprogramaciones;
  end if;
  return new;
end;
$$;

comment on function private.trg_tareas_before_update() is
  'Candado BEFORE UPDATE de crm.tareas: una tarea cerrada no se reabre; cerrar, anular y reprogramar solo entran por las RPC de agenda; sella quién cancela y restaura las columnas inmutables. Además rechaza (22023) pasar una reunión a no_show —«No asistió»— mientras su hora pactada (vence_en) sea posterior al reloj.';

do $postflight$
begin
  -- La regla quedó, y el cuerpo instalado es exactamente el que se ensayó.
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'private.trg_tareas_before_update()'::regprocedure)
     is distinct from '4a0a6b0048cdb6d8f2ac1d3b7ecc2852' then
    raise exception 'El candado instalado no es el ensayado: la regla de «No asistió» no quedó como se auditó';
  end if;
  -- `create or replace` conserva dueño y ACL; `security definer` y el
  -- `search_path` vacío se repiten arriba. Si algo de eso se movió, se cae.
  if (select row(p.proowner, p.prosecdef, p.provolatile, p.proleakproof, p.proisstrict,
                 p.proparallel, p.proconfig, p.proacl, p.prorettype, p.prolang)::text
      from pg_proc p
      where p.oid = 'private.trg_tareas_before_update()'::regprocedure)
     is distinct from current_setting('crm.no_asistio_ficha_previa', true) then
    raise exception 'El candado de crm.tareas cambió de dueño, de atributos o de ACL al añadir la regla';
  end if;
  -- Y no solo «igual que antes»: la ficha y la columna se vuelven a exigir en
  -- absoluto, con el mismo criterio que el preflight.
  if not exists (
    select 1 from pg_proc p
    where p.oid = 'private.trg_tareas_before_update()'::regprocedure
      and p.proowner = 'postgres'::regrole::oid
      and p.prosecdef
      and p.proconfig = array['search_path=""']
  ) then
    raise exception 'El candado de crm.tareas quedó sin la ficha auditada (dueño postgres, security definer y search_path vacío como única configuración) tras añadir la regla';
  end if;
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'private.trg_tareas_before_update()'::regprocedure
      and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'Algún rol distinto del dueño quedó con EXECUTE sobre el candado de crm.tareas tras añadir la regla';
  end if;
  if not exists (
    select 1 from pg_attribute a
    where a.attrelid = 'crm.tareas'::regclass
      and a.attname = 'vence_en'
      and not a.attisdropped
      and a.attnotnull
  ) then
    raise exception 'crm.tareas.vence_en dejó de ser NOT NULL mientras se añadía la regla';
  end if;
  -- Y sigue colgado con la misma forma que exigió el preflight.
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'crm.tareas'::regclass
      and t.tgname = 'trg_tareas_00_before_update'
      and t.tgfoid = 'private.trg_tareas_before_update()'::regprocedure
      and t.tgenabled = 'O'
      and t.tgtype = 19
      and t.tgqual is null
      and cardinality(t.tgattr::int2[]) = 0
  ) then
    raise exception 'El candado dejó de colgar de crm.tareas como BEFORE UPDATE por fila, sin WHEN ni lista de columnas';
  end if;
  -- Los writers de agenda NO se tocaron: sus sellos md5 tienen que seguir
  -- pasando, igual que la puerta de la entrevista que compone sobre ellos.
  perform private.assert_sla_comandos();
  perform private.assert_entrevista_al_asistir();
end;
$postflight$;

commit;

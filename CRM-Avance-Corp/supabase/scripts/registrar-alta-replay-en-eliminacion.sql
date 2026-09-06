-- REGISTRO en supabase_migrations.schema_migrations de «el replay del alta no devuelve un contrato en eliminación».
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración.
-- Idempotente; se niega si la migración no está aplicada o si la versión ya está registrada con OTRO contenido.
-- Mismo candado que migración y reversa (y que la familia 20260905190000): un registro y una reversa concurrentes se serializan.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_alta_contrato_idempotente'));
do $chk$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2') is distinct from '9833ed526e733dc8af6ca78e5c85c7ca' then
    raise exception 'REGISTRO REPLAY EN ELIMINACION: la migración 20260905234500 NO está aplicada (la puerta no lleva el texto nuevo); aplica primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version='20260905234500' and coalesce(md5(statements[1]), '') <> '5187b573c1f8de9083996f29b6452081') then
    raise exception 'REGISTRO REPLAY EN ELIMINACION: la versión 20260905234500 ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260905234500', 'crm_alta_idempotente_replay_no_en_eliminacion', array[$m$-- ============================================================================
-- CRM · EL REPLAY DEL ALTA NO DEVUELVE UN CONTRATO EN ELIMINACIÓN (crm.crear_contrato_con_cuenta_pdf_v2, m3)
-- ============================================================================
--
-- QUÉ. Enmienda la v2.1 de «el alta es idempotente por clave» (20260905190000, aplicada en prod el
-- 05/09/2026). Hallazgo m3 del auditor-rls: la rama de replay bloqueaba la fila del contrato y
-- comprobaba lectura, pero no preguntaba private.contrato_en_eliminacion, así que un contrato con
-- eliminación PREPARADA (Gerencia pulsó «Eliminar»; la edge aún no finalizó, o quedó a medias) se
-- devolvía como «alta recuperada» con idempotente:true. El alta nueva SÍ lo pregunta
-- (private.crear_job_contrato_pdf_base → 55000). Ventana rara (preparar y finalizar corren en la
-- misma llamada de la edge), pero real si la edge muere entre medias: la remediación del 05/09 tuvo
-- que comprobar a mano «preparación pendiente» por lo mismo.
--
-- QUÉ HACE. En la rama de replay, tras bloquear la fila (con lo que la respuesta es estable en la
-- transacción) y antes de devolver el contrato: si private.contrato_en_eliminacion(v_contrato_id)
-- → 55000 'El contrato está en proceso de eliminación', el mismo mensaje y código del alta. Nada
-- más cambia: sin clave byte a byte, replay normal, lápida P0409, huella distinta P0409, todo igual.
--
-- QUÉ NO TOCA. Firma, retorno, dueño, DEFINER, search_path, ACL {postgres=X/postgres,authenticated=X/postgres}; sin DROP; nada de public;
-- ni la tabla de memoria ni crear_contrato_con_cuenta ni public.crear_contrato.
--
-- IDENTIDAD DE LA PUERTA (m2 del auditor-rls): guardas y postflight fijan md5(pg_get_functiondef(oid))
-- —cabecera incluida—, dueño/DEFINER/search_path por IGUALDAD y la ACL EXACTA. Vivo (v2.1) 3d7680ae01b461f33deaa87b7cd0056b
-- → nuevo 9833ed526e733dc8af6ca78e5c85c7ca. Mismo advisory lock que 20260905190000: misma función.
--
-- ORDEN DE REVERSA: esta se revierte ANTES que 20260905190000 (su reversa exige el texto de v2.1).
--
-- Generada por scripts/idempotencia-m3/gen-alta-replay-no-en-eliminacion.py desde
-- scripts/idempotencia-m3/vivas/crm.crear_contrato_con_cuenta_pdf_v2.functiondef.sql. Reversa: scripts/rollback-alta-replay-en-eliminacion.sql.
-- Registro: scripts/registrar-alta-replay-en-eliminacion.sql. Oráculo: scripts/oraculo-alta-replay-en-eliminacion.sh.
-- ============================================================================
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_advisory_xact_lock(hashtext('crm_alta_contrato_idempotente'));

do $guard$
declare v_h text; v_owner text; v_definer boolean; v_config text[]; v_acl text;
begin
  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text, p.prosecdef, p.proconfig, p.proacl::text
    into v_h, v_owner, v_definer, v_config, v_acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb';
  if v_h is null then
    raise exception 'REPLAY EN ELIMINACION: falta crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)';
  end if;
  if v_h is distinct from '3d7680ae01b461f33deaa87b7cd0056b' and v_h is distinct from '9833ed526e733dc8af6ca78e5c85c7ca' then
    raise exception 'REPLAY EN ELIMINACION: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no es ni el texto vivo de producción (v2.1 de idempotencia) ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or v_config <> array['search_path=""'] then
    raise exception 'REPLAY EN ELIMINACION: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'REPLAY EN ELIMINACION: la ACL de crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no es la viva {postgres=X/postgres,authenticated=X/postgres} (%)', v_acl;
  end if;
end
$guard$;

CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_contrato jsonb := p_contrato;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
  v_clave_texto text := nullif(btrim(coalesce(p_contrato->>'clave_idempotencia', '')), '');
  v_clave uuid;
  v_huella text;
  v_huella_previa text;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- IDEMPOTENCIA DEL ALTA (05/09/2026). El front manda una clave (uuid) por intento de
  -- formulario, la MISMA en cada reintento. Si este actor ya registró un alta con esa
  -- clave, se devuelve el MISMO contrato en vez de crear otro. Viaja DENTRO de
  -- p_contrato para no cambiar la firma del RPC; es del transporte, no del contrato:
  -- se quita antes de bajar a la cadena, que recibe EXACTAMENTE lo que recibía.
  -- Sin clave, nada cambia (los clientes que no la mandan siguen igual).
  if v_clave_texto is not null then
    begin
      v_clave := v_clave_texto::uuid;
    exception when invalid_text_representation then
      raise exception 'La clave de idempotencia del alta no es válida'
        using errcode = '22023';
    end;
    -- Dos envíos simultáneos con la misma clave del mismo actor (doble clic, dos
    -- pestañas) se serializan aquí: el segundo espera y lee el alta del primero.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'crm.alta_contrato_idempotente|' || v_actor_id::text || '|' || v_clave::text, 0
      )
    );
    -- La huella de LO QUE SE PIDE (sin la clave): la misma clave solo vale para la
    -- misma solicitud. jsonb::text es canónico (claves ordenadas), así que dos
    -- envíos iguales dan la misma huella.
    v_huella := md5(
      (p_contrato - 'clave_idempotencia')::text || '|'
      || coalesce(p_cronograma::text, '') || '|'
      || coalesce(p_cuenta::text, '')
    );
    select a.respuesta, a.contrato_id, a.huella
      into v_resultado, v_contrato_id, v_huella_previa
    from private.contrato_altas_idempotentes a
    where a.actor_id = v_actor_id and a.clave = v_clave;
    if found then
      -- El replay pasa por la MISMA autorización que el alta (Codex 05/09): una
      -- membresía revocada o un contrato fuera de cartera no recuperan nada.
      if not (select private.puede_registrar_ventas()) then
        raise insufficient_privilege using
          message = 'Cliente no encontrado o fuera de tu cartera';
      end if;
      -- Lápida: el contrato de este intento fue eliminado después (FK SET NULL).
      -- Un reintento tardío NO recrea lo que Gerencia borró a propósito.
      if v_contrato_id is null then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end if;
      -- Misma fila que bloquea la puerta de eliminación: replay y borrado se
      -- serializan. Si el contrato desaparece mientras esperamos, es lápida.
      begin
        perform private.bloquear_fila_contrato_pdf(v_contrato_id);
      exception when sqlstate 'P0002' then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end;
      -- Eliminación PREPARADA y aún no finalizada (Gerencia pulsó «Eliminar» y la edge todavía
      -- no borró): no se devuelve como «alta recuperada» un contrato que está a punto de
      -- desaparecer. La misma pregunta y el mismo 55000 que hace el alta
      -- (private.crear_job_contrato_pdf_base); la fila ya está bloqueada, así que la
      -- respuesta es estable hasta que esta transacción termine.
      if private.contrato_en_eliminacion(v_contrato_id) then
        raise exception 'El contrato está en proceso de eliminación'
          using errcode = '55000';
      end if;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
        raise insufficient_privilege using
          message = 'Contrato no encontrado o fuera de tu cartera';
      end if;
      -- Misma clave pero OTROS datos (el analista editó el formulario tras un
      -- intento que SÍ creó el contrato): no se devuelve el viejo como si fuera
      -- el nuevo ni se crea otro. Se le dice la verdad, con el número.
      if v_huella_previa is distinct from v_huella then
        raise exception 'Este intento ya creó el contrato % con otros datos; no se creó otro. Revísalo antes de registrar uno nuevo',
          coalesce(v_resultado->>'numero_contrato', v_contrato_id::text)
          using errcode = 'P0409',
                hint = 'ALTA_YA_CREADA_CON_OTROS_DATOS',
                detail = jsonb_build_object(
                  'contrato_id', v_contrato_id,
                  'numero_contrato', v_resultado->>'numero_contrato'
                )::text;
      end if;
      -- El MISMO contrato, con el estado documental de HOY (la reserva pudo avanzar
      -- desde el primer intento) y la marca de que es un alta ya registrada.
      return (v_resultado - 'pdf')
        || jsonb_build_object('pdf', private.contrato_pdf_estado_base(v_contrato_id))
        || jsonb_build_object('idempotente', true);
    end if;
    v_contrato := p_contrato - 'clave_idempotencia';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    v_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  v_resultado := v_resultado || jsonb_build_object('pdf', v_pdf);
  if v_clave is not null then
    -- Misma transacción que el alta: o quedan los dos, o ninguno.
    insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
end;
$function$
;

do $post$
declare v_h text; v_owner text; v_definer boolean; v_config text[]; v_acl text;
begin
  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text, p.prosecdef, p.proconfig, p.proacl::text
    into v_h, v_owner, v_definer, v_config, v_acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb';
  if v_h is null then
    raise exception 'REPLAY EN ELIMINACION: falta crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)';
  end if;
  if v_h is distinct from '3d7680ae01b461f33deaa87b7cd0056b' and v_h is distinct from '9833ed526e733dc8af6ca78e5c85c7ca' then
    raise exception 'REPLAY EN ELIMINACION: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no es ni el texto vivo de producción (v2.1 de idempotencia) ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or v_config <> array['search_path=""'] then
    raise exception 'REPLAY EN ELIMINACION: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'REPLAY EN ELIMINACION: la ACL de crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no es la viva {postgres=X/postgres,authenticated=X/postgres} (%)', v_acl;
  end if;
  if v_h is distinct from '9833ed526e733dc8af6ca78e5c85c7ca' then
    raise exception 'POSTFLIGHT REPLAY EN ELIMINACION: el texto instalado no es el de esta migración (%)', v_h;
  end if;
end
$post$;

commit;

select 'ALTA_REPLAY_EN_ELIMINACION_OK' as resultado,
       (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2') as huella;
$m$])
on conflict (version) do nothing;
commit;
select 'REGISTRO_ALTA_REPLAY_EN_ELIMINACION_OK' as resultado, version, name, md5(statements[1]) as huella_archivo
from supabase_migrations.schema_migrations where version = '20260905234500';

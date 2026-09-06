-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-4]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.
-- Idempotente; toma el MISMO advisory que la migración y la reversa; exige la puerta con su cuerpo, definer, search_path,
-- lock_timeout y grants exactos, los helpers vivos que reutiliza, y se niega si la versión ya está registrada con OTRO contenido.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d4_importador_por_puerta'));
do $chk$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.importar_lead_fn(jsonb)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'd3ba66a37f66f6b9eae6f4c913e1a838') then
    raise exception 'REGISTRO D-4: crm.importar_lead_fn no quedó como la genera gen-d4.py (cuerpo, definer, dueño postgres, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('service_role', 'crm.importar_lead_fn(jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.importar_lead_fn(jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'crm.importar_lead_fn(jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.importar_lead_fn(jsonb)'::regprocedure and a.grantee = 0) then
    raise exception 'REGISTRO D-4: los grants de la puerta no son «solo service_role»';
  end if;
  if to_regprocedure('private.trg_leads_hereda_veto_persona()') is null or left(md5(pg_get_functiondef('private.trg_leads_hereda_veto_persona()'::regprocedure)), 8) <> 'f3fabb22' then
    raise exception 'REGISTRO D-4: private.trg_leads_hereda_veto_persona() falta o no es el texto vivo de producción (esperado f3fabb22…)';
  end if;
  if to_regprocedure('private.trg_leads_disponibilidad_atomica()') is null or left(md5(pg_get_functiondef('private.trg_leads_disponibilidad_atomica()'::regprocedure)), 8) <> 'fdae5787' then
    raise exception 'REGISTRO D-4: private.trg_leads_disponibilidad_atomica() falta o no es el texto vivo de producción (esperado fdae5787…)';
  end if;
  if to_regprocedure('private.trg_leads_zz_enlaza_identidad()') is null or left(md5(pg_get_functiondef('private.trg_leads_zz_enlaza_identidad()'::regprocedure)), 8) <> 'd6fa34ca' then
    raise exception 'REGISTRO D-4: private.trg_leads_zz_enlaza_identidad() falta o no es el texto vivo de producción (esperado d6fa34ca…)';
  end if;
  if to_regprocedure('private.bloquear_contactos_lead(text[],text[])') is null or left(md5(pg_get_functiondef('private.bloquear_contactos_lead(text[],text[])'::regprocedure)), 8) <> '0d52f58c' then
    raise exception 'REGISTRO D-4: private.bloquear_contactos_lead(text[],text[]) falta o no es el texto vivo de producción (esperado 0d52f58c…)';
  end if;
  if to_regprocedure('private.identidad_bloquear_documento(text,text)') is null or left(md5(pg_get_functiondef('private.identidad_bloquear_documento(text,text)'::regprocedure)), 8) <> '96de62e3' then
    raise exception 'REGISTRO D-4: private.identidad_bloquear_documento(text,text) falta o no es el texto vivo de producción (esperado 96de62e3…)';
  end if;
  if to_regprocedure('private.identidad_bloquear_persona(text,text)') is null or left(md5(pg_get_functiondef('private.identidad_bloquear_persona(text,text)'::regprocedure)), 8) <> 'b0ebfdb9' then
    raise exception 'REGISTRO D-4: private.identidad_bloquear_persona(text,text) falta o no es el texto vivo de producción (esperado b0ebfdb9…)';
  end if;
  if to_regprocedure('crm.registrar_reingreso_lead_fn(uuid,text,jsonb)') is null or left(md5(pg_get_functiondef('crm.registrar_reingreso_lead_fn(uuid,text,jsonb)'::regprocedure)), 8) <> '7acc82d8' then
    raise exception 'REGISTRO D-4: crm.registrar_reingreso_lead_fn(uuid,text,jsonb) falta o no es el texto vivo de producción (esperado 7acc82d8…)';
  end if;
  if to_regprocedure('private.leads_de_personas(uuid[])') is null or left(md5(pg_get_functiondef('private.leads_de_personas(uuid[])'::regprocedure)), 8) <> '6eded477' then
    raise exception 'REGISTRO D-4: private.leads_de_personas(uuid[]) falta o no es el texto vivo de producción (esperado 6eded477…)';
  end if;
  if to_regprocedure('private.inversionista_por_documento(text,text)') is null then
    raise exception 'REGISTRO D-4: falta private.inversionista_por_documento(text,text)';
  end if;
  if not exists (select 1 from pg_class c join pg_index i on i.indexrelid = c.oid where i.indrelid = 'crm.leads'::regclass and c.relname = 'uq_leads_telefono_vivo' and i.indisunique and left(md5(pg_get_indexdef(c.oid)), 8) = '9fab4b46') then
    raise exception 'REGISTRO D-4: el índice único crm.leads.uq_leads_telefono_vivo falta o no es el de producción (esperado 9fab4b46…)';
  end if;
  if not exists (select 1 from pg_class c join pg_index i on i.indexrelid = c.oid where i.indrelid = 'crm.leads'::regclass and c.relname = 'uq_leads_dni_vivo' and i.indisunique and left(md5(pg_get_indexdef(c.oid)), 8) = '28351eeb') then
    raise exception 'REGISTRO D-4: el índice único crm.leads.uq_leads_dni_vivo falta o no es el de producción (esperado 28351eeb…)';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_hereda_veto' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4) then
    raise exception 'REGISTRO D-4: el trigger de nacimiento crm.leads.trg_leads_000_hereda_veto falta, está deshabilitado o no es BEFORE INSERT';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4) then
    raise exception 'REGISTRO D-4: el trigger de nacimiento crm.leads.trg_leads_00_disponibilidad_insert falta, está deshabilitado o no es BEFORE INSERT';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_enlaza_identidad' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4) then
    raise exception 'REGISTRO D-4: el trigger de nacimiento crm.leads.trg_leads_zz_enlaza_identidad falta, está deshabilitado o no es BEFORE INSERT';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version='20260906130000' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> 'b48bc6b9f9a94ef638568ca97dd8caf7')) then
    raise exception 'REGISTRO D-4: la versión 20260906130000 ya está registrada con otro contenido (o incompleto)';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260906130000', 'crm_f2b_d4_importador_por_puerta_sql', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-4] — EL IMPORTADOR ENTRA POR UNA PUERTA SQL
-- (bloque 3 del plan de activación, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE: el edge crm-importar-leads (las filas de la hoja de Google, cada 5 minutos, con service_role) INSERTA hoy directo
-- en crm.leads y adivina el veredicto parseando los errores del INSERT (P0481 con el veredicto en DETAIL, P0429, 23505).
-- La puerta no valida nada que la fila al nacer no valide ya (misma prioridad que el INSERT directo) y el reingreso es
-- idempotente 24 h (la misma fila reenviada por la hoja no se anota dos veces).
-- Los leads del front entran por crm.crear_lead_si_disponible: candados en el orden TOTAL (documento → persona →
-- contactos → fila) y un veredicto único. Esta puerta hace el MISMO INSERT del edge bajo ese mismo orden (los de
-- identidad explícitos; los de contacto los toma el trigger 00 tras el veto 000, como hoy) y devuelve un veredicto:
--   crm.importar_lead_fn(p_fila jsonb) → {resultado, lead_id, veredicto, reingreso}   (SOLO service_role, sin sesión)
--   · resultado = importado (insertó, mismo payload del edge) | duplicado (lead vivo con ese teléfono/DNI) |
--     ya_cliente (persona reconocida por identidad, bandera encendida; anota el REINGRESO en su lead en la misma
--     transacción vía crm.registrar_reingreso_lead_fn) | rechazado (enfriamiento, reutilizable, no_contactar,
--     ya_es_cliente por perfil con la bandera apagada…), con el veredicto íntegro para que la hoja reciba el mismo texto.
--   · Con resolver_en_puertas APAGADA responde exactamente lo que hoy produce el INSERT directo: los candados de
--     identidad no toman nada y el verificador no mira la identidad. No hay bandera propia: la puerta es inerte hasta
--     que el edge la llame (fase 2 del bloque 3, deploy aparte).
-- No transforma ninguna función viva. Guardas: huellas de los helpers que reutiliza y de las PREMISAS de nacimiento que
-- interpreta (triggers 000/00/zz habilitados BEFORE INSERT e índices únicos de teléfono/DNI vivos: son el contrato del
-- importador); postflight: cuerpo, definer, dueño, search_path, lock_timeout y grants. Ensayo: scripts/oraculo-f2b-d4.sh (INSERT directo vs puerta, fila a fila, OFF y ON).
-- Reversa: scripts/rollback-f2b-d4.sql (DROP). Registro: scripts/registrar-f2b-d4.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d4_importador_por_puerta'));

do $guard$
begin
  if to_regprocedure('private.trg_leads_hereda_veto_persona()') is null or left(md5(pg_get_functiondef('private.trg_leads_hereda_veto_persona()'::regprocedure)), 8) <> 'f3fabb22' then
    raise exception 'F2.b D-4: private.trg_leads_hereda_veto_persona() falta o no es el texto vivo de producción (esperado f3fabb22…)';
  end if;
  if to_regprocedure('private.trg_leads_disponibilidad_atomica()') is null or left(md5(pg_get_functiondef('private.trg_leads_disponibilidad_atomica()'::regprocedure)), 8) <> 'fdae5787' then
    raise exception 'F2.b D-4: private.trg_leads_disponibilidad_atomica() falta o no es el texto vivo de producción (esperado fdae5787…)';
  end if;
  if to_regprocedure('private.trg_leads_zz_enlaza_identidad()') is null or left(md5(pg_get_functiondef('private.trg_leads_zz_enlaza_identidad()'::regprocedure)), 8) <> 'd6fa34ca' then
    raise exception 'F2.b D-4: private.trg_leads_zz_enlaza_identidad() falta o no es el texto vivo de producción (esperado d6fa34ca…)';
  end if;
  if to_regprocedure('private.bloquear_contactos_lead(text[],text[])') is null or left(md5(pg_get_functiondef('private.bloquear_contactos_lead(text[],text[])'::regprocedure)), 8) <> '0d52f58c' then
    raise exception 'F2.b D-4: private.bloquear_contactos_lead(text[],text[]) falta o no es el texto vivo de producción (esperado 0d52f58c…)';
  end if;
  if to_regprocedure('private.identidad_bloquear_documento(text,text)') is null or left(md5(pg_get_functiondef('private.identidad_bloquear_documento(text,text)'::regprocedure)), 8) <> '96de62e3' then
    raise exception 'F2.b D-4: private.identidad_bloquear_documento(text,text) falta o no es el texto vivo de producción (esperado 96de62e3…)';
  end if;
  if to_regprocedure('private.identidad_bloquear_persona(text,text)') is null or left(md5(pg_get_functiondef('private.identidad_bloquear_persona(text,text)'::regprocedure)), 8) <> 'b0ebfdb9' then
    raise exception 'F2.b D-4: private.identidad_bloquear_persona(text,text) falta o no es el texto vivo de producción (esperado b0ebfdb9…)';
  end if;
  if to_regprocedure('crm.registrar_reingreso_lead_fn(uuid,text,jsonb)') is null or left(md5(pg_get_functiondef('crm.registrar_reingreso_lead_fn(uuid,text,jsonb)'::regprocedure)), 8) <> '7acc82d8' then
    raise exception 'F2.b D-4: crm.registrar_reingreso_lead_fn(uuid,text,jsonb) falta o no es el texto vivo de producción (esperado 7acc82d8…)';
  end if;
  if to_regprocedure('private.leads_de_personas(uuid[])') is null or left(md5(pg_get_functiondef('private.leads_de_personas(uuid[])'::regprocedure)), 8) <> '6eded477' then
    raise exception 'F2.b D-4: private.leads_de_personas(uuid[]) falta o no es el texto vivo de producción (esperado 6eded477…)';
  end if;
  if to_regprocedure('private.inversionista_por_documento(text,text)') is null then
    raise exception 'F2.b D-4: falta private.inversionista_por_documento(text,text)';
  end if;
  if not exists (select 1 from pg_class c join pg_index i on i.indexrelid = c.oid where i.indrelid = 'crm.leads'::regclass and c.relname = 'uq_leads_telefono_vivo' and i.indisunique and left(md5(pg_get_indexdef(c.oid)), 8) = '9fab4b46') then
    raise exception 'F2.b D-4: el índice único crm.leads.uq_leads_telefono_vivo falta o no es el de producción (esperado 9fab4b46…)';
  end if;
  if not exists (select 1 from pg_class c join pg_index i on i.indexrelid = c.oid where i.indrelid = 'crm.leads'::regclass and c.relname = 'uq_leads_dni_vivo' and i.indisunique and left(md5(pg_get_indexdef(c.oid)), 8) = '28351eeb') then
    raise exception 'F2.b D-4: el índice único crm.leads.uq_leads_dni_vivo falta o no es el de producción (esperado 28351eeb…)';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_hereda_veto' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4) then
    raise exception 'F2.b D-4: el trigger de nacimiento crm.leads.trg_leads_000_hereda_veto falta, está deshabilitado o no es BEFORE INSERT';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4) then
    raise exception 'F2.b D-4: el trigger de nacimiento crm.leads.trg_leads_00_disponibilidad_insert falta, está deshabilitado o no es BEFORE INSERT';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_enlaza_identidad' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4) then
    raise exception 'F2.b D-4: el trigger de nacimiento crm.leads.trg_leads_zz_enlaza_identidad falta, está deshabilitado o no es BEFORE INSERT';
  end if;
end
$guard$;

-- ============================================================================
-- 1. crm.importar_lead_fn(jsonb): la puerta del importador
-- ============================================================================
create or replace function crm.importar_lead_fn(p_fila jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare
  v_id         uuid := pg_catalog.gen_random_uuid();
  v_nombre     text := nullif(pg_catalog.btrim(p_fila->>'nombre_completo'), '');
  v_telefono   text := nullif(pg_catalog.btrim(p_fila->>'telefono'), '');
  v_alt        text := nullif(pg_catalog.btrim(p_fila->>'telefono_alternativo'), '');
  v_alt_crudo  text := nullif(pg_catalog.btrim(p_fila->>'telefono_alternativo_crudo'), '');
  v_correo     text := nullif(pg_catalog.btrim(p_fila->>'correo'), '');
  v_dni        text := nullif(pg_catalog.btrim(p_fila->>'dni'), '');
  v_genero     text := nullif(pg_catalog.btrim(p_fila->>'genero'), '');
  v_fecha      date;
  v_distrito   text := nullif(pg_catalog.btrim(p_fila->>'distrito'), '');
  v_origen     text := nullif(pg_catalog.btrim(p_fila->>'origen'), '');
  v_monto      numeric;
  v_moneda     text := nullif(pg_catalog.btrim(p_fila->>'moneda'), '');
  v_categoria  text := nullif(pg_catalog.btrim(p_fila->>'categoria_interes'), '');
  v_nota       text := nullif(pg_catalog.btrim(p_fila->>'nota'), '');
  v_cons_en    timestamptz;
  v_cons_fuente text := nullif(pg_catalog.btrim(p_fila->>'consentimiento_fuente'), '');
  v_vendedor   uuid;
  v_detalle    text;
  v_constraint text;
  v_veredicto  jsonb;
  v_resultado  text;
  v_lead       uuid;
  v_reingreso  jsonb;
  v_datos      jsonb;
  v_prev       uuid;
begin
  -- F2.b [D-4]: solo el importador (service_role, sin sesión de usuario), la misma regla que registrar_reingreso_lead_fn.
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) usa esta puerta' using errcode = '42501';
  end if;
  -- Defensa en profundidad (auditor N5): esta puerta nunca corre como operación privilegiada, venga como venga la sesión.
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  if p_fila is null or pg_catalog.jsonb_typeof(p_fila) <> 'object' then
    raise exception 'Fila invalida' using errcode = '22023';
  end if;
  -- Los casts van DESPUÉS de la autorización (Codex v3 #6): un payload malformado no cambia el 42501 por un 22xxx.
  v_fecha    := nullif(pg_catalog.btrim(p_fila->>'fecha_nacimiento'), '')::date;
  v_monto    := nullif(pg_catalog.btrim(p_fila->>'monto_estimado'), '')::numeric;
  v_cons_en  := nullif(pg_catalog.btrim(p_fila->>'consentimiento_en'), '')::timestamptz;
  v_vendedor := nullif(pg_catalog.btrim(p_fila->>'vendedor_id'), '')::uuid;
  -- La puerta NO valida el formato: lo hace la fila al nacer (trigger 00: teléfono y DNI → 22023 con el mismo texto de
  -- hoy; NOT NULL y CHECKs de la tabla), con la MISMA prioridad que el INSERT directo —el veto de la persona (000) va
  -- antes que el formato— (Codex v4 #9). El teléfono viaja crudo, como lo manda el edge; lo normaliza el trigger de la tabla.

  -- Orden TOTAL de candados (b1/D-13, el de crm.crear_lead_si_disponible): documento → persona → contactos → fila.
  -- El INSERT directo de hoy YA los toma en ese orden (triggers BEFORE 000 → 00, antes de tocar tupla e índice). Aquí
  -- se toman explícitos SOLO los de identidad (documento → persona; apagada la bandera no toman nada), antes del
  -- sub-bloque para que sobrevivan a su rollback y el reingreso corra con la persona retenida. Los de CONTACTO los toma
  -- el trigger 00 del INSERT, DESPUÉS del veto de la persona (000), exactamente como el INSERT directo: una persona
  -- vetada recibe su «no insistir» sin esperar por un teléfono retenido (Codex v3 #3). D-4 no cambia el orden: lo que
  -- aporta es un veredicto único sin parsear SQLSTATE y el reingreso en la misma transacción.
  perform private.identidad_bloquear_documento('DNI', v_dni);
  perform private.identidad_bloquear_persona('DNI', v_dni);

  -- El CONTRATO del importador es el de la fila al nacer sin sesión humana (trigger de disponibilidad: «un escritor
  -- interno se serializa pero conserva su contrato especializado»): NO se consulta la disponibilidad comercial
  -- (enfriamiento, ficha de cliente, «no insistir» de un lead viejo) —el cliente que vuelve por la hoja es el mejor
  -- lead posible—; sí mandan el índice único de teléfono VIVO (duplicado) y, con la identidad encendida, los triggers
  -- de nacimiento: 000 (la persona vetada → P0429) y zz (la persona ya tiene lead o está en conversión → P0481 por
  -- identidad). Por eso la puerta hace el MISMO INSERT (payload exacto del edge: sin sesión, cola global, alta_manual
  -- por defecto) y convierte esos tres resultados en un veredicto en vez de una excepción.
  begin
    insert into crm.leads (
      id, nombre_completo, telefono, telefono_alternativo, telefono_alternativo_crudo, correo, dni, genero,
      fecha_nacimiento, distrito, origen, etapa, monto_estimado, moneda, categoria_interes, nota, no_contactar,
      consentimiento_en, consentimiento_fuente, vendedor_id, asignado_supervisor_id, activo, creado_por
    ) values (
      v_id, v_nombre, v_telefono, v_alt, v_alt_crudo, v_correo, v_dni, v_genero,
      v_fecha, v_distrito, v_origen, 'nuevo', v_monto, v_moneda, v_categoria, v_nota, false,
      v_cons_en, v_cons_fuente, v_vendedor, null, true, null
    );
    return pg_catalog.jsonb_build_object('resultado', 'importado', 'lead_id', v_id, 'veredicto', null, 'reingreso', null);
  exception
    when unique_violation then
      -- uq_leads_telefono_vivo (o uq_leads_dni_vivo): ya hay un lead VIVO con ese contacto → DUPLICADO (hoy: 23505).
      -- Se devuelve el NOMBRE del índice, no el DETAIL (que lleva el teléfono o el DNI en claro; auditor N1).
      get stacked diagnostics v_constraint = constraint_name;
      v_veredicto := pg_catalog.jsonb_build_object('estado', 'duplicado', 'indice', coalesce(v_constraint, 'desconocido'));
      v_resultado := 'duplicado';
    when sqlstate 'P0481' then
      -- «Contacto no disponible» con el veredicto en DETAIL (hoy lo parsea el edge): ya_es_cliente por identidad
      -- (con lead_id) o en conversión → ya_cliente; cualquier otro → rechazado.
      get stacked diagnostics v_detalle = pg_exception_detail;
      begin
        v_veredicto := v_detalle::jsonb;
      exception when others then
        v_veredicto := pg_catalog.jsonb_build_object('estado', 'no_disponible', 'detalle', pg_catalog.left(coalesce(v_detalle, ''), 200));
      end;
      v_resultado := case when v_veredicto->>'estado' = 'ya_es_cliente' and v_veredicto->>'via' = 'identidad' then 'ya_cliente' else 'rechazado' end;
    when sqlstate 'P0429' then
      -- La persona tiene «No insistir» (trigger 000, identidad encendida) → RECHAZADO (hoy: P0429).
      get stacked diagnostics v_detalle = pg_exception_detail;
      begin
        v_veredicto := coalesce(nullif(v_detalle, '')::jsonb, pg_catalog.jsonb_build_object('estado', 'no_contactar'));
      exception when others then
        v_veredicto := pg_catalog.jsonb_build_object('estado', 'no_contactar');
      end;
      v_resultado := 'rechazado';
  end;

  v_lead := nullif(v_veredicto->>'lead_id', '')::uuid;
  if v_resultado = 'ya_cliente' and v_lead is not null then
    -- El reingreso en la MISMA transacción (hoy el edge lo pedía aparte tras leer el error). Si fallara de forma
    -- DEFINITIVA, la fila sigue siendo «ya cliente» y el edge lo dice en la hoja, como hoy.
    v_datos := pg_catalog.jsonb_build_object(
      'fila', p_fila->'fila', 'nombre', v_nombre, 'telefono', v_telefono, 'telefono_alternativo', v_alt,
      'correo', v_correo, 'capital', v_monto, 'moneda', v_moneda, 'canal', v_origen, 'distrito', v_distrito,
      'interes', v_categoria, 'nota', v_nota);
    -- IDEMPOTENCIA (Codex v4 #7): si la hoja reenvía la MISMA fila (perdió la confirmación HTTP o el lote falló después),
    -- el reingreso ya anotado en las últimas 24 h vale: no se escribe una segunda nota. Misma persona, mismo origen y
    -- los mismos datos (lo que registrar_reingreso_lead_fn guarda en metadata.datos).
    select a.id into v_prev
      from crm.actividades a
     where a.lead_id = v_lead
       and a.metadata->>'evento' = 'reingreso'
       and a.metadata->>'origen' = 'hoja'
       and a.metadata->'datos' = v_datos
       and a.creado_en > pg_catalog.now() - interval '24 hours'
     order by a.creado_en desc
     limit 1;
    if v_prev is not null then
      v_reingreso := pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_prev, 'repetido', true);
    else
      begin
        v_reingreso := crm.registrar_reingreso_lead_fn(v_lead, 'hoja', v_datos);
      exception when others then
        -- Un fallo TRANSITORIO sube entero: el edge lo trata como temporal y la fila se reintenta en el siguiente lote
        -- (auditor M4). Las clases son LAS MISMAS que el edge considera temporales (Codex v4 #8): conexión (08),
        -- transacción (40), recursos (53), candado (55), operador/cancelación (57), E/S (58) e internos (XX).
        -- Solo lo definitivo queda anotado en la respuesta.
        if pg_catalog.left(sqlstate, 2) in ('08', '40', '53', '55', '57', '58', 'XX') then
          raise;
        end if;
        v_reingreso := pg_catalog.jsonb_build_object('ok', false, 'error', sqlstate || ': ' || pg_catalog.left(sqlerrm, 120));
      end;
    end if;
  end if;

  return pg_catalog.jsonb_build_object('resultado', v_resultado, 'lead_id', v_lead, 'veredicto', v_veredicto, 'reingreso', v_reingreso);
end;
$function$;
revoke all on function crm.importar_lead_fn(jsonb) from public, anon, authenticated;
grant execute on function crm.importar_lead_fn(jsonb) to service_role;
comment on function crm.importar_lead_fn(jsonb) is 'F2.b [D-4]: puerta SQL del importador (solo service_role). Una fila de la hoja → veredicto {resultado, lead_id, veredicto, reingreso}; el MISMO INSERT del edge bajo el orden total de candados, con el reingreso en la misma transacción.';

do $post$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.importar_lead_fn(jsonb)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'd3ba66a37f66f6b9eae6f4c913e1a838') then
    raise exception 'POSTFLIGHT D-4: crm.importar_lead_fn no quedó como la genera gen-d4.py (cuerpo, definer, dueño postgres, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('service_role', 'crm.importar_lead_fn(jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.importar_lead_fn(jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'crm.importar_lead_fn(jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.importar_lead_fn(jsonb)'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-4: los grants de la puerta no son «solo service_role»';
  end if;
  raise notice 'F2.b D-4 OK: crm.importar_lead_fn creada (solo service_role); inerte hasta que el edge la llame.';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
commit;

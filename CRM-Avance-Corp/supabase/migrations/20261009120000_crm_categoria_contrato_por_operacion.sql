-- 20261009120000_crm_categoria_contrato_por_operacion.sql
--
-- La categoría de un contrato con operación de cartera es la de su operación: «la operación decide».
-- Decisión de Miguel (08/10/2026, auditoría de Facturación): «El tipo de un contrato lo decide la operación de cartera».
-- Miguel dio OK para tocar public.contratos (puerta + trigger). La puerta es SOLO para Gerencia.
--
-- POR QUÉ
--   12 contratos de septiembre (8 en soles, 4 en dólares) están en 'nuevo' y tienen una operación de cartera 'upgrade'.
--   Medido en producción (08/10 19:11, solo lectura): nacieron 'nuevo', nadie les cambió la categoría y la operación se
--   creó DESPUÉS, sobre el contrato ya existente (fuente 'flujo_cartera', no nació con el contrato). 11 de los 12 son el
--   backfill único de conversión del 23/09 (supabase/scripts/backfill-conversion-2026-09/backfill-B-setiembre-2026.sql),
--   que insertó la operación «sin tocar contratos». Dentro del servidor, el único que escribe operaciones es
--   public.crear_contrato, y escribe la MISMA categoría en el contrato y en la operación. El error entra por un INSERT
--   directo de la operación, no por una función: por eso la regla vive en triggers (vale para toda vía).
--
-- QUÉ HACE (orden: núcleo → puerta → triggers → permisos → comentarios)
--   1. Núcleo private.fijar_categoria_contrato(contrato, categoria, motivo, via, usuario): UNA definición de «poner la
--      categoría de un contrato». Solo en READ COMMITTED (25001 si no: el sello tiene que verse con la foto de AHORA).
--      Candados en el orden del sello: primero el del mes (leyendo el día comercial sin bloquear), después la fila, y se
--      revalida que el mes no cambió (40001, reintenta). Si ya tiene esa categoría no escribe nada; contrato en
--      eliminación → 55000; mes comercial sellado → P0409; respaldo: con operación, la categoría tiene que ser la de la
--      operación, y sin operación solo 'nuevo' → 23514. No declara contrato de origen (crm.rentabilidad_origen_upgrade
--      vacío durante el UPDATE y repuesto después), abre la congelación del PDF SOLO para ese contrato y la cierra también
--      si algo falla, cambia SOLO la categoría y deja una fila de motivo en public.audit_log. NO crea revisión de PDF.
--   2. Puerta crm.corregir_categoria_contrato_fn(p_contrato_id, p_categoria, p_motivo): solo Gerencia vigente con la
--      membresía CRM sin revocar; motivo de 5 a 300 caracteres. Valida, autoriza y llama al núcleo.
--   3. Trigger trg_operaciones_cartera_10_fija_categoria (AFTER INSERT OR UPDATE OF tipo, contrato_nuevo_id en
--      crm.operaciones_cartera): una renovación o un upgrade solo se registran en READ COMMITTED (25001, antes de
--      cualquier candado). SIEMPRE bloquea el contrato (mes y fila, en ese orden) antes de leer su categoría —también
--      cuando ya coincide—, así un UPDATE de la categoría en curso no puede colarse; si difiere, la categoría pasa a la de
--      la operación en la MISMA transacción, por el núcleo (mes sellado → P0409 y no entra la operación). En el alta
--      normal (public.crear_contrato) la categoría ya coincide y no toca nada más (ni la declaración de origen).
--   4. Trigger trg_contratos_01_categoria_por_operacion (AFTER UPDATE en public.contratos, por fila, WHEN la categoría
--      cambió): una categoría solo cambia en READ COMMITTED (25001, antes de buscar la operación: con una foto vieja no
--      se vería una operación recién confirmada). Mira la fila FINAL (después de todos los BEFORE): si el contrato tiene
--      operación de cartera, su categoría tiene que ser la de la operación (23514 «La categoría la decide la operación
--      de cartera»). Sin operación no se restringe: los contratos antiguos (marzo a julio) siguen como están.
--   La API (PostgREST) ya trabaja en READ COMMITTED. Lo que cambie una categoría desde SQL —también una migración futura,
--   aunque la convención de las migraciones sea REPEATABLE READ— tiene que abrir la transacción en READ COMMITTED.
-- QUÉ NO CAMBIA: el alta y sus envoltorios, el cinturón del alta (trg_contratos_operacion_cartera_commit), la congelación
--   del PDF para todo lo demás, el observador de rentabilidad, las operaciones (siguen sin poder editarse ni borrarse).
--   NO toca datos: los 12 se corrigen DESPUÉS con la puerta (supabase/scripts/categoria-por-operacion/1-ENSAYO.sql y
--   2-REAL.sql).
-- EFECTO CONOCIDO: lo que hoy cambia en silencio la categoría de un contrato con operación (p. ej. elegir una condición
--   de catálogo en «Corregir», contrato-corregir.tsx) recibirá el 23514 con ese texto.
-- PREFLIGHT: las 12 huellas R7 (md5 de pg_get_functiondef con public en el search_path, medidas en producción el 08/10 a
--   las 19:11), definición + dueño + ACL de las otras 9 piezas de las que depende (medidas en el banco, que es el volcado
--   de producción del 08/10 a las 19:14), los 15 triggers de public.contratos (R7) y los 2 de crm.operaciones_cartera
--   exactos y habilitados, contrato_nuevo_id único y nombres libres. Después toma public.contratos y
--   crm.operaciones_cartera (SHARE ROW EXCLUSIVE) en el orden del alta.
-- POSTFLIGHT: dueño postgres, search_path vacío, SECURITY como se declara, ACL exacta (sin PUBLIC ni anon), triggers
--   presentes y habilitados con su forma, las piezas previas intactas, ningún dato escrito y pruebas en negativo que se
--   deshacen (puerta sin sesión → 42501; un contrato legacy con operación llevado a otra categoría → 23514 con el texto
--   «La categoría la decide la operación de cartera»).
-- REVERSA: supabase/scripts/categoria-por-operacion/reversa.sql (esquema) y reversa-datos.sql (los 12; solo con su mes
--   abierto y DESPUÉS de reversa.sql: mientras exista la prevención nada puede volver a dejarlos en 'nuevo').
-- REGISTRO: supabase/scripts/categoria-por-operacion/registrar/20261009120000.sql (`db query --file` NO registra).
-- TIPOS: `npm run gen:types` en app/ DESPUÉS de aplicarla en producción (la puerta es una función nueva de crm).

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

-- READ COMMITTED (no REPEATABLE READ como otras migraciones): la guarda que se crea aquí solo deja cambiar una categoría
-- en READ COMMITTED, y la prueba en negativo 2 del postflight cambia una dentro de esta transacción. Explícito, para no
-- heredar el aislamiento por defecto de la sesión.
begin;
set transaction isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local quote_all_identifiers = off;
-- Las huellas R7 y la de los triggers se midieron con public en el search_path: el texto de pg_get_functiondef y de
-- pg_get_triggerdef cambia con él. Solo para el preflight; después, search_path vacío.
set local search_path = public;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  r record;
begin
  -- R7: producción, 08/10/2026 19:11 (salida/medir-categoria.json). Si algo cambió desde entonces, no se aplica.
  for r in select * from (values
    ('private.trg_contratos_observar_rentabilidad()', '9a0c04118488b8ec0058a40d71cebcec'),
    ('private.proteger_contrato_documental()', 'ad8ebbb6fd6fe738195bc1c91c1a54e9'),
    ('private.mutacion_documental_autorizada(uuid)', '9f2fa9a2d81aa76bafaf70d127f1f928'),
    ('private.trg_contratos_producto_snapshot()', 'c4c222984db5bf6232edae70b0ee19f1'),
    ('private.trg_contrato_exige_operacion_cartera()', '05eb8f83c80398bed044e46715763d90'),
    ('private.rentabilidad_origen_declarado(public.contratos)', '1a7c2f07a86eaa69cb26c3bdcf6b8b36'),
    ('private.analista_atribuido_cadena(uuid)', '3c9cec305b014ad8c933df25057d3e8b'),
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', 'c9e58c1da9dd7a5d52991c9e47dc19d5'),
    ('private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'b71910d2af0cb7a257d44faef612b8c9'),
    ('crm.corregir_fecha_cierre_comercial(uuid,date,text)', 'd56f800dc5e279c3d4d5e08625856fc7'),
    ('public.actualizar_contrato(uuid,jsonb,jsonb)', '6184aad4be1b234db83b096e08e92428'),
    ('public.actualizar_numero_contrato(uuid,text,text,text)', '84ba035d9888b7d4b5494c82b8e04b00')
  ) as v(firma, huella) loop
    if to_regprocedure(r.firma) is null
       or md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'CATEGORIA: % cambió desde la medición del 08/10; revisar antes de aplicar', r.firma
        using errcode = 'P0409';
    end if;
  end loop;

  -- Otras piezas de las que depende el diseño: definición completa (md5 de pg_get_functiondef con public en el
  -- search_path: cuerpo, SECURITY y search_path fijado), dueño y permisos. Medidas en el banco, que es el volcado de
  -- producción del 08/10 19:14 (re-volcado del banco = ese volcado).
  --   crear_contrato y su envoltorio: el alta escribe la misma categoría en contrato y operación (la sincronización no hace nada).
  --   append_only: una operación no se edita (por eso basta mirar el INSERT).
  for r in select * from (values
    ('public.crear_contrato(jsonb,jsonb)', 'dce8f0dd6d6776b960096c56bdc29173',
     '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'd0b33d8fb1d27ef2da62105b7ccabd88',
     '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.trg_operaciones_cartera_append_only()', '13ab28fb606943c2f84b1fca7673ed31', '{postgres=X/postgres}'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.membresia_crm_revocada()', '47f8ceb6455f4855562941a7057be02c', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.contrato_en_eliminacion(uuid)', 'a359830b9cc889532d6aa31036d8eb8f', '{postgres=X/postgres}'),
    ('private.contrato_documental_congelado(uuid)', 'a3e9b19959f0c0d6c02681c928d8d464', '{postgres=X/postgres}'),
    ('private.crear_snapshot_producto_legacy(uuid,text,text,text,text,numeric,numeric,date,date)',
     'b4b82b6ad6ec34c2b09617a87d300cc7', '{postgres=X/postgres}'),
    ('public.log_audit_change()', 'e4b2d9805ac5283016b11a2bee0313e5', '{postgres=X/postgres,service_role=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p
                    where p.oid = to_regprocedure(r.firma) and md5(pg_get_functiondef(p.oid)) = r.huella
                      and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl) then
      raise exception 'CATEGORIA: % cambió (cuerpo, dueño o permisos); revisar antes de aplicar', r.firma
        using errcode = 'P0409';
    end if;
  end loop;

  -- Los 15 triggers de public.contratos tal como los midió R7, todos habilitados.
  if (select md5(string_agg(t.tgname || '|' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname))
        from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal)
       is distinct from '7acf3de332dc5c670f013dbc4ee64f6f'
     or exists (select 1 from pg_trigger t
                 where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal and t.tgenabled <> 'O') then
    raise exception 'CATEGORIA: los triggers de public.contratos no son los medidos el 08/10; revisar antes de aplicar'
      using errcode = 'P0409';
  end if;
  -- Los 2 de crm.operaciones_cartera (auditoría y append-only), habilitados.
  if (select md5(string_agg(t.tgname || '|' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname))
        from pg_trigger t where t.tgrelid = 'crm.operaciones_cartera'::regclass and not t.tgisinternal)
       is distinct from '442178a6bbfc450b23223d74df6cfb7e'
     or exists (select 1 from pg_trigger t
                 where t.tgrelid = 'crm.operaciones_cartera'::regclass and not t.tgisinternal and t.tgenabled <> 'O') then
    raise exception 'CATEGORIA: los triggers de crm.operaciones_cartera cambiaron; revisar antes de aplicar'
      using errcode = 'P0409';
  end if;

  -- Una operación por contrato: el respaldo lee LA operación del contrato.
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'crm.operaciones_cartera'::regclass and c.contype = 'u'
                    and c.conname = 'operaciones_cartera_contrato_nuevo_id_key') then
    raise exception 'CATEGORIA: falta la unicidad de crm.operaciones_cartera.contrato_nuevo_id' using errcode = 'P0409';
  end if;

  -- Nombres libres: si algo ya existe, esta migración ya se aplicó (o hay otra a medias).
  if to_regprocedure('crm.corregir_categoria_contrato_fn(uuid,text,text)') is not null
     or to_regprocedure('private.fijar_categoria_contrato(uuid,text,text,text,uuid)') is not null
     or to_regprocedure('private.trg_operacion_cartera_fija_categoria()') is not null
     or to_regprocedure('private.trg_contrato_categoria_por_operacion()') is not null
     or exists (select 1 from pg_trigger t
                 where t.tgname in ('trg_contratos_01_categoria_por_operacion', 'trg_operaciones_cartera_10_fija_categoria')) then
    raise exception 'CATEGORIA: la puerta, el núcleo o los triggers ya existen; esta migración ya se aplicó'
      using errcode = 'P0409';
  end if;
end;
$preflight$;

-- Foto de las piezas previas (para comprobar al final que nada cambió) y de la bitácora de categoría (ningún dato escrito).
create temporary table categoria_piezas_antes on commit drop as
  select p.oid as funcion, md5(p.prosrc) as huella, p.proacl::text as acl
    from pg_proc p
   where p.oid in (
     'private.trg_contratos_observar_rentabilidad()'::regprocedure,
     'private.proteger_contrato_documental()'::regprocedure,
     'private.mutacion_documental_autorizada(uuid)'::regprocedure,
     'private.trg_contratos_producto_snapshot()'::regprocedure,
     'private.trg_contrato_exige_operacion_cartera()'::regprocedure,
     'private.rentabilidad_origen_declarado(public.contratos)'::regprocedure,
     'public.crear_contrato(jsonb,jsonb)'::regprocedure,
     'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure,
     'private.trg_operaciones_cartera_append_only()'::regprocedure,
     'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure,
     'public.actualizar_numero_contrato(uuid,text,text,text)'::regprocedure);
create temporary table categoria_bitacora_antes on commit drop as
  select count(*) as filas from public.audit_log a where a.tabla = 'contratos.categoria';

set local search_path = '';

-- Candado de las dos tablas en el MISMO orden que el alta (public.crear_contrato escribe el contrato y después la
-- operación): sin esto, un alta de upgrade a medias y esta migración podrían bloquearse mutuamente. Con lock_timeout 5 s.
lock table public.contratos, crm.operaciones_cartera in share row exclusive mode;

-- ── 1 · Núcleo ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- SECURITY INVOKER: solo lo llaman la puerta y el trigger de la operación (los dos SECURITY DEFINER, dueño postgres);
-- ningún rol de la API puede ejecutarlo.
create function private.fijar_categoria_contrato(
  p_contrato_id uuid,
  p_categoria text,
  p_motivo text,
  p_via text,
  p_usuario_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $nucleo$
declare
  v_contrato public.contratos%rowtype;
  v_motivo text := btrim(p_motivo);
  v_fecha date;
  v_periodo date;
  v_operacion_id uuid;
  v_operacion_tipo text;
  v_guc_previo text;
  v_origen_previo text;
begin
  -- Solo READ COMMITTED: con una foto vieja (REPEATABLE READ o SERIALIZABLE) el candado del mes llegaría tarde y la
  -- comprobación del sello no vería un sello recién confirmado.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La categoría de un contrato solo se corrige en una transacción READ COMMITTED'
      using errcode = '25001',
            hint = 'Con una foto vieja no se vería un sello mensual recién confirmado.';
  end if;
  if p_contrato_id is null
     or p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade')
     or v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300
     or p_via is null or p_via not in ('puerta', 'operacion_de_cartera') then
    raise exception 'Datos inválidos para fijar la categoría del contrato' using errcode = '22023';
  end if;

  -- Candados en el orden del sello mensual: primero el del mes (el día comercial se lee SIN bloquear la fila), después la
  -- fila, y se comprueba que el mes no cambió mientras se esperaba.
  select c.fecha_cierre_comercial into v_fecha from public.contratos c where c.id = p_contrato_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  v_periodo := date_trunc('month', v_fecha)::date;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );
  select c.* into v_contrato from public.contratos c where c.id = p_contrato_id for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  if date_trunc('month', v_contrato.fecha_cierre_comercial)::date is distinct from v_periodo then
    raise exception 'El día comercial del contrato cambió mientras se corregía su categoría; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  -- Ya tiene esa categoría: no se escribe nada (ni contrato ni bitácora).
  if v_contrato.categoria is not distinct from p_categoria then
    return jsonb_build_object('ok', true, 'cambio', false, 'contrato_id', p_contrato_id, 'categoria', p_categoria);
  end if;

  -- Un contrato que se está eliminando no se toca (la congelación abierta lo dejaría pasar: se pregunta antes).
  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación' using errcode = '55000';
  end if;

  -- Con el candado del mes ya tomado (mismas llaves que el sello): o el sello fue antes y aquí se rechaza, o esta
  -- corrección entra antes del sello.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    raise exception 'No se puede reescribir un mes comercial sellado'
      using errcode = 'P0409',
            hint = 'La categoría se corrige antes del sello mensual. Lo sellado no se reescribe.';
  end if;

  -- Respaldo: con operación de cartera manda la operación; sin operación solo cabe 'nuevo'.
  select o.id, o.tipo into v_operacion_id, v_operacion_tipo
    from crm.operaciones_cartera o
   where o.contrato_nuevo_id = p_contrato_id;
  if v_operacion_id is not null then
    if p_categoria is distinct from v_operacion_tipo then
      raise exception 'La categoría la decide la operación de cartera'
        using errcode = '23514',
              detail = format('El contrato tiene una operación de cartera de tipo %s.', v_operacion_tipo);
    end if;
  elsif p_categoria <> 'nuevo' then
    raise exception 'Un contrato sin operación de cartera solo puede quedar como nuevo'
      using errcode = '23514',
            hint = 'Una renovación o un upgrade se registran por el flujo de cartera, que crea su operación.';
  end if;

  -- Durante el UPDATE: sin contrato de origen declarado (si el observador de rentabilidad corre en ese momento, lo
  -- resuelve como sin_regla y la tasa no entra en juego) y la congelación del PDF abierta SOLO para este contrato. Los dos
  -- GUC vuelven a su valor anterior después (una declaración pendiente de un alta de la misma transacción no se pierde),
  -- también si el UPDATE falla.
  v_origen_previo := coalesce(pg_catalog.current_setting('crm.rentabilidad_origen_upgrade', true), '');
  v_guc_previo := coalesce(pg_catalog.current_setting('crm.contrato_pdf_revision_autorizada', true), '');
  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', '', true);
  perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', p_contrato_id::text, true);
  begin
    update public.contratos c set categoria = p_categoria where c.id = p_contrato_id;
  exception when others then
    perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_guc_previo, true);
    perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', v_origen_previo, true);
    raise;
  end;
  perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_guc_previo, true);
  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', v_origen_previo, true);

  -- trg_audit_contratos ya guardó la fila completa (antes y después). Esta fila hermana guarda el motivo.
  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    'contratos.categoria', 'UPDATE', p_contrato_id::text, p_usuario_id,
    jsonb_build_object('categoria', v_contrato.categoria),
    jsonb_build_object('categoria', p_categoria, 'motivo', v_motivo, 'via', p_via,
                       'operacion_id', v_operacion_id, 'operacion_tipo', v_operacion_tipo)
  );

  return jsonb_build_object(
    'ok', true, 'cambio', true, 'contrato_id', p_contrato_id,
    'categoria_anterior', v_contrato.categoria, 'categoria', p_categoria, 'operacion_id', v_operacion_id
  );
end;
$nucleo$;

-- ── 2 · Puerta (solo Gerencia) ───────────────────────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER, justificado: escribe public.contratos y public.audit_log y lee crm.operaciones_cartera y
-- crm.periodos_cerrados, que Gerencia no puede escribir ni leer completos con sus permisos. La autoridad se comprueba
-- aquí dentro (rol CRM vigente = gerencia y membresía sin revocar), con search_path vacío y nombres calificados.
create function crm.corregir_categoria_contrato_fn(p_contrato_id uuid, p_categoria text, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $puerta$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_categoria text := nullif(btrim(p_categoria), '');
  v_motivo text := nullif(btrim(p_motivo), '');
begin
  if v_uid is null or v_rol is distinct from 'gerencia'
     or (select private.membresia_crm_revocada()) is not false then
    raise exception 'Solo Gerencia puede corregir la categoría de un contrato' using errcode = '42501';
  end if;
  if p_contrato_id is null then
    raise exception 'El contrato es obligatorio' using errcode = '22023';
  end if;
  if v_categoria is null or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'La categoría debe ser nuevo, renovacion o upgrade' using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300 then
    raise exception 'El motivo debe tener entre 5 y 300 caracteres' using errcode = '22023';
  end if;
  return private.fijar_categoria_contrato(p_contrato_id, v_categoria, v_motivo, 'puerta', v_uid);
end;
$puerta$;

-- ── 3 · Triggers ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- 3a · Al registrar la operación, el contrato toma su categoría. SECURITY DEFINER, justificado: escribe public.contratos
-- y public.audit_log venga de donde venga la operación (hoy solo postgres o funciones SECURITY DEFINER pueden insertarla).
create function private.trg_operacion_cartera_fija_categoria()
returns trigger
language plpgsql
security definer
set search_path = ''
as $sincronia$
declare
  v_categoria text;
  v_fecha date;
  v_periodo date;
begin
  if new.tipo is null or new.tipo not in ('renovacion', 'upgrade') then
    return null;
  end if;
  -- Solo READ COMMITTED, antes de cualquier candado: con una foto vieja (REPEATABLE READ o SERIALIZABLE) la categoría que
  -- se lee después del candado no sería la de AHORA.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Una renovación o un upgrade solo se registran en una transacción READ COMMITTED'
      using errcode = '25001',
            hint = 'Con una foto vieja la categoría del contrato no sería la de ahora. La API ya trabaja en READ COMMITTED.';
  end if;
  -- SIEMPRE se bloquea el contrato antes de leer su categoría (también cuando ya coincide): un UPDATE de la categoría que
  -- esté en curso en otra transacción espera a esta, o esta espera a él y lee lo que dejó. Mismo orden que el núcleo y el
  -- sello: el mes (día comercial leído sin bloquear) y después la fila.
  select c.fecha_cierre_comercial into v_fecha from public.contratos c where c.id = new.contrato_nuevo_id;
  v_periodo := date_trunc('month', v_fecha)::date;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );
  select c.categoria, c.fecha_cierre_comercial into v_categoria, v_fecha
    from public.contratos c where c.id = new.contrato_nuevo_id for update;
  if date_trunc('month', v_fecha)::date is distinct from v_periodo then
    raise exception 'El día comercial del contrato cambió mientras se registraba la operación; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  -- Camino del alta (public.crear_contrato): la categoría ya es la de la operación; no se toca nada más (tampoco la
  -- declaración de origen del upgrade, que el observador de rentabilidad lee al confirmar).
  if v_categoria is not distinct from new.tipo then
    return null;
  end if;
  perform private.fijar_categoria_contrato(
    new.contrato_nuevo_id,
    new.tipo,
    'La operación de cartera decide la categoría: se registró una operación ' || new.tipo
      || ' sobre un contrato que estaba como ' || coalesce(v_categoria, 'sin categoría') || '.',
    'operacion_de_cartera',
    (select auth.uid())
  );
  return null;
end;
$sincronia$;

-- 3b · Ninguna vía deja la categoría distinta de la operación. AFTER y por fila: mira la fila FINAL, después de que todos
-- los BEFORE hayan hecho lo suyo. SECURITY DEFINER, justificado: tiene que VER la operación aunque quien edita el contrato
-- no pueda leerla por RLS (si no la viera, la regla se saltaría en silencio). Devuelve NEW (en un AFTER no se usa).
create function private.trg_contrato_categoria_por_operacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $guarda$
declare
  v_tipo text;
begin
  if new.categoria is not distinct from old.categoria then
    return new;
  end if;
  -- Solo READ COMMITTED, ANTES de buscar la operación: con una foto vieja (REPEATABLE READ o SERIALIZABLE) esta consulta
  -- no vería una operación confirmada después de la foto, y la categoría quedaría distinta de la operación sin aviso.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La categoría de un contrato solo se cambia en una transacción READ COMMITTED'
      using errcode = '25001',
            hint = 'La API ya trabaja en READ COMMITTED. En SQL: BEGIN ISOLATION LEVEL READ COMMITTED.';
  end if;
  select o.tipo into v_tipo from crm.operaciones_cartera o where o.contrato_nuevo_id = new.id;
  if found and new.categoria is distinct from v_tipo then
    raise exception 'La categoría la decide la operación de cartera'
      using errcode = '23514',
            detail = format('El contrato tiene una operación de cartera de tipo %s; su categoría no puede quedar como %s.',
                            v_tipo, coalesce(new.categoria, 'vacía')),
            hint = 'La categoría de un contrato con operación de cartera es la de su operación.';
  end if;
  return new;
end;
$guarda$;

create trigger trg_operaciones_cartera_10_fija_categoria
  after insert or update of tipo, contrato_nuevo_id on crm.operaciones_cartera
  for each row execute function private.trg_operacion_cartera_fija_categoria();

create trigger trg_contratos_01_categoria_por_operacion
  after update on public.contratos
  for each row
  when (old.categoria is distinct from new.categoria)
  execute function private.trg_contrato_categoria_por_operacion();

-- ── 4 · Permisos ──────────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function private.fijar_categoria_contrato(uuid, text, text, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.trg_operacion_cartera_fija_categoria() from public, anon, authenticated, service_role;
revoke all on function private.trg_contrato_categoria_por_operacion() from public, anon, authenticated, service_role;
revoke all on function crm.corregir_categoria_contrato_fn(uuid, text, text) from public, anon, service_role;
grant execute on function crm.corregir_categoria_contrato_fn(uuid, text, text) to authenticated;

-- ── 5 · Comentarios ───────────────────────────────────────────────────────────────────────────────────────────────────
comment on function private.fijar_categoria_contrato(uuid, text, text, text, uuid) is
  'Núcleo único para poner la categoría de un contrato (20261009120000). Bloquea la fila; sin cambio no escribe; en eliminación 55000; mes sellado P0409; con operación de cartera la categoría es la de la operación y sin operación solo nuevo (23514); no declara origen; abre la congelación del PDF solo para ese contrato y la cierra también si falla; sin revisión de PDF; fila de motivo en public.audit_log (tabla contratos.categoria). Lo llaman crm.corregir_categoria_contrato_fn y private.trg_operacion_cartera_fija_categoria.';
comment on function crm.corregir_categoria_contrato_fn(uuid, text, text) is
  'Corrige la categoría de un contrato antes del sello mensual. Solo Gerencia vigente con membresía CRM sin revocar; motivo de 5 a 300 caracteres. La operación de cartera decide: con operación, la categoría tiene que ser la suya; sin operación, solo nuevo. Devuelve {cambio:false} si ya la tiene. Decisión de Miguel 08/10/2026.';
comment on function private.trg_operacion_cartera_fija_categoria() is
  'Al registrar una renovación o un upgrade, el contrato nuevo toma la categoría de la operación en la misma transacción (por private.fijar_categoria_contrato: mes sellado P0409, fila de motivo, sin revisión de PDF). Solo en READ COMMITTED (25001). Bloquea siempre el contrato (mes y fila) antes de leer su categoría. En el alta normal ya coincide y no hace nada.';
comment on function private.trg_contrato_categoria_por_operacion() is
  'Una categoría solo cambia en READ COMMITTED (25001). Si el contrato tiene operación de cartera, su categoría no puede quedar distinta de la operación (23514 «La categoría la decide la operación de cartera»). Sin operación no restringe (contratos antiguos).';
comment on trigger trg_operaciones_cartera_10_fija_categoria on crm.operaciones_cartera is
  'La operación decide: sincroniza la categoría del contrato nuevo con la operación (20261009120000).';
comment on trigger trg_contratos_01_categoria_por_operacion on public.contratos is
  'Toda vía: un contrato con operación de cartera conserva la categoría de su operación (20261009120000).';

-- ── 6 · Postflight ────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  r record;
  v_contrato uuid;
  v_tipo text;
  v_estado text;
  v_mensaje text;
  v_attnums_operacion int2[];
begin
  -- Dueño, search_path vacío, SECURITY como se declara y ACL exacta.
  for r in select * from (values
    ('private.fijar_categoria_contrato(uuid,text,text,text,uuid)', false, '{postgres=X/postgres}'),
    ('private.trg_operacion_cartera_fija_categoria()', true, '{postgres=X/postgres}'),
    ('private.trg_contrato_categoria_por_operacion()', true, '{postgres=X/postgres}'),
    ('crm.corregir_categoria_contrato_fn(uuid,text,text)', true, '{postgres=X/postgres,authenticated=X/postgres}')
  ) as v(firma, definer, acl) loop
    if not exists (select 1 from pg_catalog.pg_proc p
                    where p.oid = to_regprocedure(r.firma)
                      and p.proowner = 'postgres'::regrole
                      and p.prosecdef = r.definer
                      and p.proconfig = array['search_path=""']
                      and p.proacl::text = r.acl) then
      raise exception 'CATEGORIA postflight: % no quedó como se declara (dueño, seguridad, search_path o permisos)', r.firma;
    end if;
    if pg_catalog.has_function_privilege('anon', to_regprocedure(r.firma), 'execute') then
      raise exception 'CATEGORIA postflight: anon puede ejecutar %', r.firma;
    end if;
  end loop;
  if pg_catalog.has_function_privilege('authenticated', 'private.fijar_categoria_contrato(uuid,text,text,text,uuid)'::regprocedure, 'execute') then
    raise exception 'CATEGORIA postflight: authenticated puede ejecutar el núcleo';
  end if;

  -- Triggers presentes, habilitados y con su forma (por fila; AFTER UPDATE con WHEN; AFTER INSERT OR UPDATE OF ...).
  select array_agg(a.attnum order by a.attnum) into v_attnums_operacion from pg_catalog.pg_attribute a
   where a.attrelid = 'crm.operaciones_cartera'::regclass and a.attname in ('tipo', 'contrato_nuevo_id');
  if not exists (select 1 from pg_catalog.pg_trigger t
                  where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_01_categoria_por_operacion'
                    and t.tgenabled = 'O' and t.tgtype = 17   -- ROW(1) + AFTER(0) + UPDATE(16)
                    and t.tgattr::text = '' and t.tgqual is not null
                    and pg_catalog.pg_get_triggerdef(t.oid) like '%WHEN ((old.categoria IS DISTINCT FROM new.categoria))%'
                    and t.tgfoid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure) then
    raise exception 'CATEGORIA postflight: el trigger de public.contratos no quedó como se declara';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger t
                  where t.tgrelid = 'crm.operaciones_cartera'::regclass and t.tgname = 'trg_operaciones_cartera_10_fija_categoria'
                    and t.tgenabled = 'O' and t.tgtype = 21   -- ROW(1) + AFTER(0) + INSERT(4) + UPDATE(16)
                    and (select array_agg(x order by x) from unnest(t.tgattr::int2[]) x) = v_attnums_operacion
                    and t.tgqual is null
                    and t.tgfoid = 'private.trg_operacion_cartera_fija_categoria()'::regprocedure) then
    raise exception 'CATEGORIA postflight: el trigger de crm.operaciones_cartera no quedó como se declara';
  end if;

  -- Las piezas previas no cambiaron y no se escribió ningún dato.
  if (select count(*) from pg_temp.categoria_piezas_antes) <> 11
     or exists (select 1 from pg_temp.categoria_piezas_antes a
                  left join pg_catalog.pg_proc p on p.oid = a.funcion
                 where p.oid is null or md5(p.prosrc) is distinct from a.huella or p.proacl::text is distinct from a.acl) then
    raise exception 'CATEGORIA postflight: una pieza previa cambió durante la migración';
  end if;
  if (select count(*) from public.audit_log a where a.tabla = 'contratos.categoria')
       <> (select b.filas from pg_temp.categoria_bitacora_antes b) then
    raise exception 'CATEGORIA postflight: la migración escribió en la bitácora de categoría';
  end if;

  -- Prueba en negativo 1: la puerta sin sesión → 42501 (no lee ni escribe nada).
  begin
    perform crm.corregir_categoria_contrato_fn(gen_random_uuid(), 'nuevo', 'prueba del postflight');
    v_estado := 'sin_error';
  exception when others then
    v_estado := sqlstate;
  end;
  if v_estado is distinct from '42501' then
    raise exception 'CATEGORIA postflight: la puerta sin sesión respondió % (se esperaba 42501)', v_estado;
  end if;

  -- Prueba en negativo 2: un contrato con operación no puede quedar con otra categoría (toda vía) → 23514 con su texto.
  -- Se intenta dentro de un bloque que se deshace SIEMPRE, con la congelación abierta solo para ese contrato y solo en el
  -- bloque. Un contrato de producto LEGACY (como los 12): con uno de catálogo, el trigger de producto rechazaría antes; y
  -- que no se esté eliminando (otra regla rechazaría el UPDATE por un motivo ajeno a la guarda).
  select o.contrato_nuevo_id, o.tipo into v_contrato, v_tipo
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
    join crm.producto_condiciones pc on pc.id = c.producto_condicion_id and pc.es_legacy
   where not private.contrato_en_eliminacion(c.id)
   order by o.creado_en desc, o.id limit 1;
  if v_contrato is not null then
    begin
      perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_contrato::text, true);
      update public.contratos c
         set categoria = case when v_tipo = 'upgrade' then 'renovacion' else 'upgrade' end
       where c.id = v_contrato;
      raise exception using errcode = 'P0001', message = 'postflight: el UPDATE pasó y se deshace';
    exception when others then
      v_estado := sqlstate;
      v_mensaje := sqlerrm;
    end;
    perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', '', true);
    if v_estado is distinct from '23514' or v_mensaje is distinct from 'La categoría la decide la operación de cartera' then
      raise exception 'CATEGORIA postflight: cambiar la categoría de un contrato con operación respondió % «%» (se esperaba 23514 «La categoría la decide la operación de cartera»)', v_estado, v_mensaje;
    end if;
  else
    raise notice 'CATEGORIA postflight: no hay contratos legacy con operación de cartera; la prueba en negativo 2 no se pudo correr aquí';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));

-- reversa-datos.sql — Devuelve a 'nuevo' los 12 contratos de septiembre que 2-REAL.sql pasó a 'upgrade'. ESCRIBE.
--
-- CUÁNDO: solo si Miguel decide deshacer la corrección, con SEPTIEMBRE ABIERTO (lo sellado no se reescribe) y DESPUÉS de
-- reversa.sql. El orden es obligatorio: mientras exista la prevención (trg_contratos_01_categoria_por_operacion), ninguna
-- vía —tampoco la puerta— puede dejar en 'nuevo' un contrato cuya operación de cartera es 'upgrade'. Por eso esta reversa
-- no usa la puerta: hace lo mismo que el núcleo (el mes y las filas tomados, congelación del PDF abierta SOLO
-- para ese contrato y cerrada después, UPDATE solo de la categoría, fila de motivo) pero hacia atrás.
-- reversa.sql y este archivo son DOS transacciones: si este falla, el esquema YA está revertido (ver LEEME.md, «Reversa»).
--
-- SE NIEGA si la prevención sigue puesta, si septiembre está sellado, si algún contrato se está eliminando o si alguno no
-- está exactamente como lo dejó la puerta (en 'upgrade' y con la corrección del 08/10 como ÚLTIMA fila de categoría).
-- TODO O NADA, con postflight en la misma transacción (los 12 en 'nuevo', el capital de septiembre por moneda igual, lo que
-- vuelve a «nuevo» = los 12, PDF sin trabajos nuevos, observador sin P0410 y EXACTAMENTE una fila nueva del libro por
-- contrato firmada por Gerencia). La bitácora no se borra: queda una fila más por contrato que dice «reversa», firmada por
-- la misma Gerencia que eligen los guiones.
-- OJO: solo con la política de rentabilidad en OBSERVACIÓN. Volver a 'nuevo' recalcula la tasa base (15): con la política en
-- enforcement, los contratos con tasa por encima de la base (001362 a 32,4, 001401 a 24…) darían P0410 y la reversa
-- abortaría entera (sin escribir nada).
-- `db query` manda el archivo ENTERO como UN solo mensaje: nada antes del BEGIN ni candados de sesión; todo vive y muere
-- con la transacción, que se abre EXPLÍCITAMENTE en READ COMMITTED (no hereda el aislamiento por defecto de la sesión).
-- Candados SIN ESPERAR (bloque $candados$, idéntico en 1-ENSAYO, 2-REAL y reversa-datos): primero SHARE NOWAIT sobre las
-- tablas que se miden (nadie más escribe en ellas mientras dura: el «antes» y el «después» son del mismo mundo), después
-- el candado del mes de septiembre (el del sello mensual) con pg_try_advisory_xact_lock y por último las 12 filas FOR
-- UPDATE NOWAIT. Si algo ya está tomado, aborta AL INSTANTE con «Hay actividad en curso: vuelve a correr el guion en unos
-- minutos» y no escribe nada. Así el guion nunca espera a otra transacción y no puede cerrar un círculo con un alta a
-- medias (que ya tiene public.contratos y el mes) ni con el sello mensual (que escribe crm.conversion_acreditaciones,
-- una de estas tablas). Si falla a mitad, la conexión se cierra y Postgres suelta todo.
-- El resultado viaja como la ÚLTIMA fila (después del COMMIT).
begin isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
do $candados$
begin
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'ABORTA: este guion corre solo en READ COMMITTED (la transacción está en %)',
      pg_catalog.current_setting('transaction_isolation') using errcode = '25001';
  end if;
  -- 1) Las tablas que se miden, SHARE y sin esperar.
  begin
    lock table public.contratos, crm.operaciones_cartera, crm.cierres_externos, crm.cierres_avance_anulados,
               crm.conversion_acreditaciones, crm.lead_asignaciones, crm.leads, crm.inversion_solicitudes, crm.inversiones,
               crm.inversiones_eliminadas, crm.origenes_capital_confirmados, crm.ledger_rentabilidad, crm.equipo,
               crm.meta_periodos, crm.metas_vendedor, crm.conversion_pesos, crm.conversion_politica, crm.politica_rentabilidad,
               crm.rentabilidad_hitos, public.perfiles, private.contrato_pdf_jobs, private.contrato_pdfs
      in share mode nowait;
  exception when lock_not_available then
    raise exception 'Hay actividad en curso: vuelve a correr el guion en unos minutos'
      using errcode = '55P03',
            detail = 'Otra transacción está escribiendo en una de las tablas que mide el guion (un alta, un sello mensual, una corrección…). No se escribió nada.';
  end;
  -- 2) El mes de septiembre (mismas llaves que el sello mensual y el núcleo), sin esperar.
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
                                              (date '2026-09-01' - date '2000-01-01')::integer) then
    raise exception 'Hay actividad en curso: vuelve a correr el guion en unos minutos'
      using errcode = '55P03',
            detail = 'Otra transacción tiene tomado el mes de septiembre (el sello mensual, un alta o una corrección de ese mes). No se escribió nada.';
  end if;
  -- 3) Las 12 filas, sin esperar. Después de esto el guion ya no espera a nadie: la puerta y el núcleo vuelven a pedir
  --    el mes y cada fila, pero ya son suyos.
  begin
    perform 1 from public.contratos c
     where c.numero_contrato in ('2026-01-001362', '2026-01-001369', '2026-01-001401', '2026-01-001408',
                                 '2026-01-001400', '2026-01-001439', '2026-01-001440', '2026-01-001441',
                                 '2026-01-001424', '2026-01-001425', '2026-01-001445', '2026-01-001447')
       for update nowait;
  exception when lock_not_available then
    raise exception 'Hay actividad en curso: vuelve a correr el guion en unos minutos'
      using errcode = '55P03',
            detail = 'Otra transacción tiene tomado uno de los 12 contratos. No se escribió nada.';
  end;
end
$candados$;

do $reversa$
declare
  -- Firma: la misma cuenta de Gerencia que el ensayo y el real (ADMINISTRADOR AVANCE CORP, elegida por Miguel el 08/10/2026).
  c_firma_prefijo constant text := 'bf1c562e';
  c_numeros constant text[] := array[
    '2026-01-001362', '2026-01-001369', '2026-01-001401', '2026-01-001408',
    '2026-01-001400', '2026-01-001439', '2026-01-001440', '2026-01-001441',
    '2026-01-001424', '2026-01-001425', '2026-01-001445', '2026-01-001447'];
  c_motivo_correccion constant text := 'Upgrade registrado como nuevo: la operación de cartera manda (decisión de Miguel 08/10/2026, auditoría de Facturación)';
  c_motivo_reversa constant text := 'Reversa de la corrección de categoría del 08/10/2026 (20261009120000): vuelve a nuevo por decisión de Miguel';
  c_periodo constant date := date '2026-09-01';
  c_ini constant timestamptz := timestamp '2026-09-01 00:00:00' at time zone 'America/Lima';
  c_fin constant timestamptz := timestamp '2026-10-01 00:00:00' at time zone 'America/Lima';
  v_ids uuid[] := '{}';
  v_num text;
  v_id uuid;
  v_n int;
  v_capital_antes jsonb;
  v_capital_despues jsonb;
  v_movido jsonb;
  v_pdf_antes jsonb;
  v_pdf_despues jsonb;
  v_libro_antes bigint;
  v_actor uuid;
begin
  if exists (select 1 from pg_catalog.pg_trigger t
              where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_01_categoria_por_operacion') then
    raise exception 'ABORTA: la prevención sigue puesta; correr antes reversa.sql';
  end if;
  -- El mes y las 12 filas ya son de esta transacción (bloque $candados$): lo que se lee aquí es lo de AHORA.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = c_periodo) then
    raise exception 'ABORTA: septiembre 2026 ya está sellado; lo sellado no se reescribe';
  end if;

  -- Cada contrato, comprobado (su fila ya está bloqueada desde el bloque $candados$).
  foreach v_num in array c_numeros loop
    select c.id into v_id
      from public.contratos c
     where c.numero_contrato = v_num and c.categoria = 'upgrade'
       and c.fecha_cierre_comercial >= c_periodo and c.fecha_cierre_comercial < date '2026-10-01'
       and (select a.data_despues ->> 'motivo' = c_motivo_correccion
                   and a.data_antes ->> 'categoria' = 'nuevo' and a.data_despues ->> 'categoria' = 'upgrade'
              from public.audit_log a
             where a.tabla = 'contratos.categoria' and a.fila_id = c.id::text
             order by a.ts desc, a.id desc limit 1)
     for update;
    if v_id is null then
      raise exception 'ABORTA: el contrato % no está como lo dejó la corrección del 08/10 (upgrade con su fila de motivo)', v_num;
    end if;
    if private.contrato_en_eliminacion(v_id) then
      raise exception 'ABORTA: el contrato % está en proceso de eliminación', v_num;
    end if;
    v_ids := v_ids || v_id;
  end loop;

  -- La misma Gerencia que el ensayo y el real (c_firma_prefijo, una sola), para firmar la bitácora y el libro.
  select count(*) into v_n
    from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  select p.id into v_actor
    from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  if v_actor is null or v_n <> 1 then
    raise exception 'ABORTA: no se pudo elegir UNA identidad de gerencia para firmar la reversa';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_actor::text, true);

  select coalesce(jsonb_object_agg(t.moneda, jsonb_build_object('total', t.total, 'nuevo', t.nuevo, 'upgrade', t.up)), '{}')
    into v_capital_antes
    from (select e.moneda, sum(e.monto) as total,
                 coalesce(sum(e.monto) filter (where e.tipo = 'contrato_nuevo'), 0) as nuevo,
                 coalesce(sum(e.monto) filter (where e.tipo = 'contrato_upgrade'), 0) as up
            from private.capital_episodios(c_ini, c_fin, true, '{}'::uuid[]) e
           where e.medida = 'stock' group by e.moneda) t;
  select jsonb_object_agg(c.numero_contrato, jsonb_build_object(
           'trabajos', (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = c.id),
           'archivos', (select count(*) from private.contrato_pdfs p where p.contrato_id = c.id)))
    into v_pdf_antes from public.contratos c where c.id = any(v_ids);
  select count(*) into v_libro_antes from crm.ledger_rentabilidad l where l.contrato_id = any(v_ids);

  -- Sin contrato de origen declarado (como el núcleo).
  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', '', true);
  foreach v_id in array v_ids loop
    perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_id::text, true);
    update public.contratos c set categoria = 'nuevo' where c.id = v_id;
    perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', '', true);
    insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
    values ('contratos.categoria', 'UPDATE', v_id::text, v_actor,
            jsonb_build_object('categoria', 'upgrade'),
            jsonb_build_object('categoria', 'nuevo', 'motivo', c_motivo_reversa, 'via', 'reversa',
                               'operacion_id', (select o.id from crm.operaciones_cartera o where o.contrato_nuevo_id = v_id)));
  end loop;

  -- El observador de rentabilidad AHORA (y firmado por Gerencia): un P0410 aborta aquí.
  set constraints all immediate;
  set constraints all deferred;

  -- Postflight.
  select count(*) into v_n from public.contratos c where c.id = any(v_ids) and c.categoria = 'nuevo';
  if v_n <> 12 then
    raise exception 'ABORTA: solo % de 12 volvieron a nuevo', v_n;
  end if;
  select coalesce(jsonb_object_agg(t.moneda, jsonb_build_object('total', t.total, 'nuevo', t.nuevo, 'upgrade', t.up)), '{}')
    into v_capital_despues
    from (select e.moneda, sum(e.monto) as total,
                 coalesce(sum(e.monto) filter (where e.tipo = 'contrato_nuevo'), 0) as nuevo,
                 coalesce(sum(e.monto) filter (where e.tipo = 'contrato_upgrade'), 0) as up
            from private.capital_episodios(c_ini, c_fin, true, '{}'::uuid[]) e
           where e.medida = 'stock' group by e.moneda) t;
  select coalesce(jsonb_object_agg(t.moneda, t.capital), '{}') into v_movido
    from (select c.moneda, sum(c.capital) as capital from public.contratos c where c.id = any(v_ids) group by c.moneda) t;
  if exists (select 1 from jsonb_object_keys(v_capital_antes || v_capital_despues) k
              where (v_capital_antes -> k ->> 'total')::numeric is distinct from (v_capital_despues -> k ->> 'total')::numeric
                 or (v_capital_despues -> k ->> 'nuevo')::numeric - (v_capital_antes -> k ->> 'nuevo')::numeric
                      is distinct from coalesce((v_movido ->> k)::numeric, 0)
                 or (v_capital_antes -> k ->> 'upgrade')::numeric - (v_capital_despues -> k ->> 'upgrade')::numeric
                      is distinct from coalesce((v_movido ->> k)::numeric, 0)) then
    raise exception 'ABORTA: el capital de septiembre no cuadra (antes %, después %, los 12 %)', v_capital_antes, v_capital_despues, v_movido;
  end if;
  select jsonb_object_agg(c.numero_contrato, jsonb_build_object(
           'trabajos', (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = c.id),
           'archivos', (select count(*) from private.contrato_pdfs p where p.contrato_id = c.id)))
    into v_pdf_despues from public.contratos c where c.id = any(v_ids);
  if v_pdf_antes is distinct from v_pdf_despues then
    raise exception 'ABORTA: el PDF de algún contrato cambió';
  end if;
  -- Libro: EXACTAMENTE una fila nueva por contrato, 'nuevo' y firmada por Gerencia.
  if (select count(*) from crm.ledger_rentabilidad l where l.contrato_id = any(v_ids)) - v_libro_antes <> 12
     or (select count(*) from (select l.contrato_id from crm.ledger_rentabilidad l
                                where l.contrato_id = any(v_ids) and l.registrado_en >= now()
                                group by l.contrato_id
                               having count(*) = 1 and bool_and(l.actor_id = v_actor and l.categoria = 'nuevo')) x) <> 12 then
    raise exception 'ABORTA: el libro de rentabilidad no tiene exactamente una fila nueva por contrato, nuevo y firmada por Gerencia';
  end if;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  -- Resultado en un GUC de SESIÓN (false): sobrevive al COMMIT para la última fila; si la transacción aborta, desaparece.
  perform set_config('categoria.reversa', jsonb_build_object(
    'resultado', 'OK: 12 contratos de vuelta a nuevo', 'capital_antes', v_capital_antes,
    'capital_despues', v_capital_despues, 'movido', v_movido)::text, false);
end
$reversa$;

commit;
select current_setting('categoria.reversa', true)::jsonb as resultado;

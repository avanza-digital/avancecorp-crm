-- 2-REAL.sql — ESCRIBE EN PRODUCCIÓN. Solo después de un ENSAYO con veredicto «LISTO PARA 2-REAL» (1-ENSAYO.sql) y con el
-- OK de Miguel. Pasa los 12 contratos de septiembre de 'nuevo' a 'upgrade' por la ÚNICA puerta
-- (crm.corregir_categoria_contrato_fn: solo Gerencia, motivo, bitácora, mes abierto, respaldo de la operación de cartera),
-- con la identidad de Gerencia que el ensayo mostró.
--
-- TODO O NADA: si un solo contrato falla, o si el postflight (dentro de la MISMA transacción) no cuadra, el bloque aborta
-- y no queda nada escrito. Postflight: los 12 en 'upgrade'; capital de septiembre por moneda IGUAL que antes; lo que sale
-- de «nuevo» entra en «upgrade» por moneda (= los 12: S/ 2.092.254 y US$ 54.971) y por analista (nadie cambia de dueño);
-- conversión de septiembre igual, total y por analista (numerador y divisor); PDF sin trabajos ni archivos nuevos;
-- observador de rentabilidad sin P0410 y EXACTAMENTE una fila nueva del libro por contrato, upgrade y firmada por
-- Gerencia; 12 filas de motivo; la medición de rentabilidad y de ranking sin errores. Informa además, sin abortar, lo que
-- se mueve en el Ranking por origen y en la tarjeta de rentabilidad (lo mismo que mostró el ensayo).
--
-- CÓMO LO CORRE MIGUEL (con `!`, desde CRM-Avance-Corp):
--   supabase db query --linked -f supabase/scripts/categoria-por-operacion/2-REAL.sql
-- `db query` manda el archivo ENTERO como UN solo mensaje: nada antes del BEGIN ni candados de sesión; todo vive y muere
-- con la transacción, que se abre EXPLÍCITAMENTE en READ COMMITTED (no hereda el aislamiento por defecto de la sesión).
-- Candados SIN ESPERAR (bloque $candados$, idéntico en 1-ENSAYO, 2-REAL y reversa-datos): primero SHARE NOWAIT sobre las
-- tablas que se miden (nadie más escribe en ellas mientras dura: el «antes» y el «después» son del mismo mundo), después
-- el candado del mes de septiembre (el del sello mensual) con pg_try_advisory_xact_lock y por último las 12 filas FOR
-- UPDATE NOWAIT. Si algo ya está tomado, aborta AL INSTANTE con «Hay actividad en curso: vuelve a correr el guion en unos
-- minutos» y no escribe nada. Así el guion nunca espera a otra transacción y no puede cerrar un círculo con un alta a
-- medias (que ya tiene public.contratos y el mes) ni con el sello mensual (que escribe crm.conversion_acreditaciones,
-- una de estas tablas). Si falla a mitad, la conexión se cierra y Postgres suelta todo.
-- El resultado viaja como la ÚLTIMA fila (después del COMMIT), que es la que muestra `db query`.
-- DESPUÉS: el oráculo de solo lectura oraculo-despues.sql. No sellar septiembre hasta verlo en PASS.
-- Reversa: reversa.sql (esquema) y luego reversa-datos.sql (los 12 vuelven a 'nuevo'; solo con septiembre abierto).
begin isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '180s';
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

-- Foto de todo lo que se compara (función temporal de esta transacción). Misma foto que el ensayo.
create function pg_temp.categoria_foto(p_ids uuid[], p_periodo_meta uuid) returns jsonb
language plpgsql as $foto$
declare
  c_periodo constant date := date '2026-09-01';
  c_ini constant timestamptz := timestamp '2026-09-01 00:00:00' at time zone 'America/Lima';
  c_fin constant timestamptz := timestamp '2026-10-01 00:00:00' at time zone 'America/Lima';
  v jsonb := '{}'::jsonb;
  v_tmp jsonb;
begin
  select coalesce(jsonb_object_agg(t.moneda, jsonb_build_object('total', t.total, 'nuevo', t.nuevo, 'upgrade', t.up)), '{}')
    into v_tmp
    from (select e.moneda, sum(e.monto) as total,
                 coalesce(sum(e.monto) filter (where e.tipo = 'contrato_nuevo'), 0) as nuevo,
                 coalesce(sum(e.monto) filter (where e.tipo = 'contrato_upgrade'), 0) as up
            from private.capital_episodios(c_ini, c_fin, true, '{}'::uuid[]) e
           where e.medida = 'stock' group by e.moneda) t;
  v := v || jsonb_build_object('capital', v_tmp);
  select coalesce(jsonb_object_agg(coalesce(r.vendedor_id::text, 'sin_analista') || '|' || r.categoria || '|' || r.moneda,
                                   jsonb_build_object('capital', r.capital_real, 'contratos', r.contratos_real)), '{}')
    into v_tmp
    from private.produccion_mes_por_vendedor(c_ini, c_fin, p_periodo_meta) r;
  v := v || jsonb_build_object('analistas', v_tmp);
  select jsonb_build_object('numerador', round(coalesce(sum(e.aporte_numerador), 0), 4), 'divisor', coalesce(sum(e.aporte_divisor), 0))
    into v_tmp
    from private.conversion_episodios(c_ini, c_fin, c_periodo, true, null, private.peso_referido_conversion(c_periodo)) e;
  v := v || jsonb_build_object('conversion', v_tmp || jsonb_build_object('por_analista', (
    select coalesce(jsonb_object_agg(x.analista, jsonb_build_object('numerador', x.num, 'divisor', x.div)), '{}')
      from (select coalesce(e.analista_id::text, 'sin_analista') as analista,
                   round(coalesce(sum(e.aporte_numerador), 0), 4) as num, coalesce(sum(e.aporte_divisor), 0) as div
              from private.conversion_episodios(c_ini, c_fin, c_periodo, true, null, private.peso_referido_conversion(c_periodo)) e
             group by 1) x)));
  select jsonb_object_agg(c.numero_contrato, jsonb_build_object(
           'trabajos', (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = c.id),
           'archivos', (select count(*) from private.contrato_pdfs p where p.contrato_id = c.id),
           'ultimo', (select j.estado || '/' || j.revision from private.contrato_pdf_jobs j where j.contrato_id = c.id order by j.revision desc limit 1)))
    into v_tmp from public.contratos c where c.id = any(p_ids);
  v := v || jsonb_build_object('pdf', v_tmp,
    'libro', (select count(*) from crm.ledger_rentabilidad l where l.contrato_id = any(p_ids)));
  begin
    select coalesce(jsonb_object_agg(t.origen || '|' || t.moneda, t.capital), '{}') into v_tmp
      from (select r.origen, r.moneda, sum(r.capital) as capital
              from private.ranking_capital_origen_filas(c_ini, c_fin, p_periodo_meta) r group by 1, 2) t;
    v := v || jsonb_build_object('ranking_origen', v_tmp);
  exception when others then
    v := v || jsonb_build_object('ranking_origen', jsonb_build_object('error', sqlstate || ': ' || sqlerrm));
  end;
  begin
    v := v || jsonb_build_object('rentabilidad', (crm.observacion_rentabilidad_fn()) -> 'totales');
  exception when others then
    v := v || jsonb_build_object('rentabilidad', jsonb_build_object('error', sqlstate || ': ' || sqlerrm));
  end;
  return v;
end
$foto$;

do $real$
declare
  -- Firma: la cuenta de Gerencia que eligió Miguel (08/10/2026): ADMINISTRADOR AVANCE CORP. La MISMA que el ensayo.
  c_firma_prefijo constant text := 'bf1c562e';
  c_numeros constant text[] := array[
    '2026-01-001362', '2026-01-001369', '2026-01-001401', '2026-01-001408',
    '2026-01-001400', '2026-01-001439', '2026-01-001440', '2026-01-001441',
    '2026-01-001424', '2026-01-001425', '2026-01-001445', '2026-01-001447'];
  c_motivo constant text := 'Upgrade registrado como nuevo: la operación de cartera manda (decisión de Miguel 08/10/2026, auditoría de Facturación)';
  -- Lo que mueven los 12 (medición de producción del 08/10 19:11, R0 movibles_por_moneda).
  c_movido_esperado constant jsonb := '{"PEN": 2092254, "USD": 54971}';
  c_periodo constant date := date '2026-09-01';
  v_ids uuid[] := '{}';
  v_num text;
  v_id uuid;
  v_n int;
  v_actor uuid;
  v_actor_nombre text;
  v_periodo_meta uuid;
  v_res jsonb;
  a jsonb;   -- foto antes
  d jsonb;   -- foto después
  v_movido jsonb;
  v_ranking jsonb;
begin
  if to_regprocedure('crm.corregir_categoria_contrato_fn(uuid,text,text)') is null then
    raise exception 'ABORTA: falta la migración 20261009120000 (crm.corregir_categoria_contrato_fn)';
  end if;
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = c_periodo) then
    raise exception 'ABORTA: septiembre 2026 ya está sellado; lo sellado no se reescribe';
  end if;

  -- 1. Los 12 siguen siendo EXACTAMENTE los medidos: 'nuevo', con su operación 'upgrade', día comercial de septiembre, no demo.
  foreach v_num in array c_numeros loop
    select c.id into v_id
      from public.contratos c
      join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id and o.tipo = 'upgrade'
     where c.numero_contrato = v_num and c.categoria = 'nuevo' and not c.es_demo
       and c.fecha_cierre_comercial >= c_periodo and c.fecha_cierre_comercial < date '2026-10-01';
    if v_id is null then
      raise exception 'ABORTA: el contrato % no existe, ya no está en nuevo, no tiene su operación upgrade o no es de septiembre', v_num;
    end if;
    v_ids := v_ids || v_id;
  end loop;

  -- 2. La identidad: la misma cuenta de Gerencia que el ensayo (c_firma_prefijo); tiene que ser UNA.
  select count(*) into v_n
    from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  if v_n <> 1 then
    raise exception 'ABORTA: la cuenta de Gerencia elegida (%) no es UN perfil con rol gerencia vigente (hay %)', c_firma_prefijo, v_n;
  end if;
  select p.id, p.nombre_completo into v_actor, v_actor_nombre
    from public.perfiles p
   where left(p.id::text, length(c_firma_prefijo)) = c_firma_prefijo and private.rol_crm(p.id) = 'gerencia';
  perform set_config('request.jwt.claims', json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_actor::text, true);

  -- 3. Foto ANTES.
  select mp.id into v_periodo_meta from crm.meta_periodos mp where mp.periodo = c_periodo order by mp.revision desc limit 1;
  a := pg_temp.categoria_foto(v_ids, v_periodo_meta);
  if (a -> 'rentabilidad') ? 'error' or (a -> 'ranking_origen') ? 'error' then
    raise exception 'ABORTA: la medición de rentabilidad o de ranking falló (rentabilidad %, ranking %)', a -> 'rentabilidad', a -> 'ranking_origen';
  end if;

  -- 4. La puerta como Gerencia, los 12. Cualquier error aborta TODO.
  execute 'set local role authenticated';
  for i in 1 .. array_length(v_ids, 1) loop
    v_res := crm.corregir_categoria_contrato_fn(v_ids[i], 'upgrade', c_motivo);
    if not coalesce((v_res ->> 'cambio')::boolean, false) then
      raise exception 'ABORTA: la puerta no cambió el contrato % (%)', c_numeros[i], v_res;
    end if;
  end loop;
  -- 5. El observador de rentabilidad AHORA (no al confirmar) y todavía como Gerencia (firma las filas del libro): un P0410
  --    aborta aquí, antes del postflight.
  set constraints all immediate;
  set constraints all deferred;
  execute 'reset role';

  -- 6. Postflight en la MISMA transacción.
  select count(*) into v_n
    from public.contratos c join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
   where c.id = any(v_ids) and c.categoria = 'upgrade' and o.tipo = 'upgrade';
  if v_n <> 12 then
    raise exception 'ABORTA: solo % de 12 quedaron en upgrade', v_n;
  end if;
  d := pg_temp.categoria_foto(v_ids, v_periodo_meta);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  if (d -> 'rentabilidad') ? 'error' or (d -> 'ranking_origen') ? 'error' then
    raise exception 'ABORTA: la medición de rentabilidad o de ranking falló después (rentabilidad %, ranking %)', d -> 'rentabilidad', d -> 'ranking_origen';
  end if;
  select coalesce(jsonb_object_agg(t.moneda, t.capital), '{}') into v_movido
    from (select c.moneda, sum(c.capital) as capital from public.contratos c where c.id = any(v_ids) group by c.moneda) t;
  if exists (select 1 from jsonb_object_keys((a -> 'capital') || (d -> 'capital')) k
              where (a -> 'capital' -> k ->> 'total')::numeric is distinct from (d -> 'capital' -> k ->> 'total')::numeric) then
    raise exception 'ABORTA: el capital de septiembre por moneda cambió (antes %, después %)', a -> 'capital', d -> 'capital';
  end if;
  if exists (select 1 from jsonb_object_keys((a -> 'capital') || (d -> 'capital')) k
              where (a -> 'capital' -> k ->> 'nuevo')::numeric - (d -> 'capital' -> k ->> 'nuevo')::numeric
                      is distinct from coalesce((v_movido ->> k)::numeric, 0)
                 or (d -> 'capital' -> k ->> 'upgrade')::numeric - (a -> 'capital' -> k ->> 'upgrade')::numeric
                      is distinct from coalesce((v_movido ->> k)::numeric, 0)) then
    raise exception 'ABORTA: lo que sale de nuevo no es lo que entra en upgrade (antes %, después %, los 12 %)',
      a -> 'capital', d -> 'capital', v_movido;
  end if;
  if (select bool_or((v_movido ->> k)::numeric is distinct from (c_movido_esperado ->> k)::numeric)
        from jsonb_object_keys(v_movido || c_movido_esperado) k) then
    raise exception 'ABORTA: los 12 no suman lo medido el 08/10 (hoy %, medido %)', v_movido, c_movido_esperado;
  end if;
  if exists (select 1
               from (select distinct split_part(k, '|', 1) as an, split_part(k, '|', 3) as m
                       from jsonb_object_keys((a -> 'analistas') || (d -> 'analistas')) k) x
              where coalesce((d -> 'analistas' -> (x.an || '|nuevo|' || x.m) ->> 'capital')::numeric, 0)
                    - coalesce((a -> 'analistas' -> (x.an || '|nuevo|' || x.m) ->> 'capital')::numeric, 0)
                    + coalesce((d -> 'analistas' -> (x.an || '|upgrade|' || x.m) ->> 'capital')::numeric, 0)
                    - coalesce((a -> 'analistas' -> (x.an || '|upgrade|' || x.m) ->> 'capital')::numeric, 0) <> 0) then
    raise exception 'ABORTA: algún analista cambió de capital total en una moneda (alguien cambió de dueño)';
  end if;
  -- Conversión: total y por analista, numerador Y divisor.
  if (a -> 'conversion') is distinct from (d -> 'conversion') then
    raise exception 'ABORTA: la conversión de septiembre cambió (antes %, después %)', a -> 'conversion', d -> 'conversion';
  end if;
  if (a -> 'pdf') is distinct from (d -> 'pdf') then
    raise exception 'ABORTA: el PDF de algún contrato cambió (antes %, después %)', a -> 'pdf', d -> 'pdf';
  end if;
  -- Libro de rentabilidad: EXACTAMENTE una fila nueva por contrato, upgrade y firmada por Gerencia.
  if (d ->> 'libro')::int - (a ->> 'libro')::int <> 12
     or (select count(*) from (select l.contrato_id from crm.ledger_rentabilidad l
                                where l.contrato_id = any(v_ids) and l.registrado_en >= now()
                                group by l.contrato_id
                               having count(*) = 1 and bool_and(l.actor_id = v_actor and l.categoria = 'upgrade')) x) <> 12 then
    raise exception 'ABORTA: el libro de rentabilidad no tiene exactamente una fila nueva por contrato, upgrade y firmada por Gerencia';
  end if;
  select count(*) into v_n from public.audit_log x
   where x.tabla = 'contratos.categoria' and x.ts >= now() and x.fila_id = any(select y::text from unnest(v_ids) y)
     and x.data_despues ->> 'motivo' = c_motivo and x.usuario_id = v_actor;
  if v_n <> 12 then
    raise exception 'ABORTA: hay % filas de motivo (se esperaban 12)', v_n;
  end if;
  select coalesce(jsonb_object_agg(k, jsonb_build_object('antes', a -> 'ranking_origen' -> k, 'despues', d -> 'ranking_origen' -> k)), '{}')
    into v_ranking
    from jsonb_object_keys((a -> 'ranking_origen') || (d -> 'ranking_origen')) k
   where (a -> 'ranking_origen' -> k) is distinct from (d -> 'ranking_origen' -> k);

  -- Resultado en un GUC de SESIÓN (false): sobrevive al COMMIT para la última fila; si la transacción aborta, desaparece.
  perform set_config('categoria.real', jsonb_build_object(
    'resultado', 'OK: 12 contratos de nuevo a upgrade',
    'identidad', v_actor_nombre, 'identidad_id8', left(v_actor::text, 8),
    'capital_antes', a -> 'capital', 'capital_despues', d -> 'capital', 'movido', v_movido,
    'conversion', (d -> 'conversion') - 'por_analista', 'filas_de_motivo', v_n,
    'libro_filas_nuevas', (d ->> 'libro')::int - (a ->> 'libro')::int,
    'ranking_origen_lo_que_cambia', v_ranking,
    'rentabilidad_antes', a -> 'rentabilidad', 'rentabilidad_despues', d -> 'rentabilidad')::text, false);
end
$real$;

commit;
select current_setting('categoria.real', true)::jsonb as resultado;

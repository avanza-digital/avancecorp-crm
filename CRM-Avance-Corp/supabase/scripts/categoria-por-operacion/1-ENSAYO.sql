-- 1-ENSAYO.sql — Categoría de los 12 contratos de septiembre: de 'nuevo' a 'upgrade' por la puerta auditada
-- (crm.corregir_categoria_contrato_fn). Decisión de Miguel (08/10/2026): «El tipo de un contrato lo decide la operación de
-- cartera». Requiere la migración 20261009120000 aplicada y registrada.
--
-- ESTE ARCHIVO NO ESCRIBE NADA: el bloque termina SIEMPRE en `raise exception`, así que Postgres deshace todo. El mensaje
-- del error ES el resultado del ensayo: qué identidad de Gerencia se usaría, qué pasa con cada contrato, qué se comprueba
-- (capital de septiembre por moneda y por analista, conversión por analista —numerador y divisor—, PDF, una fila del libro
-- de rentabilidad por contrato firmada por Gerencia, filas de motivo) y, para que Miguel lo vea ANTES de decidir, otras dos
-- cifras de Gerencia que también se mueven: el capital de septiembre por ORIGEN (Ranking: un contrato que no es 'nuevo'
-- cuenta como «cartera») y los totales de la tarjeta de rentabilidad (últimos 30 días). Si el veredicto es
-- «LISTO PARA 2-REAL», se corre 2-REAL.sql.
--
-- CÓMO LO CORRE MIGUEL (con `!`, desde CRM-Avance-Corp):
--   supabase db query --linked -f supabase/scripts/categoria-por-operacion/1-ENSAYO.sql
-- `db query` manda el archivo ENTERO como UN solo mensaje: nada antes del BEGIN ni candados de sesión; todo vive y muere
-- con la transacción, que se abre EXPLÍCITAMENTE en READ COMMITTED (no hereda el aislamiento por defecto de la sesión).
-- Candados SIN ESPERAR (bloque $candados$, idéntico en 1-ENSAYO, 2-REAL y reversa-datos): primero SHARE NOWAIT sobre las
-- tablas que se miden (nadie más escribe en ellas mientras dura: el «antes» y el «después» son del mismo mundo), después
-- el candado del mes de septiembre (el del sello mensual) con pg_try_advisory_xact_lock y por último las 12 filas FOR
-- UPDATE NOWAIT. Si algo ya está tomado, aborta AL INSTANTE con «Hay actividad en curso: vuelve a correr el guion en unos
-- minutos» y no escribe nada. Así el guion nunca espera a otra transacción y no puede cerrar un círculo con un alta a
-- medias (que ya tiene public.contratos y el mes) ni con el sello mensual (que escribe crm.conversion_acreditaciones,
-- una de estas tablas). Si falla a mitad, la conexión se cierra y Postgres suelta todo.
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

-- Foto de todo lo que se compara (función temporal de esta transacción). Misma foto que 2-REAL.sql.
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
  -- Conversión de septiembre: total y POR ANALISTA, numerador y divisor.
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
  -- Ranking por origen (informativo): capital de septiembre por origen y moneda.
  begin
    select coalesce(jsonb_object_agg(t.origen || '|' || t.moneda, t.capital), '{}') into v_tmp
      from (select r.origen, r.moneda, sum(r.capital) as capital
              from private.ranking_capital_origen_filas(c_ini, c_fin, p_periodo_meta) r group by 1, 2) t;
    v := v || jsonb_build_object('ranking_origen', v_tmp);
  exception when others then
    v := v || jsonb_build_object('ranking_origen', jsonb_build_object('error', sqlstate || ': ' || sqlerrm));
  end;
  -- Tarjeta de rentabilidad (informativo): totales de los últimos 30 días, leídos como Gerencia (claims de la sesión).
  begin
    v := v || jsonb_build_object('rentabilidad', (crm.observacion_rentabilidad_fn()) -> 'totales');
  exception when others then
    v := v || jsonb_build_object('rentabilidad', jsonb_build_object('error', sqlstate || ': ' || sqlerrm));
  end;
  return v;
end
$foto$;

do $ensayo$
declare
  c_perfil_pruebas constant uuid := 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2';
  c_numeros constant text[] := array[
    '2026-01-001362', '2026-01-001369', '2026-01-001401', '2026-01-001408',
    '2026-01-001400', '2026-01-001439', '2026-01-001440', '2026-01-001441',
    '2026-01-001424', '2026-01-001425', '2026-01-001445', '2026-01-001447'];
  c_motivo constant text := 'Upgrade registrado como nuevo: la operación de cartera manda (decisión de Miguel 08/10/2026, auditoría de Facturación)';
  c_periodo constant date := date '2026-09-01';
  v_ids uuid[] := '{}';
  v_num text;
  v_id uuid;
  v_actor uuid;
  v_actor_nombre text;
  v_candidatos jsonb;
  v_periodo_meta uuid;
  v_res jsonb;
  v_out jsonb := '[]'::jsonb;
  v_ok int := 0;
  v_cambiados uuid[] := '{}';
  v_p0410 text := 'sin P0410';
  a jsonb;   -- foto antes
  d jsonb;   -- foto después
  v_movido jsonb;
  v_ranking jsonb;
  v_chk jsonb;
begin
  -- 0. La puerta existe y septiembre sigue abierto (el mes ya es de esta transacción: bloque $candados$).
  if to_regprocedure('crm.corregir_categoria_contrato_fn(uuid,text,text)') is null then
    raise exception 'ABORTA: falta la migración 20261009120000 (crm.corregir_categoria_contrato_fn)';
  end if;
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = c_periodo) then
    raise exception 'ABORTA: septiembre 2026 ya está sellado; lo sellado no se reescribe';
  end if;

  -- 1. Los contratos, resueltos como dueño (sin RLS de por medio).
  foreach v_num in array c_numeros loop
    select c.id into v_id from public.contratos c where c.numero_contrato = v_num;
    if v_id is null then
      raise exception 'ABORTA: no existe el contrato %', v_num;
    end if;
    v_ids := v_ids || v_id;
  end loop;

  -- 2. La identidad: un perfil de GERENCIA vigente. Si hay varios, el de Miguel (mismo nombre que el de pruebas); tiene que
  --    ser UNO solo.
  select jsonb_agg(jsonb_build_object('id8', left(p.id::text, 8), 'nombre', p.nombre_completo) order by p.nombre_completo)
    into v_candidatos
    from public.perfiles p
   where p.id <> c_perfil_pruebas and private.rol_crm(p.id) = 'gerencia';
  select p.id, p.nombre_completo into v_actor, v_actor_nombre
    from public.perfiles p
   where p.id <> c_perfil_pruebas and private.rol_crm(p.id) = 'gerencia'
     and (jsonb_array_length(coalesce(v_candidatos, '[]')) = 1
          or p.nombre_completo = (select q.nombre_completo from public.perfiles q where q.id = c_perfil_pruebas));
  if v_actor is null then
    raise exception 'ABORTA: no se pudo elegir la identidad de gerencia. Candidatos: %', coalesce(v_candidatos, '[]');
  end if;
  if (select count(*) from public.perfiles p
       where p.id <> c_perfil_pruebas and private.rol_crm(p.id) = 'gerencia'
         and (jsonb_array_length(coalesce(v_candidatos, '[]')) = 1
              or p.nombre_completo = (select q.nombre_completo from public.perfiles q where q.id = c_perfil_pruebas))) <> 1 then
    raise exception 'ABORTA: la identidad de gerencia es ambigua (más de un perfil cumple la regla). Candidatos: %', v_candidatos;
  end if;

  -- La sesión de Gerencia queda puesta hasta el final (la tarjeta de rentabilidad se lee como ella y el libro la firma).
  perform set_config('request.jwt.claims', json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_actor::text, true);

  -- 3. Foto ANTES.
  select mp.id into v_periodo_meta from crm.meta_periodos mp where mp.periodo = c_periodo order by mp.revision desc limit 1;
  a := pg_temp.categoria_foto(v_ids, v_periodo_meta);

  -- 4. La puerta COMO esa Gerencia, contrato por contrato, sin parar en el primer fallo.
  execute 'set local role authenticated';
  for i in 1 .. array_length(v_ids, 1) loop
    begin
      v_res := crm.corregir_categoria_contrato_fn(v_ids[i], 'upgrade', c_motivo);
      v_out := v_out || jsonb_build_array(jsonb_build_object('numero', c_numeros[i], 'ok', true,
                 'cambio', v_res -> 'cambio', 'de', v_res -> 'categoria_anterior'));
      v_ok := v_ok + 1;
      if coalesce((v_res ->> 'cambio')::boolean, false) then
        v_cambiados := v_cambiados || v_ids[i];
      end if;
    exception when others then
      v_out := v_out || jsonb_build_array(jsonb_build_object('numero', c_numeros[i], 'ok', false,
                 'error', sqlerrm, 'sqlstate', sqlstate));
    end;
  end loop;

  -- 5. El observador de rentabilidad (diferido) AHORA, como al confirmar y aún como Gerencia: un P0410 se anota.
  begin
    set constraints all immediate;
    set constraints all deferred;
  exception when others then
    v_p0410 := sqlstate || ': ' || sqlerrm;
  end;
  execute 'reset role';

  -- 6. Foto DESPUÉS y comprobaciones.
  d := pg_temp.categoria_foto(v_ids, v_periodo_meta);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select coalesce(jsonb_object_agg(t.moneda, t.capital), '{}') into v_movido
    from (select c.moneda, sum(c.capital) as capital from public.contratos c where c.id = any(v_cambiados) group by c.moneda) t;
  -- Ranking por origen: solo las claves que cambian.
  select coalesce(jsonb_object_agg(k, jsonb_build_object('antes', a -> 'ranking_origen' -> k, 'despues', d -> 'ranking_origen' -> k)), '{}')
    into v_ranking
    from jsonb_object_keys(coalesce(a -> 'ranking_origen', '{}') || coalesce(d -> 'ranking_origen', '{}')) k
   where (a -> 'ranking_origen' -> k) is distinct from (d -> 'ranking_origen' -> k);

  v_chk := jsonb_build_object(
    'los_12_en_upgrade', (select count(*) from public.contratos c join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
                           where c.id = any(v_ids) and c.categoria = 'upgrade' and o.tipo = 'upgrade') = 12,
    'total_por_moneda_igual', (select bool_and((a -> 'capital' -> k ->> 'total')::numeric = (d -> 'capital' -> k ->> 'total')::numeric)
                                 from jsonb_object_keys((a -> 'capital') || (d -> 'capital')) k),
    'nuevo_baja_y_upgrade_sube_lo_movido', (select bool_and(
        (a -> 'capital' -> k ->> 'nuevo')::numeric - (d -> 'capital' -> k ->> 'nuevo')::numeric = coalesce((v_movido ->> k)::numeric, 0)
        and (d -> 'capital' -> k ->> 'upgrade')::numeric - (a -> 'capital' -> k ->> 'upgrade')::numeric = coalesce((v_movido ->> k)::numeric, 0))
      from jsonb_object_keys((a -> 'capital') || (d -> 'capital')) k),
    -- Por analista y moneda: lo que sale de «nuevo» entra en «upgrade» del MISMO analista (nadie cambia de dueño).
    'por_analista_cuadra', (select bool_and(
        coalesce((d -> 'analistas' -> (x.an || '|nuevo|' || x.m) ->> 'capital')::numeric, 0) - coalesce((a -> 'analistas' -> (x.an || '|nuevo|' || x.m) ->> 'capital')::numeric, 0)
        + coalesce((d -> 'analistas' -> (x.an || '|upgrade|' || x.m) ->> 'capital')::numeric, 0) - coalesce((a -> 'analistas' -> (x.an || '|upgrade|' || x.m) ->> 'capital')::numeric, 0) = 0)
      from (select distinct split_part(k, '|', 1) as an, split_part(k, '|', 3) as m
              from jsonb_object_keys((a -> 'analistas') || (d -> 'analistas')) k) x),
    -- Conversión igual: total y por analista, numerador Y divisor.
    'conversion_igual', (a -> 'conversion') = (d -> 'conversion'),
    'pdf_sin_trabajos_nuevos', (a -> 'pdf') = (d -> 'pdf'),
    'libro_una_fila_por_contrato_firmada', (d ->> 'libro')::int - (a ->> 'libro')::int = cardinality(v_cambiados)
       and (select count(*) from (select l.contrato_id from crm.ledger_rentabilidad l
                                   where l.contrato_id = any(v_ids) and l.registrado_en >= now()
                                   group by l.contrato_id
                                  having count(*) = 1 and bool_and(l.actor_id = v_actor and l.categoria = 'upgrade')) x)
           = cardinality(v_cambiados),
    'medicion_sin_errores', not ((a -> 'rentabilidad') ? 'error' or (d -> 'rentabilidad') ? 'error'
                                 or (a -> 'ranking_origen') ? 'error' or (d -> 'ranking_origen') ? 'error'),
    'sin_P0410', v_p0410 = 'sin P0410',
    'filas_de_motivo', (select count(*) from public.audit_log x where x.tabla = 'contratos.categoria' and x.ts >= now()
                         and x.fila_id = any(select y::text from unnest(v_ids) y) and x.data_despues ->> 'motivo' = c_motivo
                         and x.usuario_id = v_actor));

  raise exception 'ENSAYO (no se escribió nada) · veredicto: % · identidad: % (%) · candidatos: % · contratos ok: % de 12 · cambian: % · comprobaciones: % · capital antes: % · capital después: % · movido: % · conversión antes: % · después: % · observador: % · PARA MIGUEL — ranking por origen (lo que cambia): % · tarjeta de rentabilidad antes: % · después: % · contratos: %',
    case when v_ok = 12 and cardinality(v_cambiados) = 12
              and not exists (select 1 from jsonb_each(v_chk) e where e.key <> 'filas_de_motivo' and e.value <> 'true'::jsonb)
              and (v_chk ->> 'filas_de_motivo')::int = 12
         then 'LISTO PARA 2-REAL' else 'REVISAR' end,
    v_actor_nombre, left(v_actor::text, 8), v_candidatos, v_ok, cardinality(v_cambiados), v_chk,
    a -> 'capital', d -> 'capital', v_movido,
    (a -> 'conversion') - 'por_analista', (d -> 'conversion') - 'por_analista', v_p0410,
    v_ranking, a -> 'rentabilidad', d -> 'rentabilidad', v_out;
end
$ensayo$;

rollback;

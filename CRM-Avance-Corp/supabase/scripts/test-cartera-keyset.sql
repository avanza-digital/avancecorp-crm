-- Oráculo transaccional de F2 tramo 1 (20260810141953_crm_cartera_keyset).
-- Éxito = token CARTERA_KEYSET_TX_OK; todo queda en rollback.
--
-- Cubre lo que la matriz .mjs NO puede con los fixtures del seed:
--   · el EMPATE de `actualizado_en` — el caso que el desempate por id existe
--     para resolver, y que el seed no produce jamás;
--   · el recorrido COMPLETO por páginas de 2 hasta agotar la lista, exigiendo
--     que reconstruya el conjunto exacto sin repetir ni perder una sola fila;
--   · que la función sea SECURITY INVOKER — toda la tesis de la migración es
--     esa, y hasta aquí nada en el gate lo afirmaba: un `create or replace`
--     futuro que heredara por copia el `definer` de las hermanas de F1 pasaría
--     inadvertido (hallazgo MAYOR de la auditoría RLS);
--   · que `ultimo_contacto_en` mida CONTACTO y no la última fila del timeline.
--
-- Fixtures fabricados con triggers apagados (session_replication_role=replica,
-- solo rama desechable): los CHECK sí aplican.

begin;

set local session_replication_role = replica;

-- ── Personas: supervisor S, vendedor V (subárbol de S), portal-only P ────────
insert into public.perfiles(id, nombre_completo, correo, rol, activo) values
  ('7f200000-0000-4000-8000-000000000001', 'ORACULO F2 SUPERVISOR', 'f2-s@test.invalid', 'comercial', true),
  ('7f200000-0000-4000-8000-000000000002', 'ORACULO F2 VENDEDOR', 'f2-v@test.invalid', 'comercial', true),
  ('7f200000-0000-4000-8000-000000000003', 'ORACULO F2 PORTAL PURO', 'f2-p@test.invalid', 'cliente', true),
  -- Lector global (directorio): el ÚNICO rol cuya rama de `leads_select` no
  -- exige `activo`, y por tanto el único al que le afecta el filtro nuevo.
  ('7f200000-0000-4000-8000-000000000004', 'ORACULO F2 DIRECTORIO', 'f2-d@test.invalid', 'directorio', true);

insert into crm.equipo(perfil_id, rol_crm, supervisor_id, activo) values
  ('7f200000-0000-4000-8000-000000000001', 'supervisor', null, true),
  ('7f200000-0000-4000-8000-000000000002', 'vendedor', '7f200000-0000-4000-8000-000000000001', true);

-- ── Leads del vendedor V ─────────────────────────────────────────────────────
-- K1..K4 comparten EXACTAMENTE el mismo `actualizado_en`: sin el desempate por
-- id, el keyset saltaría o repetiría filas justo aquí. Los ids se eligen para
-- que el orden ascendente sea K1 < K2 < K3 < K4.
-- K5 es el más reciente (encabeza la lista); K6 el más antiguo (la cierra).
-- K7 convertido VIEJO (60 d) → fuera por la ventana de 45 d.
-- K8 convertido FRESCO (10 d) → dentro.
-- K9 parkeado en la bandeja de S (sin dueño): V no lo ve, S sí.
insert into crm.leads(id, nombre_completo, telefono, dni, origen, etapa, monto_estimado, moneda,
                      vendedor_id, asignado_supervisor_id, creado_por, creado_en,
                      actualizado_en, convertido_en, contrato_id, motivo_descarte) values
  ('7f200000-0000-4000-8000-000000000101', 'ORACULO K1 EMPATE', '51999227101', '81000001', 'otro', 'nuevo', 1000, 'PEN',
   '7f200000-0000-4000-8000-000000000002', null, '7f200000-0000-4000-8000-000000000002',
   now() - interval '10 days', timestamptz '2026-08-01 12:00:00+00', null, null, null),
  ('7f200000-0000-4000-8000-000000000102', 'ORACULO K2 EMPATE', '51999227102', null, 'otro', 'contactado', 2000, 'PEN',
   '7f200000-0000-4000-8000-000000000002', null, '7f200000-0000-4000-8000-000000000002',
   now() - interval '10 days', timestamptz '2026-08-01 12:00:00+00', null, null, null),
  ('7f200000-0000-4000-8000-000000000103', 'ORACULO K3 EMPATE', '51999227103', null, 'otro', 'contactado', 3000, 'PEN',
   '7f200000-0000-4000-8000-000000000002', null, '7f200000-0000-4000-8000-000000000002',
   now() - interval '10 days', timestamptz '2026-08-01 12:00:00+00', null, null, null),
  ('7f200000-0000-4000-8000-000000000104', 'ORACULO K4 EMPATE', '51999227104', null, 'otro', 'propuesta_enviada', 4000, 'PEN',
   '7f200000-0000-4000-8000-000000000002', null, '7f200000-0000-4000-8000-000000000002',
   now() - interval '10 days', timestamptz '2026-08-01 12:00:00+00', null, null, null),
  ('7f200000-0000-4000-8000-000000000105', 'ORACULO K5 RECIENTE', '51999227105', null, 'otro', 'nuevo', 5000, 'USD',
   '7f200000-0000-4000-8000-000000000002', null, '7f200000-0000-4000-8000-000000000002',
   now() - interval '10 days', timestamptz '2026-08-02 12:00:00+00', null, null, null),
  ('7f200000-0000-4000-8000-000000000106', 'ORACULO K6 ANTIGUO', '51999227106', null, 'otro', 'descartado', 6000, 'PEN',
   '7f200000-0000-4000-8000-000000000002', null, '7f200000-0000-4000-8000-000000000002',
   now() - interval '10 days', timestamptz '2026-07-30 12:00:00+00', null, null, 'sin_interes'),
  ('7f200000-0000-4000-8000-000000000107', 'ORACULO K7 GANADO VIEJO', '51999227107', null, 'otro', 'convertido', 7000, 'PEN',
   '7f200000-0000-4000-8000-000000000002', null, '7f200000-0000-4000-8000-000000000002',
   now() - interval '90 days', timestamptz '2026-07-31 12:00:00+00', now() - interval '60 days', null, null),
  ('7f200000-0000-4000-8000-000000000108', 'ORACULO K8 GANADO FRESCO', '51999227108', null, 'otro', 'convertido', 8000, 'USD',
   '7f200000-0000-4000-8000-000000000002', null, '7f200000-0000-4000-8000-000000000002',
   now() - interval '30 days', timestamptz '2026-07-31 06:00:00+00', now() - interval '10 days', null, null),
  ('7f200000-0000-4000-8000-000000000109', 'ORACULO K9 PARKEADO', '51999227109', null, 'otro', 'nuevo', 9000, 'PEN',
   null, '7f200000-0000-4000-8000-000000000001', '7f200000-0000-4000-8000-000000000001',
   now() - interval '5 days', timestamptz '2026-07-29 12:00:00+00', null, null, null);

-- K10: SOFT-BORRADO (lo que hace `crm.descartar_lead` sobre la cola global).
-- Se inserta aparte para poder poner `activo = false` sin repetir 15 columnas.
insert into crm.leads(id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
                      vendedor_id, creado_por, creado_en, actualizado_en, motivo_descarte, activo)
values ('7f200000-0000-4000-8000-000000000110', 'ORACULO K10 BORRADO', '51999227110', 'otro',
        'descartado', 10000, 'PEN', '7f200000-0000-4000-8000-000000000002',
        '7f200000-0000-4000-8000-000000000002', now() - interval '20 days',
        timestamptz '2026-08-03 12:00:00+00', 'datos_invalidos', false);

-- Timeline de K1: primero un CONTACTO, después una NOTA más reciente. Si el
-- lateral tomara la última fila de cualquier tipo, devolvería la nota.
insert into crm.actividades(id, lead_id, tipo, detalle, creado_por, creado_en) values
  ('7f200000-0000-4000-8000-0000000001a1', '7f200000-0000-4000-8000-000000000101',
   'llamada_realizada', 'ORACULO F2 CONTACTO', '7f200000-0000-4000-8000-000000000002',
   timestamptz '2026-07-20 09:00:00+00'),
  ('7f200000-0000-4000-8000-0000000001a2', '7f200000-0000-4000-8000-000000000101',
   'nota', 'ORACULO F2 NOTA POSTERIOR', '7f200000-0000-4000-8000-000000000002',
   timestamptz '2026-07-25 09:00:00+00');

-- ═════════════════════════════════════════════════════════════════════════════
-- K01 — La función es INVOKER, stable, search_path='' y con ACL exacta.
-- Se comprueba ANTES de asumir ningún rol: es una propiedad del catálogo.
-- ═════════════════════════════════════════════════════════════════════════════
do $test$
declare
  v_fn text := 'crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)';
begin
  if (select count(*) from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm'
         and p.proname = 'cartera_pagina_fn'
         and not p.prosecdef                       -- INVOKER: la tesis entera
         and p.provolatile = 's'
         and p.proconfig @> array['search_path=""']
         and p.pronargs = 7) <> 1 then
    raise exception 'K01a cartera_pagina_fn perdio invoker/stable/search_path/firma';
  end if;
  if not has_function_privilege('authenticated', v_fn, 'execute')
     or has_function_privilege('anon', v_fn, 'execute')
     or has_function_privilege('service_role', v_fn, 'execute') then
    raise exception 'K01b ACL incorrecta en cartera_pagina_fn';
  end if;
end;
$test$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Asserts como el VENDEDOR V (ve sus 8 leads con dueño; K9 es de la bandeja de S)
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f200000-0000-4000-8000-000000000002', true);
set local role authenticated;

-- K02 — Ámbito y ventana de convertidos: 7 filas (8 menos el ganado viejo).
do $test$
declare
  v_ids uuid[];
begin
  -- `with ordinality` captura el orden REAL en que la función emite las filas;
  -- un array_agg sin él dependería de un detalle de implementación.
  select array_agg(id order by ordinality) into v_ids
    from crm.cartera_pagina_fn(p_limite => 200) with ordinality;
  if array_length(v_ids, 1) <> 7 then
    raise exception 'K02a el vendedor recibe % filas, esperaba 7: %', array_length(v_ids, 1), v_ids;
  end if;
  if '7f200000-0000-4000-8000-000000000107'::uuid = any(v_ids) then
    raise exception 'K02b el convertido de 60 dias sigue en el ambito operativo';
  end if;
  if not ('7f200000-0000-4000-8000-000000000108'::uuid = any(v_ids)) then
    raise exception 'K02c el convertido fresco quedo fuera de la ventana de 45 dias';
  end if;
  if '7f200000-0000-4000-8000-000000000109'::uuid = any(v_ids) then
    raise exception 'K02d el vendedor ve un parkeado de la bandeja de su supervisor';
  end if;
end;
$test$;

-- K03 — El orden exacto esperado, sello a sello:
--   1.º K5 (02/08 12:00) · 2.º-5.º K1..K4 (01/08 12:00, EMPATE → id asc)
--   6.º K8 (31/07 06:00) · 7.º K6 (30/07 12:00)
do $test$
declare
  v_ids uuid[];
begin
  select array_agg(id order by ordinality) into v_ids
    from crm.cartera_pagina_fn(p_limite => 200) with ordinality;
  if v_ids <> array[
       '7f200000-0000-4000-8000-000000000105',
       '7f200000-0000-4000-8000-000000000101',
       '7f200000-0000-4000-8000-000000000102',
       '7f200000-0000-4000-8000-000000000103',
       '7f200000-0000-4000-8000-000000000104',
       '7f200000-0000-4000-8000-000000000108',
       '7f200000-0000-4000-8000-000000000106'
     ]::uuid[] then
    raise exception 'K03 el orden (o el desempate por id de los 4 empatados) no es el esperado: %', v_ids;
  end if;
end;
$test$;

-- K04 — Recorrido COMPLETO de 2 en 2: reconstruye el conjunto exacto, sin
-- repetidos y sin huecos. Este es el test que el empate de arriba hace duro.
do $test$
declare
  v_cursor_ts timestamptz := null;
  v_cursor_id uuid := null;
  v_pagina record;
  v_acumulado uuid[] := '{}';
  v_vueltas int := 0;
  v_completo uuid[];
begin
  select array_agg(id order by ordinality) into v_completo
    from crm.cartera_pagina_fn(p_limite => 200) with ordinality;

  loop
    v_vueltas := v_vueltas + 1;
    exit when v_vueltas > 20;  -- salvavidas: un keyset mal hecho no debe colgar
    for v_pagina in
      select f.id, f.actualizado_en
        from crm.cartera_pagina_fn(
               p_limite => 2, p_antes_de => v_cursor_ts, p_antes_id => v_cursor_id)
             with ordinality as f
       order by f.ordinality
    loop
      v_acumulado := v_acumulado || v_pagina.id;
      v_cursor_ts := v_pagina.actualizado_en;
      v_cursor_id := v_pagina.id;
    end loop;
    exit when array_length(v_acumulado, 1) >= array_length(v_completo, 1);
    -- Si una vuelta no añadió nada, el cursor no avanza: mejor fallar que colgar.
    if v_vueltas > 1 and array_length(v_acumulado, 1) = 0 then
      raise exception 'K04a el cursor no avanza';
    end if;
  end loop;

  if v_acumulado <> v_completo then
    raise exception 'K04b paginar de 2 en 2 no reconstruye la lista: % vs %',
      v_acumulado, v_completo;
  end if;
  if (select count(*) from unnest(v_acumulado) x) <>
     (select count(distinct x) from unnest(v_acumulado) x) then
    raise exception 'K04c el paginado repite filas: %', v_acumulado;
  end if;
end;
$test$;

-- K05 — `ultimo_contacto_en` mide CONTACTO, no la última fila del timeline.
do $test$
declare
  v_contacto timestamptz;
  v_sin_contacto timestamptz;
begin
  select f.ultimo_contacto_en into v_contacto
    from crm.cartera_pagina_fn(p_limite => 200) f
   where f.id = '7f200000-0000-4000-8000-000000000101';
  select f.ultimo_contacto_en into v_sin_contacto
    from crm.cartera_pagina_fn(p_limite => 200) f
   where f.id = '7f200000-0000-4000-8000-000000000102';
  if v_contacto is distinct from timestamptz '2026-07-20 09:00:00+00' then
    raise exception 'K05a ultimo_contacto_en tomo la nota (o nada): %', v_contacto;
  end if;
  if v_sin_contacto is not null then
    raise exception 'K05b un lead sin contactos deberia dar null: %', v_sin_contacto;
  end if;
end;
$test$;

-- K06 — Filtros del servidor.
do $test$
declare
  v_n int;
begin
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200, p_etapa => 'contactado');
  if v_n <> 2 then raise exception 'K06a filtro por etapa: % (esperaba 2)', v_n; end if;

  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200, p_sin_asignar => true);
  if v_n <> 0 then raise exception 'K06b el vendedor no tiene parkeados: %', v_n; end if;

  select count(*) into v_n from crm.cartera_pagina_fn(
    p_limite => 200, p_vendedor_id => '7f200000-0000-4000-8000-000000000002');
  if v_n <> 7 then raise exception 'K06c filtro por su propio vendedor: %', v_n; end if;

  -- Texto por nombre.
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200, p_texto => 'EMPATE');
  if v_n <> 4 then raise exception 'K06d busqueda por nombre: % (esperaba 4)', v_n; end if;

  -- Teléfono: 3+ dígitos.
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200, p_texto => '227101');
  if v_n <> 1 then raise exception 'K06e busqueda por telefono: %', v_n; end if;

  -- DNI (la PII más sensible de la tabla): solo K1 lo tiene.
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200, p_texto => '81000001');
  if v_n <> 1 then raise exception 'K06f busqueda por DNI: %', v_n; end if;

  -- Los tres metacaracteres de LIKE son LITERALES del usuario: como comodines,
  -- 'K%' y 'K_' casarían con los cuatro «ORACULO K1 EMPATE» y compañía.
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200, p_texto => 'K%');
  if v_n <> 0 then raise exception 'K06g el %% se trato como comodin: %', v_n; end if;
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200, p_texto => 'K_');
  if v_n <> 0 then raise exception 'K06h el _ se trato como comodin: %', v_n; end if;
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200, p_texto => 'K\');
  if v_n <> 0 then raise exception 'K06i la barra rompio el patron: %', v_n; end if;
end;
$test$;

-- K07 — Parámetros inválidos: 22023, cada uno con su mensaje.
do $test$
declare
  v_n int;
begin
  begin
    select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 0);
    raise exception 'K07a p_limite=0 fue aceptado';
  exception when others then
    if sqlstate <> '22023' then raise exception 'K07a sqlstate %: %', sqlstate, sqlerrm; end if;
  end;
  begin
    select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 201);
    raise exception 'K07b p_limite=201 fue aceptado';
  exception when others then
    if sqlstate <> '22023' then raise exception 'K07b sqlstate %: %', sqlstate, sqlerrm; end if;
  end;
  begin
    select count(*) into v_n from crm.cartera_pagina_fn(p_antes_de => now());
    raise exception 'K07c cursor a medias fue aceptado';
  exception when others then
    if sqlstate <> '22023' then raise exception 'K07c sqlstate %: %', sqlstate, sqlerrm; end if;
  end;
  begin
    select count(*) into v_n from crm.cartera_pagina_fn(p_etapa => 'perdido');
    raise exception 'K07d etapa fuera del catalogo fue aceptada';
  exception when others then
    if sqlstate <> '22023' then raise exception 'K07d sqlstate %: %', sqlstate, sqlerrm; end if;
  end;
  begin
    select count(*) into v_n from crm.cartera_pagina_fn(p_texto => 'a');
    raise exception 'K07e texto de 1 caracter fue aceptado';
  exception when others then
    if sqlstate <> '22023' then raise exception 'K07e sqlstate %: %', sqlstate, sqlerrm; end if;
  end;
  begin
    select count(*) into v_n from crm.cartera_pagina_fn(
      p_sin_asignar => true, p_vendedor_id => '7f200000-0000-4000-8000-000000000002');
    raise exception 'K07f filtro contradictorio fue aceptado';
  exception when others then
    if sqlstate <> '22023' then raise exception 'K07f sqlstate %: %', sqlstate, sqlerrm; end if;
  end;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- K08 — El SUPERVISOR S ve su subárbol MÁS su bandeja (el parkeado K9).
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f200000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $test$
declare
  v_n int;
  v_park int;
begin
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 200);
  if v_n <> 8 then raise exception 'K08a el supervisor recibe % filas, esperaba 8', v_n; end if;
  select count(*) into v_park from crm.cartera_pagina_fn(p_limite => 200, p_sin_asignar => true);
  if v_park <> 1 then raise exception 'K08b el parkeado de su bandeja no llega: %', v_park; end if;
  -- El mismo contacto que veía el vendedor, idéntico (co-extensividad de
  -- actividades_select con leads_select: es lo que sostiene el invoker).
  if (select f.ultimo_contacto_en from crm.cartera_pagina_fn(p_limite => 200) f
       where f.id = '7f200000-0000-4000-8000-000000000101')
     is distinct from timestamptz '2026-07-20 09:00:00+00' then
    raise exception 'K08c el supervisor ve otro ultimo_contacto_en que su vendedor';
  end if;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- K10 — El DIRECTORIO (lector global) NO ve los soft-borrados (20260810151433).
-- Es el único rol al que le afecta: su rama de `leads_select` no exige `activo`,
-- así que hasta esta migración la Cartera le mezclaba en las FILAS lo que sus
-- TILES (resumen_cartera_fn, que sí filtra) nunca contaron.
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f200000-0000-4000-8000-000000000004', true);
set local role authenticated;

do $test$
declare
  v_ve_borrado boolean;
  v_ve_vivo boolean;
  v_ve_descartado boolean;
begin
  select exists (select 1 from crm.cartera_pagina_fn(p_limite => 200) f
                  where f.id = '7f200000-0000-4000-8000-000000000110'),
         exists (select 1 from crm.cartera_pagina_fn(p_limite => 200) f
                  where f.id = '7f200000-0000-4000-8000-000000000101'),
         exists (select 1 from crm.cartera_pagina_fn(p_limite => 200) f
                  where f.id = '7f200000-0000-4000-8000-000000000106')
    into v_ve_borrado, v_ve_vivo, v_ve_descartado;

  if v_ve_borrado then
    raise exception 'K10a el lector global sigue viendo un lead soft-borrado';
  end if;
  if not v_ve_vivo then
    raise exception 'K10b el filtro de activo se llevo por delante un lead vivo';
  end if;
  -- La otra mitad, y la que de verdad podria haberse roto: un lead DESCARTADO
  -- (etapa) no es un lead BORRADO (activo) y tiene que seguir en la cartera.
  if not v_ve_descartado then
    raise exception 'K10c un lead descartado desaparecio de la cartera';
  end if;
  -- El lector global comprueba ademas que sigue viendo lo AJENO vivo: el filtro
  -- de activo no debe haberse comido su alcance global.
  if not exists (select 1 from crm.cartera_pagina_fn(p_limite => 200) f
                  where f.id = '7f200000-0000-4000-8000-000000000109') then
    raise exception 'K10d el lector global perdio el parkeado de otra bandeja';
  end if;
end;
$test$;

reset role;

-- Y el vendedor tampoco lo ve — no porque lo filtre esta migracion, sino
-- porque su policy ya lo excluia. Aserto de NO REGRESION del predicado.
select set_config('request.jwt.claim.sub', '7f200000-0000-4000-8000-000000000002', true);
set local role authenticated;

do $test$
begin
  if exists (select 1 from crm.cartera_pagina_fn(p_limite => 200) f
              where f.id = '7f200000-0000-4000-8000-000000000110') then
    raise exception 'K10e el vendedor ve un lead soft-borrado';
  end if;
  if (select count(*) from crm.cartera_pagina_fn(p_limite => 200)) <> 7 then
    raise exception 'K10f el ambito del vendedor cambio de tamano con el filtro nuevo';
  end if;
end;
$test$;

reset role;

-- ═════════════════════════════════════════════════════════════════════════════
-- K09 — Un autenticado AJENO al CRM: 42501 explícito, no una lista vacía.
-- ═════════════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub', '7f200000-0000-4000-8000-000000000003', true);
set local role authenticated;

do $test$
declare
  v_n int;
begin
  select count(*) into v_n from crm.cartera_pagina_fn(p_limite => 50);
  raise exception 'K09a el ajeno al CRM recibio una lista (% filas) en vez de 42501', v_n;
exception when others then
  if sqlstate <> '42501' then
    raise exception 'K09a sqlstate %: %', sqlstate, sqlerrm;
  end if;
end;
$test$;

reset role;

rollback;

select 'CARTERA_KEYSET_TX_OK' as resultado;

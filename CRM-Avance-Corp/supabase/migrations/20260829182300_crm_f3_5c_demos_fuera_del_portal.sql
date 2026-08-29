-- P-055 Fase 3.5c - Los contratos de prueba tampoco cuentan en el PORTAL (P0-2).
--
-- TOCA `public` (9 funciones del portal): con permiso explicito de Miguel
-- (decision 6: los demos «se excluyen de metricas y ranking» — de TODAS, no de
-- las del CRM nada mas). La auditoria adversarial de Codex encontro que el lote
-- de la 182000 dejaba fuera el Directorio y los paneles de pagos/admin: los dos
-- demos desaparecian del cierre pero seguian sumando en el AUM, el crecimiento,
-- el top de clientes, el ranking del Directorio y la cobranza. Dos pantallas
-- habrian dado capital distinto para el mismo mes.
--
-- LAS 9, con lo que cuenta cada una:
--   public.metricas_directorio            AUM, crecimiento, cobranza, caja (5 sitios)
--   public.directorio_ranking_analistas   ranking del Directorio
--   public.directorio_top_clientes        top de clientes
--   public.directorio_morosidad           cuotas vencidas
--   public.dashboard_admin_metricas       tablero del admin
--   public.admin_pagos_metricas           pagos del mes
--   public.admin_pagos_resumen            resumen de pagos
--   public.pagos_admin_metricas_globales  pagos globales
--   public.pagos_admin_resumen_contratos  detalle de pagos por contrato
--
-- COMO: el mismo motor anclado de la 182000 (huella md5 + conteo exacto de
-- sitios + invariante de menciones totales), con los patrones DE ESTAS
-- funciones (usan `FROM contratos` sin calificar, con search_path=public).
-- El reemplazo conserva el alias: `FROM (SELECT * FROM contratos WHERE NOT
-- es_demo) c` — ni una linea mas cambia. Donde no hay alias, la subconsulta se
-- llama `contratos` y el resto de la funcion ni se entera.
--
-- OJO CON LO QUE NO SE TOCA: `FROM contratos_norm` y `FROM contratos_full` son
-- CTEs internas de dos de estas funciones; los patrones llevan el espacio o el
-- salto de linea pegado para no rozarlas, y el invariante de menciones totales
-- lo verifica.
--
-- Y LA VIA DE LAS CONVERSIONES DE CARTERA, cerrada por el otro lado: tres
-- funciones leen `crm.operaciones_cartera` para contar conversiones de
-- renovacion/upgrade y ninguna mira si el contrato es demo. En vez de operarle
-- el corazon a la conversion dias antes del cierre, se cierra LA CAUSA:
-- `public.marcar_contrato_demo` RECHAZA marcar un contrato que tenga
-- operaciones de cartera (como origen o como nuevo). Los demos son contratos
-- de prueba sueltos, como los dos de Kirk; una renovacion real que resulto
-- falsa tiene su puerta de siempre: la anulacion de gerencia, que si sabe
-- descontar conversiones.

begin;

do $parche$
declare
  v_reg regprocedure; v_huella text; v_def text; v_nuevo text;
  v_pat text; v_rep text; v_esperado int; v_hechos int; v_menciones int;
  v_total int := 0;
  -- firma | huella | menciones totales de 'contratos' | lista de (patron :: reemplazo :: veces)
  v_fns text[][] := array[
    ['public.metricas_directorio()',           '652b50d673ce058406187e3416450a1d', '6'],
    ['public.directorio_ranking_analistas()',  'bdf65281a29dfd6b7cc9c560e6ecb27d', '1'],
    ['public.directorio_top_clientes()',       '1f94d618d0c28ca0bb1c15465b0677ad', '1'],
    ['public.directorio_morosidad()',          'e75d74fe4d2fca226f6f3060609718fe', '1'],
    ['public.dashboard_admin_metricas()',      '7a4afa07a469a31967e47f3e17e397a2', '6'],
    ['public.admin_pagos_metricas()',          'd5aa19bf1997ffa3e0f712665ffa45dc', '1'],
    ['public.admin_pagos_resumen()',           '4e3e989d7424334dd5f559e7b08f5fe5', '2'],
    ['public.pagos_admin_metricas_globales()', '356b8f5ac3b81e0281508da679e86cc2', '1'],
    ['public.pagos_admin_resumen_contratos(text,text,text,integer,integer)', '3acc54d9d28bee9c31368c9bc7183b07', '3']
  ];
  -- patrones: tabla PLANA y rectangular (un array anidado desigual no es legal
  -- en Postgres): cada fila = [indice de funcion, patron, reemplazo, veces].
  v_pats text[][] := array[
    ['1', 'FROM contratos WHERE estado = ''activo''',
          'FROM (SELECT * FROM contratos WHERE NOT es_demo) contratos WHERE estado = ''activo''', '1'],
    ['1', 'FROM contratos' || E'\n',
          'FROM (SELECT * FROM contratos WHERE NOT es_demo) contratos' || E'\n', '2'],
    ['1', 'JOIN contratos c ON c.id = cp.contrato_id',
          'JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id = cp.contrato_id', '1'],
    ['1', 'JOIN contratos c ON c.id=cp.contrato_id',
          'JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id=cp.contrato_id', '1'],
    ['2', 'FROM contratos c' || E'\n',
          'FROM (SELECT * FROM contratos WHERE NOT es_demo) c' || E'\n', '1'],
    ['3', 'FROM contratos c JOIN perfiles',
          'FROM (SELECT * FROM contratos WHERE NOT es_demo) c JOIN perfiles', '1'],
    ['4', 'JOIN contratos c ON c.id = cp.contrato_id',
          'JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id = cp.contrato_id', '1'],
    ['5', 'FROM contratos c' || E'\n',
          'FROM (SELECT * FROM contratos WHERE NOT es_demo) c' || E'\n', '1'],
    ['6', 'JOIN contratos c ON c.id = cp.contrato_id',
          'JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id = cp.contrato_id', '1'],
    ['7', 'FROM contratos c' || E'\n',
          'FROM (SELECT * FROM contratos WHERE NOT es_demo) c' || E'\n', '1'],
    ['8', 'JOIN contratos c ON c.id = cp.contrato_id',
          'JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id = cp.contrato_id', '1'],
    ['9', 'FROM contratos c' || E'\n',
          'FROM (SELECT * FROM contratos WHERE NOT es_demo) c' || E'\n', '1']
  ];
  i int; j int;
begin
  set local lock_timeout = '5s';

  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname='es_demo' and not attisdropped) then
    raise exception 'Falta la migracion 20260829180000 (es_demo): ABORTA';
  end if;

  for i in 1 .. array_length(v_fns, 1) loop
    v_reg := v_fns[i][1]::regprocedure;
    select md5(p.prosrc), pg_get_functiondef(p.oid) into v_huella, v_def
    from pg_proc p where p.oid = v_reg;
    if v_huella <> v_fns[i][2] then
      raise exception '% cambio desde que se midio (huella %): ABORTA', v_reg, v_huella;
    end if;
    -- invariante de menciones ANTES (sobre prosrc, no functiondef, para que el
    -- encabezado CREATE no cuente)
    select (length(p.prosrc)-length(replace(p.prosrc,'contratos','')))/length('contratos')
      into v_menciones from pg_proc p where p.oid = v_reg;
    if v_menciones <> v_fns[i][3]::int then
      raise exception '% menciona contratos % veces y se esperaban %: ABORTA', v_reg, v_menciones, v_fns[i][3];
    end if;

    v_nuevo := v_def;
    for j in 1 .. array_length(v_pats, 1) loop
      continue when v_pats[j][1]::int <> i;
      v_pat := v_pats[j][2];
      v_rep := v_pats[j][3];
      v_esperado := v_pats[j][4]::int;
      v_hechos := (length(v_nuevo)-length(replace(v_nuevo,v_pat,'')))/length(v_pat);
      if v_hechos <> v_esperado then
        raise exception '% patron % aparece % veces y se esperaban %: ABORTA', v_reg, j, v_hechos, v_esperado;
      end if;
      v_nuevo := replace(v_nuevo, v_pat, v_rep);
      v_total := v_total + v_esperado;
    end loop;
    if v_nuevo = v_def then
      raise exception 'El parche de % no cambio nada: ABORTA', v_reg;
    end if;
    execute v_nuevo;
  end loop;

  raise notice 'PARCHE: 9 funciones del portal, % sitios filtrados', v_total;
end
$parche$;

-- La causa de las conversiones: un contrato con operaciones NO se marca demo.
do $puerta$
declare v_src text;
begin
  select p.prosrc into v_src
  from pg_proc p where p.oid = 'public.marcar_contrato_demo(uuid,boolean,text)'::regprocedure;
  if v_src is null then
    raise exception 'Falta public.marcar_contrato_demo (20260829181500): ABORTA';
  end if;
  if strpos(v_src, 'operaciones_cartera') > 0 then
    raise exception 'marcar_contrato_demo ya conoce operaciones_cartera: ABORTA (¿re-run?)';
  end if;
  if strpos(v_src, 'if v_row.es_demo = p_es_demo then') = 0 then
    raise exception 'El ancla de marcar_contrato_demo no esta: ABORTA';
  end if;

  v_src := replace(v_src, 'if v_row.es_demo = p_es_demo then',
'-- P0-2 (Codex): las conversiones de cartera se cuentan desde
  -- crm.operaciones_cartera y esa via no mira es_demo. Un contrato con
  -- operaciones reales no es un contrato de prueba: si la operacion fue
  -- falsa, la puerta es la anulacion de gerencia, que si descuenta.
  if exists (select 1 from crm.operaciones_cartera o
             where o.contrato_nuevo_id = p_contrato_id
                or o.contrato_origen_id = p_contrato_id) then
    raise exception using
      errcode = ''P0409'',
      message = ''Este contrato tiene operaciones de cartera: no es un contrato de prueba'',
      hint = ''Si la operacion fue un error, gerencia la anula; la anulacion si sabe descontar la conversion.'';
  end if;

  if v_row.es_demo = p_es_demo then');

  execute format(
    'create or replace function public.marcar_contrato_demo(p_contrato_id uuid, p_es_demo boolean, p_motivo text) '
    'returns jsonb language plpgsql security definer set search_path to '''' as %L', v_src);
end
$puerta$;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_reg regprocedure; v_src text; v_falta text := '';
  v_fns text[] := array[
    'public.metricas_directorio()','public.directorio_ranking_analistas()',
    'public.directorio_top_clientes()','public.directorio_morosidad()',
    'public.dashboard_admin_metricas()','public.admin_pagos_metricas()',
    'public.admin_pagos_resumen()','public.pagos_admin_metricas_globales()',
    'public.pagos_admin_resumen_contratos(text,text,text,integer,integer)'];
  v_sitios int[] := array[5,1,1,1,1,1,1,1,1];
  i int; v_n int;
begin
  for i in 1 .. array_length(v_fns, 1) loop
    v_reg := v_fns[i]::regprocedure;
    select p.prosrc into v_src from pg_proc p where p.oid = v_reg;
    v_n := (length(v_src)-length(replace(v_src,'WHERE NOT es_demo','')))/length('WHERE NOT es_demo');
    if v_n <> v_sitios[i] then
      v_falta := v_falta || v_reg::text || ' (filtros ' || v_n || ', esperados ' || v_sitios[i] || ') ';
    end if;
  end loop;
  if v_falta <> '' then
    raise exception 'POSTFLIGHT: %', v_falta;
  end if;

  select strpos(p.prosrc, 'operaciones_cartera') into v_n
  from pg_proc p where p.oid = 'public.marcar_contrato_demo(uuid,boolean,text)'::regprocedure;
  if coalesce(v_n, 0) = 0 then
    raise exception 'POSTFLIGHT: marcar_contrato_demo no cierra la via de las conversiones';
  end if;

  raise notice 'POSTFLIGHT OK: los demos tampoco cuentan en el portal, y la via de conversiones quedo cerrada';
end
$postflight$;

commit;

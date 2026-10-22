-- ESPERA ENTRE DOS SESIONES del bloque 2.11, SESIÓN B, modo «ORDEN» (ronda 3; Codex r1, P3): ¿la pieza toma los candados ANTES de
-- juzgar? La arma `armar-ensayo.mjs --espera-b orden` DETRÁS de la migración real (o de un mutante) y la corre `espera.sh` a la vez
-- que la sesión A; las dos terminan en rollback. NUNCA contra producción.
--
-- Cómo se distingue SIN confirmar nada: el JUICIO (`private.juicio_cliente_convertido`) es lo único de la pieza que lee public.perfiles
-- (el nombre del asesor); los candados no leen tablas. Postgres toma el candado de tabla (AccessShareLock) de cada relación que nombra una
-- consulta al ejecutarla y lo retiene hasta el final de la transacción. Si B llama a la pieza en una transacción que NO ha tocado
-- perfiles y A observa, mientras B espera por el candado de X, que B YA tiene public.perfiles ⇒ B juzgó antes de pedir el candado (el
-- mutante M17); si no la tiene ⇒ el candado fue antes (la migración). Por eso este montaje no usa el alta ni mira perfiles: inserta el
-- lead con los disparadores apagados (estado declarado), sin vendedor ni creador, y llama a la pieza como postgres. Al terminar, B dice
-- si el juicio tomó perfiles (tiene que ser «sí»: si no, la observación de A no significaría nada).
set local statement_timeout = '60s';

do $b$
declare
  v_x text := '@@X@@';
  v_l uuid := gen_random_uuid();
  v_r jsonb;
  v_clave bigint := hashtextextended('avancecrm:lead:telefono:' || private.normalizar_telefono('@@X@@'), 0);
  v_t0 timestamptz;
  v_ms integer;
  v_vio boolean := false;
  i integer;
begin
  if exists (select 1 from crm.leads l where l.telefono in (v_x, '+51924119906') or l.telefono_alternativo = v_x) then
    raise exception 'ESPERA ABORTADA: los números del ensayo de orden no están libres';
  end if;
  -- El lead que CONSERVA X como alternativo, con los disparadores apagados y sin tocar perfiles (sin vendedor, sin creador).
  -- La ORDEN «set local» (no set_config): en esta imagen solo la orden puede poner session_replication_role sin ser superusuario.
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, telefono_alternativo, origen, etapa, monto_estimado, moneda, activo, alta_manual,
                         ciclo_actual, no_contactar, creado_en, actualizado_en, sla_global_iniciado_en, sla_global_aproximado)
  values (v_l, 'ESPERA ORDEN', '+51924119906', v_x, 'formulario', 'contactado', 1000, 'PEN', true, true, 1, false, now(), now(), now(), false);
  set local session_replication_role = origin;
  if exists (select 1 from pg_locks k where k.pid = pg_backend_pid() and k.locktype = 'relation' and k.relation = 'public.perfiles'::regclass) then
    raise exception 'ESPERA ABORTADA: el montaje tocó public.perfiles (la prueba de orden no valdría)';
  end if;
  -- Esperar a que A tenga el candado de X (hasta 3 s).
  for i in 1..60 loop
    if exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid <> pg_backend_pid() and l.objsubid = 1
                 and (((l.classid::text::bigint) << 32) | (l.objid::text::bigint)) = v_clave) then
      v_vio := true;
      exit;
    end if;
    perform pg_sleep(0.05);
  end loop;
  if not v_vio then
    raise exception 'ESPERA ABORTADA: la sesión A no tomó el candado de X a tiempo';
  end if;
  -- La llamada medida: la pieza sola, como postgres.
  v_t0 := clock_timestamp();
  v_r := private.juicio_cliente_conservado(v_l);
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  raise exception 'ESPERA B (orden): espera de B = % ms · resultado de la llamada: ok:% · cuerpo de la pieza (md5): % · perfiles tomada al terminar: %',
    v_ms, coalesce(v_r::text, 'null'),
    coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.juicio_cliente_conservado(uuid)')), 'ausente'),
    case when exists (select 1 from pg_locks k where k.pid = pg_backend_pid() and k.locktype = 'relation' and k.relation = 'public.perfiles'::regclass)
         then 'sí' else 'no' end;
end
$b$;

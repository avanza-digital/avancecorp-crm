-- ESPERA ENTRE DOS SESIONES del bloque 2.11, SESIÓN B (la arma `armar-ensayo.mjs --espera-b <pieza|alta|base>` DETRÁS de la migración
-- real y la corre `espera.sh` a la vez que la sesión A; las dos terminan en rollback). NUNCA contra producción.
--
-- La sesión A retiene el candado de contacto del número @@X@@ (la misma clave que `private.bloquear_contactos_lead`: lo que tomaría un
-- cliente que se pone ese número como alternativo, o la conversión de un lead con ese número). Aquí, un lead que CONSERVA @@X@@ nace por
-- la puerta real con números auxiliares (sus candados no tocan @@X@@) y recibe @@X@@ con los disparadores apagados (estado declarado);
-- se espera a ver el candado de A tomado y se mide cuánto tarda la llamada:
--   · pieza: `private.juicio_cliente_conservado` sobre el lead (su alternativo es @@X@@): con la migración tiene que ESPERAR a A (el
--     candado va antes del juicio); sin el candado (mutante M15), no espera.
--   · alta: un alta que reactiva una ficha retirada cuyo alternativo conservado es @@X@@ (se teclean su teléfono y su DNI, no @@X@@).
--   · base: `crm.reactivar_lead_base_v2` de un contacto de base cuyo teléfono es @@X@@.
--   En «alta» y «base» B espera también sin la pieza (el disparador de disponibilidad toma esa clave al escribir): se mide que la
--   reactivación queda serializada detrás de A; DÓNDE espera (antes de juzgar) lo prueba «pieza».
set local statement_timeout = '60s';

create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

do $b$
declare
  v_x text := '@@X@@';
  v_via text := '@@VIA@@';
  v_vend1 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 VEND1');
  v_vend2 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 VEND2');
  v_sup1 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 SUP1');
  v_ger uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 GERENCIA');
  v_l uuid := gen_random_uuid();
  v_base uuid;
  v_r jsonb;
  v_res text;
  v_clave bigint := hashtextextended('avancecrm:lead:telefono:' || private.normalizar_telefono('@@X@@'), 0);
  v_t0 timestamptz;
  v_ms integer;
  v_vio boolean := false;
  i integer;
begin
  if v_vend1 is null or v_vend2 is null or v_sup1 is null or v_ger is null then
    raise exception 'ESPERA ABORTADA: faltan actores del banco';
  end if;
  if exists (select 1 from crm.leads l where l.telefono in (v_x, '+51924119902', '+51924119903', '+51924119904')
                                          or l.telefono_alternativo = v_x or l.dni = '75319903') then
    raise exception 'ESPERA ABORTADA: los números del ensayo de espera no están libres';
  end if;
  -- Montaje (sin tocar el número X: sus candados los retiene A).
  if v_via = 'pieza' then
    perform pg_temp.sesion(v_vend1);
    v_r := crm.crear_lead_si_disponible(p_nombre_completo => 'ESPERA PIEZA', p_telefono => '924119902', p_origen => 'formulario',
                                        p_monto_estimado => 5000, p_moneda => 'PEN', p_id => v_l);
    perform pg_temp.sesion(null);
    set local session_replication_role = replica;
    update crm.leads set telefono_alternativo = v_x where id = v_l;
    set local session_replication_role = origin;
  elsif v_via = 'alta' then
    perform pg_temp.sesion(v_vend1);
    v_r := crm.crear_lead_si_disponible(p_nombre_completo => 'ESPERA FICHA RETIRADA', p_telefono => '924119903', p_origen => 'formulario',
                                        p_monto_estimado => 5000, p_moneda => 'PEN', p_id => v_l, p_dni => '75319903');
    perform pg_temp.sesion(v_ger);
    update crm.leads set activo = false where id = v_l;
    perform pg_temp.sesion(null);
    set local session_replication_role = replica;
    update crm.leads set telefono_alternativo = v_x where id = v_l;
    set local session_replication_role = origin;
  elsif v_via = 'base' then
    perform pg_temp.sesion(v_sup1);
    v_base := (crm.crear_base(gen_random_uuid(), 'BASE ESPERA 2.11', 'archivo', null, 'espera-2-11.csv') ->> 'base_id')::uuid;
    v_r := crm.cargar_base_lote(gen_random_uuid(), v_base, '[{"fila": 1, "nombre": "CONTACTO ESPERA", "telefono": "+51924119904"}]'::jsonb);
    perform pg_temp.sesion(null);
    v_l := (select l.id from crm.leads l where l.telefono = '+51924119904');
    set local session_replication_role = replica;
    update crm.leads set telefono = v_x where id = v_l;
    set local session_replication_role = origin;
  else
    raise exception 'ESPERA ABORTADA: vía desconocida %', v_via;
  end if;
  if v_l is null or not exists (select 1 from crm.leads l where l.id = v_l and v_x in (l.telefono, l.telefono_alternativo)) then
    raise exception 'ESPERA ABORTADA: el lead del ensayo no quedó con el número X';
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
  -- La llamada medida.
  v_t0 := clock_timestamp();
  if v_via = 'pieza' then
    v_r := private.juicio_cliente_conservado(v_l);
    v_res := 'ok|' || coalesce(v_r::text, 'null');
  elsif v_via = 'alta' then
    perform pg_temp.sesion(v_vend2);
    v_r := crm.crear_lead_si_disponible(p_nombre_completo => 'ESPERA REINGRESO', p_telefono => '924119903', p_origen => 'formulario',
                                        p_monto_estimado => 5000, p_moneda => 'PEN', p_id => gen_random_uuid(), p_dni => '75319903');
    perform pg_temp.sesion(null);
    v_res := 'ok|' || v_r::text;
  else
    perform pg_temp.sesion(v_sup1);
    v_r := crm.reactivar_lead_base_v2(gen_random_uuid(), v_l, 'ensayo de espera del bloque 2.11', 5000, 'PEN');
    perform pg_temp.sesion(null);
    v_res := 'ok|' || v_r::text;
  end if;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  raise exception 'ESPERA B (%): espera de B = % ms · resultado de la llamada: % · cuerpo de la pieza (md5): %', v_via, v_ms,
    split_part(v_res, '|', 1) || ':' || coalesce(v_r ->> 'estado', v_r ->> 'etapa', left(split_part(v_res, '|', 2), 40)),
    coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.juicio_cliente_conservado(uuid)')), 'ausente');
end
$b$;

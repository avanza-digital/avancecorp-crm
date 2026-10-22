-- ESPERA ENTRE DOS SESIONES del bloque 2.10, SESIÓN B (la arma `armar-ensayo.mjs --espera-b` DETRÁS de las migraciones del 2.11, del
-- 2.16 y de la real de este bloque, y la corre `espera.sh` a la vez que la sesión A; las dos terminan en rollback). NUNCA contra producción.
--
-- La sesión A retiene el candado del DOCUMENTO del DNI @@DNI@@ (la misma clave `inv_resolver:DNI:<dni>` que toma la puerta de conversión
-- antes de resolver la persona, y que toman otra conversión con ese DNI, el resolver y la puerta del DNI de la ficha). Aquí nace un
-- cliente antiguo sin ficha con ese DNI (convertido RETIRADO, sembrado sin tocar el documento: sus candados los retiene A) y un lead
-- nuevo por el alta real (sin DNI); se espera a ver el candado de A tomado y se mide cuánto tarda la preparación de la conversión con
-- ese DNI: tiene que ESPERAR a A (la puerta toma el candado del documento ANTES de juzgar y absorber) y, al soltarse, absorber al
-- antiguo (puente histórico) y seguir. Sin A (control), no espera.
set local statement_timeout = '60s';

create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

do $b$
declare
  v_dni text := '@@DNI@@';
  v_vend1 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 VEND1');
  v_vend2 uuid := (select p.id from public.perfiles p where p.nombre_completo = 'PASO08 VEND2');
  v_c uuid := gen_random_uuid();
  v_l uuid := gen_random_uuid();
  v_r jsonb;
  v_res text;
  v_clave bigint := hashtext('inv_resolver:DNI:' || v_dni);
  v_t0 timestamptz;
  v_ms integer;
  v_vio boolean := false;
  i integer;
begin
  if v_vend1 is null or v_vend2 is null then
    raise exception 'ESPERA ABORTADA: faltan actores del banco';
  end if;
  if exists (select 1 from crm.leads l where l.telefono in ('+51924099901', '+51924099902') or l.dni = v_dni)
     or exists (select 1 from crm.inversionista_identificadores d where d.documento_normalizado = v_dni) then
    raise exception 'ESPERA ABORTADA: los contactos del ensayo de espera no están libres';
  end if;
  -- Montaje. El antiguo, sembrado con los disparadores apagados (estado heredado: convertido, retirado, sin persona, con su cierre
  -- externo inicial); sin tocar el documento @@DNI@@ por ninguna puerta (sus candados los retiene A).
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, convertido_en, monto_estimado, moneda, vendedor_id, activo,
                         creado_por, alta_manual, ciclo_actual, creado_en, actualizado_en, sla_global_iniciado_en)
  values (v_c, 'ESPERA ANTIGUO', '+51924099901', v_dni, 'formulario', 'convertido', clock_timestamp() - interval '5 days', 1000, 'PEN',
          v_vend1, false, v_vend1, true, 1, now() - interval '30 days', now() - interval '10 days', now() - interval '30 days');
  insert into crm.cierres_externos (lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion,
                                    vendedor_id, creado_por, es_cierre_inicial)
  values (v_c, 'prodelco', 1000, 'PEN', 'DNI', v_dni, 'ESPERA ANTIGUO', 'ESPERA-' || left(v_c::text, 8), v_vend1, v_vend1, true);
  set local session_replication_role = origin;
  perform pg_temp.sesion(v_vend2);
  v_r := crm.crear_lead_si_disponible(p_nombre_completo => 'ESPERA LEAD NUEVO', p_telefono => '924099902', p_origen => 'formulario',
                                      p_monto_estimado => 5000, p_moneda => 'PEN', p_id => v_l);
  perform pg_temp.sesion(null);
  if v_r ->> 'estado' is distinct from 'creado' then
    raise exception 'ESPERA ABORTADA: no nació el lead nuevo (%)', v_r;
  end if;
  -- Espera a ver el candado de A tomado (hasta 3 s: A lleva ya varios segundos reteniéndolo); si no está (control), sigue.
  for i in 1..30 loop
    exit when exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid <> pg_backend_pid()
                        and ((l.classid::text::bigint) << 32 | l.objid::text::bigint) = v_clave);
    perform pg_sleep(0.1);
  end loop;
  v_vio := exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid <> pg_backend_pid()
                     and ((l.classid::text::bigint) << 32 | l.objid::text::bigint) = v_clave);
  v_t0 := clock_timestamp();
  begin
    perform pg_temp.sesion(v_vend2);
    v_r := crm.preparar_persona_lead_inversion_fn(v_l, 'DNI', v_dni, 'ESPERA LEAD NUEVO');
    perform pg_temp.sesion(null);
    v_res := 'ok:' || case when exists (select 1 from crm.inversionista_leads il where il.lead_id = v_c and il.rol = 'historico'
                                           and il.inversionista_id = (v_r ->> 'inversionista_id')::uuid) then 'absorbido' else 'SIN-PUENTE' end;
  exception when others then
    perform pg_temp.sesion(null);
    v_res := sqlstate || ':' || replace(sqlerrm, ' ', '_');
  end;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  raise exception 'ESPERA B: candado de A visto antes: % · espera de B = % ms · resultado de la llamada: % · puerta md5(prosrc)=%',
    case when v_vio then 'sí' else 'no' end, v_ms, v_res,
    (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'::regprocedure);
end
$b$;

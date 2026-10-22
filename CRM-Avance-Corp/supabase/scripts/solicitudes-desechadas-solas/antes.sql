-- MONTAJE del ensayo de «el CRM cancela solo las solicitudes de inversión que ya no corresponden» (bloque 2.15: D-58, D-59,
-- D-63, D-66) — se ejecuta en el LABORATORIO (banco Docker local), NUNCA contra producción, y no escribe nada: todo vive en la
-- transacción que `armar-ensayo.mjs` abre y termina en `rollback`.
--
-- Va DELANTE de la migración (y, en `--sin-migracion`, delante del oráculo a secas):
--   1. Auxiliares temporales (sesión, registro de fallos, la llamada al alta v2 y a la consulta como un actor).
--   2. Actores reales del banco (OBLIGATORIOS: si faltan, el ensayo aborta): V1, un vendedor activo (rol comercial en el Portal,
--      ficha vendedor activa) con un cliente activo C1 con documento en su cartera cuya ficha de inversionista I1 existe.
--   3. Números de contrato LIBRES (N1…N7, serie 2026-01-99NNNN, comprobados contra public.contratos) y dos números YA USADOS
--      (EX1, EX2: contratos existentes del banco).
--   4. La siembra de solicitudes de inversión (con los disparadores de la tabla encendidos: los de INSERT no hacen nada aquí) y
--      el disparador de ensayo que fuerza el rechazo de UNA cancelación (S8).
--   5. Las mediciones de ANTES: la consulta de S3 como V1 y el texto del trinquete de auditoría.
--
-- Escenario (todas de I1, responsable V1, puerta cartera salvo que se diga; «edad» = actualizado_en):
--   S1  preparada, Avance, número N1                         → la cancela el alta con N1 (motivo numero_contrato_usado)
--   S2  preparada, Avance, número N1                         → también (dos víctimas)
--   S3  preparada, Avance, número N2 (libre)                 → no se toca; después la cancela V1 a mano (camino de hoy, sin motivo)
--   S4  preparada, Avance, número N1, acceso Avance reservado (auth_claim_id) → NUNCA se toca
--   S5  preparada, Avance, número N1, con inversión (inversion_id)           → NUNCA se toca
--   S6  preparada, Prodelco, con el número N1 en sus datos                    → otra empresa: no se toca
--   S7  preparada, Avance, número N1, con fila en private.contrato_altas_idempotentes (ya creó su contrato) → no se toca
--   S8  preparada, Avance, número N1, con un disparador de ensayo que RECHAZA su cancelación → queda preparada y el alta entra
--   S9  cancelada (hoy, sin motivo), Avance, número N1        → no se toca
--   S10 preparada, Avance, número N3, edad 31 días           → la cancela la tarea (sin_movimiento)
--   S11 preparada, Prodelco, sin número, edad 45 días        → también (cualquier empresa)
--   S12 preparada, Avance, número N4, edad 29 días 23 horas  → no (todavía no son 30 días)
--   S13 preparada, Avance, número N5, edad 31 días, acceso Avance reservado → NUNCA
--   S14 preparada, Avance, número EX1 (ya existe un contrato con él), edad 1 día → la cancela la tarea (numero_contrato_usado, vía tarea)
--   S15 preparada, Avance, número EX2, con fila idempotente que apunta a ESE contrato (el reintento de D-57) → no se toca
--   S16 preparada, Avance, número N1: LA CREADORA (el alta manda clave_idempotencia = S16) → no se toca
--   S17 preparada, Avance, número N7, edad 31 días, con origen de REINVERSIÓN (postventa) → medida: lo que decida el disparador
--       de continuidad (cancelada o rechazada), nunca un aborto de la tarea.

set local statement_timeout = '300s';

create temp sequence ens_seq;

-- Identidad de la sesión, en las DOS formas de los claims.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Acumulador del informe: un caso que pasa suma una línea «ok»; uno que falla, un fallo con su texto.
create function pg_temp.reg(p_caso text, p_txt text) returns void language plpgsql as $f$
begin
  if p_txt = '' then
    perform set_config('ensayo.oks', coalesce(current_setting('ensayo.oks', true), '') || 'ok ' || p_caso || E'\n', true);
  else
    perform set_config('ensayo.fallos',
      (coalesce(nullif(current_setting('ensayo.fallos', true), ''), '0')::integer + 1)::text, true);
    perform set_config('ensayo.informe', coalesce(current_setting('ensayo.informe', true), '') || p_txt, true);
  end if;
end;
$f$;

-- Exige una condición: si no se cumple, registra «FALLO <caso>: <detalle>» (el prefijo literal es lo que juzga mutantes.sh).
create function pg_temp.exigir(p_caso text, p_ok boolean, p_detalle text) returns void language plpgsql as $f$
begin
  if coalesce(p_ok, false) then
    perform pg_temp.reg(p_caso, '');
  else
    perform pg_temp.reg(p_caso, format(E'FALLO %s: %s\n', p_caso, p_detalle));
  end if;
end;
$f$;

-- Una medida: no juzga, documenta.
create function pg_temp.medir(p_txt text) returns void language sql as $$
  select set_config('ensayo.medidas', coalesce(current_setting('ensayo.medidas', true), '') || p_txt || E'\n', true);
$$;

-- La fila de una solicitud como JSON (funciona con y sin las columnas nuevas: sin ellas las claves no existen).
create function pg_temp.sol(p_id uuid) returns jsonb language sql as $$
  select to_jsonb(s) from crm.inversion_solicitudes s where s.id = p_id;
$$;

create function pg_temp.g(p_clave text) returns uuid language sql as $$
  select nullif(current_setting('ensayo.' || p_clave, true), '')::uuid;
$$;

-- El p_contrato de un alta (como el ensayo del 2.3).
create function pg_temp.contrato(p_cliente uuid, p_analista uuid, p_numero text) returns jsonb language sql as $$
  select jsonb_build_object('cliente_id', p_cliente, 'capital', 500, 'moneda', 'PEN', 'tasa_anual', 15,
           'modalidad', 'mensual', 'tipo_interes', 'simple',
           'fecha_inicio', (now() at time zone 'America/Lima')::date,
           'fecha_vencimiento', (now() at time zone 'America/Lima')::date + 365,
           'categoria', 'nuevo', 'analista_cierre_id', p_analista, 'numero_contrato', p_numero);
$$;
create function pg_temp.cron() returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('numero_cuota', 1,
           'fecha_programada', (now() at time zone 'America/Lima')::date + 30, 'monto_programado', 100, 'tipo', 'cuota'));
$$;
-- Una cuenta bancaria nueva distinta en cada llamada (solo letras y números, como exige la puerta).
create function pg_temp.cuenta() returns jsonb language plpgsql as $f$
declare v_n integer := nextval('pg_temp.ens_seq');
begin
  return jsonb_build_object('tipo', 'nueva', 'banco', 'BANCO ENS', 'tipo_cuenta', 'ahorros',
    'numero_cuenta', 'ENS' || v_n, 'cci', '0020000000000000' || lpad(v_n::text, 4, '0'), 'titular_distinto', false);
end;
$f$;

-- El alta v2 como el actor (la puerta viva del CRM, concedida a authenticated). 'ok|<respuesta>' o 'SQLSTATE|mensaje|pista'.
-- El bloque con EXCEPTION es una subtransacción: un rechazo deshace TODO lo que la llamada había hecho.
create function pg_temp.llamar(p_actor uuid, p_contrato jsonb) returns text language plpgsql as $f$
declare
  v_r    jsonb;
  v_hint text;
begin
  perform pg_temp.sesion(p_actor);
  perform set_config('crm.producto_condicion_id', '', true);
  v_r := crm.crear_contrato_con_cuenta_pdf_v2(p_contrato, pg_temp.cron(), pg_temp.cuenta());
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_hint, '');
end;
$f$;

-- La consulta de una solicitud como el actor. 'ok|<respuesta>' o 'SQLSTATE|mensaje'.
create function pg_temp.puerta(p_actor uuid, p_solicitud uuid) returns text language plpgsql as $f$
declare v_r jsonb;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.solicitud_inversion_fn(p_solicitud);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- La cancelación de la pantalla como el actor (el camino de hoy). 'ok|<respuesta>' o 'SQLSTATE|mensaje'.
create function pg_temp.cancelar_a_mano(p_actor uuid, p_solicitud uuid, p_revision integer) returns text language plpgsql as $f$
declare v_r jsonb;
begin
  perform pg_temp.sesion(p_actor);
  v_r := crm.cancelar_solicitud_inversion_fn(p_solicitud, p_revision);
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Una llamada dinámica a una pieza que puede no existir (sin la migración). 'ok|<json>' o 'SQLSTATE|mensaje'.
create function pg_temp.pieza(p_sql text) returns text language plpgsql as $f$
declare v_r jsonb;
begin
  execute p_sql into v_r;
  return 'ok|' || coalesce(v_r::text, 'null');
exception when others then
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Ficha de una función (dueño, DEFINER, volatilidad, paralelo, configuración, ACL con opción de concesión).
create function pg_temp.ficha(p_firma text) returns text language sql as $$
  select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || p.proparallel::text
           || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
           || '|' || coalesce((select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text)
                                 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a), '-')
    from pg_proc p where p.oid = to_regprocedure(p_firma);
$$;

-- La foto de lo que la siembra deja (para exigir «no se tocó»).
create temp table ensayo_siembra (nombre text primary key, id uuid not null, estado text not null, actualizado_en timestamptz not null);

-- Siembra una solicitud y guarda su id en el GUC ensayo.<nombre>.
create function pg_temp.sembrar(p_nombre text, p_empresa text, p_numero text, p_estado text, p_edad interval,
                                p_claim boolean default false, p_inversion uuid default null, p_rechazar boolean default false) returns uuid language plpgsql as $f$
declare
  v_id uuid := gen_random_uuid();
  v_i1 uuid := pg_temp.g('i1');
  v_v1 uuid := pg_temp.g('v1');
  v_emp uuid := (select id from crm.empresas where clave = p_empresa);
  v_datos jsonb;
  v_claim uuid := case when p_claim then gen_random_uuid() end;
begin
  -- p_rechazar: la marca que el disparador de ensayo (abajo) usa para negarse a cancelar (como S8, pero por lotes: ronda 4).
  if p_empresa = 'avance' then
    v_datos := jsonb_build_object('inversionista_id', v_i1, 'empresa', 'avance',
      'contrato', jsonb_build_object('capital', 500, 'moneda', 'PEN') || case when p_numero is null then '{}'::jsonb else jsonb_build_object('numero_contrato', p_numero) end,
      'cronograma', jsonb_build_array(), 'cuenta', jsonb_build_object('tipo', 'nueva'));
  else
    v_datos := jsonb_build_object('inversionista_id', v_i1, 'empresa', p_empresa, 'monto', 1000, 'moneda', 'PEN')
      || case when p_numero is null then '{}'::jsonb else jsonb_build_object('contrato', jsonb_build_object('numero_contrato', p_numero)) end;
  end if;
  if p_rechazar then
    v_datos := v_datos || jsonb_build_object('ensayo_rechazar', true);
  end if;
  insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, auth_claim_id, auth_contexto,
      hash_payload, datos, revision_datos, estado, inversion_id, creado_por, creado_en, actualizado_en)
  values (v_id, v_i1, v_emp, v_v1, v_claim, case when p_claim then jsonb_build_object('inversionista_id', v_i1) end,
      encode(sha256(convert_to(v_id::text, 'UTF8')), 'hex'), v_datos, 0, p_estado, p_inversion, v_v1,
      now() - p_edad, now() - p_edad);
  perform set_config('ensayo.' || p_nombre, v_id::text, true);
  insert into ensayo_siembra (nombre, id, estado, actualizado_en) values (p_nombre, v_id, p_estado, now() - p_edad);
  return v_id;
end;
$f$;

-- ── Actores, números y siembra ──────────────────────────────────────────────────────────────────────────────────────────────
do $montaje$
declare
  v_v1 uuid; v_c1 uuid; v_i1 uuid;
  v_ex1 record; v_ex2 record;
  v_inv uuid;
  v_n integer;
  v_k integer := 0;
  v_num text;
  v_cierre uuid;
  v_s uuid;
begin
  select e.perfil_id, c.id, i.id into v_v1, v_c1, v_i1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    join public.perfiles c on c.asesor_perfil_id = e.perfil_id and c.rol = 'cliente' and c.activo and c.dni is not null
    join crm.inversionistas i on i.perfil_id = c.id and i.estado <> 'fusionado'
   where e.rol_crm = 'vendedor' and e.activo and p.activo and p.rol = 'comercial' and private.rol_crm(e.perfil_id) = 'vendedor'
   order by e.perfil_id, c.id, i.id
   limit 1;
  if v_v1 is null then
    raise exception 'MONTAJE: el banco no tiene un vendedor activo (comercial en el Portal, vendedor en crm.equipo) con un cliente activo con documento en su cartera y ficha de inversionista';
  end if;
  perform set_config('ensayo.v1', v_v1::text, true);
  perform set_config('ensayo.c1', v_c1::text, true);
  perform set_config('ensayo.i1', v_i1::text, true);
  if (select count(*) from crm.empresas where clave in ('avance', 'prodelco') and activa) <> 2
     or (select crea_contrato_avance from crm.empresas where clave = 'avance') is not true
     or (select crea_contrato_avance from crm.empresas where clave = 'prodelco') is not false then
    raise exception 'MONTAJE: faltan las empresas avance (crea contrato) y prodelco (no crea contrato) activas';
  end if;

  -- Números libres N1…N7 (serie 2026-01-99NNNN).
  for v_n in 1..7 loop
    loop
      v_k := v_k + 1;
      v_num := '2026-01-99' || lpad(v_k::text, 4, '0');
      exit when not exists (select 1 from public.contratos c where c.numero_contrato = v_num);
    end loop;
    perform set_config('ensayo.n' || v_n, v_num, true);
  end loop;
  -- Dos números YA usados por contratos del banco (los dos más altos de la serie 2026).
  select c.id, c.numero_contrato into v_ex1 from public.contratos c where c.numero_contrato ~ '^2026-01-[0-9]{6}$' order by c.numero_contrato desc, c.id limit 1;
  select c.id, c.numero_contrato into v_ex2 from public.contratos c where c.numero_contrato ~ '^2026-01-[0-9]{6}$' order by c.numero_contrato desc, c.id limit 1 offset 1;
  if v_ex1.id is null or v_ex2.id is null then
    raise exception 'MONTAJE: el banco no tiene dos contratos con número de la serie 2026-01-';
  end if;
  perform set_config('ensayo.ex1_id', v_ex1.id::text, true);
  perform set_config('ensayo.ex1_num', v_ex1.numero_contrato, true);
  perform set_config('ensayo.ex2_id', v_ex2.id::text, true);
  perform set_config('ensayo.ex2_num', v_ex2.numero_contrato, true);
  -- Una inversión libre (sin solicitud que la referencie) para S5.
  select i.id into v_inv from crm.inversiones i
   where not exists (select 1 from crm.inversion_solicitudes s where s.inversion_id = i.id)
   order by i.id limit 1;
  if v_inv is null then
    raise exception 'MONTAJE: el banco no tiene una inversión libre para la guarda «con inversión»';
  end if;
  -- Un cierre externo que NO puede ser origen de una reinversión de Avance: de otra cooperativa, o anulado. Con él, la
  -- continuidad de postventa (private.postventa_fuente: «La inversión de origen no está disponible», P0409) TIENE que negarse a
  -- cancelar S17 (ronda 4, P2-4: expectativa independiente del resultado), y un UPGRADE con el mismo origen (S18) tiene que
  -- poder cancelarse (la guarda deja pasar upgrade preparada → cancelada antes de mirar el origen).
  select c.id into v_cierre from crm.cierres_externos c
   where c.cooperativa <> 'avance' or c.anulado_en is not null
   order by (c.anulado_en is not null), c.id limit 1;
  if v_cierre is null then
    raise exception 'MONTAJE: el banco no tiene un cierre externo de otra cooperativa (o anulado) para un origen de reinversión que deba rechazarse';
  end if;

  -- Siembra.
  perform pg_temp.sembrar('s1',  'avance',   current_setting('ensayo.n1'), 'preparada', interval '2 days');
  perform pg_temp.sembrar('s2',  'avance',   current_setting('ensayo.n1'), 'preparada', interval '1 day');
  perform pg_temp.sembrar('s3',  'avance',   current_setting('ensayo.n2'), 'preparada', interval '3 days');
  perform pg_temp.sembrar('s4',  'avance',   current_setting('ensayo.n1'), 'preparada', interval '2 days', true);
  perform pg_temp.sembrar('s5',  'avance',   current_setting('ensayo.n1'), 'preparada', interval '2 days', false, v_inv);
  perform pg_temp.sembrar('s6',  'prodelco', current_setting('ensayo.n1'), 'preparada', interval '2 days');
  v_s := pg_temp.sembrar('s7',  'avance',   current_setting('ensayo.n1'), 'preparada', interval '2 days');
  insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_v1, v_s, v_ex1.id, md5('ensayo s7'), '{}'::jsonb);
  perform pg_temp.sembrar('s8',  'avance',   current_setting('ensayo.n1'), 'preparada', interval '2 days');
  perform pg_temp.sembrar('s9',  'avance',   current_setting('ensayo.n1'), 'cancelada', interval '2 days');
  perform pg_temp.sembrar('s10', 'avance',   current_setting('ensayo.n3'), 'preparada', interval '31 days');
  perform pg_temp.sembrar('s11', 'prodelco', null,                          'preparada', interval '45 days');
  perform pg_temp.sembrar('s12', 'avance',   current_setting('ensayo.n4'), 'preparada', interval '29 days 23 hours');
  perform pg_temp.sembrar('s13', 'avance',   current_setting('ensayo.n5'), 'preparada', interval '31 days', true);
  perform pg_temp.sembrar('s14', 'avance',   v_ex1.numero_contrato,        'preparada', interval '1 day');
  v_s := pg_temp.sembrar('s15', 'avance',   v_ex2.numero_contrato,        'preparada', interval '1 day');
  insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_v1, v_s, v_ex2.id, md5('ensayo s15'), '{}'::jsonb);
  perform pg_temp.sembrar('s16', 'avance',   current_setting('ensayo.n1'), 'preparada', interval '1 hour');
  v_s := pg_temp.sembrar('s17', 'avance',   current_setting('ensayo.n7'), 'preparada', interval '31 days');
  insert into crm.inversion_solicitud_origenes (solicitud_id, fuente_id, creado_por, tipo) values (v_s, v_cierre, v_v1, 'reinversion');
  -- S18 (ronda 4): un UPGRADE con origen, 31 días: la continuidad lo deja cancelar (debe quedar cancelada por la tarea).
  v_s := pg_temp.sembrar('s18', 'avance',   current_setting('ensayo.n6'), 'preparada', interval '31 days');
  insert into crm.inversion_solicitud_origenes (solicitud_id, fuente_id, creado_por, tipo) values (v_s, v_cierre, v_v1, 'upgrade');
  -- S19 (ronda 4, P2-3): 31 días SIN número pero con memoria idempotente (ya creó su contrato): la pasada de 30 días tiene que
  -- descartarla ANTES del recorrido (no cuenta ni como omitida).
  v_s := pg_temp.sembrar('s19', 'avance',   null,                         'preparada', interval '31 days');
  insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_v1, v_s, v_ex2.id, md5('ensayo s19'), '{}'::jsonb);

  -- El disparador de ensayo: rechaza la cancelación de S8 y de toda solicitud marcada con datos.ensayo_rechazar (simula un
  -- disparador de la tabla que se niega; por lotes en los casos de volumen de la ronda 4).
  execute $t$create function private.ensayo_b215_rechazo() returns trigger language plpgsql as $f$
begin
  if (old.id = current_setting('ensayo.s8', true)::uuid or (old.datos ->> 'ensayo_rechazar') = 'true') and new.estado = 'cancelada' then
    raise exception 'ENSAYO: rechazo forzado de la cancelacion' using errcode = 'P0409';
  end if;
  return new;
end $f$$t$;
  create trigger ensayo_b215_rechazo before update of estado on crm.inversion_solicitudes
    for each row execute function private.ensayo_b215_rechazo();

  -- Mediciones de ANTES.
  perform set_config('ensayo.antes.s3', pg_temp.puerta(v_v1, pg_temp.g('s3')), true);
  perform set_config('ensayo.antes.s1', pg_temp.puerta(v_v1, pg_temp.g('s1')), true);
  begin
    perform private.assert_auditoria();
    perform set_config('ensayo.antes.auditoria', 'pasa', true);
  exception when others then
    perform set_config('ensayo.antes.auditoria', 'cae: ' || sqlstate || ' ' || sqlerrm, true);
  end;
  perform set_config('ensayo.antes.pdf_v2', (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure), true);
  perform set_config('ensayo.antes.consulta', (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.solicitud_inversion_fn(uuid)'::regprocedure), true);
  perform set_config('ensayo.antes.contratos', (select count(*) from public.contratos)::text, true);
end;
$montaje$;

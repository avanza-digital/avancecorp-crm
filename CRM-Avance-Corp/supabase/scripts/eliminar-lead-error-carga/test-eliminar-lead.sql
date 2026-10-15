-- Pruebas de 20261015044917_crm_eliminar_lead_error_carga.sql — SOLO en un banco Docker (esquema de producción, sin
-- datos de personas). Todo dentro de UNA transacción que termina en ROLLBACK: no deja nada escrito.
-- Uso: psql "<banco>" -v ON_ERROR_STOP=1 -f test-eliminar-lead.sql   (como superusuario del banco)
-- Veredicto: la última consulta devuelve una fila por caso (ok = true/false) y un resumen.

begin;
set local search_path = '';
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean) on commit drop;
grant all on table r to public;
grant all on sequence r_n_seq to public;

-- ── Siembra (sin triggers ni FK: replica). Ids fijos; nada de personas reales. ────────────────────────────────────────
set local session_replication_role = replica;
insert into public.perfiles (id, nombre_completo, rol, activo) values
  ('10000000-0000-4000-8000-000000000001', 'PRUEBA GERENCIA', 'analista', true),
  ('10000000-0000-4000-8000-000000000002', 'PRUEBA ADMIN', 'admin', true),
  ('10000000-0000-4000-8000-000000000003', 'PRUEBA VENDEDOR', 'analista', true),
  ('10000000-0000-4000-8000-000000000004', 'PRUEBA SUPERVISOR', 'analista', true),
  ('10000000-0000-4000-8000-000000000005', 'PRUEBA SUPERADMIN', 'superadmin', true),
  ('10000000-0000-4000-8000-000000000006', 'PRUEBA COORDINADOR', 'analista', true),
  ('10000000-0000-4000-8000-000000000007', 'PRUEBA DIRECTORIO', 'analista', true),
  ('10000000-0000-4000-8000-000000000008', 'PRUEBA GERENCIA DE BAJA', 'analista', true),
  ('10000000-0000-4000-8000-000000000009', 'PRUEBA ADMIN INACTIVO', 'admin', false);
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('10000000-0000-4000-8000-000000000001', 'gerencia', true),
  ('10000000-0000-4000-8000-000000000003', 'vendedor', true),
  ('10000000-0000-4000-8000-000000000004', 'supervisor', true),
  ('10000000-0000-4000-8000-000000000006', 'coordinador', true),
  ('10000000-0000-4000-8000-000000000007', 'directorio', true),
  ('10000000-0000-4000-8000-000000000008', 'gerencia', false);

-- L1 válido (con TODO lo que puede colgar), L2 convertido, L3 con contrato, L4 de hace 40 días, L5 con reserva,
-- L6 válido mínimo (para admin), L7 válido (para el mes cerrado), L8 válido (para superadmin), L9 (copias trucadas),
-- L11–L25: un motivo de rechazo aislado cada uno (r2: L12, L18 y L20 ya se pueden borrar). L31–L40: casos de r2.
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, activo, creado_en, contrato_id, convertido_en,
  monto_estimado, moneda)
select ('20000000-0000-4000-8000-' || pg_catalog.lpad(n::text, 12, '0'))::uuid, 'LEAD PRUEBA ' || n,
       '9876543' || pg_catalog.lpad(n::text, 2, '0'), 'oficina',
       case when n = 2 then 'convertido' else 'nuevo' end, '10000000-0000-4000-8000-000000000003', true,
       case when n = 4 then pg_catalog.now() - interval '40 days' else pg_catalog.now() - interval '2 days' end,
       case when n = 3 then '30000000-0000-4000-8000-000000000003'::uuid end,
       case when n = 2 then pg_catalog.now() - interval '1 day' end, 10000, 'PEN'
from pg_catalog.generate_series(1, 58) n;

insert into crm.lead_asignaciones (id, lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
  resultado, resultado_en, finalizado_en, finalizado_por, motivo_cierre,
  sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en)
select ('40000000-0000-4000-8000-' || pg_catalog.lpad(n::text, 12, '0'))::uuid,
       ('20000000-0000-4000-8000-' || pg_catalog.lpad(n::text, 12, '0'))::uuid, 1, 1,
       '10000000-0000-4000-8000-000000000003', 'ingreso', pg_catalog.now() - interval '2 days', 'PEN', 'oficina',
       case when n in (2, 13) then 'convertido' end, case when n in (2, 13) then pg_catalog.now() - interval '1 day' end,
       case when n in (2, 13) then pg_catalog.now() - interval '1 day' end,
       case when n in (2, 13) then '10000000-0000-4000-8000-000000000003'::uuid end,
       case when n in (2, 13) then 'convertido' end, pg_catalog.now() - interval '2 days', '50000000-0000-4000-8000-000000000001',
       pg_catalog.now(), pg_catalog.now()
from pg_catalog.generate_series(1, 58) n;
insert into crm.lead_asignacion_sla_hitos (id, lead_asignacion_id, primera_gestion_en)
values ('41000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', pg_catalog.now() - interval '1 day');
insert into crm.lead_sla_ciclos (id, lead_id, ciclo_n, politica_id, iniciado_en, primera_gestion_limite_en, primer_contacto_limite_en)
values ('42000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 1,
        '50000000-0000-4000-8000-000000000001', pg_catalog.now() - interval '2 days', pg_catalog.now(), pg_catalog.now());
insert into crm.lead_sla_etapas (id, lead_id, ciclo_n, episodio_n, etapa, politica_id, iniciado_en, limite_en)
values ('43000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 1, 1, 'nuevo',
        '50000000-0000-4000-8000-000000000001', pg_catalog.now() - interval '2 days', pg_catalog.now());
insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por) values
  ('44000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'llamada_realizada', 'prueba',
   '{}', '10000000-0000-4000-8000-000000000003'),
  ('44000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', 'nota', 'veto',
   '{"evento":"no_contactar"}', '10000000-0000-4000-8000-000000000003');
insert into crm.lead_sla_etapa_ajustes (id, etapa_sla_id, origen_actividad_id, secuencia, minutos_reales, limite_antes,
  limite_despues, creado_por)
values ('45000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000001',
        '44000000-0000-4000-8000-000000000001', 1, 30, pg_catalog.now(), pg_catalog.now() + interval '30 minutes',
        '10000000-0000-4000-8000-000000000003');
insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en, resultado_actividad_id, estado) values
  ('46000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003',
   'llamada', 'Llamar', pg_catalog.now(), '44000000-0000-4000-8000-000000000001', 'completada');
insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en, reagendada_de) values
  ('46000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003',
   'llamada', 'Llamar otra vez', pg_catalog.now(), '46000000-0000-4000-8000-000000000001');
insert into crm.tarea_sla_contexto (tarea_id, lead_id, ciclo_n, fuente)
values ('46000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 1, 'evento');
insert into crm.sla_operacion_recibos (actor_id, operacion_id, lead_id, sujeto_id, comando, payload)
values ('10000000-0000-4000-8000-000000000003', '47000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'registrar_actividad', '{}');
insert into crm.lead_potencial_eventos (id, lead_id, nivel_nuevo, motivo)
select '48000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', e.enumlabel::crm.nivel_potencial, 'caducidad'
from pg_catalog.pg_enum e where e.enumtypid = 'crm.nivel_potencial'::regtype order by e.enumsortorder limit 1;
insert into crm.llamadas_celular_eventos (id, asignacion_id, analista_id, evento_origen_id, identificacion, atencion, lead_id,
  metodo_asociacion, asociado_en)
values ('49000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001',
        '10000000-0000-4000-8000-000000000003', 'C1-0000000001', 'identificado', 'registrado',
        '20000000-0000-4000-8000-000000000001', 'exacto', pg_catalog.now());
insert into crm.llamadas_celular_enlaces (id, evento_id, actividad_id, lead_id)
values ('4a000000-0000-4000-8000-000000000001', '49000000-0000-4000-8000-000000000001',
        '44000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001');
insert into private.llamadas_celular_intenciones (id, evento_origen_id, analista_id, lead_id, actividad_id, via)
values ('4b000000-0000-4000-8000-000000000001', 'C1-0000000001', '10000000-0000-4000-8000-000000000003',
        '20000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', 'al_colgar');
insert into crm.conversion_reservas (lead_id, reservado_por, expira_en, vence_absoluto_en)
values ('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000003', pg_catalog.now() + interval '1 hour',
        pg_catalog.now() + interval '1 day');

-- Siembra genérica: columnas dadas + relleno de las NOT NULL sin default (para tablas de negocio de los rechazos).
-- ANDAMIO: para sembrar una fila mínima retira los CHECK de esa tabla DENTRO de esta transacción, que termina en
-- ROLLBACK (no persiste nada). La puerta solo pregunta si la fila existe; sus CHECK no intervienen.
create function pg_temp.sembrar(p_tabla regclass, p_vals jsonb) returns text language plpgsql as $s$
declare v_cols text[] := '{}'; v_exprs text[] := '{}'; r record; k text;
begin
  for r in select c.conname from pg_catalog.pg_constraint c where c.conrelid = p_tabla and c.contype = 'c' loop
    execute pg_catalog.format('alter table %s drop constraint %I', p_tabla, r.conname);
  end loop;
  for k in select pg_catalog.jsonb_object_keys(p_vals) loop
    v_cols := v_cols || pg_catalog.quote_ident(k);
    v_exprs := v_exprs || pg_catalog.format('(%L::jsonb ->> %L)::%s', p_vals, k,
      (select pg_catalog.format_type(a.atttypid, a.atttypmod) from pg_catalog.pg_attribute a
       where a.attrelid = p_tabla and a.attname = k));
  end loop;
  for r in select a.attname, a.atttypid, pg_catalog.format_type(a.atttypid, a.atttypmod) as t, ty.typtype
           from pg_catalog.pg_attribute a join pg_catalog.pg_type ty on ty.oid = a.atttypid
           where a.attrelid = p_tabla and a.attnum > 0 and not a.attisdropped and a.attnotnull and not a.atthasdef
             and a.attidentity = '' and a.attgenerated = '' and not (p_vals ? a.attname::text) loop
    v_cols := v_cols || pg_catalog.quote_ident(r.attname);
    v_exprs := v_exprs || case
      when r.t = 'uuid' then 'pg_catalog.gen_random_uuid()'
      when r.t like 'timestamp%' then 'pg_catalog.now()'
      when r.t = 'date' then 'current_date'
      when r.t in ('integer', 'bigint', 'smallint') or r.t like 'numeric%' then '1'
      when r.t = 'boolean' then 'false'
      when r.t in ('jsonb', 'json') then '''{}'''
      when r.t like '%[]' then '''{}'''
      when r.typtype = 'e' then pg_catalog.format(
        '(select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = %s order by e.enumsortorder limit 1)::%s',
        r.atttypid, r.t)
      else '''x''' end;
  end loop;
  execute pg_catalog.format('insert into %s (%s) values (%s)', p_tabla, pg_catalog.array_to_string(v_cols, ','),
                            pg_catalog.array_to_string(v_exprs, ','));
  return 'ok';
exception when others then return sqlstate || ' ' || sqlerrm;
end $s$;
create temp table siembra (caso text primary key, resultado text) on commit drop;
grant all on table siembra to public;

-- L1: también base cargada, potencial y actividad de cliente sobre su tarea.
insert into siembra values
  ('L1 base_carga_leads', pg_temp.sembrar('crm.base_carga_leads', '{"lead_id":"20000000-0000-4000-8000-000000000001"}')),
  ('L1 lead_potencial', pg_temp.sembrar('crm.lead_potencial', '{"lead_id":"20000000-0000-4000-8000-000000000001"}')),
  ('L1 actividades_cliente', pg_temp.sembrar('crm.actividades_cliente',
     '{"tarea_id":"46000000-0000-4000-8000-000000000001","tipo":"nota"}'));
-- L9: un ciclo SLA solo (para las copias trucadas).
insert into crm.lead_sla_ciclos (id, lead_id, ciclo_n, politica_id, iniciado_en, primera_gestion_limite_en,
  primer_contacto_limite_en, aproximado)
values ('42000000-0000-4000-8000-000000000009', '20000000-0000-4000-8000-000000000009', 1,
        '50000000-0000-4000-8000-000000000001', pg_catalog.now() - interval '2 days', pg_catalog.now(), pg_catalog.now(), false);
-- L11–L25: un motivo de rechazo cada uno.
update crm.leads set perfil_id = '60000000-0000-4000-8000-000000000011' where id = '20000000-0000-4000-8000-000000000011';
update crm.leads set inversionista_id = '60000000-0000-4000-8000-000000000012' where id = '20000000-0000-4000-8000-000000000012';
insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en) values
  ('46000000-0000-4000-8000-000000000023', '20000000-0000-4000-8000-000000000023',
   '10000000-0000-4000-8000-000000000003', 'llamada', 'T23', pg_catalog.now()),
  ('46000000-0000-4000-8000-000000000024', '20000000-0000-4000-8000-000000000024',
   '10000000-0000-4000-8000-000000000003', 'llamada', 'T24', pg_catalog.now());
insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en, reagendada_de) values
  ('46000000-0000-4000-8000-000000000025', '20000000-0000-4000-8000-000000000025',
   '10000000-0000-4000-8000-000000000003', 'llamada', 'T25', pg_catalog.now(), '46000000-0000-4000-8000-000000000024');
insert into siembra values
  ('L14 cierres_externos', pg_temp.sembrar('crm.cierres_externos', '{"lead_id":"20000000-0000-4000-8000-000000000014"}')),
  ('L15 conversion_acreditaciones', pg_temp.sembrar('crm.conversion_acreditaciones',
     '{"lead_id":"20000000-0000-4000-8000-000000000015","episodio_id":"40000000-0000-4000-8000-000000000015"}')),
  ('L16 cierres_avance_anulados', pg_temp.sembrar('crm.cierres_avance_anulados', '{"lead_id":"20000000-0000-4000-8000-000000000016"}')),
  ('L17 ajustes_mes_cerrado', pg_temp.sembrar('crm.ajustes_mes_cerrado', '{"lead_id":"20000000-0000-4000-8000-000000000017"}')),
  ('L18 solicitudes_tasa', pg_temp.sembrar('crm.solicitudes_tasa', '{"id":"63000000-0000-4000-8000-000000000018","lead_id":"20000000-0000-4000-8000-000000000018","estado":"pendiente","categoria":"nuevo"}')),
  ('L18 envio push', pg_temp.sembrar('crm.envios_push_tasa', '{"solicitud_id":"63000000-0000-4000-8000-000000000018"}')),
  ('L19 inversion_solicitudes', pg_temp.sembrar('crm.inversion_solicitudes', '{"lead_origen_id":"20000000-0000-4000-8000-000000000019"}')),
  ('L20 inversionista_leads', pg_temp.sembrar('crm.inversionista_leads', '{"lead_id":"20000000-0000-4000-8000-000000000020"}')),
  ('L21 inversionista_operaciones', pg_temp.sembrar('crm.inversionista_operaciones', '{"lead_id":"20000000-0000-4000-8000-000000000021"}')),
  ('L22 busquedas_cliente_existente', pg_temp.sembrar('crm.busquedas_cliente_existente', '{"lead_id":"20000000-0000-4000-8000-000000000022"}')),
  ('L23 inversionista_gestiones', pg_temp.sembrar('crm.inversionista_gestiones', '{"tarea_id":"46000000-0000-4000-8000-000000000023"}'));
set local session_replication_role = origin;

-- ── Ayudante: llama a la puerta COMO un usuario (rol authenticated + JWT) y anota el resultado ────────────────────────
create function pg_temp.probar(p_caso text, p_actor uuid, p_lead uuid, p_motivo text, p_esperado text)
returns void language plpgsql as $$
declare v_res jsonb; v_obt text;
begin
  begin
    perform pg_catalog.set_config('request.jwt.claims',
      pg_catalog.json_build_object('sub', p_actor, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true);
    execute 'set local role authenticated';
    v_res := crm.eliminar_lead_error_carga(p_lead, p_motivo);
    v_obt := 'OK ' || coalesce(v_res ->> 'ok', '?');
    raise exception using errcode = 'XX999', message = v_obt;   -- deshace la llamada si no se espera OK… salvo abajo
  exception when others then
    v_obt := case when sqlstate = 'XX999' then sqlerrm else sqlstate || ' ' || sqlerrm end;
  end;
  insert into pg_temp.r (caso, esperado, obtenido, ok) values (p_caso, p_esperado, v_obt, v_obt ~ ('^(' || p_esperado || ')'));
end $$;

-- Igual que probar() pero CONSERVA el efecto (para el borrado válido que se inspecciona después).
create function pg_temp.ejecutar(p_caso text, p_actor uuid, p_lead uuid, p_motivo text)
returns jsonb language plpgsql as $$
declare v_res jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claims',
    pg_catalog.json_build_object('sub', p_actor, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v_res := crm.eliminar_lead_error_carga(p_lead, p_motivo);
  execute 'reset role';
  -- La sesión simulada no debe filtrarse a los casos siguientes (los candados miran auth.uid()).
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  insert into pg_temp.r (caso, esperado, obtenido, ok) values (p_caso, 'OK', v_res::text, coalesce((v_res ->> 'ok')::boolean, false));
  return v_res;
end $$;

-- Intenta un DELETE directo (sin la puerta) y anota si lo frenó el candado.
create function pg_temp.borrar_directo(p_caso text, p_sql text, p_esperado text)
returns void language plpgsql as $$
declare v_obt text; v_n bigint;
begin
  begin
    execute p_sql;
    get diagnostics v_n = row_count;
    v_obt := 'BORRÓ ' || v_n;
    raise exception using errcode = 'XX999', message = v_obt;
  exception when others then
    v_obt := case when sqlstate = 'XX999' then sqlerrm else sqlstate || ' ' || sqlerrm end;
  end;
  insert into pg_temp.r (caso, esperado, obtenido, ok) values (p_caso, p_esperado, v_obt, v_obt ~ ('^(' || p_esperado || ')'));
end $$;

-- ── 1 · Roles ─────────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.probar('vendedor → 42501', '10000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000001', 'cargado por error en prueba', '42501');
select pg_temp.probar('supervisor → 42501', '10000000-0000-4000-8000-000000000004',
  '20000000-0000-4000-8000-000000000001', 'cargado por error en prueba', '42501');
select pg_temp.probar('sin sesión → 42501', null,
  '20000000-0000-4000-8000-000000000001', 'cargado por error en prueba', '42501');
select pg_temp.probar('coordinador → 42501', '10000000-0000-4000-8000-000000000006',
  '20000000-0000-4000-8000-000000000001', 'cargado por error en prueba', '42501');
select pg_temp.probar('directorio → 42501', '10000000-0000-4000-8000-000000000007',
  '20000000-0000-4000-8000-000000000001', 'cargado por error en prueba', '42501');
select pg_temp.probar('gerencia dada de baja en el CRM → 42501', '10000000-0000-4000-8000-000000000008',
  '20000000-0000-4000-8000-000000000001', 'cargado por error en prueba', '42501');
select pg_temp.probar('admin del portal inactivo → 42501', '10000000-0000-4000-8000-000000000009',
  '20000000-0000-4000-8000-000000000001', 'cargado por error en prueba', '42501');
select pg_temp.probar('gerencia, motivo de 501 → 22023', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', pg_catalog.repeat('a', 501), '22023');
select pg_temp.probar('gerencia, motivo nulo → 22023', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', null, '22023');
select pg_temp.probar('gerencia, lead nulo → 22023', '10000000-0000-4000-8000-000000000001',
  null, 'cargado por error en prueba', '22023');
select pg_temp.probar('gerencia, motivo corto → 22023', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', '   corto   ', '22023');

-- ── 2 · Rechazos ─────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.probar('con conversión → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000002', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: tiene una conversión');
select pg_temp.probar('con contrato → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000003', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: tiene un contrato');
select pg_temp.probar('de hace 40 días → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000004', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: se creó hace más de 30 días');
select pg_temp.probar('con reserva de conversión → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000005', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: tiene una reserva');
select pg_temp.probar('no existe → P0002', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-0000000000ff', 'cargado por error en prueba', 'P0002');
-- Cada motivo de rechazo, aislado en su propio lead. Si la siembra de su tabla falló, el caso queda NOT RUN (ok nulo).
create function pg_temp.rechazo(p_n int, p_siembra text, p_msg text) returns void language plpgsql as $s$
declare v_s text;
begin
  if p_siembra is not null then
    select s.resultado into v_s from pg_temp.siembra s where s.caso = p_siembra;
    if v_s is distinct from 'ok' then
      insert into pg_temp.r (caso, esperado, obtenido, ok)
      values ('L' || p_n || ' → ' || p_msg, 'P0409', 'NOT RUN · siembra: ' || coalesce(v_s, 'sin fila'), null);
      return;
    end if;
  end if;
  perform pg_temp.probar('L' || p_n || ' → ' || p_msg, '10000000-0000-4000-8000-000000000001',
    ('20000000-0000-4000-8000-' || pg_catalog.lpad(p_n::text, 12, '0'))::uuid, 'cargado por error en prueba',
    'P0409 No se puede eliminar este lead: .*' || p_msg);
end $s$;
select pg_temp.rechazo(11, null, 'está enlazado a un perfil de cliente');
-- r2: una ficha de inversionista sin dinero ya no frena (se borra con el lead); ver también el bloque 2b.
select pg_temp.probar('L12 con ficha sin dinero → se borra (r2)', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000012', 'cargado por error en prueba', 'OK true');
select pg_temp.rechazo(13, null, 'tiene una conversión registrada');
select pg_temp.rechazo(14, 'L14 cierres_externos', 'tiene un cierre en cooperativa');
select pg_temp.rechazo(15, 'L15 conversion_acreditaciones', 'tiene una conversión acreditada');
select pg_temp.rechazo(16, 'L16 cierres_avance_anulados', 'tiene un cierre anulado');
select pg_temp.rechazo(17, 'L17 ajustes_mes_cerrado', 'tiene un ajuste de mes cerrado');
select pg_temp.probar('L18 con solicitud de tasa sin usar → se borra (r2)', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000018', 'cargado por error en prueba', 'OK true');
select pg_temp.rechazo(19, 'L19 inversion_solicitudes', 'tiene una solicitud de inversión en curso');
select pg_temp.probar('L20 con enlace a ficha sin dinero → se borra (r2)', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000020', 'cargado por error en prueba', 'OK true');
select pg_temp.rechazo(21, 'L21 inversionista_operaciones', 'tiene operaciones de inversionista registradas');
select pg_temp.rechazo(22, 'L22 busquedas_cliente_existente', 'tiene búsquedas de cliente existente registradas');
select pg_temp.rechazo(23, 'L23 inversionista_gestiones', 'tiene gestiones de inversionista');
select pg_temp.rechazo(24, null, 'otro lead tiene tareas o llamadas enlazadas a las suyas');

-- ── 2b · r2 (20261015150731): fichas de inversionista, solicitudes de inversión y de tasa ────────────────────────────
-- Siembra (sin triggers ni FK). L31: ficha exclusiva y sin dinero con TODO lo que puede colgarle → se borra completa.
-- L32/L33: ficha compartida. L34: con inversión. L35: fusionada. L36: con perfil. L37: con tarea de inversionista.
-- L38: solicitud cancelada con revisión. L39: tasa consumida. L40: tasa con movimiento de rentabilidad.
set local session_replication_role = replica;
insert into pg_temp.siembra values
  ('I31 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000031"}')),
  ('I31 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000031","lead_id":"20000000-0000-4000-8000-000000000031"}')),
  ('I31 identificador', pg_temp.sembrar('crm.inversionista_identificadores', '{"inversionista_id":"61000000-0000-4000-8000-000000000031"}')),
  ('I31 responsable', pg_temp.sembrar('crm.inversionista_responsables', '{"inversionista_id":"61000000-0000-4000-8000-000000000031"}')),
  ('I31 gestion', pg_temp.sembrar('crm.inversionista_gestiones', '{"inversionista_id":"61000000-0000-4000-8000-000000000031"}')),
  ('I31 lectura', pg_temp.sembrar('crm.cartera_lecturas', '{"inversionista_id":"61000000-0000-4000-8000-000000000031"}')),
  ('I31 contacto', pg_temp.sembrar('crm.inversionista_datos_contacto', '{"inversionista_id":"61000000-0000-4000-8000-000000000031"}')),
  ('I31 solicitud cancelada', pg_temp.sembrar('crm.inversion_solicitudes', '{"inversionista_id":"61000000-0000-4000-8000-000000000031","lead_origen_id":"20000000-0000-4000-8000-000000000031","estado":"cancelada"}')),
  ('I32 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000032"}')),
  ('I32 enlace L32', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000032","lead_id":"20000000-0000-4000-8000-000000000032"}')),
  ('I32 enlace L33', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000032","lead_id":"20000000-0000-4000-8000-000000000033","rol":"historico"}')),
  ('I34 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000034"}')),
  ('I34 inversion', pg_temp.sembrar('crm.inversiones', '{"inversionista_id":"61000000-0000-4000-8000-000000000034"}')),
  ('I35 ficha fusionada', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000035","inversionista_canonico_id":"61000000-0000-4000-8000-000000000034"}')),
  ('I36 ficha con perfil', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000036","perfil_id":"10000000-0000-4000-8000-000000000001"}')),
  ('I37 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000037"}')),
  ('I37 tarea', pg_temp.sembrar('crm.tareas', '{"inversionista_id":"61000000-0000-4000-8000-000000000037","tipo":"llamada","titulo":"postventa"}')),
  ('S38 solicitud cancelada', pg_temp.sembrar('crm.inversion_solicitudes', '{"id":"62000000-0000-4000-8000-000000000038","lead_origen_id":"20000000-0000-4000-8000-000000000038","estado":"cancelada"}')),
  ('S38 revision', pg_temp.sembrar('crm.inversion_solicitud_revisiones', '{"solicitud_id":"62000000-0000-4000-8000-000000000038"}')),
  ('T39 tasa consumida', pg_temp.sembrar('crm.solicitudes_tasa', '{"id":"63000000-0000-4000-8000-000000000039","lead_id":"20000000-0000-4000-8000-000000000039","estado":"consumida"}')),
  ('T40 tasa', pg_temp.sembrar('crm.solicitudes_tasa', '{"id":"63000000-0000-4000-8000-000000000040","lead_id":"20000000-0000-4000-8000-000000000040","estado":"rechazada"}')),
  ('T40 ledger', pg_temp.sembrar('crm.ledger_rentabilidad', '{"solicitud_id":"63000000-0000-4000-8000-000000000040"}'));
update crm.leads set inversionista_id = '61000000-0000-4000-8000-000000000031' where id = '20000000-0000-4000-8000-000000000031';
update crm.leads set inversionista_id = '61000000-0000-4000-8000-000000000034' where id = '20000000-0000-4000-8000-000000000034';
update crm.leads set inversionista_id = '61000000-0000-4000-8000-000000000035' where id = '20000000-0000-4000-8000-000000000035';
update crm.leads set inversionista_id = '61000000-0000-4000-8000-000000000036' where id = '20000000-0000-4000-8000-000000000036';
update crm.leads set inversionista_id = '61000000-0000-4000-8000-000000000037' where id = '20000000-0000-4000-8000-000000000037';
set local session_replication_role = origin;
-- Si una siembra falla, el caso que depende de ella no prueba nada: se registra como FALLO.
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'siembra r2: ' || s.caso, 'ok', s.resultado, false from pg_temp.siembra s
where (s.caso like 'I3%' or s.caso like 'S3%' or s.caso like 'T%' or s.caso like 'L18 %') and s.resultado <> 'ok';

-- Rechazos r2.
select pg_temp.probar('L32 ficha compartida → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000032', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*también pertenece a otro lead');
select pg_temp.probar('L34 ficha con inversión → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000034', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*tiene inversiones o cierres');
select pg_temp.probar('L35 ficha fusionada → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000035', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*está fusionada con otra');
select pg_temp.probar('L36 ficha con perfil de cliente → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000036', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*tiene acceso de cliente');
select pg_temp.probar('L37 ficha con tarea propia → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000037', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*tiene historia propia');
select pg_temp.probar('L38 solicitud cancelada con revisión → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000038', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*con revisiones o fuentes');
select pg_temp.probar('L39 tasa consumida → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000039', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*solicitud de tasa ya usada');
select pg_temp.probar('L40 tasa con movimiento de rentabilidad → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000040', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*solicitud de tasa ya usada');
-- Sin la puerta, la solicitud de tasa sigue sin poder borrarse.
select pg_temp.borrar_directo('directo solicitudes_tasa', $q$delete from crm.solicitudes_tasa where id = '63000000-0000-4000-8000-000000000039'$q$, 'P0409 Una solicitud de tasa no se borra');

-- L31: ficha exclusiva y sin dinero → se borra el lead con su ficha y todo lo que le cuelga, con copia.
select pg_temp.ejecutar('L31 con ficha exclusiva se borra completa', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000031', 'Ficha creada por un registro que no se completó');
reset role;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'L31: ficha y anexos borrados', '0', v.n::text, v.n = 0
from (select (select pg_catalog.count(*) from crm.inversionistas where id = '61000000-0000-4000-8000-000000000031')
           + (select pg_catalog.count(*) from crm.inversionista_leads where inversionista_id = '61000000-0000-4000-8000-000000000031')
           + (select pg_catalog.count(*) from crm.inversionista_identificadores where inversionista_id = '61000000-0000-4000-8000-000000000031')
           + (select pg_catalog.count(*) from crm.inversionista_responsables where inversionista_id = '61000000-0000-4000-8000-000000000031')
           + (select pg_catalog.count(*) from crm.inversionista_gestiones where inversionista_id = '61000000-0000-4000-8000-000000000031')
           + (select pg_catalog.count(*) from crm.cartera_lecturas where inversionista_id = '61000000-0000-4000-8000-000000000031')
           + (select pg_catalog.count(*) from crm.inversionista_datos_contacto where inversionista_id = '61000000-0000-4000-8000-000000000031')
           + (select pg_catalog.count(*) from crm.inversion_solicitudes where inversionista_id = '61000000-0000-4000-8000-000000000031')
           + (select pg_catalog.count(*) from crm.leads where id = '20000000-0000-4000-8000-000000000031') n) v;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'L31: copia con la ficha y sus 8 anexos', 'version 2 · 1 de cada', e.filas::text,
       (e.copia ->> 'version') = '2'
       and (e.filas ->> 'inversionistas')::int = 1 and (e.filas ->> 'inversionista_leads')::int = 1
       and (e.filas ->> 'inversionista_identificadores')::int = 1 and (e.filas ->> 'inversionista_responsables')::int = 1
       and (e.filas ->> 'inversionista_gestiones')::int = 1 and (e.filas ->> 'cartera_lecturas')::int = 1
       and (e.filas ->> 'inversionista_datos_contacto')::int = 1 and (e.filas ->> 'inversion_solicitudes')::int = 1
from crm.leads_eliminados e where e.lead_id = '20000000-0000-4000-8000-000000000031';
-- Las fichas que NO se podían borrar siguen ahí.
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'fichas rechazadas intactas', '5', v.n::text, v.n = 5
from (select pg_catalog.count(*) n from crm.inversionistas
      where id in ('61000000-0000-4000-8000-000000000032', '61000000-0000-4000-8000-000000000034',
                   '61000000-0000-4000-8000-000000000035', '61000000-0000-4000-8000-000000000036',
                   '61000000-0000-4000-8000-000000000037')) v;

-- ── 2c · r2 tras revisión (auditor-rls + Codex): pertenencia, cliente, ficha preexistente, saga, veto, historia ─────────
set local session_replication_role = replica;
insert into pg_temp.siembra values
  ('S41 solicitud de otra persona', pg_temp.sembrar('crm.inversion_solicitudes', '{"lead_origen_id":"20000000-0000-4000-8000-000000000041","inversionista_id":"61000000-0000-4000-8000-000000000034","estado":"cancelada"}')),
  ('I42 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000042"}')),
  ('I42 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000042","lead_id":"20000000-0000-4000-8000-000000000042","rol":"canonico"}')),
  ('S42 solicitud de otro lead', pg_temp.sembrar('crm.inversion_solicitudes', '{"lead_origen_id":"20000000-0000-4000-8000-000000000043","inversionista_id":"61000000-0000-4000-8000-000000000042","estado":"cancelada"}')),
  ('T44 tasa de cliente', pg_temp.sembrar('crm.solicitudes_tasa', '{"lead_id":"20000000-0000-4000-8000-000000000044","estado":"rechazada","cliente_id":"10000000-0000-4000-8000-000000000003","categoria":"nuevo"}')),
  ('I45 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000045"}')),
  ('I45 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000045","lead_id":"20000000-0000-4000-8000-000000000045","rol":"canonico"}')),
  ('S45 cancelada que fue confirmada', pg_temp.sembrar('crm.inversion_solicitudes', '{"lead_origen_id":"20000000-0000-4000-8000-000000000045","inversionista_id":"61000000-0000-4000-8000-000000000045","estado":"cancelada","confirmado_por":"10000000-0000-4000-8000-000000000001"}')),
  ('I46 ficha preexistente', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000046","creado_en":"2026-01-01T00:00:00Z"}')),
  ('I46 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000046","lead_id":"20000000-0000-4000-8000-000000000046","rol":"canonico"}')),
  ('I47 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000047"}')),
  ('I47 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000047","lead_id":"20000000-0000-4000-8000-000000000047","rol":"canonico"}')),
  ('I47 saga', pg_temp.sembrar('crm.multiempresa_idempotencia', '{"clave":"auth_persona:61000000-0000-4000-8000-000000000047","tipo":"alta_cliente"}')),
  ('I48 ficha con veto', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000048","no_contactar":true}')),
  ('I48 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000048","lead_id":"20000000-0000-4000-8000-000000000048","rol":"canonico"}')),
  ('I49 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000049"}')),
  ('I49 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000049","lead_id":"20000000-0000-4000-8000-000000000049","rol":"canonico"}')),
  ('I49 reserva', pg_temp.sembrar('crm.conversion_reservas', '{"inversionista_id":"61000000-0000-4000-8000-000000000049","lead_id":"20000000-0000-4000-8000-000000000050"}')),
  ('I51 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000051"}')),
  ('I51 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000051","lead_id":"20000000-0000-4000-8000-000000000051","rol":"canonico"}')),
  ('I51 identificador', pg_temp.sembrar('crm.inversionista_identificadores', '{"id":"64000000-0000-4000-8000-000000000051","inversionista_id":"61000000-0000-4000-8000-000000000051","documento_normalizado":"10000051"}')),
  ('I51 cotitular', pg_temp.sembrar('crm.inversion_cotitular_origenes', '{"identificador_origen_id":"64000000-0000-4000-8000-000000000051"}')),
  ('I52 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000052"}')),
  ('I52 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000052","lead_id":"20000000-0000-4000-8000-000000000052","rol":"canonico"}')),
  ('I52 identificador', pg_temp.sembrar('crm.inversionista_identificadores', '{"id":"64000000-0000-4000-8000-000000000052","inversionista_id":"61000000-0000-4000-8000-000000000052","documento_normalizado":"10000052"}')),
  ('I52 operacion', pg_temp.sembrar('crm.inversionista_operaciones', '{"identificador_nuevo_id":"64000000-0000-4000-8000-000000000052"}')),
  ('I53 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000053"}')),
  ('I53 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000053","lead_id":"20000000-0000-4000-8000-000000000053","rol":"canonico"}')),
  ('I53 backfill', pg_temp.sembrar('crm.backfill_multiempresa_mapa', '{"inversionista_id":"61000000-0000-4000-8000-000000000053"}')),
  ('I54 ficha', pg_temp.sembrar('crm.inversionistas', '{"id":"61000000-0000-4000-8000-000000000054"}')),
  ('I54 enlace', pg_temp.sembrar('crm.inversionista_leads', '{"inversionista_id":"61000000-0000-4000-8000-000000000054","lead_id":"20000000-0000-4000-8000-000000000054","rol":"canonico"}')),
  ('I54 otra ficha fusionada en ella', pg_temp.sembrar('crm.inversionistas', '{"inversionista_canonico_id":"61000000-0000-4000-8000-000000000054"}'));
set local session_replication_role = origin;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'siembra 2c: ' || s.caso, 'ok', s.resultado, false from pg_temp.siembra s
where (s.caso ~ '^(S4|I4|I5|T44)') and s.resultado <> 'ok';

select pg_temp.probar('L41 solicitud de otra persona → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000041', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*solicitud de inversión de otra persona');
select pg_temp.probar('L42 ficha con solicitud de otro lead → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000042', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*tiene solicitudes de otro lead');
select pg_temp.probar('L44 tasa de un cliente → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000044', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*solicitud de tasa de un cliente');
select pg_temp.probar('L45 solicitud cancelada que fue confirmada → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000045', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*solicitud de inversión en curso');
select pg_temp.probar('L46 ficha anterior al lead → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000046', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*ya existía antes del lead');
select pg_temp.probar('L47 ficha con alta al portal en proceso → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000047', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*alta al portal en proceso');
select pg_temp.probar('L48 persona pidió no ser contactada → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000048', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*pidió no ser contactada');
select pg_temp.probar('L49 ficha con reserva de conversión → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000049', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*tiene inversiones o cierres');
select pg_temp.probar('L51 identificador usado como cotitular → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000051', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*tiene historia propia');
select pg_temp.probar('L52 identificador en una operación → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000052', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*tiene historia propia');
select pg_temp.probar('L53 ficha en el mapa de backfill → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000053', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*tiene historia propia');
select pg_temp.probar('L54 otra ficha fusionada en la suya → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000054', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*está fusionada con otra');

-- El candado de tasa con la excepción: el permiso puesto a mano sin copia no abre; una copia trucada solo abre con todo
-- en regla (control positivo) y no desde otra transacción.
select pg_temp.borrar_directo('tasa: permiso a mano sin copia', $q$do $d$ begin perform set_config('crm.borrado_lead_error', '20000000-0000-4000-8000-000000000039', true); perform set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true); delete from crm.solicitudes_tasa where id = '63000000-0000-4000-8000-000000000039'; end $d$$q$, 'P0409 Una solicitud de tasa no se borra');
create function pg_temp.trucar_tasa(p_caso text, p_tx text, p_esperado text) returns void language plpgsql as $s$
declare v_fila jsonb;
begin
  select pg_catalog.to_jsonb(t) into v_fila from crm.solicitudes_tasa t where t.id = '63000000-0000-4000-8000-000000000039';
  perform pg_temp.borrar_directo(p_caso, pg_catalog.format($q$do $d$ begin
      insert into crm.leads_eliminados (lead_id, motivo, eliminado_por, rol_actor, copia, filas, transaccion)
      values ('20000000-0000-4000-8000-000000000039', 'motivo de prueba', '10000000-0000-4000-8000-000000000001', 'gerencia',
              %L, '{}', coalesce(%L::xid8, pg_catalog.pg_current_xact_id()));
      perform pg_catalog.set_config('crm.borrado_lead_error', '20000000-0000-4000-8000-000000000039', true);
      perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
      delete from crm.solicitudes_tasa where id = '63000000-0000-4000-8000-000000000039';
      if not found then raise exception 'NO BORRÓ'; end if;
    end $d$$q$, pg_catalog.jsonb_build_object('lead', '{}'::jsonb, 'solicitudes_tasa', pg_catalog.jsonb_build_array(v_fila)), p_tx), p_esperado);
end $s$;
select pg_temp.trucar_tasa('tasa trucada: control positivo', null, 'BORRÓ');
select pg_temp.trucar_tasa('tasa trucada: copia de otra transacción', '1', 'P0409 Una solicitud de tasa no se borra');

-- Ficha anterior al lead (Codex r2): solo pasa la que nació CON el lead (<1 s antes y con el documento del lead).
set local session_replication_role = replica;
insert into pg_temp.siembra
select 'I5' || n || ' ficha', pg_temp.sembrar('crm.inversionistas', pg_catalog.jsonb_build_object(
         'id', '61000000-0000-4000-8000-0000000000' || n,
         'creado_en', (select l.creado_en - case n when 56 then interval '1 millisecond' when 57 then interval '30 seconds' else interval '500 milliseconds' end
                       from crm.leads l where l.id = ('20000000-0000-4000-8000-0000000000' || n)::uuid)))
from pg_catalog.generate_series(56, 58) n
union all
select 'I5' || n || ' enlace', pg_temp.sembrar('crm.inversionista_leads', pg_catalog.jsonb_build_object(
         'inversionista_id', '61000000-0000-4000-8000-0000000000' || n, 'lead_id', '20000000-0000-4000-8000-0000000000' || n, 'rol', 'canonico'))
from pg_catalog.generate_series(56, 58) n
union all
select 'I5' || n || ' identificador', pg_temp.sembrar('crm.inversionista_identificadores', pg_catalog.jsonb_build_object(
         'inversionista_id', '61000000-0000-4000-8000-0000000000' || n, 'documento_normalizado', '200000' || n,
         'fuente', case n when 56 then 'documento_lead' else 'conversion_inversion' end))
from pg_catalog.generate_series(56, 57) n;
set local session_replication_role = origin;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'siembra 2d: ' || s.caso, 'ok', s.resultado, false from pg_temp.siembra s where s.caso ~ '^I5[678]' and s.resultado <> 'ok';
select pg_temp.probar('L56 ficha nacida con el lead (1 ms antes, documento del lead) → se borra', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000056', 'cargado por error en prueba', 'OK true');
select pg_temp.probar('L57 ficha de otro origen 30 s antes del lead → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000057', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*ya existía antes del lead');
select pg_temp.probar('L58 ficha sin documento 0,5 s antes del lead → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000058', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: .*ya existía antes del lead');

savepoint mes;
set local session_replication_role = replica;
insert into pg_temp.siembra values ('mes cerrado', pg_temp.sembrar('crm.periodos_cerrados',
  pg_catalog.jsonb_build_object('periodo', pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date)));
set local session_replication_role = origin;
select pg_temp.probar('mes cerrado → P0409', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000007', 'cargado por error en prueba', 'P0409 No se puede eliminar este lead: aparece en un mes cerrado');
-- El registro del caso se pierde con el rollback del savepoint: se captura antes y se reinserta después.
select caso, esperado, obtenido, ok::text as ok from pg_temp.r order by n desc limit 1 \gset sp_
rollback to savepoint mes;
insert into pg_temp.r (caso, esperado, obtenido, ok) values (:'sp_caso', :'sp_esperado', :'sp_obtenido', :'sp_ok'::boolean);
savepoint fk;
create table crm.zz_prueba_fk (id uuid primary key, lead_id uuid references crm.leads (id) on delete cascade);
select pg_temp.probar('FK nueva desconocida → 55000', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000006', 'cargado por error en prueba', '55000 Hay tablas nuevas');
-- El registro del caso se pierde con el rollback del savepoint: se captura antes y se reinserta después.
select caso, esperado, obtenido, ok::text as ok from pg_temp.r order by n desc limit 1 \gset sp_
rollback to savepoint fk;
insert into pg_temp.r (caso, esperado, obtenido, ok) values (:'sp_caso', :'sp_esperado', :'sp_obtenido', :'sp_ok'::boolean);
-- Misma tabla, misma columna de origen y misma acción, pero OTRA columna de destino: también es desconocida (Codex r2).
-- Un ALTER TABLE no admite eventos de trigger pendientes (la FK diferida de los recibos tras los borrados de arriba).
set constraints all immediate;
savepoint fk2;
alter table crm.leads add column zz_clave_alterna uuid unique;
alter table crm.llamadas_celular_eventos add constraint zz_prueba_fk_alterna
  foreign key (lead_id) references crm.leads (zz_clave_alterna) on delete cascade not valid;
select pg_temp.probar('FK con otra columna de destino → 55000', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000006', 'cargado por error en prueba', '55000 Hay tablas nuevas');
-- El registro del caso se pierde con el rollback del savepoint: se captura antes y se reinserta después.
select caso, esperado, obtenido, ok::text as ok from pg_temp.r order by n desc limit 1 \gset sp_
rollback to savepoint fk2;
insert into pg_temp.r (caso, esperado, obtenido, ok) values (:'sp_caso', :'sp_esperado', :'sp_obtenido', :'sp_ok'::boolean);

-- ── 3 · Sin la puerta, el DELETE directo sigue bloqueado (como dueño de las tablas, sin RLS) ─────────────────────────
select pg_temp.borrar_directo('directo lead_asignaciones', $q$delete from crm.lead_asignaciones where lead_id = '20000000-0000-4000-8000-000000000001'$q$, 'P0001 Los episodios de asignacion no se eliminan');
select pg_temp.borrar_directo('directo lead_asignacion_sla_hitos', $q$delete from crm.lead_asignacion_sla_hitos where id = '41000000-0000-4000-8000-000000000001'$q$, '55000 Los hitos SLA');
select pg_temp.borrar_directo('directo lead_sla_ciclos', $q$delete from crm.lead_sla_ciclos where lead_id = '20000000-0000-4000-8000-000000000001'$q$, '55000 Los ciclos SLA');
select pg_temp.borrar_directo('directo lead_sla_etapas', $q$delete from crm.lead_sla_etapas where lead_id = '20000000-0000-4000-8000-000000000001'$q$, '55000 Las etapas SLA');
select pg_temp.borrar_directo('directo tarea_sla_contexto', $q$delete from crm.tarea_sla_contexto where lead_id = '20000000-0000-4000-8000-000000000001'$q$, '55000 Los hechos SLA');
select pg_temp.borrar_directo('directo lead_sla_etapa_ajustes', $q$delete from crm.lead_sla_etapa_ajustes where id = '45000000-0000-4000-8000-000000000001'$q$, '55000 Los hechos SLA');
select pg_temp.borrar_directo('directo sla_operacion_recibos', $q$delete from crm.sla_operacion_recibos where lead_id = '20000000-0000-4000-8000-000000000001'$q$, '55000 Los recibos');
select pg_temp.borrar_directo('directo lead_potencial_eventos', $q$delete from crm.lead_potencial_eventos where lead_id = '20000000-0000-4000-8000-000000000001'$q$, 'P0409 El historial de potencial');
select pg_temp.borrar_directo('directo actividad No contactar', $q$do $d$ begin perform set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true); delete from crm.actividades where id = '44000000-0000-4000-8000-000000000002'; end $d$$q$, '42501 La nota de No contactar');
select pg_temp.borrar_directo('directo lead (RESTRICT)', $q$delete from crm.leads where id = '20000000-0000-4000-8000-000000000001'$q$, '23503');
-- Con el permiso de transacción puesto A MANO pero sin copia: sigue bloqueado.
select pg_temp.borrar_directo('GUC a mano sin copia', $q$do $d$ begin perform set_config('crm.borrado_lead_error', '20000000-0000-4000-8000-000000000001', true); perform set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true); delete from crm.lead_sla_ciclos where lead_id = '20000000-0000-4000-8000-000000000001'; end $d$$q$, '55000 Los ciclos SLA');
-- Como usuario autenticado (gerencia), DELETE directo: lo frena el permiso de tabla o el candado.
select pg_temp.borrar_directo('authenticated directo lead_sla_ciclos', $q$do $d$ begin perform set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true); execute 'set local role authenticated'; delete from crm.lead_sla_ciclos where lead_id = '20000000-0000-4000-8000-000000000001'; end $d$$q$, '42501');
select pg_temp.borrar_directo('authenticated directo leads', $q$do $d$ begin perform set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true); execute 'set local role authenticated'; delete from crm.leads where id = '20000000-0000-4000-8000-000000000001'; end $d$$q$, '42501|BORRÓ 0');
select pg_temp.borrar_directo('authenticated escribe copia', $q$do $d$ begin execute 'set local role authenticated'; insert into crm.leads_eliminados (lead_id, motivo, eliminado_por, rol_actor, copia, filas) values (gen_random_uuid(), 'motivo de prueba', gen_random_uuid(), 'gerencia', '{"lead":{}}', '{}'); end $d$$q$, '42501');

-- Copias TRUCADAS (insertadas por el dueño de la tabla): la llave exige todas sus condiciones a la vez. Primero un
-- control positivo (con todo en regla el DELETE pasa: la prueba discrimina); luego una condición rota cada vez.
create function pg_temp.trucar(p_caso text, p_variante text, p_esperado text) returns void language plpgsql as $s$
declare
  v_fila jsonb;
  v_copia jsonb;
  v_tabla text := 'lead_sla_ciclos';
  v_actor uuid := '10000000-0000-4000-8000-000000000001';
  v_guc text := '20000000-0000-4000-8000-000000000009';
  v_tx text := null;
  v_sub text := '10000000-0000-4000-8000-000000000001';
begin
  select pg_catalog.to_jsonb(c) into v_fila from crm.lead_sla_ciclos c where c.id = '42000000-0000-4000-8000-000000000009';
  if p_variante = 'fila_distinta' then v_fila := pg_catalog.jsonb_set(v_fila, '{aproximado}', 'true'); end if;
  if p_variante = 'fila_con_extra' then v_fila := v_fila || '{"extra": 1}'; end if;
  if p_variante = 'otra_tabla' then v_tabla := 'lead_sla_etapas'; end if;
  if p_variante = 'otro_actor' then v_actor := '10000000-0000-4000-8000-000000000002'; end if;
  if p_variante = 'otro_lead_en_permiso' then v_guc := '20000000-0000-4000-8000-000000000008'; end if;
  if p_variante = 'otra_transaccion' then v_tx := '1'; end if;
  if p_variante = 'sin_sesion' then v_sub := ''; end if;
  v_copia := pg_catalog.jsonb_build_object('lead', '{}'::jsonb, v_tabla, pg_catalog.jsonb_build_array(v_fila));
  perform pg_temp.borrar_directo(p_caso, pg_catalog.format($q$do $d$ begin
      insert into crm.leads_eliminados (lead_id, motivo, eliminado_por, rol_actor, copia, filas, transaccion)
      values ('20000000-0000-4000-8000-000000000009', 'motivo de prueba', %L, 'gerencia', %L, '{}',
              coalesce(%L::xid8, pg_catalog.pg_current_xact_id()));
      perform pg_catalog.set_config('crm.borrado_lead_error', %L, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', %L, true);
      perform pg_catalog.set_config('request.jwt.claims', '{}', true);
      delete from crm.lead_sla_ciclos where id = '42000000-0000-4000-8000-000000000009';
      if not found then raise exception 'NO BORRÓ'; end if;
    end $d$$q$, v_actor, v_copia, v_tx, v_guc, v_sub), p_esperado);
end $s$;
select pg_temp.trucar('trucada: control positivo (todo en regla)', 'ninguna', 'BORRÓ');
select pg_temp.trucar('trucada: fila distinta', 'fila_distinta', '55000 Los ciclos SLA');
select pg_temp.trucar('trucada: fila con un campo de más (contención no basta)', 'fila_con_extra', '55000 Los ciclos SLA');
select pg_temp.trucar('trucada: fila bajo otra tabla', 'otra_tabla', '55000 Los ciclos SLA');
select pg_temp.trucar('trucada: otro actor', 'otro_actor', '55000 Los ciclos SLA');
select pg_temp.trucar('trucada: permiso con otro lead', 'otro_lead_en_permiso', '55000 Los ciclos SLA');
select pg_temp.trucar('trucada: copia de otra transacción', 'otra_transaccion', '55000 Los ciclos SLA');
select pg_temp.trucar('trucada: sin sesión', 'sin_sesion', '55000 Los ciclos SLA');

-- ── 4 · Borrado válido completo (gerencia) + copia ───────────────────────────────────────────────────────────────────
select pg_temp.ejecutar('gerencia borra L1 completo', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', '  Cargado por error: duplicado de prueba  ');
reset role;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'L1: no queda ninguna fila', '0', v.n::text, v.n = 0
from (select (select pg_catalog.count(*) from crm.leads where id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.lead_asignaciones where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.lead_asignacion_sla_hitos where id = '41000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.lead_sla_ciclos where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.lead_sla_etapas where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.lead_sla_etapa_ajustes where id = '45000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.tareas where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.tarea_sla_contexto where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.actividades where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.sla_operacion_recibos where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.lead_potencial_eventos where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.llamadas_celular_eventos where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from crm.llamadas_celular_enlaces where lead_id = '20000000-0000-4000-8000-000000000001')
           + (select pg_catalog.count(*) from private.llamadas_celular_intenciones where lead_id = '20000000-0000-4000-8000-000000000001') n) v;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'L1: copia con autor, rol, motivo normalizado y filas', 'gerencia|2 tareas|2 actividades|1 asignación',
       e.rol_actor || '|' || (e.filas ->> 'tareas') || ' tareas|' || (e.filas ->> 'actividades') || ' actividades|'
         || (e.filas ->> 'lead_asignaciones') || ' asignación · motivo=«' || e.motivo || '»',
       e.rol_actor = 'gerencia' and e.eliminado_por = '10000000-0000-4000-8000-000000000001'
         and e.motivo = 'Cargado por error: duplicado de prueba' and (e.filas ->> 'tareas')::int = 2
         and (e.filas ->> 'actividades')::int = 2 and (e.filas ->> 'lead_asignaciones')::int = 1
         and (e.filas ->> 'lead_sla_ciclos')::int = 1 and (e.filas ->> 'llamadas_celular_eventos')::int = 1
         and (e.filas ->> 'llamadas_celular_intenciones')::int = 1 and e.copia -> 'lead' ->> 'id' = '20000000-0000-4000-8000-000000000001'
         and (e.filas ->> 'base_carga_leads')::int = (select pg_catalog.count(*) from pg_temp.siembra where caso = 'L1 base_carga_leads' and resultado = 'ok')
         and (e.filas ->> 'lead_potencial')::int = (select pg_catalog.count(*) from pg_temp.siembra where caso = 'L1 lead_potencial' and resultado = 'ok')
         and (e.filas ->> 'actividades_cliente')::int = (select pg_catalog.count(*) from pg_temp.siembra where caso = 'L1 actividades_cliente' and resultado = 'ok')
from crm.leads_eliminados e where e.lead_id = '20000000-0000-4000-8000-000000000001';
select pg_temp.probar('L1 otra vez → P0002', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', 'cargado por error en prueba', 'P0002');

-- Tras la puerta, en la MISMA transacción, con la copia de L1 y el permiso puesto a mano para L1: una fila de OTRO
-- lead (L9) sigue bloqueada.
select pg_temp.borrar_directo('tras la puerta: fila de otro lead', $q$do $d$ begin perform set_config('crm.borrado_lead_error', '20000000-0000-4000-8000-000000000001', true); perform set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true); delete from crm.lead_sla_ciclos where id = '42000000-0000-4000-8000-000000000009'; end $d$$q$, '55000 Los ciclos SLA');

-- La copia es inmutable (incluso para el dueño de la tabla).
select pg_temp.borrar_directo('copia: DELETE prohibido', $q$delete from crm.leads_eliminados where lead_id = '20000000-0000-4000-8000-000000000001'$q$, '42501 La copia de un lead eliminado es inmutable');
select pg_temp.borrar_directo('copia: UPDATE prohibido', $q$update crm.leads_eliminados set motivo = 'cambiado a mano' where lead_id = '20000000-0000-4000-8000-000000000001'$q$, '42501 La copia de un lead eliminado es inmutable');
select pg_temp.borrar_directo('copia: TRUNCATE prohibido', $q$truncate crm.leads_eliminados$q$, '42501 La copia de un lead eliminado es inmutable');

-- ── 5 · Admin y superadmin del portal también pueden ─────────────────────────────────────────────────────────────────
select pg_temp.ejecutar('admin portal borra L6', '10000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000006', 'cargado dos veces por error');
reset role;
select pg_temp.ejecutar('superadmin portal borra L8', '10000000-0000-4000-8000-000000000005',
  '20000000-0000-4000-8000-000000000008', 'cargado dos veces por error');
reset role;

-- ── 6 · Lectura de la copia: solo por la puerta y solo gerencia; la tabla no tiene grants ──────────────────────────
create function pg_temp.listar(p_actor uuid) returns text language plpgsql as $s$
declare v bigint;
begin
  perform pg_catalog.set_config('request.jwt.claims',
    pg_catalog.json_build_object('sub', p_actor, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', p_actor::text, true);
  begin
    execute 'set local role authenticated';
    select pg_catalog.count(*) into v from crm.listar_leads_eliminados();
    raise exception using errcode = 'XX999', message = 'FILAS ' || v;
  exception when others then
    return case when sqlstate = 'XX999' then sqlerrm else sqlstate || ' ' || sqlerrm end;
  end;
end $s$;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'listar: gerencia ve las 4 eliminaciones', 'FILAS 4', x, x = 'FILAS 4'
from pg_temp.listar('10000000-0000-4000-8000-000000000001') x;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'listar: admin del portal → 42501', '42501', x, x like '42501%'
from pg_temp.listar('10000000-0000-4000-8000-000000000002') x;
insert into pg_temp.r (caso, esperado, obtenido, ok)
select 'listar: vendedor → 42501', '42501', x, x like '42501%'
from pg_temp.listar('10000000-0000-4000-8000-000000000003') x;
select pg_temp.borrar_directo('gerencia lee la tabla directo → 42501', $q$do $d$ declare v bigint; begin perform set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true); execute 'set local role authenticated'; select count(*) into v from crm.leads_eliminados; end $d$$q$, '42501');

-- ── Veredicto ─────────────────────────────────────────────────────────────────────────────────────────────────────────
select n, ok, caso, esperado, obtenido from pg_temp.r order by n;
select pg_catalog.count(*) filter (where ok) as pasan, pg_catalog.count(*) filter (where not ok) as fallan from pg_temp.r;
rollback;

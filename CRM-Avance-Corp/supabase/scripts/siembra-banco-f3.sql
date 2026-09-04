-- SIEMBRA para el ensayo del lote Contrato-F2 (la «F3» del plan) — SOLO en banco.
-- Presupone: F1 + F2-backfill + el lote (190000..260000) ya aplicados en el banco.
-- POR CORRIDA: se invoca con `psql -v run=DDHHMM` (6 digitos) y TODO (leads, perfil, documentos,
-- telefonos) se deriva de ese RUN. No se borra nada: varias tablas son append-only
-- por diseño (depositos_reclamados, ledger) y no se desmontan candados para
-- ensayar. Cada corrida vive en su propio espacio; las anteriores quedan inertes.
--
-- Escenario (lo prueba oraculo-f3-concurrencia.sh con el mismo RUN):
--   * Persona NUEVA (doc 7RUN1) con DOS leads L1/L2 (dni NULL, telefonos
--     distintos) -> carrera coop simultanea por el MISMO documento.
--   * Perfil PA (cliente, dni 7RUN1) + lead L3 -> «vuelve» por Avance: P0409.
--   * Lead L4 (doc 7RUN4) -> paridad con bandera APAGADA.
--   * Lead L5 (doc 7RUN3 al convertir) -> identidad sin perfil + no_contactar.
-- Los leads llevan dni NULL a proposito: el indice unico de crm.leads impide dos
-- leads con el mismo DNI; el documento entra por el parametro de la coop o por el
-- perfil de Avance (asi ocurre en la vida real, y es el hueco que Codex describio).
\set ON_ERROR_STOP on
\if :{?run}
\else
  \echo 'FALTA -v run=NNNN (4 digitos)'
  \quit 2
\endif
begin;
select set_config('crm.op_privilegiada','on', true);

-- Actores FIJOS (idempotentes): V vendedor, S supervisor de V, G gerencia.
insert into auth.users (id) values
  ('f3000000-0000-0000-0000-000000000001'),
  ('f3000000-0000-0000-0000-000000000002'),
  ('f3000000-0000-0000-0000-000000000003')
on conflict (id) do nothing;
insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values
  ('f3000000-0000-0000-0000-000000000003','F3 SUPERVISOR','comercial','DNI','70000093'),
  ('f3000000-0000-0000-0000-000000000001','F3 VENDEDOR','comercial','DNI','70000091'),
  ('f3000000-0000-0000-0000-000000000002','F3 GERENCIA','comercial','DNI','70000092')
on conflict (id) do update set activo = true;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por) values
  ('f3000000-0000-0000-0000-000000000003','supervisor', null, true, 'f3000000-0000-0000-0000-000000000003'),
  ('f3000000-0000-0000-0000-000000000001','vendedor',   'f3000000-0000-0000-0000-000000000003', true, 'f3000000-0000-0000-0000-000000000003'),
  ('f3000000-0000-0000-0000-000000000002','gerencia',   null, true, 'f3000000-0000-0000-0000-000000000002')
on conflict (perfil_id) do update set rol_crm = excluded.rol_crm, supervisor_id = excluded.supervisor_id, activo = true;

-- PA POR CORRIDA: perfil cliente con el MISMO documento que la carrera.
insert into auth.users (id) values (('f3a00000-0000-0000-0000-' || :'run' || '000001')::uuid) on conflict (id) do nothing;
insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, asesor_perfil_id) values
  (('f3a00000-0000-0000-0000-' || :'run' || '000001')::uuid, 'F3 PERSONA UNO r' || :'run', 'cliente', 'DNI', '7' || :'run' || '1', 'f3000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

-- Leads POR CORRIDA (dni NULL, telefonos distintos, del vendedor V, etapa nuevo).
insert into crm.leads (id, nombre_completo, telefono, monto_estimado, origen, etapa, creado_por, vendedor_id)
select ('f31ead00-0000-0000-0000-' || :'run' || '00000' || n)::uuid,
       'F3 LEAD ' || n || ' r' || :'run', '9' || :'run' || '0' || n, 5000, 'landing', 'nuevo',
       'f3000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001'
from generate_series(1,5) as n
on conflict (id) do nothing;

select set_config('crm.op_privilegiada','off', true);
commit;

select 'SIEMBRA-F3-OK run=' || :'run' as resultado,
       (select count(*) from crm.leads where id::text like 'f31ead00-0000-0000-0000-' || :'run' || '%') as leads_run,
       (select count(*) from crm.equipo where perfil_id::text like 'f3000000-%' and activo) as actores;

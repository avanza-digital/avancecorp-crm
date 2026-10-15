-- Lectura equivalente reconstruida al cierre para documentar la medición.
-- La respuesta ejecutada se conserva en conversion-numerador.json.
-- No es la transcripción exacta del comando original, ni una nueva ejecución.
-- Solo fixtures del ensayo aislado retirado; reemplazar IDs en otro ensayo.
begin read only;
with objetivos(id) as (
  values ('15c43aa0-2892-4aa1-81ac-cfe421ee1936'::uuid),
         ('12743927-a9c0-40c1-9cfa-c83ff3b65699'::uuid)
), l as (
  select id, etapa, nombre, origen, campania_origen as campania
  from crm.leads where id in (select id from objetivos)
), a as (
  select * from crm.lead_asignaciones
  where lead_id in (select id from objetivos)
), c as (
  select * from private.conversion_episodios(
    '2026-10-01 00:00:00 America/Lima'::timestamptz,
    '2026-11-01 00:00:00 America/Lima'::timestamptz,
    null::date, true, null::uuid[], 1::numeric
  ) where lead_id in (select id from objetivos)
)
select jsonb_build_object(
  'leads', (select jsonb_agg(to_jsonb(l)) from l),
  'episodios', (select jsonb_agg(to_jsonb(a)) from a),
  'conversion', (select jsonb_agg(to_jsonb(c)) from c)
) as paridad;
rollback;

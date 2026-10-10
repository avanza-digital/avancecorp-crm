-- REVERSA de 20261010150451_crm_jerarquia_relleno_carmen_jorge: borra los DOS eventos del relleno por su idempotencia
-- fija. Facturación vuelve a poner sus ventas desde el 29/08 con CARLOS VALLES. Idempotente; se niega si encuentra uno
-- solo o alguno distinto en CUALQUIER campo que decide la atribución (Codex r1, P2). No toca supabase_migrations (si
-- hiciera falta, se desregistra a mano).
begin;
set local lock_timeout = '10s';
do $reversa$
declare
  v_n integer;
  v_exactos integer;
  v_borrados integer;
begin
  -- Se bloquean las filas antes de validarlas: nadie las cambia entre la validación y el borrado.
  select count(*) into v_n from (
    select 1 from crm.usuario_eventos ue
    where ue.actor_id = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d' and ue.accion = 'jerarquia_actualizada'
      and ue.idempotencia in ('df2577aa-0315-43ad-8d28-cc1fce382b61', '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5')
    for update) x;
  if v_n = 0 then
    raise notice 'Reversa del relleno: no hay eventos que borrar';
    return;
  end if;
  select count(*) into v_exactos from crm.usuario_eventos ue
  where ue.actor_id = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d' and ue.accion = 'jerarquia_actualizada'
    and ue.detalle ->> 'via' = 'relleno'
    and ue.detalle ->> 'supervisor_anterior' = 'ebb19751-5976-4446-91ec-03382247d8b8'
    and ue.detalle ->> 'supervisor_nuevo' = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'
    and ue.creado_en = '2026-08-29 17:56:38.8714+00'
    and (ue.objetivo_id, ue.idempotencia) in (
      ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e'::uuid, 'df2577aa-0315-43ad-8d28-cc1fce382b61'::uuid),
      ('cc8b660a-49e9-49b2-a939-c12b5078911b'::uuid, '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5'::uuid));
  if v_n <> 2 or v_exactos <> 2 then
    raise exception 'REVERSA: % eventos con la idempotencia del relleno, % exactos; no son los dos esperados, revisar a mano',
      v_n, v_exactos;
  end if;
  delete from crm.usuario_eventos ue
  where ue.actor_id = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d' and ue.accion = 'jerarquia_actualizada'
    and ue.detalle ->> 'via' = 'relleno'
    and ue.detalle ->> 'supervisor_anterior' = 'ebb19751-5976-4446-91ec-03382247d8b8'
    and ue.detalle ->> 'supervisor_nuevo' = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'
    and ue.creado_en = '2026-08-29 17:56:38.8714+00'
    and (ue.objetivo_id, ue.idempotencia) in (
      ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e'::uuid, 'df2577aa-0315-43ad-8d28-cc1fce382b61'::uuid),
      ('cc8b660a-49e9-49b2-a939-c12b5078911b'::uuid, '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5'::uuid));
  get diagnostics v_borrados = row_count;
  if v_borrados <> 2 then
    raise exception 'REVERSA: se iban a borrar 2 eventos y se borraron %; se deshace', v_borrados;
  end if;
  raise notice 'Reversa del relleno hecha: 2 eventos borrados';
end
$reversa$;
commit;

// Cada alteración deliberada vive en una transacción revertida. Sólo en banco fijo.
import assert from 'node:assert/strict';
import { sqlLocal } from './banco.mjs';
const tabla = 'crm.politica_gestion_diaria';
const mutantes = [
  ['RLS apagada', `alter table ${tabla} disable row level security`],
  ['SELECT total', `grant select on ${tabla} to authenticated`],
  ['lectura de motivo', `grant select (motivo) on ${tabla} to authenticated`],
  ['escritura API', `grant update on ${tabla} to authenticated`],
  ['escritura por columna', `grant update (cortes_activos) on ${tabla} to authenticated`],
  ['service por columna', `grant select (motivo) on ${tabla} to service_role`],
  ['anon', `grant execute on function private.gestion_diaria_cortes(date,uuid[],timestamptz) to anon`],
  ['umbrales legacy anon', 'grant execute on function private.gestion_diaria_umbrales() to anon'],
  ['umbrales legacy cuerpo', `do $mutar$ declare d text; begin
    d:=pg_get_functiondef('private.gestion_diaria_umbrales()'::regprocedure);
    execute replace(d,'statement_timestamp()','now()'); end $mutar$`],
  ['definer', `alter function private.gestion_diaria_cortes(date,uuid[],timestamptz) security definer`],
  ['policy permisiva', `alter policy politica_gestion_diaria_select on ${tabla} using (true)`],
  ['sin inmutabilidad', `alter table ${tabla} disable trigger trg_config_inmutable`],
  ['sin auditoría', `alter table ${tabla} disable trigger trg_audit_politica_gestion_diaria`],
  ['sin validación futura', `alter table ${tabla} disable trigger trg_validar_politica_gestion_diaria`],
  ['redondeo alterado', `do $mutar$ declare d text; begin
    d := pg_get_functiondef('private.gestion_diaria_cortes(date,uuid[],timestamptz)'::regprocedure);
    if position('ceil(' in d)=0 then raise exception 'Mutante sin ancla'; end if;
    execute replace(d,'ceil(','floor('); end $mutar$`],
];
for (const [nombre, cambio] of mutantes) {
  const r = sqlLocal(`begin; ${cambio};
    do $detectar$ declare detectado boolean := false; begin
      begin perform private.assert_gestion_diaria(); exception when others then detectado := true; end;
      if not detectado then raise exception 'Mutante escapó'; end if;
    end $detectar$;
    select 'MUTANTE_DETECTADO'; rollback;`);
  assert.match(r, /MUTANTE_DETECTADO/);
  sqlLocal('select private.assert_gestion_diaria()');
  console.log(`PASS: mutante ${nombre}`);
}

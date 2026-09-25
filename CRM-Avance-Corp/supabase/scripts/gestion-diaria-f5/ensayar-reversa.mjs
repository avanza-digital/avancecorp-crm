// Demuestra reversa de funciones sin confirmar cambios, sólo en el banco F5.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { sql } from './banco.mjs';

const reversa = readFileSync(new URL('./reversa-propuesta.sql', import.meta.url), 'utf8');
assert.match(reversa, /commit;\s*$/i);
sql(reversa.replace(/commit;\s*$/i, `
do $comprobar$ begin
  if to_regprocedure('crm.gestion_diaria_pulso_fn(date)') is not null
    or to_regprocedure('crm.gestion_diaria_habitos_fn(date,integer)') is not null
    or md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure))<>'45e6e7a82c54b2f15110b828ba70761d'
    or md5(pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure))<>'84fc8e66c81639536168bcd62709f6b9' then
    raise exception 'La reversa no restituyó los contratos originales';
  end if;
end $comprobar$;
rollback;`));
sql('select private.assert_gestion_diaria_pulso();');
console.log('PASS: reversa restaura ambos cuerpos originales y retira las puertas F5; ROLLBACK conserva el candidato y sus guardas.');

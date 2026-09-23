import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { carpeta, sql } from '../gestion-diaria-cortes/http/banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
const pruebas=readFileSync(new URL('./test-correcciones.sql',import.meta.url),'utf8');
const mutantes=readFileSync(new URL('./test-mutantes.sql',import.meta.url),'utf8');
// supabase_admin únicamente para retirar el grant directo auth del banco y
// ensayar BYPASSRLS dentro de la transacción. Las acciones de negocio usan
// SET ROLE authenticated; se termina en ROLLBACK sin instalar modificaciones.
const bypass=`do $$ declare visto boolean:=false; begin
  begin
    alter role crm_gestion_diaria_lector bypassrls;
    begin perform private.assert_gestion_diaria(); exception when others then visto:=true; end;
    raise exception 'Revertir' using errcode='Z0001';
  exception when sqlstate 'Z0001' then null;
  end;
  if not visto then raise exception 'BYPASSRLS no detectado'; end if;
end $$;`;
const resultado=sql(`begin; ${bypass}\nset local role postgres;\n${mutantes}\n${pruebas}\nselect private.assert_gestion_diaria(); rollback;`,{propietarioAlmacen:true});
sql('select private.assert_gestion_diaria()');
writeFileSync(`${carpeta}/gd-f4-correcciones-sql.log`,resultado+'\n',{mode:0o600});
console.log(resultado.split('\n').filter(l=>l.startsWith('PASS:')).join('\n'));

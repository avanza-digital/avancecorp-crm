// Copia únicamente los contratos afectados por F4 desde la generación oficial.
// El banco tiene otra versión de PostgREST y no reemplaza tipos de otras tareas.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const actualizar=process.argv[2]==='--actualizar';
assert.deepEqual(process.argv.slice(2),[actualizar?'--actualizar':'--comprobar']);
const archivo=fileURLToPath(new URL('../../../app/src/lib/database.types.ts',import.meta.url));
const ts=createRequire(archivo)('typescript');
const generado='/private/tmp/gd-f4-tipos-generados.ts';
function abrir(path) {
  const texto=readFileSync(path,'utf8');
  const fuente=ts.createSourceFile(path,texto,ts.ScriptTarget.Latest,true);
  assert.equal(fuente.parseDiagnostics.length,0);
  const database=fuente.statements.find(n=>ts.isTypeAliasDeclaration(n)&&n.name.text==='Database');
  const crm=database.type.members.find(n=>n.name.getText(fuente)==='crm');
  const categorias=Object.fromEntries(crm.type.members.map(n=>[n.name.getText(fuente),n]));
  return {texto,fuente,categorias};
}
const a=abrir(archivo),b=abrir(generado);
const cambios=[];
for(const [categoria,nombres] of Object.entries({
  Tables:['politica_gestion_diaria','alertas_reconocimientos','gestion_diaria_control_avisos','gestion_diaria_entregas'],
  Functions:['gestion_diaria_avisos_fn','gestion_diaria_presentar_corte','gestion_diaria_reconocer_corte',
    'configuracion_gestion_diaria_fn','publicar_politica_gestion_diaria','controlar_avisos_gestion_diaria'],
})) {
  for(const nombre of nombres) {
    const anterior=a.categorias[categoria].type.members.find(n=>n.name.getText(a.fuente)===nombre);
    const nuevo=b.categorias[categoria].type.members.find(n=>n.name.getText(b.fuente)===nombre);
    assert.ok(nuevo,`Falta ${categoria}.${nombre} generado`);
    const texto=nuevo.getText(b.fuente);
    if(anterior?.getText(a.fuente)===texto) continue;
    assert.ok(actualizar,`Diferencia pendiente en ${categoria}.${nombre}`);
    cambios.push(anterior?{inicio:anterior.getStart(a.fuente),fin:anterior.end,texto}:
      {inicio:a.categorias[categoria].type.members.pos,fin:a.categorias[categoria].type.members.pos,texto:`\n      ${texto}`});
  }
}
let resultado=a.texto;
for(const c of cambios.sort((x,y)=>y.inicio-x.inicio)) resultado=resultado.slice(0,c.inicio)+c.texto+resultado.slice(c.fin);
if(actualizar) writeFileSync(archivo,resultado);
console.log(`PASS: diez contratos F4 cotejados con postgres-meta; ${cambios.length} actualizados`);

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {comprobarBase,comprobarParidad,verificarSql} from './verificar-base-instalacion.mjs';

// Evidencia real y saneada. El reloj fijo prueba el comportamiento histórico;
// nunca se usa este reloj ni esta captura vieja para autorizar una instalación.
const base=JSON.parse(readFileSync(new URL(
  './instalacion/base-produccion-revisada-2026-09-13.json',import.meta.url),'utf8'));
const ahora=Date.parse(base.precondiciones.inicio_captura_utc)+30_000;
const reciente=()=>{
  const c=structuredClone(base);
  for(const campo of ['inicio_captura_utc','fin_captura_utc'])
    c.precondiciones[campo]=new Date(Date.parse(c.precondiciones[campo])+1000).toISOString();
  return c;
};
test('acepta la base observada y cambios normales de volumen; no autoriza merge',()=>{
  verificarSql();
  const actual=reciente();
  actual.precondiciones.fuentes.find(f=>!f.es_demo).fuentes+=7;
  const r=comprobarBase(base,actual,ahora);
  assert.equal(r.estado,'PASS_PRECONDICIONES_PADRE');
  assert.equal(r.autoriza_merge,false);
});
const casos=[
  ['captura vencida',x=>{x.precondiciones.inicio_captura_utc=new Date(ahora-60_001).toISOString();}],
  ['captura futura',x=>{x.precondiciones.fin_captura_utc=new Date(ahora+1).toISOString();}],
  ['otro proyecto',x=>{x.proyecto='otra-rama';}],
  ['nueva brecha real',x=>{x.precondiciones.fuentes[0].brechas_identidad=1;}],
  ['marca NULL incluso con identidad coherente',x=>{x.precondiciones.fuentes.push({es_demo:null,fuentes:1,brechas_identidad:0});}],
  ['falta universo real',x=>{x.precondiciones.fuentes=x.precondiciones.fuentes.filter(f=>f.es_demo);}],
  ['falta función',x=>{x.precondiciones.funciones.pop();}],
  ['firma duplicada',x=>{x.precondiciones.funciones[1]=x.precondiciones.funciones[0];}],
  ['cuerpo cambiado',x=>{x.precondiciones.funciones[0].definicion_coincide=false;}],
  ['ACL sin comprobar',x=>{x.precondiciones.funciones[0].acl_exigida_coincide=null;}],
  ['dueño cambiado',x=>{x.precondiciones.funciones[0].propietario_postgres=false;}],
  ['F7 encendida',x=>{x.precondiciones.banderas.metricas_multiempresa_sombra=true;}],
  ['F6 encendida',x=>{x.precondiciones.banderas.postventa_neutral=true;}],
  ['instalación parcial',x=>{x.precondiciones.instalacion.control=true;}],
  ['historial cambió',x=>{x.precondiciones.historial.md5_arrays='0'.repeat(32);}],
  ['otra función ajena cambió',x=>{x.precondiciones.catalogo_funciones.md5='0'.repeat(32);}],
  ['permisos por defecto distintos',x=>{x.paridad.find(p=>p.categoria==='default_acl').md5='0'.repeat(32);}],
  ['inventario incompleto',x=>{x.paridad.pop();}],
  ['protección demo ausente',x=>{x.precondiciones.proteccion_demo_presente=false;}],
];
for(const [nombre,mutar] of casos) test(`rechaza ${nombre}`,()=>{
  const actual=reciente();mutar(actual);
  assert.throws(()=>comprobarBase(base,actual,ahora));
});

test('rechaza reutilizar como actual la misma base fresca',()=>{
  assert.throws(()=>comprobarBase(base,base,ahora),/posterior/);
});
const refRama='aaaaaaaaaaaaaaaaaaaa';
const rama=()=>({...reciente(),proyecto:refRama});
test('paridad registra ambos proyectos y liga los archivos por SHA',()=>{
  const r=comprobarParidad(base,rama(),refRama);
  assert.equal(r.estado,'PASS_PARIDAD_RAMA');assert.equal(r.autoriza_merge,false);
  assert.equal(r.padre,base.proyecto);assert.equal(r.rama,refRama);
  assert.match(r.sha256_padre,/^[a-f0-9]{64}$/);
});
test('paridad rechaza ref ajeno, comparación consigo misma y captura de otra ventana',()=>{
  assert.throws(()=>comprobarParidad(base,rama(),'bbbbbbbbbbbbbbbbbbbb'));
  assert.throws(()=>comprobarParidad(base,base,base.proyecto));
  const tarde=rama();tarde.precondiciones.inicio_captura_utc=new Date(ahora+60_000).toISOString();
  assert.throws(()=>comprobarParidad(base,tarde,refRama));
});
test('paridad rechaza categorías ausentes y cambios de default ACL en la rama',()=>{
  const falta=rama();falta.paridad.pop();
  assert.throws(()=>comprobarParidad(base,falta,refRama));
  const deriva=rama();deriva.paridad.find(x=>x.categoria==='default_acl').md5='0'.repeat(32);
  assert.throws(()=>comprobarParidad(base,deriva,refRama));
});

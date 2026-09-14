import test from 'node:test';
import assert from 'node:assert/strict';
import {comprobarParidadRevisada} from './paridad-revisada.mjs';

const ahora=Date.parse('2026-09-14T15:00:00Z');
const h='a'.repeat(32),otro='b'.repeat(32);
function caso() {
  const padre={proyecto:'dctqcbznekcyxhjujuci',inicio_captura_utc:new Date(ahora-10_000).toISOString(),
    paridad:Array.from({length:15},(_,i)=>({categoria:'categoria'+i,n:1,md5:h})),
    detalle:Array.from({length:15},(_,i)=>({categoria:'categoria'+i,clave:'objeto',md5:h})),
    externos:{objects:{'extension:ejemplo':h}}};
  const rama=structuredClone(padre);rama.proyecto='zgjyapayxvnvrgpiarod';
  rama.detalle[0].md5=otro;rama.paridad[0].md5=otro;
  rama.externos.objects['extension:ejemplo']=otro;
  const revision={rama:rama.proyecto,estado:'ACEPTADA_POR_PRIMARY',sha256_dictamen:'c'.repeat(64),
    catalogo:[{key:'categoria0|objeto',parent:h,branch:otro}],
    externos:[{key:'extension:ejemplo',parent:h,branch:otro}]};
  return {padre,rama,revision};
}
test('solo acepta exactamente las diferencias documentadas y no autoriza merge',()=>{
  const c=caso(),antes=JSON.stringify(c);
  const r=comprobarParidadRevisada(c.padre,c.rama,c.revision,ahora);
  assert.equal(r.estado,'PASS_PARIDAD_REVISADA');assert.equal(r.autoriza_merge,false);
  assert.equal(r.diferencias_catalogo,1);assert.equal(r.diferencias_externas,1);
  assert.equal(JSON.stringify(c),antes,'No normalizar ni modificar las capturas');
});
const mutantes={
  'diferencia adicional en la misma categoría':c=>{c.rama.detalle.push({categoria:'categoria0',clave:'extra',md5:h});c.rama.paridad[0].n++;},
  'diferencia adicional externa':c=>{c.rama.externos.objects['relation:auth.users']=h;},
  'hash de la excepción cambió':c=>{c.rama.detalle[0].md5='d'.repeat(32);},
  'hash del padre cambió':c=>{c.padre.detalle[0].md5=otro;},
  'objeto desaparecido':c=>{c.rama.detalle.splice(1,1);c.rama.paridad[1].n=0;},
  'excepción ya inexistente':c=>{c.rama.detalle[0].md5=h;},
  'claves duplicadas por truncamiento':c=>{c.rama.detalle.push(c.rama.detalle[0]);c.rama.paridad[0].n++;},
  'excepción duplicada':c=>{c.revision.catalogo.push(c.revision.catalogo[0]);},
  'categoría duplicada':c=>{c.rama.paridad[1]=c.rama.paridad[0];},
  'resumen alterado sin detalle':c=>{c.rama.paridad[1].md5=otro;},
  'conteo incoherente':c=>{c.rama.paridad[1].n++;},
  'rama incorrecta':c=>{c.rama.proyecto='abcdefghijklmnopqrst';},
  'producción como rama':c=>{c.revision.rama=c.padre.proyecto;c.rama.proyecto=c.padre.proyecto;},
  'captura antigua':c=>{c.padre.inicio_captura_utc=new Date(ahora-60_001).toISOString();},
  'captura futura':c=>{c.rama.inicio_captura_utc=new Date(ahora+1).toISOString();},
  'revisión pendiente':c=>{c.revision.estado='PENDIENTE';},
  'dictamen sin huella':c=>{c.revision.sha256_dictamen='';},
};
for(const [nombre,mutar] of Object.entries(mutantes)) test('rechaza '+nombre,()=>{
  const c=caso();mutar(c);
  assert.throws(()=>comprobarParidadRevisada(c.padre,c.rama,c.revision,ahora));
});
test('distingue dos sobrecargas con prefijo mayor de 63 caracteres',()=>{
  const c=caso(),prefijo='funcion_extremadamente_larga_para_comprobar_claves_completas_'.repeat(2);
  for(const destino of [c.padre,c.rama]) {
    destino.detalle.push({categoria:'categoria1',clave:prefijo+'(integer)',md5:h},
      {categoria:'categoria1',clave:prefijo+'(text)',md5:otro});destino.paridad[1].n+=2;
  }
  assert.equal(comprobarParidadRevisada(c.padre,c.rama,c.revision,ahora).estado,'PASS_PARIDAD_REVISADA');
});

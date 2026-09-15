// Verifica los recibos saneados; no conecta a ninguna base ni concede G7.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const leer=n=>JSON.parse(readFileSync(new URL(n,import.meta.url),'utf8'));
try {
const a=leer('conciliacion.json'),b=leer('postflight.json');
const roles=leer('roles.json').roles,fichas=leer('fichas.json').fichas,casos=leer('casos.json');
const complemento=leer('complemento.json');
const total=xs=>xs.reduce((n,x)=>n+x,0);
for(const foto of [a,b]) {
  assert.equal(foto.solo_lectura,'on');
  for(const clave of ['diferencias_cartera_capital','diferencias_metricas_capital',
    'fuentes_duplicadas','sin_identidad_coherente','identidades_metricas_distintas']) {
    assert.equal(foto.conciliacion[clave],0,clave);
  }
  assert.ok(foto.conciliacion.fuentes_cartera>0);
  assert.equal(foto.conciliacion.fuentes_cartera,foto.conciliacion.fuentes_capital);
  assert.equal(foto.conciliacion.fuentes_capital,foto.conciliacion.fuentes_metricas);
  assert.equal(total(foto.por_empresa.map(x=>x.inversiones)),foto.conciliacion.fuentes_cartera);
  assert.equal(foto.identidades.sin_documento_verificado,0);
}
for(const campo of ['banderas','piloto','funciones','fotos_selladas']) assert.deepEqual(b[campo],a[campo],campo);
assert.deepEqual(a.banderas,{ficha_360_neutral:false,postventa_neutral:false,
  resolver_en_puertas:true,inversiones_escritura:false,metricas_multiempresa_sombra:false});
assert.ok(a.piloto.activo);
assert.equal(roles.length,24);
assert.equal(new Set(roles.map(x=>x.actor)).size,24);
assert.deepEqual(Object.fromEntries(['gerencia','supervisor','vendedor','coordinador'].map(rol=>
  [rol,roles.filter(x=>x.rol===rol).length])),{gerencia:2,supervisor:3,vendedor:18,coordinador:1});
assert.equal(roles.filter(x=>x.piloto).length,4);
for(const r of roles) {
  assert.ok(r.cuenta_auth_vigente);
  if(r.rol==='coordinador') assert.equal(r.error_cartera,'42501');
  else {
    assert.equal(r.error_cartera,null);
    assert.equal(r.cartera.habilitada,r.piloto);
    assert.equal(r.cartera.escritura_habilitada,r.piloto);
  }
  assert.equal(r.error_postventa,null);
  assert.equal(r.postventa.habilitada,r.piloto);
}
const muestra=a.muestra_retrospectiva;
assert.equal(muestra.fuentes,20);
assert.equal(muestra.fuentes_hash.length,20);
assert.equal(new Set(muestra.fuentes_hash.map(x=>x.empresa+':'+x.fuente)).size,20);
const personas=[...new Set(muestra.fuentes_hash.map(x=>x.persona))].sort();
assert.equal(personas.length,19);
assert.deepEqual(fichas.map(x=>x.persona).sort(),personas);
assert.equal(total(fichas.map(x=>x.inversiones)),25);
for(const f of fichas) {
  assert.equal(f.error,null); assert.ok(f.fuente_estable);
  assert.equal(f.diferencias_fuentes,0); assert.equal(f.diferencias_totales,0);
}
assert.equal(casos.sin_responsable.length,a.identidades.sin_responsable);
for(const c of casos.sin_responsable) {assert.ok(c.visible);assert.equal(c.nueva_inversion,false);}
assert.ok(complemento.ancla_coincide);
assert.equal(complemento.desglose.diferencias,0);
assert.equal(complemento.desglose.filas_esperadas,complemento.desglose.filas_nucleo);
assert.equal(complemento.desglose.renovaciones_con_suma_incorrecta,0);
for(const c of complemento.candidato_reasignado) {
  assert.ok(c.stock_coincide&&c.atribucion_coincide&&c.autor_preservado_coincide);
}
const archivos=['conciliacion.json','roles.json','fichas.json','casos.json','postflight.json','guardias.json','complemento.json'];
const resultado={estado:'PASS',alcance:'Consistencia de la evidencia técnica retrospectiva; G7 permanece ABIERTO.',
  corte:a.corte,postflight:b.corte,fuentes:a.conciliacion.fuentes_cartera,identidades:a.identidades.total,
  muestra_fuentes:20,fichas:19,inversiones_en_fichas:25,cuentas:24,analistas:18,
  capacidades_piloto:4,funciones_banderas_y_sello_conservados:true,
  sha256:Object.fromEntries(archivos.map(f=>[f,createHash('sha256').update(readFileSync(new URL(f,import.meta.url))).digest('hex')]))};
writeFileSync(new URL('verificacion.json',import.meta.url),JSON.stringify(resultado,null,2)+'\n');
console.log(JSON.stringify(resultado,null,2));
} catch(error) {
  writeFileSync(new URL('verificacion.json',import.meta.url),JSON.stringify({estado:'FAIL',
    alcance:'No autoriza G7 ni activación.',error:error.message},null,2)+'\n');
  throw error;
}

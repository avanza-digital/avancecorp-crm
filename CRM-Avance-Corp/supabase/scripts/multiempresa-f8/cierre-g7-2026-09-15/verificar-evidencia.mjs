// Verifica los recibos reales y sintéticos; no conecta a una base ni concede G7.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const leer=n=>JSON.parse(readFileSync(new URL(n,import.meta.url),'utf8'));
try {
const a=leer('conciliacion.json'),b=leer('postflight.json');
const roles=leer('roles.json').roles,fichas=leer('fichas.json').fichas,casos=leer('casos.json');
const complemento=leer('complemento.json');
const economico=leer('ensayo-local.json'),general=leer('roles-general-local.json');
const transicion=leer('transicion-local.json'),funciones=leer('versiones-nucleo.json');
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
for(const r of [economico,general,transicion]) {assert.equal(r.estado,'PASS');assert.equal(r.banco,'g7_cierre_20260915');}
assert.equal(funciones.length,65);
assert.equal(new Set(funciones.map(f=>f.firma)).size,65);
assert.equal(economico.funciones_verificadas,65);
assert.equal(economico.huella_funciones,createHash('sha256').update(JSON.stringify(funciones)).digest('hex'));
assert.equal(economico.resultados.find(r=>r.reintentos===10)?.historia_sin_cambios,true);
const carreras=economico.resultados.filter(r=>r.sesiones_coincidentes===2);
assert.equal(carreras.length,5);
assert.ok(carreras.every(r=>r.codigos.length===2&&r.codigos.includes('OK')));
assert.equal(general.roles.length,21);
assert.equal(general.roles.filter(r=>r.fuera_de_ambito_probado).length,4);
assert.equal(general.roles.filter(r=>r.directorio_ficha_avance_probada).length,2);
const contextos={coordinador:[false,false],perfil_inactivo:[false,false],
  equipo_inactivo:[false,false],directorio_sin_equipo:[true,false],
  directorio_sin_equipo_inactivo:[false,false],directorio_equipo_inactivo:[false,false]};
for(const [caso,[lectura,escritura]] of Object.entries(contextos)) {
  const filas=general.roles.filter(r=>r.caso===caso);assert.equal(filas.length,1,caso);
  assert.equal(filas[0].lectura_esperada,lectura,caso);
  assert.equal(filas[0].escritura_esperada,escritura,caso);
}
for(const r of general.roles) {
  if(r.lectura_esperada) {
    assert.equal(r.error_f5,null);assert.equal(r.f5.habilitada,true);
    assert.equal(r.f5.escritura_habilitada,r.escritura_esperada);
  } else {assert.equal(r.error_f5,'42501');assert.equal(r.error_lista,'42501');}
  if(r.error_f6===null) assert.equal(r.f6.habilitada,r.escritura_esperada);
  else {assert.equal(r.error_f6,'42501');assert.equal(r.escritura_esperada,false);}
}
assert.equal(transicion.resultados.length,5);
assert.ok(transicion.resultados.every(r=>r.estado==='PASS'));
assert.equal(Object.keys(transicion.huellas_economicas_conservadas).length,16);
const archivos=['conciliacion.json','roles.json','fichas.json','casos.json','postflight.json','guardias.json','complemento.json',
  'ensayo-local.mjs','ensayo-local.json','roles-general-local.sql','roles-general-local.json',
  'transicion-local.mjs','transicion-local.json','versiones-nucleo.json'];
const resultado={estado:'PASS',alcance:'Coherencia retrospectiva real y controles SQL sintéticos separados; G7 permanece ABIERTO.',
  corte:a.corte,postflight:b.corte,fuentes:a.conciliacion.fuentes_cartera,identidades:a.identidades.total,
  muestra_fuentes:20,fichas:19,inversiones_en_fichas:25,cuentas:24,analistas:18,
  capacidades_piloto:4,funciones_banderas_y_sello_conservados:true,
  banco_local:{reintentos:10,carreras:5,contextos_roles:21,controles_transicion:5,
    superficies_conservadas:16,funciones_cotejadas:65},
  sha256:Object.fromEntries(archivos.map(f=>[f,createHash('sha256').update(readFileSync(new URL(f,import.meta.url))).digest('hex')]))};
writeFileSync(new URL('verificacion.json',import.meta.url),JSON.stringify(resultado,null,2)+'\n');
console.log(JSON.stringify(resultado,null,2));
} catch(error) {
  writeFileSync(new URL('verificacion.json',import.meta.url),JSON.stringify({estado:'FAIL',
    alcance:'No autoriza G7 ni activación.',error:error.message},null,2)+'\n');
  throw error;
}

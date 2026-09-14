// Comparación puntual después de investigar diferencias reales del catálogo.
// No cambia las capturas ni sustituye la revisión, las pruebas o la autorización.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const huella = x => createHash('sha256').update(JSON.stringify(x)).digest('hex');
const ordenar = xs => [...xs].sort((a,b) => a.key.localeCompare(b.key));
const md5 = x => assert.match(x,/^[a-f0-9]{32}$/);

function inventario(filas) {
  assert.ok(Array.isArray(filas));
  const mapa = new Map();
  for (const f of filas) {
    assert.equal(typeof f.categoria,'string');
    assert.ok(typeof f.clave==='string' && f.clave.length>0);
    md5(f.md5);
    const key=f.categoria+'|'+f.clave;
    assert.ok(!mapa.has(key),'Clave duplicada o truncada: '+key);
    mapa.set(key,f.md5);
  }
  return mapa;
}

function externos(objetos) {
  assert.ok(objetos && typeof objetos==='object' && !Array.isArray(objetos));
  for (const valor of Object.values(objetos)) md5(valor);
  return new Map(Object.entries(objetos));
}

function diferencias(a,b) {
  return ordenar([...new Set([...a.keys(),...b.keys()])]
    .filter(k=>a.get(k)!==b.get(k))
    .map(key=>({key,parent:a.get(key)??null,branch:b.get(key)??null})));
}

function comparar(a,b,documentadas) {
  assert.ok(Array.isArray(documentadas));
  const claves=new Set();
  for (const d of documentadas) {
    assert.deepEqual(Object.keys(d).sort(),['branch','key','parent']);
    assert.ok(typeof d.key==='string' && d.key.length>0);
    assert.ok(!claves.has(d.key),'Excepción duplicada');
    claves.add(d.key);
    if(d.parent!==null) md5(d.parent);
    if(d.branch!==null) md5(d.branch);
    assert.notEqual(d.parent,d.branch,'La excepción debe ser una diferencia real');
  }
  assert.deepEqual(diferencias(a,b),ordenar(documentadas),
    'Diferencias distintas de las investigadas: detener y revisar');
}

export function comprobarParidadRevisada(padre,rama,revision,ahora=Date.now()) {
  assert.equal(padre.proyecto,'dctqcbznekcyxhjujuci');
  assert.match(revision.rama,/^[a-z]{20}$/);
  assert.notEqual(revision.rama,padre.proyecto);
  assert.equal(rama.proyecto,revision.rama);
  assert.equal(revision.estado,'ACEPTADA_POR_PRIMARY');
  assert.match(revision.sha256_dictamen,/^[a-f0-9]{64}$/);
  const inicio=c=>Date.parse(c.inicio_captura_utc??c.precondiciones?.inicio_captura_utc);
  const fechas=[inicio(padre),inicio(rama)];
  assert.ok(Number.isFinite(ahora) && fechas.every(x=>Number.isFinite(x)
    && x<=ahora && ahora-x<=60_000),'Capturas antiguas o futuras');
  const a=inventario(padre.detalle),b=inventario(rama.detalle);
  const categorias=c=>c.paridad.map(x=>x.categoria).sort();
  assert.equal(padre.paridad.length,15);
  assert.equal(new Set(categorias(padre)).size,15);
  assert.deepEqual(categorias(rama),categorias(padre));
  for (const c of [padre,rama]) {
    assert.ok(c.detalle.every(x=>categorias(c).includes(x.categoria)));
    for (const fila of c.paridad) {
      md5(fila.md5);
      assert.equal(fila.n,c.detalle.filter(x=>x.categoria===fila.categoria).length,
        'Resumen y detalle deben provenir de la misma captura');
    }
  }
  comparar(a,b,revision.catalogo);
  comparar(externos(padre.externos.objects),externos(rama.externos.objects),revision.externos);
  const distintas=new Set(revision.catalogo.map(x=>x.key.split('|')[0]));
  for (const fila of padre.paridad) {
    if(!distintas.has(fila.categoria)) {
      assert.deepEqual(rama.paridad.find(x=>x.categoria===fila.categoria),fila,
        'Cambió una categoría sin diferencias documentadas');
    }
  }
  return {estado:'PASS_PARIDAD_REVISADA',autoriza_merge:false,
    padre:padre.proyecto,rama:revision.rama,
    diferencias_catalogo:revision.catalogo.length,diferencias_externas:revision.externos.length,
    sha256_padre:huella(padre),sha256_rama:huella(rama),sha256_revision:huella(revision)};
}

// Precondiciones y deriva del padre. No conecta, instala ni autoriza un merge.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const leer = nombre => readFileSync(new URL(nombre, import.meta.url), 'utf8');
const preflight = leer('preflight-instalacion.sql');
const paridad = leer('paridad-instalacion.sql');
const shaJson = valor => createHash('sha256').update(JSON.stringify(valor)).digest('hex');
export const firmas = [...preflight.matchAll(/^  \('([^']+)','[a-f0-9]{32}',/gm)]
  .map(x => x[1]).sort();
assert.equal(firmas.length, 14);
const categorias = ['esquemas','relaciones','columnas','funciones','triggers',
  'politicas','constraints','indices','vistas','default_acl','tipos','secuencias',
  'extensiones','publicaciones','event_triggers'].sort();
const banderas = {resolver_en_puertas:true,inversiones_escritura:false,
  ficha_360_neutral:false,postventa_neutral:false,metricas_multiempresa_sombra:false};

// Las dos subconsultas comparten snapshot. La fecha comprobada es la del BEGIN,
// no la de serialización ni la fecha declarada por un archivo de entorno.
const cuerpo = preflight.slice(preflight.indexOf('\nwith esperadas'),
  preflight.lastIndexOf('\nrollback;')).trim().replace(/;$/, '');
export const consultaCaptura = `begin isolation level repeatable read read only;
set local search_path='';
set local timezone='UTC';
set local lock_timeout='1s';
set local statement_timeout='30s';
select jsonb_build_object('precondiciones',(${cuerpo}),
  'paridad',(${paridad.trim().replace(/;$/, '')})) as captura;
rollback;`;

const envolver = cuerpo => `begin isolation level repeatable read read only;
set local search_path=''; set local timezone='UTC';
set local lock_timeout='1s'; set local statement_timeout='30s';
${cuerpo}\nrollback;`;
export const consultaParidad = envolver(`select jsonb_build_object(
  'inicio_captura_utc',transaction_timestamp(),
  'paridad',(${paridad.trim().replace(/;$/, '')})) as captura;`);
// Mismo CTE y misma sesión; solo cambia la proyección, sin cuerpos ni datos.
const corteDetalle=paridad.indexOf('), categorias as (');
assert.ok(corteDetalle>0,'Falta el CTE objetos del inventario');
export const consultaDetalle = envolver(`${paridad.slice(0,corteDetalle)})
select categoria,clave,md5(valor::text) as md5 from objetos order by categoria,clave;`);

const orden = xs => [...xs].sort((a,b) => a.categoria.localeCompare(b.categoria));
function validarParidad(lista) {
  assert.deepEqual(lista.map(x=>x.categoria).sort(),categorias,'Inventario incompleto');
  for(const x of lista) {
    assert.ok(Number.isSafeInteger(x.n)&&x.n>=0);
    assert.match(x.md5,/^[a-f0-9]{32}$/);
  }
}

export function comprobarParidad(padre,rama,refRama) {
  assert.equal(padre.proyecto,'dctqcbznekcyxhjujuci');
  assert.match(refRama,/^[a-z]{20}$/);
  assert.notEqual(refRama,padre.proyecto,'La rama debe ser exclusiva');
  assert.equal(rama.proyecto,refRama,'Rama distinta de la registrada para este ensayo');
  validarParidad(padre.paridad);validarParidad(rama.paridad);
  const inicio=c=>Date.parse(c.inicio_captura_utc??c.precondiciones?.inicio_captura_utc);
  assert.ok(Number.isFinite(inicio(padre))&&Number.isFinite(inicio(rama))
    &&Math.abs(inicio(padre)-inicio(rama))<=60_000,'Capturar padre y rama en la misma ventana');
  assert.deepEqual(orden(rama.paridad),orden(padre.paridad),
    'Paridad rechazada: obtener --consulta-detalle en ambos destinos e investigar');
  return {estado:'PASS_PARIDAD_RAMA',autoriza_merge:false,padre:padre.proyecto,
    rama:refRama,sha256_padre:shaJson(padre),sha256_rama:shaJson(rama)};
}
function validar(c) {
  // El ejecutor liga este valor al project_id usado realmente en MCP. El JSON
  // no es una atestación criptográfica ni permite verificar credenciales.
  assert.equal(c.proyecto,'dctqcbznekcyxhjujuci','Destino distinto del padre autorizado');
  const p=c.precondiciones;
  assert.equal(p.version,1);
  assert.deepEqual(p.banderas,banderas,'F3 ON y F4–F7 OFF obligatorios');
  assert.deepEqual(p.instalacion,{control:false,miembros:false,exclusion_demo:false},
    'El paquete no se reinstala ni continúa a ciegas una instalación parcial');
  assert.deepEqual(p.funciones.map(f=>f.firma).sort(),firmas,'Faltan firmas o hay duplicados');
  for(const f of p.funciones) {
    assert.equal(f.definicion_coincide,true,`Cambió ${f.firma}`);
    assert.equal(f.acl_exigida_coincide,true,`Cambió la ACL de ${f.firma}`);
    assert.equal(f.propietario_postgres,true,`Cambió el propietario de ${f.firma}`);
  }
  assert.equal(p.es_demo_not_null,true);
  assert.equal(p.proteccion_demo_presente,true);
  assert.ok(Array.isArray(p.fuentes)&&p.fuentes.length>0,'Falta el censo real');
  assert.equal(new Set(p.fuentes.map(f=>f.es_demo)).size,p.fuentes.length);
  for(const f of p.fuentes) {
    assert.equal(typeof f.es_demo,'boolean','Una marca demo NULL requiere investigar');
    assert.ok(Number.isSafeInteger(f.fuentes)&&f.fuentes>0);
    assert.ok(Number.isSafeInteger(f.brechas_identidad)&&f.brechas_identidad>=0
      &&f.brechas_identidad<=f.fuentes);
    if(!f.es_demo) assert.equal(f.brechas_identidad,0,'Hay nuevas brechas reales');
  }
  assert.ok(p.fuentes.some(f=>f.es_demo===false),'Falta el universo real');
  assert.ok(Number.isSafeInteger(p.historial.n)&&p.historial.n>0);
  assert.match(p.historial.ultima,/^\d{14}$/);
  assert.match(p.historial.md5_arrays,/^[a-f0-9]{32}$/);
  assert.match(p.catalogo_funciones.md5,/^[a-f0-9]{32}$/);
  assert.ok(Number.isSafeInteger(p.catalogo_funciones.n)&&p.catalogo_funciones.n>=14);
  validarParidad(c.paridad);
  const inicio=Date.parse(p.inicio_captura_utc),fin=Date.parse(p.fin_captura_utc);
  assert.ok(Number.isFinite(inicio)&&Number.isFinite(fin)&&fin>=inicio,'Fechas inválidas');
}

export function comprobarBase(base,actual,ahora=Date.now()) {
  validar(base);validar(actual);
  const inicio=Date.parse(actual.precondiciones.inicio_captura_utc);
  const fin=Date.parse(actual.precondiciones.fin_captura_utc);
  assert.ok(Number.isFinite(ahora)&&inicio<=ahora&&fin<=ahora&&ahora-inicio<=60_000,
    'La captura del padre debe comprobarse dentro de 60 segundos de su snapshot');
  assert.ok(inicio>Date.parse(base.precondiciones.inicio_captura_utc),
    'La captura viva debe ser posterior a la base del ensayo, no el mismo archivo');
  assert.deepEqual(actual.precondiciones.historial,base.precondiciones.historial,
    'Cambió el historial: integrar y volver a ensayar');
  assert.deepEqual(actual.precondiciones.catalogo_funciones,base.precondiciones.catalogo_funciones,
    'Cambió una función del padre');
  assert.deepEqual(orden(actual.paridad),orden(base.paridad),
    'Cambió estructura, permisos o configuración del catálogo');
  return {estado:'PASS_PRECONDICIONES_PADRE',autoriza_merge:false,
    proyecto:actual.proyecto,migraciones:actual.precondiciones.historial.n,
    comprobado_en:new Date(ahora).toISOString()};
}

export function verificarSql() {
  const sha=nombre=>createHash('sha256').update(readFileSync(new URL(nombre,import.meta.url))).digest('hex');
  assert.equal(sha('../../migrations/20260913215240_crm_f8_piloto_controlado.sql'),
    '0807e59bcaccfbce8d7af02dc67fcfa8a64686305aaa976d4840af16c86c18fe');
  assert.equal(sha('../../migrations/20260914025926_crm_f8_excluir_fuentes_demo.sql'),
    '0f7daa10f1e1ac1d71501795d0f0d45c64e58fa263426c7e27a56f5c0e73dc08');
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  verificarSql();
  const consultas={'--consulta':consultaCaptura,'--consulta-paridad':consultaParidad,
    '--consulta-detalle':consultaDetalle};
  if(process.argv.length===3&&Object.hasOwn(consultas,process.argv[2])) console.log(consultas[process.argv[2]]);
  else if(process.argv.length===6&&process.argv[2]==='--paridad-rama') {
    console.log(JSON.stringify(comprobarParidad(
      ...process.argv.slice(4).map(p=>JSON.parse(readFileSync(p,'utf8'))),process.argv[3])));
  }
  else {
    assert.equal(process.argv.length,4,'Uso: node verificar-base-instalacion.mjs base.json actual.json | --consulta');
    console.log(JSON.stringify(comprobarBase(...process.argv.slice(2).map(
      p=>JSON.parse(readFileSync(p,'utf8'))))));
  }
}

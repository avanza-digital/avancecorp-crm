// Genera SQL revisable sin conexiones ni ejecución.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
function parametros(opciones) {
  assert.match(opciones?.responsable_id,uuid,'Responsable explícito inválido');
  assert.match(opciones?.referencia,/^[A-Z0-9_-]{4,60}$/,'Referencia de autorización inválida');
  return {responsable_id:opciones.responsable_id,referencia:opciones.referencia};
}
function renderizar(archivo,config) {
  const plantilla=readFileSync(new URL(archivo,import.meta.url),'utf8');
  assert.equal(plantilla.split('__CONFIG_JSON__').length,2,'Marcador alterado');
  return plantilla.replace('__CONFIG_JSON__',JSON.stringify(config));
}
export function crearReversa(opciones) {
  return renderizar('./revertir.sql',parametros(opciones));
}
export function crearActivacion(equipo,opciones) {
  assert.ok(Array.isArray(equipo)&&equipo.length===4,'Se requieren cuatro participantes');
  const filas=equipo.map(p=>{
    assert.match(p.perfil_id,uuid,'Identificador inválido');
    assert.ok(['gerencia','supervisor','vendedor'].includes(p.rol_esperado),'Rol inválido');
    if(p.supervisor_id!==null) assert.match(p.supervisor_id,uuid,'Supervisor inválido');
    return {perfil_id:p.perfil_id,rol_esperado:p.rol_esperado,supervisor_id:p.supervisor_id};
  });
  assert.equal(new Set(filas.map(p=>p.perfil_id)).size,4,'Participantes duplicados');
  for(const [rol,n] of [['gerencia',1],['supervisor',1],['vendedor',2]])
    assert.equal(filas.filter(p=>p.rol_esperado===rol).length,n,'Composición incorrecta');
  return renderizar('./activar.sql',{equipo:filas,...parametros(opciones)});
}

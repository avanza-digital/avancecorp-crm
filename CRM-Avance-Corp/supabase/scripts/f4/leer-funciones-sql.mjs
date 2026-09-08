import assert from 'node:assert/strict';

// Solo el formato de las funciones generado por este paquete. El cuerpo puede
// contener SQL y otros dollar quotes; se cierra exclusivamente con SU etiqueta.
export function funcionesDelSql(sql) {
  const funciones = [];
  const encabezado = /create or replace function\s+([a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*)\s*\(/ig;
  let m;
  while ((m = encabezado.exec(sql))) {
    const desde = m.index;
    const etiqueta = /\bas\s+(\$[a-z_0-9]*\$)/i.exec(sql.slice(encabezado.lastIndex));
    assert(etiqueta, `Falta el cuerpo de ${m[1]}`);
    const inicio = encabezado.lastIndex + etiqueta.index + etiqueta[0].length;
    const fin = sql.indexOf(etiqueta[1], inicio);
    assert(fin > inicio, `Cuerpo sin cierre en ${m[1]}`);
    funciones.push({ nombre: m[1].toLowerCase(), body: sql.slice(inicio, fin),
      definicion: sql.slice(desde, fin + etiqueta[1].length) + ';' });
    encabezado.lastIndex = fin + etiqueta[1].length;
  }
  assert.equal(new Set(funciones.map(f => f.nombre)).size, funciones.length, 'Funciones duplicadas o parser fuera del contrato');
  return funciones;
}

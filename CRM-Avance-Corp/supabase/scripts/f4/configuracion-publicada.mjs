import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
// El dump schema-only no contiene esta configuración. Reproduce exclusivamente
// los nueve pares ya declarados en la migración publicada; no inventa permisos.
const migracion=readFileSync(new URL('../../migrations/20260830170000_crm_f5_b_una_pregunta_por_capacidad.sql',import.meta.url),'utf8');
const inicio='insert into private.pares_autoridad (rol_portal, rol_crm, razon) values';
const fin='on conflict (rol_portal, rol_crm) do update set razon = excluded.razon;';
assert.equal(migracion.split(inicio).length,2);assert.equal(migracion.split(fin).length,2);
export const paresAutoridadSql=migracion.slice(migracion.indexOf(inicio),migracion.indexOf(fin)+fin.length)
 .replace(fin,'on conflict (rol_portal, rol_crm) do nothing;');

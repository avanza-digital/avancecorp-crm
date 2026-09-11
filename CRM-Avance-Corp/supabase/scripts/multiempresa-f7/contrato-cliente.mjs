// El banco real usa exactamente el esquema y la integridad del consumidor.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {MetricasMultiempresaSchema,informeMultiempresaCompleto,estadoConciliacion}
  from '../../../app/src/lib/metricas-multiempresa.ts';
const {safeParse}=createRequire(new URL('../../../app/package.json',import.meta.url))('valibot');
export {estadoConciliacion};
export function verificarContrato(payload) {
  const r=safeParse(MetricasMultiempresaSchema,payload);
  assert.equal(r.success,true,r.issues?.map(i=>i.message).join('; '));
  assert.equal(informeMultiempresaCompleto(r.output),true,'El JSON real no cumple la integridad del consumidor');
  return r.output;
}

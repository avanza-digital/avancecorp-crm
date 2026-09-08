import assert from 'node:assert/strict';
import { randomInt, randomUUID } from 'node:crypto';
import { sql, literal as q, rpc } from './banco-local.mjs';
import { comprobar as ok } from './portal-fixture.mjs';

// Semilla de una ficha histórica sin lead ni Portal. Documento y responsable
// se verifican/asignan por las puertas reales de Gerencia; la fusión nunca se
// fabrica con UPDATE, ni se manipulan reservas/claims para hacerla viable.
export async function crearCanonica({ gerente, responsable, creador, tipo = 'CE' }) {
  const persona = randomUUID();
  let documento;
  do { documento = `${tipo === 'CE' ? '009' : 'F4'}${String(randomInt(1_000_000)).padStart(6, '0')}`; }
  while (sql(`select count(*) from crm.inversionista_identificadores where documento_normalizado=${q(documento)}`) !== '0');
  sql(`insert into crm.inversionistas(id,creado_por) values(${q(persona)},${q(creador)})`);
  ok(await rpc('corregir_documento_inversionista_fn', { p_inversionista: persona, p_tipo: tipo,
    p_documento: documento, p_motivo: 'Verificación de ficha histórica ficticia para ensayo de fusión' }, gerente), 'Identificar ficha histórica');
  ok(await rpc('reasignar_responsable_relacion_fn', { p_inversionista: persona,
    p_nuevo_responsable: responsable, p_motivo: 'Asignación de ficha histórica ficticia del ensayo' }, gerente), 'Asignar ficha histórica');
  return { persona, documento, tipo };
}

export async function fusionar(perdedora, canonica, gerente) {
  const p = ok(await rpc('fusion_previsualizar_fn', { p_perdedora: perdedora, p_canonica: canonica }, gerente), 'Previsualizar fusión');
  assert.equal(p.viable, true, `Fusión no viable: ${p.bloqueos?.join(' · ')}`);
  return ok(await rpc('fusionar_inversionistas_fn', { p_perdedora: perdedora, p_canonica: canonica,
    p_hash: p.hash, p_motivo: 'Fusión autorizada de dos fichas ficticias durante el ensayo F4' }, gerente), 'Fusionar por puerta canónica');
}

export const firmaIntencion = c => sql(`select md5(jsonb_build_object('datos',datos,'hash',hash_payload,
  'origen',inversionista_id,'contexto',auth_contexto,'claim',auth_claim_id)::text)
  from crm.inversion_solicitudes where id=${q(c.solicitud)}`);

export const firmaSaga = c => sql(`select coalesce((select md5(to_jsonb(m)::text)
  from crm.inversion_solicitudes s join crm.multiempresa_idempotencia m
    on m.clave='auth_persona:'||coalesce(s.auth_contexto->>'inversionista_id',s.inversionista_id::text)
    and m.resultado->>'claim_id'=s.auth_claim_id::text where s.id=${q(c.solicitud)}),'ausente')`);

import assert from 'node:assert/strict';
import { randomUUID, randomInt } from 'node:crypto';
import { sql, literal as q, rpc } from './banco-local.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';

export function comprobar(r, nombre) {
  assert.equal(r.ok, true, `${nombre}: ${r.status} ${r.data?.message ?? r.data?.error ?? ''}`);
  return r.data;
}
export const contadoresPortal = () => JSON.parse(sql(`select jsonb_build_object(
  'auth',(select count(*) from auth.users),'perfiles',(select count(*) from public.perfiles),
  'personas',(select count(*) from crm.inversionistas),'leads',(select count(*) from crm.leads),
  'contratos',(select count(*) from public.contratos),'cuotas',(select count(*) from public.cronograma_pagos),
  'cuentas',(select count(*) from crm.cuentas_bancarias),'inversiones',(select count(*) from crm.inversiones),
  'jobs',(select count(*) from private.contrato_pdf_jobs))`));

/** Antecedente comercial ficticio: identidad y cierre por la RPC existente. */
export async function prepararPersonaPortal({ vendedor, token, etiqueta, correo }) {
  const lead = randomUUID();
  const solicitud = randomUUID();
  let documento;
  do { documento = `94${String(randomInt(1_000_000)).padStart(6, '0')}`; }
  while (sql(`select count(*) from crm.inversionista_identificadores where documento_normalizado=${q(documento)}`) !== '0');
  const nombre = `PERSONA FICTICIA F4 PORTAL ${etiqueta.toUpperCase()}`;
  sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
    values(${q(lead)},${q(nombre)},${q(`999${documento.slice(2)}`)},1000,'propuesta_enviada',${q(vendedor)},${q(vendedor)},'otro');`);
  const cierre = comprobar(await rpc('convertir_lead_externo', {
    p_lead_id: lead, p_cooperativa: 'qorilazo', p_monto: 1000, p_moneda: 'PEN',
    p_documento_tipo: 'DNI', p_documento: documento, p_nombre: nombre,
    p_numero_transaccion: `F4-PORTAL-${lead}`, p_referencia: 'ANTECEDENTE FICTICIO PORTAL',
    p_vence_en: '2027-09-07', p_nota: 'Prueba de recuperación; sin dinero real',
  }, token), 'Crear antecedente Qorilazo');
  const persona = sql(`select inversionista_id from crm.leads where id=${q(lead)}`);
  assert(uuidValido(persona));
  const datos = { inversionista_id: persona, empresa: 'avance',
    ...contratoPrueba(null, vendedor, { inicio: '2026-09-01', capital: 1800 }),
    alta_portal: { correo: correo ?? `f4.portal.${solicitud}@pruebas.example`,
      nombre_completo: nombre, telefono: `999${documento.slice(2)}`,
      domicilio: 'CALLE FICTICIA DEL ENSAYO 123, LIMA' },
  };
  return { persona, lead, solicitud, documento, datos, cierre };
}
const uuidValido = valor => /^[a-f0-9-]{36}$/.test(valor);

export async function llamarHandler(handler, solicitud, tokenUsuario, tokenSaga) {
  const r = await handler(new Request('http://127.0.0.1:56321/functions/v1/crm-inversion-portal', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tokenUsuario}` },
    body: JSON.stringify({ solicitud_id: solicitud, ...(tokenSaga ? { token: tokenSaga } : {}) }),
  }));
  return { ok: r.ok, status: r.status, data: await r.json() };
}

export function estadoAcceso(solicitud) {
  return JSON.parse(sql(`select jsonb_build_object('estado',s.estado,'inversion',s.inversion_id,
    'saga',m.resultado->>'estado','auth',m.resultado->>'auth_user_id','perfil',i.perfil_id,
    'perfilesCreados',(select count(*) from public.perfiles p where p.id=(m.resultado->>'auth_user_id')::uuid),
    'version',m.version,'leaseHasta',m.resultado->>'lease_hasta')
    from crm.inversion_solicitudes s join crm.inversionistas i on i.id=s.inversionista_id
    left join crm.multiempresa_idempotencia m on m.resultado->>'claim_id'=s.auth_claim_id::text
    where s.id=${q(solicitud)}`));
}

import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { sql, literal as q, leer, http } from './banco-local.mjs';

const f = leer('fixtures.json');
const base = leer('operaciones-base.json');
const contrato = sql('select contrato_id from crm.inversiones where contrato_id is not null order by id limit 1');
assert(contrato, 'Primero crea una inversión Avance en el banco');
const antes = sql(`select jsonb_build_object('contratos',(select count(*) from public.contratos),
  'inversiones',(select count(*) from crm.inversiones),'borrados',(select count(*) from private.contrato_eliminaciones),
  'jobs',(select count(*) from private.contrato_pdf_jobs))`);
const rechazo = await http('/rest/v1/rpc/contrato_eliminacion_preparar', {
  admin: true, body: { p_contrato_id: contrato, p_actor_id: f.usuarios.gerencia.id },
  headers: { 'Content-Profile': 'crm', 'Accept-Profile': 'crm' },
});
assert.equal(rechazo.ok, false);
assert.equal(rechazo.data.code, '55000');
assert.match(rechazo.data.message, /historial de inversiones/);
assert.equal(sql(`select count(*) from private.contrato_eliminaciones where contrato_id=${q(contrato)}`), '0');

// Caso contrario, sin ejecutar el borrado de Storage: la reserva se crea y
// después se intenta enlazar esa fuente. TODO el ensayo se revierte al salir.
const historico = base.contratos.inicial.id;
assert.equal(sql(`select count(*) from crm.inversiones where contrato_id=${q(historico)}`), '0');
sql(`begin;
  do $ensayo$ declare rechazado boolean:=false; begin
    perform crm.contrato_eliminacion_preparar(${q(historico)},${q(f.usuarios.gerencia.id)});
    begin
      perform private.inversion_vincular_fuente(${q(base.identidades.avance)},${q(historico)},null,${q(f.usuarios.gerencia.id)},false);
    exception when sqlstate '55000' then rechazado:=true;
    end;
    if not rechazado then raise exception 'Se permitió enlazar una fuente con borrado reservado'; end if;
    if exists(select 1 from crm.inversiones where contrato_id=${q(historico)}) then
      raise exception 'El intento rechazado dejó una inversión';
    end if;
  end; $ensayo$;
  rollback;`);
assert.equal(sql(`select jsonb_build_object('contratos',(select count(*) from public.contratos),
  'inversiones',(select count(*) from crm.inversiones),'borrados',(select count(*) from private.contrato_eliminaciones),
  'jobs',(select count(*) from private.contrato_pdf_jobs))`), antes);
writeFileSync(new URL(`../evidencia-f4/conservacion-historia-${randomUUID()}.json`, import.meta.url), JSON.stringify({
  entorno, terminadoEn: new Date().toISOString(),
  borradoDeContratoVinculadoRechazadoAntesDeReservar: true,
  fuenteConBorradoReservadoNoSeVincula: true,
  contratosInversionesPdfEHistorialConservados: true,
  alcance: 'Protección mutua entre enlace económico y preparación del borrado. No equivale al backfill histórico F2.',
}, null, 2) + '\n', {flag:'wx'});
console.log('Historia F4: borrado rechazado antes de Storage y enlace rechazado si el borrado ya se preparó; cero efectos finales del ensayo.');

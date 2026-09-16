// Operaciones sintéticas por las RPC reales; destino fijo en banco.mjs.
import {randomUUID,randomInt} from 'node:crypto';
import assert from 'node:assert/strict';
import {sql,objeto,q,j} from './banco.mjs';
export function crearOperaciones(actor) {
  const lead=randomUUID(),nombre='PERSONA FICTICIA REVERSA F9';
  const claims=`set local role authenticated;set local request.jwt.claim.sub=${q(actor)};`;
  const rpc=exp=>objeto(`begin;${claims}select ${exp};commit;`);
  sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id,creado_por)
    values(${q(lead)},${q(nombre)},${q('+519'+randomInt(10000000,99999999))},1000,${q(actor)},${q(actor)})`);
  rpc(`crm.convertir_lead_externo(${q(lead)},'qorilazo',1000,'PEN','DNI',${q(randomInt(88000000,89999999))},
    ${q(nombre)},${q('F9-INICIAL-'+lead)},'CONSTANCIA FICTICIA',null,null,12,12)`);
  const persona=sql(`select inversionista_id from crm.leads where id=${q(lead)}`);
  assert.match(persona,/^[a-f0-9-]{36}$/);
  const fecha=sql("select (now() at time zone 'America/Lima')::date");
  const vence=sql(`select private.coopac_validar_condiciones(${q(fecha)},12,12)`);
  const inversiones=[];
  for(const empresa of ['prodelco','qorilazo']) {
    const id=randomUUID(),datos={inversionista_id:persona,empresa,monto:123,moneda:'PEN',
      fecha_comercial:fecha,vence_en:vence,plazo_meses:12,tasa_anual:12,
      numero_transaccion:'F9-'+id,referencia:'REVERSA F9 FICTICIA',evidencia:{ruta:persona+'/'+id+'/comprobante.pdf'}};
    rpc(`crm.preparar_inversion_fn(${q(id)},${j(datos)})`);
    // Metadatos Storage locales; este ensayo no acredita subida HTTP.
    sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',
      ${q(datos.evidencia.ruta)},'{"size":12,"mimetype":"application/pdf"}')`);
    const res=rpc(`crm.confirmar_inversion_revisada_fn(${q(id)},0)`);
    assert.ok(res.inversion_id,JSON.stringify(res));
    inversiones.push({solicitud:id,inversion:res.inversion_id,empresa});
  }
  return {persona,inversiones};
}

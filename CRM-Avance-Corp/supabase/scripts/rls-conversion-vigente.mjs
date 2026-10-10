// Recorrido compartido REAL para el gate: cada escritura económica pasa por
// Auth/PostgREST/Storage con el cliente del actor. Sin service_role, SQL ni mocks.
import { createHash, randomUUID, randomBytes } from 'node:crypto';
import { contratoPrueba } from './f4/operaciones-fixture.mjs';
import { crearHandlerAccesoInversion } from '../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aUN0AAAAASUVORK5CYII=', 'base64');
const fecha = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date());

export function claveConversion(lead, operacion) {
  const h = createHash('sha256').update(JSON.stringify(['rls-conversion-vigente', lead, operacion])).digest('hex');
  return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;
}

async function reconocer(client, lead, tipo, documento, nombre) {
  return client.schema('crm').rpc('preparar_persona_lead_inversion_fn', {
    p_lead: lead, p_tipo_documento: tipo, p_documento: documento, p_nombre: nombre,
  });
}

async function confirmar(client, clave, datos, { comprobante = false } = {}) {
  const preparado = await client.schema('crm').rpc('preparar_inversion_fn', { p_clave: clave, p_datos: datos });
  if (preparado.error) return preparado;
  // Un replay no sobrescribe un comprobante inmutable. La confirmación sigue
  // invocándose por HTTP: es el servidor quien debe devolver reintento=true.
  if (comprobante && preparado.data.estado !== 'confirmada') {
    const subida = await client.storage.from('f4-comprobantes').upload(datos.evidencia.ruta, png,
      { contentType: 'image/png', upsert: false });
    if (subida.error) return subida;
  }
  return client.schema('crm').rpc('confirmar_inversion_revisada_fn', {
    p_solicitud: clave, p_revision_datos_esperada: preparado.data.revision_datos,
  });
}

export async function convertirCoopVigente(client, args) {
  const persona = await reconocer(client, args.p_lead_id, args.p_documento_tipo, args.p_documento, args.p_nombre);
  if (persona.error) return persona;
  const id = claveConversion(args.p_lead_id, args.p_numero_transaccion);
  const fin = `${Number(fecha.slice(0,4)) + 1}${fecha.slice(4)}`;
  return confirmar(client, id, {
    inversionista_id: persona.data.inversionista_id, lead_id: args.p_lead_id,
    empresa: args.p_cooperativa, moneda: args.p_moneda, monto: args.p_monto,
    fecha_comercial: fecha, vence_en: args.p_vence_en ?? fin,
    plazo_meses: args.p_plazo_meses ?? 12, tasa_anual: args.p_tasa_anual ?? 18,
    numero_transaccion: args.p_numero_transaccion, referencia: args.p_referencia ?? 'COMPROBANTE SINTETICO RLS',
    ...(args.p_nota ? { nota: args.p_nota } : {}),
    evidencia: { ruta: `${persona.data.inversionista_id}/${id}/comprobante.png` },
  }, { comprobante: true });
}

// El handler se ejecuta en proceso (NO acredita un despliegue Edge). Todas sus
// llamadas a Auth y a las RPC usan HTTP real. La clave de servicio sólo se usa
// dentro del handler oficial de acceso, nunca para escribir la inversión.
// `numero` (OPCIONAL; fase 4 · bloque 2.3, 20261009210100): número de contrato con el que se corrige la solicitud
// (llega a `p_datos.contrato.numero_contrato`). Con esa migración la confirmación de un NO exento (D-17) sin número
// muere con 22023. Sin `numero`, el recorrido es idéntico al de antes (contratoPrueba no añade la clave).
export async function convertirAvanceVigente(client, {
  leadId, documento, vendedorId, apiUrl, anonKey, serviceKey, capital = 1000, numero,
}) {
  const persona = await reconocer(client, leadId, 'DNI', documento, 'PERSONA SINTETICA RLS');
  if (persona.error) return persona;
  const id = claveConversion(leadId, 'avance');
  if (persona.data.solicitud_id) {
    const actual = await client.schema('crm').rpc('solicitud_inversion_fn',{p_solicitud:id});
    if (actual.error) return actual;
    if (actual.data.estado === 'confirmada') return client.schema('crm').rpc('confirmar_inversion_revisada_fn',
      {p_solicitud:id,p_revision_datos_esperada:actual.data.revision_datos});
  }
  const datos = { inversionista_id:persona.data.inversionista_id,lead_id:leadId,empresa:'avance',
    contrato:{moneda:'PEN'},cronograma:[],cuenta:{},alta_portal:{correo:`rls.${id}@example.test`,
      nombre_completo:'PERSONA SINTETICA RLS',nombres:'PERSONA',apellidos:'SINTETICA RLS',
      telefono:'999888777',domicilio:'AVENIDA FICTICIA 123 LIMA'} };
  const preparado = await client.schema('crm').rpc('preparar_inversion_fn',{p_clave:id,p_datos:datos});
  if (preparado.error) return preparado;
  const {data:{session}} = await client.auth.getSession();
  const handler = crearHandlerAccesoInversion({supabaseUrl:apiUrl,anonKey,serviceKey});
  const respuesta = await handler(new Request(`${apiUrl}/functions/v1/crm-inversion-portal`,{
    method:'POST',headers:{Authorization:`Bearer ${session.access_token}`},
    body:JSON.stringify({solicitud_id:id,token:randomBytes(24).toString('hex')}),
  }));
  const acceso = await respuesta.json();
  if (!respuesta.ok) return {data:null,error:{code:String(respuesta.status),message:acceso.error},status:respuesta.status};
  const propuesta = contratoPrueba(acceso.perfil_id, vendedorId, { capital, inicio: fecha.slice(0,8) + '01', numero });
  delete propuesta.contrato.cliente_id;
  delete propuesta.contrato.analista_cierre_id;
  const corregida = await client.schema('crm').rpc('corregir_solicitud_inversion_fn',{
    p_solicitud:id,p_clave:randomUUID(),p_revision_datos_esperada:0,
    p_datos:{...datos,...propuesta},p_motivo:'Completar las condiciones ficticias tras crear el acceso de prueba',
  });
  if (corregida.error) return corregida;
  return client.schema('crm').rpc('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:1});
}

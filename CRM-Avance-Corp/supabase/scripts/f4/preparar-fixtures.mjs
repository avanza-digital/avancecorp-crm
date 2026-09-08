import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import { banco, sql, literal as q, usuarioAuth, guardar, leer, sesion, rpc } from './banco-local.mjs';

// No borra nada ni desactiva triggers/RLS. La primera ejecución exige base vacía;
// una ejecución posterior solo reutiliza la semilla de este mismo banco.
if (existsSync(join(banco, 'fixtures.json'))) {
  const f = leer('fixtures.json');
  for (const u of Object.values(f.usuarios)) {
    assert.equal(sql(`select count(*) from public.perfiles where id=${q(u.id)}::uuid`), '1');
  }
  console.log('Semilla F4 existente verificada; cero filas recreadas.');
} else {
  assert.equal(sql('select count(*) from public.perfiles'), '0', 'El banco debe estar vacío');
  const anterior = existsSync(join(banco, 'auth-fixtures.json')) ? leer('auth-fixtures.json') : null;
  const password = anterior?.password ?? `F4-${randomBytes(18).toString('hex')}`;
  const usuarios = anterior?.usuarios ?? {};
  guardar('auth-fixtures.json', { usuarios, password });
  for (const rol of ['gerencia', 'supervisor', 'supervisor_ajeno', 'vendedor', 'ajeno', 'directorio', 'cliente']) {
    if (!usuarios[rol]) usuarios[rol] = await usuarioAuth(rol, password);
    guardar('auth-fixtures.json', { usuarios, password });
  }
  // Guardar inmediatamente permite diagnosticar/reanudar un fallo de la semilla
  // sin crear otro Auth. Este archivo temporal contiene solo claves de prueba.
  guardar('auth-fixtures.json', { usuarios, password });
  const ids = Object.fromEntries(Object.entries(usuarios).map(([rol, u]) => [rol, u.id]));
  const perfil = (rol, portal, dni, asesor = null) => `insert into public.perfiles
    (id,nombre_completo,correo,rol,dni,tipo_documento,activo,asesor_perfil_id)
    values (${q(ids[rol])},${q(`PRUEBA F4 ${rol}`)},${q(usuarios[rol].email)},${q(portal)},
      ${q(dni)},'DNI',true,${q(asesor)});`;
  const politica = randomUUID();
  sql(`begin;
    ${perfil('gerencia', 'admin', '91000001')}
    ${perfil('supervisor', 'analista', '91000002')}
    ${perfil('supervisor_ajeno', 'analista', '91000006')}
    ${perfil('vendedor', 'analista', '91000003')}
    ${perfil('ajeno', 'analista', '91000004')}
    ${perfil('directorio', 'directorio', '91000005')}
    insert into crm.equipo(perfil_id,rol_crm,supervisor_id) values
      (${q(ids.gerencia)},'gerencia',null),
      (${q(ids.supervisor)},'supervisor',${q(ids.gerencia)}),
      (${q(ids.supervisor_ajeno)},'supervisor',${q(ids.gerencia)}),
      (${q(ids.vendedor)},'vendedor',${q(ids.supervisor)}),
      (${q(ids.ajeno)},'vendedor',${q(ids.supervisor_ajeno)}),
      (${q(ids.directorio)},'directorio',null);
    ${perfil('cliente', 'cliente', '92000001', ids.vendedor)}
    insert into crm.empresas(clave,nombre_legal,nombre_visible,monedas,crea_contrato_avance,
      requiere_portal,exige_numero_transaccion,fuente_capital) values
      ('avance','Avance prueba','Avance prueba',array['PEN','USD'],true,true,false,'contratos'),
      ('qorilazo','Qorilazo prueba','Qorilazo prueba',array['PEN'],false,false,true,'cierres_externos'),
      ('prodelco','Prodelco prueba','Prodelco prueba',array['PEN'],false,false,true,'cierres_externos');
    insert into crm.multiempresa_flags(nombre,activo) values
      ('resolver_en_puertas',true),('inversiones_escritura',false),('ficha_360_neutral',false);
    insert into crm.sla_politicas(id,version,vigente_desde,zona_horaria,tipo_reloj,
      primera_gestion_minutos,primer_contacto_minutos,publicada_por)
    values(${q(politica)},1,'2020-01-01T00:00:00-05:00','America/Lima','corrido',60,120,${q(ids.gerencia)});
    insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
    select ${q(politica)},etapa,1440 from unnest(array['nuevo','contactado','reunion_agendada','propuesta_enviada']) etapa;
    select private.asegurar_identidad_perfil(${q(ids.cliente)},'f4_prueba');
    commit;`);
  const identidadCliente = sql(`select id from crm.inversionistas where perfil_id=${q(ids.cliente)}`);
  guardar('fixtures.json', { usuarios, password, identidadCliente, politica, creado_en: new Date().toISOString() });
}
const f = leer('fixtures.json');
const token = await sesion(f.usuarios.vendedor, f.password);
const r = await rpc('bandera_activa', { p_nombre: 'resolver_en_puertas' }, token);
assert.equal(r.status, 200, JSON.stringify(r.data));
assert.equal(r.data, true);
console.log('Banco F4: 7 Auth reales de prueba, dos equipos, identidad y API CRM comprobados.');

import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'

// Banco Docker ficticio y exclusivo, nunca una URL productiva.
function sql(sentencia, rechazo) {
  const resultado = spawnSync('docker', ['exec', '-i', 'supabase_db_crm-avance-corp-local',
    'psql', '-XqAt', '-U', 'postgres', '-d', 'ranking_origen_correccion_20260928',
    '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    input: `begin; set local statement_timeout='15s'; ${sentencia}; rollback;`,
    encoding: 'utf8', timeout: 30000,
  })
  if (rechazo) {
    assert.notEqual(resultado.status, 0)
    assert.match(resultado.stderr, rechazo)
    return
  }
  assert.equal(resultado.status, 0, resultado.stderr)
  return resultado.stdout.trim().split('\n').at(-1)
}
const identidad = n => `select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-${String(n).padStart(12, '0')}',true); set local role authenticated;`
const alta = origen => `select crm.crear_lead_si_disponible('PRUEBA CANAL CONCRETO','+51988009901',${origen},1000,'PEN')`
for (const [n, rol] of [[1, 'supervisor'], [2, 'vendedor'], [3, 'gerencia']]) {
  for (const origen of ['landing', 'formulario', 'oficina']) {
    assert.equal(JSON.parse(sql(identidad(n) + alta(`'${origen}'`))).estado, 'creado')
  }
  for (const origen of ["'otro'", 'null']) {
    sql(identidad(n) + alta(origen), /Selecciona un canal concreto/)
  }
  if (rol === 'vendedor') assert.equal(JSON.parse(sql(identidad(n) + alta("'referido'"))).estado, 'creado')
  else sql(identidad(n) + alta("'referido'"), /Un referido lo registra el vendedor/)
  console.log(`PASS ${rol}: altas concretas, rechazo de Otro/vacio y permisos de Referido`)
}
// La imagen local reinicia PostgreSQL al invocar esta RPC sin USAGE en crm.
// Verificar ACL aqui; las denegaciones HTTP se ensayan en la rama de Supabase.
assert.equal(sql("select has_function_privilege('anon','crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)','EXECUTE') or has_function_privilege('service_role','crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)','EXECUTE')"), 'f')
console.log('PASS ACL: anon y service_role sin EXECUTE de la RPC manual')

const insertar = "insert into crm.leads(nombre_completo,telefono,origen,monto_estimado,moneda) values('PRUEBA CANAL CONCRETO','+51988009902','otro',1000,'PEN')"
sql(insertar, /Selecciona un canal concreto/)
sql("select set_config('crm.op_privilegiada','on',true);" + insertar, /Selecciona un canal concreto/)
sql('set local role service_role;' + insertar, /Selecciona un canal concreto/)
console.log('PASS INSERT directo, privilegiado y de integracion rechazan Otro')

assert.equal(sql(identidad(3) + "update crm.leads set nota='Nota actualizada de prueba' where nombre_completo='PRUEBA CORRECCION 1'; select count(*) from crm.leads where nombre_completo='PRUEBA CORRECCION 1' and origen='otro' and nota='Nota actualizada de prueba'"), '1')
assert.equal(sql("select count(*) from crm.leads where nombre_completo='PRUEBA CANAL CONCRETO'"), '0')
console.log('PASS ficha historica editable y todos los ensayos revertidos')

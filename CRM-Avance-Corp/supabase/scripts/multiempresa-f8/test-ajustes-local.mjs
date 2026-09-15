// Banco sintético ya copiado para F8. Destinos cerrados; no admite URL ni credenciales.
// Las fixtures, cambios de flags y reemplazos para comparación SIEMPRE hacen ROLLBACK.
import assert from 'node:assert/strict';
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';

const contenedor='supabase_db_avancecorp-f5-bank';
const base='multiempresa_f8_ajustes_20260914';
const fuente='multiempresa_f8_20260913';
function ejecutar(consulta,db=base) {
  assert.ok([base,fuente].includes(db));
  return spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres',
    '-d',db,'-v','ON_ERROR_STOP=1','-f','-'],{encoding:'utf8',maxBuffer:16*1024*1024,
    input:`set timezone='America/Lima';\n${consulta}\n`});
}
function sql(consulta,db=base) {
  const r=ejecutar(consulta,db);
  assert.equal(r.status,0,r.stderr||r.error?.message);
  return r.stdout.trim();
}
const literal=v=>`'${String(v).replaceAll("'","''")}'`;
const json=v=>`${literal(JSON.stringify(v))}::jsonb`;
const como=uid=>`set local role authenticated; set local request.jwt.claim.sub=${literal(uid)};`;
const rechazo=(codigo,consulta)=>`do $rechazo$ begin begin ${consulta};
  raise exception 'Faltó rechazo ${codigo}';
  exception when sqlstate '${codigo}' then null; end; end; $rechazo$;`;
const migracion=readFileSync(new URL('../../migrations/20260914213634_crm_f8_cartera_lectura_eficiente.sql',import.meta.url),'utf8')
  .replace(/^begin;\s*/m,'').replace(/^commit;\s*/m,'');
const original=sql("select pg_get_functiondef('private.cartera_f5_personas_visibles()'::regprocedure)",fuente)+';';
const actores=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('uid',p.id,'rol',coalesce(e.rol_crm,p.rol),
  'activo',p.activo and coalesce(e.activo,true))) from public.perfiles p
  left join crm.equipo e on e.perfil_id=p.id where e.perfil_id is not null or p.rol='directorio'`));
const gerencia=actores.find(a=>a.rol==='gerencia'&&a.activo).uid;
const vendedor=actores.find(a=>a.rol==='vendedor'&&a.activo).uid;
const ajeno=actores.find(a=>a.rol==='vendedor'&&a.activo&&a.uid!==vendedor).uid;
const supervisor=sql(`select supervisor_id from crm.equipo where perfil_id=${literal(vendedor)}`);
const flags=`update crm.multiempresa_flags set activo=true
  where nombre in ('resolver_en_puertas','ficha_360_neutral','inversiones_escritura','postventa_neutral');`;
const personasQuery=`select coalesce(jsonb_agg(to_jsonb(p) order by p.inversionista_id),'[]')
  from private.cartera_f5_personas_visibles() p`;
const recibo={banco:base,paridad:[],rendimiento:[],condiciones:[]};

// Comparación de todos los campos y arrays, para cada actor del banco, incluido
// Directorio y los inactivos. No basta con comparar cantidades de personas.
for(const a of [...actores,{uid:'',rol:'sin_sesion',activo:false}]) {
  const antes=sql(`begin;${original} set local request.jwt.claim.sub=${literal(a.uid)};${personasQuery};rollback;`);
  const despues=sql(`begin;set local request.jwt.claim.sub=${literal(a.uid)};${personasQuery};rollback;`);
  assert.deepEqual(JSON.parse(despues),JSON.parse(antes),`Paridad: ${a.rol}/${a.activo}`);
  recibo.paridad.push({rol:a.rol,activo:a.activo,personas:JSON.parse(despues).length});
}
console.log(`PASS paridad íntegra: ${recibo.paridad.length} actores`);

// La exclusión demo tiene cinco enlaces históricos distintos. Se conserva el
// lector real salvo por una fuente temporal explícita, como en demos.test.mjs.
// Los ocho antecedentes fusionados del banco también entran en la paridad.
const fuentesOriginal=sql("select pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure)",fuente);
const fuenteTemporal=fuentesOriginal.replace(/AS \$function\$[\s\S]*\$function\$\s*$/,
  'AS $function$ select * from pg_temp.fuentes_ajustes $function$');
assert.notEqual(fuenteTemporal,fuentesOriginal);
const personaDemo='d401a318-6072-4348-a86f-bd398751c710';
const perfilDemo='d401a318-6072-4348-a86f-bd398751c711';
const leadDemo='d401a318-6072-4348-a86f-bd398751c712';
const cierreDemo='d401a318-6072-4348-a86f-bd398751c713';
const inversionDemo='d401a318-6072-4348-a86f-bd398751c714';
const hijaDemo='d401a318-6072-4348-a86f-bd398751c715';
for(const enlace of ['perfil','inversion','cierre','lead','puente','fusion','mixta']) {
  const setup=`create temporary table fuentes_ajustes as select * from private.cartera_f5_fuentes();
    set local session_replication_role='replica';
    insert into auth.users(id,aud,role,email) values('${perfilDemo}','authenticated','authenticated','ajustes@fixtures.invalid');
    insert into public.perfiles select (jsonb_populate_record(null::public.perfiles,to_jsonb(p)||
      jsonb_build_object('id','${perfilDemo}','nombre_completo','DEMO AJUSTES F8','dni',null,
        'correo','ajustes@fixtures.invalid','asesor_perfil_id',${literal(vendedor)}))).*
      from public.perfiles p where p.rol='cliente' and p.activo order by p.id limit 1;
    insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
      values('${personaDemo}','${perfilDemo}',${literal(vendedor)});
    insert into crm.inversionistas(id,inversionista_canonico_id,estado,fusionado_en)
      values('${hijaDemo}','${personaDemo}','fusionado',now());
    insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id,inversionista_id)
      values('${leadDemo}','DEMO AJUSTES F8','+51987666999',1000,${literal(vendedor)},
        ${enlace==='lead'?literal(personaDemo):'null'});
    ${enlace==='puente'?`insert into crm.inversionista_leads(inversionista_id,lead_id,rol)
      values('${personaDemo}','${leadDemo}','historico');`:''}
    insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,
      nombre_completo,numero_transaccion,vendedor_id,creado_por,inversionista_id)
      values('${cierreDemo}','${leadDemo}','qorilazo',1000,'PEN','DNI','79999171',
        'DEMO AJUSTES F8','F8-AJUSTES-DEMO',${literal(vendedor)},${literal(gerencia)},
        ${enlace==='cierre'?literal(personaDemo):enlace==='fusion'?literal(hijaDemo):'null'});
    insert into crm.inversiones select (jsonb_populate_record(null::crm.inversiones,to_jsonb(i)||
      jsonb_build_object('id','${inversionDemo}','inversionista_id','${personaDemo}',
        'contrato_id',null,'cierre_externo_id','${cierreDemo}'))).*
      from crm.inversiones i where i.cierre_externo_id is not null limit 1;
    insert into fuentes_ajustes select (jsonb_populate_record(null::pg_temp.fuentes_ajustes,to_jsonb(f)||
      jsonb_build_object('fuente_id','${cierreDemo}','inversionista_id','${personaDemo}',
        'es_demo',true,'perfil_id',${enlace==='perfil'||enlace==='mixta'?literal(perfilDemo):'null'},
        'inversion_id',${enlace==='inversion'?literal(inversionDemo):'null'},
        'lead_id',${enlace==='lead'||enlace==='puente'?literal(leadDemo):'null'}))).*
      from fuentes_ajustes f limit 1;
    ${enlace==='mixta'?`insert into fuentes_ajustes select (jsonb_populate_record(null::pg_temp.fuentes_ajustes,
      to_jsonb(f)||jsonb_build_object('fuente_id',gen_random_uuid(),'es_demo',false))).*
      from fuentes_ajustes f where fuente_id='${cierreDemo}';`:''}
    set local session_replication_role='origin';${fuenteTemporal};`;
  for(const a of actores) {
    const respuestas=sql(`begin;${original}${setup}
      set local request.jwt.claim.sub=${literal(a.uid)};${personasQuery};
      ${migracion}${personasQuery};rollback;`).split('\n').map(JSON.parse);
    assert.deepEqual(respuestas[1],respuestas[0],`Demo ${enlace}/${a.rol}`);
    if(a.uid===gerencia||a.uid===vendedor) assert.equal(
      respuestas[1].some(p=>p.inversionista_id===personaDemo),enlace==='mixta',enlace);
  }
}
recibo.paridad_demo='PASS: perfil, inversión, cierre, lead, puente, fusión y mezcla real/demo; todos los actores';
console.log('PASS paridad demo y fusiones: 7 enlaces × todos los actores');

// Volumen comparable con el corte productivo (491 personas / 1690 leads).
// Datos inventados, inserción sin triggers SOLO en la transacción de fixtures.
const id=n=>`md5('f8-ajustes-persona-'||(${n})::text)::uuid`;
const leadId=n=>`md5('f8-ajustes-lead-'||(${n})::text)::uuid`;
const fixtures=`set local session_replication_role='replica';
  insert into crm.inversionistas(id,responsable_relacion_id)
    select ${id('n')},case when n%2=0 then ${literal(vendedor)}::uuid else ${literal(ajeno)}::uuid end
    from generate_series(1,500) n;
  insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id,inversionista_id)
    select ${leadId('n')},'PERSONA SINTETICA '||n,'+51987'||lpad(n::text,6,'0'),1000,
      case when n%2=0 then ${literal(vendedor)}::uuid else ${literal(ajeno)}::uuid end,
      case when n<=500 then ${id('n')} end from generate_series(1,1700) n;
  insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,
    nombre_completo,numero_transaccion,vendedor_id,creado_por,inversionista_id,vence_en)
    select md5('f8-ajustes-cierre-'||n)::uuid,${leadId('n')},'qorilazo',1000,'PEN','DNI',
      lpad((70000000+n)::text,8,'0'),'PERSONA SINTETICA '||n,'F8-AJUSTES-'||n,
      case when n%2=0 then ${literal(vendedor)}::uuid else ${literal(ajeno)}::uuid end,
      ${literal(gerencia)}::uuid,${id('n')},current_date+365 from generate_series(1,500) n;
  set local session_replication_role='origin';
  analyze crm.inversionistas; analyze crm.leads; analyze crm.cierres_externos;`;
for(const [version,definicion] of [['anterior',original],['corregida',original+migracion]]) {
  for(const [rol,uid] of [['gerencia',gerencia],['supervisor',supervisor],['analista',vendedor]]) {
    const t=performance.now();
    const r=ejecutar(`begin;${definicion}${fixtures}${flags}${como(uid)}
      set local statement_timeout='8s';
      select jsonb_build_object('lista',crm.cartera_inversionistas_fn(),
        'ficha',crm.inversionista_ficha_fn(${id('2')}));rollback;`);
    const ms=Math.round(performance.now()-t);
    if(version==='corregida') {
      assert.equal(r.status,0,r.stderr);
      const res=JSON.parse(r.stdout.trim());
      assert.ok(res.lista.total>=250);
      assert.equal(res.ficha.persona.nombre,'PERSONA SINTETICA 2');
      assert.equal(res.ficha.inversiones_total,1);
    } else if(r.status!==0) assert.match(r.stderr,/statement timeout/);
    recibo.rendimiento.push({version,rol,ms,resultado:r.status===0?'PASS':'TIMEOUT_8S'});
    console.log(`${version} ${rol}: ${ms} ms (${r.status===0?'PASS':'límite de 8 s'})`);
  }
}

// Primera inversión real por RPC (fixtures en la misma transacción).
// Incluye reintento idéntico, conflicto de tasa, validación de fechas y ámbitos.
const lead='c401a318-6072-4348-a86f-bd398751c710';
const solicitud='c401a318-6072-4348-a86f-bd398751c711';
const correccion='c401a318-6072-4348-a86f-bd398751c712';
const inicial=(extras='12,12',op='F8-CONDICIONES-PRIMERO')=>`crm.convertir_lead_externo(
  '${lead}','qorilazo',1000,'PEN','DNI','79999871','PERSONA CONDICIONES',
  '${op}','CERTIFICADO PRUEBA',null,null,${extras})`;
const evidencia=`${lead}/${solicitud}/comprobante.pdf`;
const captura=sql(`begin;${flags}
  insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id,creado_por)
    values('${lead}','PERSONA CONDICIONES','+51987999871',1000,${literal(vendedor)},${literal(gerencia)});
  ${como(vendedor)}
  ${rechazo('22023',`perform ${inicial('0,12')}`)}
  ${rechazo('22023',`perform ${inicial('12,null')}`)}
  ${rechazo('22023',`perform ${inicial("12,'NaN'::numeric")}`)}
  ${rechazo('22023',`perform ${inicial('12,12.345')}`)}
  select ${inicial()};
  select ${inicial()};
  ${rechazo('P0409',`perform ${inicial('12,13')}`)}
  reset role;
  select jsonb_build_object('fuente',to_jsonb(ce),'persona',l.inversionista_id)
    from crm.cierres_externos ce join crm.leads l on l.id=ce.lead_id where l.id='${lead}';
  rollback;`).split('\n').map(JSON.parse);
assert.equal(captura[1].reintento,true);
assert.equal(captura[0].cierre_id,captura[1].cierre_id);
assert.equal(captura[2].fuente.plazo_meses,12);
assert.equal(Number(captura[2].fuente.tasa_anual),12);
recibo.condiciones.push('alta_inicial_idempotente_y_conflictos');

// Una operación escrita por la firma ANTERIOR debe poder reintentarse después
// de instalar la nueva, con el mismo hash y sin inventar condiciones históricas.
const firmaAnterior='crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)';
const firmaNueva='crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text,integer,numeric)';
const convertirAntes=sql(`select pg_get_functiondef(${literal(firmaAnterior)}::regprocedure)`,fuente);
const convertirAhora=sql(`select pg_get_functiondef(${literal(firmaNueva)}::regprocedure)`);
const permisos=firma=>`select jsonb_build_object('propietario',p.proowner::regrole::text,
  'definer',p.prosecdef,'config',p.proconfig,'acl',
  (select jsonb_agg(jsonb_build_array(a.grantor::regrole::text,a.grantee::regrole::text,
    a.privilege_type,a.is_grantable) order by a.grantor,a.grantee,a.privilege_type)
   from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a))
  from pg_proc p where p.oid=${literal(firma)}::regprocedure`;
assert.deepEqual(JSON.parse(sql(permisos(firmaNueva))),JSON.parse(sql(permisos(firmaAnterior),fuente)));
recibo.condiciones.push('acl_propietario_y_config_rpc_identicos_para_todos_los_roles');
const llamadaAnterior=`crm.convertir_lead_externo('${lead}','qorilazo',1000,'PEN','DNI',
  '79999871','PERSONA CONDICIONES','F8-COMPATIBILIDAD-ANTERIOR',null,null,null)`;
const anterior=sql(`begin;${flags}
  drop function ${firmaNueva};${convertirAntes};
  grant execute on function ${firmaAnterior} to authenticated;
  insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id,creado_por)
    values('${lead}','PERSONA CONDICIONES','+51987999871',1000,${literal(vendedor)},${literal(gerencia)});
  ${como(vendedor)} select ${llamadaAnterior};reset role;
  drop function ${firmaAnterior};${convertirAhora};
  grant execute on function ${firmaNueva} to authenticated;
  ${como(vendedor)} select ${llamadaAnterior};reset role;
  select jsonb_build_object('plazo',plazo_meses,'tasa',tasa_anual,'vence',vence_en)
    from crm.cierres_externos where lead_id='${lead}';rollback;`).split('\n').map(JSON.parse);
assert.equal(anterior[0].cierre_id,anterior[1].cierre_id);
assert.equal(anterior[1].reintento,true);
assert.deepEqual(anterior[2],{plazo:null,tasa:null,vence:null});
recibo.condiciones.push('operacion_anterior_reintenta_tras_migracion_sin_cambiar_hash');

// Alta adicional F4 y corrección de solicitud: los términos viajan en el mismo
// payload/hash/revisión y se leen desde su fuente, no desde el borrador del UI.
const datos={inversionista_id:lead,empresa:'prodelco',monto:2500,moneda:'PEN',
  fecha_comercial:'2024-02-29',vence_en:'2025-02-28',plazo_meses:12,tasa_anual:12,
  numero_transaccion:'F8-CONDICIONES-ADICIONAL',referencia:'CERTIFICADO PRUEBA',evidencia:{ruta:evidencia}};
const corregidos={...datos,plazo_meses:6,tasa_anual:12.5,vence_en:'2024-08-29'};
const adicional=sql(`begin;${flags}
  insert into crm.leads(id,nombre_completo,telefono,monto_estimado,vendedor_id,creado_por)
    values('${lead}','PERSONA CONDICIONES','+51987999871',1000,${literal(vendedor)},${literal(gerencia)});
  ${como(vendedor)} select ${inicial()}; reset role;
  -- Sustituye solo el UUID ficticio del payload por la identidad resuelta por F3.
  create temporary table payload as select (${json(datos)} || jsonb_build_object(
    'inversionista_id',l.inversionista_id,'evidencia',jsonb_build_object('ruta',
    l.inversionista_id::text||'/${solicitud}/comprobante.pdf'))) datos from crm.leads l where l.id='${lead}';
  grant select on payload to authenticated;
  insert into storage.objects(bucket_id,name,metadata)
    select 'f4-comprobantes',datos#>>'{evidencia,ruta}',
      '{"size":12,"mimetype":"application/pdf"}'::jsonb from payload;
  ${como(vendedor)}
  select crm.preparar_inversion_fn('${solicitud}',(select datos from payload));
  ${rechazo('22023',`perform crm.preparar_inversion_fn(gen_random_uuid(),(select datos||'{"vence_en":"2025-03-01"}'::jsonb from payload))`)}
  select crm.corregir_solicitud_inversion_fn('${solicitud}','${correccion}',0,
    (select datos||${json({plazo_meses:6,tasa_anual:12.5,vence_en:corregidos.vence_en})} from payload),'Corregir plazo y tasa pactados');
  ${rechazo('PT409',`perform crm.confirmar_inversion_revisada_fn('${solicitud}',0)`)}
  select crm.confirmar_inversion_revisada_fn('${solicitud}',1);
  select crm.confirmar_inversion_revisada_fn('${solicitud}',1);
  select crm.inversionista_ficha_fn((select (datos->>'inversionista_id')::uuid from payload));
  set local request.jwt.claim.sub=${literal(ajeno)};
  ${rechazo('42501',`perform crm.confirmar_inversion_revisada_fn('${solicitud}',1)`)}
  reset role;
  select jsonb_build_object('plazo',plazo_meses,'tasa',tasa_anual,'vence',vence_en)
    from crm.cierres_externos where numero_transaccion='F8-CONDICIONES-ADICIONAL';
  rollback;`).split('\n').map(JSON.parse);
assert.deepEqual(adicional.at(-1),{plazo:6,tasa:12.5,vence:'2024-08-29'});
assert.equal(adicional[4].reintento,true);
const inversion=adicional[5].inversiones.find(i=>i.empresa==='prodelco');
assert.deepEqual(inversion.condiciones_coopac,{plazo_meses:6,tasa_anual:12.5});
assert.equal(inversion.vence_en,'2024-08-29');
// La inversión vencida sigue pendiente de revisión aunque haya otra futura:
// otra fuente no acredita que esta se haya renovado o liquidado.
assert.equal(adicional[5].continuidad.proximo_vencimiento,'2024-08-29');
recibo.condiciones.push('preparar_corregir_confirmar_reintentar_leer_por_nucleos');
assert.equal(sql("select private.coopac_validar_condiciones('2025-01-31',1,12)"),'2025-02-28');
assert.equal(sql("select private.coopac_validar_condiciones('2024-02-29',12,12)"),'2025-02-28');
recibo.condiciones.push('fin_de_mes_y_bisiesto');
assert.equal(sql(`select count(*) from information_schema.role_column_grants
  where table_schema='crm' and table_name='cierres_externos' and grantee in ('anon','authenticated')`),'0');
assert.equal(sql(`select has_function_privilege('anon',
  'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text,integer,numeric)','execute')`),'f');
recibo.condiciones.push('sin_grants_directos_ni_rpc_anonima');
mkdirSync('/private/tmp/avancecorp-f8-ajustes-20260914',{recursive:true});
writeFileSync('/private/tmp/avancecorp-f8-ajustes-20260914/resultado-local.json',JSON.stringify(recibo,null,2)+'\n');
console.log('PASS condiciones COOPAC, fechas, idempotencia y permisos');

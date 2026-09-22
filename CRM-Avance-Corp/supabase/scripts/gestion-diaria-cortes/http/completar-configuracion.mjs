// Completa configuración TÉCNICA omitida por un dump --schema-only. Nunca copia
// usuarios, comprobantes ni filas económicas. Origen SELECT; escrituras locales.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { carpeta, sql, verificarBanco } from './banco.mjs';

const [modo, ...resto] = process.argv.slice(2);
assert.ok(['--capturar-configuracion', '--solo-banco-autorizado'].includes(modo) && resto.length === 0);
const archivo = `${carpeta}/configuracion-tecnica-complementaria.json`;
const q = x => `'${String(x).replaceAll("'", "''")}'`;
if (modo === '--capturar-configuracion') {
  const consulta = `select jsonb_build_object(
    'exenciones',(select jsonb_agg(jsonb_build_object('tabla',tabla,'razon',razon) order by tabla) from private.auditoria_exenciones),
    'condicionadas',(select coalesce(jsonb_agg(jsonb_build_object('tabla',tabla,'razon',razon) order by tabla),'[]') from private.auditoria_condicionada),
    'sello',(select huella from private.auditoria_sello),
    'enfriamiento',(select jsonb_agg(jsonb_build_object('motivo',motivo,'dias',dias) order by motivo) from crm.enfriamiento_politica),
    'storage',(select jsonb_agg(to_jsonb(p)) from pg_policies p where schemaname='storage' and tablename='objects' and policyname like 'f4_comprobante_%')
  ) as configuracion;`;
  assert.ok(!/\b(?:insert|update|delete|alter|drop|grant|revoke|create)\s/i.test(consulta));
  const r = spawnSync('supabase', ['db','query','--linked','--project-ref','dctqcbznekcyxhjujuci','-o','json',consulta],
    { cwd:new URL('../../../../',import.meta.url),encoding:'utf8',maxBuffer:1024*1024,timeout:60_000 });
  assert.equal(r.status,0,'No se pudo leer configuración técnica; no se sustituye por una inventada');
  const datos = JSON.parse(r.stdout).rows[0].configuracion;
  assert.equal(datos.enfriamiento.length,7);
  assert.match(datos.sello,/^[a-f0-9]{32}$/);
  writeFileSync(archivo,JSON.stringify(datos,null,2)+'\n',{mode:0o600});
  console.log('PASS: sólo configuración técnica y políticas de comprobantes capturadas');
} else {
  verificarBanco();
  const d = JSON.parse(readFileSync(archivo,'utf8'));
  const sembrado = sql('select count(*) from private.auditoria_sello') === '1';
  if (sembrado) assert.equal(sql('select private.huella_exenciones()'),d.sello,'Configuración previa diferente: no sobreescribir');
  else for(const tabla of ['auditoria_exenciones','auditoria_condicionada','auditoria_sello'])
    assert.equal(sql(`select count(*) from private.${tabla}`),'0',`La tabla ${tabla} ya tiene historia; no sobreescribir`);
  const valores = xs => xs.map(x=>`(${q(x.tabla)},${q(x.razon)})`).join(',');
  if (!sembrado) sql(`begin;
    ${d.exenciones.length ? `insert into private.auditoria_exenciones(tabla,razon) values ${valores(d.exenciones)};` : ''}
    ${d.condicionadas.length ? `insert into private.auditoria_condicionada(tabla,razon) values ${valores(d.condicionadas)};` : ''}
    insert into private.auditoria_sello(unico,huella) values(true,${q(d.sello)});
    do $$ begin if private.huella_exenciones()<>${q(d.sello)} then raise exception 'Sello técnico no coincide'; end if; end $$;
    insert into crm.enfriamiento_politica(motivo,dias) values ${d.enfriamiento.map(x=>`(${q(x.motivo)},${Number(x.dias)})`).join(',')};
    insert into crm.rentabilidad_hitos(clave,valor) values ('observacion_activa_desde',jsonb_build_object('en',statement_timestamp()));
    update crm.empresas set monedas=array['PEN','USD'] where clave='prodelco';
    commit;`);
  const existentes = JSON.parse(sql("select coalesce(jsonb_agg(policyname),'[]') from pg_policies where schemaname='storage' and tablename='objects'"));
  const ddl = d.storage.map(p=>{
    assert.match(p.policyname,/^f4_comprobante_[a-z_]+$/);
    assert.deepEqual(p.roles,['authenticated']);
    assert.ok(['INSERT','SELECT','UPDATE','DELETE'].includes(p.cmd));
    assert.ok(['PERMISSIVE','RESTRICTIVE'].includes(p.permissive));
    assert.ok(!existentes.includes(p.policyname),'Política preexistente: detener sin reemplazarla');
    return `create policy ${p.policyname} on storage.objects as ${p.permissive} for ${p.cmd} to authenticated
      ${p.qual ? `using (${p.qual})` : ''} ${p.with_check ? `with check (${p.with_check})` : ''};`;
  }).join('\n');
  sql(`begin; ${ddl}
    insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
    values('f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf','image/jpeg','image/png']);
    notify pgrst,'reload schema'; commit;`,{propietarioAlmacen:true});
  console.log('PASS: sello de auditoría verificado, siete enfriamientos, hito sintético y Storage privado');
}

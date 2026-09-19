import assert from 'node:assert/strict';
import {randomBytes,randomInt} from 'node:crypto';
import {writeFileSync,readFileSync} from 'node:fs';
import {carpeta,fixture,http} from './http-banco.mjs';
import {sql,q} from './banco.mjs';
// Lectores publicados después de crear el template. Se instalan sus definiciones
// exactas, capturadas en sólo lectura, únicamente en esta copia de pruebas.
const lectores=JSON.parse(readFileSync(new URL('./baseline-cartera.json',import.meta.url),'utf8'));
for(const f of [...lectores].reverse()){
  const firma=`${f.esquema}.${f.nombre}(${f.argumentos.split(', ').map(x=>x.split(' ').slice(1).join(' ')).join(',')})`;
  const actual=sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure(${q(firma)}))),'')`);
  if(actual){assert.equal(actual,f.huella,`El lector local cambió: ${firma}`);continue;}
  sql(`begin; ${f.definicion}; alter function ${firma} owner to postgres;
    revoke all on function ${firma} from public,anon,authenticated,service_role;
    ${f.esquema==='crm'?`grant execute on function ${firma} to authenticated;`:''}
    notify pgrst,'reload schema'; commit;`);
}
// El dump sintético conserva el schema de Storage, pero no su historial de
// instalación. Sólo lo reconstruimos si TODAS sus funciones y columnas
// coinciden con el servicio local que proporciona las mismas imágenes.
const funciones="select jsonb_object_agg(proname||pg_get_function_identity_arguments(oid),md5(pg_get_functiondef(oid))) from pg_proc where pronamespace='storage'::regnamespace";
const columnas="select jsonb_agg(to_jsonb(c) order by table_name,ordinal_position) from (select table_name,column_name,ordinal_position,data_type,udt_name,is_nullable,column_default from information_schema.columns where table_schema='storage') c";
assert.deepEqual(JSON.parse(sql(funciones)),JSON.parse(sql(funciones,'postgres')));
assert.deepEqual(JSON.parse(sql(columnas)),JSON.parse(sql(columnas,'postgres')));
const historial=sql('select jsonb_agg(to_jsonb(m)) from storage.migrations m','postgres');
sql(`insert into storage.migrations select * from jsonb_populate_recordset(null::storage.migrations,${q(historial)}::jsonb)
  on conflict(id) do nothing;
  create schema if not exists graphql_public;
  notify pgrst,'reload schema';`,undefined,'supabase_admin');
const reglas=JSON.parse(readFileSync(new URL('./baseline-storage.json',import.meta.url),'utf8'));
const presentes=JSON.parse(sql("select coalesce(jsonb_agg(policyname),'[]') from pg_policies where schemaname='storage' and tablename='objects'"));
for(const regla of reglas.filter(x=>x.tipo==='policy')){
  const p=JSON.parse(regla.definicion);
  if(presentes.includes(p.policyname))continue;
  assert.match(p.policyname,/^f4_comprobante_[a-z_]+$/);
  assert.deepEqual(p.roles,['authenticated']);assert(['INSERT','SELECT'].includes(p.cmd));
  sql(`create policy ${p.policyname} on storage.objects as ${p.permissive} for ${p.cmd} to authenticated
    ${p.qual?`using (${p.qual})`:''} ${p.with_check?`with check (${p.with_check})`:''};`,undefined,'supabase_admin');
}
// El template trae un cierre ficticio de una prueba antigua, sin identidad.
// Se enlaza sólo ese registro en NUESTRA copia para poder probar los lectores
// que correctamente exigen cobertura completa. No se desactiva su guard.
sql(`do $$ declare c crm.cierres_externos%rowtype; persona uuid; begin
  select * into c from crm.cierres_externos where id='fcd4baa6-49d9-40e1-9c09-0e81b801ee55';
  if found and c.inversionista_id is null then
    persona:=private.inversionista_resolver('DNI','48000999',true,'fixture_conversion_http');
    insert into crm.inversionista_responsables(inversionista_id,responsable_id,motivo,por)
      values(persona,c.vendedor_id,'Preparar dato sintético incompleto del banco',c.vendedor_id);
    update crm.inversionistas set responsable_relacion_id=c.vendedor_id where id=persona;
    perform set_config('crm.op_privilegiada','on',true);
    update crm.leads set inversionista_id=persona where id=c.lead_id;
    update crm.cierres_externos set inversionista_id=persona where id=c.id;
    perform private.inversion_vincular_fuente(persona,null,c.id,c.vendedor_id,true);
  end if;
end $$;`);
// El catálogo de Storage debe estar preparado antes de arrancar su servicio;
// las cuentas sintéticas requieren después el gateway HTTP activo.
if(process.argv[2]==='catalogo'){
  console.log('PASS: catálogo sintético preparado; sin altas de usuarios HTTP.');
  process.exit(0);
}
const datos=fixture??{usuarios:{},password:randomBytes(24).toString('base64url'),prefijo:randomBytes(6).toString('hex')};
const guardar=()=>writeFileSync(`${carpeta}/fixture.json`,JSON.stringify(datos),{mode:0o600});
guardar();
for(const rol of ['gerencia','supervisor','vendedor','supervisor_ajeno','ajeno','directorio','cliente']){
  if(!datos.usuarios[rol]){
    const email=`conversion.${datos.prefijo}.${rol}@example.test`;
    const r=await http('/auth/v1/admin/users',{admin:true,body:{email,password:datos.password,email_confirm:true}});
    assert.equal(r.ok,true,`Crear fixture ${rol}: ${r.status} ${r.data?.msg??''}`);
    datos.usuarios[rol]={id:r.data.id,email,documento:String(randomInt(70000000,79999999))};guardar();
  }
  const u=datos.usuarios[rol], rolPublico=({gerencia:'admin',directorio:'directorio',cliente:'cliente'})[rol]??'analista';
  sql(`insert into public.perfiles(id,nombre_completo,rol,activo,dni,telefono,correo,nombres,apellidos,domicilio)
    values(${q(u.id)},${q('PRUEBA CONVERSION '+rol.toUpperCase())},${q(rolPublico)},true,${q(u.documento)},'999555222',${q(u.email)},'PRUEBA','CONVERSION','AVENIDA SINTETICA 123 LIMA')
    on conflict(id) do update set rol=excluded.rol,activo=true;
    ${rol==='cliente'?'':`insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
      values(${q(u.id)},${q(rol==='ajeno'?'vendedor':rol==='supervisor_ajeno'?'supervisor':rol)},${q(rol==='vendedor'?datos.usuarios.supervisor.id:rol==='ajeno'?datos.usuarios.supervisor_ajeno.id:null)},true)
      on conflict(perfil_id) do update set activo=true;`}`);
}
sql(`insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('f4-comprobantes','f4-comprobantes',false,10485760,array['application/pdf','image/jpeg','image/png'])
  on conflict(id) do nothing;`,undefined,'supabase_admin');
console.log('Siete usuarios exclusivamente sintéticos preparados en la copia aislada; credenciales privadas.');

import assert from 'node:assert/strict';
import {randomBytes,randomInt} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {carpeta,fixture,http,sql,q} from './banco-remoto.mjs';
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

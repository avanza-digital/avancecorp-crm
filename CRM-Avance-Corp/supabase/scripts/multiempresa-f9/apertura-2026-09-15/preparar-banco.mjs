// Solo fixtures de copia F9: UUID/roles del equipo, nombres/correos sintéticos.
// No copia datos personales, credenciales ni inversiones de producción.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {db,sql,objeto,q,j} from './banco.mjs';
const cfg=JSON.parse(readFileSync(new URL('config.json',import.meta.url),'utf8'));
assert.equal(sql('select current_database()'),db);
sql(`begin;set local statement_timeout='30s';
  do $guardia$ begin if current_database()<>'f9_apertura_20260915' then raise exception 'Destino incorrecto';end if;end $guardia$;
  update crm.piloto_f8_control set activo=false where singleton;
  update crm.piloto_f8_miembros set activo=false;
  update crm.multiempresa_flags set activo=(nombre='resolver_en_puertas');
  -- Apartar el equipo sintético anterior sin borrar sus antecedentes. Solo
  -- este fixture omite su validador de dependencias; se reactiva de inmediato.
  alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
  update crm.equipo set activo=false,supervisor_id=null where activo;
  alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;
  insert into auth.users(id,aud,role,email,email_confirmed_at)
    select (x->>'perfil_id')::uuid,'authenticated','authenticated',x->>'perfil_id'||'@f9.example.invalid',now()
    from jsonb_array_elements(${j(cfg.equipo)}) x on conflict(id) do nothing;
  insert into auth.identities(user_id,provider,provider_id,identity_data)
    select (x->>'perfil_id')::uuid,'email',x->>'perfil_id',jsonb_build_object('sub',x->>'perfil_id',
      'email',x->>'perfil_id'||'@f9.example.invalid') from jsonb_array_elements(${j(cfg.equipo)}) x
    on conflict(provider_id,provider) do nothing;
  insert into public.perfiles(id,nombre_completo,rol,activo)
    select (x->>'perfil_id')::uuid,'PERSONAL SINTETICO F9 '||left(x->>'perfil_id',8),x->>'rol_portal',true
    from jsonb_array_elements(${j(cfg.equipo)}) x on conflict(id) do nothing;
  insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
    select (x->>'perfil_id')::uuid,x->>'rol_crm',(x->>'supervisor_id')::uuid,true
    from jsonb_array_elements(${j(cfg.equipo)}) x order by (x->>'supervisor_id') is not null
    on conflict(perfil_id) do update set activo=true,rol_crm=excluded.rol_crm,supervisor_id=excluded.supervisor_id;
  insert into crm.piloto_f8_miembros select (jsonb_populate_record(null::crm.piloto_f8_miembros,x)).*
    from jsonb_array_elements(${j(cfg.miembros)}) x on conflict(perfil_id) do update set activo=true;
  -- Únicamente para fijar la revisión inicial del fixture. El trigger se
  -- habilita antes del COMMIT y debe coincidir con producción en ACTIVAR.sql.
  alter table crm.piloto_f8_control disable trigger trg_piloto_f8_control_00_validar;
  update crm.piloto_f8_control set activo=true,revision=1,
    inicia_en=${q(cfg.control.inicia_en)},vence_en=${q(cfg.control.vence_en)},
    motivo=${q(cfg.control.motivo)},actualizado_por=${q(cfg.responsable_id)} where singleton;
  alter table crm.piloto_f8_control enable trigger trg_piloto_f8_control_00_validar;
  commit;`,true);
assert.equal(sql('select private.piloto_f8_modo_activo()'),'t');
console.log(JSON.stringify({estado:'PASS',banco:db,cuentas:objeto('select count(*) from crm.equipo where activo')}));

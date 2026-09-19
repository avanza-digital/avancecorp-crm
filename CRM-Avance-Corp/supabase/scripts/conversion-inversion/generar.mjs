// Generación reproducible desde las definiciones productivas saneadas.
// Cada sustitución exige una única coincidencia: un cambio de base no se oculta.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
const base = JSON.parse(readFileSync(new URL('./baseline-funciones.json', import.meta.url), 'utf8'));
const storage=JSON.parse(readFileSync(new URL('./baseline-storage.json',import.meta.url),'utf8'));
const firma = f => `${f.esquema}.${f.nombre}(${f.argumentos.split(', ').map(a=>a.split(' ').slice(1).join(' ')).join(',')})`;
const anclas=[...base,...storage.filter(f=>f.tipo==='funcion')].map(f=>({firma:firma(f),huella:f.huella}));
const preflight=`do $anclas$ declare a record; begin
  for a in select * from jsonb_to_recordset($datos$${JSON.stringify(anclas)}$datos$::jsonb) as x(firma text,huella text) loop
    if md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'La base cambió: %. Revisa el cambio antes de instalarlo.',a.firma;
    end if;
  end loop;
end $anclas$;`;
const def = n => {const f = base.filter(f => f.nombre === n); assert.equal(f.length, 1); return f[0].definicion.trimEnd()+';';};
function cambiar(s, antes, despues) {
  assert.equal(s.split(antes).length, 2, `Fragmento no único: ${antes}`);
  return s.replace(antes, despues);
}
const partes = ["-- Conversión y Cartera comparten preparar/revisar/confirmar.\n-- Producción: pendiente de autorización. Ensayo en banco sintético propio.\nbegin;\nset local lock_timeout='5s';\n",
  preflight,
  readFileSync(new URL('./contexto.sql', import.meta.url), 'utf8'),
  readFileSync(new URL('./bienvenida.sql', import.meta.url), 'utf8'),
  readFileSync(new URL('./cancelar.sql', import.meta.url), 'utf8')];
let contexto = cambiar(def('inversion_persona_contexto'), 'p_persona uuid)', 'p_persona uuid, p_lead uuid)');
contexto = cambiar(contexto, "    if v_l.etapa <> 'convertido' then", "    if p_lead is null and v_l.etapa <> 'convertido' then");
contexto = cambiar(contexto, '  v_nombre :=', `  if p_lead is not null then
    if v_l.id is distinct from p_lead or v_l.activo is not true or
      not coalesce((private.rol_crm((select auth.uid()))='gerencia' or
        v_l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))),false) then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
    end if;
    if v_l.etapa in ('convertido','descartado') then
      raise exception 'El lead ya está cerrado; consulta su inversión en Cartera' using errcode='P0409';
    end if;
    if v_l.vendedor_id is distinct from v_i.responsable_relacion_id then
      raise exception 'El responsable de la persona y el analista del lead deben coincidir antes de invertir' using errcode='P0409';
    end if;
    if exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
      or exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion) then
      raise exception 'La persona ya tiene una conversión inicial; requiere conciliación' using errcode='P0409';
    end if;
    if exists(select 1 from crm.conversion_reservas r where
      (r.lead_id=p_lead or r.inversionista_id=v_persona) and
      (r.efectos_iniciados_en is not null or r.expira_en>now()) for update nowait) then
      raise exception 'Hay una conversión anterior pendiente; revisa su acceso antes de continuar' using errcode='P0409';
    end if;
  end if;
  v_nombre :=`);
partes.push(contexto, `revoke all on function private.inversion_persona_contexto(uuid,uuid) from public,anon,authenticated,service_role;`,
  `create or replace function private.inversion_persona_contexto(p_persona uuid) returns jsonb
language sql security definer set search_path='' set lock_timeout='5s' as $$
select private.inversion_persona_contexto(p_persona,null::uuid) $$;`);

// Las lecturas periódicas conservan exactamente los controles del escritor,
// pero no toman sus locks de persona, documento, perfil, lead o reserva.
// Las banderas y la jerarquía mantienen sus candados compartidos globales.
let autorizadaLectura=cambiar(def('inversion_persona_autorizada'),
  'private.inversion_persona_autorizada(', 'private.inversion_persona_lectura(');
autorizadaLectura=cambiar(autorizadaLectura,
  '  v_docs := private.identidad_bloquear_documentos_de(array[v_persona]);\n','');
autorizadaLectura=cambiar(autorizadaLectura,' where id=v_persona for update;',' where id=v_persona;');
const inicioDocumentos=autorizadaLectura.indexOf('  select coalesce(array_agg(k order by k)');
const finDocumentos=autorizadaLectura.indexOf('  return jsonb_build_object',inicioDocumentos);
assert(inicioDocumentos>0&&finDocumentos>inicioDocumentos);
autorizadaLectura=autorizadaLectura.slice(0,inicioDocumentos)+autorizadaLectura.slice(finDocumentos);
let contextoLectura=cambiar(contexto,'private.inversion_persona_contexto(', 'private.inversion_contexto_lectura(');
contextoLectura=cambiar(contextoLectura,'private.inversion_persona_autorizada(', 'private.inversion_persona_lectura(')
  .replaceAll(' for update nowait','').replaceAll(' for share nowait','').replaceAll(' for update','').replaceAll(' for share','');
partes.push(autorizadaLectura,contextoLectura,
  'revoke all on function private.inversion_persona_lectura(uuid), private.inversion_contexto_lectura(uuid,uuid) from public,anon,authenticated,service_role;');

let preparar = def('preparar_inversion_fn');
preparar = cambiar(preparar, '  v_persona uuid;', '  v_persona uuid;\n  v_lead uuid;');
preparar = cambiar(preparar, "'inversionista_id','empresa'", "'inversionista_id','lead_id','empresa'");
preparar = cambiar(preparar, '  v_ctx := private.inversion_persona_autorizada(v_persona);',
  "  begin v_lead := (p_datos->>'lead_id')::uuid;\n  exception when invalid_text_representation then\n    raise exception 'Origen de inversión inválido' using errcode='22023';\n  end;\n  v_ctx := private.inversion_persona_autorizada(v_persona);");
preparar = preparar.replaceAll('private.inversion_persona_contexto(v_persona)', 'private.inversion_persona_contexto(v_persona,v_lead)');
preparar = cambiar(preparar, '  v_e.id:=private.inversion_validar_datos', `  if v_lead is not null and exists(select 1 from crm.inversion_solicitudes
    where lead_origen_id=v_lead and estado in ('preparada','confirmada')) then
    raise exception 'Este lead ya tiene una solicitud: retómala antes de crear otra' using errcode='P0409';
  end if;
  v_e.id:=private.inversion_validar_datos`);
preparar = cambiar(preparar, 'responsable_esperado_id,hash_payload,datos,creado_por)', 'responsable_esperado_id,hash_payload,datos,creado_por,lead_origen_id)');
preparar = cambiar(preparar, 'v_hash,p_datos,(select auth.uid()));', 'v_hash,p_datos,(select auth.uid()),v_lead);');
partes.push(preparar);
partes.push(cambiar(def('inversion_validar_datos'), "'inversionista_id','empresa'", "'inversionista_id','lead_id','empresa'"));

for (const nombre of ['corregir_solicitud_inversion_fn','revisar_solicitud_inversion_fn','acceso_inversion_fn']) {
  let f = def(nombre);
  assert.ok(f.includes('private.inversion_persona_contexto(v_persona)'));
  f = f.replaceAll('private.inversion_persona_contexto(v_persona)',
    'private.inversion_persona_contexto(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud))');
  if (nombre === 'corregir_solicitud_inversion_fn') f = cambiar(f,
    "    or p_datos->'empresa' is distinct from v_s.datos->'empresa'",
    "    or p_datos->'lead_id' is distinct from v_s.datos->'lead_id'\n    or p_datos->'empresa' is distinct from v_s.datos->'empresa'");
  if (nombre === 'acceso_inversion_fn') f = cambiar(f,
    "    update crm.inversion_solicitudes set auth_claim_id=(v_r->>'claim_id')::uuid,", `    -- El formulario guarda su token ANTES del primer envío. La saga general
    -- emite otro token; aquí conservamos el ya conocido para poder recuperar
    -- también una respuesta perdida del primer reclamo (sin esperar el lease).
    -- saga_auth_reclamar ya verificó el token vigente al retomar. No se altera
    -- el claim, su versión, su dueño ni su huella; las otras puertas no cambian.
    if v_token is not null and v_r->>'estado'<>'enlazado' then
      update crm.multiempresa_idempotencia set resultado=jsonb_set(resultado,'{token_hash}',
        to_jsonb(private.saga_token_hash(v_token)))
        where clave='auth_persona:'||(v_r->>'inversionista_id') and resultado->>'claim_id'=v_r->>'claim_id';
      if not found then
        raise exception 'El proceso de acceso cambió; recupera la solicitud' using errcode='40001';
      end if;
      v_r:=jsonb_set(v_r,'{token}',to_jsonb(v_token));
    end if;
    update crm.inversion_solicitudes set auth_claim_id=(v_r->>'claim_id')::uuid,`);
  partes.push(f);
}
partes.push(cambiar(def('inversion_solicitud_resultado'), "'solicitud_id',s.id,'estado'", "'solicitud_id',s.id,'lead_id',s.lead_origen_id,'estado'"));
// Storage comparte el contexto de la solicitud, antes de convertir el lead.
// Se conservan las policies, el responsable esperado y la ruta exacta reservada.
const permisoArchivo=storage.find(f=>f.nombre==='f4_comprobante_autorizado').definicion.trimEnd()+';';
let permisoNuevo=cambiar(permisoArchivo,'private.inversion_persona_contexto(v_persona)',
  'private.inversion_persona_contexto(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=v_solicitud))');
permisoNuevo=cambiar(permisoNuevo,'when insufficient_privilege then',
  "when insufficient_privilege or lock_not_available or sqlstate 'P0409' or sqlstate 'P0429' then");
partes.push(permisoNuevo);

let confirmar = def('confirmar_inversion_revisada_fn');
confirmar = cambiar(confirmar, '  v_res jsonb;', "  v_res jsonb;\n  v_config_conversion text:=coalesce(current_setting('crm.op_privilegiada',true),'off');");
confirmar = cambiar(confirmar, 'private.inversion_persona_contexto(v_persona)', 'private.inversion_persona_contexto(v_persona,v_s.lead_origen_id)');
confirmar = cambiar(confirmar, 'v_ahora,false,v_fecha', 'v_ahora,v_s.lead_origen_id is not null,v_fecha');
confirmar = cambiar(confirmar, '    v_payload_contrato := v_s.datos->\'contrato\';', `    v_payload_contrato := v_s.datos->'contrato';
    if v_s.lead_origen_id is not null then
      if coalesce(v_payload_contrato->>'categoria','nuevo')<>'nuevo' then
        raise exception 'La conversión inicial registra una inversión nueva' using errcode='22023';
      end if;
      perform private.validar_tasa_conversion_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid,v_payload_contrato);
      perform private.enlazar_tasa_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid);
    end if;`);
confirmar = cambiar(confirmar, 'private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,false)',
  'private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,v_s.lead_origen_id is not null)');
confirmar = cambiar(confirmar, '  return v_res;\nend;', `  if v_s.lead_origen_id is not null then
    -- El escritor contractual puede haber enlazado ya su fuente; se reconoce
    -- ESTA inversión como inicial, conservando un único hecho y titular.
    update crm.inversiones set es_primera_conversion=true where id=v_inversion;
    perform set_config('crm.op_privilegiada','on',true);
    update crm.leads set etapa='convertido',convertido_en=statement_timestamp(),
      perfil_id=case when v_e.clave='avance' then (v_ctx->>'perfil_id')::uuid else perfil_id end,
      contrato_id=coalesce(v_contrato,contrato_id)
      where id=v_s.lead_origen_id;
    perform set_config('crm.op_privilegiada',v_config_conversion,true);
    insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
      values(v_s.lead_origen_id,'conversion','Convertido al confirmar su inversión',
        jsonb_build_object('solicitud_id',v_s.id,'inversion_id',v_inversion,'empresa',v_e.clave,
          'contrato_id',v_contrato,'cierre_externo_id',v_cierre),v_uid);
    if v_e.clave='avance' and v_s.auth_claim_id is not null then
      update crm.inversion_solicitudes set bienvenida=jsonb_build_object(
        'estado','pendiente','correo',v_s.datos->'alta_portal'->>'correo',
        'nombre',v_s.datos->'alta_portal'->>'nombre_completo') where id=v_s.id;
    end if;
  end if;
  return v_res;
end;`);
partes.push(confirmar);
// Conserva las respuestas idempotentes históricas, pero cierra las escrituras
// nuevas del formulario anterior antes de resolver identidad o crear el cierre.
partes.push(cambiar(def('convertir_lead_externo'),
  '  -- Validaciones de entrada ANTES de tocar el lead:',
  `  raise exception 'Actualiza el CRM y confirma la inversión desde el formulario compartido'
    using errcode='P0409';
  -- Validaciones de entrada ANTES de tocar el lead:`));
partes.push(`-- No se modifica ningún trigger ni tabla de public. Este control de CRM
-- evita que un bundle anterior cierre el lead mientras su solicitud sigue abierta.
create or replace function private.conversion_lead_con_inversion() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.etapa='convertido' and old.etapa<>'convertido' then
    if exists(select 1 from crm.inversion_solicitudes where lead_origen_id=new.id and estado='preparada') then
      raise exception 'Confirma la solicitud de inversión antes de convertir el lead' using errcode='P0409';
    end if;
    if not exists(select 1 from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id
      where s.lead_origen_id=new.id and s.estado='confirmada'
        and i.inversionista_id=new.inversionista_id and i.es_primera_conversion and i.estado='vigente') then
      raise exception 'Registra y confirma la inversión desde el formulario compartido antes de convertir' using errcode='P0409';
    end if;
  end if;
  return new;
end $$;
revoke all on function private.conversion_lead_con_inversion() from public,anon,authenticated,service_role;
create trigger trg_leads_conversion_con_inversion before update of etapa on crm.leads
  for each row execute function private.conversion_lead_con_inversion();
alter function private.conversion_reserva_legacy_cerrada() owner to postgres;
alter function private.inversion_origen_inmutable() owner to postgres;
alter function private.conversion_lead_con_inversion() owner to postgres;
alter function private.inversion_persona_contexto(uuid,uuid) owner to postgres;
alter function private.inversion_persona_lectura(uuid) owner to postgres;
alter function private.inversion_contexto_lectura(uuid,uuid) owner to postgres;
alter function crm.cancelar_solicitud_inversion_fn(uuid,integer) owner to postgres;
alter function crm.preparar_persona_lead_inversion_fn(uuid,text,text,text) owner to postgres;
alter function crm.contexto_conversion_inversion_fn(uuid,uuid) owner to postgres;
alter function crm.bienvenida_inversion_estado_fn(uuid) owner to postgres;
alter function crm.bienvenida_inversion_entrega_fn(uuid,text,uuid,text) owner to postgres;
notify pgrst,'reload schema';
commit;`);
writeFileSync(new URL('../../migrations/20260919161807_crm_conversion_inversion_unificada.sql', import.meta.url), partes.join('\n\n')+'\n');
console.log('Migración reproducida desde 16 definiciones verificadas y el contexto explícito del lead.');
const restaurar=new Set(['acceso_inversion_fn','confirmar_inversion_revisada_fn','convertir_lead_externo',
  'corregir_solicitud_inversion_fn','preparar_inversion_fn','revisar_solicitud_inversion_fn',
  'inversion_persona_contexto','inversion_solicitud_resultado','inversion_validar_datos']);
const reversa=`-- REVERSA OPERATIVA: requiere autorización independiente. Conserva hechos,
-- columnas, auditoría, correos e identidades. No abandona solicitudes abiertas.
begin;
set local lock_timeout='5s';
lock table crm.inversion_solicitudes in access exclusive mode;
do $$ begin
  if exists(select 1 from crm.inversion_solicitudes where lead_origen_id is not null and estado='preparada') then
    raise exception 'Finaliza las solicitudes de conversión pendientes con la interfaz nueva antes de revertir';
  end if;
end $$;
revoke execute on function crm.preparar_persona_lead_inversion_fn(uuid,text,text,text) from authenticated;
revoke execute on function crm.contexto_conversion_inversion_fn(uuid,uuid) from authenticated;
revoke execute on function crm.cancelar_solicitud_inversion_fn(uuid,integer) from authenticated;
drop trigger conversion_reserva_legacy_cerrada on crm.conversion_reservas;
drop trigger trg_leads_conversion_con_inversion on crm.leads;
${base.filter(f=>restaurar.has(f.nombre)).map(f=>f.definicion.trimEnd()+';').join('\n')}
${permisoArchivo}
notify pgrst,'reload schema';
commit;
`;
writeFileSync(new URL('./reversa.sql',import.meta.url),reversa);

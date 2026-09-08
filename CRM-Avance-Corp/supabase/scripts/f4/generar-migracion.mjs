// Ensambla el SQL revisable, sin conectarse a ninguna base.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const originales=['base-funciones.json','base-funciones-adicionales.json'].flatMap(n=>
  JSON.parse(readFileSync(new URL(n,import.meta.url),'utf8')));
const cambios=[];
const fecha=a=>`coalesce((${a}.fecha_imputacion::timestamp at time zone 'America/Lima'),${a}.creado_en)`;
function reemplazar(s,antes,despues,n=1) {
  const encontrados=s.split(antes).length-1;
  assert.equal(encontrados,n,`Ancla inesperada (${encontrados}): ${antes}`);
  return s.replaceAll(antes,despues);
}
function cambiar(nombre,transformar) {
  const f=originales.find(x=>x.nombre===nombre);
  assert(f,`Falta ${nombre}`);
  const definicion=transformar(f.definicion);
  assert.notEqual(definicion,f.definicion,`Transformación vacía: ${nombre}`);
  cambios.push({...f,definicion});
}

// La migración global F2 sólo corresponde al estado anterior a F4. Desde
// esta instalación se usa censo y lote acotado, incluso con escritor apagado.
cambiar('private.backfill_multiempresa_ejecutar',s=>reemplazar(s,'\nbegin\n',`
begin
  if to_regclass('crm.inversion_solicitudes') is not null then
    raise exception 'F2 global ya fue sustituida por el censo y los lotes históricos F4'
      using errcode='55000';
  end if;
`));

cambiar('private.capital_episodios',s=>reemplazar(s,'ce.creado_en',fecha('ce'),5));
cambiar('private.cierre_anulado',s=>reemplazar(s,'where ce.lead_id = p_lead_id',
  'where ce.lead_id = p_lead_id and ce.es_cierre_inicial'));
cambiar('private.leads_before_update',s=>reemplazar(s,'where ce.lead_id = new.id',
  'where ce.lead_id = new.id and ce.es_cierre_inicial'));
cambiar('crm.cierres_estado_fn',s=>reemplazar(s,'left join crm.cierres_externos ce on ce.lead_id = l.id',
  'left join crm.cierres_externos ce on ce.lead_id = l.id and ce.es_cierre_inicial'));
cambiar('crm.anular_cierre_avance',s=>reemplazar(s,'from crm.cierres_externos ce where ce.lead_id = p_lead_id)',
  'from crm.cierres_externos ce where ce.lead_id = p_lead_id and ce.es_cierre_inicial)'));
cambiar('crm.enlazar_lead_inversionista_fn',s=>reemplazar(s,
  'select * into v_cierre from crm.cierres_externos ce where ce.lead_id = p_lead_id for update;',
  'select * into v_cierre from crm.cierres_externos ce where ce.lead_id = p_lead_id and ce.es_cierre_inicial for update;'));
cambiar('crm.altas_nuevas_por_analista_fn',s=>reemplazar(s,'where ce.anulado_en is not null',
  'where ce.anulado_en is not null and ce.es_cierre_inicial'));
cambiar('crm.contrato_eliminacion_preparar',s=>reemplazar(s,'  select * into v_eliminacion',
  `  -- La fila contractual ya está bloqueada y el actor ya fue autorizado.
  -- Rechazar ANTES de reservar el borrado o entregar rutas al borrador Storage.
  if exists(select 1 from crm.inversiones i where i.contrato_id=p_contrato_id) then
    raise exception 'El contrato forma parte del historial de inversiones; conserva el registro y utiliza la anulación comercial que corresponda'
      using errcode='55000';
  end if;

  select * into v_eliminacion`));

cambiar('public.proteger_campos_inmutables',s=>{
  s=reemplazar(s,'BEGIN\n  NEW.id',`DECLARE
  v_f4_alinea boolean := false;
BEGIN
  -- Excepción de una única columna desde la revisión F4 del servidor. Las
  -- escrituras directas mantienen todas las congelaciones originales.
  IF TG_TABLE_NAME='perfiles' AND current_user='postgres'
     AND nullif(current_setting('crm.f4_revision_solicitud',true),'') IS NOT NULL THEN
    v_f4_alinea:=private.f4_alineacion_perfil_permitida(OLD.id,NEW.asesor_perfil_id);
  END IF;
  NEW.id`);
  s=reemplazar(s,'    NEW.asesor_perfil_id := OLD.asesor_perfil_id;',
    '    IF NOT v_f4_alinea THEN NEW.asesor_perfil_id := OLD.asesor_perfil_id; END IF;');
  return reemplazar(s,`    IF NEW.asesor_perfil_id IS DISTINCT FROM OLD.asesor_perfil_id
       OR NEW.asesor_id IS DISTINCT FROM OLD.asesor_id THEN`,
    `    IF (NEW.asesor_perfil_id IS DISTINCT FROM OLD.asesor_perfil_id AND NOT v_f4_alinea)
       OR NEW.asesor_id IS DISTINCT FROM OLD.asesor_id THEN`);
});

for (const nombre of ['crm.anular_cierre_externo','crm.corregir_cierre_externo']) cambiar(nombre,s=>{
  if (nombre==='crm.anular_cierre_externo') s=reemplazar(s,
    'v_ajuste := private.registrar_ajuste_si_mes_cerrado(v_cierre.lead_id, v_motivo, v_uid);',
    `if v_cierre.es_cierre_inicial then
    v_ajuste := private.registrar_ajuste_si_mes_cerrado(v_cierre.lead_id, v_motivo, v_uid);
  end if;`);
  s=reemplazar(s,'  insert into crm.actividades (','  if v_cierre.lead_id is not null then\n  insert into crm.actividades (');
  s=reemplazar(s,'    v_uid\n  );\n\n  return jsonb_build_object(',
    '    v_uid\n  );\n  end if;\n\n  return jsonb_build_object(');
  return s;
});

cambiar('crm.cierres_externos_fn',s=>{
  s=reemplazar(s,`'telefono', case when v_global or l.vendedor_id = any(v_visibles)
                         then l.telefono end,`,
    `'telefono', case when v_global or case
          -- F3 conserva la tenencia del lead convertido como historia. El
          -- teléfono vivo de una persona reconocida sigue su relación actual.
          when ce.inversionista_id is not null then exists (
            select 1 from crm.inversionistas ip
            where ip.id=private.inversionista_canonica(ce.inversionista_id)
              and ip.responsable_relacion_id=any(v_visibles))
          else l.vendedor_id=any(v_visibles) end
                         then l.telefono end,`,2);
  s=reemplazar(s,'join crm.leads l on l.id = ce.lead_id','left join crm.leads l on l.id = ce.lead_id',2);
  for (const a of ['ce','ce0']) {
    s=reemplazar(s,`${a}.creado_en >= v_ini and ${a}.creado_en < v_fin`,
      `${fecha(a)} >= v_ini and ${fecha(a)} < v_fin`,a==='ce'?2:1);
  }
  s=reemplazar(s,"'creado_en', ce.creado_en,",`'creado_en', ce.creado_en,
        'fecha_comercial', coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
        'fecha_imputacion', coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
        'es_cierre_inicial', ce.es_cierre_inicial,`,2);
  return s;
});
cambiar('private.metricas_conversiones_implementacion',s=>{
  s=reemplazar(s,"(ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta",
    `(${fecha('ce')} at time zone 'America/Lima')::date between p_desde and p_hasta`);
  return reemplazar(s,'where ce.lead_id = l.id and ce.anulado_en is null',
    'where ce.lead_id = l.id and ce.es_cierre_inicial and ce.anulado_en is null');
});
cambiar('crm.convertir_lead_externo',s=>{
  s=reemplazar(s,'  v_flag        boolean;','  v_flag        boolean;\n  v_escribe_inversion boolean;');
  const lectura="v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);";
  s=reemplazar(s,lectura,`${lectura}\n  v_escribe_inversion := private.inversiones_escritura_bajo_candado();`);
  s=reemplazar(s,'where ce.lead_id = p_lead_id\n      and upper(ce.numero_transaccion)',
    'where ce.lead_id = p_lead_id and ce.es_cierre_inicial\n      and upper(ce.numero_transaccion)');
  const ini=s.indexOf("  if v_flag and v_inv is not null\n     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'inversiones_escritura'), false) then");
  assert(ini>=0,'Falta la rama relacional legacy');
  const fin=s.indexOf('\n  end if;',ini);
  assert(fin>ini);
  s=s.slice(0,ini)+`  if v_flag and v_inv is not null and v_escribe_inversion then
    perform private.inversion_vincular_fuente(v_inv,null,v_cierre_id,v_uid,true);`+s.slice(fin);
  return s;
});

// La bandera F4 se toma antes de cualquier candado de persona, cuenta o PDF.
for (const nombre of ['public.crear_contrato','crm.crear_contrato_con_cuenta','crm.crear_contrato_con_cuenta_pdf_v2']) {
  cambiar(nombre,s=>{
    const i=s.indexOf('\nbegin\n');
    assert(i>=0,`Falta el BEGIN exterior de ${nombre}`);
    s=s.slice(0,i)+s.slice(i).replace('\nbegin\n',
      '\nbegin\n  perform private.inversiones_escritura_bajo_candado(); -- F4: bandera antes de persona/cuenta/PDF\n');
    if (nombre==='crm.crear_contrato_con_cuenta_pdf_v2') s=reemplazar(s,
      '  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);',
      `  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  if private.inversiones_escritura_bajo_candado() then
    perform private.inversion_cotitulares_vincular(
      (select id from crm.inversiones where contrato_id=v_contrato_id),'alta');
  end if;`);
    return s;
  });
}

const mods=['01-base.sql','02-confirmacion.sql','03-coherencia.sql','04-avance.sql','05-acceso-portal.sql','06-revision-responsable.sql','07-historicos.sql','08-historicos-lote.sql','09-cotitular-puerta.sql','10-cotitulares-neutrales.sql','11-correccion-solicitud.sql'];
const cuerpos=mods.map(n=>readFileSync(new URL(n,import.meta.url),'utf8'));
const firmasNuevas=[
  'private.inversiones_escritura_bajo_candado()', 'private.inversion_persona_contexto(uuid)',
  'private.inversion_persona_autorizada(uuid)',
  'private.inversion_solicitud_resultado(uuid,jsonb)','crm.preparar_inversion_fn(uuid,jsonb)',
  'private.f4_comprobante_autorizado(text)','private.f4_fuente_inmutable()',
  'private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)','crm.confirmar_inversion_fn(uuid)',
  'private.f4_comprobante_visible(text)','private.f4_sincronizar_cierre()',
  'private.f4_contrato_reconocer()','private.f4_contrato_vincular()',
  'private.inversion_datos_portal(jsonb)','crm.acceso_inversion_fn(uuid,text,jsonb)',
  'private.f4_alineacion_perfil_permitida(uuid,uuid)','crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)',
  'private.inversion_historica_estado(text,uuid)','private.inversion_historica_aplicar(uuid,jsonb)',
  'private.f4_proteger_lote_historico()',
  'private.inversion_validar_datos(uuid,jsonb,jsonb)', 'crm.solicitud_inversion_fn(uuid)',
  'crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)', 'crm.confirmar_inversion_revisada_fn(uuid,integer)',
  'private.f4_proteger_origen_cotitular()', 'private.inversion_cotitular_estado(uuid)',
  'private.inversion_cotitulares_vincular(uuid,text)', 'crm.inversion_cotitulares_fn(uuid)',
  'crm.conciliar_cotitulares_inversion_fn(uuid)', 'private.inversion_cotitulares_historicos(uuid)',
];
const literal=s=>`'${s.replaceAll("'","''")}'`;
const guardas=originales.map(f=>`  if md5(pg_get_functiondef(${literal(f.firma)}::regprocedure)) is distinct from ${literal(f.md5)} then
    raise exception 'F4: cambió la función %; recapturar y revisar antes de aplicar',${literal(f.firma)};
  end if;`).join('\n');
const propietarios=firmasNuevas.map(f=>`alter function ${f} owner to postgres;`).join('\n')+
  '\n'+['inversion_solicitudes','inversion_ajustes_mes_cerrado','inversion_eventos','inversion_solicitud_revisiones','inversion_backfill_lotes','inversion_cotitular_origenes','inversion_solicitud_correcciones']
    .map(t=>`alter table crm.${t} owner to postgres;`).join('\n');
const salida=resolve(process.argv[2]??'');
const raizMigraciones=fileURLToPath(new URL('../../migrations/',import.meta.url));
assert(salida.startsWith(raizMigraciones) && /^\d{14}_crm_f4_.*\.sql$/.test(basename(salida)),
  'Indica el archivo F4 creado por supabase migration new');
const contenido=`-- F4 multiempresa: SQL candidato. Construcción y pruebas aisladas; G4 aún no aprobado.
-- Fuentes: código vivo con huellas; módulos scripts/f4. No enciende ninguna bandera.
begin;
set local lock_timeout='5s';
set local check_function_bodies=true;
select pg_advisory_xact_lock(hashtext('crm_f4_multiempresa'));
do $guard$
begin
  if to_regclass('crm.inversion_solicitudes') is not null then raise exception 'F4 ya está instalada'; end if;
${guardas}
end;
$guard$;
${cuerpos[0]}
${cuerpos[1]}
${cambios.map(f=>`-- Adaptación acotada de ${f.firma}; antes ${f.md5}\n${f.definicion.trimEnd()}${f.definicion.trimEnd().endsWith(';')?'':';'}`).join('\n')}
${cuerpos.slice(2).join('\n')}
${propietarios}
notify pgrst,'reload schema';
commit;
`;
writeFileSync(salida,contenido);
writeFileSync(new URL('./ultima-migracion.json',import.meta.url),JSON.stringify({
  archivo:basename(salida),funciones:[...cambios.map(f=>f.nombre),...firmasNuevas.map(f=>f.split('(')[0])].sort(),
},null,2)+'\n');
console.log(`SQL F4 ensamblado: ${cambios.length} puertas adaptadas, ${firmasNuevas.length} funciones nuevas.`);

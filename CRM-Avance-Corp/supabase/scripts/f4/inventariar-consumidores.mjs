// Inventario estático reproducible del catálogo local; no sustituye las pruebas.
import assert from 'node:assert/strict';
import {writeFileSync,readFileSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {sql,entorno,literal as q} from './banco-local.mjs';
const funciones=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
 'nombre',n.nspname||'.'||p.proname,'body',p.prosrc,'md5',md5(pg_get_functiondef(p.oid)),
 'owner',pg_get_userbyid(p.proowner),'acl',p.proacl)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('crm','public','private') and p.prokind='f'`));
const sinComentarios=s=>s.replace(/--[^\n]*/g,'').replace(/\/\*[\s\S]*?\*\//g,'');
const clases={};
function clasificar(nombres,decision){for(const n of nombres.split(' ')){assert(!clases[n]);clases[n]=decision;}}
clasificar('private.cierre_anulado private.leads_before_update crm.cierres_estado_fn crm.anular_cierre_avance crm.altas_nuevas_por_analista_fn crm.enlazar_lead_inversionista_fn',
 'La conversión inicial usa es_cierre_inicial. Las inversiones adicionales no cambian canal ni sanción inicial.');
clasificar('private.capital_episodios crm.cierres_externos_fn private.metricas_conversiones_implementacion',
 'Recorre todas las fuentes económicas con fecha_imputacion o fecha histórica; no suma dinero desde inversiones. Detalle de cierres conserva foto de atribución; teléfono vivo exige relación canónica actual. Directorio recibe agregados.');
clasificar('private.inversion_solicitud_resultado private.inversion_validar_datos', 'Clasifica empresa/fuente; no presupone una fila por lead.');
clasificar('private.inversion_vincular_fuente private.inversion_persona_contexto private.inversion_historica_estado private.inversion_historica_aplicar',
 'Identifica fuente por UUID y persona canónica; censo y lote cerrado reemplazan mantenimiento global.');
clasificar('crm.confirmar_inversion_revisada_fn crm.convertir_lead_externo',
 'Escritores autorizados y serializados: fuente UUID/deposito único. Solo convertir_lead_externo crea el cierre inicial.');
clasificar('private.backfill_multiempresa_ejecutar', 'Retirada desde instalación F4 (55000), incluso con escritor apagado; corpus original probado ANTES.');
clasificar('crm.anular_cierre_externo crm.corregir_cierre_externo',
 'Gerencia modifica cierre por UUID; triggers conservan procedencia y sincronizan empresa/estado/eventos. Anulación conserva Capital ATR-4.');
clasificar('crm.corregir_documento_inversionista_fn crm.fusion_previsualizar_fn crm.fusionar_inversionistas_fn private.fusion_estado_jsonb private.fusion_impacto',
 'F3 recorre conjuntos completos por identidad, sin escalar por lead; conserva fuentes y fotos documentales, reasigna referencias canónicas.');
clasificar('private.inversiones_empresa_coherente', 'Comprueba empresa contra fuente UUID; no lee una fuente escalar por lead.');
const directos=funciones.filter(f=>sinComentarios(f.body).includes('cierres_externos'));
assert.deepEqual(directos.map(f=>f.nombre).sort(),Object.keys(clases).sort(),'Todo consumidor directo debe quedar clasificado');
const decisionesEscritor={
 'crm.confirmar_inversion_revisada_fn':'Confirmación F4: ámbito, revisión, evidencia, período y depósito; fuente y principal atómicos.',
 'private.backfill_multiempresa_ejecutar':'Bloqueado por guarda 55000 desde F4.',
 'private.inversion_historica_aplicar':'Administración sin API, escritor OFF, mapa y recenso bajo candados.',
 'crm.anular_cierre_externo':'Gerencia y UUID; sanción inicial separada de adicional, Capital conservado.',
 'crm.contrato_eliminacion_finalizar':'Requiere reserva por preparar, que rechaza vínculo F4 antes de entregar rutas; FK impide borrar fuente vinculada.',
 'crm.corregir_cierre_externo':'Gerencia y UUID; unicidad del depósito y trigger relacional.',
 'crm.convertir_lead_externo':'Una conversión inicial por lead; la segunda inversión usa otra puerta.',
 'crm.corregir_fecha_cierre_comercial':'Puerta publicada sujeta a congelación documental y atribución; no crea fuentes.',
 'crm.fusionar_inversionistas_fn':'Reapunta conjunto de identidades, conserva dinero y snapshots.',
 'crm.enlazar_lead_inversionista_fn':'Repara solo cierre inicial; las adicionales ya tienen identidad propia.',
 'private.trg_restaurar_operacion_antes_borrar_contrato':'Restauración legacy de cadena; borrado de fuente F4 no autorizado.',
 'public.actualizar_contrato':'Modificación publicada sujeta a snapshot PDF y procedencia inmutables.',
 'public.crear_contrato':'Puerta compartida F4 antes de persona/PDF; AFTER INSERT crea vínculo atómico.',
 'public.actualizar_numero_contrato':'Numeración administrativa; protege documento congelado.',
 'public.cerrar_contrato':'Estado/vigencia publicados; no borra inversión ni capital por sanción comercial.',
 'public.marcar_contrato_demo':'Marca auditada publicada; exclusión de Capital real conservada.',
 'public.marcar_contratos_vencidos':'Job publicado de vigencia; no crea ni duplica fuentes.',
 'public.reasignar_analista_contrato':'Atribución efectiva de cadena; autor histórico y meses sellados conservados.',
};
const patron=/(?:insert\s+into|update|delete\s+from)\s+(?:public\.)?contratos\b|(?:insert\s+into|update|delete\s+from)\s+crm\.cierres_externos\b/i;
const escritores=funciones.filter(f=>patron.test(sinComentarios(f.body)));
assert.deepEqual(escritores.map(f=>f.nombre).sort(),Object.keys(decisionesEscritor).sort());
const semillas=new Set([...directos,...escritores].map(f=>f.nombre));
// Cierre transitivo de llamadas SQL explícitas; incluye wrappers públicos.
let nuevos=true;while(nuevos){nuevos=false;for(const f of funciones){
 const llamadas=[...sinComentarios(f.body).matchAll(/\b((?:crm|private|public)\.[a-z_0-9]+)\s*\(/gi)].map(m=>m[1]);
 if(llamadas.some(n=>semillas.has(n))&&!semillas.has(f.nombre)){semillas.add(f.nombre);nuevos=true;}
}}
const tablas=['crm.cierres_externos','public.contratos','crm.inversiones','crm.inversion_titulares'];
const triggers=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('tabla',t.tgrelid::regclass::text,'nombre',t.tgname,
 'funcion',t.tgfoid::regprocedure::text,'definicion',pg_get_triggerdef(t.oid))) from pg_trigger t where not t.tgisinternal
 and t.tgrelid=any(array[${tablas.map(t=>q(t)+'::regclass').join(',')}])`));
const vistas=JSON.parse(sql(`select coalesce(jsonb_agg(jsonb_build_object('schema',schemaname,'vista',viewname,'md5',md5(definition))),'[]')
 from pg_views where schemaname in ('crm','public','private') and (definition ilike '%cierres_externos%' or definition ilike '%inversiones%')`));
const permisos=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('tabla',c.oid::regclass::text,'rls',c.relrowsecurity,'acl',c.relacl))
 from pg_class c where c.oid=any(array[${tablas.map(t=>q(t)+'::regclass').join(',')}])`));
const comisiones=JSON.parse(sql(`select jsonb_build_object('tablas',(select coalesce(jsonb_agg(table_schema||'.'||table_name),'[]') from information_schema.tables
 where table_schema in ('crm','public','private') and table_name ~* '(comisi|commiss|liquidacion)'),
 'funciones',(select coalesce(jsonb_agg(p.oid::regprocedure::text),'[]') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('crm','public','private') and p.proname ~* '(comisi|commiss|liquidacion)'))`));
const resumir=f=>({firma:f.firma,md5:f.md5,owner:f.owner,acl:f.acl});
const informe={entorno,creadoEn:new Date().toISOString(),funcionesInspeccionadas:funciones.length,
 consumidoresDirectos:directos.map(f=>({...resumir(f),decision:clases[f.nombre]})),
 escritores:escritores.map(f=>({...resumir(f),decision:decisionesEscritor[f.nombre]})),
 consumidoresTransitivos:funciones.filter(f=>semillas.has(f.nombre)).map(resumir),triggers,vistas,permisos,comisiones,
 limites:['Inventario de catálogo y referencias SQL explícitas; no es análisis dinámico de SQL arbitrario. Triggers genéricos se incluyen por pg_trigger.',
 'No hay motor/registro de comisión identificado en este esquema; pendiente localizar fuente externa, no se inventa una regla de liquidación.'],
 sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex')};
writeFileSync(new URL(`../evidencia-f4/inventario-consumidores-${randomUUID()}.json`,import.meta.url),JSON.stringify(informe,null,2)+'\n',{flag:'wx'});
console.log(`Inventario: ${funciones.length} funciones; ${directos.length} consumidores directos clasificados, ${escritores.length} escritores, ${semillas.size} consumidores transitivos y ${triggers.length} triggers.`);

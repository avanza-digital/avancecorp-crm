import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { sql, leer, guardar, literal as q } from './banco-local.mjs';
import { cargarHistoricosPrueba, objetosHistoricosSql } from './cargar-historicos-prueba.mjs';

const base = leer('operaciones-base.json');
const ejecucion = randomUUID();
const fuente = readFileSync(new URL('./07-historicos.sql', import.meta.url), 'utf8');
const sha = x => createHash('sha256').update(x).digest('hex');
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f');
const carga=cargarHistoricosPrueba(sql);
const objetosIniciales=sql(objetosHistoricosSql);
const fotoSql = `select jsonb_object_agg(tabla,huella) from (
  select 'contratos' tabla,private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) huella from public.contratos t
  union all select 'cuotas',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from public.cronograma_pagos t
  union all select 'cierres',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.cierres_externos t
  union all select 'personas',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversionistas t
  union all select 'identificadores',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversionista_identificadores t
  union all select 'perfiles',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from public.perfiles t
  union all select 'leads',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.leads t
  union all select 'mapaF2',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.backfill_multiempresa_mapa t
  union all select 'inversiones',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversiones t
  union all select 'titulares',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversion_titulares t
  union all select 'jobsPdf',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from private.contrato_pdf_jobs t
  union all select 'sellosPdf',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.contrato_id),'[]')) from private.contrato_pdfs t
  union all select 'banderas',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.nombre),'[]')) from crm.multiempresa_flags t
  union all select 'capital',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'))
    from private.capital_episodios('-infinity','infinity',true,'{}') t
) x`;
const antes = JSON.parse(sql(fotoSql));
const guion = `begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
${carga.preparacion}
create function pg_temp.foto_f4() returns jsonb language sql as $f$ ${fotoSql} $f$;
create temp table _f4_censo_pruebas(nombre text,datos jsonb) on commit drop;
do $pruebas$
declare r record; x jsonb; inicial jsonb; h jsonb; n integer:=0; v uuid; ce uuid; lead_negativo uuid:=gen_random_uuid();
begin
  inicial:=pg_temp.foto_f4();
  for r in
    select 'contrato' tipo,id from public.contratos where numero_contrato like 'F4-BASE-%'
    union all select 'cierre',id from crm.cierres_externos where numero_transaccion like 'F4-BASE-%'
  loop
    x:=private.inversion_historica_estado(r.tipo,r.id);
    if x->>'estado'<>'pendiente' then raise exception 'Antecedente inesperado: %',x; end if;
    if x->>'persona' is null or x->>'huella' !~ '^[a-f0-9]{64}$' then raise exception 'Censo incompleto'; end if;
    n:=n+1;
  end loop;
  if n<>6 or pg_temp.foto_f4()<>inicial then raise exception 'El censo debe conservar las seis fuentes y toda la foto'; end if;
  insert into _f4_censo_pruebas values('Seis antecedentes pendientes: censo sin escrituras',jsonb_build_object('fuentes',n));

  n:=0;
  for r in select ce.id from crm.cierres_externos ce join crm.inversiones i on i.cierre_externo_id=ce.id
    order by ce.id limit 14 loop
    x:=private.inversion_historica_estado('cierre',r.id);
    if x->>'estado'<>'resuelto' then raise exception 'Vínculo previo no resuelto: %',x; end if;
    n:=n+1;
  end loop;
  if n<>14 or pg_temp.foto_f4()<>inicial then raise exception 'Los vínculos previos deben conservarse'; end if;
  insert into _f4_censo_pruebas values('Catorce vínculos anteriores se reconocen sin otra escritura',jsonb_build_object('fuentes',n,'procedencia','operaciones F4 del banco; no se atribuyen a F2 productiva'));

  -- Fixture relacional equivalente a una salida F2: usa sus primitivas de mapa
  -- y enlace sobre una fuente anterior real del banco; no ejecuta el pipeline
  -- global de F2 ni pretende probar todavía su reconstrucción histórica.
  select id into ce from crm.cierres_externos where numero_transaccion='F4-BASE-qorilazo';
  v:=private.inversion_vincular_fuente(${q(base.identidades.qorilazo)},null,ce,null,true);
  perform private.f2_mapear('cierre',ce,${q(base.identidades.qorilazo)},'B','Fixture de salida F2: documento verificado','alta');
  h:=pg_temp.foto_f4();
  x:=private.inversion_historica_estado('cierre',ce);
  if x->>'estado'<>'resuelto' or (x->>'inversion')::uuid<>v or pg_temp.foto_f4()<>h then
    raise exception 'El enlace y el mapa F2 deben conservarse: %',x;
  end if;
  insert into _f4_censo_pruebas values('Mapa F2 y vínculo coherentes conservados',jsonb_build_object('estado',x->>'estado'));

  perform private.f2_mapear('cierre',ce,${q(base.identidades.prodelco)},'B','Fixture negativa de mapa discrepante','alta');
  h:=pg_temp.foto_f4();
  x:=private.inversion_historica_estado('cierre',ce);
  if x->>'estado'<>'revision' or not (x->'motivos' ? 'identidades_en_conflicto') or pg_temp.foto_f4()<>h then
    raise exception 'La discrepancia no se puede resolver escribiendo: %',x;
  end if;
  insert into _f4_censo_pruebas values('Mapa en conflicto requiere revisión sin efectos',x->'motivos');

  select id into ce from crm.cierres_externos where numero_transaccion='F4-BASE-prodelco';
  perform set_config('crm.op_privilegiada','on',true);
  update crm.cierres_externos set inversionista_id=null where id=ce;
  perform set_config('crm.op_privilegiada','off',true);
  h:=pg_temp.foto_f4();
  x:=private.inversion_historica_estado('cierre',ce);
  if x->>'estado'<>'pendiente' or x->>'fuente_persona' is not null
    or (x->>'persona')::uuid<>${q(base.identidades.prodelco)}::uuid or pg_temp.foto_f4()<>h then
    raise exception 'La fuente sin vínculo exige documento y lead coincidentes: %',x;
  end if;
  insert into _f4_censo_pruebas values('Fuente sin vínculo se reconoce por documento verificado y lead',jsonb_build_object('estado',x->>'estado'));

  -- El documento de un cierre es inmutable: la fixture negativa nace separada,
  -- no se evita el trigger de corrección de una fuente existente.
  insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,vendedor_id,creado_por,origen)
    select lead_negativo,'FIXTURE CENSO SIN DOCUMENTO',
      '990'||lpad(trunc(random()*1000000)::text,6,'0'),10,'propuesta_enviada',vendedor_id,creado_por,'otro'
    from crm.cierres_externos where id=ce;
  with nuevo as (
    insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
      nombre_completo,numero_transaccion,referencia_externa,vendedor_id,creado_por)
    select lead_negativo,cooperativa,10,'PEN','DNI','00000000','FIXTURE FICTICIA SIN VERIFICACION',
      'F4-CENSO-'||gen_random_uuid()::text,'ENSAYO REVERTIDO',vendedor_id,creado_por
    from crm.cierres_externos where id=ce returning id
  ) select id into ce from nuevo;
  h:=pg_temp.foto_f4();
  x:=private.inversion_historica_estado('cierre',ce);
  if x->>'estado'<>'revision' or not (x->'motivos' ? 'documento_sin_identidad_verificada') or pg_temp.foto_f4()<>h then
    raise exception 'Un formato válido no verifica a la persona: %',x;
  end if;
  insert into _f4_censo_pruebas values('Formato documental válido sin verificación no crea identidad',x->'motivos');

  x:=private.inversion_historica_estado('contrato','00000000-0000-4000-8000-000000000000');
  if x->>'estado'<>'ausente' then raise exception 'Fuente ausente incorrecta'; end if;
  begin
    perform private.inversion_historica_estado('otro',ce);
    raise exception 'No rechazó el tipo';
  exception when invalid_parameter_value then null; end;
  insert into _f4_censo_pruebas values('Fuente ausente y tipo inválido rechazados','{}');
end;
$pruebas$;
select jsonb_agg(jsonb_build_object('nombre',nombre,'conforme',true,'datos',datos) order by nombre) from _f4_censo_pruebas;
rollback;`;
let pruebas;
try {
  pruebas = JSON.parse(sql(guion));
} catch (error) {
  guardar(`historicos-censo-${ejecucion}-fallo.json`, { error: error.message, sha256Definicion: sha(fuente) });
  throw error;
} finally {
  assert.deepEqual(JSON.parse(sql(fotoSql)), antes, 'El ensayo debe revertir todas sus fixtures y conservar la foto inicial');
  assert.equal(sql(objetosHistoricosSql), objetosIniciales);
}
const resultado = { entorno, ejecucion, terminadoEn: new Date().toISOString(), pruebas,
  sha256Definicion: sha(fuente), huellasAntesYDespues: antes, transaccionRevertida: true,
  limites: ['Previsualización administrativa; todavía no aplica un lote histórico.',
    'Los escenarios negativos y el mapa equivalente a F2 son fixtures explícitas dentro de una transacción revertida.',
    'La reconstrucción con el pipeline F2 original y su reversa siguen pendientes.',
    'El ensayo conserva la instalación inicial; no aplica ningún lote histórico fuera de la transacción revertida.',
    'Contenido PDF intacto; G4 sigue abierto.'] };
guardar(`historicos-censo-${ejecucion}.json`, resultado);
writeFileSync(new URL(`../evidencia-f4/historicos-censo-${ejecucion}.json`, import.meta.url), JSON.stringify(resultado, null, 2) + '\n', { flag: 'wx' });
console.log(`Censo histórico F4: ${pruebas.length} grupos conformes; fuentes, identidad, mapa, PDFs y Capital conservados.`);

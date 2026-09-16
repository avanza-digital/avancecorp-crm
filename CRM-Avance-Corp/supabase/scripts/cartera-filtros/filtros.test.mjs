import test from 'node:test';
import assert from 'node:assert/strict';
import {consulta,sql,ejecutar,q,gerencia,preparar,claims} from './banco.mjs';

const persona='1236062f-a28e-4fe7-a6ba-feb45a63c798';
const perfil='3dc87919-4c2a-469c-a7fc-eadd1f9d9433';
const documento=sql(`select dni from public.perfiles where id=${q(perfil)}`);
const vendedor=sql(`select responsable_relacion_id from crm.inversionistas where id=${q(persona)}`);
const supervisor=sql("select perfil_id from crm.equipo where activo and rol_crm='supervisor' order by perfil_id limit 1");
const ajeno=sql(`select perfil_id from crm.equipo where activo and rol_crm='vendedor' and perfil_id<>${q(vendedor)} order by perfil_id desc limit 1`);
const directorio=sql("select perfil_id from crm.equipo where rol_crm='directorio' limit 1");
const activarViejos=`update crm.equipo set activo=true,supervisor_id=${q(supervisor)} where perfil_id=${q(vendedor)};
  update crm.equipo set activo=true where perfil_id=${q(directorio)};`;
const llamada=c=>'crm.cartera_inversionistas_filtrada_fn('+Object.entries(c).map(([k,v])=>`${k}=>${typeof v==='number'||typeof v==='boolean'?v:q(v)}`).join(',')+')';
const lista=(c={},actor=gerencia,antes='')=>consulta(llamada(c),actor,activarViejos+antes);
const cliente=c=>lista({p_texto:documento,...c});
const sinInversiones=`set local request.jwt.claim.sub=${q(gerencia)};
  do $s$ declare id uuid; begin for n in 1..26 loop id:=gen_random_uuid();
    insert into auth.users(id) values(id);
    insert into public.perfiles(id,nombre_completo,rol,activo,asesor_perfil_id,tipo_documento,dni)
      values(id,'FILTROS SIN INVERSION '||lpad(n::text,2,'0'),'cliente',true,${q(vendedor)},'CE','007700'||lpad(n::text,3,'0'));
    perform private.asegurar_identidad_perfil(id,'ensayo_filtros');
  end loop;end;$s$;`;

test('mes comercial preserva el cierre retroactivo, sin usar registro ni imputación',()=>{
  const julio=cliente({p_mes:'2026-07'});
  assert.equal(julio.total,1);
  assert.deepEqual(julio.totales,[{empresa:'qorilazo',moneda:'PEN',cantidad:1,capital_registrado:450,capital_activo:null}]);
  assert.equal(julio.filas[0].ultima_fecha_comercial,'2026-07-15');
  assert.deepEqual(julio.filas[0].resumen,julio.totales);
  const septiembre=cliente({p_mes:'2026-09',p_empresa:'qorilazo'});
  assert.equal(septiembre.totales[0].capital_registrado,3300);
  assert.equal(septiembre.totales[0].cantidad,2);
});
test('empresa, mes, moneda y estado deben corresponder a la MISMA fuente',()=>{
  for(const c of [
    {p_mes:'2026-07',p_empresa:'avance'},
    {p_mes:'2026-07',p_moneda:'USD'},
    {p_empresa:'prodelco',p_moneda:'USD'},
    {p_mes:'2026-09',p_estado:'anulado_comercialmente'},
    {p_mes:'2026-07',p_estado:'vigente'},
  ]) {const d=cliente(c);assert.equal(d.total,0);assert.deepEqual(d.totales,[]);assert.deepEqual(d.filas,[]);}
});
test('PEN/USD no se mezclan y capital activo viene del mismo núcleo',()=>{
  const d=cliente({p_empresa:'avance',p_mes:'2026-09',p_estado:'vigente'});
  assert.equal(d.total,1);
  assert.deepEqual(d.totales,[
    {empresa:'avance',moneda:'PEN',cantidad:3,capital_registrado:3800,capital_activo:3800},
    {empresa:'avance',moneda:'USD',cantidad:2,capital_registrado:4900,capital_activo:4900},
  ]);
  assert.deepEqual(cliente({p_empresa:'avance',p_mes:'2026-09',p_moneda:'USD'}).totales,[d.totales[1]]);
});
test('los estados del contrato no cambian por su etiqueta en pantalla',()=>{
  for(const estado of ['vencido','renovado','retirado']) {
    const d=lista({p_texto:documento,p_empresa:'avance',p_estado:estado},gerencia,
      `update public.contratos set estado=${q(estado)},renovado_a_id=${estado==='renovado' ? "'b480b3ea-a52c-476e-a69a-1183c46c8a64'::uuid" : 'null'}
        where id='56f79d92-aa9f-4f48-a3c2-101d16f14acb';`);
    assert.equal(d.total,1);assert.equal(d.totales.length,1);assert.equal(d.totales[0].capital_registrado,3400);
    assert(d.totales.every(t=>t.capital_activo===0));
  }
});
test('sin inversiones es ausencia real; clientes fuera del mes no entran en ese grupo',()=>{
  const d=lista({p_texto:'FILTROS SIN INVERSION',p_mes:'2026-07'},gerencia,sinInversiones);
  assert.equal(d.total,26);assert.equal(d.sin_inversiones_total,26);assert.deepEqual(d.totales,[]);
  assert(d.filas.every(p=>p.resumen.length===0 && p.empresas.length===0));
  assert.equal(cliente({p_estado:'sin_inversiones'}).total,0);
  assert.equal(lista({p_texto:'FILTROS SIN INVERSION',p_estado:'sin_inversiones'},gerencia,sinInversiones).total,26);
  assert.equal(lista({p_texto:'FILTROS SIN INVERSION',p_empresa:'avance'},gerencia,sinInversiones).total,0);
});
test('las páginas mantienen totales de TODA la selección y no duplican personas',()=>{
  const [a,b]=consulta(`jsonb_build_array(${llamada({p_texto:'FILTROS SIN INVERSION'})},${llamada({p_texto:'FILTROS SIN INVERSION',p_pagina:2})})`,gerencia,activarViejos+sinInversiones);
  assert.deepEqual([a.total,b.total,a.filas.length,b.filas.length],[26,26,25,1]);
  assert.equal(new Set([...a.filas,...b.filas].map(p=>p.inversionista_id)).size,26);
  const uno=lista({p_tamano:10,p_empresa:'avance'}),dos=lista({p_tamano:10,p_empresa:'avance',p_pagina:2});
  assert(uno.total>10);assert.equal(uno.total,dos.total);assert.deepEqual(uno.totales,dos.totales);
});
test('opciones de mes y responsable incluyen solo el ámbito autorizado, no la página',()=>{
  const d=lista({p_texto:documento},vendedor),s=lista({p_texto:documento},supervisor);
  assert.equal(d.total,1);assert.equal(s.total,1);
  assert(d.opciones_responsables.every(r=>r.id===vendedor));
  assert(d.opciones_meses.includes('2026-07'));
  assert.deepEqual(cliente({p_mes:'2026-07'}).opciones_meses,cliente({p_mes:'2026-09'}).opciones_meses);
  const otro=lista({p_texto:documento},ajeno);
  assert.equal(otro.total,0);assert(!otro.opciones_responsables.some(r=>r.id===vendedor));
  assert(!otro.opciones_meses.includes('2026-07'));
});
test('Directorio conserva solo Avance incluso en opciones y búsqueda de referencias',()=>{
  const d=lista({},directorio);
  assert.equal(d.solo_avance,true);assert(d.total>0);assert(d.totales.length>0);assert(d.totales.every(t=>t.empresa==='avance'));
  assert(d.filas.every(p=>p.empresas.every(e=>e==='avance') && p.resumen.every(r=>r.empresa==='avance')));
  assert.equal(lista({p_empresa:'qorilazo'},directorio).total,0);
  assert.equal(lista({p_texto:'AJUSTE SINTETICO F5'},directorio).total,0);
  assert(!d.opciones_meses.includes('2026-07'));
});
test('sin inversiones Avance no revela COOPAC ocultas a Directorio',()=>{
  // Fixture ya existente: perfil autorizado, una COOPAC y ningún contrato Avance.
  const soloCoopac='0a2b2a78-883b-4895-9f8c-5b32cff5b28b';
  const doc=sql(`select p.dni from crm.inversionistas i join public.perfiles p on p.id=i.perfil_id where i.id=${q(soloCoopac)}`);
  assert(doc.length>0);
  const d=lista({p_texto:doc,p_estado:'sin_inversiones'},directorio);
  assert.equal(d.solo_avance,true);assert.equal(d.total,1);assert.equal(d.sin_inversiones_total,1);
  assert.equal(d.filas[0].inversionista_id,soloCoopac);assert.deepEqual(d.filas[0].empresas,[]);
  assert.deepEqual(d.filas[0].resumen,[]);assert.deepEqual(d.totales,[]);
  const g=lista({p_texto:doc},gerencia);
  assert.equal(g.solo_avance,false);assert.equal(g.total,1);assert.equal(g.sin_inversiones_total,0);
  assert(g.totales.length>0);assert(g.totales.every(t=>t.empresa!=='avance'));
  assert.equal(lista({p_texto:doc,p_estado:'sin_inversiones'},gerencia).total,0);
});
test('Sin fecha no confunde ausencia de inversiones con ausencia de fecha',()=>{
  // Las fuentes actuales tienen fecha: Avance NOT NULL; COOPAC tiene fallback
  // canónico a creado_en. Se prueba el estado vacío real, sin perforar contratos.
  const d=cliente({p_mes:'sin_fecha'});
  assert.equal(d.total,0);assert.deepEqual(d.filas,[]);assert.deepEqual(d.totales,[]);
  assert.equal(lista({p_texto:'FILTROS SIN INVERSION',p_mes:'sin_fecha'},gerencia,sinInversiones).total,0);
  assert.equal(lista({p_texto:'FILTROS SIN INVERSION',p_estado:'sin_inversiones',p_mes:'sin_fecha'},gerencia,sinInversiones).total,0);
  assert.equal(lista({p_mes:'sin_fecha',p_empresa:'qorilazo'},directorio).total,0);
});
test('el núcleo no duplica identidades y el DTO no expone campos internos',()=>{
  for(const actor of [gerencia,supervisor,vendedor,directorio]) {
    const unicas=JSON.parse(sql(`begin;${preparar}${activarViejos}set local request.jwt.claim.sub=${q(actor)};
      select jsonb_build_array(count(*),count(distinct inversionista_id)) from private.cartera_f5_personas_visibles();rollback;`));
    assert(unicas[0]>0);assert.equal(unicas[0],unicas[1]);
    const d=lista({},actor);assert(d.filas.length>0);
    for(const fila of d.filas) assert.deepEqual(Object.keys(fila).sort(),[
      'inversionista_id','nombre','documento_tipo','documento','documento_verificado','telefono','correo',
      'estado','no_contactar','responsable_id','responsable_nombre','creado_en','empresas','ultima_fecha_comercial','resumen',
    ].sort());
  }
});
test('referencias se buscan literalmente y respetan los demás filtros',()=>{
  const d=lista({p_texto:'AC-2026-0016'});assert.equal(d.total,1);assert.equal(d.filas[0].inversionista_id,persona);
  assert.equal(lista({p_texto:'AC-2026-0016',p_empresa:'qorilazo'}).total,0);
  for(const texto of ['%','_','NO EXISTE ESTA PERSONA']) assert.equal(lista({p_texto:texto}).total,0);
});
test('No contactar filtra el atributo vigente sin quitar historia ni inventar permiso',()=>{
  const antes=`update crm.inversionistas set no_contactar=true,no_contactar_en=now() where id=${q(persona)};`;
  const d=lista({p_texto:documento,p_contacto:'no_contactar'},gerencia,antes);
  assert.equal(d.total,1);assert(d.totales.length>0);
  assert.equal(lista({p_texto:documento,p_contacto:'sin_restriccion'},gerencia,antes).total,0);
});
test('vencimiento de 30 días incluye los límites; no entra un contrato retirado',()=>{
  for(const [dias,estado,incluido] of [[0,'activo',true],[30,'activo',true],[31,'activo',false],[-1,'activo',false],[15,'retirado',false]]) {
    const d=lista({p_texto:documento,p_por_vencer:true,p_empresa:'avance'},gerencia,
      // Solo semilla de lectura en esta transacción local: conservar el PDF
      // anterior y restaurar el candado ANTES de consultar como authenticated.
      `alter table public.contratos disable trigger trg_contratos_00_documental_congelado;
       update public.contratos set fecha_vencimiento=(statement_timestamp() at time zone 'America/Lima')::date+${dias},estado=${q(estado)} where cliente_id=${q(perfil)};
       set constraints all immediate;
       alter table public.contratos enable trigger trg_contratos_00_documental_congelado;`);
    assert.equal(d.total,incluido?1:0,`${dias} / ${estado}`);
  }
});
test('un perfil inactivo conserva capital registrado pero no lo cuenta como activo',()=>{
  const d=lista({p_texto:documento,p_empresa:'avance'},gerencia,`update public.perfiles set activo=false where id=${q(perfil)};`);
  assert.equal(d.total,1);assert(d.totales.every(t=>t.capital_activo===0 && t.capital_registrado>0));
});
test('anon, coordinador, cliente e inactivo no enumeran datos ni opciones',()=>{
  const coord=sql("select perfil_id from crm.equipo where activo and rol_crm='coordinador' limit 1");
  const inactivo=sql("select perfil_id from crm.equipo where not activo and rol_crm='gerencia' limit 1");
  for(const [rol,actor,antes] of [['anon',null,''],['authenticated',coord,''],['authenticated',perfil,''],
    ['authenticated',inactivo,'']]) {
    const r=ejecutar(`begin;${preparar}${activarViejos}${antes}set local request.jwt.claim.sub=${q(actor??'')};set local role ${rol};select ${llamada({})};rollback;`);
    assert.notEqual(r.status,0);assert.match(r.stderr,/42501/);
  }
});
test('validación estricta y candado F5 previo a todas las lecturas',()=>{
  for(const c of [{p_mes:'2026-13'},{p_mes:'0000-01'},{p_mes:'2026-09-01'},{p_mes:''},{p_moneda:'EUR'},
    {p_estado:'activo'},{p_contacto:'otro'},{p_tamano:100},{p_pagina:0},{p_por_vencer:null},
    {p_sin_responsable:true,p_responsable:vendedor},{p_texto:'a'.repeat(121)}]) {
    const r=ejecutar(`begin;${preparar}${claims(gerencia)}select ${llamada(c)};rollback;`);
    assert.notEqual(r.status,0);assert.match(r.stderr,/22023/,JSON.stringify(c));
  }
  const r=ejecutar(`begin;${preparar}update crm.multiempresa_flags set activo=false where nombre='ficha_360_neutral';${claims(gerencia)}select ${llamada({})};rollback;`);
  assert.notEqual(r.status,0);assert.match(r.stderr,/P0409/);
});

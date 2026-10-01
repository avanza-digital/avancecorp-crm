-- Flag apagado en transacción propia: nunca se pierde el CE en silencio.
begin;
update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$ begin
  perform crm.crear_lead_documento_fn(
    '{"id":"d0000000-0000-4000-8000-000000000099","nombre_completo":"FLAG APAGADO","telefono":"988770099","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
    'CE','009900099');
  raise exception 'FAIL: alta CE con identidad apagada';
exception when sqlstate 'P0409' then raise notice 'PASS: flag apagado impide alta sin perder documento'; end $$;
rollback;
begin;
create function pg_temp.comprobar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %',mensaje; end if; raise notice 'PASS: %',mensaje; end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
-- La envoltura conserva permisos y validación de la puerta DEFINER anterior.
do $$ declare v_etapa text; begin
  begin
    perform crm.crear_lead_documento_fn(
      '{"id":"d0000000-0000-4000-8000-000000000090","nombre_completo":"ASIGNACION AJENA","telefono":"988770090","origen":"referido","monto_estimado":5000,"moneda":"PEN","vendedor_id":"b0000000-0000-4000-8000-000000000001"}', 'CE','009900090');
    raise exception 'FAIL: alta para otro responsable';
  exception when insufficient_privilege then raise notice 'PASS: alta para otro responsable denegada'; end;
  foreach v_etapa in array array['convertido','descartado','ganado'] loop
    begin
      perform crm.crear_lead_documento_fn(jsonb_build_object('id','d0000000-0000-4000-8000-000000000091','nombre_completo','ETAPA INVALIDA','telefono','988770091','origen','referido','monto_estimado',5000,'moneda','PEN','etapa',v_etapa),'CE','009900091');
      raise exception 'FAIL: etapa terminal/inválida';
    exception when sqlstate '22023' then raise notice 'PASS: etapa % rechazada',v_etapa; end;
  end loop;
end $$;
select pg_temp.comprobar(crm.crear_lead_documento_fn(
  '{"id":"d0000000-0000-4000-8000-000000000001","nombre_completo":"PERSONA CE SINTETICA","telefono":"988770001","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
  'CE','009900001')->>'estado'='creado','alta CE');
select pg_temp.comprobar(crm.documento_lead_fn('d0000000-0000-4000-8000-000000000001')->>'numero'='009900001','CE conserva ceros');
select pg_temp.comprobar((crm.documento_lead_fn('d0000000-0000-4000-8000-000000000001')->>'tipo')='CE','lectura del tipo CE');
select pg_temp.comprobar((select dni is null from crm.leads where id='d0000000-0000-4000-8000-000000000001'),'CE no contamina DNI legado');
select pg_temp.comprobar(crm.crear_lead_documento_fn(
  '{"id":"d0000000-0000-4000-8000-000000000001","nombre_completo":"PERSONA CE SINTETICA","telefono":"988770001","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
  'CE','009900001')->>'estado'='creado','reintento CE idempotente');
do $$ begin
  perform crm.crear_lead_documento_fn(
    '{"id":"d0000000-0000-4000-8000-000000000001","nombre_completo":"PERSONA CE SINTETICA","telefono":"988770001","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
    'CE','009900002');
  raise exception 'FAIL: reintento con otro documento';
exception when sqlstate '22023' then raise notice 'PASS: reintento con otro documento rechazado'; end $$;
select pg_temp.comprobar(crm.preparar_persona_lead_inversion_fn(
  'd0000000-0000-4000-8000-000000000001','CE','009900001','PERSONA CE SINTETICA')->>'lead_id'='d0000000-0000-4000-8000-000000000001',
  'conversión acepta el CE del alta');
select pg_temp.comprobar(crm.crear_lead_documento_fn(
  '{"id":"d0000000-0000-4000-8000-000000000002","nombre_completo":"PERSONA PASAPORTE SINTETICA","telefono":"988770002","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
  'PASAPORTE','ab990002')->>'estado'='creado','alta pasaporte');
select pg_temp.comprobar(crm.documento_lead_fn('d0000000-0000-4000-8000-000000000002')->>'numero'='AB990002','pasaporte en mayúscula');
select pg_temp.comprobar(crm.preparar_persona_lead_inversion_fn(
  'd0000000-0000-4000-8000-000000000002','PASAPORTE','AB990002','PERSONA PASAPORTE SINTETICA')->>'lead_id'='d0000000-0000-4000-8000-000000000002',
  'conversión acepta el pasaporte del alta');
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000001','CE','009900099');
  raise exception 'FAIL: vendedor cambia identidad reconocida';
exception when insufficient_privilege then raise notice 'PASS: vendedor no cambia identidad reconocida'; end $$;
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000001','CE','009900001',
    'd0000000-0000-4000-8000-000000000099');
  raise exception 'FAIL: acepta identificador obsoleto';
exception when sqlstate 'P0409' then
  if sqlerrm not like '%otra sesión%' then raise; end if;
  raise notice 'PASS: identificador obsoleto pide recargar con código reconocido por la UI'; end $$;
do $$ begin
  perform crm.crear_lead_documento_fn(
    '{"id":"d0000000-0000-4000-8000-000000000003","nombre_completo":"DUPLICADO SINTETICO","telefono":"988770003","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
    'CE','009900001');
  raise exception 'FAIL: mismo CE en dos leads';
exception when sqlstate 'P0409' then raise notice 'PASS: CE duplicado rechazado'; end $$;
select pg_temp.comprobar(not exists(select 1 from crm.leads where id='d0000000-0000-4000-8000-000000000003'),'rechazo no deja lead huérfano');
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000001','CE','009-900001');
  raise exception 'FAIL: CE con separadores';
exception when sqlstate '22023' then raise notice 'PASS: validador no elimina caracteres inválidos'; end $$;
reset role;
select pg_temp.comprobar(not has_function_privilege('anon','crm.documento_lead_fn(uuid)','execute'),'anon no lee documentos');
select pg_temp.comprobar(not has_function_privilege('anon','crm.crear_lead_documento_fn(jsonb,text,text)','execute'),'anon no crea leads');
select pg_temp.comprobar(not has_function_privilege('authenticated','private.validar_documento_lead(text,text)','execute'),'helper privado cerrado');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select crm.crear_lead_documento_fn(
  '{"id":"d0000000-0000-4000-8000-000000000004","nombre_completo":"DOCUMENTO CORREGIBLE","telefono":"988770004","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
  'DNI','88009904');
select crm.preparar_persona_lead_inversion_fn('d0000000-0000-4000-8000-000000000004','DNI','88009904','DOCUMENTO CORREGIBLE');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select pg_temp.comprobar(crm.editar_lead_documento_fn('d0000000-0000-4000-8000-000000000004',
  '{"distrito":"LIMA"}','CE','009900004',
  (crm.documento_lead_fn('d0000000-0000-4000-8000-000000000004')->>'identificador_id')::uuid,
  'Tipo incorrecto en el alta')->>'numero'='009900004','Administración corrige DNI reconocido a CE');
select pg_temp.comprobar((select dni is null and distrito='LIMA' from crm.leads where id='d0000000-0000-4000-8000-000000000004'),'corrección y ficha se guardan juntas');
select pg_temp.comprobar(coalesce(current_setting('crm.op_privilegiada',true),'off')='off'
  and coalesce(current_setting('crm.correccion_documento',true),'off')='off','corrección no deja privilegios activos');
do $$ begin
  perform crm.editar_lead_documento_fn('d0000000-0000-4000-8000-000000000004',
    '{"telefono":"+51988770001"}','CE','009900014',
    (crm.documento_lead_fn('d0000000-0000-4000-8000-000000000004')->>'identificador_id')::uuid,
    'Prueba de reversión atómica');
  raise exception 'FAIL: corrección parcialmente guardada';
exception when sqlstate 'P0481' then raise notice 'PASS: fallo de ficha revierte corrección administrativa'; end $$;
select pg_temp.comprobar(crm.documento_lead_fn('d0000000-0000-4000-8000-000000000004')->>'numero'='009900004','corrección fallida conserva identidad previa');
reset role;
select pg_temp.comprobar((select count(*)=1 from crm.inversionista_operaciones
  where lead_id='d0000000-0000-4000-8000-000000000004' and tipo='correccion'
  and por='b0000000-0000-4000-8000-000000000003' and motivo='Tipo incorrecto en el alta'),
  'corrección registra motivo y actor una sola vez');
select pg_temp.comprobar(not exists(select 1 from crm.inversionista_identificadores where documento_normalizado='009900014'),
  'corrección fallida no deja identificador');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select pg_temp.comprobar(crm.preparar_persona_lead_inversion_fn('d0000000-0000-4000-8000-000000000004',
  'CE','009900004','DOCUMENTO CORREGIBLE')->>'lead_id'='d0000000-0000-4000-8000-000000000004',
  'caso del incidente: después de corregir a CE la conversión continúa');
select crm.crear_lead_documento_fn(
  '{"id":"d0000000-0000-4000-8000-000000000005","nombre_completo":"LEAD SIN DOCUMENTO","telefono":"988770005","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
  'DNI',null);
do $$ begin
  perform crm.editar_lead_documento_fn('d0000000-0000-4000-8000-000000000005',
    '{"telefono":"+51988770001"}','CE','009900005');
  raise exception 'FAIL: edición parcial con teléfono duplicado';
exception when unique_violation or sqlstate 'P0481' then raise notice 'PASS: edición inválida revierte también el documento'; end $$;
select pg_temp.comprobar((select inversionista_id is null and telefono='+51988770005' from crm.leads where id='d0000000-0000-4000-8000-000000000005'),'edición fallida conserva lead original');
reset role;
select pg_temp.comprobar(not exists(select 1 from crm.inversionista_identificadores where documento_normalizado='009900005'),'edición fallida no deja identidad huérfana');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select pg_temp.comprobar(crm.crear_lead_documento_fn(
  '{"id":"d0000000-0000-4000-8000-000000000006","nombre_completo":"CONTACTO DUPLICADO","telefono":"988770001","origen":"referido","monto_estimado":5000,"moneda":"PEN"}',
  'CE','009900006')->>'estado'<>'creado','alta con teléfono ocupado rechazada');
reset role;
select pg_temp.comprobar(not exists(select 1 from crm.inversionista_identificadores where documento_normalizado='009900006'),'alta rechazada no deja identidad huérfana');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
select crm.crear_lead_documento_fn(
  '{"id":"d0000000-0000-4000-8000-000000000007","nombre_completo":"LEAD DE SUPERVISOR","telefono":"988770007","origen":"oficina","monto_estimado":5000,"moneda":"PEN"}',
  'PASAPORTE','AA990007');
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$ begin
  perform crm.documento_lead_fn('d0000000-0000-4000-8000-000000000007');
  raise exception 'FAIL: lectura fuera de ámbito';
exception when sqlstate 'P0002' then raise notice 'PASS: lectura fuera de ámbito denegada'; end $$;
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000007','CE','009900099');
  raise exception 'FAIL: escritura fuera de ámbito';
exception when sqlstate 'P0002' then raise notice 'PASS: escritura fuera de ámbito denegada'; end $$;
reset role;
-- Veto de contacto: no se puede añadir identidad para continuar la gestión.
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select crm.marcar_no_contactar('d0000000-0000-4000-8000-000000000005','Veto sintético de prueba');
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000005','CE','009900005');
  raise exception 'FAIL: identidad sobre lead vetado';
exception when sqlstate 'P0429' then raise notice 'PASS: no-contactar respetado'; end $$;
do $$ begin
  perform crm.fijar_dni_lead_fn('d0000000-0000-4000-8000-000000000001','88009901');
  raise exception 'FAIL: ruta DNI altera identidad CE';
exception when sqlstate 'P0409' then raise notice 'PASS: ruta DNI antigua tampoco cambia CE reconocido'; end $$;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  perform crm.documento_lead_fn('d0000000-0000-4000-8000-000000000001');
  raise exception 'FAIL: uid nulo lee documento';
exception when insufficient_privilege then raise notice 'PASS: uid nulo denegado'; end $$;
reset role;
-- Historia de fusión: el vínculo existe solo por puente. La puerta histórica
-- no corrige ese lead, así que la nueva debe abortar y conservar la identidad.
select set_config('crm.op_privilegiada','on',true);
update crm.leads set inversionista_id=null where id='d0000000-0000-4000-8000-000000000002';
select set_config('crm.op_privilegiada','off',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select pg_temp.comprobar(crm.documento_lead_fn('d0000000-0000-4000-8000-000000000002')->>'numero'='AB990002',
  'lectura recupera identidad por puente');
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000002','CE','009900022',
    (crm.documento_lead_fn('d0000000-0000-4000-8000-000000000002')->>'identificador_id')::uuid,'Prueba de puente histórico');
  raise exception 'FAIL: corrección de puente confirma un lead incoherente';
exception when sqlstate 'P0409' then
  if sqlerrm not like '%conciliar los leads%' then raise; end if;
  raise notice 'PASS: puente requiere conciliación explícita y revierte corrección'; end $$;
select pg_temp.comprobar(crm.documento_lead_fn('d0000000-0000-4000-8000-000000000002')->>'numero'='AB990002',
  'rechazo del puente conserva documento original');
reset role;
-- La hipótesis de dos leads directos está cerrada por el índice único vivo.
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
select crm.crear_lead_si_disponible('SEGUNDO LEAD SINTETICO','988770089','referido',5000,'PEN',p_id=>'d0000000-0000-4000-8000-000000000089');
reset role;
select set_config('crm.op_privilegiada','on',true);
do $$ begin
  update crm.leads set inversionista_id=(select inversionista_id from crm.leads where id='d0000000-0000-4000-8000-000000000001') where id='d0000000-0000-4000-8000-000000000089';
  raise exception 'FAIL: segundo vínculo directo aceptado';
exception when unique_violation then raise notice 'PASS: índice único impide dos leads directos de una persona'; end $$;
select set_config('crm.op_privilegiada','off',true);
select pg_temp.comprobar(exists(select 1 from public.audit_log
  where tabla='crm.leads' and operacion='UPDATE' and fila_id='d0000000-0000-4000-8000-000000000001'
  and usuario_id='b0000000-0000-4000-8000-000000000002' and data_despues->>'inversionista_id' is not null),
  'vincular documento conserva auditoría por actor incluso con GUC privilegiada');
set local role authenticated;
select crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000089','DNI','88009989');
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000089','CE','');
  raise exception 'FAIL: CE vacío borra DNI legado';
exception when sqlstate '22023' then raise notice 'PASS: CE vacío no borra DNI legado'; end $$;
select pg_temp.comprobar(crm.documento_lead_fn('d0000000-0000-4000-8000-000000000089')->>'numero'='88009989',
  'rechazo de CE vacío conserva DNI anterior');
reset role;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
-- Dos documentos vigentes: nunca confirmar una corrección que no será el
-- documento primario que lee la conversión.
insert into crm.inversionista_identificadores
  (inversionista_id,tipo_documento,documento_normalizado,documento_original,estado,verificado,fuente)
select inversionista_id,'DNI','88009944','88009944','vigente',true,'prueba_local'
  from crm.leads where id='d0000000-0000-4000-8000-000000000004';
set local role authenticated;
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000004','PASAPORTE','AB990044',
    (crm.documento_lead_fn('d0000000-0000-4000-8000-000000000004')->>'identificador_id')::uuid,'Prueba de varios documentos');
  raise exception 'FAIL: corrección confirma otro documento primario';
exception when sqlstate 'P0409' then
  if sqlerrm not like '%varios documentos%' then raise; end if;
  raise notice 'PASS: varios documentos requieren conciliación explícita'; end $$;
select pg_temp.comprobar(crm.documento_lead_fn('d0000000-0000-4000-8000-000000000004')->>'numero'='88009944',
  'rechazo de documento primario revierte operación completa');
reset role;
update crm.equipo set activo=false where perfil_id='b0000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
do $$ begin
  perform crm.documento_lead_fn('d0000000-0000-4000-8000-000000000001');
  raise exception 'FAIL: baja lee documento';
exception when insufficient_privilege then raise notice 'PASS: miembro inactivo no lee documentos'; end $$;
do $$ begin
  perform crm.fijar_documento_lead_fn('d0000000-0000-4000-8000-000000000001','CE','009900001');
  raise exception 'FAIL: baja escribe documento';
exception when insufficient_privilege then raise notice 'PASS: miembro inactivo no edita documentos'; end $$;
reset role;
rollback;
select 'PASS: documentos del lead / banco local, datos revertidos';

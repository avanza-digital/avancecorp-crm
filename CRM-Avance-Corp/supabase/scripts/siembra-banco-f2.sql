-- SIEMBRA para el ensayo F2 — SOLO en banco. Datos minimos que cubren TODAS las
-- clases y las excepciones del censo. Usa la valvula op_privilegiada para poder
-- crear leads convertidos y con perfil (las guardas vivas lo exigen).
begin;
select set_config('crm.op_privilegiada','on', true);

-- auth.users para los perfiles (perfiles.id -> auth.users.id en el banco).
insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('a0000000-0000-0000-0000-000000000001'),('a0000000-0000-0000-0000-000000000002'),('a0000000-0000-0000-0000-000000000003'),
  ('e0000000-0000-0000-0000-000000000001'),('e0000000-0000-0000-0000-000000000002'),
  ('e0000000-0000-0000-0000-000000000003'),('e0000000-0000-0000-0000-000000000004'),
  ('b0000000-0000-0000-0000-000000000001');

-- Equipo: un asesor/vendedor activo (perfil + fila de equipo).
insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values
  ('11111111-1111-1111-1111-111111111111','ASESOR UNO','comercial','DNI','10000001');
insert into crm.equipo (perfil_id, rol_crm, activo, creado_por)
  values ('11111111-1111-1111-1111-111111111111','supervisor', true, '11111111-1111-1111-1111-111111111111');

-- Clientes CLASE A (doc valido y unico): DNI, CE, PASAPORTE.
insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni, asesor_perfil_id) values
  ('a0000000-0000-0000-0000-000000000001','CLIENTE DNI','cliente','DNI','20000001','11111111-1111-1111-1111-111111111111'),
  ('a0000000-0000-0000-0000-000000000002','CLIENTE CE','cliente','CE','200000002','11111111-1111-1111-1111-111111111111'),
  ('a0000000-0000-0000-0000-000000000003','CLIENTE PAS','cliente','PASAPORTE','PAS12345','11111111-1111-1111-1111-111111111111');

-- Cliente CLASE E: sin documento (perfil de prueba).
insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values
  ('e0000000-0000-0000-0000-000000000001','SIN DOC','cliente','DNI', null);
-- Cliente CLASE E: documento invalido.
insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values
  ('e0000000-0000-0000-0000-000000000002','DOC INVALIDO','cliente','DNI','123');
-- Cliente CLASE E: documento COMPARTIDO con otro rol (cross-rol). Cliente + analista, mismo DNI.
insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values
  ('e0000000-0000-0000-0000-000000000003','CROSS ROL CLIENTE','cliente','DNI','30000003'),
  ('e0000000-0000-0000-0000-000000000004','CROSS ROL ANALISTA','analista','DNI','30000003');

-- Cierre CLASE B (coop qorilazo, persona NUEVA por documento). Necesita un lead.
insert into public.perfiles (id, nombre_completo, rol, tipo_documento, dni) values
  ('b0000000-0000-0000-0000-000000000001','LEAD DUENO','cliente','DNI','40000001'); -- placeholder para creado_por; no cliente real de A? es rol cliente pero su doc unico -> tambien seria A. Para evitar, lo dejamos fuera del cierre.
insert into crm.leads (id, nombre_completo, telefono, monto_estimado, origen, etapa, creado_por, vendedor_id) values
  ('1ead0000-0000-0000-0000-00000000000b','LEAD DEL CIERRE','999000001', 10000, 'landing', 'nuevo', '11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111');
insert into crm.cierres_externos (id, lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion, vendedor_id, creado_por) values
  ('c1e50000-0000-0000-0000-00000000000b','1ead0000-0000-0000-0000-00000000000b','qorilazo', 5000, 'PEN', 'DNI','50000001','PERSONA COOP','TX-0001','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111');
-- el lead del cierre pasa a convertido (clase C via cierre).
update crm.leads set etapa='convertido' where id='1ead0000-0000-0000-0000-00000000000b';

-- Cierre DEMO (debe EXCLUIRSE por id).
insert into crm.leads (id, nombre_completo, telefono, monto_estimado, origen, etapa, creado_por, vendedor_id) values
  ('1ead0000-0000-0000-0000-0000000000de','LEAD DEMO','999000009', 100000, 'landing', 'nuevo', '11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111');
insert into crm.cierres_externos (id, lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion, vendedor_id, creado_por, anulado_en, anulado_por, motivo_anulacion) values
  ('a112aead-184a-4979-9041-943978fadae4','1ead0000-0000-0000-0000-0000000000de','qorilazo', 100000, 'PEN', 'DNI','99999999','DEMO PERSONA','TX-DEMO','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111', now(), '11111111-1111-1111-1111-111111111111','DEMO');
update crm.leads set etapa='convertido' where id='1ead0000-0000-0000-0000-0000000000de';

-- Lead CLASE C: convertido con perfil (cliente DNI). DNI del lead = el del perfil.
insert into crm.leads (id, nombre_completo, telefono, monto_estimado, origen, etapa, perfil_id, dni, creado_por, vendedor_id) values
  ('1ead0000-0000-0000-0000-0000000000c1','LEAD CONVERTIDO A','999000002', 20000, 'landing', 'convertido','a0000000-0000-0000-0000-000000000001','20000001','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111');
-- Lead CLASE C (2o lead de la MISMA persona) -> debe ir a historico, no romper la unique.
insert into crm.leads (id, nombre_completo, telefono, monto_estimado, origen, etapa, perfil_id, dni, creado_por, vendedor_id) values
  ('1ead0000-0000-0000-0000-0000000000c2','LEAD CONVERTIDO A BIS','999000003', 20000, 'landing', 'convertido','a0000000-0000-0000-0000-000000000001','20000001','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111');
-- Lead CLASE E: convertido cuyo DNI DISCREPA del de su perfil (Katherine).
insert into crm.leads (id, nombre_completo, telefono, monto_estimado, origen, etapa, perfil_id, dni, creado_por, vendedor_id) values
  ('1ead0000-0000-0000-0000-0000000000e1','LEAD DISCREPA','999000004', 20000, 'landing', 'convertido','a0000000-0000-0000-0000-000000000002','88888888','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111');

commit;
-- Nota: el cliente b0000000... (DNI 40000001) NO tiene lead ni cierre; sera clase A normal.
--       Esperado tras F2: A = 4 (los 3 + el dueno-placeholder), B = 1, C = 2 (lead cierre + lead A;
--       el 2o lead A va a historico), E = 5 (sin doc, invalido, cross-rol cliente, cross-rol... no:
--       el analista no es cliente y no se procesa en A; discrepa). Se valida en el ensayo.

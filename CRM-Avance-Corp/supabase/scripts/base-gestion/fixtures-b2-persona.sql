-- Fixtures B2 «persona real» (idempotentes). Pedidos por auditor-rls (P2) y Codex (P1/P2) para ejercitar la regla
-- «todos los leads de la persona en tu equipo» con identidad resuelta y el caso NULL (lead parqueado en otra bandeja).
--   P (DNI 70000104): LA_VETO (A, descartado, enlace canónico) + LD (C, equipo 2, descartado, suelto) + LE (parqueado en S2:
--      vendedor NULL, asignado_supervisor_id S2, nuevo, suelto). Vetada. → S1 42501 «pídelo a Gerencia»; G ok (3 leads).
--   Q (DNI 70000106): LF (A, descartado, canónico) + LG (parqueado en S1, nuevo, suelto). Vetada. → S1 ok (2 leads).
--   R (DNI 70000107): LH (A, descartado, canónico) + LI (parqueado en S2, nuevo, suelto). Vetada. → S1 42501 (caso NULL puro).
-- Todo bajo crm.op_privilegiada=on (única vía para escribir enlaces y veto fuera de las puertas).
begin;
set local search_path = '';
select set_config('crm.op_privilegiada','on',true);
-- Leads nuevos (los descartados nacen en «nuevo» y se descartan después).
insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, vendedor_id, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo) values
  ('b0000000-0000-4000-8000-0000000000f1','BANCO B2 LEAD F (Q, A)','988770106','70000106','otro','nuevo','b0000000-0000-4000-8000-000000000002',null,1000,'PEN','b0000000-0000-4000-8000-000000000002',true),
  ('b0000000-0000-4000-8000-0000000000f3','BANCO B2 LEAD H (R, A)','988770107','70000107','otro','nuevo','b0000000-0000-4000-8000-000000000002',null,1000,'PEN','b0000000-0000-4000-8000-000000000002',true)
on conflict (id) do nothing;
update crm.leads set etapa='descartado', motivo_descarte='no_responde'
 where id in ('b0000000-0000-4000-8000-0000000000f1','b0000000-0000-4000-8000-0000000000f3') and etapa='nuevo';
-- Parqueados (vendedor NULL) con el mismo DNI de su persona: solo pueden nacer con el canónico ya descartado (DNI vivo único).
insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, vendedor_id, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo) values
  ('b0000000-0000-4000-8000-0000000000e5','BANCO B2 LEAD E (P, parqueado S2)','988770115','70000104','otro','nuevo',null,'b0000000-0000-4000-8000-000000000011',1000,'PEN','b0000000-0000-4000-8000-000000000011',true),
  ('b0000000-0000-4000-8000-0000000000f2','BANCO B2 LEAD G (Q, parqueado S1)','988770116','70000106','otro','nuevo',null,'b0000000-0000-4000-8000-000000000001',1000,'PEN','b0000000-0000-4000-8000-000000000001',true),
  ('b0000000-0000-4000-8000-0000000000f4','BANCO B2 LEAD I (R, parqueado S2)','988770117','70000107','otro','nuevo',null,'b0000000-0000-4000-8000-000000000011',1000,'PEN','b0000000-0000-4000-8000-000000000011',true)
on conflict (id) do nothing;
-- Personas e identificadores DESPUÉS de los leads: si existieran antes, la disponibilidad del contacto
-- rechaza el alta («ya_es_cliente» vía identidad).
insert into crm.inversionistas (id, estado, creado_por) values
  ('b0000000-0000-4000-8000-00000000000a','activo','b0000000-0000-4000-8000-000000000003'),
  ('b0000000-0000-4000-8000-00000000000b','activo','b0000000-0000-4000-8000-000000000003'),
  ('b0000000-0000-4000-8000-00000000000c','activo','b0000000-0000-4000-8000-000000000003')
on conflict (id) do nothing;
insert into crm.inversionista_identificadores (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente) values
  ('b0000000-0000-4000-8000-00000000000a','DNI','70000104','70000104','vigente',true,'banco'),
  ('b0000000-0000-4000-8000-00000000000b','DNI','70000106','70000106','vigente',true,'banco'),
  ('b0000000-0000-4000-8000-00000000000c','DNI','70000107','70000107','vigente',true,'banco')
on conflict do nothing;
-- Enlace canónico persona ↔ lead (puente + columna), bajo privilegio.
insert into crm.inversionista_leads (inversionista_id, lead_id, rol) values
  ('b0000000-0000-4000-8000-00000000000a','b0000000-0000-4000-8000-0000000000a2','canonico'),
  ('b0000000-0000-4000-8000-00000000000b','b0000000-0000-4000-8000-0000000000f1','canonico'),
  ('b0000000-0000-4000-8000-00000000000c','b0000000-0000-4000-8000-0000000000f3','canonico')
on conflict do nothing;
update crm.leads set inversionista_id = 'b0000000-0000-4000-8000-00000000000a' where id = 'b0000000-0000-4000-8000-0000000000a2' and inversionista_id is null;
update crm.leads set inversionista_id = 'b0000000-0000-4000-8000-00000000000b' where id = 'b0000000-0000-4000-8000-0000000000f1' and inversionista_id is null;
update crm.leads set inversionista_id = 'b0000000-0000-4000-8000-00000000000c' where id = 'b0000000-0000-4000-8000-0000000000f3' and inversionista_id is null;
-- Veto de las tres personas y de todos sus leads.
update crm.inversionistas set no_contactar = true, no_contactar_en = now(), no_contactar_por = 'b0000000-0000-4000-8000-000000000003'
 where id in ('b0000000-0000-4000-8000-00000000000a','b0000000-0000-4000-8000-00000000000b','b0000000-0000-4000-8000-00000000000c') and not no_contactar;
update crm.leads set no_contactar = true
 where dni in ('70000104','70000106','70000107') and not no_contactar;
select set_config('crm.op_privilegiada','off',true);
do $$ begin
  if (select count(*) from crm.inversionistas where id::text like 'b0000000-0000-4000-8000-00000000000%' and no_contactar) <> 3 then raise exception 'fixtures persona: faltan personas vetadas'; end if;
  if (select count(*) from crm.leads where dni in ('70000104','70000106','70000107') and no_contactar) <> 7 then raise exception 'fixtures persona: esperaba 7 leads vetados, hay %', (select count(*) from crm.leads where dni in ('70000104','70000106','70000107') and no_contactar); end if;
  if (select count(*) from private.leads_de_persona_veto('b0000000-0000-4000-8000-00000000000a')) <> 3 then raise exception 'fixtures persona: P no reúne 3 leads (enlace + 2 sueltos), reúne %', (select count(*) from private.leads_de_persona_veto('b0000000-0000-4000-8000-00000000000a')); end if;
  raise notice 'fixtures B2 persona OK: P(3 leads: A, C, parqueado S2) · Q(2: A, parqueado S1) · R(2: A, parqueado S2), todo vetado';
end $$;
commit;

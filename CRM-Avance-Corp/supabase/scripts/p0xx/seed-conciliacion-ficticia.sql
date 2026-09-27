-- SOLO rama, dentro de una transaccion que termina en ROLLBACK.
-- Reproduce las tres clases de conflicto sin copiar personas ni cuentas reales.
set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000003';
create temporary table p0xx_casos_fixture (
  cliente_id uuid primary key,cuenta_id uuid,contrato_id uuid,
  motivo text,numero text,cci text,dni text,banco_perfil text,banco_crm text
) on commit drop;
insert into p0xx_casos_fixture values
 ('c1000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001','formato','TEST6087','00200000000000000031',
  '00000031','BBVA','BBVA'),
 ('c1000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000002',
  'd1000000-0000-4000-8000-000000000002','titular','TEST0033','00200000000000000032',
  '00000032','Interbank','Interbank'),
 ('c1000000-0000-4000-8000-000000000003','e1000000-0000-4000-8000-000000000003',
  'd1000000-0000-4000-8000-000000000003','banco','TEST0071','00200000000000000033',
  '00000033','Interbank','BCP');

insert into auth.users (
 id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 created_at,updated_at,confirmation_token,recovery_token,
 email_change_token_new,email_change,raw_app_meta_data,raw_user_meta_data)
select cliente_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'p0xx.conciliacion.'||motivo||'@example.invalid','',now(),now(),now(),
 '','','','','{"provider":"email"}'::jsonb,'{}'::jsonb
from p0xx_casos_fixture;

-- Exclusivamente preparacion de un estado LEGADO ficticio; se restaura el
-- trigger en esta misma transaccion y al final se revierte toda la semilla.
alter table public.perfiles disable trigger trg_perfiles_banca_solo_lectura;
insert into public.perfiles
 (id,nombre_completo,correo,rol,tipo_documento,dni,activo,asesor_perfil_id,creado_por,
  banco,tipo_cuenta,numero_cuenta,cci,titular_distinto,beneficiario_nombre,beneficiario_dni)
select cliente_id,'CONCILIACION FICTICIA '||upper(motivo),
 'p0xx.conciliacion.'||motivo||'@example.invalid','cliente','DNI',dni,true,
 'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000003',
 banco_perfil,'ahorros',numero,cci,motivo='titular',
 case when motivo='titular' then 'BENEFICIARIO FICTICIO' end,
 case when motivo='titular' then '00000999' end
from p0xx_casos_fixture;
alter table public.perfiles enable trigger trg_perfiles_banca_solo_lectura;

insert into crm.cuentas_bancarias
 (id,cliente_id,moneda,banco,tipo_cuenta,numero_cuenta,cci,titular_distinto,
  activa,origen,creado_por)
select cuenta_id,cliente_id,'PEN',banco_crm,'ahorros',
 case when motivo='formato' then 'TEST-6087' else numero end,cci,false,true,
 'contrato','b0000000-0000-4000-8000-000000000003'
from p0xx_casos_fixture;

insert into public.contratos
 (id,numero_contrato,cliente_id,capital,moneda,modalidad,tipo_interes,
  fecha_inicio,fecha_vencimiento,categoria,tasa_anual,creado_por)
select contrato_id,'P0XX-CIERRE-'||upper(motivo),cliente_id,1000,'PEN','mensual','simple',
 (pg_catalog.now() at time zone 'America/Lima')::date,
 ((pg_catalog.now() at time zone 'America/Lima')::date + interval '12 months')::date,
 'nuevo',(private.resolver_tasa(cliente_id,'nuevo',null::uuid,
   pg_catalog.statement_timestamp())->>'tasa_base')::numeric,
 'b0000000-0000-4000-8000-000000000003'
from p0xx_casos_fixture;
insert into crm.contrato_cuentas_pago (contrato_id,cuenta_bancaria_id,creado_por)
select contrato_id,cuenta_id,'b0000000-0000-4000-8000-000000000003'
from p0xx_casos_fixture;

create temporary table p0xx_casos_config on commit drop as
select f.motivo,pg_catalog.jsonb_build_object(
 'cliente_id',f.cliente_id,'motivo',f.motivo,
 'huella_perfil',pg_catalog.md5(private.validar_cuenta_bancaria(
  pg_catalog.to_jsonb(p))::text),
 'huella_cuenta',pg_catalog.md5(private.validar_cuenta_bancaria(
  pg_catalog.to_jsonb(cb))::text)) as caso
from p0xx_casos_fixture f join public.perfiles p on p.id=f.cliente_id
join crm.cuentas_bancarias cb on cb.id=f.cuenta_id;
select pg_catalog.set_config('p0xx.casos_versionado',
 (select pg_catalog.jsonb_agg(caso)::text from p0xx_casos_config where motivo<>'banco'),true);
select pg_catalog.set_config('p0xx.caso_banco',
 (select caso::text from p0xx_casos_config where motivo='banco'),true);

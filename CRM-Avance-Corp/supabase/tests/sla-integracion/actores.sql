-- Identidades exclusivamente sinteticas. Se ejecuta como migrador sin auth.uid,
-- con los guards/auditores reales instalados; no se apagan triggers.
begin;
insert into auth.users(id,email,aud,role,created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
select ('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
  'sla-integral-'||i||'@example.invalid','authenticated','authenticated',clock_timestamp(),clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb
from generate_series(1001,1007) i;
insert into public.perfiles(id,nombre_completo,rol,activo)
values
('00000000-0000-0000-0000-000000001001','Analista SLA A','analista',true),
('00000000-0000-0000-0000-000000001002','Analista SLA B','analista',true),
('00000000-0000-0000-0000-000000001003','Supervisor SLA','analista',true),
('00000000-0000-0000-0000-000000001004','Gerencia SLA','superadmin',true),
('00000000-0000-0000-0000-000000001005','Directorio SLA','directorio',true),
('00000000-0000-0000-0000-000000001006','Sin acceso SLA','cliente',true),
('00000000-0000-0000-0000-000000001007','Supervisor SLA B','analista',true);
insert into crm.equipo(perfil_id,rol_crm) values
('00000000-0000-0000-0000-000000001004','gerencia'),
('00000000-0000-0000-0000-000000001005','directorio');
insert into crm.equipo(perfil_id,rol_crm,supervisor_id) values
('00000000-0000-0000-0000-000000001003','supervisor','00000000-0000-0000-0000-000000001004'),
('00000000-0000-0000-0000-000000001007','supervisor','00000000-0000-0000-0000-000000001004');
insert into crm.equipo(perfil_id,rol_crm,supervisor_id) values
('00000000-0000-0000-0000-000000001001','vendedor','00000000-0000-0000-0000-000000001003'),
('00000000-0000-0000-0000-000000001002','vendedor','00000000-0000-0000-0000-000000001007');
commit;

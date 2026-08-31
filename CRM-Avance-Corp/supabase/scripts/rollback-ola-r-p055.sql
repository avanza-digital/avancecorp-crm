-- MARCHA ATRAS de P-055 OLA R (las doce actas mudas).
-- Devuelve las 12 a su estado anterior EXACTO: statements a NULL, y el nombre
-- a NULL solo en las 9 que no lo tenian (las 3 F1.x del 28/08 ya venian con
-- nombre). Anti-pisado: solo revierte si cada cuerpo es EXACTAMENTE el que la
-- Ola R escribio (jamas borra un cuerpo ajeno). La fila propia de la version
-- 20260831055000 se retira A MANO tras este script (convencion de la casa).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create temp table _olar_rb (version text primary key, md5_cuerpo text, n_sentencias int) on commit drop;
insert into _olar_rb values
  ('20260819162752', '3756aa8ff82fa1ec63f283f8ee62c08d', 17),
  ('20260819211815', '8ab82c082e7884d611a11087e6b3241e', 13),
  ('20260820190500', '0a9202c300cba5655d21ec197c8b0744', 17),
  ('20260826151907', '64260c58878bd114c8cf0feb27810f80', 10),
  ('20260826154500', '7e0c2ffa4d41d5ca7fd045777732fe4c', 9),
  ('20260826173523', 'e0d4c7e255412e5bce4072311f39b387', 11),
  ('20260826174500', '5ce2631bffcc2120e5e2a3d091b14ac2', 10),
  ('20260826182000', '8735ab49a697468b9a80124466f568de', 7),
  ('20260826182500', '538438b7dcf1033a96e3fbc46cc60162', 10),
  ('20260828190000', '3121d69c9f99b3a214982eb8b3a670dc', 7),
  ('20260828190500', 'aab6762606cf487376f0ea77058dd524', 19),
  ('20260828191000', '2b48a5eee28654b3f93c7781c663a88c', 6);

do $$
declare v_mal text;
begin
  select r.version into v_mal from _olar_rb r
    left join supabase_migrations.schema_migrations m on m.version = r.version
   where m.statements is null
      or md5(array_to_string(m.statements, E'\n')) is distinct from r.md5_cuerpo
      or coalesce(array_length(m.statements, 1), 0) is distinct from r.n_sentencias
   limit 1;
  if v_mal is not null then
    raise exception 'rollback OLA R: la version % NO tiene el cuerpo que esta ola escribio - NO se pisa nada', v_mal;
  end if;
end $$;

update supabase_migrations.schema_migrations
   set statements = null
 where version in ('20260819162752', '20260819211815', '20260820190500', '20260826151907', '20260826154500', '20260826173523', '20260826174500', '20260826182000', '20260826182500', '20260828190000', '20260828190500', '20260828191000');

-- (auditor 30/08 P2-2): el name vuelve a NULL SOLO si es exactamente el que
-- esta ola escribio - un name ajeno pre-existente se conserva.
update supabase_migrations.schema_migrations m
   set name = null
  from (values
  ('20260819162752', '20260819162752_crm_domicilio_legal_faltante'),
  ('20260819211815', '20260819211815_crm_domicilio_una_sola_puerta'),
  ('20260820190500', '20260820190500_crm_documento_regimen_por_fecha_de_firma'),
  ('20260826151907', '20260826151907_crm_cartera_pagina_telefono_alternativo'),
  ('20260826154500', '20260826154500_crm_leads_telefono_alternativo_fijos_e_internacional'),
  ('20260826173523', '20260826173523_crm_leads_telefono_alternativo_crudo'),
  ('20260826174500', '20260826174500_crm_cartera_pagina_telefono_alternativo_crudo'),
  ('20260826182000', '20260826182000_crm_canonizar_contacto'),
  ('20260826182500', '20260826182500_crm_crear_lead_telefono_alternativo')
  ) as e(version, nombre)
 where m.version = e.version and m.name = e.nombre;

do $$
begin
  if (select count(*) from supabase_migrations.schema_migrations where statements is null) <> 12 then
    raise exception 'rollback OLA R: no quedaron exactamente 12 mudas';
  end if;
  if (select count(*) from supabase_migrations.schema_migrations
       where version in ('20260819162752', '20260819211815', '20260820190500', '20260826151907', '20260826154500', '20260826173523', '20260826174500', '20260826182000', '20260826182500') and name is not null) <> 0 then
    raise exception 'rollback OLA R: algun nombre no volvio a NULL';
  end if;
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
  if private.assert_f7_piezas_cerradas() not like 'OK:%' then
    raise exception 'rollback OLA R: el vigilante F7 no da OK';
  end if;
end $$;

commit;

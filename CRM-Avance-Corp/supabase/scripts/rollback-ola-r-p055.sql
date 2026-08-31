-- MARCHA ATRAS de P-055 OLA R v3 (las doce actas mudas).
-- Devuelve las 12 a su estado anterior EXACTO. Anti-pisado POR ELEMENTO
-- (huella que codifica fronteras) + conteo, con las filas BLOQUEADAS
-- (FOR UPDATE: Codex v2 cazo el TOCTOU entre chequear y anular). El name
-- vuelve a NULL SOLO si es exactamente el que esta ola escribio. La fila
-- propia de la 20260831055000 se retira A MANO tras este script.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create temp table _olar_rb (version text primary key, huella_elems text, n_sentencias int) on commit drop;
insert into _olar_rb values
  ('20260819162752', '399f72b907f4bab63ad4fb124c4d4755', 17),
  ('20260819211815', '14e8587e631e35d318b580d23f0342f5', 13),
  ('20260820190500', '6e4ae5f02480d3a0fc913b38cdcfa578', 17),
  ('20260826151907', 'f6b4b452868510ad433d3fd4418b4874', 10),
  ('20260826154500', '066eaf9312823cdc860545ca3764c5f7', 9),
  ('20260826173523', '8a3bb03f7da1d3a6f9181fd61bedd8c9', 11),
  ('20260826174500', 'b4444752f25e85f5d54a830b9f24fe9e', 10),
  ('20260826182000', 'e1d79c85d595e72f61ddfaacb081c87b', 7),
  ('20260826182500', '1f71c71f2b2db9dae6d23a6080be838f', 10),
  ('20260828190000', '018116c2ff04537be42e034abba7de2a', 7),
  ('20260828190500', 'a109153ca42c6de632c8ea23b19bde1f', 19),
  ('20260828191000', '3390c367bf9b573b525c508ad21bd576', 6);

do $$
declare v_mal text;
begin
  -- BLOQUEO + chequeo en el mismo paso: nadie puede mover las filas entre
  -- este candado y los UPDATE de abajo (misma transaccion, filas con lock).
  perform 1 from supabase_migrations.schema_migrations
   where version in ('20260819162752', '20260819211815', '20260820190500', '20260826151907', '20260826154500', '20260826173523', '20260826174500', '20260826182000', '20260826182500', '20260828190000', '20260828190500', '20260828191000') for update;

  select r.version into v_mal from _olar_rb r
    left join supabase_migrations.schema_migrations m on m.version = r.version
   where m.statements is null
      or (select md5(string_agg(md5(u.s), '|' order by u.ord))
           from unnest(m.statements) with ordinality as u(s, ord)) is distinct from r.huella_elems
      or coalesce(array_length(m.statements, 1), 0) is distinct from r.n_sentencias
   limit 1;
  if v_mal is not null then
    raise exception 'rollback OLA R: la version % NO tiene el cuerpo que esta ola escribio - NO se pisa nada', v_mal;
  end if;
end $$;

update supabase_migrations.schema_migrations
   set statements = null
 where version in ('20260819162752', '20260819211815', '20260820190500', '20260826151907', '20260826154500', '20260826173523', '20260826174500', '20260826182000', '20260826182500', '20260828190000', '20260828190500', '20260828191000');

-- el name vuelve a NULL SOLO si es exactamente el que esta ola escribio:
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
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
  if private.assert_f7_piezas_cerradas() not like 'OK:%' then
    raise exception 'rollback OLA R: el vigilante F7 no da OK';
  end if;
end $$;

commit;

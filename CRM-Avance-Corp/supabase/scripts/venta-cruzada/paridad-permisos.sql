-- Venta cruzada · Fase 2: FOTO de conducta de las cuatro reglas de permisos.
-- Se corre ANTES y DESPUÉS de la migración de la Fase 2 y las dos fotos deben ser
-- idénticas línea a línea: la Fase 2 separa la regla por dentro SIN cambiar nada.
-- Para cada actor × persona × lead guarda la respuesta exacta, o el código y el
-- mensaje del error. Todo en una transacción que se deshace (las reglas toman
-- candados, no escriben). Solo en el banco sintético con mundo.sql sembrado.
-- Uso:
--   psql -h 127.0.0.1 -p 53322 -U postgres -d postgres -v ON_ERROR_STOP=1 -At \
--     -f supabase/scripts/venta-cruzada/paridad-permisos.sql > foto-antes.txt
begin;

do $guarda$ begin
  if (select count(*) from crm.leads) > 200 or (select count(*) from public.perfiles where rol = 'cliente') > 50 then
    raise exception 'La foto de paridad solo corre en el banco sintético';
  end if;
  if not exists (select 1 from public.perfiles where id = 'c0000000-0000-4000-8000-000000000001') then
    raise exception 'Falta el mundo de venta cruzada (mundo.sql)';
  end if;
end $guarda$;

create temporary table p_actores(etiqueta text, id uuid) on commit drop;
insert into p_actores values
  ('G','c0000000-0000-4000-8000-000000000001'),('S1','c0000000-0000-4000-8000-000000000002'),
  ('S2','c0000000-0000-4000-8000-000000000003'),('A','c0000000-0000-4000-8000-000000000004'),
  ('A2','c0000000-0000-4000-8000-000000000005'),('B','c0000000-0000-4000-8000-000000000006'),
  ('C','c0000000-0000-4000-8000-000000000007'),('D','c0000000-0000-4000-8000-000000000008'),
  ('DIR','c0000000-0000-4000-8000-000000000009'),('CO','c0000000-0000-4000-8000-00000000000a'),
  ('ANON',null);

create temporary table p_personas(etiqueta text, id uuid) on commit drop;
insert into p_personas
  select 'X', id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000021'
  union all select 'Q', id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000022'
  union all select 'R', id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000023'
  union all select 'W', id from crm.inversionistas where perfil_id = 'c0000000-0000-4000-8000-000000000025'
  union all select v.e, d.inversionista_id from (values ('Z','70000024'),('V','70000026'),('T','70000027'),
      ('U','70000028'),('Y','70000029')) v(e, doc)
    join crm.inversionista_identificadores d on d.tipo_documento = 'DNI' and d.documento_normalizado = v.doc
  union all select 'INEXISTENTE', '00000000-0000-4000-8000-00000000dead'::uuid
  union all select 'NULA', null::uuid;
do $$ begin
  if (select count(*) from p_personas) <> 11 then raise exception 'PARIDAD: faltan personas del mundo'; end if;
end $$;

create temporary table p_leads(etiqueta text, id uuid) on commit drop;
insert into p_leads values ('SIN', null), ('LEAD_T', 'c0000000-0000-4000-8000-000000000071'),
  ('LEAD_UNO', 'c0000000-0000-4000-8000-000000000081');

create temporary table p_foto(funcion text, actor text, persona text, lead text, salida text) on commit drop;

do $foto$
declare
  a record; p record; l record; f text; r jsonb; s text;
begin
  for a in select * from p_actores loop
    perform set_config('request.jwt.claims',
      case when a.id is null then '' else json_build_object('sub', a.id, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(a.id::text, ''), true);
    for p in select * from p_personas loop
      for f in select unnest(array['autorizada','lectura']) loop
        begin
          r := case f when 'autorizada' then private.inversion_persona_autorizada(p.id)
                      else private.inversion_persona_lectura(p.id) end;
          s := 'OK ' || r::text;
        exception when others then s := 'ERR ' || sqlstate || ' ' || sqlerrm;
        end;
        insert into p_foto values (f, a.etiqueta, p.etiqueta, '-', s);
      end loop;
      for l in select * from p_leads loop
        for f in select unnest(array['contexto','contexto_lectura']) loop
          begin
            r := case f when 'contexto' then private.inversion_persona_contexto(p.id, l.id)
                        else private.inversion_contexto_lectura(p.id, l.id) end;
            s := 'OK ' || r::text;
          exception when others then s := 'ERR ' || sqlstate || ' ' || sqlerrm;
          end;
          insert into p_foto values (f, a.etiqueta, p.etiqueta, l.etiqueta, s);
        end loop;
      end loop;
      -- La variante de un argumento del contexto (usada por la ficha y el comprobante).
      begin
        r := private.inversion_persona_contexto(p.id);
        s := 'OK ' || r::text;
      exception when others then s := 'ERR ' || sqlstate || ' ' || sqlerrm;
      end;
      insert into p_foto values ('contexto_1arg', a.etiqueta, p.etiqueta, '-', s);
    end loop;
  end loop;
end $foto$;

select funcion || ' | ' || actor || ' | ' || persona || ' | ' || lead || ' | ' || salida
  from p_foto order by funcion, actor, persona, lead;
select 'FOTO_PARIDAD: ' || count(*) || ' casos, ' || count(*) filter (where salida like 'OK %') || ' OK, '
  || count(*) filter (where salida like 'ERR %') || ' con error' from p_foto;
rollback;

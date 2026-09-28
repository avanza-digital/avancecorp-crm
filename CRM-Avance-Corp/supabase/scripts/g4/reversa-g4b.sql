-- Reversa de G4b (20260928044910): desenchufa el gate de citas del paraguas y retira
-- las tres piezas nuevas (sólo lectura: no hay datos que restaurar). Si el front ya
-- abre la lista de citas, revertir PRIMERO el front (release anterior) y después esto.
-- Aplicar en un solo mensaje (supabase db query --linked --file …), como la migración.
--
-- supabase_migrations.schema_migrations: esta reversa NO toca la fila de 20260928044910.
-- Si ya se registró, queda y describe una migración revertida: anotar la reversa en
-- MIGRACIONES.md el mismo día. Para volver a instalarla: aplicar la migración (su preflight
-- exige que no exista ninguna pieza de G4b) y correr el registrador, que es idempotente y
-- solo acepta la fila si trae EXACTAMENTE el mismo cuerpo.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
begin
  if md5(pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria()'))) is distinct from '58208b4fba6d2f76554e19e21444fe94'
    or md5(pg_get_functiondef(to_regprocedure('private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid)'))) is distinct from '904d3b0a853a6cf794943217fc957f03'
    or md5(pg_get_functiondef(to_regprocedure('crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)'))) is distinct from 'fd2b0376be5e8c6728e4c33776e1a9e4'
    or md5(pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria_citas()'))) is distinct from '12012959d2e751c43df86b847dcce037' then
    raise exception 'Reversa G4b: el paraguas o las piezas vivas no son las de G4b; no se toca';
  end if;
end $preflight$;
-- Nadie más puede depender de la lista: si otra función o vista la nombra, no se retira.
do $dependientes$
declare v_ajenos text;
begin
  select string_agg(x.objeto, ', ' order by x.objeto) into v_ajenos from (
    select p.oid::regprocedure::text as objeto from pg_proc p
    where p.oid not in (to_regprocedure('private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid)'),
        to_regprocedure('crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)'),
        to_regprocedure('private.assert_gestion_diaria_citas()'))
      and coalesce(p.prosrc, '') ~ '\mgestion_diaria_citas_(core|fn)\M'
    union all
    select v.schemaname || '.' || v.viewname from pg_views v
    where v.definition ~ '\mgestion_diaria_citas_(core|fn)\M'
  ) x;
  if v_ajenos is not null then
    raise exception 'Reversa G4b: otras piezas nombran la lista de citas (%); no se retira', v_ajenos;
  end if;
end $dependientes$;
do $desenchufar$
declare
  v_def text := pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure);
  v_nuevo text := $v$private.assert_gestion_diaria_pendientes()
    || '] [' || private.assert_gestion_diaria_citas() || ']'$v$;
  v_viejo text := $v$private.assert_gestion_diaria_pendientes() || ']'$v$;
begin
  if md5(v_def) is distinct from '58208b4fba6d2f76554e19e21444fe94' then
    raise exception 'Reversa G4b: el paraguas cambió antes de desenchufar';
  end if;
  if (length(v_def) - length(replace(v_def, v_nuevo, ''))) <> length(v_nuevo) then
    raise exception 'Reversa G4b: el enchufe del gate de citas no aparece una sola vez';
  end if;
  execute replace(v_def, v_nuevo, v_viejo);
  if md5(pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure)) is distinct from '5d9dbf0850798fb5cb10942838740d54' then
    raise exception 'Reversa G4b: el paraguas no quedó como antes';
  end if;
end $desenchufar$;
drop function private.assert_gestion_diaria_citas();
drop function crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid);
drop function private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid);
do $postflight$
begin
  if to_regprocedure('private.gestion_diaria_citas_core(date,text,uuid,integer,timestamptz,uuid)') is not null
    or to_regprocedure('crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)') is not null
    or to_regprocedure('private.assert_gestion_diaria_citas()') is not null then
    raise exception 'Reversa G4b: quedó una pieza de G4b';
  end if;
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end $postflight$;
notify pgrst, 'reload schema';
commit;

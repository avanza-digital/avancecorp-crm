-- Reversa de G4b (20260928044910): desenchufa el gate de citas del paraguas y retira
-- las tres piezas nuevas (sólo lectura: no hay datos que restaurar). Si el front ya
-- abre la lista de citas, revertir PRIMERO el front (release anterior) y después esto.
-- Aplicar en un solo mensaje (supabase db query --linked --file …), como la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
begin
  if md5(pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure)) is distinct from '58208b4fba6d2f76554e19e21444fe94' then
    raise exception 'Reversa G4b: el paraguas vivo no es el de G4b; no se toca';
  end if;
end $preflight$;
do $desenchufar$
declare
  v_def text := pg_get_functiondef('private.assert_gestion_diaria()'::regprocedure);
  v_nuevo text := $v$private.assert_gestion_diaria_pendientes()
    || '] [' || private.assert_gestion_diaria_citas() || ']'$v$;
  v_viejo text := $v$private.assert_gestion_diaria_pendientes() || ']'$v$;
begin
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
  perform private.assert_gestion_diaria();
end $postflight$;
notify pgrst, 'reload schema';
commit;

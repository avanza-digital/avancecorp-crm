-- Reversa de la reparacion excepcional; mismos parametros y actor autorizado.
-- Solo vuelve al valor previo si la fila sigue exactamente como se dejo.
lock table public.perfiles in access exclusive mode;
do $revertir_banco$
declare
  v_caso jsonb := pg_catalog.current_setting('p0xx.caso_banco')::jsonb;
  v_perfil public.perfiles%rowtype;
  v_huella text;
begin
  if current_user <> 'postgres' or (select auth.uid()) is null
     or not coalesce((select public.es_admin()),false) then
    raise exception 'P0XX: reversa bancaria no autorizada';
  end if;
  select p.* into strict v_perfil from public.perfiles p
  where p.id=(v_caso->>'cliente_id')::uuid and p.rol='cliente' for update;
  v_huella := pg_catalog.md5(private.validar_cuenta_bancaria(
    pg_catalog.to_jsonb(v_perfil))::text);
  if v_huella = v_caso->>'huella_perfil' then return; end if;
  if v_huella is distinct from v_caso->>'huella_cuenta'
     or v_perfil.banco <> 'BCP'
     or not exists (select 1 from pg_catalog.pg_trigger
       where tgrelid='public.perfiles'::regclass
         and tgname='trg_perfiles_banca_solo_lectura' and tgenabled='O') then
    raise exception 'P0XX: el perfil cambio despues de la reparacion';
  end if;
  execute 'alter table public.perfiles disable trigger trg_perfiles_banca_solo_lectura';
  update public.perfiles set banco='Interbank' where id=v_perfil.id;
  execute 'alter table public.perfiles enable trigger trg_perfiles_banca_solo_lectura';
  if (select pg_catalog.md5(private.validar_cuenta_bancaria(
      pg_catalog.to_jsonb(p))::text) from public.perfiles p where p.id=v_perfil.id)
      is distinct from v_caso->>'huella_perfil' then
    raise exception 'P0XX: la reversa no recupero el estado esperado';
  end if;
end;
$revertir_banco$;

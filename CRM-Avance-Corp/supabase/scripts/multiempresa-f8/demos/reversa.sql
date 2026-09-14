-- Reversa exclusiva de 20260914025926. NO apaga ni desinstala el control F8.
-- Requiere piloto y F4-F7 apagados. Restaura la comprobación anterior (los demos
-- vuelven a bloquear), conservando fuentes, identidades, documentos y auditoría.
-- No modifica supabase_migrations.schema_migrations. Si se usa tras publicar,
-- registrar la compensación y una eventual reinstalación mediante NUEVAS
-- migraciones en el ciclo de rama aprobado. db push no vuelve a ejecutar una
-- versión ya aplicada; no reparar el ledger ni reinstalar automáticamente.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $reversa$
declare r record; v_def text; v_ini integer; v_fin integer; v_ancla text;
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'La reversa requiere READ COMMITTED' using errcode='0A000';
  end if;
  perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
  if exists(select 1 from crm.piloto_f8_control where activo)
    or exists(select 1 from crm.multiempresa_flags where activo and nombre in
      ('inversiones_escritura','ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra')) then
    raise exception 'Apagar F8 y F4-F7 antes de revertir la exclusión demo';
  end if;
  for r in select * from (values
    ('private.trg_piloto_f8_control_validar()','47585a27b991a442bb09b3477be5f224','4fba28d46a46ac4febb7ff81fbd9ac04'),
    ('crm.cartera_inversionistas_estado_fn()','83575873409d51508753fa6405ffcc92','e1da1dd2f01a85bd3cc70a8e28db651b'),
    ('crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean)','e02e89b5a920c8388d77a01c07f13198','350989c4bde7dc99779f59374a455a3a'),
    ('crm.inversionista_ficha_fn(uuid,integer,integer)','8068f1491852e2c64260b359183fd92b','82fe243e7748c392db73f53501ece1e9'),
    ('crm.inversionista_documento_fn(uuid,uuid,uuid)','18db225353031f1afc67a8263c281494','6139b23100b5004a797b69a50eab1989'),
    ('private.postventa_fuente(uuid,uuid,text)','07fb5ace10e00eeedd123306d791d086','f66eb77a61942a617f2f84b17845c85d'),
    ('crm.postventa_vencimientos_fn(text,integer)','d8d3aa51705748888e5dfffc347f98ee','191d24569c9248cb336aa1b475714062'),
    ('private.cartera_f5_personas_visibles()','f32a1baf67372df496388508a724e6bb','2fa1627bf8f36e731756e0502136549f')
  ) v(firma,actual,anterior) loop
    v_def:=pg_get_functiondef(to_regprocedure(r.firma));
    if md5(v_def) is distinct from r.actual then
      raise exception 'La base cambió: no revertir % sin revisar',r.firma;
    end if;
    if r.firma='private.cartera_f5_personas_visibles()' then
      v_ini:=strpos(v_def,'), fuentes as materialized (');
      v_fin:=strpos(v_def,'  autorizadas as materialized (');
      if v_ini=0 or v_fin<=v_ini then raise exception 'Falta el ancla de personas'; end if;
      v_def:=overlay(v_def placing
        E'), fuentes as materialized (select * from private.cartera_f5_fuentes()),\n'
        from v_ini for v_fin-v_ini);
      v_ancla:=$sql$or (not exists(select 1 from con_historia h where h.id=i.id)
          and exists (select 1 from crm.inversionistas h
            join public.perfiles p on p.id=h.perfil_id and p.rol='cliente'
            where private.inversionista_canonica(h.id)=i.id)))$sql$;
      if strpos(v_def,v_ancla)=0 then raise exception 'Falta la excepción de perfiles'; end if;
      v_def:=replace(v_def,v_ancla,$sql$or exists (select 1 from crm.inversionistas h
          join public.perfiles p on p.id=h.perfil_id and p.rol='cliente'
          where private.inversionista_canonica(h.id)=i.id))$sql$);
    else
      v_def:=replace(v_def,'private.cartera_f5_fuentes_reales()','private.cartera_f5_fuentes()');
    end if;
    execute v_def;
    if md5(pg_get_functiondef(to_regprocedure(r.firma)))<>r.anterior then
      raise exception 'La reversa no recuperó la definición exacta de %',r.firma;
    end if;
  end loop;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname !~ '^pg_' and n.nspname<>'information_schema'
        and p.prosrc ~ '(?i)\mcartera_f5_fuentes_reales"?[[:space:]]*\(') then
    raise exception 'Otro consumidor depende de la exclusión; revisar antes de revertir';
  end if;
  if exists(select 1 from pg_depend d where d.refclassid='pg_proc'::regclass
      and d.refobjid='private.cartera_f5_fuentes_reales()'::regprocedure
      and d.classid in ('pg_rewrite'::regclass,'pg_policy'::regclass,'pg_proc'::regclass)) then
    raise exception 'Otra dependencia de catálogo requiere la exclusión; revisar antes de revertir';
  end if;
end;
$reversa$;
drop function private.cartera_f5_fuentes_reales();
commit;

-- Propuesta de reparacion EXCEPCIONAL de un nombre de banco legado.
-- Requiere autorizacion expresa adicional antes de produccion.
-- Dentro de BEGIN, con actor administrador y p0xx.caso_banco JSON:
-- {cliente_id,huella_perfil,huella_cuenta}. No contiene numeros ni CCI.
-- El bloqueo de tabla evita escrituras concurrentes mientras se suspende
-- exclusivamente el trigger bancario; la auditoria sigue activa.
lock table public.perfiles in access exclusive mode;
do $conciliar_banco$
declare
  v_caso jsonb := pg_catalog.current_setting('p0xx.caso_banco')::jsonb;
  v_perfil public.perfiles%rowtype;
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_antes jsonb;
  v_despues jsonb;
  v_campos text[];
  v_auditorias bigint;
begin
  if current_user <> 'postgres' or (select auth.uid()) is null
     or not coalesce((select public.es_admin()), false) then
    raise exception 'P0XX: reparacion bancaria no autorizada';
  end if;
  select p.* into strict v_perfil from public.perfiles p
  where p.id = (v_caso->>'cliente_id')::uuid and p.rol = 'cliente'
    and p.activo is true for update;
  v_antes := private.validar_cuenta_bancaria(pg_catalog.jsonb_build_object(
    'banco',v_perfil.banco,'tipo_cuenta',v_perfil.tipo_cuenta,
    'numero_cuenta',v_perfil.numero_cuenta,'cci',v_perfil.cci,
    'titular_distinto',v_perfil.titular_distinto,
    'beneficiario_nombre',v_perfil.beneficiario_nombre,
    'beneficiario_dni',v_perfil.beneficiario_dni));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    v_perfil.id::text || '|PEN|' || (v_antes->>'cci'),0));
  select cb.* into strict v_cuenta from crm.cuentas_bancarias cb
  where cb.cliente_id = v_perfil.id and cb.moneda = 'PEN'
    and cb.cci = v_antes->>'cci' and cb.activa is true for update;
  v_despues := private.validar_cuenta_bancaria(pg_catalog.jsonb_build_object(
    'banco',v_cuenta.banco,'tipo_cuenta',v_cuenta.tipo_cuenta,
    'numero_cuenta',v_cuenta.numero_cuenta,'cci',v_cuenta.cci,
    'titular_distinto',v_cuenta.titular_distinto,
    'beneficiario_nombre',v_cuenta.beneficiario_nombre,
    'beneficiario_dni',v_cuenta.beneficiario_dni));
  if pg_catalog.md5(v_despues::text) is distinct from v_caso->>'huella_cuenta' then
    raise exception 'P0XX: la cuenta difiere de la revisada';
  end if;
  if v_antes = v_despues then
    perform pg_catalog.set_config('p0xx.resultado_banco','0',true);
    return;
  end if;
  if pg_catalog.md5(v_antes::text) is distinct from v_caso->>'huella_perfil'
     or v_antes - 'banco' <> v_despues - 'banco'
     or v_antes->>'banco' <> 'Interbank'
     or v_despues->>'banco' <> 'BCP'
     or pg_catalog.left(v_despues->>'cci',3) <> '002'
     or not exists (select 1 from pg_catalog.pg_trigger
       where tgrelid = 'public.perfiles'::regclass
         and tgname = 'trg_perfiles_banca_solo_lectura' and tgenabled = 'O') then
    raise exception 'P0XX: la discrepancia no es la reparacion aprobada';
  end if;
  select count(*) into v_auditorias from public.audit_log a
  where a.tabla='perfiles' and a.fila_id=v_perfil.id::text
    and a.operacion='UPDATE' and a.usuario_id=(select auth.uid())
    and a.data_despues->'_audit_campos_bancarios_modificados'='["banco"]'::jsonb;
  execute 'alter table public.perfiles disable trigger trg_perfiles_banca_solo_lectura';
  update public.perfiles set banco = 'BCP' where id = v_perfil.id;
  execute 'alter table public.perfiles enable trigger trg_perfiles_banca_solo_lectura';
  select pg_catalog.array_agg(k order by k) into v_campos
  from pg_catalog.jsonb_each(pg_catalog.to_jsonb(v_perfil)) oldrow(k,v)
  join public.perfiles p on p.id = v_perfil.id
  where oldrow.v is distinct from pg_catalog.to_jsonb(p)->oldrow.k
    and k <> 'actualizado_en';
  if v_campos is distinct from array['banco'] then
    raise exception 'P0XX: la reparacion modifico campos no previstos';
  end if;
  if (select count(*) from public.audit_log a
    where a.tabla = 'perfiles' and a.fila_id = v_perfil.id::text
      and a.usuario_id = (select auth.uid())
      and a.operacion='UPDATE'
      and a.data_despues->'_audit_campos_bancarios_modificados'
        = '["banco"]'::jsonb) <> v_auditorias + 1 then
    raise exception 'P0XX: falta la auditoria de la reparacion';
  end if;
  perform pg_catalog.set_config('p0xx.resultado_banco','1',true);
end;
$conciliar_banco$;

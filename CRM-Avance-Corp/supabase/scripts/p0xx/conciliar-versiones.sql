-- Conciliacion de dos correcciones aprobadas; no escribe banca en perfiles.
-- Ejecutar dentro de BEGIN con request.jwt.claim.sub del administrador y
-- p0xx.casos_versionado = [{cliente_id,motivo,huella_perfil,huella_cuenta}].
-- Los parametros reales quedan fuera del repositorio. Solo postgres.
-- El wrapper oficial aporta validacion, advisory lock, versiones y auditoria.
do $conciliar_versiones$
declare
  v_casos jsonb := pg_catalog.current_setting('p0xx.casos_versionado')::jsonb;
  v_caso jsonb;
  v_perfil public.perfiles%rowtype;
  v_actual crm.cuentas_bancarias%rowtype;
  v_deseada jsonb;
  v_anterior jsonb;
  v_nueva uuid;
  v_actor uuid := (select auth.uid());
  v_vinculos bigint;
  v_insertadas integer := 0;
begin
  if current_user <> 'postgres'
     or v_actor is null or not coalesce((select public.es_admin()), false)
     or pg_catalog.jsonb_typeof(v_casos) is distinct from 'array'
     or pg_catalog.jsonb_array_length(v_casos) <> 2
     or (select count(distinct x->>'cliente_id')
         from pg_catalog.jsonb_array_elements(v_casos) x) <> 2
     or (select count(distinct x->>'motivo')
         from pg_catalog.jsonb_array_elements(v_casos) x
         where x->>'motivo' in ('formato','titular')) <> 2 then
    raise exception 'P0XX: autorizacion o lote de conciliacion invalido';
  end if;

  for v_caso in select x from pg_catalog.jsonb_array_elements(v_casos) x
      order by x->>'cliente_id'
  loop
    if v_caso->>'motivo' not in ('formato','titular') then
      raise exception 'P0XX: motivo de conciliacion invalido';
    end if;
    select p.* into strict v_perfil from public.perfiles p
    where p.id = (v_caso->>'cliente_id')::uuid
      and p.rol = 'cliente' and p.activo is true for share;
    v_deseada := private.validar_cuenta_bancaria(
      pg_catalog.jsonb_build_object(
        'banco',v_perfil.banco,'tipo_cuenta',v_perfil.tipo_cuenta,
        'numero_cuenta',v_perfil.numero_cuenta,'cci',v_perfil.cci,
        'titular_distinto',v_perfil.titular_distinto,
        'beneficiario_nombre',v_perfil.beneficiario_nombre,
        'beneficiario_dni',v_perfil.beneficiario_dni));
    if pg_catalog.md5(v_deseada::text) is distinct from v_caso->>'huella_perfil' then
      raise exception 'P0XX: el perfil cambio desde la revision; no se concilia';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      v_perfil.id::text || '|PEN|' || (v_deseada->>'cci'), 0));
    select cb.* into strict v_actual from crm.cuentas_bancarias cb
    where cb.cliente_id = v_perfil.id and cb.moneda = 'PEN'
      and cb.cci = v_deseada->>'cci' and cb.activa is true for update;
    v_anterior := private.validar_cuenta_bancaria(
      pg_catalog.jsonb_build_object(
        'banco',v_actual.banco,'tipo_cuenta',v_actual.tipo_cuenta,
        'numero_cuenta',v_actual.numero_cuenta,'cci',v_actual.cci,
        'titular_distinto',v_actual.titular_distinto,
        'beneficiario_nombre',v_actual.beneficiario_nombre,
        'beneficiario_dni',v_actual.beneficiario_dni));

    if v_anterior = v_deseada then continue; end if;
    if pg_catalog.md5(v_anterior::text) is distinct from v_caso->>'huella_cuenta' then
      raise exception 'P0XX: la cuenta cambio desde la revision; no se concilia';
    end if;
    if v_caso->>'motivo' = 'formato' and (
       v_anterior - 'numero_cuenta' <> v_deseada - 'numero_cuenta'
       or pg_catalog.replace(v_anterior->>'numero_cuenta','-','')
          <> v_deseada->>'numero_cuenta') then
      raise exception 'P0XX: la diferencia no es exclusivamente de formato';
    end if;
    if v_caso->>'motivo' = 'titular' and (
       v_anterior - array['titular_distinto','beneficiario_nombre','beneficiario_dni']
         <> v_deseada - array['titular_distinto','beneficiario_nombre','beneficiario_dni']
       or (v_anterior->>'titular_distinto')::boolean is not false
       or (v_deseada->>'titular_distinto')::boolean is not true) then
      raise exception 'P0XX: la diferencia no corresponde al titular confirmado';
    end if;

    select count(*) into v_vinculos from crm.contrato_cuentas_pago cp
    where cp.cuenta_bancaria_id = v_actual.id;
    v_nueva := crm.registrar_cuenta_cliente(v_perfil.id,
      v_deseada || pg_catalog.jsonb_build_object('moneda','PEN'));
    if v_nueva = v_actual.id or v_nueva is null
       or not exists (select 1 from crm.cuentas_bancarias cb
         where cb.id = v_actual.id and cb.activa is false)
       or not exists (select 1 from crm.cuentas_bancarias cb
         where cb.id = v_nueva and cb.activa is true
           and cb.creado_por = v_actor and cb.origen = 'portal')
       or (select count(*) from crm.contrato_cuentas_pago cp
           where cp.cuenta_bancaria_id = v_actual.id) <> v_vinculos then
      raise exception 'P0XX: version, actor o vinculo contractual incorrecto';
    end if;
    insert into private.backfill_cuentas_p0xx
      (tipo,fila_id,cliente_id,marca_actor)
    values ('cuenta',v_nueva,v_perfil.id,
      'conciliacion:p0xx:' || (v_caso->>'motivo') || ':anterior=' || v_actual.id::text);
    delete from private.conciliacion_cuentas_p0xx
    where clase = 'perfil' and cliente_id = v_perfil.id and moneda = 'PEN'
      and motivo = 'mismo_cci_datos_distintos';
    v_insertadas := v_insertadas + 1;
  end loop;
  perform pg_catalog.set_config('p0xx.resultado_versiones',v_insertadas::text,true);
end;
$conciliar_versiones$;

begin;
set local statement_timeout = '20s';
set local lock_timeout = '3s';
-- @MIGRACION@

-- Únicamente en este banco y transacción: no depender del día real del test.
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $reloj$ select '2026-09-26 22:00-05'::timestamptz $reloj$;

create temp table fuentes_antes as
select 'contratos' as tabla,md5(jsonb_agg(to_jsonb(c) order by c.id)::text) as huella from public.contratos c
union all select 'leads',md5(jsonb_agg(to_jsonb(l) order by l.id)::text) from crm.leads l
union all select 'asignaciones',md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from crm.lead_asignaciones a
union all select 'inversiones',md5(jsonb_agg(to_jsonb(i) order by i.id)::text) from crm.inversiones i;

do $$
declare
  v_lead uuid;
  v_id uuid;
  v_antes crm.conversion_acreditaciones%rowtype;
  v_despues crm.conversion_acreditaciones%rowtype;
  v_cantidad bigint;
begin
  select l.id into strict v_lead from crm.leads l
    where l.perfil_id='c0000000-0000-4000-8000-000000000001';
  v_id := private.conversion_acreditar_fuente(v_lead,'contrato',
    'e0000000-0000-4000-8000-00000000000a','Fuente exacta del banco sintetico');
  select * into strict v_antes from crm.conversion_acreditaciones where id=v_id;
  if v_antes.estado<>'acreditada' or v_antes.periodo_comercial<>date '2026-09-01' then
    raise exception 'FAIL: fuente elegida acreditada en su mes';
  end if;
  if v_antes.analista_id is distinct from (select analista_id from crm.lead_asignaciones
      where id=v_antes.episodio_id) then
    raise exception 'FAIL: atribucion del episodio preservada';
  end if;
  if (select count(*) from private.conversion_cierres(
      '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,array[v_lead]))<>1 then
    raise exception 'FAIL: el nucleo consume la acreditacion una sola vez';
  end if;
  if (select fecha_numerador from private.conversion_cierres(
      '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,array[v_lead]))
      is distinct from '2026-09-05 00:00-05'::timestamptz then
    raise exception 'FAIL: el nucleo usa fecha comercial de fuente';
  end if;
  if exists(select 1 from private.conversion_cierres(
      '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',false,'{}',0.15,array[v_lead])) then
    raise exception 'FAIL: el nucleo respeta el ambito visible';
  end if;
  if v_antes.vinculado_en<v_antes.creado_en-interval '1 second' then
    raise exception 'FAIL: vinculo toma reloj actual del servidor';
  end if;
  select count(*) into v_cantidad from public.audit_log
    where tabla='crm.conversion_acreditaciones' and fila_id=v_id::text;
  if v_cantidad<>1 then raise exception 'FAIL: acreditacion auditada'; end if;
  execute $reloj$
    create or replace function private.conversion_instante_servidor()
    returns timestamptz language sql volatile security invoker set search_path=''
    as 'select ''2030-01-01 12:00-05''::timestamptz'
  $reloj$;
  perform private.conversion_acreditar_fuente(v_lead,'contrato',
    'e0000000-0000-4000-8000-00000000000a','Reintento no renueva la acreditacion');
  select * into strict v_despues from crm.conversion_acreditaciones where id=v_id;
  if v_despues is distinct from v_antes then
    raise exception 'FAIL: reintento conserva el hecho completo';
  end if;
  if (select count(*) from public.audit_log where tabla='crm.conversion_acreditaciones'
      and fila_id=v_id::text)<>v_cantidad then
    raise exception 'FAIL: reintento no agrega escritura de auditoria';
  end if;
  begin
    perform private.conversion_acreditar_fuente(v_lead,'contrato',
      'e0000000-0000-4000-8000-00000000000b','Intento con contrato de otro cliente');
    raise exception 'FAIL: fuente de otra persona aceptada';
  exception when sqlstate 'P0409' then
    if sqlerrm<>'La fuente no corresponde al lead' then raise; end if;
  end;
  begin
    perform private.conversion_acreditar_fuente(v_lead,'contrato',
      'e0000000-0000-4000-8000-000000000099','Intento con fuente inexistente');
    raise exception 'FAIL: fuente inexistente aceptada';
  exception when sqlstate 'P0002' then
    if sqlerrm<>'La fuente elegida no existe' then raise; end if;
  end;
end $$;

-- El cliente no puede inventar hechos ni fechas por acceso directo.
set local role authenticated;
do $$ begin
  begin
    perform private.conversion_acreditar_fuente(null,'contrato',null,'escritura directa');
    raise exception 'FAIL: authenticated puede invocar escritor';
  exception when insufficient_privilege then null; end;
  begin
    perform count(*) from crm.conversion_acreditaciones;
    raise exception 'FAIL: authenticated puede leer acreditaciones sin puerta';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin
    perform count(*) from crm.conversion_acreditaciones;
    raise exception 'FAIL: anon puede leer acreditaciones';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

do $$ begin
  if exists(
    select * from fuentes_antes except all (
      select 'contratos',md5(jsonb_agg(to_jsonb(c) order by c.id)::text) from public.contratos c
      union all select 'leads',md5(jsonb_agg(to_jsonb(l) order by l.id)::text) from crm.leads l
      union all select 'asignaciones',md5(jsonb_agg(to_jsonb(a) order by a.id)::text) from crm.lead_asignaciones a
      union all select 'inversiones',md5(jsonb_agg(to_jsonb(i) order by i.id)::text) from crm.inversiones i
    )) then raise exception 'FAIL: fuente o ledger original mutado'; end if;
end $$;
select 'PASS: acreditacion estable, identidad, auditoria y permisos locales' as resultado;
rollback;

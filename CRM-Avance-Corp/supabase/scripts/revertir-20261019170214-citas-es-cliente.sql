-- Reversión de 20261019170214_crm_citas_es_cliente_por_cita.sql (ensayada en el banco
-- Docker el 19/10/2026). Deja los dos lectores de Citas con su cuerpo anterior exacto,
-- re-declara sus huellas, re-sella el censo y retira la auxiliar. Un solo mensaje.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;

create temporary table es_cliente_rev_censo_antes on commit drop as
  select * from private.contadores_crudos_leads_citas();

-- El estado recibido tiene que ser consistente: un sello que no cuadra es una
-- modificación previa del ledger que hay que conciliar, no sobrescribir.
do $preflight$
begin
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSIÓN es_cliente: el sello de exenciones no cuadra; conciliar antes de revertir';
  end if;
  if pg_catalog.to_regprocedure('private.cita_con_cliente(uuid,timestamptz)') is null then
    raise exception 'REVERSIÓN es_cliente: la auxiliar no existe; nada que revertir';
  end if;
end;
$preflight$;

do $revertir$
declare
  v_objetos text[] := array[
    'private.citas_gerencia_consulta(date,date)',
    'private.citas_gerencia_consulta_corte(date,date,uuid)'];
  v_esperado text[] := array['d07e19d9731f3a7c6aef2a82f5745d58', '89ef3e8cc067c344641f247e519007a6'];
  v_clave text := $k$,
    'es_cliente',case when t.perfil_id is not null then true else private.cita_con_cliente(t.lead_id,t.creado_en) end$k$;
  v_i integer; v_def text; v_veces integer; v_md5 text;
begin
  for v_i in 1..2 loop
    v_def := pg_catalog.pg_get_functiondef(v_objetos[v_i]::regprocedure);
    v_veces := (length(v_def) - length(replace(v_def, v_clave, ''))) / length(v_clave);
    if v_veces is distinct from 1 then
      raise exception 'REVERSIÓN es_cliente: la clave aparece % veces en % (se esperaba 1)', v_veces, v_objetos[v_i];
    end if;
    execute replace(v_def, v_clave, '');
    select pg_catalog.md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p where p.oid = v_objetos[v_i]::regprocedure;
    if v_md5 is distinct from v_esperado[v_i] then
      raise exception 'REVERSIÓN es_cliente: % no volvió a su cuerpo anterior (md5 %)', v_objetos[v_i], v_md5;
    end if;
  end loop;
end;
$revertir$;

update private.analitica_leads_citas_exenciones e
set huella = pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
      pg_catalog.lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
    razon = replace(e.razon, ' Citas (19/10/2026): cada cita añade es_cliente (persona ya cliente antes de generarla, vía private.cita_con_cliente); sin cambio de alcance, población ni capital.', '')
from pg_catalog.pg_proc p
where e.objeto in ('private.citas_gerencia_consulta(date,date)',
                   'private.citas_gerencia_consulta_corte(date,date,uuid)')
  and p.oid = e.objeto::regprocedure;

update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

drop function private.cita_con_cliente(uuid,timestamptz);

do $postflight$
begin
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSIÓN es_cliente: el sello analítico no coincide';
  end if;
  if (select count(*) from private.contadores_crudos_leads_citas() c
      where c.objeto in ('private.citas_gerencia_consulta(date,date)',
                         'private.citas_gerencia_consulta_corte(date,date,uuid)')
        and c.declarada and c.huella_ok) <> 2 then
    raise exception 'REVERSIÓN es_cliente: los lectores no quedaron declarados con huella vigente';
  end if;
  if exists (
    (select * from es_cliente_rev_censo_antes except all select * from private.contadores_crudos_leads_citas())
    union all
    (select * from private.contadores_crudos_leads_citas() except all select * from es_cliente_rev_censo_antes)
  ) then
    raise exception 'REVERSIÓN es_cliente: cambió el censo analítico';
  end if;
end;
$postflight$;
commit;

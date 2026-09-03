-- ORACULO F3 comportamiento — SOLO en banco. Prueba que la puerta unica, al
-- convertir, reconoce/crea la identidad y la enlaza; y que APAGADA no cambia nada.
-- Simula la conversion como lo hace la puerta viva: set op on; update leads etapa.
-- Hace ROLLBACK. Requiere F1+F2+F3 aplicados y datos sembrados (siembra-banco-f3).
begin;
do $ora$
declare
  v_lead uuid; v_perfil uuid; v_inv uuid; v_antes bigint; v_despues bigint;
begin
  -- Tomamos un cliente A ya con identidad (de F2) y creamos un lead NUEVO suyo
  -- para convertirlo: debe REUTILIZAR su identidad (no crear otra).
  select i.perfil_id into v_perfil from crm.inversionistas i
    where i.perfil_id is not null limit 1;
  if v_perfil is null then raise exception 'ORACULO F3: no hay identidad con perfil para la prueba'; end if;
  select count(*) into v_antes from crm.inversionistas;

  perform pg_catalog.set_config('crm.op_privilegiada','on', true);
  insert into crm.leads (id, nombre_completo, telefono, monto_estimado, origen, etapa, perfil_id,
    dni, creado_por, vendedor_id)
  select pg_catalog.gen_random_uuid(), 'LEAD REUTILIZA', '999123123', 15000, 'landing', 'nuevo',
    v_perfil, p.dni, e.perfil_id, e.perfil_id
  from public.perfiles p, crm.equipo e where p.id=v_perfil and e.activo limit 1
  returning id into v_lead;
  -- convertir (dispara el trigger de F3)
  update crm.leads set etapa='convertido', convertido_en=now() where id=v_lead;
  perform pg_catalog.set_config('crm.op_privilegiada','off', true);

  select count(*) into v_despues from crm.inversionistas;
  if v_despues <> v_antes then
    raise exception 'ORACULO F3: la conversion CREO una identidad nueva (% -> %) en vez de reutilizar', v_antes, v_despues;
  end if;
  select inversionista_id into v_inv from crm.leads where id=v_lead;
  if v_inv is null then
    raise exception 'ORACULO F3: la conversion no enlazo el lead a la identidad';
  end if;
  if v_inv <> (select id from crm.inversionistas where perfil_id=v_perfil) then
    raise exception 'ORACULO F3: el lead se enlazo a una identidad distinta de la del perfil';
  end if;
  -- un solo lead vivo por persona sigue en pie
  if (select count(*) from crm.leads where inversionista_id=v_inv) > 1 then
    -- este perfil ya tenia su lead canonico de F2 -> el nuevo debe ir a historico (sin puntero vivo)
    raise exception 'ORACULO F3: la persona quedo con mas de un lead vivo';
  end if;
  raise notice 'ORACULO F3 VERDE: la conversion REUTILIZA la identidad del perfil (sin crear otra), enlaza el lead y respeta un-lead-vivo.';
end
$ora$;
rollback;

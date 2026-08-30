-- MUTANTE DEL TRINQUETE DE AUDITORÍA (P-055 F1.4)
--
-- Por cada defensa, un mutante que la neutralice: si sobrevive, esa defensa no
-- está probada. Aquí se rompe la regla A PROPÓSITO, de tres formas, y se exige
-- que cada filo la cace:
--   1. una tabla nueva sin rastro  → la regla del servidor debe verla
--   2. el vigía diario             → debe abrir su alerta
--   3. una exención metida a mano  → el espejo del repo debe delatarla
--
-- No deja nada: todo se crea y se deshace dentro de este bloque, y no escribe
-- una sola fila de negocio.
do $mutante$
declare
  v_visto_por_la_regla boolean;
  v_visto_por_el_vigia boolean;
  v_exencion_colada boolean;
  v_lista text;
begin
  -- ---- MUTANTE 1: tabla nueva sin rastro ---------------------------------
  create table crm.zzz_mutante_sin_rastro (id uuid primary key);

  v_visto_por_la_regla := exists (
    select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.zzz_mutante_sin_rastro');

  -- ---- MUTANTE 2: ¿el vigía lo anota? -------------------------------------
  perform private.vigia_auditoria();
  v_visto_por_el_vigia := exists (
    select 1 from private.auditoria_alertas a
    where a.tabla = 'crm.zzz_mutante_sin_rastro' and a.resuelta_en is null);

  -- ---- MUTANTE 3: exención colada sin pasar por el repo --------------------
  insert into private.auditoria_exenciones (tabla, razon)
  values ('crm.zzz_mutante_sin_rastro',
          'Exencion falsa del mutante: comprueba que el gate compara la lista viva con la del repo.');
  select pg_catalog.array_to_string(pg_catalog.array_agg(e.tabla order by e.tabla), ', ')
    into v_lista from private.auditoria_exenciones e;
  v_exencion_colada := v_lista
    is distinct from 'crm.usuario_eventos, public.novedades_leidas';

  -- ---- Limpieza total ------------------------------------------------------
  delete from private.auditoria_exenciones where tabla = 'crm.zzz_mutante_sin_rastro';
  drop table crm.zzz_mutante_sin_rastro;
  perform private.vigia_auditoria();  -- cierra la alerta del mutante
  delete from private.auditoria_alertas where tabla = 'crm.zzz_mutante_sin_rastro';

  -- ---- Veredicto -----------------------------------------------------------
  if not v_visto_por_la_regla then
    raise exception 'EL MUTANTE SOBREVIVIÓ (filo 1): private.tablas_sin_rastro() no vio una tabla sin auditoría';
  end if;
  if not v_visto_por_el_vigia then
    raise exception 'EL MUTANTE SOBREVIVIÓ (filo 2): el vigía no abrió alerta por una tabla sin auditoría';
  end if;
  if not v_exencion_colada then
    raise exception 'EL MUTANTE SOBREVIVIÓ (filo 3): una exención metida a mano no cambió la lista viva';
  end if;

  -- Y la casa quedó como estaba
  if exists (select 1 from private.tablas_sin_rastro())
     or exists (select 1 from private.auditoria_alertas where resuelta_en is null)
     or (select pg_catalog.count(*) from private.auditoria_exenciones) <> 2 then
    raise exception 'F1.4: el mutante dejó rastro — revisar private.auditoria_exenciones y auditoria_alertas';
  end if;

  raise notice 'MUTANTE CAZADO por los tres filos: la regla lo vio, el vigía lo anotó y el espejo delató la exención colada';
end
$mutante$;

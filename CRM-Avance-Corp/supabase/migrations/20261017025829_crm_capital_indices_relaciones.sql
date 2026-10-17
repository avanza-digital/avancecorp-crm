-- Cubrir las relaciones nuevas señaladas por Advisors antes de activar.
-- Candidata local: tablas nuevas aún vacías al instalar; sin DDL en public.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create index capital_cortes_meta_periodo on crm.capital_cortes_valorados(meta_periodo_id);
create index capital_mes_sellos_corte on crm.capital_mes_sellos(corte_id);
create index capital_valoraciones_anterior on crm.capital_valoraciones(anterior_id);
create index capital_valoraciones_tipo_cambio on crm.capital_valoraciones(fecha_tc,politica_tc);
commit;

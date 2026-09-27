begin; grant crm_metricas_bridge to postgres with set true;
grant create on schema crm to crm_metricas_bridge; grant create on schema private to crm_gestion_diaria_lector;
ALTER FUNCTION "crm"."metricas_distribucion_leads_fn"("p_desde" "date", "p_hasta" "date") OWNER TO "crm_metricas_bridge";
ALTER FUNCTION "crm"."metricas_distribucion_leads_v2_fn"("p_desde" "date", "p_hasta" "date") OWNER TO "crm_metricas_bridge";
ALTER FUNCTION "crm"."metricas_distribucion_leads_v3_fn"("p_desde" "date", "p_hasta" "date") OWNER TO "crm_metricas_bridge";
ALTER FUNCTION "private"."gestion_diaria_avisos"("p_ahora" timestamp with time zone) OWNER TO "crm_gestion_diaria_lector";
ALTER FUNCTION "private"."gestion_diaria_avisos_con_contexto"("p_ahora" timestamp with time zone) OWNER TO "crm_gestion_diaria_lector";
revoke create on schema crm from crm_metricas_bridge; revoke create on schema private from crm_gestion_diaria_lector;
grant crm_metricas_bridge to postgres with set false; commit;

# auditor-rls · B7 (04/10)

**PASS** (sin P0/P1/P2). Ninguna vía de la API a las tres tablas (sin grants; el postflight comprueba `has_table_privilege`
para anon/authenticated/service_role). La válvula `crm.op_bases_carga` no la enciende un cliente (`set_config` no expuesto;
ninguna función hace `set_config(p_…)`; el sello no exime sesiones sin usuario). El CHECK del capital no deja pasar NULL
(`origen` y `etapa` NOT NULL, `20260709000001:161-164`). El sello aguanta PATCH, `editar_lead_fn`, el importador y las
puertas de descarte/reapertura. Reversa con candados en orden fijo. P3 aplicados en la r1: detail del 23514, `lock table`
antes del preflight, no salir del motivo `base_cargada` sin válvula mientras siga descartado, nota de `public.perfiles`.

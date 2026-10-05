# auditor-rls · B6c (04/10)

**PASS** (sin P0/P1/P2). Ninguna vía de la API escribe la nota del veto: `authenticated` solo SELECT/INSERT en
`crm.actividades` (`20260709000001:538`), la policy exige `creado_por = auth.uid()` (`20260807123000:88`), `anon` sin
grant, ninguna Edge Function escribe actividades. Las tres puertas escriben con la válvula (marcar
`20260910150039:976/1016/1023`, postventa `:488/511/516` envuelta por `20260910190000:51-64`, levantar corregida
`:306/327/333`). `set_config` no está en un esquema expuesto; ninguna función hace `set_config(p_…)` con valores del cliente.
Reversa en orden correcto. P3 (aplicados en la r1): inmutabilidad (UPDATE/DELETE), variantes del evento
(`lower(btrim)`), riesgo de bloqueo del postflight (resuelto: postflight solo de catálogo), service_role sin sub documentado.

# Verificación en producción de los hallazgos del frente A (solo lectura, 2026-10-22, entre 20:40 y 21:03 Lima (hora real por `date`))

| Hallazgo | Comprobación | Resultado | Lectura |
|---|---|---|---|
| A-1 | convertidos sin contrato_id ni cierre inicial vivo | 80 → 27 tienen inversión vigente por `leads.inversionista_id`; **53 sin inversión vigente por ninguna vía** | De los 53: 44 tienen contrato ACTIVO en el portal bajo su perfil, pero ese contrato NO tiene fila en `crm.inversiones` y el lead no lo enlaza; 38 tienen acreditación (36 por contrato, 2 por cierre externo); 1 no tiene ni perfil ni inversionista. |
| A-1 (ampliado) | acreditaciones con fuente `contrato` sin fila en `crm.inversiones` | **45 de 218** (sep 39, oct 4, mar 1, may 1); 40 con el lead sin `contrato_id`, 5 con el lead enlazado | `crm.inversiones` se llena desde septiembre (140 en sep, 248 en oct). Hay **39 ventas de septiembre y 4 de octubre acreditadas en la conversión que la cartera (`crm.inversiones`) no tiene.** Contratos activos del portal sin inversión: 568, casi todos anteriores a septiembre (pre-modelo), pero 55 con inicio en septiembre. |
| A-1 | contratos con 2 o más leads | 0 | Limpio. |
| A-2 | filas que un borrado de perfil arrastraría | cuentas_bancarias 1, actividades_cliente 0, tareas 0. `public.contratos.cliente_id` es RESTRICT; `public.perfiles` tiene trigger BEFORE DELETE `usuario_retirado_perfil`; `perfiles.id → auth.users` es CASCADE | Riesgo bajo hoy: un perfil con contrato no se puede borrar. El CASCADE de `cuentas_bancarias`/`actividades_cliente`/`tareas.perfil_id` sigue sin candado propio. |
| A-3 | episodio de otro lead / analista distinto / analista fuera de equipo / contexto con lead distinto / titular principal distinto / inversión sin principal / lead sin par | 0 / 0 / 0 / 0 / 0 / 0 / 0 | Copias coherentes hoy. Hallazgo preventivo. |
| A-4 | huérfanos en las 4 columnas sin FK ni comentario | producto_condicion_id 0, **legacy_contrato_id 110**, cambio_cuenta_avisos 0 | 110 condiciones legado apuntan a contratos borrados (inofensivo según el agente; no se ofrecen). |
| A-5 | respaldo de septiembre: filas / distintas | 169 / 169 | Sin duplicados. |
| A-7 | actividades sin autor | nota:5 | Casi nada perdido. |
| A-8 | conteo real de «residuales» | objetivos_legacy_archivo 0, objetivos_vendedores_legacy_archivo 0, inversion_backfill_lotes 0; **backfill_multiempresa_mapa 471, backfill_cuentas_p0xx 511, conciliacion_cuentas_p0xx 41, piloto_f8 1/4, respaldo_agosto 17** | Solo 3 están vacías de verdad; las demás tienen datos (fuente de reversa). `n_live_tup` engañaba. Controles: empresas 3, equipo 40. |
| A-9 | triggers de FK (RI) deshabilitados / triggers de usuario deshabilitados | 0 / 0 | Todas las FK están activas: no hay huérfanos posibles por FK. |

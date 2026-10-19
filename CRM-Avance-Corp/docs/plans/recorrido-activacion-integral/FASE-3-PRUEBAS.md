# Fase 3 — Verificación local

Estado: **PASS local, 6/6**. Revisión Codex completada después de corregir los hallazgos de fase 2. Este resultado no sustituye el ensayo hosted ni acredita exigencia productiva.

| Subfase | Resultado | Evidencia |
|---|---|---|
| SQL real | PASS: evaluación, oficina, conversión, corrección PR y todos los pendientes | `evidencia/fase3-test*.log` |
| Auth/HTTP/RLS | PASS: 81 comprobaciones con Auth y PostgREST reales en copia local desechable | `evidencia/fase3-http-rls.log` |
| Interfaz en Docker | PASS: 42 tests, cero fallos/retries; recorrido, gestión diaria, Hoy, ficha/cierre, postventa y SLA | `evidencia/fase3-e2e.log` |
| Antiguos y hechos ausentes | PASS: borrador anterior, identidad tardía, ciclo ausente, mismo evento, futuro y habilitación tras hechos reales | `evidencia/fase3-test-todos.log`, `fase3-test-conversion.log` |
| Concurrencia y regresión financiera | PASS: doble envío, invalidación, rollback, cambio de modo, instalación/activación; cartera/addicional/renovación conservadas | `evidencia/fase3-concurrencia*.log`, `fase3-regresion-cartera.log` |
| Revisión Codex y gates | PASS: diff, permisos, contratos; scripts, seed/RLS offline y Edge preflight | `evidencia/fase3-check-scripts.log`, `fase3-seed-preflight.log`, `fase3-test-rls-preflight.log`, `fase3-test-edge-preflight.log` |

El primer preflight offline no tenía sus variables requeridas. Se repitió con valores ficticios explícitos y URL loopback; no abrió conexiones. El test SQL nuevo empezó con un fixture que intentaba ejecutar un helper privado bajo `authenticated`: el cálculo de fecha se movió al preparador de fixtures, conservando cerrados los permisos del producto. Después reprodujo la exención antigua y pasó con la regla nueva.

Los E2E habituales usan transporte simulado; SQL y HTTP acreditan separadamente la defensa del servidor. No hubo navegador interactivo ni datos financieros productivos. Las copias desechables se eliminaron al terminar y conservaron modo/revisión/corte del banco original.

No hay cambios de frontend en esta fase: no hace falta generar otro ZIP web para cambiar el backend. Las firmas y tipos no cambian. La suite web integral del commit base sigue siendo evidencia histórica, no se presenta como una ejecución nueva. Safari/VoiceOver manual: NOT RUN.

Se permite avanzar al ensayo de rama Supabase autorizado por un máximo de 24 horas.

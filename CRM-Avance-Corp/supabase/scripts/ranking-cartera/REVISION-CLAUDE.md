VERDICT: PASS

SUMMARY:
El candidato añade una sola rama `WHEN EXISTS` en el CASE de `origen`, después de los leads directos y del fallback por perfil y antes del `ELSE 'sin_origen'`. Solo alcanza contratos `nuevo` sin ningún lead directo ni lead de perfil temporalmente elegible, que es exactamente el requisito. No toca capital, categoría, atribución de vendedor, rama COOPAC, conversión ni snapshots. Firma, `STABLE SECURITY DEFINER`, `search_path=''`, owner y ACL se conservan y el `REVOKE` final replica el anterior. El preflight por MD5 de las tres funciones y el rollback por MD5 son coherentes. La evidencia de tests (23 aserciones con oráculo explícito, suite previa sin cambios, proyección productiva de solo lectura 143→143 sin duplicados y 12 reclasificaciones) sostiene la corrección dentro del alcance. No encuentro cambios obligatorios; sí observaciones P2/P3 y gates de release pendientes que el PRIMARY ya declara como no ejecutados.

FINDINGS:

[P2] Medio — Igualdad estricta de fecha depende de la semántica de `k.fecha` en `capital_episodios`, no del campo persistido del contrato
File:
CRM-Avance-Corp/supabase/migrations/20260927003433_crm_ranking_cartera_legada.sql
Lines:
52, 61
Problem:
El comparador `o.fecha_operacion = c.fecha_cierre_comercial` usa un alias derivado de `(k.fecha at time zone 'America/Lima')::date` (línea 61), no de `public.contratos.fecha_cierre_comercial`. Los tests insertan el ledger con `fecha_operacion = contratos.fecha_cierre_comercial` (prueba-local.sql líneas 18-22, 130-134). Que pasen implica que ambas coinciden en el banco sintético y en las 12 filas productivas, pero no demuestra que coincidan en todo contrato legado.
Evidence:
Cuerpo de `capital_episodios` no adjunto; la proyección productiva reporta 12 reclasificaciones pero no cuántos `sin_origen` con fila de ledger quedaron fuera por discrepancia de fecha, cliente o moneda.
Impact:
Hipótesis, confianza baja: contratos con ledger legítimo pero `fecha_operacion` distinta a la fecha del episodio seguirían en `sin_origen`. Es un falso negativo conservador, no un error monetario ni de seguridad; el requisito exige igualdad de fecha, así que el comportamiento es el pedido.
Recommendation:
Antes del release, ejecutar una consulta de solo lectura que cuente contratos `nuevo` sin lead con fila en `operaciones_cartera` por `contrato_nuevo_id` y que fallen exactamente uno de los cuatro predicados (cliente, moneda, fecha, tipo). Solo documentar el resultado; no cambiar el criterio sin decisión del usuario.

[P3] Bajo — La aserción de "cinco diferencias en PEN y USD" no verifica la mezcla de monedas
File:
supabase/scripts/ranking-cartera/prueba-local.sql
Lines:
65-66
Problem:
El mensaje afirma cobertura PEN y USD, pero el predicado solo comprueba `count(*)=5`.
Evidence:
`select count(*)=5 from esperado e join filas_antes a using(operacion_id) where e.origen<>a.origen`.
Impact:
Si un fixture USD cambiara de moneda, el test seguiría en PASS con un mensaje engañoso.
Recommendation:
Añadir `and count(distinct e.moneda)=2` o una aserción separada sobre las monedas de las cinco filas.

[P3] Bajo — Falta caso negativo para ledger con `tipo` fuera de `('upgrade','renovacion')`
File:
supabase/scripts/ranking-cartera/prueba-local.sql
Lines:
146-181
Problem:
Se cubren moneda, fecha y cliente discordantes, pero no un ledger que coincida en todo salvo el tipo.
Evidence:
Línea 53 del candidato filtra `o.tipo in ('upgrade','renovacion')`; ningún savepoint ejercita otro valor de `tipo`.
Impact:
Una futura ampliación del enum o un cambio accidental del `IN` no sería detectado.
Recommendation:
Un savepoint más que reinserte el ledger de `BANCO-A3` con otro `tipo` válido y espere `sin_origen`.

[P3] Bajo — Lead directo con `origen` nulo bloquea el rescate
File:
CRM-Avance-Corp/supabase/migrations/20260927003433_crm_ranking_cartera_legada.sql
Lines:
40-41, 76-77
Problem:
Un contrato con un único lead directo de `origen` nulo produce `origen_unico='sin_origen'` y nunca llega al `EXISTS`.
Evidence:
`coalesce(l.origen,'sin_origen')` en la lateral `directo`; la rama `directo.cantidad > 0` precede al `EXISTS`.
Impact:
Comportamiento idéntico al anterior y conforme al requisito literal ("no direct lead"). Solo lo señalo porque el resultado visible sigue siendo `sin_origen` aunque exista ledger.
Recommendation:
Ninguna acción; dejar constancia en el ledger de migración de que es intencional.

TEST GAPS:
- Verificación explícita de la mezcla PEN/USD en el oráculo (P3).
- Ledger con `tipo` distinto a upgrade/renovación (P3).
- Aserción de que el índice único sobre `operaciones_cartera.contrato_nuevo_id` existe; el `EXISTS` ya evita multiplicar filas, pero la afirmación de coste vive solo en el encargo.
- Matriz HTTP/RLS y preflight de seed: no ejecutados por falta de `SUPABASE_URL`. No hay cambios de tablas, políticas ni grants, por lo que no bloquea la revisión local, pero sigue siendo gate de release.

ARCHITECTURE RISKS:
- Meses ya sellados conservan `sin_origen` para estos contratos y meses posteriores mostrarán `cartera`. Es consecuencia deliberada del snapshot append-only; conviene anotarlo para quien compare periodos.
- Los rescates por ledger se agregan al grupo `cartera` existente junto con contratos no `nuevo`; el orden y la ocultación de conversión en UI ya contemplan ese grupo.

SECURITY RISKS:
- Ninguno nuevo. La subconsulta usa nombre calificado `crm.operaciones_cartera` bajo `search_path=''`, la función sigue revocada a `public, anon, authenticated, service_role`, y el único llamador textual (`private.ranking_origen_live`) queda detrás del gate de ámbito de `crm.ranking_origen_vendedor_fn`. No hay ampliación de roles ni exposición de PII.

REGRESSION RISKS:
- Bajo. Capital, moneda, vendedor y categoría por fila no cambian; la conciliación bruto vs neto+ajuste en `ranking_origen_live` sigue cuadrando por construcción. La proyección productiva confirma 143→143 filas y columnas restantes intactas.
- El preflight aborta si cambió el lector o el núcleo monetario entre la conciliación local y la instalación; el rollback exige el MD5 del candidato antes de restaurar.

RECOMMENDED NEXT ACTIONS:
1. Ejecutar la consulta diagnóstica de solo lectura del P2 y adjuntar el conteo al ledger de migración antes de pedir aprobación del SQL exacto.
2. Añadir las dos aserciones P3 (mezcla de monedas y `tipo` discordante) al test local y repetir la ejecución con rollback.
3. Al disponer de credenciales, correr matriz HTTP/RLS, preflight de seed y advisors como gates de release; no interpretar este PASS como aprobación de despliegue.

CONFIDENCE:
HIGH en corrección, seguridad y ausencia de regresión monetaria dentro del alcance revisado. MEDIUM en cobertura de contratos legados reales, por la hipótesis del P2 sin el cuerpo de `capital_episodios`.

# Conversión: adicional de renovación como upgrade

14/10/2026. Decisión de Miguel, probada en branch, autorizada y **aplicada en producción**. PR #278 integrado en Main; verificación productiva a las 21:29 UTC (16:29 de Lima).

Una renovación sigue pesando cero. Desde 01/10/2026, si la primera operación elegible del cliente/mes es una renovación con capital_adicional > 0, su aporte se clasifica como upgrade y suma 1. Se conserva la primera elegible incluso si fue renovación pura: no se busca una segunda que puntúe. No cambian divisor, referido, capital ni fotos cerradas.

Cambio mínimo: solo private.conversion_episodios. La operación y el contrato siguen siendo renovación; la categoría del aporte es upgrade. El capital se conserva separado por moneda. El campo fuente es capital_adicional, no los agregados capital_adicional_pen/usd. Las operaciones confirmadas son inmutables por trigger.

Producción: solo Vladimir cambia entre 32 perfiles. Contrato 2026-01-001568: US$ 5.000 renovados + US$ 7.000 adicionales; 3/67 (4,48 %) → 4/67 (5,97 %). Todos los demás perfiles y divisores iguales. Total oficial productivo: 55,05/905 (6,08 %) → 56,05/905 (6,19 %). La copia inicial tenía 50,05/905 → 51,05/905 por haberse creado antes de nueva actividad real.

Diciembre 2025–setiembre 2026: siete lecturas por mes, datos iguales. En branch se probó igualdad JSON literal dentro de la misma transacción. En producción solo avanzaron las marcas temporales de generación/seguimiento, comprobadas contra la hora de cada lectura. Las huellas completas de pesos, fotos, periodos cerrados, contratos y operaciones son idénticas antes/después. Solo una función cambió entre 1.047; ACL, dueño y search_path intactos. Las 12 tareas cron productivas siguen activas y las 23 Edge Functions conservan código y configuración JWT. Advisors sin diferencias.

Validación: 22 aserciones sintéticas, 7 de cierre con reloj simulado y rollback, 6 guardas, 43 contextos SQL de roles, 108 tests específicos y check:scripts PASS. Claude revisó migración/RLS, PASS; observaciones verificadas. CI del PR: preflight, lint, tipos, tests y build PASS (primera ejecución: 6.689 tests en 419 archivos). Auth/HTTP real: 7/7 PASS en branch y 7/7 PASS en producción, sin enviar correos ni cambiar contraseñas; sesiones temporales cerradas. Matriz RLS general con fixtures ajenos y E2E no ejecutados.

La migración rechaza si octubre o un mes posterior ya está cerrado. No añadir NOT EXISTS(periodos_cerrados) dentro del núcleo: cerrar_periodo inserta el sello antes de calcular la foto y perdería el punto. El cierre ensayado conserva 4/67 incluso al volver temporalmente al núcleo anterior.

PR https://github.com/avanza-digital/avancecorp-crm/pull/278 integrado el 14/10/2026 21:26 UTC. Main verificado: 2338514179a6712e3aab74d5fffd54cf2b29b1e4. SQL local 20261014174026, ledger productivo 20261014185718; no duplicar con db push masivo. SHA-256 del SQL aprobado: 22c37322ad8f2614d19542d4b59960f00d5375d45e12214dbde7ae2020cc82ea. Cuerpo productivo: 13d0c920eb7f620d1992826fb43cb584; anterior ed15fbd034c636e4897c7600002ee8cf.

Branch conversion-adicional-renovacion-20261014 (yeiwghzhcrvwfcybymxy) eliminada tras la verificación, sin coste horario futuro. Se retiró solo la branch propia. No se publicó frontend: la API existente ya entrega el cálculo corregido.

[Informe y pruebas](../../CRM-Avance-Corp/supabase/scripts/conversion-adicional-renovacion/LEEME.md). [Comparación productiva de los 32 perfiles](../../CRM-Avance-Corp/supabase/scripts/conversion-adicional-renovacion/produccion.json). [Figma](https://www.figma.com/board/tO6Lpx3ieJ6QuwUxfZcSvM/?node-id=89-115): «Activo en producción», verificación visual PASS.

Relacionado: [[Conversion mensual - definicion cerrada]] · [[Gestión comercial de clientes - renovaciones y upgrades]] · [[Conversion - referidos activos y frontend publicado (2026-10-13)]].

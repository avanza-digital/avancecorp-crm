# Adicional de renovación: aplicado y verificado

**APLICADO Y VERIFICADO EN PRODUCCIÓN el 14/10/2026, tras autorización de Miguel. PR #278 integrado; merge de la branch Supabase completado.**

El adicional de una renovación cuenta como upgrade desde el 01/10/2026. La renovación pura sigue aportando cero. Se conserva la primera operación elegible por cliente/mes: si ya hay una operación elegible anterior, la siguiente no aporta otro punto. Una renovación pura anterior también ocupa ese lugar, tal como ocurría antes.

Vladimir es el único analista cuyo numerador cambia, tanto en el ensayo como en producción. El contrato **2026-01-001568**, del 06/10/2026, conserva US$ 5.000 renovados y US$ 7.000 adicionales. Ese adicional añade un punto: **3/67 = 4,48 % → 4/67 = 5,97 %**. Los dos cierres de lead y el upgrade de otro cliente se conservan.

En producción, el total de empresa pasa de **55,05/905 = 6,08 %** a **56,05/905 = 6,19 %**. El divisor y los importes no cambian.

## Verificación en producción

[Resultado completo de los 32 analistas](produccion.json). Lecturas del 14/10/2026 a las 21:27 y 21:29 UTC (16:27 y 16:29 de Lima): **solo Vladimir cambia, 3/67 → 4/67; 4,48 % → 5,97 %**. Todos los divisores se conservan. La fila completa de cada responsable se cotejó por vendedor_id, ya que el ranking cambia de orden al subir Vladimir.

El total oficial actual de empresa pasa de **55,05/905 (6,08 %) a 56,05/905 (6,19 %)**. Es distinto del ensayo inicial porque hubo actividad real después de crear la copia; el efecto de esta migración sigue siendo exactamente un punto.

Setenta salidas históricas de diciembre 2025 a setiembre 2026 conservan todos sus datos. Entre las lecturas productivas solo avanzan las marcas de reloj `generado_en`, `cosecha.madura_hasta` y `citas_reales.seguimiento_hasta`; las dos últimas se comprobaron iguales a la hora exacta de cada captura. La equivalencia JSON literal ya se había probado en la misma transacción en la branch. Pesos, periodos cerrados, fotos, contratos y operaciones mantienen las mismas huellas completas. Las 12 tareas cron productivas siguen activas; las 23 Edge Functions conservan código y validación JWT. Advisors de seguridad y rendimiento sin diferencias.

[Auth/HTTP en producción](produccion-http.json): **7/7 PASS**, con respuestas iguales a SQL para Vladimir, otro analista, Supervisión, Gerencia, Coordinación, anónimo y servicio. Sesiones temporales generadas y cerradas internamente, sin correos ni cambio de contraseñas. Entre las 1.047 funciones comparadas, solo cambió `private.conversion_episodios`; dueño, ACL, estabilidad y search_path intactos.

El SQL aprobado está en Main `2338514179a6712e3aab74d5fffd54cf2b29b1e4` y fue cotejado por SHA-256 antes del merge de Supabase. Registro productivo: **20261014185718**. La branch temporal fue eliminada después de verificar; ya no genera coste horario.

El [preflight previo](produccion-preflight.json) conserva el estado histórico de las 21:00 UTC, cuando todavía faltaba la aprobación de GitHub. El estado final es el de [produccion.json](produccion.json) y [verificacion.json](verificacion.json): aplicado y verificado.

## Comparación del ensayo en branch

En la copia inicial, el total de empresa pasó de **50,05/905 = 5,53 %** a **51,05/905 = 5,64 %**. Estos son los resultados de ese ensayo, anterior a las capturas productivas.

Se compararon 32 perfiles: 27 del ranking oficial y 5 inactivos. Los inactivos no aparecen en el ranking: también se comprobó el núcleo, sin actividad ni aporte. «—» significa que no hay porcentaje porque el divisor es cero. Todos los divisores antes/después son iguales.

| Analista | Divisor | Numerador antes → después | Conversión antes → después |
|---|---:|---:|---:|
| ADELAYDA GASPAR MARTINEZ | 56 | 5 → 5 | 8,93 % → 8,93 % |
| ALAN YUTRONIC | 64 | 0 → 0 | 0,00 % → 0,00 % |
| ALVARO LEOMAR CCAHUANA ALHUIRCA | 0 | 0 → 0 | — → — |
| ANALISTA CRM (DEMO) (inactivo) | 0 | 0 → 0 | — → — |
| ANTONELLA JARAMILLO JULCA | 58 | 2,15 → 2,15 | 3,71 % → 3,71 % |
| ASTRID CENTENARO | 65 | 1,15 → 1,15 | 1,77 % → 1,77 % |
| BETZABETH FUENMAYOR SAAVEDRA | 62 | 3 → 3 | 4,84 % → 4,84 % |
| CLAUDIA FERNANDA CRUCES BRAVO | 0 | 0 → 0 | — → — |
| DANIELA ALESSANDRA CASTILLO | 65 | 3 → 3 | 4,62 % → 4,62 % |
| EDGAR ANCCASI HUAMANI | 0 | 0 → 0 | — → — |
| EDSON ALAGON VILCA | 0 | 0 → 0 | — → — |
| ELIZABETH CHIROQUE NAVARRO | 11 | 3 → 3 | 27,27 % → 27,27 % |
| FIORELLA RUIZ | 67 | 4 → 4 | 5,97 % → 5,97 % |
| GABRIELA CUTIPA ROBLES | 0 | 0 → 0 | — → — |
| GERENTE CRM (DEMO) (inactivo) | 0 | 0 → 0 | — → — |
| GRECIA RAMIREZ CORTEZ | 0 | 0 → 0 | — → — |
| GUILLERMO CASTRO SOTOMAYOR | 65 | 2 → 2 | 3,08 % → 3,08 % |
| IVETT TEEVIN (inactivo) | 0 | 0 → 0 | — → — |
| JAICO CERVERA LUNA | 0 | 0 → 0 | — → — |
| JESSICA ESCUDERO TENAZOA | 0 | 0 → 0 | — → — |
| JHON ESPINOZA | 0 | 0 → 0 | — → — |
| KELLY VEGA | 1 | 1 → 1 | 100,00 % → 100,00 % |
| LINDA CONDORI GUTIERREZ | 68 | 5 → 5 | 7,35 % → 7,35 % |
| LISSETH NUÑEZ GARCÍA | 66 | 2,3 → 2,3 | 3,48 % → 3,48 % |
| LUIS ENRIQUE VELA RAMÍREZ | 0 | 0 → 0 | — → — |
| MERLYS GARCIA | 57 | 8,15 → 8,15 | 14,30 % → 14,30 % |
| MIGUEL BRICEÑO | 0 | 1 → 1 | — → — |
| NAYRA GAMERO LINO | 67 | 4,3 → 4,3 | 6,42 % → 6,42 % |
| NOELIA SALAZAR RUIZ (inactivo) | 0 | 0 → 0 | — → — |
| PIERINA LEVANO PURIZACA (inactivo) | 0 | 0 → 0 | — → — |
| ROSA AGUIRRE | 66 | 1 → 1 | 1,52 % → 1,52 % |
| VLADIMIR JURADO | 67 | 3 → 4 | 4,48 % → 5,97 % |

[Resultados estructurados](comparacion.json). La única operación cuyo episodio cambia es `22a7be9b-b040-4c67-a01e-000ac1c12fbb`: categoría de aporte `renovacion → upgrade`, aporte `0 → 1`; mismos identificadores, fecha y responsable. No se crea una segunda operación.

## Cambio mínimo y coherencia

[SQL completo de la migración](../../migrations/20261014174026_crm_conversion_adicional_renovacion.sql), mostrado al usuario antes de aplicarlo a la branch.

Solo reemplaza `private.conversion_episodios`. Dentro de su último `UNION ALL`, la subconsulta de `crm.operaciones_cartera` calcula `categoria_conversion`: una renovación de octubre o posterior con `capital_adicional > 0` se clasifica como upgrade para conversión. La selección mediante `row_number()` y el ámbito permanecen iguales.

El dato fuente es `crm.operaciones_cartera.capital_adicional` junto con `moneda`. Los campos `capital_adicional_pen/usd` y `capital_renovado_pen/usd` se agregan separadamente desde los episodios de capital. El tipo de operación y la categoría del contrato siguen siendo renovación. Por eso la conversión puede mostrar dos upgrades mientras cartera conserva una operación de renovación: son conteos distintos y deliberados.

Se revisaron el catálogo vivo y sus consumidores: `conversion_mensual_por_vendedor`, `conversion_mensual_fn`, `metricas_conversiones_fn` y su implementación, `metricas_conversiones_equipo_fn`, `metricas_cartera_por_vendedor`, Coordinación, Metas, `cerrar_periodo` y el trigger de sellado. Comparten el núcleo; los conteos de conversión usan la categoría del episodio. No requieren copiar la regla ni modificar sus pesos. Los ajustes de leads y el trigger de acreditaciones filtran `tipo='cierre'`, por lo que no reclasifican estas operaciones.

La fecha de vigencia queda en código; un cambio futuro de esa regla necesitará otra migración. Las fotos almacenan los resultados y los conteos de upgrade. No se añadió una columna ni se cambiaron firmas, permisos o políticas RLS.

## Histórico y meses cerrados

**PASS:** igualdad exacta de los JSON de siete lecturas mensuales durante los diez meses desde diciembre de 2025 (primera acreditación existente) hasta setiembre de 2026. Se compararon la oficial, Coordinación, métricas, equipo, Metas, episodios y núcleo dentro de la misma transacción, incluso el orden y los metadatos. [Ensayo reproducible](historico.sql).

Las huellas de todas las filas de pesos, periodos cerrados, fotos de vendedores, operaciones y contratos son idénticas antes y después, también tras terminar los ensayos. Agosto y setiembre continúan cerrados. Ninguna foto anterior se reescribe.

La migración toma el mismo candado global del cierre y rechaza si ya existe un mes cerrado desde octubre. No se pone una excepción dinámica por mes cerrado dentro del núcleo: `cerrar_periodo` crea primero el sello y después calcula la foto, y esa excepción quitaría el punto al cerrar.

## Verificación ejecutada

| Verificación | Resultado |
|---|---|
| Comparación real de octubre, todos los perfiles | PASS: solo Vladimir +1 |
| Histórico completo diciembre 2025–setiembre 2026 | PASS: 70 salidas mensuales idénticas |
| Casos sintéticos en la branch | PASS: 22 aserciones, con rollback |
| Cierre y lectura congelada | PASS: 7 aserciones, con rollback |
| Guardas de núcleo, mes cerrado, pesos y ACL | PASS: 6 escenarios, con rollback |
| Ámbitos y permisos SQL | PASS: 43 contextos (40 perfiles + anónimo, sin equipo y servicio) |
| Tests existentes de frontend de conversión | PASS: 108 tests |
| `npm run check:scripts` | PASS |
| Revisión independiente de migración y RLS | PASS; observaciones evaluadas por Codex |
| Supabase advisors de seguridad | Sin diferencias; ninguna alerta nueva |
| Supabase advisors de rendimiento | Sin problemas nuevos; 24 índices dejan de figurar sin uso tras las consultas |
| Puerta afectada por Auth/HTTP | PASS: 7 contextos; respuestas iguales a SQL |
| `npm run test:rls:preflight` | PASS con variables de la branch |
| Matriz general `test-rls.mjs` | NOT RUN: necesita fixtures propios; se ejecutó la matriz pertinente de esta puerta sin reemplazar los datos clonados |
| Gate completo de aplicación en CI | PASS: lint, tipos, 6.689 tests en 419 archivos y build |
| E2E de frontend | NOT RUN: sin cambios de frontend; no se ejecutaron E2E en GitHub |

El ensayo de cierre cambia **solo las dos guardas de reloj** de `cerrar_periodo` a noviembre 11 dentro de una transacción; el cálculo, la inserción de la foto y sus lecturas usan el código real. Después se carga el núcleo anterior: el cálculo vivo vuelve a 3 pero la foto de Vladimir sigue en 4 y el total oficial en 51,05. Todo se revierte. El cierre vigente omite un perfil sin metas ni actividad (Luis Vela), aunque la pantalla viva sí lo muestra con ceros; se comprobó esta diferencia preexistente.

La siembra sintética suspende triggers y sustituye el filtro de fuentes para fabricar estados de prueba. No acredita los comandos de alta. La matriz SQL separada usa los datos y funciones reales, con `SET ROLE`, conserva todos los IDs visibles y verifica que solo quien puede ver a Vladimir recibe su +1. El núcleo sigue sin EXECUTE para anon, authenticated y service_role.

La comprobación [Auth/HTTP](http.json) usa sesiones reales de Vladimir, Fiorella, Supervisión, Gerencia y Coordinación, más anónimo y servicio. Los siete resultados coinciden íntegramente con SQL, excluyendo solo la hora de generación. Los enlaces de acceso se generaron y consumieron internamente mediante [generateLink](https://supabase.com/docs/reference/javascript/auth-admin-generatelink); no se enviaron correos ni se cambiaron contraseñas. Las sesiones se cerraron después. No prueba login con contraseña ni recuperación. El intento inicial con JWT fabricados falló porque la firma no correspondía a las claves activas de la copia; se sustituyó por Auth real. Un intento amplio encontró el límite de peticiones de Auth; el ensayo final ejecutó secuencialmente los siete contextos de roles indicados, respetando la espera del servicio. El preflight inicial sin variables falló; el final con variables de la branch pasó.

La revisión pidió comprobar mutabilidad y consumidores. El catálogo confirma un trigger `trg_operaciones_cartera_00_append_only` que rechaza todo UPDATE, además de ausencia de permiso UPDATE para los tres roles de aplicación. No existe el escenario normal de completar el desglose después del alta. El CHECK exige que toda renovación sea elegible: fabricar una renovación no elegible violaría el esquema; el caso no elegible usa un upgrade. Se añadió el ensayo de rango que cruza setiembre/octubre. El frontend valida ambos conteos independientemente, sin cocientes ni límites entre conversiones y operaciones. Se conservó el SQL revisado sin cambios opcionales de estilo.

## Entorno y reproducción

- Organización aprobada: `fzxtxnkvslpcsscxqfbr`.
- Branch: `conversion-adicional-renovacion-20261014`, proyecto `yeiwghzhcrvwfcybymxy`, copia con datos de `dctqcbznekcyxhjujuci`.
- Creada el 14/10/2026 18:30:49 UTC. Coste autorizado: **US$ 0,01344/h** (aprox. US$ 0,32/día); eliminada tras la verificación productiva.
- Durante el ensayo sus 12 tareas cron estuvieron desactivadas. En producción se conservan las 12 activas. Solo se retiró la branch propia.
- Migración en el ledger remoto: `20261014185718_crm_conversion_adicional_renovacion`; archivo local: `20261014174026`. El conector asignó el timestamp remoto. No hacer `db push` masivo ni repetir ambas versiones.
- Huella de cuerpo anterior: `ed15fbd034c636e4897c7600002ee8cf`; candidata: `13d0c920eb7f620d1992826fb43cb584`. Producción conserva la candidata, verificada después del merge.
- Las capturas extensas permanecen fuera del repositorio en `/private/tmp/conversion-adicional-antes.json` y `/private/tmp/conversion-adicional-despues.json`. La comparación publicable está en este directorio.
- El contenedor local propio se detuvo al terminar.

Comandos usados durante el ensayo. La branch indicada fue retirada: para repetir, preparar otra copia autorizada y actualizar primero sus identificadores fijos en los ejecutores; nunca apuntarlos a producción:

```sh
python3 supabase/scripts/conversion-adicional-renovacion/branch-prueba.py prueba.sql /private/tmp/adicional-prueba.log
python3 supabase/scripts/conversion-adicional-renovacion/branch-prueba.py historico.sql /private/tmp/adicional-historico.log
python3 supabase/scripts/conversion-adicional-renovacion/branch-prueba.py cierre.sql /private/tmp/adicional-cierre.log
python3 supabase/scripts/conversion-adicional-renovacion/branch-prueba.py seguridad.sql /private/tmp/adicional-seguridad.log
python3 supabase/scripts/conversion-adicional-renovacion/branch-prueba.py guardas.sql /private/tmp/adicional-guardas.log
supabase db query --linked --project-ref yeiwghzhcrvwfcybymxy --file supabase/scripts/conversion-adicional-renovacion/http-esperado.sql --output json > /private/tmp/conversion-adicional-http-esperado.json
python3 supabase/scripts/conversion-adicional-renovacion/probar-http.py
```

El ejecutor fija el proyecto de la branch, expande los includes y solo acepta ensayos terminados en rollback. No imprime credenciales. La conexión administrativa de la CLI funciona; la conexión PostgreSQL directa de la copia no estuvo disponible.

## Figma y cierre

[Tablero actualizado, con el caso y los resultados](https://www.figma.com/board/tO6Lpx3ieJ6QuwUxfZcSvM/?node-id=89-115). Se actualizaron también la regla del numerador y sus ejemplos. Captura revisada sin recortes.

**Aplicado y verificado.** El [PR #278](https://github.com/avanza-digital/avancecorp-crm/pull/278) fue integrado el 14/10/2026 a las 21:26 UTC con sus controles PASS. Main local y `avancecorp/main` se comprobaron en el mismo commit antes del merge de Supabase. Figma muestra «Activo en producción». El SQL de reversa base está en `nucleo-anterior.sql`; no ejecutarlo aisladamente ni después de un cierre sin revisar las fotos y el estado vigente.

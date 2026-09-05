---
tags: [crm, gerencia, metricas, auditoria, pruebas]
requerimiento: REQ-GER-MET-001
punto: 5
fecha: 2026-09-05
estado: ampliaciones-n1-n4-implementadas-y-auditadas-local-produccion-pendiente
---

# Auditoría de Gerencia — avance del punto 5

Relacionado con [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Datos faltantes de Gerencia - punto 4 - decision pendiente 2026-09-05]], [[Inventario de indicadores de Gerencia - Contrato de lectura]], [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]] y [[Publicacion frontend metricas Gerencia 2026-09-04]].

## Actualización final local de N1–N4

Las cuatro ampliaciones fueron implementadas y auditadas localmente después de la línea base descrita más abajo. Se modificaron únicamente las proyecciones de los dos agregadores existentes; no se creó función, RPC, núcleo ni calculadora. Los núcleos de conversión, citas y capital, las fachadas, propietarios y ACL conservaron sus definiciones.

- N1 separa `lead_id` con cita registrada como realizada del avance inferido; incluye el corte y declara citas anteriores al alta.
- N2 entrega el divisor computable y las exclusiones por modalidad sin recalcular el porcentaje en el navegador.
- N3 entrega identidad, atribución, período, fecha y aporte exacto de cada operación seleccionada por el núcleo.
- N4 agrupa por la fecha del cierre en Lima y declara cantidad/aporte fuera del roster, sin reasignarlos ni mezclar Cartera.
- La interfaz valida el contrato y usa el título acordado **«Resultados de los leads del mes»** en Resumen, Conversiones y Ranking. Se retiraron «hasta hoy» y «Cosecha del lote» de esa lectura sin alterar sus datos.

Evidencia final: banco SQL con migración → rollback → migración → N1–N4/ACL aprobado; revisión independiente en GO técnico sin hallazgos críticos, altos o medios; `npm run check` con 194 archivos y 2.819 pruebas; 97 pruebas focales; 121 E2E aprobadas, 26 omitidas y cero fallos. Detalle, huellas y reversión en [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]]. No se aplicó este SQL en producción y no hubo commit ni deploy nuevo.

## Línea base previa a las ampliaciones

Esta sección conserva la evidencia obtenida antes de implementar N1–N4. En ese momento se verificaron los contratos previos y se corrigió una regresión visual compartida; sus límites históricos quedaron superados por la actualización final local anterior. El commit, la migración productiva y el deploy continúan pendientes.

Main al iniciar: `9b09efa859a51ed43c60a15d8c9d860e969628c3`, árbol inicialmente limpio. La publicación anterior de los puntos 1–3 no se repitió. Ningún SQL, permiso, usuario de Auth ni dato comercial productivo fue modificado durante esta auditoría.

## Defecto visual reproducido y corregido localmente

`AnimatedValue` restaba `performance.now()` al timestamp de `requestAnimationFrame`. El segundo puede corresponder a un instante anterior; al no limitar el extremo inferior, el progreso era negativo y cambiaba transitoriamente el signo de un saldo positivo. La prueba determinista reprodujo `S/ -420.5k` antes del saldo positivo esperado. No era un saldo negativo enviado por Cartera.

Se corrigió **el mismo componente**, sin cambiar su API ni crear una calculadora de métricas: primer timestamp del RAF como inicio, progreso visual entre 0 y 1, cancelación incluso con identificador 0, conservación exacta del texto final y protección frente a valores anteriores al cambiar filtro. Un negativo real sigue siendo negativo; no se recortan los datos del servidor. Duraciones inválidas y movimiento reducido presentan el valor sin animarlo.

La documentación de [requestAnimationFrame de MDN](https://developer.mozilla.org/en-US/docs/Web/API/Window/requestAnimationFrame) respalda la diferencia entre ambos relojes. Se consultó Context7 para ciclo/limpieza de React y observación con Playwright. Supabase se utilizó sólo para contrastar lecturas y catálogo reales, no para desplegar cambios.

Prueba roja previa: 10 fallos y 1 aprobación. Después: **11/11 aprobadas** en `app/src/components/common/animated-value.test.tsx`. El E2E nuevo en `app/e2e/mi-cartera-resumen.spec.ts` habilita movimiento, observa varios cambios reales del texto y comprueba que no aparezcan signos negativos inventados, NaN ni Infinity; termina en los dos importes servidos por el resumen. No se usó movimiento reducido como sustituto de esa prueba.

## Verificación ejecutada

- `npm run check`: salida 0; **192 archivos y 2.752 pruebas aprobadas**, lint sin errores, typecheck, 4 pruebas de configuración de release, compilación, comprobación del bundle y duplicación aprobados. Permanecen cuatro advertencias previas de accesibilidad en `coverflow-carousel.tsx`.
- Cobertura: líneas 79,66 %, ramas 74,03 %, funciones 75,90 %, sentencias 77,26 %. No afirmar cobertura total.
- Duplicación: 0,69 % de líneas, por debajo de la puerta configurada 0,8 %.
- `npm run test:e2e -- --workers=2`: salida 0, **121 aprobadas y 26 omitidas previamente**, 3,7 minutos. Las omitidas no cuentan como verificadas. Los errores intencionales del backend simulado pertenecen a pruebas de rechazo; no son errores productivos.
- E2E dirigido de Cartera: 4/4, incluido el caso con movimiento habilitado.
- SQL aislado: `test-conversion-llegadas.sql`, `test-f2-reuniones.sql` y `test-gerencia-citas-extremos.sql`, todos con salida 0. Fixtures dentro de transacciones revertidas.
- Banco de Cartera: `test-cartera-sin-demo-local.mjs`, salida 0; 7 contextos, V1/V2/vista, 56 lecturas de cronograma, 56 de titulares, denegación anónima, datos intactos, reversión y reaplicación local aprobadas. **No se reaplicó la migración en producción.**

## Matriz de los trece escenarios acordados

La columna «Límite pendiente» registra el estado de la línea base previa. Los límites N1–N4 allí descritos fueron cubiertos después por la actualización final local; no deben leerse como pendientes actuales.

Las rutas de prueba de frontend son relativas a `CRM-Avance-Corp/app/`; las SQL, a `CRM-Avance-Corp/supabase/scripts/`.

| Caso | Evidencia ejecutada y resultado | Límite pendiente |
| --- | --- | --- |
| 1. Reasignación, Ana/llegada y Luis/cierre | `test-conversion-llegadas.sql`: base global 4; Ana conserva divisor 3 y Luis divisor 0 con sus cierres. Rescatar, ocultar o descartar no aumenta la base. | Ninguno en el contrato vigente. |
| 2. Automáticos, manuales, referido y pesos | Misma prueba: 6 llegadas no equivalen a divisor 4; numerador parcial 3,30. Renovación sigue el parámetro de referido incluso al probar 0,25; upgrade conserva 1. | Ninguno en esas reglas; no se modificaron. |
| 3. Cierre/propuesta sin cita | `src/screens/hoy/inteligencia-comercial.test.tsx`: conserva las señales servidas pero las llama «Reunión o avance posterior», nunca asistencia real. El núcleo de citas se prueba aparte. | N1: personas del lote con cita real aún no es un campo servido. |
| 4. Estados de citas y divisores | SQL nuevo: 11 citas, 9 vencidas al corte controlado, realizadas/no-show/canceladas propias-ajenas-sistema/nula/reprogramadas/pendientes/futuras, excluyendo inactivas, llamadas y frontera final. Agregador: realización 37,5 %, asistencia 75 %; responsable 42,9 % por cancelador ajeno. Interfaz en `reuniones-gerencia.test.tsx`. | N2: la fracción por modalidad no se inventa; conserva el porcentaje servido sin usar el bruto como divisor. |
| 5. Rango parcial y navegación mensual | `src/screens/hoy/gerencia.test.tsx`: Rendimiento deja de heredar el rango oculto y consulta el mes correspondiente; navegación histórica, fechas manipuladas y mes futuro cubiertos. E2E de gráficas comprueba el mes calendario. | No implica que todos los bloques pasen a medir el mismo período. |
| 6. Maduración y fotos selladas | `test-f2-reuniones.sql`: cita de julio con cierre en agosto cuenta; cierre anterior a cita, anulado y no cerrado no cuentan. `test-conversion-llegadas.sql`: una foto legacy conserva su fuente/peso y la foto nueva conserva llegadas sin analista. | N4: no existe aún una serie semanal por fecha real de cierre. |
| 7. Demos, PEN/USD y capital | Banco Cartera excluye demos sin borrar contratos y conserva ámbitos. Unit/E2E comprueban resumen global frente a mes/listado y monedas separadas. SQL de citas verifica dos monedas por cliente sin cambiar la selección vigente por moneda del lead. | El capital de citas no certifica todo el stock de un cliente; ver precisión debajo. |
| 8. Varias operaciones por cliente/mes | SQL: recortar el rango no convierte la segunda operación en un nuevo aporte. `mi-cartera.test.tsx`: una elegible no promete «1 conversión» ni «suma conversión». | N3: la selección y el aporte por ID no se entregan todavía al listado. |
| 9. Filtros, roster y sin analista | `mi-cartera.test.tsx`: alcance global/filtrado explícito, dueño nulo o fuera del roster, bajas y acciones fuera de ámbito. Prueba mensual de SQL conserva el agregado sin analista y las fotos históricas. | Roster comercial y operativo son poblaciones diferentes, no números que deban forzarse a coincidir. |
| 10. Error, carga, null, sondas y filas inválidas | `inteligencia-comercial.test.tsx`, `mi-cartera.test.tsx` y `crm-api-clientes-msw.test.ts`: no se presenta cero ante ausencia/error/verificación fallida; fila inválida invalida la lectura completa. E2E prueba aviso y reintento. | No sustituir un dato nuevo ausente por cero al ampliar N1–N4. |
| 11. Listado recortado y paginación | `crm-api-clientes-msw.test.ts`: 2.105 clientes con páginas recortadas a 73; cambia total, falta total, página vacía y repetición rechazan el éxito parcial. Operaciones también paginadas. Tarjetas globales usan resumen, no longitud del listado. | La prueba simula un límite menor; no altera la configuración remota de PostgREST. |
| 12. Sobrecumplimiento | `resumen-gerencia.test.tsx`: 150 % de conversión y 200 % de capital completos, barras a 100 %. `inteligencia-comercial.test.tsx`: 150,00 % canónico no se recorta. | Ninguno en esos consumidores. |
| 13. Roles y núcleos intactos | SQL nuevo ejecuta la fachada como `authenticated` con Gerencia; vendedor/sin identidad rechazados y núcleo privado inaccesible. Catálogo productivo de 32 funciones idéntico antes/después. | No es una auditoría de seguridad integral ni una prueba de todas las escrituras del CRM. |

## Conciliación real y diferencias justificadas

Lecturas productivas del rango 1–4 de septiembre, realizadas esta madrugada en transacciones de sólo lectura:

- **231 base automática y 243 llegadas:** 11 altas manuales y 1 referido explican la diferencia. El núcleo sirve numerador 9 y conversión comercial 3,9 %; 7 cierres no referidos y 2 upgrades. Sondas cuadradas, paridad 0.
- **6 cierres del lote / 243 llegadas = 2,5 %** no es el índice comercial anterior: tiene población y seguimiento distintos.
- **25 señales inferidas, 4 personas del lote con cita real y 5 citas realizadas operativas:** no son intercambiables. La sonda de personas tiene corte `2026-09-05 05:07:19 UTC`; no se codificó este resultado en ninguna pantalla.
- **28 citas pactadas:** 5 realizadas, 16 no-show, 1 cancelada por asesor, 4 canceladas por sistema y 2 pendientes. Virtual 23,5 % corresponde a 4/17 computables, no 4/21 brutas. Sin ampliar N2, se conserva el porcentaje sin fabricar la fracción.
- Cartera: **S/ 19.485.413,12 y US$ 1.075.193,33**, 516 contratos activos y 1 vencido. Su fuente excluye demos. «Sin analista» visible usa una definición de gestión que no se sustituye por el campo global «sin asesor».

**Precisión confirmada del capital de Citas:** el agregador toma stock por la moneda del lead y lo atribuye a su última cita realizada. El fixture entrega al primer cliente PEN 100/USD 7 y al segundo PEN 9/USD 20; los leads son PEN/USD respectivamente. La respuesta vigente es PEN 100/USD 20, no PEN 109/USD 27, y las dos citas del primer lead no duplican ese capital. Esto confirma el alcance descrito en [[Inventario de indicadores de Gerencia - Citas y operacion]]; no ampliar su interpretación a «todo el capital de esos clientes» ni cambiarlo por analogía con Cartera.

## Inmutabilidad y límites del banco

Se compararon las **32 funciones** del catálogo inicial usando la misma firma de identidad: definición, salida, propietario, permisos, search_path, SECURITY DEFINER y volatilidad. **Cero cambios y cero ausencias.** Huellas de los tres núcleos:

| Núcleo | MD5 de definición, antes y después |
| --- | --- |
| `private.conversion_episodios` | `8a2549dbfa59c732da04900ed90b6361` |
| `private.citas_episodios` | `ea636888a266941e959f26c6a5727216` |
| `private.capital_episodios` | `b8f375fbb377582835f4cfe222240c5b` |

Banco general en `/tmp/avancecorp-gerencia.TwY3KC`, base `crm_llegadas_auditoria_20260905`, socket privado puerto 55438, `listen_addresses=''`. Se verificó cluster vacío antes del montaje. Quince funciones se cargaron desde sus definiciones productivas exactas, con las mismas huellas y permisos. Se reutilizó el bootstrap del runner F2 **sin ejecutar su antiguo montaje destructivo sobre 5432**. Catálogo, Auth, roster, capital y Distribución V2 usaron dobles declarados; no se presenta este banco como una auditoría completa de esas dependencias.

Banco Cartera separado en `/tmp/avancecorp-cartera.Tbnnqt`, socket privado 55437. Ambos servidores locales se detuvieron al terminar; se conservaron fixtures y registros, sin borrar directorios. PostgreSQL local 16.14, producción 17.6.1.105: las funciones copiadas compilaron con huellas idénticas, pero no es igualdad de versión de infraestructura.

Artefactos locales de auditoría en `CRM-Avance-Corp/releases/` (directorio ignorado por Git, no artefactos publicados): `auditoria-gerencia-20260905-funciones.json` y `auditoria-gerencia-20260905-banco.json`. Conservan fuentes, huellas y fixtures necesarios para reconstruir el banco en otro cluster nuevo **sin TCP**. No ejecutar esos fixtures contra producción ni una base compartida. La prueba SQL nueva exige nombre de base, directorio temporal y doble de capital antes de tocar fixtures.

## Siguiente acción

Presentar y confirmar el SQL exacto ya auditado antes de aplicarlo. Después se debe leer el resultado productivo, versionar todo preservando el trabajo concurrente, sincronizar Main únicamente con `avancecorp/main`, publicar el artefacto de ese mismo commit con autorización y comprobar las cuatro lecturas con una sesión real de Gerencia. **No volver a pedir aprobación conceptual de N1–N4 ni afirmar que ya están en producción.**

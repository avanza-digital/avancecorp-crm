# Codex · SECONDARY_REVIEWER · 2026-09-21 (codex exec, sandbox read-only, sin shell/MCP, gpt-6-astra)

VERDICT: **CHANGES_REQUESTED**

SUMMARY:

Hay defectos demostrables en la publicación de cifras y en el cálculo del navegador. Otros hallazgos mezclan un mecanismo confirmado con consecuencias todavía no demostradas. **No hay evidencia suficiente para sostener un P0.**

Esta revisión cubre exclusivamente los extractos adjuntos. Las coincidencias entre agentes no sustituyen código faltante, reproducciones ni evidencia del despliegue.

FINDINGS P0–P3:

**F1 — CONFIRMADO el cálculo en vivo; HIPÓTESIS la discrepancia publicada. P1 condicionado.**

El rango agrega `conversion_episodios` y construye el porcentaje directamente: migración `20260908211349`, líneas 2208–2211, 2346–2365 y 2518–2519. Distribución hace lo mismo en `20260904210831:1128–1156,1276–1280`. La lectura mensual selecciona la foto en `1386–1389`.

Esto demuestra dos fuentes de lectura distintas en los tramos mostrados. No demuestra que sus valores **siempre** difieran, ni permite descartar una intervención posterior de los wrappers cuyos cuerpos no están adjuntos. Mantendría P1 cuando un mes completo sellado se publique como el mismo índice mensual y cambie con el ledger. Para rangos parciales o de varios meses hace falta precisar cómo debe intervenir la foto.

**F2 — CONFIRMADO el bruto frente al neto. P1 en superficies que presentan el mismo índice mensual.**

La mensual aplica `conversion_con_ajuste` tanto al numerador como al porcentaje (`20260904210831:1660–1665`); los cálculos de rango y Distribución adjuntos utilizan la suma bruta. La alerta de caída toma ese porcentaje del rango (`alertas-gerencia.ts:291–296`).

La divergencia aparecerá cuando el ajuste tenga efecto y se comparen el mismo período y alcance. **No extendería automáticamente el defecto a cualquier rango:** la regla de negocio reserva expresamente los ajustes a la lectura mensual. Tampoco trasladaría la deuda al núcleo para resolverlo. F1 y F2 son mecanismos diferentes —foto frente a lectura viva, y neto frente a bruto— que pueden coincidir en una misma discrepancia.

**F3 — HIPÓTESIS en su formulación completa. P2.**

La comparación está visible en `20260908211349:2373–2384`, pero falta el cuerpo de `conversion_mensual_por_vendedor`. No puede afirmarse que ambas llamadas sean idénticas: la invocación directa recibe `v_periodo`; la del helper mostrado no lo recibe explícitamente.

También falta `sondasNucleoVerificadas`, por lo que no puede verificarse qué exige. Además, el adaptador comprueba presencia del núcleo, períodos, divisor, origen y completitud (`conversion-vendedores.ts:171–183,232–249`).

La preocupación válida es que **no se demuestra una comparación contra la foto y el neto publicados**. Eso debe probarse introduciendo una discrepancia conocida y comprobando que la sonda la detecta.

**F4 — CONFIRMADO el saldo sin período; HIPÓTESIS las dos consecuencias completas. P1 provisional.**

`ajuste_pendiente_por_vendedor()` suma todos los ajustes no saldados, sin límite temporal (`20260815002100:196–221`). La CTE mensual adjunta tampoco introduce uno (`20260904210831:1640–1647`).

Si ambos meses abiertos utilizan ese saldo para el mismo vendedor, ambos mostrarán el descuento. Sin embargo, faltan las ramas completas, los joins posteriores y la regla que permite consultar ambos meses para cerrar esa prueba.

La afirmación de que la deuda de quien sale del roster **nunca** se salda necesita el cuerpo de `cerrar_periodo` y los demás consumidores de ajustes. También debe distinguirse una doble imputación **visible** de una doble liquidación persistida: lo segundo no está demostrado.

**F5 — HIPÓTESIS. P2.**

No se adjuntó la línea 1480 ni el cuerpo de `cerrar_periodo`. La rama de lectura de la foto sí está acreditada, pero no el literal diagnóstico ni la ausencia de conservación o validación de la sonda al sellar.

Si se confirma, la corrección debe conservar el estado real de cobertura: una sonda desconocida o fallida no puede transformarse en cero incidencias.

**F6 — CONFIRMADO. P2, obligatorio corregir por contrato.**

Las divisiones están explícitas en `conversion-vendedores.ts:196,240–242,254–256,289–297`. Contradicen la regla de servir el porcentaje desde el servidor.

Lo bajaría de P1 a P2 porque la evidencia no demuestra que la aritmética produzca hoy un porcentaje incorrecto: el denominador global y el rótulo «Aporte» están definidos. El defecto demostrado es la duplicación del cálculo en el cliente. Tampoco describiría esta ruta como carente de controles: sí comprueba sondas y otras condiciones; no está acreditada una validación específica del porcentaje por fuente.

**F7 — CONFIRMADO el fallback incompatible. P1.**

`inteligencia-comercial.tsx:750–758` publica `pct(cosechaPct)` precisamente cuando existe payload pero falta `nucleo`. Esa rama sustituye la lectura canónica por otra variable sin exigir sus sondas.

Además, tiene precedencia sobre `rangoError`: un payload incompleto puede producir una cifra incluso cuando debería mostrarse indisponibilidad. Falta la asignación de `cosechaPct` para confirmar independientemente su fórmula exacta; el fallo de publicación ya queda demostrado sin ella.

**F8 — HIPÓTESIS como defecto completo de presentación. P2 provisional.**

Está confirmado que el titular puede usar rango y la barra usa mes (`resumen-gerencia.tsx:178–181,238–240`). Eso solo viola el contrato temporal si la barra no identifica claramente su período mensual; no se adjuntó el renderizado de sus rótulos.

Pasar `periodoRanking` dos veces a `semanticaMetaMensual` no demuestra que `comparable` sea siempre verdadero: falta el helper. La exclusión de Resumen de `vistaMensual` sí desactiva específicamente `fuenteMensualSellada` para esa sección (`gerencia.tsx:264,329`), pero no demuestra que ninguna otra parte de Resumen conozca el cierre.

**F9 — HIPÓTESIS. P1 si una cobertura inválida alcanza la alerta.**

El bloque `alertas-gerencia.ts:240–278` valida muestra y valores, sin una comprobación local de cobertura. Sin embargo, comienza dentro de una condición incompleta y consume `cumplimientosVendedores` ya construido.

Faltan el bloque anterior y la procedencia de esos datos para descartar que lleguen filtrados. La prueba decisiva es entregar cobertura con `cierres_sin_episodio > 0` y verificar si se publica la alerta con porcentaje.

**F10 — CONFIRMADO en Dashboard; HIPÓTESIS en el resto del alcance. P1, sin sustento para P0.**

`dashboard.js:172–178` convierte los elementos que conservan `.skeleton` en `'0'` cuando ocurre un error. Fabrica una observación válida a partir de una carga fallida. El alcance exacto son esos elementos, no necesariamente todos los KPI.

La expresión reportada de `directorio.js` efectivamente convierte `null` en cero, pero faltan sus usos para determinar qué indicadores afecta. Tampoco están adjuntos los SQL citados ni la relación de esas métricas con el índice de conversión. No daría por probado todo ese paquete a partir del fallo del Dashboard.

**F11 — HIPÓTESIS. P2.**

No se adjuntaron workflows, scripts, tests ni salidas que permitan confirmar la ausencia de gates.

Una redefinición de función no vuelve obsoleto un test por sí sola; hay que contrastar sus aserciones con el contrato vigente. Asimismo, que un archivo no contenga la palabra `conversion` no demuestra que no ejecute comprobaciones transitivas. Mantendría este hallazgo pendiente de evidencia y separado de los defectos funcionales.

**F12 — HIPÓTESIS. P1 provisional; comprobación urgente.**

Faltan los cuerpos del escritor, del trigger, del gate y de los clientes legacy, además del estado efectivo de producción. La anotación de apertura del 15/09 no prueba el comportamiento posterior a la migración del 19/09.

Tampoco puede confirmarse que las llamadas legacy sigan siendo alcanzables, que falte toda vía de anulación o que las operaciones descritas deban cerrar ese lead según el contrato de vinculación. Un bloqueo general comprobado de la conversión justificaría elevar la severidad; los extractos actuales no lo establecen.

TEST GAPS:

**Verificación ejecutada: NOT RUN.** No se ejecutaron herramientas ni se adjuntaron resultados reproducibles de los checks mencionados.

Las pruebas que más reducirían incertidumbre son:

- **Mes sellado:** comparar mensual, rango de mes completo y Distribución antes y después de una modificación que afecte al ledger. Igualar período, actor, alcance y fuentes; verificar el contrato esperado para cada lectura.
- **Ajustes:** dos meses abiertos, anulación posterior al período consultado, vendedor fuera del roster, deuda superior al numerador y cierre repetido. Verificar imputación única y conservación del saldo pendiente.
- **Publicación:** payload sin núcleo, sondas falsas o nulas y cobertura incompleta. Ningún héroe ni alerta debería sustituir la cifra por otra métrica o período. Incluir cero válido, divisor cero y porcentajes superiores a 100.
- **Escritores:** configuración efectiva y errores existentes en producción mediante lectura; reproducción de confirmación, vinculación y anulación en un entorno de prueba.
- **Gates:** mostrar qué tests ejecuta realmente CI y sus resultados contra las definiciones vigentes.

RISKS:

- **[P1] Otro fallback temporal en Resumen.** En `resumen-gerencia.tsx:178–181`, con fuente global, payload sin núcleo y carga terminada, `conversionPrincipal` pasa a `conversionMes`. Si el rango seleccionado difiere del mes, puede publicar una cifra de otro período. Este mecanismo está demostrado y es adicional al desacople entre titular y barra de F8.
- **Propagación de fallos del Dashboard.** El `catch` engloba métricas, contratos y pagos (`dashboard.js:165–178`). Un fallo de una consulta auxiliar puede fabricar ceros en indicadores cuya consulta habría sido válida.
- **Riesgo al unificar el neto.** Si el «suelo en cero» documentado en `20260904210831:1658–1665` describe la implementación, aplicar ajustes por vendedor y luego sumar no equivale a descontar la deuda total del bruto total. Por ejemplo, dos vendedores con brutos `1, 1` y deudas `2, 0` producen neto agregado `1` por filas, frente a `0` aplicando el suelo globalmente. Una corrección de F2 debe preservar la regla elegida y comprobar qué ocurre con la deuda no absorbida.

RECOMMENDED NEXT ACTIONS:

1. **Priorizaría la corrección de F7 y del fallback análogo de Resumen.** Son fallos concretos del contrato de publicación: ante la ausencia del dato canónico pueden mostrar otro significado o período. Su corrección no depende de resolver primero la política de rangos. El cero artificial de F10 merece el mismo tratamiento inmediato.
2. Comprobar urgentemente F12 con configuración efectiva, cuerpos desplegados y errores existentes. Esa evidencia decidirá si hay una interrupción operativa de mayor prioridad.
3. Resolver la asignación temporal y liquidación de ajustes de F4 antes de unificar lecturas. Después, fijar cómo deben representar los rangos los meses sellados y corregir F1/F2 conforme a ese contrato.
4. Servir los porcentajes por fuente desde el servidor; conservar cobertura y sondas en las fotos; verificar su aplicación en alertas. Incorporar las pruebas anteriores a un gate cuya ejecución quede acreditada.

CONFIDENCE: **MEDIUM.** Alta en las expresiones y bifurcaciones visibles; limitada en las afirmaciones de ausencia global, liquidación, despliegue y comportamiento de los escritores.

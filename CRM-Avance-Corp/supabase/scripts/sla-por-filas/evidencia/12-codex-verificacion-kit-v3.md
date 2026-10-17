**VERDICT: CHANGES_REQUESTED**

**SUMMARY:**

La v3 rechaza los contraejemplos ensayados, pero **todavía permite registrar una identidad distinta de la ejecutada y ocultar transiciones pendientes**. Los dos P1 anteriores están parcialmente corregidos.

Sí quedan cerrados, con la evidencia informada, el mutante Unicode, la ejecución del RLS integral y la ausencia de una medición concurrente de Gestión Diaria. Ahora existe medición directa de CPU de `estado`; eso resuelve aquella carencia experimental, aunque no demuestra cumplimiento del umbral de latencia.

No recomendaría todavía solicitar el «!» para ejecutar este kit. Los pendientes concretos están abajo. **Comprobaciones ejecutadas por mí: NOT RUN**; revisión exclusivamente de las transcripciones, sin reabrir equivalencia, cuerpos M1–M3 ni guardianes.

**FINDINGS:**

**[P1] La transición válida sigue sin identificar el evento ejecutado.**

**File:** `registrar-indice.sql`, `registrar-reversa-m3.sql`; mismo mecanismo en los otros registradores de reversa.  
**Lines:** validaciones de `v_h_estado`, `v_h_apl`, `v_h_max` y construcción de `v_texto`.

**Problem:** El historial permite identificar una transición pendiente, pero no la versión que efectivamente la produjo.

**Evidence — contraejemplos estáticos:**

1. Con M3 aplicada y registrada, ejecutar su reversa con versión **R**, sin registrarla todavía. Ejecutar después el registrador con otra versión libre **R′**, posterior al historial. Todas sus condiciones pasan: serie viva M2, historial M3 y aplicación original vigente. Inserta el texto de **R′**, aunque se ejecutó **R**. El registrador correcto de R ya no puede registrarla: ahora el historial está en M2.

   El ensayo CE2 prueba cambiar la versión **después de registrar la primera reversa**. No cubre este cambio **antes del primer registro**.

2. Con M3 original registrada:
   - ejecutar R3 y dejar su registro pendiente: historial M3, esquema M2;
   - reaplicar M3 con una versión nueva libre: el contrato transcrito de M3 permite esa aplicación desde M2;
   - ejecutar `registrar-indice.sql` original.

   El historial y las huellas vuelven a coincidir con M3 original. El registrador devuelve **«0 nuevas y 3 vigentes»**, omitiendo tanto la reversa como la reaplicación. No requiere concurrencia ni editar el historial.

**Impact:** Persiste el registro de versiones no ejecutadas y la omisión silenciosa de eventos ejecutados. La advertencia «no se acredita al 100 % qué archivo se ejecutó» describe una limitación operativa concreta, no solo una reserva teórica.

**Recommendation:** Vincular una constancia duradera de versión y contenido al commit que realiza la transición, y hacer que los registradores consuman esa evidencia. Con M1–M3 byteidénticas, cualquier mecanismo externo que aporte esa garantía debe quedar diseñado y ensayado; la máquina de estados actual no la sustituye. Añadir ambos contraejemplos.

---

**[P2] Se acepta una reversa anterior a migraciones ajenas ya aplicadas.**

**File:** `reversa-m1/m2/m3.sql` y sus registradores.  
**Lines:** consulta del historial limitada a seis nombres; comparación con `v_h_max`.

**Problem:** Se protege el orden dentro de la serie, pero no el orden del historial completo.

**Evidence:** Supóngase M3 registrada y una migración ajena X ya aplicada con versión `20261017160000`. Una R3 libre con versión `20261017150000` pasa: es posterior a `20261017054427`, que puede seguir siendo `v_h_max`.

Si X exigía M3 en su preflight, la ejecución original fue válida, pero la reproducción ascendente ejecutará R3 antes de X y esta fallará. Es un contraejemplo construido; no afirmo que esa X exista en producción.

**Impact:** La reproducción de nueve eventos acredita la serie aislada, no el orden global. El propio informe reconoce esta limitación.

**Recommendation:** Exigir versiones nuevas posteriores al máximo de **todo** el índice, antes del DDL y al registrar. Para la publicación inicial, comprobar también la posición de M1–M3 respecto del historial vigente. Crear un archivo «ahora» no sustituye esa comprobación.

---

**[P2] Una versión SQL NULL elude la validación previa de las reversas.**

**File:** `reversa-m1/m2/m3.sql`; `registrar-reversa-m1/m2/m3.sql`.  
**Lines:** `if v_esta_version !~ '^[0-9]{14}$'` y validación equivalente de `v_version`.

**Problem:** Las condiciones no rechazan explícitamente NULL.

**Evidence:** Con `v_esta_version := NULL`, la comparación regular devuelve NULL, la búsqueda de ocupación devuelve falso y `v_esta_version <= v_h_max` devuelve NULL. Ningún `IF` rechaza la entrada; con el resto de precondiciones satisfechas, la reversa confirma DDL sin una versión válida. Su registrador tampoco rechaza NULL al principio y termina intentando insertar esa versión.

**Impact:** El preflight no garantiza la identidad válida que declara exigir.

**Recommendation:** Añadir `IS NULL` a ambas validaciones y ensayar que el rechazo ocurre antes del DDL.

**TEST GAPS:**

- **Kit:** faltan los contraejemplos anteriores. Los 48 pasos informados no los cubren.
- **71 cadenas:** siguen **NOT RUN** en la evidencia aportada.
- **Transporte de `verificar.sql`:** recibir íntegro el informe P0001 demuestra su entrega, pero no la limpieza o descarte de la conexión tras quedar abortada la transacción. Falta acreditar ese comportamiento y una petición posterior correcta por la vía exacta. La evidencia de v1 citada en el LEEME no demuestra ese segundo punto.

**RISKS / RESPUESTAS A Q1–Q4:**

**Q1 — Correcciones aceptadas.** La protección previa contra versiones ocupadas, el orden R3 < R2 < R1 y el rechazo de la reversa cuando falta registrar su aplicación están implementados. La reproducción informada respalda el ciclo normal. El mutante Unicode aportado queda cerrado mediante el rechazo conservador de `U&"`; permanece el límite documentado del SQL dinámico.

**Acepto que `v_exigidas_ok` informe sin bloquear en los registradores de reversa.** Es coherente con lo que la reversa permite confirmar y evita impedir después su registro por una condición que no era precondición del DDL. El aviso debe conservarse, y el éxito del registro no debe interpretarse como validación del funcionamiento del servicio.

**Q2 — RLS: pendiente de ejecución cerrado.** Lo clasificaría como **PASS diferencial y FAIL global por los mismos 15 fallos**, con `testSlaPorFilas` pasando 36/36 y M3 exigida.

Comparar `antes-3` con `despues-1` es razonable para el estado con residuos descrito; los controles A/A respaldan esa elección. El 14 → 15 de la primera repetición no invalida automáticamente el contraste posterior. También quedan atendidas las comprobaciones antes potencialmente vacías: se informan conjuntos positivos y fixtures dentro de la página examinada.

Una reserva metodológica: normalizar **todas las cifras** puede ocultar diferencias en identificadores o detalles de fallos. La comparación debe conservar identidad y multiplicidad de las aserciones; los mensajes numéricos normalizados, por sí solos, no prueban identidad completa. Esto no convierte nuevamente la batería ejecutada en NOT RUN.

**Q3 — CPU: retiro la objeción de ausencia de medición bajo concurrencia.** La sonda dedicada mide precisamente el recurso que faltaba. Para el vendedor, argumento `'{}'` y escenario medido, respalda una diferencia pequeña no detectada con precisión suficiente para distinguirla de cero.

No permite afirmar igualdad: el IC superior de +0,43 ms admite aproximadamente **+13 % sobre 3,3 ms**. Tampoco demuestra que el p95 del pool empeore menos del 10 %. Que un intervalo contenga cero significa incertidumbre sobre el efecto, no equivalencia.

Además, la tanda de las 15:10 **añade una sonda en bucle**: no es una repetición exacta de la carga de las 12:57. Sus resultados y los controles sí acreditan variabilidad considerable, pero no sustituyen el NO PASA original.

Hay dos salidas legítimas:

- **Aceptación informada del propietario:** puede autorizar una excepción al criterio de latencia, conservando los NO PASA y su incertidumbre. No exigiría otra medición de CPU para presentar esa decisión.
- **Despejar técnicamente la regresión de latencia:** ejecutar la carga normal, sin sonda adicional, con interferencia externa controlada, orden A/B contrabalanceado y réplicas independientes suficientes. Para recomendar cumplimiento robusto del margen, buscaría un límite superior del IC del cociente de p95 **≤ 1,10**, en las mezclas exigidas. Fijar previamente el diseño y la regla de parada; no repetir hasta obtener un PASA.

**Q4 — Gestión Diaria: no añade un bloqueo independiente.** En esta comparación hay el mismo número de llamadas y cero cortes: la reducción de temporales totales del 27 % resulta interpretable sin el sesgo de llamadas completadas del escenario «peor». Memoria y p95 de Gestión Diaria también mejoran.

Su aumento propio de temporales es real y debe acompañar la decisión: aproximadamente **+5,2 MiB por llamada en la mezcla y +10,2 MiB para gerencia sola**. Es un coste aceptable conscientemente con esta evidencia; Fase 4 es trabajo posterior, no una mejora ya obtenida. El NO PASA de `estado` sigue sujeto a la decisión anterior.

**RECOMMENDED NEXT ACTIONS:**

1. Corregir la vinculación del evento, el orden global y NULL; ejecutar los contraejemplos y repetir la reproducción afectada.
2. Completar las 71 cadenas y cerrar la evidencia del transporte tras P0001.
3. Integrar el `avancecorp/main` vigente —el adjunto 5 aún informa que la rama está detrás— y dejar identificados commit y artefactos finales verificados.
4. Entonces solicitar el «!» con una decisión explícita sobre la excepción de latencia, mostrando **FAIL global RLS preexistente**, **PASS diferencial**, los **NO PASA de carga** y el coste adicional de Gestión Diaria. Mantener la aplicación de una migración cada vez, verificación y registro; no avanzar con un evento pendiente.

**CONFIDENCE:**

**HIGH** en los contraejemplos estáticos de los registradores y la validación NULL. **MEDIUM** en las conclusiones experimentales: se basan en informes transcritos, sin inspección de datos crudos ni ejecución propia.

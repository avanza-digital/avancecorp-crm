# Respuesta de Codex (28/09) — validación de cifras de Citas (equipo de Jorge)

Encargo: `2026-09-28-codex-citas-cifras-jorge.md`. Veredicto CHANGES_REQUESTED sobre la PRESENTACIÓN de la conclusión, no sobre las cifras: confirma fórmula y conciliación (160 − 71 + 3 = 92; 37/92 = 40,2 %).

**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

La lectura de la fórmula es correcta con la configuración vigente:

- `registradas`: creación dentro del periodo, atribución a `c.analista`, procedente de `tareas.vendedor_id`.
- `resueltas`: asistencia registrada para realizadas; fecha prevista para `no_show`.
- Con `mes_resultado = evento`, el resultado debe pertenecer a septiembre y no superar `min(corte, fin de mes)`.
- Con `actividad_real` y `citas_realizadas`, la tasa es `visitas.length / resultado.length`.

La conciliación también cuadra: **160 − 71 + 3 = 92; 37 / 92 = 40,2 %**. Son indicadores de poblaciones temporales distintas, conforme a la regla de negocio transcrita.

Lo que necesita corrección es presentar esto como una equivalencia plenamente demostrada con la sesión de Miguel. La reproducción aportada deja condiciones sin verificar y la presentación del total oculta precisamente el divisor que explica su duda.

El perfil de pruebas **sí aporta una de las 160 citas**. Excluyendo únicamente su actividad atribuida, quedarían **159 citas, 37 entrevistas y 40,2 %**; aporta cero al divisor 92.

**FINDINGS**

**[P2] La equivalencia del SQL manual con la pantalla está incompletamente acreditada**

Evidencia: `avance.ts` exige `personas.has(c.leadId)`, construye `personas` mediante `coincidePersona(...)` y aplica `ambito(...)`. El SQL transcrito selecciona reuniones de leads activos mediante un subárbol recursivo.

Hay diferencias que requieren comprobación:

- **Población y filtros:** no se adjunta el cuerpo de `coincidePersona`, el conjunto efectivo de `datos.poblacion` ni los filtros de la sesión. Un lead activo no demuestra por sí solo pertenencia a esa población filtrada.
- **Ámbito:** el filtro de supervisor usa `roster.get(id)?.supervisorId === filtros.equipo`; el SQL recorre descendientes e incluye a Jorge. Tampoco se transcribe `private.vendedor_ids_visibles(uid)` para demostrar equivalencia con ese recorrido.
- **Estado:** la RPC obtiene `estado_comercial` desde `private.citas_episodios`; el conteo directo usa `t.estado`. Faltan esa función y la transformación a `CitaEjemplo` para comprobar que ambos clasifican exactamente las mismas tareas.
- **Corte:** `historial` exige `t.creado_en <= v_ahora` para todas las citas. El SQL manual aplica ese límite al contador de citas, pero no a entrevistas y ausencias. Además, varios `now()` de consultas separadas no acreditan el mismo `generado_en` que vio Miguel.

Con la configuración aportada, `owner` sí se reduce a `c.analista`, y `actividad_manuales = incluir` elimina la exclusión por alta manual; **permanece el requisito de pertenecer a `personas`**. El límite de fin de mes tampoco introduce una diferencia el 28/09.

Estas omisiones están demostradas; **que alteren los números actuales es una hipótesis**, no un fallo probado.

Además, el encabezado «Variantes probadas — ninguna reproduce» contradice «Por dueño del lead […] sigue 160/92/37». Esa variante sí reproduce los agregados: la coincidencia numérica no discrimina entre ambas atribuciones.

Recomendación: comparar los conjuntos de IDs con un payload autorizado, su corte y sus filtros exactos. Adjuntar también la segunda reproducción del lector, actualmente solo descrita.

**[P2] El total no permite comprobar visualmente la tasa**

Evidencia: `avance-mensual.tsx:31` muestra el porcentaje y «37 entrevistas» junto a la columna de 160 citas. El detalle `:54` revela `baseEntrevistas`, pero el pie `:108` carece de apertura de detalle; el CSV tampoco exporta el divisor, según el encargo.

Mostrar ambos indicadores es coherente. **La ambigüedad es de presentación:** el usuario tiene a la vista un numerador y otro conteo de citas, pero no las 92 utilizadas para dividir. La ayuda explica la regla, aunque no permite conciliar ese total concreto.

Severidad **P2**: produce una interpretación equivocada de un indicador de gestión y ya motivó una consulta del dueño.

Recomendación concreta: exponer en el total «37 entrevistas / 92 citas con resultado».

También debe evitarse llamar a `37/160` la conversión de las citas creadas en septiembre: dos de esas entrevistas pertenecen a citas creadas en agosto. Para esa cohorte, los datos aportados indican **35/160 = 21,9 %**, que sería otro indicador.

**[P2] El “no asistió” futuro requiere investigación del registro; no demuestra un error de la fórmula**

Evidencia: `53b4ac59`, prevista para el 30/09, quedó marcada como inasistencia el 23/09. En `avance.ts`, `fechaResultado` usa la fecha prevista para `no_show`, y el límite temporal la excluye hasta entonces. La ayuda declara expresamente ese criterio.

Está acreditada la discordancia entre el momento del registro de inasistencia y la cita prevista. **No está acreditado qué flujo la produjo**, ni que el desplazamiento «+7 días» sea automático. Son hipótesis una fecha incorrecta, un cierre aplicado a la nueva cita al reprogramar o una validación insuficiente.

El cálculo sigue la regla documentada. Cambiarlo a la fecha de marcación modificaría esa regla y la atribución mensual.

La predicción **37/93 = 39,8 %** es correcta **si permanecen iguales los demás datos, estados, filtros y configuración**. No debe comunicarse como un resultado futuro garantizado.

Recomendación: reconstruir la secuencia de `4f73735d` y `53b4ac59`, incluyendo actividades de cierre y tareas a las que quedaron vinculadas.

**[P3] La opción `personas_unicas` tiene una discrepancia explicativa verificable**

Evidencia: `avance.ts` calcula `nEntrevistas = gente.size` bajo esa opción, pero devuelve siempre `entrevistas: visitas.length`. El detalle `avance-mensual.tsx:54` imprime `fila.entrevistas / fila.baseEntrevistas`.

Con los datos aportados, al activar esa opción la tasa sería **29/92 = 31,5 %**, mientras el detalle seguiría mostrando **37 entrevistas / 92 citas con resultado**.

Es una inconsistencia condicional del texto explicativo, **inactiva en la configuración actual**. Conviene incluirla en la prueba de esa alternativa; no explica el 40,2 % observado.

**TEST GAPS**

- **NOT RUN:** no ejecuté SQL, RPC ni tests; esta revisión utiliza exclusivamente la transcripción.
- La ausencia de tests de `no_show`, `meta_proyectada` y `personas_unicas` es una afirmación del PRIMARY: no se adjunta inventario o código de tests para confirmarla.
- Sí está demostrado que `testigoCuadra` **no compara citas registradas, citas resueltas ni la tasa**. Puede coincidir en 37 entrevistas aunque el divisor sea incorrecto. Además, según el encargo, el supervisor no recibe testigo.
- Faltan evidencias de pruebas que cubran el cruce de cohortes —citas de agosto con resultado en septiembre— y el `no_show` futuro al cruzar el corte al minuto.
- La comparación con la pantalla debe verificar también la clasificación canónica y los filtros de población, no únicamente tres totales.

Para distinguir reutilización técnica de asistencias, este SELECT puede sustituir al SELECT final del CTE `t` aportado; para reproducir la captura original, todos los `now()` deben sustituirse por su mismo corte:

```sql
select lead_id, resultado_actividad_id,
       count(*) as citas,
       array_agg(id order by id) as tareas
from t
where estado = 'completada'
  and creado_en <= now()
  and asistio_en >= timestamptz '2026-09-01 00:00-05'
  and asistio_en <  timestamptz '2026-10-01 00:00-05'
  and asistio_en <= now()
group by lead_id, resultado_actividad_id
having count(*) > 1;
```

Un resultado demostraría que varias tareas contabilizadas comparten el mismo registro acreditativo de asistencia. Cero filas descartaría ese mecanismo concreto, pero **no descartaría actividades duplicadas con IDs distintos**.

Para los cinco leads repetidos, comparar además IDs de tarea y actividad, `reagendada_de`, fechas de creación, asistencia y cita, y notas de cierre. La existencia de asistencias físicas distintas necesita corroboración operativa; IDs distintos no bastan.

**REGRESSION RISKS**

- Las asistencias del 23/09 para citas previstas el 24 y 25 son compatibles con reuniones adelantadas. El código no exige asistencia posterior a la fecha prevista. Tampoco las entrevistas en días consecutivos prueban duplicación. Deduplicar por lead rompería la regla expresa de contar asistencias repetidas.
- Las 25 vencidas representan resultados pendientes, no ausencias confirmadas. Los escenarios 31,6 % y 53,0 % requieren mantener lo demás constante; alcanzar el segundo exige registrar las 25 entrevistas dentro de septiembre. Una asistencia registrada en octubre correspondería a octubre.
- Usar la fecha prevista para todas las entrevistas cambiaría el resultado a los **36/91 = 39,6 %** aportados, alterando la regla vigente de asistencia registrada.

**RECOMMENDED NEXT ACTIONS**

1. Mantener la explicación matemática, pero distinguir «cuadra con la regla» de «se reprodujo exactamente la sesión».
2. Cerrar la comparación mediante payload, filtros, corte e IDs; corregir la afirmación sobre las variantes.
3. Explicitar el divisor 92 en la explicación a Miguel y registrar la limitación de presentación del total.
4. Investigar la inasistencia futura y comprobar las asistencias repetidas antes de calificarlas como duplicados.

**CONFIDENCE: MEDIUM**

Alta en la fórmula y en la ambigüedad de presentación; media en la equivalencia exacta con producción y en las causas de las anomalías.

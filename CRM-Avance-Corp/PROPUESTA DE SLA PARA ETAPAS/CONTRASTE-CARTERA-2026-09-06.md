# Contraste de SLA con la cartera existente

**El cálculo del núcleo coincide con las reglas aprobadas sobre la cartera real. La activación conjunta es una opción viable, pero todavía exige completar las escrituras, la reconstrucción del contexto y la integración de las listas.** El contraste no activó ni modificó producción.

Corte único: **6 de septiembre de 2026, 21:22:34, hora de Lima** (`2026-09-07T02:22:34.784820Z`). Se leyeron 1.157 leads activos: 827 oportunidades abiertas y 330 terminales —35 convertidas y 295 descartadas—. Los terminales no reciben acciones de contacto. No hay vetos en esta foto; se consultó el núcleo canónico de veto para cada lead.

| Etapa | Oportunidades | Seguimiento pendiente | Cubiertas por compromiso | Revisión comercial |
|---|---:|---:|---:|---:|
| Nuevo | 272 | 242 | 27 | 245 |
| Contactado | 418 | 255 | 119 | 175 |
| Reunión agendada | 98 | 28 | 61 | 23 |
| Propuesta enviada | 39 | 2 | 22 | 12 |
| **Total** | **827** | **527** | **229** | **455** |

Las columnas son señales que se solapan; no deben sumarse. Las 455 revisiones incluyen tres leads sin analista, que se presentan para reparto y no como incumplimiento de un analista. Hay 824 abiertos con evaluación completa y esos tres con evaluación parcial por falta de asignación.

Comercialmente, el sistema hará visible una carga importante desde el primer día: 527 seguimientos pendientes y 455 oportunidades para revisión. Esto no ordena descartarlas o reasignarlas. Supervisor/Gerencia debe decidir qué hacer con cada oportunidad. La regla no exige cambiar los plazos aprobados a partir de este resultado; sí exige que la bandeja permita gestionar toda esa carga.

También hay 342 oportunidades con primera atención pendiente, todas vencidas al corte, y 457 con al menos una tarea de agenda vencida. Son señales adicionales, solapadas con las anteriores. Las 537 tareas vencidas de estas oportunidades pertenecen a esos 457 leads: contar tareas como si fueran leads inflaría la carga. En todo el sistema hay una tarea pendiente adicional sin lead, vencida, excluida del dominio de oportunidades.

**La reconstrucción previa sí es necesaria y está respaldada por los datos.** Las 831 tareas pendientes vinculadas a oportunidades abiertas tienen creación humana comprobada en auditoría, fecha dentro del ciclo actual, ciclo no aproximado, tenencia coherente y ausencia de barreras posteriores de cancelación. Son 826 tareas comerciales —516 llamadas, 271 WhatsApp y 39 reuniones— y cinco administrativas. La reconstrucción local conservó autores, fechas, estados e historial.

| Resultado del nuevo núcleo | Sin reconstruir contexto | Con reconstrucción demostrada |
|---|---:|---:|
| Seguimientos pendientes | 629 | 527 |
| Coberturas reconocidas | 0 | 229 |
| Abiertos con datos incompletos | 725 | 3 |
| Revisiones confirmadas | 409 | 455 |
| Revisión no evaluable en abiertos | 382 | 0 |

Esta comparación representa dos entradas al núcleo N1; no compara dos versiones de las pantallas actuales. Reconstruir evita **102 avisos de seguimiento de más** y permite resolver revisiones antes desconocidas. No sería correcto activar omitiendo este paso ni rellenar indiscriminadamente el ciclo actual de cualquier tarea futura. La evidencia de este corte permite reconstruir las 831; las nuevas tareas deben capturar el contexto dentro de su transacción.

**Se respetaron los plazos históricos.** Hay 262 etapas abiertas con política v4 y 565 con v5. La v4 conserva bases 1/3/5/7 días; la v5 tiene 1/8/15/20. Para episodios históricos sin anexo, el techo es el límite original más el extra fijo de adopción aprobado: +2/+8/+3/+7 días, respectivamente. Por ello los topes totales de v4 son 3/11/8/14 días y los de v5 3/16/18/27. No se reescribieron las bases antiguas como si siempre hubieran tenido la política nueva.

492 oportunidades superan su límite original. En 51, un compromiso válido amplía el límite operativo, de modo que el agotamiento operativo se reduce a 441. Otras 14 requieren revisión por reingresos aun sin agotar ese límite: total 455. Dentro del conjunto hay 19 con tercer ingreso o superior y seis con tercera reprogramación o superior; estos seis ya están entre los vencidos. 372 superan incluso su techo, por lo que una tarea futura no puede volver a cubrirlos.

No se concedieron prórrogas retrospectivas. El stock conserva cero ajustes; la regla de futuras prórrogas se valida en pruebas, y su writer sigue pendiente. En las cadenas de reuniones, 15 tareas provienen de `no_show` y una de `reprogramada`; contar todos esos enlaces como reprogramaciones sería incorrecto. Se utilizó el contador persistido.

**Casos comprobados en la foto**, identificados por seudónimos:

- L-73, Reunión agendada: llamada vencida el 5/9 a las 11:00 Lima. Su margen cubre hasta el 7/9 a las 11:00. La agenda continúa vencida y el seguimiento queda cubierto. Hay 14 oportunidades con tarea vencida y cobertura vigente.
- L-10, Nuevo: tiene llamada futura el 7/9 a las 11:00, pero agotó su techo el 5/9. Conserva seguimiento y revisión pendientes.
- L-7, Reunión agendada: sexto ingreso a esa etapa en el mismo ciclo. Requiere revisión aunque su plazo todavía no se agote.
- L-81, Nuevo: cuatro reprogramaciones del WhatsApp elegido. El compromiso no cubre.
- L-3, Contactado: la llamada futura cubre seguimiento, pero no borra el primer contacto pendiente del analista. Hay 56 oportunidades con cobertura y primera atención pendiente.

Se revisaron además L-1024 y L-1119, donde el ciclo registra conversación pero el hito del analista está vacío. Es coherente con el writer vigente: la conversación la hizo Gerencia o el supervisor. Cuenta para seguimiento del lead; no se atribuye al analista como un hito propio. No se corrigieron como supuestos datos malos.

**Fallos y ajustes derivados del contraste.**

1. Corregido en N1: primera atención podía usar plazos de una asignación ajena al ciclo o responsable actual. Ahora ignora esos hitos y mantiene las deudas válidas del ciclo. Se añadieron dos regresiones; pasan 44/44 pruebas. Ningún lead de esta foto tenía esa incoherencia.
2. Incorporado al plan, implementación pendiente: la lectura de cola necesita filtros por señales y paginación. Hay 342 primeras atenciones frente a un máximo actual de 200 elementos, sin cursor. Además, 455 leads requieren revisión, pero solo 18 tienen `revision_comercial` como acción dominante. Filtrar únicamente por ese bucket ocultaría los otros casos. El [contrato de lectura a completar](AJUSTE-LECTURA-COLA-TRAS-CONTRASTE.md) exige resolverlo dentro del mismo núcleo SLA.
3. Confirmado como paso obligatorio previo: reconstruir el contexto demostrado del stock y capturarlo en cada nueva tarea. La simulación local no instala esa captura en producción.

Si nadie gestiona, cancela, completa o reprograma, el mismo stock evoluciona así. Es una prueba de sensibilidad, no un pronóstico de actividad del equipo:

| Reloj de la simulación | Seguimiento pendiente | Cobertura vigente | Revisión |
|---|---:|---:|---:|
| Corte inicial | 527 | 229 | 455 |
| +24 horas | 612 | 183 | 489 |
| +72 horas | 750 | 70 | 571 |

La primera activación permanece fija en el corte inicial; no se mueve el período de gracia al avanzar el reloj. Los plazos son corridos, como se aprobó.

**Verificación y límites.** Se extrajeron los hechos minimizados mediante una única consulta de lectura y se aplicó la migración N1 real en PostgreSQL 17.10 local; origen PostgreSQL 17.6. Un cálculo independiente comparó 18.698 valores por lead/campo: cero discrepancias. La proyección v1 mantuvo exactamente sus 1.157 filas antes/después de N1. Los escenarios estricto y basado solo en fecha coinciden en esta foto porque toda la evidencia de las pendientes pudo corroborarse.

La consulta completa del núcleo tardó aproximadamente 155 ms en `EXPLAIN ANALYZE` local. No acredita latencia ni concurrencia en Supabase: se usó el esquema reducido de contratos y dobles explícitos de identidad/ámbito; el veto sí reproduce el resultado canónico extraído. Ambos bancos quedaron detenidos. No se modificó producción, no se desplegó, ni se activó el módulo.

La evidencia respalda continuar con los plazos aprobados y preparar una activación conjunta. Se retira la exigencia previa de una jornada en observación, según la preferencia del usuario. Antes de activar quedan configuración versionada, captura/reconstrucción transaccional, writer de prórrogas y recibos/locks, filtros/paginación, pantallas y pruebas completas de integración y permisos. **No hace falta otro núcleo de cálculo comercial: estas piezas deben consumir y completar el núcleo SLA existente.**

Evidencia reproducible: [agregados y casos](../supabase/tests/sla-nucleo/contraste-cartera-2026-09-07.json), [paridad independiente](../supabase/tests/sla-nucleo/paridad-cartera-2026-09-07.json), [44 pruebas del núcleo](../supabase/tests/sla-nucleo/resultados-2026-09-07.json), [consulta de extracción](../supabase/tests/sla-nucleo/extraer-contraste-cartera.sql), [simulador local](../supabase/scripts/contrastar-sla-cartera-local.py) y [oráculo de prueba](../supabase/tests/sla-nucleo/oraculo-cartera.py). Los datos minimizados y resultados por UUID permanecen en el directorio temporal privado; los artefactos del repositorio no incluyen nombres ni datos de contacto.

Huella de la foto: `065e5496946dda8d5e50f06a4c9341327c545fce6c4f2844f7b0a6032ee0b5a2`. SQL N1 probado: `33d904a80f5eea0a94c7b3abf355827b1eec48b57a46776d9901989236f08d8f`.

codex
**VERDICT: BLOCK**

**SUMMARY**

Confirmo los oráculos de existencia y el acceso de gerencia a llamadas de leads borrados. Además, encuentro carreras en la revocación del latido, las ventanas del contador y la autorización durante una reasignación.

No encuentro una fuga persistente de identidad por `set_config`, ni un bypass mediante el GUC de purga accesible desde las puertas transcritas. Las escrituras de ingesta en bandejas ajenas están expresamente autorizadas por el negocio.

Revisión estática: pruebas **NOT RUN**. La aplicación limpia en Docker es evidencia aportada, no verificación de estos comportamientos.

Para abreviar las citas: **D** = migración `20261001145242…datos.sql`; **N** = `20261001160219…nucleo.sql`; **I** = `20261001212258…ingesta.sql`; **E** = `20261001222431…elegibilidad_dueno.sql`; **H** = `handler.ts`.

**FINDINGS P0–P3**

1. **P2 — A-P2-1 confirmado: el conflicto revela existencia; ocultarlo solamente en la Edge deja otros oráculos.**

   `E:141–149` compara el contenido únicamente cuando existe un evento guardado y lanza `P0409`. El número sin lead retorna sin guardar identidad (`E:187–190`). La Edge distingue ambos resultados mediante 409/202 (`H:129,141`).

   Además, el contador se incrementa antes de invocar el núcleo, pero el conflicto escapa de la RPC y revierte la transacción (`I:308–315`). Si únicamente se transforma ese error en 202 en la Edge, **el conflicto sigue sin consumir cupo**, mientras que el ignorado sí consume. Se puede distinguir agotando el límite; supervisión también dispone de `envios_hoy` y `ultimo_envio_en` (`I:278–282`).

   Confirmo igualmente el ataque compuesto con `(X, número_prueba)` seguido de `(X, lead_propio)`: la aparición en la bandeja depende de que el primer envío haya sido ignorado.

2. **P2 — A-P2-2 confirmado y ampliado: gerencia puede leer y modificar llamadas de leads soft-borrados.**

   La primera alternativa de `llamada_celular_visible` concede acceso a gerencia sin comprobar `lead.activo` (`N:137–142`). Las bandejas incorporan nombre y número sin otro filtro de actividad (`N:653–663`; `I:239–246`).

   El mismo helper autoriza `descartar` (`N:488–504`) y `enlazar` (`N:405–458`), por lo que el defecto también permite escrituras sobre esas llamadas.

   La corrección debe estar en el predicado compartido: para cualquier llamada con lead, exigir ámbito sobre un **lead activo**, incluida gerencia. Filtrar únicamente las bandejas dejaría abiertos detalle y operaciones.

3. **P2 — Nuevo: el latido puede confirmarse después del cierre o baja que debía invalidarlo.**

   `registrar_salud_celular_servicio` resuelve la credencial una vez y después consume cupo y escribe salud, sin bloquear ni revalidar la asignación (`I:330–336`). El contador puede esperar en su `FOR UPDATE` (`I:159`).

   Intercalado: resolver credencial → esperar contador → otra transacción cierra la asignación → continuar y guardar el latido. La respuesta será 200. La ingesta de llamadas sí dispone de una comprobación posterior bajo `FOR SHARE` (`E:129–133`).

   También hay una variante en llamadas: si el cupo está agotado, puede producirse 429 **antes** de alcanzar esa revalidación (`I:308–310`). Ambas puertas necesitan un criterio común de bloqueo y autorización anterior al límite.

4. **P2 — Nuevo: el contador puede retroceder de ventana y reiniciar cupos bajo concurrencia.**

   `v_ahora`, `v_minuto` y `v_dia` utilizan `now()`, que representa el inicio de la transacción, y se calculan antes del bloqueo (`I:150–159`). Cualquier desigualdad de ventana reinicia el contador, incluso cuando la ventana solicitada es anterior (`I:161–177`).

   Una transacción antigua que se ejecute después de otra del minuto siguiente puede sobrescribir la ventana nueva con la antigua. La siguiente petición vuelve a reiniciarla. El mismo problema existe al cambiar el día de Lima.

   El bloqueo evita incrementos perdidos dentro de una misma ventana; **no evita este retroceso**. Calcular una única hora real con `clock_timestamp()` después de adquirir el bloqueo y derivar ambas ventanas de ella.

5. **P2 — Nuevo: bloquear el evento no protege la autorización frente a una reasignación del lead.**

   `descartar` bloquea el evento, comprueba visibilidad y posteriormente escribe (`N:488–504`). No bloquea el lead que contiene la asignación utilizada para autorizar. Lo mismo sucede al asociar (`N:358–381`) y enlazar (`N:405–458`).

   El código permite este intercalado: A obtiene autorización → el lead se reasigna a B → A modifica la llamada. Para garantizar la decisión 7 durante la operación, hace falta coordinarse con las escrituras de asignación mediante un bloqueo apropiado del lead y una revalidación bajo ese bloqueo.

   La ausencia de esa protección está en el código; falta reproducir el intercalado contra los triggers reales de reasignación.

6. **P2 — A-P3-2 confirmado: la fuga de ambiguas supera el contador mostrado.**

   La ingesta guarda el número global de candidatos (`E:180–183`); una llamada sin lead resulta visible para quien llamó (`N:140–141`), y el detalle devuelve `calidad` (`N:688–694`).

   **Eliminar `calidad.candidatos` no basta** si la garantía incluye lo observable con la sesión del analista: la aparición de una llamada marcada `ambiguo` ya revela que existen múltiples leads activos con ese teléfono, aunque todos sean ajenos.

   La resolución global y la información mostrada al analista deben respetar su ámbito. Elevo este hallazgo de P3 a P2 por tratarse de información de leads ajenos.

7. **P3 — A-P3-6 confirmado: el identificador permite conservar un teléfono fuera de su retención.**

   `evento_origen_id` admite un teléfono completo (`D:237–239`; `E:99–101`). El trigger de auditoría solo solicita enmascarar `numero_canonico` y `hash_payload` (`D:398–400`).

   Por tanto, un identificador construido con el teléfono puede terminar conservado en la auditoría. Este problema también afecta a la propuesta de «lápidas sin número»: el identificador recibido no garantiza esa propiedad. Generar identificadores opacos independientes del teléfono y excluir el identificador original de la auditoría.

Los restantes hallazgos previos quedan así:

| Hallazgo | Evaluación |
|---|---|
| **A-P2-4** | **Refutado como fallo actual.** La definición aportada de `auth.uid()` sí prioriza `request.jwt.claim.sub`. Un precheck de comportamiento evita depender silenciosamente de que siga haciéndolo. |
| **A-P3-1** | **Confirmado como riesgo de abuso.** La purga no incluye identificados pendientes (`D:528–544`). Sin embargo, esto no contradice la retención ratificada, que solo exige caducar descartados y ambiguos sin resolver. |
| **A-P3-3** | **Confirmado como deuda**, sin divergencia de autorización demostrada: ambas bandejas reutilizan `llamada_celular_visible` (`N:644–667`; `I:231–267`). |
| **A-P3-4** | **Confirmado condicionalmente.** Sin política, las comparaciones con NULL dejan pasar (`I:156–175`). No encuentro una vía API para eliminar esa fila: está sembrada, protegida contra DELETE/TRUNCATE y sin grants (`D:121–152`). Añadir rechazo explícito si falta. |

**RIESGOS y test gaps**

**Identidad temporal y excepciones.** En la ruta normal, el helper restaura el valor anterior antes de insertar el evento (`E:48–55,178–193`). Las dependencias transcritas utilizadas durante la suplantación solo leen.

Si la evaluación lanza y la excepción alcanza un bloque `EXCEPTION` exterior que contiene la invocación, PostgreSQL revierte la subtransacción, incluidos sus cambios de GUC. Ese es el caso del bloque de servicio (`I:309–314`). Si el error continúa propagándose, se revierte la transacción. `set_config(..., true)` tampoco persiste en otra transacción. Restaurar NULL como cadena vacía conserva el comportamiento de la definición aportada de `auth.uid()`.

No encuentro aquí un defecto de identidad. Falta probar éxito y excepción capturada, con identidad inicial ausente, presente y obtenida desde `request.jwt.claims`, comprobando también la auditoría posterior.

**GUC de purga.** Un GUC personalizado no es una credencial: quien disponga de ejecución SQL podría fijarlo. Pero eso no concede DELETE ni EXECUTE sobre la purga. Las tablas y la función están revocadas para la API (`D:305–306,552`), y el GUC solo abre la rama DELETE del candado (`D:328–349`). No encuentro una puerta transcrita que permita explotarlo. `pg_trigger_depth()>1` tampoco demuestra por sí solo una cascada, aunque aquí no hay una ruta API para instalar o ejecutar otro trigger que aproveche esa excepción.

**Idempotencia y rotación.** Para eventos guardados, el contador serializa los envíos de una misma asignación y la unicidad protege el origen (`I:159–178`; `D:288`; `E:203–216`). El `FOR SHARE` de la ingesta se coordina con el cierre/rotación mediante `FOR UPDATE`: una vez adquirido, el cierre espera; si el cierre ganó, la ingesta revalida y rechaza. Las excepciones son las descritas en el hallazgo 3.

La rotación crea otra asignación (`N:601–607`): cambia tanto el ámbito de idempotencia como el contador. Reenviar el mismo origen con la clave nueva puede crear otro evento. Es una consecuencia del diseño que debe probarse con la cola durable.

**Edge.** El límite de 4096 bytes se aplica al flujo recibido, sin depender de `Content-Length` (`H:79–90`). El campo `abrir` solo reproduce información enviada por el cliente; no revela una coincidencia.

El 401 uniforme se cumple para solicitudes bien formadas, salvo las carreras indicadas. Con cuerpo inválido, una clave de forma válida pero desconocida recibe 400/413 antes de autenticarse, mientras que una clave ausente recibe 401 (`H:109–122`). Esto distingue forma sintáctica, no existencia de leads. Además, `Date.parse` no constituye un contrato estricto de fecha ni aplica el rango de la base (`H:39`; `E:124–125`).

Las pruebas prioritarias, todas **NOT RUN** en esta revisión, son:

- Comparar secuencias idénticas cambiando únicamente la existencia de un lead ajeno: respuestas, cupo, salud y bandeja.
- Ejecutar carreras con barreras entre autenticación/cierre, autorización/reasignación y ventanas del contador, incluido medianoche de Lima.
- Repetir eventos ignorados, guardados y purgados; incluir envíos concurrentes con contenido distinto.
- Verificar restauración de identidad y actor de auditoría tras éxito y excepciones.
- Comprobar aislamiento por rol y lead activo/inactivo, más cuerpos de 4096/4097 bytes enviados por fragmentos.

**NEXT ACTIONS**

La corrección mínima del oráculo necesita estas propiedades conjuntamente:

1. **Registrar una recepción única para todo origen aceptado**, antes de consultar leads, incluidas llamadas ignoradas y entrantes apagadas. Reservarla atómicamente por `(asignacion_id, evento_origen_id)`.
2. **Aplicar “primer envío gana” a todos los casos.** Los duplicados y conflictos deben terminar normalmente en la base y compartir el 202 externo. El contador y `ultimo_envio_en` deben confirmarse con el mismo criterio para todos.
3. **Conservar esa identidad mientras pueda reutilizarse la credencial.** Purgar un evento no debe liberar su origen. Expirar únicamente las lápidas de ignorados reabriría el ataque compuesto. No guardar número ni hash del payload de los ignorados.
4. Corregir el predicado de leads activos, la autorización del latido, el reloj del contador y la coordinación con reasignaciones. Resolver también la exposición global de ambiguas.
5. Ejecutar los casos anteriores antes de aplicar.

Esto cierra los oráculos deterministas descritos. **No acredita indistinguibilidad temporal:** el primer envío todavía realiza trabajo diferente según las coincidencias y escrituras. Hay que medirlo; si #12 exige ocultar también ese canal, el acuse debe desacoplarse del procesamiento dependiente del lead, con un diseño compatible con la regla de no conservar números sin identificar.

**CONFIDENCE**

Alta en los oráculos, el acceso a soft-borrados y el análisis del GUC. Media en la incidencia práctica de las carreras hasta reproducirlas con los triggers y aislamiento reales.

**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

El plan puede incorporar las llamadas a clientes, pero todavía no cierra cuatro puntos: el contrato de autorización del DEFINER, su protección mediante el gate, la identidad usada para contar personas distintas y la cobertura del camino legado.

Las invariantes horarias sí se mantienen. No hay evidencia suficiente para afirmar una fuga de datos ni un doble conteo efectivo en producción. Tampoco para garantizar que los cortes reconocidos permanezcan intactos.

Las referencias SQL siguientes corresponden a archivos bajo `supabase/migrations/`.

**RESPUESTA P1. Sí, añade una capacidad interna de lectura privilegiada; su equivalencia de permisos no está demostrada.**

`gestiones_clientes_eventos` ya lee esos cierres mediante DEFINER, limita autores con `vendedor_ids_visibles` y comprueba la bandera. Por tanto, **no está demostrado que el nuevo ayudante amplíe el universo histórico autorizado por autor**. Sin embargo, aquel lector también ejecuta `gestiones_validar`, cuyo cuerpo no está transcrito, y utiliza una resolución de identidades que condiciona la entrega de detalles y del identificador de tarea (`20261006012208_crm_gestiones_clientes_supervision.sql:84–105,129–143`).

Limitar autores **no equivale a reproducir la RLS de tareas**: existe una restricción adicional por `postventa_visible` (`20260910150039_crm_f6_postventa_persona.sql:121–122`). El DEFINER la evita.

Hay que distinguir:

- **Acceso del actor:** sí queda comprobado por `postventa_estado_fn`, que exige `puede_acceder_crm`, limita roles y excluye lectores globales. No encuentro fundamento para afirmar que el plan permita acceder a un actor dado de baja (`20260910150039_crm_f6_postventa_persona.sql:87–95`).
- **Autores históricos:** `vendedor_ids_visibles` incluye históricos para gerencia y no muestra un filtro de actividad en el subárbol del supervisor. Añadir indiscriminadamente `equipo.activo` cambiaría ese contrato (`20260803164348_crm_offboarding_gate_activos.sql:57–72`).
- **Cartera reasignada:** aplicar la visibilidad actual de la persona podría hacer desaparecer llamadas históricas del autor. Si la métrica es por autor, esa excepción debe quedar escrita y probada.
- **Identidad:** el ayudante entregaría `persona_id` sin una etapa explícita de resolución/visibilidad. Al estar en `private`, eso no acredita una nueva puerta PostgREST; debe comprobarse qué consumidores pueden proyectarlo.

Además, hay una incompatibilidad potencial: Pulso autoriza a `es_lector_global`, pero postventa lo excluye. Si ese actor tiene un rol para el que `vendedor_ids_visibles(auth.uid())` devuelve vacío, validar los autores **antes** de devolver vacío por bandera puede romper Pulso completo con `42501`. Es un caso permitido por los contratos mostrados, no una incidencia demostrada en producción (`20260924201358_crm_gestion_diaria_pulso_habitos.sql:112–118`; `20260803164348_crm_offboarding_gate_activos.sql:53–74`).

**RESPUESTA P2. Sí, INVOKER → DEFINER es válido; no basta con re-sellar las dos funciones existentes.**

El gate comprueba las funciones enumeradas, no toda su cadena de llamadas. Mantener el lector como INVOKER satisface su comprobación estructural, aunque delegue una lectura privilegiada. El nuevo ayudante quedaría fuera de esas comprobaciones (`20260924201358_crm_gestion_diaria_pulso_habitos.sql:497–529`).

Hace falta una sección específica que compruebe para el ayudante:

- DEFINER, propietario `postgres`, STABLE y `search_path` vacío.
- ACL efectiva restringida según el contrato.
- Ausencia de `count(` y `sum(1)`.
- Su propio cuerpo sellado, incluyendo las defensas de autorización y bandera.

**No debe añadirse al bucle que exige INVOKER.** Los hashes del lector y agregador tampoco protegen transitivamente el cuerpo del ayudante (`20260924201358_crm_gestion_diaria_pulso_habitos.sql:532–547`). Añadir mutantes requiere definir primero qué comprobación rechazará cada uno.

El DROP + CREATE necesita una migración transaccional con dependencias identificadas y restauración explícita de propietario, ACL y comentarios. La transcripción no permite asegurar que todos los consumidores toleren el nuevo retorno.

**RESPUESTA P3. No completamente: coincide para resultados válidos coherentes, pero cambia el tratamiento de la ausencia de resultado.**

Para los siete resultados, la propuesta produce:

| Resultado | Tipo | Útil | Contestada total |
|---|---|---:|---:|
| `no_contesto` | no contestada | Sí | No |
| `numero_errado`, `no_es_la_persona` | no contestada | No | No |
| `volver_a_llamar`, `agendo_reunion`, `no_interesado`, `pide_otro_producto` | realizada | Sí | Sí |
| Ausente → `sin_resultado` | realizada | No | No |

La clasificación de los siete resultados coincide con la del registro de clientes. En leads depende también del `tipo` almacenado: el lector no lo reconstruye desde el resultado (`20261006012208_crm_gestiones_clientes_supervision.sql:118–121`; `20260924201358_crm_gestion_diaria_pulso_habitos.sql:14–16,53–54`).

La diferencia importante es:

- **Lead sin resultado:** útil; si figura como realizada, también contestada.
- **Cliente postventa sin resultado:** no útil ni contestada según el plan.
- **Registro de clientes postventa:** contacto falso, pero gestión operativa verdadera.
- **Registro legado:** una `llamada_realizada` puede tener contacto verdadero aunque no tenga resultado.

Esto último está expresamente codificado en `20261006012208_crm_gestiones_clientes_supervision.sql:142–143`.

Por tanto, el registro respalda **“sin resultado postventa no es contacto”**, pero no demuestra la regla **“no es útil”**, porque no devuelve esa métrica. Esa decisión sigue pendiente de Miguel y afecta al mínimo útil.

La ausencia tampoco es un octavo resultado aceptado: el cierre versión 2 exige resultado y valida los siete valores (`20261005224214_crm_resultados_cliente_postventa.sql:40–49`).

**RESPUESTA P4. Sí, se mantienen las invariantes; persiste una discrepancia semántica visible.**

Para una llamada sin resultado propuesta:

`llamadas=1`, `útiles=0`, `contestadas=0`, `contestadasPorHora=1`.

Cumple `1 − 0 ≤ 1 − 0`.

En general, la diferencia entre contestadas horarias y totales cuenta las realizadas que no son útiles, que nunca pueden superar todas las llamadas no útiles. La suma de llamadas horarias también se conserva porque ambos agregados recorren los mismos eventos (`20260924201358_crm_gestion_diaria_pulso_habitos.sql:49–54,70–77`; `app/src/lib/gestion-diaria-equipo.ts:155–167`).

Pero ahora esa diferencia aparecerá por una clasificación deliberada, aunque el comentario del front la describa como una tolerancia histórica. Debe documentarse o ajustarse la presentación: **pasar `horarioConfirmado` no significa que ambas cifras de “contestadas” expresen lo mismo**.

**RESPUESTA P5. Sí, Pulso depende de `lead_id`; sí, un NULL puede sumar uno en `array_agg(DISTINCT ...)`.**

Pulso calcula únicos globales y por equipo mediante `count(distinct lead_id)`, por lo que ignorará las filas de clientes. El límite declarado es compatible con ese código, siempre que conserve la etiqueta de leads y no se presente como el mismo universo de “personas distintas” (`20260924201358_crm_gestion_diaria_pulso_habitos.sql:226–237`).

Los fragmentos de Hábitos usan autor, identificador y tiempo; los de cortes consumen el agregador. No muestran una exigencia de `lead_id` no nulo. Esto no acredita todos los consumidores, cuyos cuerpos completos faltan (`20260924201358_crm_gestion_diaria_pulso_habitos.sql:335–345`; `20260921214018_crm_gestion_diaria_cortes.sql:188–198`).

Respecto a NULL:

- `array_agg(DISTINCT NULL)` contiene un elemento.
- Debe excluirse NULL explícitamente y devolver cero cuando no queden identidades.
- `actividades.lead_id` es NOT NULL; no está transcrita una garantía equivalente para `inversionista_gestiones.inversionista_id` (`20260709000001_cimientos_crm.sql:205–207`).

Hay además un problema mayor: **`lead.id` e `inversionista.id` no constituyen, por sí solos, una identidad común de persona**. Una persona llamada como lead y después como cliente puede contarse dos veces. La existencia de `inversionista_canonica` tampoco demuestra que los históricos estén normalizados (`20260910150039_crm_f6_postventa_persona.sql:139–145`).

Para prometer “personas distintas” hace falta una equivalencia entre ambos dominios. Añadir un prefijo de origen evitaría colisiones entre entidades, pero no resolvería esa duplicación de una misma persona.

**RESPUESTA P6. Sí, el lector admitiría duplicados entre leads y postventa; no está demostrado que los escritores los generen.**

La rama de leads no excluye leads convertidos ni relaciona sus actividades con un cierre postventa. Si la misma llamada queda registrada en ambos lugares, `UNION ALL` contará dos eventos (`20260924201358_crm_gestion_diaria_pulso_habitos.sql:18–22`; `20260709000001_cimientos_crm.sql:205–215`).

Faltan escritores, triggers y restricciones de tareas/cierres para determinar si ese escenario puede producirse realmente. No debe deduplicarse por persona y hora: podría eliminar llamadas legítimas distintas. Hace falta una correlación de evento, si existe doble escritura.

Sobre `actividades_cliente`:

- **No necesita una exclusión adicional en el plan actual:** esa tabla ni siquiera participa.
- **Sí puede quedar una omisión:** las dos filas observadas podrían ser llamadas independientes o espejos; el dato agregado no permite distinguirlo.
- Si son independientes y el alcance es todas las llamadas a clientes, deben incorporarse. El lector existente proporciona la regla antiespejos por `tarea_id`, aplicada incluso con postventa apagada (`20261006012208_crm_gestiones_clientes_supervision.sql:108–116`).

Existe otra diferencia de cobertura: el plan exige `metadata.estado='completada'`; el registro usa `coalesce(metadata.estado,t.estado)`. Un cierre sin estado en metadata y con tarea completada aparecería en el registro pero no en el marcador (`20261006012208_crm_gestiones_clientes_supervision.sql:99–105,118–121`). Debe alinearse la regla o acreditarse que ese histórico no existe.

**RESPUESTA P7. Sí, habrá recálculo retrospectivo; no puede asegurarse qué ocurrirá con los cortes reconocidos.**

Los cortes consultan de nuevo las ventanas del día. Tras aplicar el cambio, incorporarán cierres anteriores a cada corte, incluso si ese corte ya había sido consultado. Los cierres posteriores no deben atribuirse al corte previo (`20260921214018_crm_gestion_diaria_cortes.sql:188–198`).

El recálculo afecta también a días históricos consultados; la condición de “hoy y dentro del horario” limita cuándo avisar, no cuándo calcular (`20260921214018_crm_gestion_diaria_cortes.sql:185–186`).

Además:

- Alcanzar el mínimo útil puede hacer aparecer un nivel antes ausente (`app/src/lib/gestion-diaria-analista.ts:43–46`).
- Apagar postventa volvería a retirar esas llamadas del cálculo.
- `cartera_abierta` sigue basándose en leads activos no convertidos. Falta su uso posterior para saber qué ocurre con un analista que solo atiende clientes (`20260921214018_crm_gestion_diaria_cortes.sql:199–202`).

No está transcrita la persistencia de reconocimientos ni la emisión de avisos. No puede prometerse que no se reabran alertas o que no se dupliquen notificaciones.

**RESPUESTA P8. Sí, faltan casos concretos y resultados esperados.**

El kit mínimo debería cubrir:

1. **Visibilidad y acceso.** Supervisor solicitando otro equipo; vendedor solicitando otro vendedor; mezcla de IDs permitidos/prohibidos; esa mezcla con NULL; duplicados; array vacío. Los IDs prohibidos deben producir `42501` según el plan. Añadir actor sin sesión, sin acceso, gerencia con históricos y lector global autorizado para Pulso.

2. **Reasignación y bandera.** Mover cliente y tarea a otra cartera después del cierre; comprobar el contrato histórico por autor. Probar postventa y cartera habilitadas/deshabilitadas. Los espejos legados no deben reaparecer al apagar postventa. Esto deriva de las diferencias entre autorización por autor y por persona descritas en P1 y de la exclusión existente en `20261006012208_crm_gestiones_clientes_supervision.sql:115–116`.

3. **Clasificación completa.** Los siete resultados, resultado ausente/JSON null, cierre cancelado, tarea pendiente, WhatsApp y reunión. Probar metadata sin tipo y sin estado. Verificar también la excepción de contacto de las llamadas legadas realizadas.

4. **Caso Vladimir y regresión de leads.** Deben añadirse **6 llamadas, 5 útiles y 5 contestadas**, bajo la regla propuesta; el marcador debe pasar de 1 a 7 llamadas. El incremento de contestadas horarias sería 6. No fijar otros totales absolutos sin definir el resultado de la llamada a lead de la semilla.

5. **Tiempo, tasa y umbrales.** Inicio inclusivo, fin exclusivo, medianoche Lima, cierres exactamente en cada corte y antes/después del mínimo útil. Incluir un día compuesto únicamente por llamadas sin resultado y comprobar los contratos de tasa/nivel nulos (`20260924201358_crm_gestion_diaria_pulso_habitos.sql:22`; `app/src/lib/gestion-diaria-analista.ts:43–46`).

6. **Identidad y duplicación.** Varias llamadas a una persona; una persona como lead y cliente; identidades fusionadas; NULL si el contrato lo permite. Llamada legada independiente, espejo legado/postventa y reintento del mismo cierre. Dos llamadas legítimas a la misma persona deben seguir contando dos llamadas.

7. **Cortes e integración.** Corte ya reconocido, alertas antes/después de desplegar, día histórico y analista sin leads abiertos. Contrastar Mi día, Equipo, Registro, Pulso y Hábitos, conservando explícitamente el alcance de únicos de Pulso.

8. **Migración y defensas.** Ejecutar la migración sobre el banco anterior, comprobar dependencias/ACL y todos los gates afectados. Añadir mutantes para cada defensa del ayudante, incluida forma DEFINER, sesión, alcance, bandera y ambos patrones prohibidos de conteo. Verificar que falle por la defensa esperada y que el estado restaurado vuelva a pasar.

**FINDINGS P0–P3**

- **[P1] El gate descrito no protege el nuevo ayudante.**  
  **Evidencia:** `20260924201358_crm_gestion_diaria_pulso_habitos.sql:499–529,533–547`.  
  **Problema/impacto:** el gate actual no inspecciona ni sella el cuerpo del futuro DEFINER; re-sellar sus llamadores no detectaría una modificación posterior de sus defensas.  
  **Acción:** añadir un contrato específico del ayudante, su sello y mutantes verificables.

- **[P1] La justificación “espejo de visibilidad” no cubre el permiso que se propone.**  
  **Evidencia:** `20260910150039_crm_f6_postventa_persona.sql:121–122`; `20261006012208_crm_gestiones_clientes_supervision.sql:87–105,129–143`.  
  **Problema/impacto:** visibilidad de autores, visibilidad actual de cartera y entrega de identidad son controles distintos. El plan no acredita equivalencia con `gestiones_validar` ni define expresamente esa separación. No constituye una fuga demostrada.  
  **Acción:** formalizar la autorización histórica por autor, comprobar los consumidores de identidad y cubrir reasignaciones y lectores globales.

- **[P2] “Personas distintas” carece de una identidad común definida.**  
  **Evidencia:** `20260709000001_cimientos_crm.sql:207`; `20261006012208_crm_gestiones_clientes_supervision.sql:97`; `20260910150039_crm_f6_postventa_persona.sql:139–145`.  
  **Problema/impacto:** sustituir `lead_id` por UUID de dos entidades no garantiza unicidad de persona; conversiones y fusiones pueden inflar el indicador.  
  **Acción:** definir identidad canónica entre fuentes o ajustar el significado y texto del indicador; excluir NULL del agregado.

- **[P2] El universo de llamadas puede discrepar del Registro de clientes.**  
  **Evidencia:** `20261006012208_crm_gestiones_clientes_supervision.sql:99–116`.  
  **Problema/impacto:** se omite todo el legado y se endurece el predicado de estado. Las discrepancias son reproducibles con las filas descritas en P6, aunque su presencia real no está acreditada.  
  **Acción:** clasificar las dos filas legadas y resolver el estado ausente antes de fijar el contrato.

**RIESGOS Y TEST GAPS**

Faltan los cuerpos de `gestiones_validar`, resolución de identidades, escritores/triggers, restricciones de cierres y gestión de reconocimientos. También faltan los demás gates completos. Esas ausencias impiden certificar equivalencia de permisos, ausencia de doble escritura y estabilidad de reconocimientos.

La regla de utilidad para clientes sin resultado sigue siendo una decisión de negocio pendiente; no se deduce de `contacto=false`.

**Pruebas, gates, build y E2E: NOT RUN.** Esta es una revisión documental de diseño; las conclusiones algebraicas no sustituyen las verificaciones del PRIMARY.

**NEXT ACTIONS**

1. Cerrar el contrato de autorización, identidad y utilidad de resultados ausentes.
2. Incorporar al plan el gate específico del ayudante y el tratamiento completo del DROP + CREATE.
3. Auditar legado, estado histórico y posibles escrituras duplicadas; fijar expectativas de cortes reconocidos.
4. Ejecutar los casos anteriores, gates y E2E locales en Docker. Si se utiliza la segunda ronda, aportar el diff y resultados, junto con la evidencia que falta.

**CONFIDENCE: MEDIUM.** Alta sobre las invariantes horarias y las diferencias explícitas de consultas; limitada sobre autorización completa, duplicación efectiva y reconocimientos por ausencia de sus implementaciones.

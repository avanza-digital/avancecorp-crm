# Plan de implementación: avisos por acción y rol

Fecha: 2026-09-07.
Estado: **APROBADO, IMPLEMENTADO, PUBLICADO Y VERIFICADO. El pendiente heredado de Citas quedó cerrado; los siete controles ejecutados están aprobados. Validación y cierre productivo en [entrega](avisos-accion-rol-20260907/README.md).**

## Resultado esperado

El analista recibe una acción principal coherente con su trabajo real. Supervisor y Gerencia conservan las decisiones comerciales de su ámbito. Una tarea futura no vuelve a estar vencida porque haya vencido la etapa; una etapa vencida sigue requiriendo revisión aunque exista una tarea futura.

Se amplía el núcleo SLA existente. No hace falta crear otro núcleo ni añadir calculadoras independientes.

## Diagnóstico confirmado

La corrección publicada en la migración `20260907194756` difiere la primera atención solo con cobertura activa del compromiso. Esa cobertura termina en el tope de etapa. Además, mezcla la falta de primera gestión con la falta de respuesta efectiva.

Por eso una oportunidad con intentos registrados, próxima tarea futura y etapa agotada vuelve a exigir contacto inmediato. El comportamiento también está afirmado en las pruebas vigentes de tope, cancelación y fin del margen; cambiar solo un texto o añadir otra excepción no resuelve el modelo.

El ajuste propuesto cambia la clasificación operativa de pendientes. Conserva los hechos, los hitos de contacto conseguido, los plazos históricos y las reglas de prórroga. Las métricas históricas y el inventario actual de trabajo seguirán respondiendo preguntas distintas.

## 1. Cerrar las reglas operativas

### Definiciones

- **Primera gestión pendiente:** falta una gestión reconocida por el núcleo en la asignación y ciclo actuales, y venció su plazo. El nuevo responsable conserva su propio plazo; el historial anterior no lo sustituye.
- **Gestión:** utilizar exactamente las actividades reconocidas por los núcleos vigentes. Un intento sin respuesta cuenta como gestión. Nota interna, reasignación, cambio de etapa y mero agendamiento no la sustituyen.
- **Contacto conseguido:** respuesta/conversación reconocida por el núcleo actual; se conserva para historia y métricas. Su ausencia no vuelve a clasificar un intento realizado como primera gestión pendiente.
- **Próxima acción comercial válida:** tarea pendiente y activa de llamada, WhatsApp o reunión, con fecha finita, sujeto, responsable y contexto coherentes con el proceso actual. Su existencia se decide por los hechos de Agenda.
- **Cobertura/prórroga:** conserva su significado para límites y política. Agotar esa cobertura no invalida por sí mismo una tarea de Agenda.
- **Revisión comercial:** decisión del supervisor o Gerencia por plazo de etapa, reprogramaciones o reingresos según las reglas existentes. No se resuelve por abrir el aviso o por agendar otra tarea.

La elegibilidad de una tarea para organizar el siguiente intento debe separarse de su capacidad para ampliar o cubrir un plazo. Este es el cambio que evita repetir el problema.

### Matriz obligatoria

| Condición | Resultado para el analista | Resultado de supervisión |
|---|---|---|
| Sin gestión inicial; plazo aún vigente | Conservar la acción inicial como trabajo previsto, sin aviso vencido | Conservar visibilidad del estado |
| Sin gestión inicial; plazo vencido, incluso si agendó algo futuro | Pedir el primer intento | Mantener el pendiente en su ámbito |
| Intento sin respuesta y tarea comercial futura válida | Mostrar próxima acción; no exigir otra gestión inmediata | Mantener las revisiones que correspondan |
| Contacto conseguido y tarea futura válida | Mostrar próxima acción; no volver a primera gestión | Mantener las revisiones que correspondan |
| Tarea para hoy, todavía no vencida | Mostrar la actividad y su hora; no llamarla vencida | La misma fecha y estado |
| Tarea pendiente que alcanza su vencimiento | Pedir revisar esa actividad concreta | Mantener la actividad vencida visible |
| Una tarea vencida y otra futura | La futura no oculta la vencida | Conservar la revisión de la vencida |
| Gestión inicial hecha, sin tarea comercial futura, cadencia vigente | No generar una insistencia vencida | Conservar visibilidad del estado |
| Gestión inicial hecha, sin tarea comercial futura, cadencia vencida | Retomar seguimiento; no volver a primera gestión | Mantener seguimiento pendiente |
| Etapa agotada y próxima tarea futura | Mantener la tarea programada | Pedir revisar el plazo de la etapa |
| Etapa agotada y tarea vencida | Revisar la tarea vencida | Revisar también la etapa; causas independientes |
| Exceso de reprogramaciones o reingresos | Conservar la actividad pendiente y su fecha real | Mantener la decisión comercial requerida |
| Tarea completada, cancelada o no realizada | Reevaluar gestión real y tareas restantes | Reevaluar sus pendientes |
| Reasignación o reapertura | Aplicar asignación/ciclo actuales; no usar tareas antiguas como justificación de espera | Conservar historia y revisiones vigentes |
| Varias tareas futuras válidas | Mostrar primero la de vencimiento más próximo; desempate estable por ID | Mismo orden dentro de su ámbito |
| Solo tarea administrativa o tarea de contexto ajeno | No usarla como siguiente intento comercial; conservar su obligación propia en Agenda | Revisar incoherencias cuando correspondan |
| Datos insuficientes o contradictorios | Mostrar que el estado necesita revisión; no afirmar que está al día | Indicar la revisión de datos necesaria |
| Sin responsable, restricción de contacto, inactiva, cerrada o descartada | Aplicar visibilidad y restricciones existentes; evitar instrucciones de contacto no permitidas | Por repartir cuando proceda, o conservar historia sin avisos comerciales improcedentes |

Completar una tarea solo cuenta como gestión si el writer registra una actividad válida; cancelar no crea una gestión. Si se completa una tarea y se agenda otra en el mismo gesto, el lector debe observar el resultado confirmado de la transacción completa.

### Prioridad y conteos

- Elegir en servidor una acción principal de atención: revisar una tarea vencida comprobada; realizar la primera gestión cuando esté pendiente; ejecutar la próxima actividad prevista; o retomar el seguimiento cuando corresponda. Resolver antes las restricciones y la falta de datos que impidan decidir.
- La tarea futura solo evita la insistencia genérica después de una gestión inicial reconocida. No permite diferir indefinidamente la primera gestión.
- Si completar una tarea comercial vencida resuelve además la primera gestión, dirigir a esa tarea y evitar dos órdenes equivalentes.
- Conservar las causas verdaderas necesarias para filtros y auditoría, pero identificar explícitamente la acción principal que presenta la ficha.
- Supervisor/Gerencia pueden recibir una revisión comercial además de la acción del analista: son responsabilidades distintas.
- Los totales de oportunidades se deduplican por oportunidad. Los conteos por causa pueden solaparse; nunca se suman como si fueran personas distintas.
- Ficha, filtros y campana se comparan con el mismo ámbito e instante de cálculo. No comparar una página con el total de toda la cartera.

**Entregable:** matriz cerrada con ejemplos y criterios de aceptación. Los cambios frente a las reglas actuales quedan explícitos, especialmente primera gestión, tope de etapa, cancelación y fin del margen.

## 2. Implementar la decisión dentro del núcleo existente

Responsabilidades:

| Pieza actual | Trabajo |
|---|---|
| Proveedores privados de hechos SLA, tareas, asignación y políticas | Reutilizar los hechos y comprobar la elegibilidad de las tareas sin otro cálculo de negocio en la interfaz |
| `private.sla_operacion_leads` | Separar primera gestión, siguiente acción y revisión comercial; producir decisiones y causas coherentes |
| `private.sla_operacion_autorizada` | Seleccionar la perspectiva permitida por rol y ámbito; incluir la acción principal autorizada |
| RPC de estado, cola y resumen de avisos | Proyectar, filtrar, paginar y contar esas mismas decisiones |
| Gate e inventario del núcleo | Certificar dependencias, firmas, permisos y contratos actualizados |

Reutilizar los códigos y RPC existentes. Añadir de forma compatible los campos de presentación que hagan falta —acción principal y próxima acción autorizadas— en las respuestas existentes; documentar su contrato. No crear una nueva RPC por pantalla.

Mantener separados los datos históricos y las decisiones operativas. No cambiar plazos, política, techos, fechas, permisos ni writers para obtener un resultado visual.

La migración debe tener preflight de fuentes vivas, límites de bloqueo/ejecución, postflight del núcleo y reversión exacta. Registrar las nuevas huellas y dependencias siguiendo la gobernanza existente.

**Entregable:** migración y reversión probadas, contrato de respuesta y evidencia del núcleo.

## 3. Alinear la interfaz y su actualización

Archivos principales identificados:

- `app/src/lib/sla-operacion.ts`: contrato, etiquetas y mensajes. Cambiar la etiqueta visible a **Primera gestión pendiente** para expresar el criterio nuevo.
- `app/src/lib/sla-avisos-presentacion.ts`: resumen de campana consistente; dejar de llamar “contactos iniciales” a la primera gestión.
- `app/src/components/app/sla-operacion.tsx`: presentar la acción principal del servidor y la revisión de supervisión cuando corresponda; conservar “Ver plazos” plegado.
- Integración de `lead-drawer.tsx`: próxima acción y botón deben apuntar a la misma tarea que eligió el núcleo, con el flujo correcto según su tipo.
- `app/src/data/sla-operacion-queries.ts` y la invalidación compartida: refrescar estado, cola y campana tras confirmarse cada operación.

Mensajes propuestos: “Realiza el primer intento”, “Revisa la actividad pendiente”, “Retoma el seguimiento” y “Revisa esta oportunidad: venció el plazo de la etapa”. Usar el mensaje y botón permitidos para el rol.

Mantener el módulo de Seguimiento separado del Resumen de Gerencia, su paginación 10/25/50 y la retirada de Seguimiento comercial del Hoy del analista.

Actualización:

- Al confirmar una gestión, cierre/cancelación/reprogramación de tarea, reasignación, reapertura o cambio de etapa, invalidar las lecturas relacionadas y reiniciar la paginación cuando cambie el orden.
- Conservar la protección ya publicada contra respuestas antiguas que terminan después de una escritura.
- Programar reconsulta en el próximo cambio temporal informado por el núcleo; el navegador pide datos, no decide el SLA. Mantener la reconsulta periódica de respaldo y al recuperar foco/conexión.
- Probar retorno desde segundo plano y errores de red. Mostrar el estado de actualización sin afirmar que los pendientes desaparecieron si la consulta falló.
- Las transiciones son exactas en el servidor. Medir el retraso de visualización en navegador activo y documentarlo; no prometer puntualidad de reloj en una pestaña suspendida o sin conexión.

**Entregable:** ficha, filtros y campana coherentes, mensajes breves y actualización verificada.

## 4. Probar estados, transiciones y permisos

Reutilizar los bancos de núcleo, avisos e integración. Crear fixtures sintéticos del patrón con tarea futura dentro del plazo y del patrón con tarea futura después del tope de etapa.

Pruebas obligatorias:

- Matriz anterior en Nuevo, Contactado, Cita agendada y Propuesta enviada.
- Sin gestión, intento sin respuesta y contacto conseguido; responsables anteriores y actuales.
- Antes, exactamente en y después del plazo inicial, vencimiento de tarea, cadencia, margen y tope; fechas de Lima y cambio de día.
- Tareas múltiples, administrativas, de otro ciclo/responsable, canceladas, no realizadas, inactivas y con contexto incompleto.
- Última tarea cancelada; completar sin sucesora; completar con sucesora en la misma transacción; reprogramar; reasignar; reabrir; cerrar.
- Analista, supervisor, Gerencia y lectores permitidos; otro equipo y usuario sin identidad no obtienen acceso.
- Igualdad de ficha, filtros y resumen; oportunidades deduplicadas y causas contadas correctamente.
- Página 2, cambio de tamaño/filtro, actualización del orden y rechazo/reinicio de cursores anteriores al nuevo modelo.
- Persistencia confirmada, respuesta antigua en vuelo, fallo de escritura, fallo de lectura, reconexión y retorno a primer plano.
- Conservación de métricas históricas, política, límites, hechos, permisos y modo operativo.
- Aplicación, reversión y reaplicación con guardas de versión.

Las expectativas antiguas que devolvían primera atención tras el tope/cancelación/margen deben reemplazarse por las nuevas reglas, conservando pruebas de historia y límites. Demostrar primero que los casos nuevos fallan con el comportamiento publicado.

Ejecutar el núcleo real en PostgreSQL 17 con esquema y autoridades reales en banco aislado, además de las regresiones reducidas existentes. Declarar cualquier doble de pruebas. No usar escrituras de prueba en producción.

**Entregable:** evidencia de fallo previo, resultado corregido, pruebas por rol y verificación visual.

## 5. Contrastar toda la cartera antes de publicar

Comparar la definición publicada y la candidata contra una misma foto consistente de hechos e instante. Preparar el contraste en un entorno aislado con los datos necesarios; guardar únicamente evidencia agregada sin PII en el repositorio.

Clasificar todos los cambios:

- Salen de primera gestión porque ya existe un intento válido.
- Esperan a una tarea futura.
- Pasan a seguimiento por cadencia.
- Conservan una tarea vencida.
- Conservan una revisión comercial.
- Necesitan revisar datos.

Verificar que no se oculten tareas vencidas, restricciones, oportunidades sin primera gestión ni revisiones por etapa/reprogramación/reingreso. Separar cambios concurrentes de negocio si se hace una comprobación adicional entre dos lecturas productivas.

**Entregable:** cuadro de antes/después por rol y causa, con cero diferencias sin explicación respecto de la matriz aprobada.

## 6. Publicar y cerrar

1. Integrar cambios remotos en el trabajo aislado, preservar cambios ajenos y terminar los commits de esta entrega.
2. Presentar el SQL exacto, su alcance y las pruebas para confirmación, conforme a la regla de `Inicio.md`. La aprobación del ajuste anterior no equivale a aprobar un SQL futuro todavía no mostrado.
3. Verificar que Main local y `avancecorp/main` señalen el mismo commit. Construir y comprobar el artefacto frontend desde ese commit limpio.
4. Verificar compatibilidad en ambos sentidos: interfaz nueva con contrato anterior e interfaz anterior con respuesta nueva. Usar identificación del modelo del servidor para que las etiquetas nuevas no describan reglas antiguas durante la transición.
5. Publicar la interfaz compatible, aplicar exclusivamente la migración aprobada y comprobar el conjunto. No ejecutar indiscriminadamente otras migraciones pendientes.
6. Verificar fuentes vivas, gate, política/contratos y lectores autenticados. Revisar advisors antes/después y el artefacto realmente servido.
7. Comprobar visualmente los dos patrones reportados, un caso sin primera gestión y uno con tarea vencida. Confirmar ficha, filtros y campana.
8. Registrar versiones, commits, evidencia, limitaciones y reversión en el ledger y el vault.

La reversión debe recuperar el comportamiento anterior sin borrar historia; ensayar la compatibilidad antes de decidir el orden de reversión de interfaz y SQL.

## Criterios de cierre

- Una gestión válida deja de aparecer como primera gestión pendiente en su asignación/ciclo.
- Una tarea futura reconocida evita una instrucción genérica anticipada después de gestionar, aunque haya revisión comercial.
- Una tarea vencida sigue siendo visible y accionable; otra tarea futura no la oculta.
- Las revisiones llegan al rol correspondiente y no desaparecen por agendar.
- Cancelar, completar, reasignar y reabrir producen resultados acordes con los hechos confirmados.
- Ficha, lista, filtros y campana usan la misma decisión autorizada.
- Plazos, historia y permisos están conservados y comprobados.
- La matriz, el contraste de cartera y la verificación productiva están documentados antes de declarar terminado el trabajo.

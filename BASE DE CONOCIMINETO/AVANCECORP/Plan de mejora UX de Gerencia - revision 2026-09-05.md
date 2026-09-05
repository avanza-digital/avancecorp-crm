---
tags: [crm, ux, gerencia, plan]
fecha: 2026-09-05
estado: plan-revisado-ejecucion-ux-por-verificar
---

# Plan de mejora UX de Gerencia — revisión del 5 de septiembre

Relacionado con [[Plan de mejoras UX-UI del CRM]], [[Fundamentos UX del CRM]], [[Acceso y roles del CRM]], [[Inventario de indicadores de Gerencia - Contrato de lectura]] y [[Plan de correccion de metricas de Gerencia - requerimiento vigente]].

## Alcance confirmado y fuente

Miguel pidió recuperar y mejorar el plan de **experiencia del usuario de Gerencia**. La respuesta inicial recuperó por error el plan de corrección de métricas; Miguel aclaró el alcance. Esta nota desarrolla el plan UX específico del rol y evita volver a confundir ambos seguimientos.

Fuente: [Plan UX por rol — Gerencia](../../output/pdf/plan-ux-gerencia-crm-avance.pdf), documento de diez páginas creado el 23 de agosto de 2026. Se revisó su contenido completo y se inspeccionaron visualmente las páginas de fases y validación. El PDF original se conserva como referencia; esta nota registra la propuesta actualizada.

La revisión es documental. El estado actual de cada superficie y el avance real de las fases UX se comprobarán en F0. Las correcciones de datos publicadas o probadas localmente no equivalen a haber ejecutado este rediseño.

## Objetivo del usuario

Que Gerencia pueda **saber qué requiere atención, entender por qué y llegar a la acción adecuada**, conservando el contexto al revisar detalles. Debe poder comparar resultados, operar sobre el ámbito autorizado y configurar las opciones existentes con claridad sobre su efecto.

El recorrido principal es: resumen → asunto que revisar → evidencia → decisión → acción existente → resultado comprobable → regreso al contexto.

## Fases y condiciones de cierre

| Fase | Trabajo y entregable | Condición de cierre |
| --- | --- | --- |
| **F0. Tareas y situación actual** | Recorrer Resumen, Conversiones, Ranking, Citas, Cartera, Distribución y Configuración con el rol Gerencia. Capturar pantallas, observar las cinco tareas de validación y anotar tiempos, pasos, dudas y errores. Clasificar qué ya funciona y qué conviene mejorar por impacto y esfuerzo. | Existe una lista priorizada con evidencia y una línea base. Cada pantalla tiene una tarea principal; las mejoras ya hechas se reconocen. |
| **F1. Resumen ejecutivo** | Ordenar la entrada para reconocer el estado del negocio y hasta tres asuntos prioritarios respaldados por datos y reglas existentes. Vincular cada asunto con su explicación y destino. Mantener los indicadores secundarios y el detalle accesibles. | El usuario identifica qué revisar primero y explica con qué dato lo sustenta. Si no hay una señal verificable, la pantalla lo comunica sin fabricar una urgencia. |
| **F2. Lectura y comparación** | Unificar jerarquía visual, títulos, filtros, tablas y gráficos. Mostrar período, ámbito, moneda y estado del dato. Facilitar el paso del resumen al detalle y el regreso conservando filtros compatibles, selección y posición. Mantener visibles las diferencias legítimas entre medidas. | Gerencia compara resultados equivalentes y consulta su evidencia sin reconstruir filtros ni confundir las poblaciones o fechas medidas. |
| **F3. Operación global** | Hacer accesibles las acciones existentes desde su contexto: distribución, reasignación y gestión comercial. Mostrar destinatario, alcance y efecto antes de un cambio sensible; después, presentar el resultado real. Diseñar recuperación ante errores y envíos inciertos. | El usuario sabe si está consultando o modificando, a quién afecta y si el cambio se guardó. Un reintento no se presenta como seguro si la operación aún no ofrece esa garantía. |
| **F4. Configuración comprensible** | Agrupar las opciones existentes por tarea: equipo y capacidad, metas y reglas operativas. Mostrar dependencias y motivos de bloqueo, validar los campos y resumir el efecto de guardar. Mantener explicaciones y verbos consistentes. | Gerencia encuentra el ajuste, entiende su alcance y verifica el resultado o sabe cómo resolver el bloqueo. La organización se adapta a las capacidades existentes; no presupone nuevos administradores de usuarios o productos. |
| **F5. Validación y entrega** | Repetir las tareas con usuarios de Gerencia; comparar con F0 y resolver los fallos. Comprobar escritorio, tablet y consulta móvil, estados parciales y accesibilidad. Publicar por entregas verificables conforme a las reglas vigentes del proyecto y revisar el uso posterior. | Las tareas acordadas se completan sin ayuda crítica, los resultados se interpretan correctamente y no quedan errores críticos dentro del alcance. La versión publicada tiene evidencia y reversión. |

Orden inicial: **F0 → F1 → F2 → F3 → F4 → F5**. F0 puede adelantar un defecto de guardado o bloqueo de alto impacto si la evidencia lo justifica. La calidad visual, la accesibilidad y los estados de error se comprueban en cada fase; F5 verifica el recorrido completo.

## Mejoras sobre el PDF original

1. **Medir antes de rediseñar.** F0 incorpora tareas observadas y reconoce lo ya implementado. Las duraciones del PDF eran estimaciones del 23 de agosto; se vuelven a estimar por entregable después del inventario actual.
2. **Prioridades justificadas.** «Hasta tres» es un límite de presentación, no una cuota que deba llenarse. Cada aviso necesita evidencia y una acción o revisión pertinente. Un color de gráfico no basta para declarar una alarma; umbrales nuevos requieren su definición comercial.
3. **Contexto durante todo el recorrido.** El regreso desde una ficha o detalle conserva el trabajo del usuario. Un filtro común no obliga a que conversión, citas y capital midan el mismo período; cuando una lectura tiene otra base, se explica.
4. **Calidad desde la primera entrega.** Contraste, foco, teclado, estados de carga/vacío/error y recuperación forman parte del cierre de cada pantalla. El color se acompaña de texto o forma. Los detalles importantes también son accesibles al tocar y con teclado, sin depender de pasar el puntero.
5. **Validación adecuada al tamaño de Gerencia.** Participan los usuarios reales disponibles del rol. Si sólo hay uno, se registran resultados individuales y el límite de la muestra; no se exige reunir cinco gerentes ni se presenta una tasa de éxito como representativa. Los porcentajes de 90 % y 80 % del PDF se sustituyen inicialmente por resultados por tarea y errores observados.
6. **Reutilizar lo existente.** Se revisan componentes y patrones compartidos antes de proponer otros. Se mantiene la gramática de color acordada y la capacidad operativa de Gerencia. La nueva organización no implica ampliar permisos o incorporar funciones de administración del portal.

## Cinco tareas para comprobar la mejora

1. Identificar el asunto comercial principal que requiere revisión y justificarlo con su evidencia; reconocer también un escenario sin alertas verificables.
2. Comparar dos equipos o responsables con un período y una base compatibles, explicando qué mide la cifra y en qué moneda se expresa.
3. Abrir el detalle desde un indicador y regresar manteniendo el contexto de consulta.
4. Ejecutar una acción global existente en un entorno de prueba controlado, reconocer a quién afecta y comprobar su resultado, incluido un escenario de fallo o respuesta incierta.
5. Localizar y modificar un ajuste permitido en ese entorno, comprender sus dependencias y verificar si se guardó o cómo resolver el impedimento.

Por tarea se registra: resultado correcto, ayuda necesaria, tiempo, pasos, confusión de significado y errores. Se comparan tareas equivalentes antes y después; las metas de tiempo se fijan tras medir F0. Las pruebas con escrituras utilizan escenarios controlados, no cambios ficticios sobre clientes reales.

## Relación con las métricas y definición de terminado

El inventario de indicadores proporciona las definiciones que la experiencia debe explicar. Las cuatro ampliaciones de Gerencia mantienen su seguimiento propio; una pantalla sólo presenta como disponible el dato que su versión de servidor entrega y verifica. Ausencia, error y cero comprobado siguen siendo estados diferentes.

Se conserva el título acordado **«Resultados de los leads del mes»**, la distinción entre llegada y cierre, los períodos propios de cada lectura y el desglose monetario correspondiente. La UX puede mejorar con las lecturas disponibles; la publicación de una visualización dependiente de un dato nuevo requiere comprobar antes que ese dato esté operativo.

Este plan queda terminado cuando Gerencia completa las cinco tareas acordadas sin ayuda crítica en la validación final, interpreta correctamente los resultados, conserva acceso a sus operaciones y recibe estados comprensibles. Las comprobaciones técnicas, visuales y de accesibilidad acompañan la evidencia del usuario; aprobar pruebas de métricas por sí solo no cierra el plan UX.

# Centro de ayuda del vendedor

Fecha de decisión: 2026-08-17.

## Objetivo

El vendedor debe poder resolver una duda operativa sin abandonar la pantalla en la que está trabajando. El manual no se abrirá en otra pestaña ni reemplazará la vista de Pipeline, Leads, Agenda o Cartera.

## Experiencia acordada

- Se abre desde **Ayuda** en la barra superior.
- En escritorio aparece acoplado a la derecha y mantiene visible la pantalla de trabajo.
- En móvil aparece como una hoja inferior que se puede minimizar.
- Las preguntas frecuentes se ordenan según la pantalla actual.
- Una respuesta muestra resumen, pasos numerados, advertencia, fuente y una acción permitida como **Ir a Agenda** o **Abrir Nuevo lead**.
- Al navegar dentro del CRM, la guía conserva la pregunta y el paso actual.
- Al abrir la ficha de un lead o el formulario de alta, la guía se minimiza y queda disponible como **Continuar guía**.
- Si una consulta no está documentada, el sistema lo declara; no inventa instrucciones.
- El vendedor puede preguntar con expresiones cotidianas, sin conocer el nombre exacto del botón. Cada guía mantiene frases equivalentes aprobadas, por ejemplo **sacar un pendiente** → **Anular tarea**.
- Si la frase puede significar operaciones distintas, el centro pide una precisión antes de responder. Ejemplo: **eliminar algo** puede referirse a anular una tarea pendiente, corregir una gestión registrada o reprogramar una reunión.
- Cuando el CRM usa un término distinto al del equipo comercial, la respuesta muestra explícitamente la traducción **lenguaje del vendedor → lenguaje del CRM**.

## Autoridad y contenido

- No se usará IA en esta etapa.
- La versión definitiva consultará contenido aprobado y versionado desde el servidor.
- El servidor resolverá las consultas mediante intenciones, sinónimos y frases aprobadas de forma determinística; esta capa no requiere IA.
- Las consultas sin resultado deberán registrarse para que un responsable las revise, las agrupe y agregue nuevas expresiones o guías sin desplegar una versión nueva del navegador.
- El navegador será responsable de presentar la respuesta, conservar el estado visual y ejecutar únicamente acciones internas permitidas; no será la fuente definitiva del consejo.
- El contenido deberá respetar las reglas operativas existentes, incluida la disponibilidad de contactos y el flujo documental descrito en [[PDF contractual privado e inmutable 2026-08-17]].

## Estado al 2026-08-18

La infraestructura y la integración están implementadas. El backend está desplegado en Supabase producción y la interfaz compilada ya está publicada en Hostinger:

- 17 guías operativas, 112 expresiones aprobadas y 3 reglas editoriales de aclaración viven en tablas privadas de PostgreSQL.
- Las guías publicadas son inmutables; un cambio posterior se publica como una versión nueva.
- Las RPC autenticadas `crm.ayuda_vendedor_inicio` y `crm.consultar_ayuda_vendedor` son la única frontera pública. El navegador ya no contiene fixture, diccionario ni algoritmo de similitud.
- La decisión combina coincidencia exacta, Full Text Search en español y `pg_trgm`, pero exige cobertura léxica de la frase aprobada, términos obligatorios, ausencia de exclusiones, puntuación mínima `0.61` y separación mínima `0.12` frente al segundo candidato.
- La pantalla actual solo ordena consultas frecuentes; no modifica la puntuación ni fuerza una respuesta.
- Las consultas ambiguas devuelven `aclaracion`; las débiles o desconocidas devuelven `sin_resultado`.
- La telemetría sustituye datos personales y vocabulario libre antes de almacenarlos y conserva registros durante 90 días.
- El panel está acoplado a la pantalla de trabajo, conserva la guía al navegar y se minimiza cuando se abre una ficha o el alta de un lead.

La implementación se verificó en una base PostgreSQL desechable que replicó `pg_trgm` en `public` y comprobó su reubicación a `extensions`. Pasaron las 112 expresiones publicadas, los conflictos críticos, permisos, redacción de PII, retención y planes con ambos índices GIN. También pasaron el contrato tipado, las pruebas del panel, el conjunto completo del frontend, lint, typecheck, build y la comprobación de que el bundle no contiene respuestas locales.

La migración remota `20260818054949_crm_ayuda_vendedor_servidor` se ejecutó correctamente. El frontend se publicó en `crm.miavance.com`, se limpió la caché y los archivos principales servidos coinciden byte a byte con el ZIP aprobado. Solo queda la validación de aceptación dentro de una sesión CRM real. La evidencia está en [[Continuidad centro de ayuda 2026-08-18]].

## Retroalimentación sobre la búsqueda — 2026-08-17

La coincidencia aproximada del prototipo producía recomendaciones incorrectas cuando una consulta compartía palabras generales con varias guías. Por eso se eliminó el diccionario del navegador y se impide aceptar una coincidencia solo porque comparte términos generales.

El plan de sustitución está documentado en [[Plan motor de búsqueda de ayuda del vendedor]].

Decisión aplicada en la implementación definitiva:

- La resolución vivirá en PostgreSQL/Supabase y el navegador solo presentará el resultado.
- Se combinará búsqueda de texto en español, normalización de tildes, similitud tipográfica y un catálogo curado de intenciones y expresiones comerciales.
- Una intención deberá cumplir sus términos de negocio obligatorios; la pantalla actual no podrá convertir por sí sola una coincidencia dudosa en respuesta.
- Solo se responderá cuando el primer candidato supere un umbral de confianza y tenga una separación suficiente frente al segundo candidato.
- Ante empate, ambigüedad o baja confianza, se devolverá una aclaración o `sin_resultado`; nunca la guía "más parecida" por descarte.
- Las consultas fallidas se registrarán sin datos personales para ampliar el catálogo y crear pruebas de regresión.

La integración visual forma parte de la continuidad operativa descrita en [[Continuidad CRM 2026-08-06]] y deberá alinearse con [[Configuración operativa CRM 2026-08-07]] cuando se defina quién publica y versiona el manual.

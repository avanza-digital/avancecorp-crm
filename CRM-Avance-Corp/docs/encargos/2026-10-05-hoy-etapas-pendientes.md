# HOY: etapas actuales y aviso de pendientes de gestión

Estado: corrección implementada; publicación se registra después de comprobar el artefacto servido.

## Criterio vigente de Miguel

Cada lead recibido HOY debe mostrar su etapa actual. El número naranja de la pestaña ahora significa **recibidos hoy todavía sin gestionar**, no el total recibido ni «sin leer». Abrir lista/ficha no lo reduce. Registrar una gestión vigente sí; cero queda neutro y sin latido. La lista conserva todos los recibidos del día, con el total explícito «Recibidos hoy» y sus etiquetas actuales.

Gestión conserva la regla existente: llamada realizada/no contestada, WhatsApp enviado/recibido o reunión realizada desde la tenencia actual, sin resultados deshechos. Notas o gestiones del titular anterior no cuentan. Convertidos/descartados quedan fuera del aviso. La etapa y la gestión son conceptos independientes: un reasignado puede conservar Contactado de su titular anterior y seguir pendiente para quien lo recibió hoy. La fila conserva esa etapa real; el contador mide su gestión actual. No se añaden estados persistidos ni filtros por etapa que oculten pendientes.

## Implementación

- Se reutilizan `useEtapaVisible` y `Badge` de Leads/ficha para Nuevo, Gestionado, Contactado, Cita agendada, Entrevista realizada y terminales. Error de verificación conserva Gestión sin verificar.
- `useLeadsRecibidosHoy` mantiene la lista completa y una consulta con `gestion: sin_gestion`, ambas con el mismo analista y recepción del día de Lima. El aviso usa `resumen.totales.abiertos`, calculado por el servidor antes de paginar; nunca cuenta solo las filas cargadas.
- Una invalidación existente de cartera actualiza ambas consultas al guardar la gestión. Un solo intervalo visible de 60 s y recarga/reintento compartidos. El intervalo espera al terminar la paginación para no cancelar la página ni perder su foco.
- Demo usa `tieneGestionVigente` con el timeline completo antes del filtro de titular/día, incluso si hay más de 50 recibidos. No consulta el backend.
- Un conteo fallido/pendiente no equivale a cero. Conserva la lista y ofrece reintento; con agenda abierta se oculta el número hasta recuperar información fiable.
- No hay textos visibles adicionales junto al número. Tooltip y texto solo para lectores de pantalla explican «sin gestionar». Etapas legibles en móvil y descripción accesible por fila.

## Verificación

- Cierre integral **PASS**: 6.100 tests / 378 archivos; lint, tipos, cobertura, configuración de release, build, bundle y duplicación 0,44 %. Cuatro avisos previos de lint permanecen fuera de alcance.
- Pruebas dirigidas finales **PASS**: 87 tests.
- Docker local PASS: 3/3, incluyendo guardar «No contestó» desde la ficha y comprobar contador 1 → 0, fila Gestionado y total recibido 3. Caso paginado: 55 recibidos, 53 sin gestionar, etapas completas en móvil. Error y vacío cubiertos. Repetición final tras el ajuste accesible: **3/3 PASS**, sin fallos ni reintentos.
- Lectura SQL productiva bajo rol authenticated, transacción READ ONLY con rollback: 9 recibidos, 9 pendientes, 9 filas, titular correcto y ausencia de gestión vigente confirmados. Las 9 filas observadas estaban en Nuevo. Función actual `crm.cartera_filtrada_fn` SECURITY INVOKER, filtro `sin_gestion` y resumen `abiertos` existentes. Ningún dato modificado.
- Gate general `gate:realidad`: NOT RUN por falta de entorno; no se sustituye su resultado por el smoke específico.
- Docker, revisión visual escritorio/móvil y `git diff --check` PASS. Sin cambios de backend, permisos ni dependencias.

## Revisión independiente y decisión del PRIMARY

Claude emitió CHANGES_REQUESTED (LEVEL 2). Su revisión quedó en el archivo hermano de texto. Resolución con evidencia:

- P2, etapa avanzada sin gestión de la tenencia actual: se conserva la etapa real pedida por Miguel y la regla vigente del contador; prueba explícita de Contactado heredado + contador 1. No se añade una marca inventada usando `gestion_vigente` en etapas avanzadas: `data/gestion-vigente.ts` devuelve false fuera de Nuevo y no acredita esa gestión. La sugerencia de usarla directamente sería incorrecta. La ambigüedad visual se mantiene acotada al significado documentado de dos datos distintos.
- P3 accesibilidad aceptado: «sin gestionar» se incorpora al nombre accesible de la pestaña sin texto visual adicional.
- P3 identidad del objeto descartado con fuente: el efecto de foco depende de `cartera.leads.length`, `cartera.cargandoMas` y `cartera.error`, no del objeto. E2E confirma foco de paginación.
- Coste: una consulta de resumen adicional por analista/día y minuto visible. Reutiliza el filtro e índice de contactos existentes; no añade sondeos independientes ni consultas por fila nuevas.
- Lista/contador pueden reflejar durante la recarga dos instantes consecutivos; se validan por separado y no se infiere un cero del fallo de ninguno.

## Integración

La PR #191 ya está fusionada a `avancecorp/main` en `0dfb1b5c`. Se integró ese Main en la copia de rescate existente, con árbol de código idéntico antes de este ajuste. El taller original preserva todos los cambios ajenos. La corrección continúa desde ese historial que contiene tanto Main como el commit vivo `ac46b2d3`.

El chequeo intermedio detectó que jsdom unía el dígito y «sin gestionar» sin espacio en el nombre accesible. Se añadió un espacio explícito y pasaron tanto las 87 dirigidas como el gate completo de 6.100 y Docker 3/3.

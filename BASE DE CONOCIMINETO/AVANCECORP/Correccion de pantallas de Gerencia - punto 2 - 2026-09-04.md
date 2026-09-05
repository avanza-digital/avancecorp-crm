---
tags: [crm, gerencia, metricas, implementacion, verificacion]
requerimiento: REQ-GER-MET-001
punto: 2
fecha: 2026-09-04
estado: punto-2-completo-publicado
---

# Corrección de pantallas de Gerencia — punto 2

Continuidad de [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Inventario de indicadores de Gerencia - Contrato de lectura]] y [[Auditoria de metricas de Gerencia - hallazgos y plan 2026-09-04]]. Esta nota registra la implementación posterior al inventario: sus etiquetas describían la línea base, no las pantallas ahora corregidas.

**Actualización posterior — 4 de septiembre, 23:49 Lima:** Miguel autorizó guardar todo y publicar; frontend publicado desde `50f33a5`, con Main sincronizado antes del build/deploy, pruebas y acceso de Gerencia verificados. El punto 3 también se completó y publicó. Evidencia vigente en [[Publicacion frontend metricas Gerencia 2026-09-04]] y [[Plan de correccion de metricas de Gerencia - requerimiento vigente]]. El resto de esta nota conserva el registro histórico de la implementación local de las 22:05, no el estado actual de publicación.

## Autorización y límites

Objetivo autorizado: corregir las pantallas y sus conexiones con datos existentes, empezando por Resumen y Conversiones; distinguir llegadas/base/asignaciones y citas registradas/avance inferido; alinear nombres, períodos y filtros; no presentar error o ausencia como cero. Corregir y verificar localmente, **sin publicar**.

No se implementó el punto 3 (lectura económica de Cartera ni exclusión SQL de contratos de prueba), ni las ampliaciones de respuesta del punto 4. Las pruebas de esta entrega no cierran la conciliación integral del punto 5.

Línea base: `ecbb7b97ad79124e34f1a924227d27dd8585c737`. El árbol de aplicación inicial era `ed23ef494093755055f1b236a37d9830fe3220f9`; los cambios de aplicación de esta etapa están en el árbol de trabajo. Esta ejecución no creó commit, rama ni artefacto de publicación; tampoco hizo push, sincronización remota o deploy. Se preservaron las notas previas del usuario. Main conserva su seguimiento a `avancecorp/main` y estaba 8 commits por delante al iniciar.

**Cambio concurrente preservado:** durante la verificación, otra ejecución publicó el commit documental `8a9afa75fd053cac08869df62f08188d14a8c5ad` y actualizó Main/remoto (21:55:53 Lima). Sólo modificó una nota F2.b, `MIGRACIONES.md` y el plan HTML; el árbol versionado de `app` siguió exactamente igual al inicial. No se atribuye esa publicación a este trabajo ni implica que estas correcciones locales estén publicadas. Las 34 funciones revisadas se volvieron a contrastar después, sin diferencias.

## Cambios implementados

### Resumen, Conversiones y foto mensual

- Llegadas únicas, base automática y base histórica se nombran por separado. El divisor mensual ya no se presenta como todos los leads recibidos. No se recalcula el índice de conversión.
- El índice del rango y los resultados por origen reutilizan `sondasNucleoVerificadas`. Si viene un núcleo sin verificación válida, sus cifras se ocultan; no se reemplazan silenciosamente por otro porcentaje mensual.
- Las tarjetas y gráficos de la cohorte dicen «Reunión o avance posterior» y «Avance comercial inferido». No afirman asistencia a partir de propuesta/cierre. Las citas registradas de Resumen conservan la lectura independiente del servidor de citas.
- Los resultados por origen y por analista se identifican como cierres observados hasta hoy entre las llegadas del rango, no conversión ponderada. El seguimiento por semana se agrupa por **semana de llegada**, no por fecha de cierre. Se retiró la comparación del gráfico semanal contra una meta mensual de otra definición.
- El detalle de capital distingue operaciones del rango atribuidas al analista de capital vinculado a las llegadas por origen. Este último no se describe como producción de operaciones ocurridas en el rango.
- El selector comercial sólo ofrece Landing, Formulario y Referido, usando el catálogo existente. El origen filtra la cohorte y sus resultados, no el índice general ni las citas registradas. El encabezado identifica el rango y el mes de metas/capital.
- La comprobación existente de mes/revisión/estado de cierre ahora se aplica **antes** de entregar la foto mensual a Resumen y Metas, no sólo como aviso. Las fuentes discordantes quedan no disponibles; el núcleo válido del rango continúa independiente.
- Una actualización fallida con datos anteriores los identifica como la última lectura disponible, sin actualizar. Sin respuesta válida no se afirma «sin actividad». Una meta desconocida se distingue de una meta comprobada en cero.
- El cumplimiento superior al 100 % conserva el porcentaje completo; sólo se limita el ancho de las barras.
- En celular, los gráficos por analista y de avance inferido conservan un ancho mínimo dentro de un contenedor desplazable, con aviso y acceso por teclado. No se cambian sus valores ni escalas; se evita comprimir las etiquetas unas sobre otras.

### Pantallas relacionadas

- **Rendimiento:** base y conversión consultan el mismo mes calendario del encabezado; capacidad/carga se identifican como actuales. Se retiran asignaciones repetidas, salidas operativas y porcentajes de resolución de asignaciones de tarjetas, orden y tabla. Repartir conserva estos datos operativos, con rótulos de asignación y sin llamarlos conversión comercial.
- **Ranking y Equipo:** base automática o histórica según la fuente de la foto; identidad, pesos y fotografías históricas siguen intactos.
- **Por empresa:** la consulta de cooperativas recibe el mismo mes que la foto de cumplimiento. Sin foto de un analista, Avance es «—», no una resta desde cero. La demo recorta el mes en Lima y respeta ATR-4: anular conversión no retira capital.
- **Citas:** muestra canceladas por asesor/sistema y vencidas sin resultado; conserva porcentajes servidos y explica su denominador. Se retira la fracción por modalidad cuyo divisor bruto no respaldaba el porcentaje ajustado. Un porcentaje nulo no se grafica como cero.
- **Pipeline y Leads:** cierres del mes no se confunden con inventario de convertidos visible durante 45 días. Los filtros del listado/columnas se distinguen de los indicadores del ámbito global.
- **Base para gestión:** errores de meses y de registros se separan; la carpeta espera la carga del mes correspondiente, permite reintentar y no presenta contadores de cero ni registros del mes anterior como actuales.
- **Alertas:** ausencia de avisos no garantiza que todos cumplan la meta; se explica falta de corte/muestra/meta/verificación. El enlace aplica el período que originó la alerta y limpia el origen antes de navegar, mediante el contexto existente. La muestra se llama base de conversión, no recibidos.
- **Cartera y nueva renovación:** sólo rótulos/alcance de filtros en esta etapa. «Elegible» no promete aporte efectivo; «renovación registrada» sustituye «1 conversión». El núcleo sigue seleccionando y ponderando las operaciones.
- **Configuración SLA:** la lectura inicial termina hoy en Lima, no al fin de mes futuro; no se cambian políticas ni cálculos.

## Verificación

- Unitarios/integración: **2.695 pruebas aprobadas en 189 archivos** tras las últimas correcciones semánticas y de disponibilidad.
- Navegador completo: **117 pruebas aprobadas, 26 omitidas preexistentes**, sin fallos. Las omisiones pertenecen a `clientes.spec.ts` y `contratos.spec.ts`, pantallas retiradas en la fase 6 con cobertura trasladada a Cartera/altas/detalle. No se agregaron omisiones.
- Después del remate de ancho móvil: **108 pruebas dirigidas** de Resumen/Conversiones/conexiones y **5 pruebas de navegador** aprobadas. Incluyen ausencia frente a cero, foto discordante, rango/origen, capturas, ausencia de desborde global y desplazamiento horizontal con teclado.
- Tipos y build final (`npm run build`), control de bundle (`npm run verify:bundle`) y `git diff --check`: aprobados. El build mantiene avisos no bloqueantes por tamaño de chunk e importación estática/dinámica de `demo-config`; no se alteró la configuración para ocultarlos.
- Inspección visual local: Resumen y Conversiones en escritorio y a 390 px, Citas en escritorio. Capturas reproducibles desde `e2e/graficas.spec.ts`, dentro de `app/test-results/graficas-resumen-de-Gerenc-91ede-s-en-las-lecturas-simuladas-chromium/`. Son datos simulados, no cifras de producción. La prueba regenera las capturas; el directorio de resultados no se incorpora al código versionado.
- La primera ejecución completa de navegador detectó un selector antiguo «Leads activos» en un test de alta demo; se actualizó al nuevo rótulo y se conservó la comprobación de incremento en vivo. No se debilitó el comportamiento probado.
- Las pruebas de navegador usan `127.0.0.1:5199`, Supabase ficticio en `127.0.0.1:59999` y respuestas simuladas. Incluso los casos llamados «sesión real» simulan autenticación y RPC; no escriben producción. No se ejecutaron semillas ni mutantes SQL.
- Lint terminó sin errores; siguen cuatro avisos de accesibilidad en `coverflow-carousel.tsx`, archivo no modificado. El control de duplicación pasó con 0,70 % de líneas, debajo de 0,8 %; no es una certificación de ausencia absoluta de duplicados.

### Servidor y reglas protegidas

Consulta de catálogo en transacción `begin read only`/`rollback`, con límite de 15 s, completada a las 02:49:25 UTC y repetida después del cambio concurrente a las **2026-09-05 03:00:11 UTC / 2026-09-04 22:00:11 Lima**. Se compararon las mismas 34 funciones del inventario verificado a las 02:21 UTC: ninguna cambió de definición (`md5(pg_get_functiondef)`), firma, propietario, permisos, opciones, volatilidad o modo de ejecución. No hubo funciones faltantes. Es evidencia de esos cortes, no una garantía contra cambios externos posteriores.

El diff local no toca SQL/migraciones, `src/data`, contratos/esquemas de lectura, tipos generados, autenticación ni bibliotecas canónicas de conversión, objetivos o sondas. No se agregaron funciones de negocio, núcleos, RPC ni calculadoras independientes; se ajustaron consumidores, rótulos, parámetros existentes y estados de disponibilidad. Las sumas/restas de presentación que ya existían no se convirtieron en nuevas fuentes canónicas.

Context7 se utilizó para confirmar el tratamiento de caché/error/refetch de TanStack Query; se conserva el último dato sólo con aviso explícito. La guía de Supabase se aplicó a la comprobación de catálogo de sólo lectura. No hubo cambios de dependencias ni de infraestructura.

## Pendiente después de esta etapa

1. **Punto 3:** conciliar las lecturas existentes de Cartera, exclusión de pruebas y completitud, antes de conectar el agregado. Cualquier cambio SQL exige mostrarlo y pedir confirmación; no cambiar el núcleo de capital.
2. **Punto 4:** justificar antes de ampliar: leads únicos con cita real en la cohorte, divisor ajustado por modalidad, aporte efectivo individual de cada operación y cierres por fecha real de cierre. No inventar esos datos en el navegador.
3. **Punto 5:** conciliación integral posterior, incluida Cartera real y los casos que se aprueben.

Límite de navegación de Alertas: el contexto conserva el período en el clic normal de la misma pestaña. Abrir el enlace en otra pestaña no transmite ese contexto porque las rutas existentes no codifican período/origen; no se introdujo un sistema de rutas nuevo.

Publicar sigue requiriendo autorización y [[Main unico - sincronizacion y publicacion 2026-09-04]]. El build de comprobación local no se debe subir: una publicación debe reconstruirse desde el commit de Main sincronizado y verificado.

**Cierre del punto 2:** completado localmente el 4 de septiembre de 2026, 22:05 America/Lima. Siguiente punto pendiente: 3. No interpretar este cierre como autorización de publicación, SQL ni cierre de los puntos 3–5.

---
tags: [crm, gerencia, citas, auditoria, frontend, metricas]
fecha: 2026-09-07
estado: diagnosticado-sin-implementar
---

# Auditoría de Citas de Gerencia — frontend y contrato backend

Solicitud: revisar Citas de Gerencia como en [[Auditoria Gerencia frontend y consumo backend 2026-09-07]], enumerar problemas y soluciones concretas. Esta labor es diagnóstico; no autoriza una fórmula nueva ni cambios a los núcleos. Antecedentes: [[Inventario de indicadores de Gerencia - Citas y operacion]], [[Inventario de indicadores de Gerencia - Contrato de lectura]], [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]], [[Correccion de los siete hallazgos de Gerencia 2026-09-07]] e [[Inicio]].

## Fuente y alcance

- Pantalla real de Gerencia, usuario CV, ruta `#/reuniones` en `crm.miavance.com`.
- Se inició con `build-20260907T173338443Z` / commit `a6eefa74bfd2a444233f7ccd55a3168904990cb9`. Durante el trabajo se publicó Rentabilidad. Se actualizó y repitió la lectura con `build-20260907T175013676Z` / commit `82b25d175680b750ce11aa049a882bfebc0b9fa5`; el componente de Citas y su esquema no cambiaron entre esos commits.
- Código publicado en checkout limpio y separado: `/private/tmp/auditoria-citas-codigo-20260907`. Todas las referencias de código de esta nota usan ese commit, prefijo `CRM-Avance-Corp/app/`.
- CodeGraph fue la primera herramienta de ubicación; al devolver contexto insuficiente se complementó con lecturas dirigidas.
- Capturas actuales, árbol accesible y respuestas HTTP reales de `crm.metricas_reuniones_fn`: 1–7 de septiembre y 1–31 de agosto de 2026. Se verificaron parámetros y período devuelto.
- SQL de solo lectura: definiciones productivas de la fachada, agregador, núcleo de citas y filtro de responsables; agregados de episodios de citas/conversión/capital. Sin escrituras, impersonación de usuarios, nuevas funciones ni cambios de permisos.
- Evidencia local: `/private/tmp/auditoria-citas-gerencia-20260907/`. Respuestas sin cabeceras ni credenciales: `respuesta-citas-20260901-20260907.json`, `respuesta-citas-20260801-20260831.json`; SQL vivo y `comprobaciones-servidor.json`.
- La sesión se cerró temporalmente. Al recuperarse se completó la prueba en una pestaña aparte y se restauró el rango 1–7 de septiembre. No se alteraron citas, clientes, capital, estados ni código de aplicación. No hubo build, commit, push o deploy de esta auditoría.

## Recorrido comprobado

1. Cabecera, fechas y KPI: carga correcta; interpretación comercial confusa. Capturas `03`, `05` y `06`.
2. Modalidades, origen y resultado: las cifras se renderizan desde el payload, pero los títulos ocultan el alcance. Capturas `04` y `07`.
3. Tabla por analista: porcentajes sin base visible y diferencia histórica entre suma de filas y total global. Captura `04` y árboles accesibles guardados.
4. Cambio a agosto y retorno a septiembre: el filtro envía y recibe las fechas correctas. Captura `08`; la comparación permite reproducir el residual histórico.

Las capturas se guardaron y se inspeccionaron antes de aceptarlas. No se hizo una auditoría completa de accesibilidad ni se forzaron fallos de red. Los subtítulos pequeños y de poco contraste visual son un riesgo de legibilidad; no se afirma incumplimiento de contraste medido.

## Hallazgos

### CIT-01 — El total histórico y la tabla por analista no se reconcilian

**Evidencia:** agosto devuelve 48 pactadas y 6 realizadas. Las diez filas de `responsables` suman 44 pactadas y 5 realizadas. En septiembre sí suman 55 y 7, por lo que revisar solamente el mes actual oculta el problema.

**Causa:** `crm.metricas_reuniones_fn` pasa la respuesta a `private.filtrar_desglose_sujetos_crm(..., 'responsables', 'responsable_id', array['vendedor','supervisor'])`. El filtro comprueba el rol actual y modifica sólo el array. Los cuatro eventos restantes, incluida una realizada, tienen responsable sin rol elegible actualmente. Los totales globales conservan los eventos. El frontend presenta las filas como todo el resultado y no informa el residual.

**Solución:** conservar el total del servidor y mostrar explícitamente lo que queda fuera del desglose actual, con sus cantidades. No eliminar historia ni reducir el total a la suma del roster visible. La tabla vive en `src/screens/hoy/reuniones-gerencia.tsx:66`. Si se necesitan identidades o razones detalladas del residual, deben venir en la respuesta existente; no eludir el filtro de roles.

### CIT-02 — «Terminan en cliente» no significa todos los prospectos atendidos que cerraron

**Evidencia:** septiembre muestra 0%, aunque un prospecto del conjunto de siete atendidos tiene cierre reconocido el 1 de septiembre a las **15:59:40.232184 Lima** y cita programada a las **16:00:00**. La consulta lo excluye por aproximadamente veinte segundos. El marcado de conversión es del mismo instante, no una fecha comercial truncada a medianoche.

**Causa:** el agregador toma la última cita realizada del rango por lead y exige que el cierre sea igual o posterior a su `vence_en` (hora prevista). Busca cierres hasta hoy, incluso posteriores al rango seleccionado. No verifica una relación causal ni mide toda la conversión comercial ponderada. Se divide entre prospectos únicos atendidos, no entre todas las citas. `clientes` y `contratos` son aquí dos nombres del mismo conteo: usar `contratos` no causa por sí solo una diferencia numérica.

**Solución inmediata de frontend:** expresar que son cierres atribuidos a las citas bajo la regla vigente, mostrar el numerador y los prospectos únicos de base y el corte de seguimiento. No presentar 0 como prueba de ausencia de cierres en el grupo. Si se pretende incluir el caso mencionado, se debe revisar la comparación temporal del **agregador existente**; cambiar sólo el frontend inventaría otro resultado. El diagnóstico no demuestra a qué hora ocurrió realmente la reunión ni autoriza atribuirle esa venta.

**Fuente:** componente líneas 113, 125, 154 y 163; SQL vivo guardado, `private.metricas_reuniones_implementacion.sql:80` y `:92`.

### CIT-03 — Dos porcentajes destacados con bases distintas poco visibles

**Evidencia:** siete realizadas de 55 pactadas conviven con 21,2% de asistencia y 16,7% de realización. El primero es 7 / (7 realizadas + 26 no-show). El segundo es 7 / 42 computables: 49 vencidas menos cinco canceladas por sistema y dos reprogramadas. Ninguno es 7 / 55.

**Impacto:** gerencia puede interpretar que la pantalla se contradice aunque las dos fórmulas estén bien ejecutadas. La explicación en texto pequeño aparece después de varias tarjetas.

**Solución:** un porcentaje principal con nombre inequívoco y base visible; la segunda lectura en detalle. Consumir las métricas existentes. El divisor global se puede explicar con los desgloses servidos; no cambiar la fórmula ni restar todas las canceladas/reprogramadas sin distinguir cuáles vencieron. Componente líneas 112–127. Agosto reproduce el patrón: 6/48, asistencia 25% y realización 15%.

### CIT-04 — Las vencidas sin resultado están bajo «Reprogramadas»

**Evidencia:** tarjeta `Reprogramadas: 2` con subtítulo `7 vencidas sin resultado registrado`; agosto muestra `1` y `9`. Son conjuntos diferentes, no un detalle del mismo indicador.

**Solución:** dar a «Vencidas sin resultado» un bloque propio y separar «Reprogramadas». Ambos campos ya llegan del servidor; sólo requiere corregir la presentación. Componente línea 124. Es también el pendiente operativo que merece visibilidad para gerencia.

### CIT-05 — La «Efectividad» del analista no se puede explicar con las columnas mostradas

**Evidencia:** Antonella aparece con cinco pactadas, dos realizadas y 66,7%. La base real es tres: hay una cita futura y una cancelada por sistema. Nayra aparece con 22 pactadas, tres realizadas y 17,6%; su base real es 17, tras tres futuras y dos reprogramadas.

**Causa:** la tabla muestra pactadas y realizadas, pero omite la base del porcentaje. Además, la regla por responsable excluye cancelaciones efectuadas por otro asesor, una diferencia respecto del total. El payload de responsables no expone hoy todos los campos para reconstruir fielmente ese divisor.

**Solución:** mostrar «2 de 3 computables» y sus exclusiones, con el porcentaje ya servido. Para una explicación completa por analista hay que proyectar el divisor y exclusiones ya calculados dentro del agregador existente, como ya se hizo por modalidad. No deducir la base invirtiendo un porcentaje redondeado ni dividir entre pactadas. Componente líneas 72–76; esquema `src/lib/metricas-reuniones.ts:81`.

### CIT-06 — «6 próximas» parece toda la agenda futura, pero sólo cubre el rango

**Evidencia:** el 1–7 de septiembre muestra seis próximas. En la lectura actual existen además 23 pendientes futuras desde el 8 de septiembre, fuera del rango. En agosto la tarjeta muestra cero próximas pese a que la empresa sí tiene agenda posterior.

**Solución:** rotular «6 próximas dentro del período», o ubicar la agenda futura en su lectura operativa correspondiente. No sumar esos 23 al KPI de septiembre sin declarar un cambio de alcance. Es un problema de etiqueta, no de filtro mal enviado. Componente línea 120; núcleo de citas recorta primero por `vence_en`.

### CIT-07 — «Capital invertido» oculta la selección y el reloj del capital

**Evidencia:** las dos modalidades muestran S/ 0. El prospecto del caso CIT-02 tiene un episodio de capital asociado por **S/ 200.000**, pero queda fuera por la misma regla de atribución temporal. No es un segundo fallo aritmético independiente: es una consecuencia de esa selección.

**Problema adicional de alcance:** el agregador consulta capital `medida='stock'` sin recorte temporal del capital y suma la moneda indicada en el lead, sólo para leads con cierre atribuido. Por tanto, el dato no representa capital captado durante el período de citas ni todo el capital de los atendidos.

**Solución:** identificarlo como capital asociado a los cierres atribuidos a esas citas, explicitando que el capital no se recorta por el rango. Si se quiere capital producido en el período, usar la lectura existente que responda esa pregunta; no renombrar este valor como captación. Componente línea 156; SQL vivo líneas 47, 63–75 y 196–202.

### CIT-08 — «Resultado final» contiene resultados intermedios de la reunión

**Evidencia:** cuatro «Interesado», dos «Seguimiento» y uno «Inicia registro». Agosto incluye «Propuesta». Son valores de `resultado_reunion` de las citas realizadas; no el desenlace comercial final ni el estado actual de venta de cada prospecto.

**Solución:** «Resultado registrado de la cita». Mantener los valores originales y separar ese bloque de los cierres. Sólo frontend. Componente línea 164; SQL vivo líneas 190–194.

## Lo que se comprobó correcto

- Se usa la RPC de Citas existente; el frontend no calcula los porcentajes operativos por su cuenta.
- Parámetros, clave de caché y validación del período coinciden. El cambio real septiembre → agosto obtuvo las cifras del período solicitado y se restauró septiembre.
- El total de estados cuadra: septiembre 7 realizadas + 26 no-show + 2 canceladas por asesor + 5 por sistema + 2 reprogramadas + 7 vencidas sin resultado + 6 futuras = 55. Agosto suma 48.
- Las bases por modalidad se reciben y se explican: septiembre presencial 3/20 = 15%; virtual 4/22 = 18,2%.
- Por origen, la respuesta contiene formulario y landing con base y 0%; `otro` tiene base cero y porcentaje null. El gráfico no demuestra pérdida de origen ni convierte hoy null en cero: distingue «sin base para calcular».
- Citas y el índice comercial ponderado son poblaciones diferentes. No se concluye que Upgrades deban convertirse artificialmente en origen de cita por compartir la palabra «conversión».

## Alcance de una corrección posterior

La mayor parte se resuelve presentando con precisión campos existentes. CIT-01 puede comenzar por hacer visible el residual del desglose sin eliminar historia. CIT-05 requiere que la respuesta existente entregue el divisor y exclusiones si se quiere explicar cada porcentaje. Cambiar qué cierre se atribuye a una cita (CIT-02) requiere revisar la regla del agregador existente; el frontend no debe sustituir al backend. No hacen falta funciones paralelas ni editar los núcleos para las correcciones de presentación descritas.

---
fecha: 2026-09-05
serial: AVC-UX-GERENCIA-FIGMA-20260905-R1
estado: f0-documentada-pendiente-contraste-gerencia
tags: [crm, ux, gerencia, figma, continuidad]
---

# F0 de Gerencia — tablero y base UX preparados

Relacionado con [[AVC-UX-GERENCIA-FIGMA-20260905-R1]], [[Plan de mejora UX de Gerencia - revision 2026-09-05]], [[Conexion Figma MCP verificada - UX Gerencia 2026-09-05]], [[Fundamentos UX del CRM]] e [[Inventario de indicadores de Gerencia - Contrato de lectura]].

Miguel indicó «vamos con la f0». Se completó la preparación documental de F0 mediante llamadas reales al MCP remoto de Figma. **El contraste de tareas con Gerencia permanece pendiente; F0 no está validada con usuarios.**

## Archivo real

- [Gerencia · UX de reportes · Avance Corp](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=2-6).
- Destino: Borradores de **El equipo de Avance Corp**. Cuenta autenticada de Miguel; plan Profesional y asiento Full verificados en la conexión previa.
- `fileKey`: `1FEvjQkwSzNDsGJ7UUvqIK`. Conservar este archivo; no crear un duplicado al retomar.
- Abierto y comprobado en la ventana habitual de Chrome, perfil Avance Corp.

| Página | Contenido comprobado | Acceso |
| --- | --- | --- |
| 00 · Auditoría y tareas | 14 capturas originales y notas editables. Una fila, 200 px entre imágenes. 28 enlaces de hallazgos a tareas. | [Auditoría](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=3-2) |
| 01 · Componentes del CRM | Inventario de 9 familias, fuentes de código, estados y estilos observados. | [Inventario](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=15-2) |
| 06 · Validación y decisiones | 7 tareas, criterios observables, línea de base conocida y registro pendiente. | [Tareas](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=15-5) |

Las capturas conservan su condición de evidencia de demo. El catálogo es documentación editable de componentes existentes en código; **no es todavía una biblioteca nativa de componentes del piloto**. Las páginas de F1–F4, pantallas propuestas y prototipo se crearán al ejecutar esas fases.

## Hallazgos y decisiones para continuar

1. La biblioteca existente «Avance Corp's team library» (`Jaai3MViA7OEUjxnm3bNzW`) se inspeccionó sin modificarla. Contiene la plantilla de aprendizaje, cero componentes, cero variables y estilos de ejemplo Fuschia/Iris. No se identificó una biblioteca publicada representativa del CRM; no importar una biblioteca genérica como sustituto del sistema del producto.
2. Fuente de diseño: código actual y capturas. Gerencia usa IBM Plex Sans y valores propios en `components/gerencia/gerencia.css`; la base general utiliza Plus Jakarta Sans y `index.css`. Las diferencias de paleta, incluido verde/teal frente al criterio general de la casa, quedan registradas. F0 no realiza una homologación global.
3. Inventario C1–C9: cabecera/acciones, período/origen, pestañas, tabla/lista móvil, indicador/moneda, panel de detalle, estados de datos, botones, señal de atención/capacidad. CodeGraph se utilizó primero, complementado con búsquedas y lecturas puntuales cuando la respuesta no contenía la pieza solicitada.
4. El código de `clasificarRankingCapitalTotal` confirma el orden por cumplimiento descendente, seguido de capital y nombre. El piloto debe hacerlo explícito y conservar esa regla. No cambiar fórmulas ni conciliar ejemplos sintéticos mediante el diseño.
5. Prioridades F1: conservar «Capital total» al volver del detalle y recuperar título/período en móvil. Repetir la secuencia exacta de la captura 6 y el viewport 390 × 844 de la captura 14.

## Verificación y límites

Se comprobaron 14 cargas correctas, destino de cada imagen, correspondencia de `imageHash`, dimensiones originales y SHA-256 sin cambios. Se inspeccionaron los 14 renders del tablero, la portada, el catálogo, los estilos y las tareas; se corrigió el fondo transparente de las exportaciones. La comprobación final confirma orden, espacios de 200 px, notas dentro de sus marcos y enlaces de tareas.

La evidencia sigue siendo la auditoría experta de la demo del 5 de septiembre, con datos sintéticos. No hubo nueva observación de usuarios ni medición de tiempos. No se modificó código de la aplicación, backend, permisos o fórmulas; no se publicó. Se preservaron los cambios concurrentes existentes del repositorio.

## Línea de base pendiente y siguiente paso

Se propusieron T1 detectar un asunto, T2 explicar una cifra/base, T3 comparar responsables, T4 detalle/regreso, T5 señal/acción, T6 consultar/administrar metas y T7 uso móvil/reunión. Cada tarea tiene escenario, éxito observable y evidencia vinculada.

Se preguntó por la última consulta real de Gerencia y la decisión que necesitaba tomar; aún no hay respuesta registrada. Falta contrastar frecuencia, prioridad, uso real del celular y formato de reunión; observar interpretación, ayuda, pasos, errores y tiempo por tarea. No inferir resultados desde la auditoría o desde la duración de llamadas automáticas.

La observación pendiente no impide preparar F1 conforme al plan. El siguiente trabajo de diseño es la biblioteca mínima y el piloto editable de Ranking en escritorio/móvil con detalle y regreso; implementación y validación del CRM siguen pendientes.

## Artefactos para retomar

- [Informe de F0 con los 14 renders y las tareas](../../output/ux-gerencia-f0-2026-09-05/F0-gerencia.md).
- `output/ux-gerencia-f0-2026-09-05/state.json`: nodos reales, páginas, fichas, tareas y estado.
- `manifest.json`: fuentes, tamaños, notas y huellas de las 14 capturas.
- `componentes.json`, `tareas.json`, `resumen-verificacion.json`, `verificacion-imagenes.json` y `evidencia/` en el mismo directorio.
- `calls/`: solicitudes y resultados de MCP. Las credenciales temporales de subida no se guardaron en el repositorio.

Si las herramientas de Figma siguen sin aparecer directamente en el catálogo de la conversación, la conexión configurada funciona mediante el cliente determinista `/private/tmp/avc-figma-mcp.mjs`, usando `codex app-server --stdio` y `mcpServer/tool/call`. No inicia un turno de modelo. No reutilizar la creación de archivo ni las llamadas de inserción ya completadas; leer `state.json` y consultar el archivo primero. Los archivos en `/private/tmp` son temporales: no asumir que existirán en otra sesión.

# Desarrollo UX Gerencia — AVC-UX-GERENCIA-FIGMA-20260905-R1

Plan vigente: BASE DE CONOCIMINETO/AVANCECORP/Plan de mejora UX de Gerencia - revision 2026-09-05.md.
Autorización: Miguel pidió desarrollar todo, autoevaluarse y seguir el plan. F1 → F2 → F3 → F4, con F5 en cada fase. Diseño → revisar recorrido → frontend → verificación.

## Estado
- F0: auditoría técnica y tablero terminados; observación real pendiente.
- F1: base de Figma creada y verificada (72 variables, 8 estilos de texto, 2 sombras); 6 familias nativas construidas. Piloto de escritorio compuesto y móvil en composición; frontend con cabecera móvil, detalle de capital y conservación del contexto en implementación. Falta cerrar el recorrido y cotejo visual.
- F2: fuentes y capturas actuales de Resumen/Citas comprobadas; 3 familias adicionales de componentes creadas en Figma. Composición de pantallas en curso.
- F3: comparación y Conversiones pendientes.
- F4: recorridos a operaciones, metas y capacidad pendientes. Exportación condicionada a la necesidad de Gerencia.
- F5: línea base 112 pruebas aprobadas en 6 archivos. Última comprobación incremental: tipos correctos y 75 pruebas en 4 archivos; comprobación de cambios recientes y tareas reales en curso.

## Control del alcance
Se guardaron huellas de 851 archivos de lib y Supabase; hay trabajo previo de otra sesión en backend, que no se modifica. El hash guardado refleja ese estado inicial; un cambio concurrente se revisará sin revertirlo. No se publicará esta entrega por inferencia.

## Evidencia
- state.json: todos los identificadores devueltos por Figma MCP.
- calls/: solicitudes y respuestas reales del conector.
- evidencia/: capturas verificables.
- alcance-componentes.json: valores y correspondencia de la biblioteca.
- baseline-protegido.json: huellas de los archivos protegidos.

## Comprobaciones de referencia
2026-09-05: npm run test:run de conversion-vendedores, ranking-vendedores, periodo-context, topbar, resumen-gerencia y reuniones-gerencia: 6 archivos, 112 pruebas aprobadas. Aviso previo de Node sobre localStorage experimental; sin fallos.

## Correcciones durante la autoevaluación
- Nombre de radio con punto rechazado por Figma; se usa radius/11-2 conservando 11.2 px.
- Salto de línea de documentación corregido antes de reintentar. Se añadió validación sintáctica local de cada script Figma.
- Se capturó Ranking / Capital total desde Chrome Avance Corp demo (47:2), y se retiró el control temporal de captura del HTML. index.html sin diff final.

## F1: recorrido comprobado
- Chrome demo, 390 × 844: Capital total → Carla → Conversiones → regreso. Conservó Capital total, mes 2026-09, scroll 135.5 y foco ranking-analista-demo-v3-lista.
- A 320 × 844: se detectó recorte adicional del título y solapamiento de pestañas; corregidos. Título medido: 68.53 px. Pestañas verticales de 44/44/48 px.
- 41 pruebas focales de Ranking y desglose aprobadas; cuatro pruebas nuevas cubren teclado, cifras/identidad, error/cambio de base y ausencia de TC. Typecheck aprobado.
- Figma: piloto 66:2 / 69:156; detalle 72:305 / 73:480; reacciones de apertura y vuelta verificadas por MCP. Falta probar el visor y completar el enlace simulado a Conversiones.
- Nueve familias nativas disponibles. QA visual de las tres últimas en curso.

## Avance F2 · 2026-09-06 02:04 UTC

- Resumen y Citas implementados localmente, con cuatro indicadores principales por vista, señal de citas con alcance acotado y accesos a evidencia. No hay publicación en producción.
- Resumen conserva las fuentes disponibles ante fallos parciales; carga y ausencia no se convierten en cero ni en ausencia de meta.
- Citas: salto a responsables con foco, lista móvil y valores de respaldo para ambos gráficos. Datos anteriores sólo con estado explícito de actualización fallida y período de la respuesta.
- Pruebas: 32 de Resumen/Altas y 18 de Citas aprobadas; se inicia regresión combinada F1–F2.
- CUA: 320×844 y 390×844 sin desbordamiento horizontal; foco en citas-resultados-analistas verificado. Capturas parejas de Citas móvil después de corregir fuentes, fechas, altura de controles y alcance de atención.
- Figma: 12 estados adicionales (sin pendientes, sin actividad y error inicial, en ambos dispositivos y reportes). IDs reales en state.json.
- F3: cobertura de comparación inspeccionada; se reutilizará adaptarConversionMensual.responsablesDisponibles y estados canónicos. No habrá agregación entre filas ni comparación de meses distintos. Diseño en curso.
- Pendiente antes del cierre técnico: terminar pares de Resumen, F1 y estados, interacciones en visor Figma; F3/F4; validación humana F0/F5.

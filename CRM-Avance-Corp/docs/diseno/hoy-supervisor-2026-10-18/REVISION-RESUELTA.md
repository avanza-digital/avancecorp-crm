# Evaluación del review por el PRIMARY

Una revisión entregada por `scripts/claude-review`: CHANGES_REQUESTED / MEDIUM.
El primer intento restringido no completó el review y no se contabiliza como dictamen.
La salida completa está en `REVISION-CLAUDE.txt`. No se pidió un segundo dictamen.

- **Base de meta (P1, hipótesis): aceptado aclarar, no acreditado como bug.**
  `objetivos.ts:157` y `:787` agregan categorías de meta y cumplimiento;
  `datos-supervisor.ts:171-174` los llama sin filtrar categoría. `metaVigente`
  conserva la misma foto. La maqueta ahora declara que las cuatro categorías
  computan en su ejemplo. La conciliación con producción y la clasificación de
  adicionales de renovación siguen como requisito de integración.
- **Metas y conversión individuales (P2): evidencia completada.**
  `objetivosDesdeConfiguracion` expone `porVendedor` y agrega por supervisor
  (`objetivos.ts:136-153`). `adaptarConversionMensual` consume responsables y
  `conversion_pct` (`conversion-vendedores.ts:534-587`). No son datos inexistentes.
  Se conserva como pendiente la cobertura/autorización real y la paridad de ámbitos.
- **Meta de conversión (P2): hipótesis rechazada por código.**
  Existe `metaConversionAplicable` (`objetivos.ts:185`) y Hoy la usa
  (`datos-supervisor.ts:169`). El 12% es ficticio como todo el ejemplo, no una
  nueva regla impuesta al CRM ni una afirmación sobre la meta productiva.
- **Citas (P2): aceptado.** Ahora son 13 previstas, 7 realizadas, 4 pendientes,
  2 inasistencias y 0 anuladas. Los estados están explícitos en el fixture y
  se suman; no se infieren por resta. El agregado real sigue pendiente de validar.
- **Estados sin dato (P3): aceptado.** Se agregó «Si faltan datos» con ejemplos
  de Sin meta, Muestra insuficiente, No disponible, Provisional y cero confirmado.
- **Universo mensual/actual y selección de intervenciones (P3): aceptado en el
  análisis.** La tabla compuesta necesita unión por identidad autorizada, marcas
  de traslado y reglas deterministas, sin juicios de incumplimiento a mitad de mes.
- **Código de prototipo (P3): documentado.** Datos constantes; la implementación
  productiva usará React y los formateadores existentes.

También se corrigieron dos hallazgos de revisión directa: un texto de acceso que
prometía otro desglose y un texto accesible con posición absoluta que desbordaba
el ancho móvil. Las primeras gestiones con cero ahora dicen 0, no «—».

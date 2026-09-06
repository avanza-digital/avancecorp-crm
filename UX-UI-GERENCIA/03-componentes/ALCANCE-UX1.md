# UX1 — Biblioteca del bloque A

Revisión del 6 de septiembre de 2026, autorizada por Miguel para avanzar con el plan principal. Este alcance prepara componentes y pantallas en Figma; la revisión visual del bloque A precede a su implementación.

## Decisiones verificadas

- Conservar las nueve familias actuales, sus 30 variantes, las tres colecciones con 72 variables, ocho estilos de texto y dos efectos. Los tokens tienen alcance explícito y sintaxis web; no hacen falta colores, fuentes ni dependencias nuevas para este bloque.
- Plus Jakarta Sans pertenece a la estructura general; IBM Plex Sans a reportes. Se conservan ambas. Navy y azul comunican resultado/objetivo con etiquetas, sin añadir verde como éxito. Los tokens verdes antiguos permanecen como antecedente del código, sin extender su uso.
- No se encontraron archivos Code Connect en `app/src`. El mapa se obtiene de las instancias reales del archivo Figma y se documenta con rutas de código; no se afirma sincronización automática.
- MCP verificó la biblioteca actual y los recursos disponibles. La búsqueda de Indicador no encontró una alternativa; se amplía la composición propia sobre `Gerencia/Indicador`. Los recursos externos ya evaluados siguen como referencia de anatomía, sin sustituir componentes del CRM.

## Trabajo de este bloque

| ID | Entrega | Fuente y aceptación |
| --- | --- | --- |
| P1.a | Fundamentos y correspondencia | Mantener valores, alcances, tipografías y alias existentes. Registrar diferencias Figma/código. |
| P1.b | Indicador visual reutilizable | Componer el indicador actual con barras de cantidad/meta y contexto. Variantes para capital, conversión y citas, en escritorio y móvil. No cambia cálculos. |
| P1.c | Período compacto móvil | Convertir la propuesta existente en componente vinculado; conservar rango, origen y acción de filtros de 44 px. |
| P1.d | Estados y anatomía documentados | Conservar carga, vacío, error, sin base y sin TC; mostrar instancias adaptadas al móvil y documentar cero, parcial y actualización. La cobertura total de UX4 sigue en su fase. |
| P2.a | Resumen | Preservar la dirección de escritorio elegida. Compactar el móvil y adelantar la evolución, manteniendo cifras, bases y acceso al detalle. |
| P2.b | Conversiones | Comparación por analista junto a la conversión mensual; resultados del rango, citas y cierres agrupados después. Mantener título y definiciones vigentes. |
| P2.c | Revisión | Capturas antes/después, desbordamiento, tipografías, tamaños táctiles y navegación del ejemplo. Registrar límites del prototipo. |

## Diferencias entre Figma y código

`IndicadorGerencia` presenta etiqueta, valor y contexto; las barras añadidas son una composición propuesta, con `Progress`/gráficos existentes como base futura. El período compacto y las nuevas posiciones son diseño, todavía no comportamiento implementado. La maqueta usa cifras fijas de septiembre de 2026: no debe atribuirse recálculo real a sus filtros.

El resultado no cierra F0: siguen pendientes prioridades/frecuencias confirmadas y observación humana. UX2 requiere revisión visual de Miguel antes de continuar frontend.

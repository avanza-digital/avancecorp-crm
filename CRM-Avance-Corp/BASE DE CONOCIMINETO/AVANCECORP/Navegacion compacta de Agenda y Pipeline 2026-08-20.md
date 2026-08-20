# Navegación compacta de Agenda y Pipeline — 2026-08-20

Relacionado con [[Historial de derivaciones de Coordinacion]] y [[Centro de ayuda del vendedor]].

## Decisión de experiencia

Agenda y Pipeline son espacios de trabajo, no reportes interminables. En
escritorio sus filtros y resumen permanecen visibles y el detalle se trabaja
dentro de una bandeja de altura acotada. En móvil se conserva el desplazamiento
natural del dispositivo, pero los datos se entregan paginados.

## Límites operativos

- Pipeline muestra **20 leads por etapa y página**. Cada columna conserva su
  propia página y desplazamiento vertical; cambiar de página no acumula cards
  en el DOM.
- Agenda muestra **12 tareas por página** para un vendedor y **8 personas por
  página** para supervisión. El detalle expandido de una persona se desplaza
  dentro de su propia tarjeta.
- Semana presenta hasta **4 tareas por día y página**; Mes usa la misma bandeja
  paginada de 12 tareas para el día elegido.
- Los contadores siempre indican el rango y el total, por ejemplo `21–40 de
  73`, para que una página compacta nunca parezca que oculta información.

## Operación preservada

- Pipeline mantiene arrastrar y soltar, el menú para mover etapa y el alta de
  un lead desde su columna.
- Agenda mantiene abrir ficha, contacto, cierre y reprogramación de cada
  tarea. La paginación no cambia la fuente de verdad ni los filtros.

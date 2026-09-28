# Respuesta de Codex (27/09) — gerencia «como el supervisor»

Aplicado en 9bdb1a2d: ceros del total abribles, «0 sin registro» visible, scroll-margin bajo el pie pegado. Hábitos (hipótesis): la regla estrecha de una columna va después y gana; lo rehace G3.

**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

Las pastillas y la tabla comparten el criterio de filtrado; el total conserva las cifras autoritativas y propaga la atención desconocida como `null` cuando alguna fila la tiene. Encontré una regresión demostrable al trasladar las cuatro cifras al pie: se pierden accesos cuando valen cero y desaparece «Sin registro».

**FINDINGS**

**[P2] El pie oculta «Sin registro: 0» y convierte cifras antes accionables en texto.**

**Archivo:** `src/components/gestion-diaria/tabla-equipos-gerencia.tsx`, funciones `CifrasEquipo` e `Integrantes`.

**Evidencia:**

- Llamadas: `f.llamadas > 0 ? <button ...> ... : <span className="font-semibold">0</span>`.
- Citas: `f.citas > 0 ? <button ...> ... : '0'`.
- Sin registro: `f.sinRegistro > 0 && ...`.
- El componente eliminado `CifrasOperacion` representaba las cuatro cifras mediante botones, sin condicionar su existencia a un valor positivo.

**Impacto:** cuando todos tienen actividad, «Sin registro: 0» desaparece del total, aunque la decisión exige conservar las cuatro cifras allí. Cuando llamadas o citas valen cero, ya no pueden abrirse mediante teclado ni ratón, incumpliendo «todo número se abre». El nuevo test de cero actividad comprueba el texto, pero deja de comprobar esos accesos.

**Recomendación:** conservar explícitamente las cuatro cifras en «Toda la operación», incluidos sus ceros y sus acciones. Puede limitarse este ajuste al total.

**TEST GAPS**

- Añadir cobertura de «Sin registro: 0» visible y de la activación de llamadas, citas y sin registro con valor cero.
- Verificar en el registro compacto que cambiar equipo limpia el analista seleccionado, que el CSV corresponde al ámbito y pestaña actuales, y que con cero filas no descarga y conserva el foco.
- Comprobar en navegador la devolución del foco al cerrar una ficha abierta por URL, tanto estrecha como ampliada. El efecto sin dependencias limpia `focoPendiente` antes de restaurar el foco; eso no demuestra un bucle.
- Verificación propia: **NOT RUN**, conforme al aislamiento del reviewer. El PRIMARY reporta el E2E **EN CURSO**; el `check` completo aportado corresponde al primer commit.

**REGRESSION RISKS**

- **Hipótesis — Hábitos:** `.gp-espacio.gd-espacio` impone dos columnas sin condición de ancho en el fragmento mostrado. Faltan las reglas restantes para confirmar que sigue habiendo una columna por debajo del umbral. Validar ambos lados de 1040 px y móvil.
- **Pendiente de verificar:** el `tfoot` sticky podría cubrir un control enfocado del cuerpo. Comprobar navegación por teclado con desplazamiento vertical y horizontal.
- Los controles nuevos del registro están condicionados por `permitirEquipo` y `permitirExportar`. No hay evidencia suficiente para afirmar una regresión del supervisor o analista; conviene verificar sus consumidores compactos.

**RECOMMENDED NEXT ACTIONS**

1. Restituir las cifras y acciones con valor cero en el total.
2. Incorporar los casos anteriores y completar el E2E local.
3. Contrastar capturas de gerencia y supervisor: los tests geométricos aportados no acreditan por sí solos la equivalencia visual solicitada.

**CONFIDENCE: MEDIUM**

Alta para el hallazgo de los ceros; limitada para comportamiento visual y foco por la ausencia de ejecución y de los componentes completos.

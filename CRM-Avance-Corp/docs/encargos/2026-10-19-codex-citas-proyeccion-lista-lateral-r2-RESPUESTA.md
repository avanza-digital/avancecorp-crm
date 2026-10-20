**VERDICT:** REQUEST CHANGES — queda una vía de desbordamiento en escritorio.

**SUMMARY:** La extracción conserva los datos, el `caption`, las cabeceras y `scope="row"`. No encuentro regresiones en la Ayuda ni cambios colaterales del stub entre los consumidores enumerados. El corte de 1 080 px es conservador: `980 / 0,92 ≈ 1 065,22`; su comentario justifica incorrectamente esos 15 px adicionales, pero no genera desbordamiento.

**FINDINGS P0–P3**

- **P2 — El contenido todavía puede ensanchar la tabla más allá del panel.** En [proyeccion.css:127](/Users/usuario/dev/avancecorp-crm-lista-lateral/CRM-Avance-Corp/app/src/components/citas/proyeccion.css:127), la tabla conserva distribución automática y las celdas mantienen `white-space: nowrap`. Las reglas de las líneas 132–133 permiten separar nombres por espacios, pero no romper palabras largas; `min-width` tampoco limita su anchura. Además, [MontoCita:31](/Users/usuario/dev/avancecorp-crm-lista-lateral/CRM-Avance-Corp/app/src/components/citas/proyeccion-detalle.tsx:31) mantiene dólares y conversión en esa misma línea indivisible.

  Caso concreto para reproducir: total con Analista, nombre `INVERSIONESINMOBILIARIASINTERNACIONALESDELASAMERICAS`, estado «Cancelada por sistema», origen «Referido» y monto USD `1_000_000_000`, convertido a `3_750_000_000`. La anchura mínima del contenido sigue imponiéndose a `width: 100%`; incluso los máximos de distintas citas se acumulan por columna. El cambio a tarjetas depende exclusivamente de la ventana, por lo que no protege este caso en escritorio. **Es una limitación verificable del CSS; no aporto una medición de navegador de ese caso.**

**TEST GAPS:** Checks y navegador **NOT RUN por mí**; los resultados indicados son reportados. La medición con diez citas no acredita los extremos anteriores. Faltan los límites 1 079/1 080 y comprobar explícitamente la tabla después de volver desde tarjetas; el test unitario desmonta y monta de nuevo.

**NEXT ACTIONS:** Permitir romper nombres sin espacios y distribuir el importe original y su conversión en varias líneas. Verificar también el estado largo sin recortes. Añadir una comprobación de desbordamiento con esos datos a 1 080 y 1 440 px.

**CONFIDENCE:** Alta sobre paridad, semántica y limitación del CSS; media sobre el alcance práctico del desbordamiento, pendiente de medición.

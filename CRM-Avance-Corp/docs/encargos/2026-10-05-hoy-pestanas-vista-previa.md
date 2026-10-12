# HOY: vista previa de agenda y leads por pestañas

Miguel corrigió la distribución publicada: «Tus citas» no debe reducirse. Pidió
«Tu agenda de hoy» como botón junto a «Leads de hoy», manteniendo la distribución
general; después pidió ver cómo quedaría. Esta nueva distribución es solo vista
previa: NO se publicó ni se actualizó la PR #191.

Implementación de preview en `/private/tmp/avancecorp-hoy-20261005-release`, sobre
el publicado `a98cf73fbd2866`: las pestañas reemplazan la cabecera de la tarjeta
izquierda, agenda por defecto; los leads usan su espacio al seleccionarlos.
Citas recupera toda la columna derecha; cumplimiento permanece abajo a la
izquierda. Se reutiliza Tabs del proyecto y las consultas existentes.

PASS: typecheck, lint (los cuatro avisos previos), 71 tests dirigidos y E2E Docker
2/2. El E2E comprueba el mismo rectángulo de citas antes/después de cambiar de
pestaña, más de 200px útiles de lista en portátil, paginación, abrir ficha y error.
Check integral y nueva publicación: NOT RUN, pendiente de confirmar esta vista.

Capturas y parche: `app/artifacts/hoy-propuesta-pestanas/`. Cuenta y datos
sintéticos; avisos de tasa ya configurados en el fixture. Sin acceso productivo.

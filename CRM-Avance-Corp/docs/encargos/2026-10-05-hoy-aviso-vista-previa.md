# Aviso de leads nuevos — propuesta local

Miguel aprobó visualmente las pestañas de agenda/leads y pidió ver una propuesta
que llame la atención al recibir leads. Solicitó verla **en local**.

Vista: http://127.0.0.1:5187/#/hoy, analista demo. Botón naranja suave con punto,
etiqueta «3 nuevos» y tres pulsos breves. Al abrir la pestaña desaparece el aviso
y queda el total. Al volver a agenda y simular otra llegada, reaparece «1 nuevo».
«Tus citas» conserva la columna. Controles de simulación separados, en el menú lateral.

Es una simulación de diseño, no una implementación de detección real ni una publicación.
Los fixtures y el estado son sintéticos. No modifica backend ni archivos del producto.
Vite aplica transformaciones solo al servir la vista previa. Reduced motion suprime el pulso.

- Servidor: `/private/tmp/hoy-preview-local.mjs`.
- Plugin: `/private/tmp/hoy-aviso-preview/aviso-plugin.mjs`.
- App previa: `/private/tmp/avancecorp-hoy-20261005-release/CRM-Avance-Corp/app`.
- Copias: `app/artifacts/hoy-propuesta-aviso/` (rutas absolutas locales en el lanzador).
- Validación de sintaxis de ambos scripts: PASS.
- Recorrido en Chrome: aviso 3 → abrir lista de 3 → volver agenda → simular llegada → aviso 1: PASS.
- Gate de producción y E2E Docker del aviso: NOT RUN; alcance solo propuesta visual servida por plugin fuera del código de producto.

Pendiente: decisión del usuario sobre la propuesta. Para integrarla realmente,
el contador debe consultar recepción del día aunque la pestaña no esté montada,
separar total recibido de no vistos, y recordar revisión por analista/día.
No trasladar fixtures ni controles de simulación al producto.

## Segunda propuesta: urgencia sin texto adicional

Miguel pidió que el número avise con más urgencia, sin añadir textos.
La vista actual muestra solo «7» dentro de una burbuja naranja intensa, número
blanco y dos latidos durante 1,6 segundos al inicio de cada ciclo de 30 segundos.
Se retiraron «nuevos» y el punto. Al abrir los leads, el contador queda gris y
sin animación. Reiniciar vuelve al ejemplo de siete recibidos. Reduced motion
mantiene el color y desactiva el movimiento.

Validado en Chrome: contador 7, animación `hoy-aviso-latido`/30s; abrir muestra
siete filas, contador gris y animación `none`: PASS. Sintaxis del plugin: PASS.
Sigue siendo únicamente una propuesta local con datos sintéticos.

## Corrección vigente: el aviso continúa con la pestaña abierta

Miguel aclaró que quiere el efecto del número también después de hacer clic
en «Leads de hoy». La propuesta ya no borra el aviso al seleccionar la pestaña.
El «7» conserva naranja, blanco y latido de 30 s en ambos estados; la pestaña
activa conserva texto y subrayado azul. Al cambiar de pestaña se reinicia el
latido para poder apreciarlo inmediatamente. Llegadas simuladas mantienen el
aviso también con la lista abierta. La condición de negocio para finalizar la
urgencia sigue pendiente; esta demostración no implementa estados de atención.

Chrome verificado con `aria-selected=true`, lista de siete leads visible,
contador `rgb(185,78,6)` y `hoy-aviso-latido`/30s: PASS. Se dejó abierta la lista
en local. Esta corrección reemplaza el apagado al abrir descrito antes.

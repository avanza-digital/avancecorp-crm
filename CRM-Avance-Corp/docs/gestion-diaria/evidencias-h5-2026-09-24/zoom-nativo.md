# H5 — zoom nativo de Chrome

24/09/2026, aproximadamente 00:14–00:15 Lima. Verificación con CUA en Chrome
de la vista local `http://127.0.0.1:4177/#/gestion-diaria`, sesión **Supervisor
DEMO**. Entorno iniciado con `VITE_ENABLE_DEMO=true`, backend loopback ficticio
y las mismas variables públicas sintéticas del banco E2E. Sin sesión productiva.

- Se ocultó el menú y se aplicó el zoom con los controles nativos del navegador.
  El árbol accesible de Chrome confirmó literalmente **«Zoom: 200%»**.
- La tabla se adaptó a filas con rótulos. Seleccionar ANALISTA UNO abrió el
  diálogo con foco en su título. Texto, pestañas y cierre permanecieron legibles;
  el contenido inferior usa scroll interno.
- Con Tab, Tab y flecha derecha se activó Registro. Chrome confirmó Registro
  seleccionado, el filtro de etapa y las tres gestiones demo legibles.
- Escape cerró el detalle y devolvió el foco a «Seleccionar a ANALISTA UNO».
  Se restauró **100%**, confirmado por Chrome.

La captura nativa y el árbol accesible quedaron en la conversación. Las
capturas automatizadas equivalentes y reproducibles se guardan en esta carpeta.
Esta revisión visual/teclado no es una certificación WCAG ni una prueba humana
con lector de pantalla. VoiceOver/NVDA y Safari: **NOT RUN**.

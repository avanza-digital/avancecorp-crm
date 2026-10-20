**VERDICT: REQUEST_CHANGES**

**SUMMARY:** Dos hallazgos P2. No encontré una discrepancia demostrable entre tarjeta y celda: comparten métricas, cifras y apertura de listas. «Citas del periodo» utiliza directamente las citas del total, lo que preserva su correspondencia por construcción.

**FINDINGS P0–P3**

- **P2 — La nueva Ayuda promete listas que algunas cifras positivas no abren.** [propuesta.tsx:55](/Users/usuario/dev/avancecorp-crm-proyeccion-f3/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx:55) dice «Cada número abre su lista de citas». Sin embargo, `Derivada` devuelve un `<span>` y se utiliza para Ticket y Proyectado ([proyeccion-cifras.tsx:21](/Users/usuario/dev/avancecorp-crm-proyeccion-f3/CRM-Avance-Corp/app/src/components/citas/proyeccion-cifras.tsx:21)). Caso concreto: el test móvil muestra **Ticket cita S/9,375 de Ana**, pero exige que `ticket` y `proyectado` carezcan de botón. La limitación existía en escritorio; Fase 3 la conserva y añade una promesa falsa en la Ayuda. También contradice el requisito recibido de hacer accionable cada cifra.

- **P2 — El detalle de los tramos móviles incumple el mínimo de 14 px.** [proyeccion.css:171](/Users/usuario/dev/avancecorp-crm-proyeccion-f3/CRM-Avance-Corp/app/src/components/citas/proyeccion.css:171) fija `font-size: 13px` para `.pc-tarjeta-tramos .pc-tiempo-cab small`. `CabeceraTramo` coloca ahí `tramo.detalle` ([proyeccion-cifras.tsx:52](/Users/usuario/dev/avancecorp-crm-proyeccion-f3/CRM-Avance-Corp/app/src/components/citas/proyeccion-cifras.tsx:52)): por ejemplo, el intervalo **8–14 oct** debajo de S2. Es información de detalle expresamente cubierta por la regla del dueño.

**TEST GAPS**

- El CSV nuevo se prueba sin embudos y con **Mín de Citas**. Falta contrastar sus identificadores con la lista del total tras combinar personas, moneda y Mín/Máx.
- Las pruebas móviles comprueban ejemplos y recuentos; no comparan exhaustivamente cifras e identidades de listas entre escritorio y tarjetas conservando filtros y orden.
- El E2E del embudo comprueba `x` y anchura, pero no `y` ni altura: no valida la nueva apertura hacia arriba ni que el contenido quede dentro de la pantalla verticalmente.
- Falta cubrir el cambio de breakpoint con un embudo abierto y verificar tamaños tipográficos mediante estilos calculados.
- **NOT RUN por mí:** Vitest, oxlint, tsc, jscpd, check completo y E2E Docker. Los resultados verdes y trabajos en curso son los reportados en el encargo.

**NEXT ACTIONS:** Hacer accionables Ticket y Proyectado conforme al requisito y ajustar las pruebas; elevar el detalle temporal a 14 px; añadir las comprobaciones específicas anteriores y cerrar las verificaciones pendientes.

**CONFIDENCE:** Alta en ambos hallazgos; media para el conjunto. Revisión limitada al diff adjunto: sin acceso al repositorio ni ejecución. El comportamiento completo de foco depende de partes de `DropdownMenu` y `EmbudoColumna` no incluidas.

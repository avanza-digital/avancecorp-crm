# Ficha anterior adaptada a multiempresa — 15/09/2026

**Estado: preparada y verificada localmente; pendiente de revisión visual de Miguel. No publicada.**

Abrir [COMPARACION.html](COMPARACION.html) para comparar la ficha anterior y la adaptación por rol y tamaño de pantalla. Incluye el detalle abierto y un ejemplo con tres empresas y dos monedas. Las capturas usan datos sintéticos y llamadas interceptadas al banco local de Playwright; no contienen clientes de producción.

## Resultado

- Recuperada la composición de `ClienteFicha`: panel de 620 px, cabecera compacta, continuidad comercial, seguimiento, tarjetas de inversiones, información agrupada, historial y acciones al pie.
- Tarjetas e historial comparten componentes de presentación con la ficha anterior. El título puede envolver líneas y el capital puede bajar en pantallas estrechas para evitar desbordamientos.
- Las tarjetas muestran estado, importe, vencimiento y avisos operativos; **Ver inversión** despliega condiciones, documentos y demás detalle. PDF pendiente y anulación comercial siguen visibles con la tarjeta cerrada.
- Los importes, cantidades y vencimiento de continuidad proceden de la respuesta canónica. Se distingue capital activo de registrado según el dato disponible, tanto en la ficha como en el resumen de cartera; cada empresa y moneda conserva su grupo.
- Postventa coloca sus controles en las secciones compartidas. Una caída o desactivación de F6 mantiene el detalle y el foco de la ficha; recuperar F6 exige lectura nueva y no reabre una gestión anterior. Un envío en curso sigue su mecanismo de recuperación existente.
- Las capacidades del núcleo gobiernan banca, documentos y operaciones. COOPAC conserva plazo, fechas y rentabilidad anual pactada, con los mismos escritores existentes.

La comparación reproduce la misma persona y contrato sintéticos en las dos rutas. El responsable y las condiciones operativas del fixture antiguo pueden diferir del fixture F5; la igualdad que se evalúa es la composición visual y los permisos se prueban por rol. No se promete igualdad de todos los textos o acciones.

## Verificación final

| Comprobación | Resultado |
| --- | --- |
| `npm run check` | **PASS**, 245 archivos y **3.596 pruebas**; lint, tipos, cobertura, configuración de release, build, bundle y duplicación |
| Dos suites focales de fichas | **PASS**, 54 pruebas |
| Playwright F5, F6, ficha anterior y comparación | **PASS**, **23 recorridos** Chromium |
| Galería local | **PASS**, 8 combinaciones de selectores y enlaces locales; render de escritorio inspeccionado |
| Inspección de capturas finales | **PASS**, escritorio, móvil y tres empresas/dos monedas |
| `git diff --check` | **PASS** |
| `npm run gate:realidad -- --json` | **NOT RUN**: faltan las variables del entorno real (`SUPABASE_URL`); el intento terminó antes de consultar datos |
| Matriz E2E completa de toda la aplicación | **NOT RUN**: se ejecutaron los 23 recorridos pertinentes a este cambio |
| Recorrido manual de producción / conformidad visual G7 | **NOT RUN**, pendiente; no había navegador de usuario conectado |

El lint conserva cuatro advertencias existentes en `coverflow-carousel.tsx`, fuera del cambio. Los errores de consola de los mocks incluyen rechazos previstos y lectores no implementados por el fixture; no son llamadas a producción. Los selectores de las nuevas pruebas se ajustaron al título accesible real del diálogo y a su restitución asíncrona de foco antes del PASS final.

Comandos ejecutados desde `CRM-Avance-Corp/app`:

```sh
npm run check
npm test -- --run src/screens/cartera-inversionistas.test.tsx src/components/app/cliente-ficha.test.tsx
npm run test:e2e -- e2e/ficha-multiempresa-visual.spec.ts e2e/f5-cartera.spec.ts e2e/f6-postventa.spec.ts e2e/mi-cartera-detalle.spec.ts --grep 'ficha neutral|móvil: búsqueda|revocación|tres empresas|un fallo de ficha|agenda compartida|móvil: recupera|veto impide|Gerencia consulta|Directorio no recibe|un rechazo|conserva la ficha anterior|real:' --workers=2
```

Las rutas de logs, sus huellas y las de los archivos de código verificados están en [VERIFICACION.json](VERIFICACION.json). No se modificaron SQL, banderas o datos de producción ni se creó otro banco de pago.

## Revisión independiente y decisiones del PRIMARY

Claude revisó por `scripts/claude-review`, como SECONDARY_REVIEWER sin herramientas ni escritura. Ambos dictámenes fueron **CHANGES_REQUESTED**, sin P0/P1: [primero](REVISION-CLAUDE-1.md) y [segundo](REVISION-CLAUDE-2.md). No se presenta una aprobación de Claude posterior a las últimas correcciones.

Codex resolvió y verificó:

1. **Capital activo/registrado y cantidad**: etiquetas por dato en continuidad y `ResumenEmpresas`; pruebas con Avance sin activo, COOPAC con activo cero y total canónico mayor que la página visible.
2. **Avisos y PDF pendiente**: visibles antes de desplegar el detalle, con prueba de regresión.
3. **Nombre accesible**: incluye el texto visible; inversiones sin número se identifican dentro de su grupo de empresa y moneda, con prueba.
4. **Continuidad F6**: árbol estable, consulta desactivada fuera de capacidad y lectura nueva al reactivar. Dos pruebas adicionales abren Agendar/Retiro durante un corte y confirman que la ventana no reaparece al recuperar F6; también se verifica que pueda abrirse de nuevo voluntariamente.
5. **Presentación**: badge demo ámbar, ayuda de responsable en Seguimiento y controles ausentes para Directorio. El ajuste de envoltura de títulos de la tarjeta compartida se acepta para evitar desbordamiento.
6. **Hipótesis sobre permiso de Recuperar PDF**: no se introdujo un cambio en su condición. El diff conserva `i.pdf?.reintentable && onRecuperarPdf` y el callback condicionado por frescura; `abrirDocumento` sigue invocando el escritor/descargador existente. `archivarContratoPdfConfirmado` llama `ensure` de `crm-contrato-pdf-v2`; su actor usa el token del usuario para verificar sesión y llamar RPC. Esta revisión visual no sustituye una nueva matriz de autorización real.

El PRIMARY ejecutó el gate y los recorridos finales después de esas correcciones; no se inició una tercera revisión para buscar un dictamen favorable.

## Retoma

Revisar la comparación con Miguel. Después, si corresponde publicar, integrar `avancecorp/main`, comprobar el commit común y construir/publicar únicamente desde él siguiendo el procedimiento del proyecto. Esta entrega no cierra G7 ni F8; la publicación productiva previa y el piloto nominal continúan como estaban documentados.

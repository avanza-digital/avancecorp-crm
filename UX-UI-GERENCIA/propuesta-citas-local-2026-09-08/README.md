# Citas de Gerencia — propuesta local

Prototipo navegable para encontrar citas, identificar pendientes y comparar la actividad del equipo. Contiene 40 citas ficticias y un escenario fijo al 7 de septiembre de 2026, 13:00, hora de Lima.

## Abrir

Desde la raíz del repositorio:

```sh
python3 -m http.server 4178 --bind 127.0.0.1 --directory CRM-Avance-Corp/app/prototypes
```

Abrir http://127.0.0.1:4178/citas-gerencia.html. Si el servidor de la sesión sigue activo, basta abrir el enlace. El prototipo no necesita build ni dependencias de red.

## Tres propuestas complementarias

1. **Bandeja comercial, recomendada:** una fila por cita, responsable visible, estado y siguiente paso. Prioriza citas vencidas sin resultado.
2. **Agenda por día:** fecha, hora y modalidad para revisar la carga del equipo.
3. **Resultados del equipo:** conteos por analista y estado; acceso a las citas que explican cada fila.

Las tres conservan una misma consulta. Hay búsqueda por nombre, teléfono y código; supervisor; analista dependiente del supervisor; período o rango inclusivo de fechas; varios estados; modalidad; origen; resultado; seguimiento; moneda y rango de monto. Incluye filtros removibles, restablecimiento, orden, paginación, exportación CSV de todas las filas filtradas y detalle de cita.

Los montos se filtran después de elegir una moneda. No se suman soles con dólares. Los atajos de estado muestran el conteo de los otros filtros, sin aplicar la selección de estado actual.

## Alcance

Código en `CRM-Avance-Corp/app/prototypes/citas-gerencia.html` y `citas-assets/`. No modifica el módulo real, las consultas del servidor ni la base de datos. No requiere cambios de dependencias. La consulta real consumida por `ReunionesGerenciaPanel` entrega agregados; conectar esta propuesta requiere una consulta autorizada con filas por cita. Los indicadores comerciales de realización y asistencia deben conservar sus bases actuales al integrar.

Las fuentes IBM Plex Sans y los iconos Lucide proceden de las dependencias instaladas del proyecto. Sus licencias se conservan en `citas-assets/LICENSE-IBM-PLEX.txt` y `LICENSE-LUCIDE.txt`.

## Verificación final del PRIMARY

- **PASS:** sintaxis de `citas.js` y `model.mjs` con `node --check`.
- **PASS:** lint específico de los tres archivos JS/MJS, sin avisos.
- **PASS:** 10/10 pruebas con `node --test prototypes/citas-assets/citas.test.mjs`, desde `CRM-Avance-Corp/app`.
- **PASS:** Chrome, filtros combinados y conservación entre vistas, navegación al detalle y a la agenda, cierre con Escape y recuperación del foco, Tab dentro del detalle y flecha derecha entre pestañas.
- **PASS:** disposición a 390 px CSS y escritorio; sin desbordamiento horizontal a 390 px. Capturas finales adjuntas.
- **NOT RUN:** gate integral, build y E2E del CRM; no hay cambios de TypeScript/React ni importaciones del prototipo en el runtime del CRM.
- **NOT RUN:** auditoría completa con lector de pantalla y matriz de navegadores. Los controles tienen etiquetas, estados, foco visible, mensajes de validación asociados y avisos accesibles; estas comprobaciones no certifican conformidad completa.

El banco cubre filtros, fechas y montos inválidos, monedas, búsquedas con tildes, conciliación de conteos, orden, paginación, CSV, existencia de recursos y contenido seguro en todas las vistas y el detalle. JSDOM usa dobles de `showModal`/`close` limitados al estado `open`; el foco modal se revisa en Chrome y no se atribuye a esos dobles.

## Revisión independiente y decisión

Una consulta a Claude con `scripts/claude-review`, rol SECONDARY_REVIEWER, evidencia ficticia y sin herramientas de escritura. Dictamen previo: `CHANGES_REQUESTED`.

Se incorporaron escape consistente del contenido, asociaciones de validación, anuncios sin repetición innecesaria y con demora breve al escribir, estado de exportación accesible, validación de fechas reales y protección de celdas CSV ante fórmulas y espacios iniciales. Se corrigió también el escape del contexto de una cita realizada y se probó contenido hostil en el detalle.

Se descartaron con evidencia dos hipótesis: colisión con tests del CRM (`vitest.config.ts` incluye solo `src/**/*.test.{ts,tsx}` y TypeScript solo `src`) y fallo de visibilidad (`[hidden]{display:none!important}` ya existe y tiene comprobación de estilo calculado). Los períodos fijos pertenecen al escenario ficticio; el CSV conserva coma estándar, pues la preferencia de Excel depende de la configuración. La versión corregida pasó el banco y la revisión de navegador del PRIMARY; no se atribuye a Claude una aprobación posterior.

## Capturas

- [Bandeja](bandeja.png)
- [Las tres propuestas](propuestas.png)
- [Móvil](movil.png)

Todas las capturas de esta carpeta contienen datos ficticios.

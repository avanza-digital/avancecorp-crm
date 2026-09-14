# Citas — propuesta local de avance mensual

Vista: <http://127.0.0.1:4180/prototypes/citas-avance.html>.

Solicitud: mostrar en local el repaso de reglas del 13/09. Es una propuesta interactiva con datos ficticios, no la activación del módulo productivo.

## Qué se puede revisar

- Marco del CRM, menú compartido, IBM Plex Sans, Button, Select y Sheet del proyecto.
- Filtros compactos de mes, semana de seguimiento, supervisor, analista, origen, registro y moneda. El selector de analistas depende del supervisor.
- Recorrido horizontal por personas, etapas vinculadas y fechas cronológicas. Las listas completas se recorren con paginación; cada persona abre su historial.
- Tabla mensual con leads incluidos los manuales y sin citas, citas/promedio, cumplimiento de la meta interna, entrevistas/asistencia70%, clientes/conversión70%, ticket mensual y cierre estimado. Incluye una analista sin citas, sin inventar ticket ni proyección.
- Detalle del analista con cantidades que faltan, fórmulas propuestas y acceso a todos sus leads, también los que no tienen citas.
- Bandeja y agenda funcionales sobre las mismas citas de ejemplo; filtro de estado local a esas vistas. Exportación CSV mensual con indicación de datos ficticios y base propuesta de conversión.

La meta de1,25 se usa internamente, sin rotularla como objetivo en el tablero. Por ejemplo, Ana tiene160 leads y100 citas:50% de cumplimiento de200 citas. Sus70 entrevistas pertenecen a60 personas y42 se convierten a cliente. La asistencia77,8% usa90 citas con resultado; quedan5 sin resultado y5 futuras fuera de esa tasa. Su recuperación contiene20 personas que faltaron,12 que reprogramaron,8 que asistieron después y5 que se convirtieron.

## Decisiones que siguen siendo propuestas

«Cómo se calcula» permite comparar clientes/personas entrevistadas y clientes/entrevistas; no guarda esta elección en el CRM. Se inicia con personas únicas. La decisión del usuario de contar cada visita no confirma automáticamente este denominador de conversión.

La semana delimita recorrido, bandeja y agenda. En Resultados aparece una línea de actividad semanal; la tabla, el ticket y la proyección permanecen mensuales. Esta distinción está visible.

La proyección utiliza el ritmo de citas registradas al13/09 para estimar el cierre del30/09, tasas actuales, repetición de entrevistados y población elegible. El ticket sale del importe de las conversiones ficticias del mismo mes, en la misma moneda. El importe estimado incluye lo ya captado. Las expectativas conservan decimales internamente; la cantidad de clientes se presenta como aproximada. El total suma las estimaciones individuales y señala cuando es parcial; no usa promedios simples de tasas ni de tickets.

El ejemplo contiene solamente septiembre de2026 y soles. Agosto o dólares muestran ausencia de datos, sin cambiar etiquetas sobre importes existentes. No modela reasignaciones ni conversiones entre meses: las reglas de atribución y vigencia del módulo real siguen pendientes.

## Verificación

### Ajuste posterior de semántica de colores

La petición posterior fue relacionar el color con el resultado. La propuesta reutiliza `SEMAFORO` y `colorVsObjetivo` del CRM: azul para meta alcanzada, ámbar para avance inferior a la meta pero de al menos su mitad, rojo para brecha mayor y gris cuando no existe una base para evaluar. El color lleva un icono, una leyenda y una descripción accesible. Cada indicador del analista abre su detalle; la interacción funciona con teclado y devuelve el foco al cerrar.

Para el volumen mensual de citas, el estado considera un ritmo diario orientativo: al día 13 de septiembre, la referencia es 43,3% de la meta. El 50% de Ana queda «A ritmo», sin presentarlo como meta alcanzada ni retraso. El 0% de Paola sí indica una brecha; sus tasas sin denominador aparecen como «Sin base». La referencia se marca en la barra y se explica en la ayuda; no cambia la meta ni los cálculos existentes.

El recorrido conserva gris para el antecedente de inasistencia, azul para los pasos de recuperación y navy para los clientes. Los pendientes de nueva cita se destacan en ámbar sólo cuando existen. El ticket, la proyección y el porcentaje de recuperación no reciben un juicio contra una meta monetaria o una tasa que no les corresponde.

Verificación de este ajuste: lint específico, typecheck, cuatro pruebas del modelo y build independiente en `/private/tmp/citas-avance-colores-20260913`: **PASS**. Navegador en cuatro anchos, lectura visual de capturas, apertura del detalle desde la alerta con teclado y contraste de los indicadores de al menos 4,5:1: **PASS**. Capturas y `verificacion-visual.json` actualizados. La propuesta se abrió de nuevo en Chrome. No se repitió el banco global ni se ejecutaron SQL/RLS o publicación para este cambio de presentación.

### Verificación de la creación de la propuesta

- Lint global y de archivos nuevos: PASS. Cuatro warnings preexistentes de `coverflow-carousel.tsx`, ajeno a esta vista.
- TypeScript: PASS.
- Pruebas globales: **3.474 PASS /241 archivos**, incluidas cuatro pruebas nuevas de coherencia (manuales, repetición, recorrido, cronología y límites con filtros).
- Build de aplicación: PASS, salida independiente `/private/tmp/citas-avance-20260913-app-build`; no se sobrescribió `app/dist`.
- Build de la entrada final del prototipo: PASS, salida independiente `/private/tmp/citas-avance-20260913-prototipo-final`.
- Navegador: `verificar.mjs` verifica cifras, filtros, detalle, paginación, teclado/retorno de foco, dos bases de conversión, estados vacíos, exportación y cuatro anchos (1440/1280/768/390). Evidencia final en `verificacion-visual.json` y capturas contiguas.

Durante la revisión se corrigieron las etiquetas accesibles de los selectores. La prueba móvil ahora carga la página a ese tamaño, para que el menú compartido inicie plegado, en lugar de heredar el estado abierto del escritorio. Se verifica que el título no quede tapado por el menú.

El navegador integrado no estaba disponible; la vista se abrió en Chrome. Chromium de pruebas necesitó permiso de macOS para arrancar; se ejecutó con la autorización concedida. No se observaron conexiones externas en la verificación de la propuesta.

**NOT RUN:** pruebas de esta propuesta con datos reales, SQL/RLS, activación de configuración y publicación. No aplican a la presentación local y no se presentan como completadas. No se modificaron componentes compartidos, reglas productivas, base de datos ni sesiones de otros trabajos. No se hizo commit ni deploy.

Fuentes nuevas: `CRM-Avance-Corp/app/prototypes/citas-avance.html` y `CRM-Avance-Corp/app/src/prototypes/citas-avance/`.

Para repetir la revisión visual desde la raíz del proyecto:

```bash
node UX-UI-GERENCIA/citas-avance-local-2026-09-13/verificar.mjs
```

Requiere el servidor local del CRM en4180. El servidor existente dejó de estar disponible al terminar la revisión; se inició uno nuevo en el puerto libre con `npm run dev -- --host 127.0.0.1 --port 4180 --strictPort`. Quedó activo y se comprobó la apertura final de la página en Chrome. No se detuvo otro servidor.

# Propuesta 3 implementada: detalle a demanda

Miguel eligió la tercera imagen del ajuste UX. Se adaptó el prototipo existente a [Detalle a demanda](../ajuste-ux/detalle-a-demanda.png), con los componentes y recursos del CRM. Es una consulta local con datos ficticios; no modifica las citas ni las metas de producción.

[Abrir prototipo local](http://127.0.0.1:4180/prototypes/citas-crm.html).

## Cómo usarlo

1. En **Resultados**, selecciona mes, semana comercial, supervisor o analista. **Más filtros** conserva los estados, modalidad, origen, resultado, seguimiento, moneda e importe.
2. Pulsa una etapa del flujo para ver sus personas. Conserva la base de recuperación y las métricas generales del analista. **Sin nueva cita** permite encontrar a quienes todavía requieren ese seguimiento.
3. Abre **Andrea Peralta** para consultar su ausencia, reprogramación, asistencia y depósito confirmado. En escritorio amplio puedes cambiar de persona o usar filtros con la ficha abierta; en ventanas menores se abre como panel modal.
4. Compara **citas por lead**, **cumplimiento** y **leads con 3+ citas**. Meta 3 = 100%; objetivo del promedio 3.75 = 125%. La flecha del analista abre sus leads; su nombre lleva a la bandeja filtrada.
5. **Columnas** recupera leads con 2+ citas, realizadas y supervisor. La ayuda explica bases, fórmulas y corte. Bandeja y Agenda mantienen los filtros. Exportar descarga todas las citas de la consulta, aunque estés en otra página.

El ejemplo conserva **4 → 3 → 1 → 1**, **25% = 1/4**, **S/35,000**. El equipo suma **40 citas / 26 leads**, promedio **1.54**, cumplimiento **51.3%** y **3 de 26** leads con 3+ citas. Andrea tiene **2 citas, 66.7%** y ya depositó; no necesita otra cita para validar su conversión.

Las cuatro semanas comerciales son 1–7, 8–14, 15–21 y 22–fin. La meta no se prorratea al elegir una semana. Los filtros determinan las citas de origen y la actividad del analista; el recorrido vinculado puede continuar fuera del período hasta el corte indicado.

## Evidencia

- [Tablero](tablero.png) y [ficha de Andrea](ficha-andrea.png), 1672 × 941.
- [Tablet](tablet.png), [móvil](movil.png) y [ficha móvil](movil-ficha.png).
- [Resultado de interacciones y medidas](interacciones.json).
- [QA visual](../../../../CRM-Avance-Corp/app/design-qa.md) y [evaluación de la revisión técnica](revision.md).

PASS: gate integral `npm run check` (218 archivos, 3106 tests, cobertura, lint, TypeScript, build, configuración de release, bundle y duplicación). Tras el último ajuste de CSS/copy se repitieron lint, las 32 pruebas del prototipo y el build con TypeScript. El lint conserva cuatro advertencias previas de `coverflow-carousel.tsx`, ajenas al cambio. Navegación local, filtros, vacío, exportación, foco, panel modal/no modal y anchos 1672/1280/1024/768/390 verificados en Chromium aislado; cero errores de consola.

NOT RUN: suite E2E completa de producción y pruebas con backend real. El recorrido se verificó en el prototipo con fixtures; no se ha integrado la política de metas con datos productivos.

Para reproducir desde la raíz del repositorio, con dependencias del CRM instaladas:

```sh
npm --prefix CRM-Avance-Corp/app run dev -- --host 127.0.0.1 --port 4180 --strictPort
```

En otra terminal:

```sh
node UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/verificar.mjs
```

La verificación usa su propio Chromium y actualiza las capturas de esta carpeta. `CITAS_QA_URL` permite cambiar la dirección del prototipo.

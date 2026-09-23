# Mejora visual de analista y supervisor

Pedido de Miguel del 23/09/2026. Referencias: `Fundamentos UX del CRM.md` del vault,
`UI-UX-playbook.pdf` y la decisión de dos paneles del encargo D.

## Diagnóstico y dirección

Se inspeccionaron en Chrome las dos pantallas demo, cargadas, antes de editar.
El analista necesita identificar el contacto y llamar; el supervisor necesita
comparar personas y abrir la evidencia de quienes requieren atención.

- Analista: la tarjeta de acción mide 340 px frente a una cola que supera 1200 px
  en una ventana amplia. La cabecera mezcla instrucciones, refresco y marcador.
  El teléfono y las acciones no forman un bloque claro.
- Supervisor: el resumen es un párrafo, los filtros quedan en extremos opuestos
  y los encabezados numéricos no coinciden con sus valores. Dos filas por persona
  consumen altura sin una jerarquía clara entre resultado, motivo y evidencia.
- En ambas: preservar los estados reales de carga, error, vacío y datos no
  evaluados; conservar foco, teclado, permisos, selección e identidad del lead.

## Sistema y composición

Paleta existente: navy `#111e3d`, azul `#2563eb`, fondo `#f6f8fc`, blanco,
ámbar `#d97706` y rojo `#dc2626`. Sin verde. Plus Jakarta Sans: títulos 700,
indicadores 800 y cifras tabulares, etiquetas 600, cuerpo mínimo 16 px.
Espacios 8/12/16/24/32, radio 12 px y separadores suaves. Controles ≥44 px.

```text
Analista
Pregunta y actualización                Mi actividad
┌ Ahora / contacto / contexto ┐  ┌ Cola de hoy / cuatro pestañas ┐
│ Teléfono y acción principal│  │ Selección y paginación        │
└────────────────────────────┘  └───────────────────────────────┘
Actividad, compromisos, descartes y registro: detalle progresivo

Supervisor
Pregunta y fecha                                      Actualizar
Resumen del equipo: cifras y significado en una sola franja
┌ Buscar analista / filtrar atención / cantidad / registro ┐
│ Analista       Llamadas   Contacto   Pendientes   Atención│
│ Datos comparables, motivo destacado, detalle y evidencia│
└────────────────────────────────────────────────────────┘
Criterios de lectura y cortes del equipo
```

La composición se apoya en las tareas existentes: no añade paneles decorativos,
gráficos sin pregunta ni indicadores inventados. La principal expresión visual
del analista es el contacto activo; la del supervisor es la comparación del equipo.

## Verificación

**Implementado y verificado en local el 23/09/2026.** Rama
`codex/gestion-diaria-ui`, en la copia aislada existente para no interferir con
la otra sesión. Se preservan consultas, RPC, permisos, registro y reglas de F4.

| Comprobación | Resultado y alcance |
|---|---|
| `npm run check` después de las correcciones | **PASS**: lint, typecheck, 279 archivos / 4.175 pruebas, cobertura, configuración de release, push tests, build, bundle y duplicación. Cuatro avisos previos de accesibilidad en `coverflow-carousel.tsx`; sin errores. |
| Docker: `gestion-diaria-analista.spec.ts` y `gestion-diaria-equipo.spec.ts` | **PASS: 13 passed / 0 failed**, 46,4 s. Contenedor `gestion-diaria-ui-e2e`, dos workers; datos sintéticos. |
| Revisión visual en Chrome | **PASS local**: analista y supervisor, escritorio y móvil, selección, jerarquía, filtros, detalle y registro. No equivale a aceptación de los usuarios. |
| Accesibilidad y navegación | **PASS en los recorridos cubiertos**: foco de Detalle y Ver registro con alto contraste, apertura/cierre por teclado, desplazamiento horario con flecha, retorno de foco y paginación revocada. Menú del analista con sus dos opciones dentro del viewport. |
| Revisión independiente de Claude | **CHANGES_REQUESTED**, sin P0/P1 demostrados. Correcciones evaluadas y aplicadas por Codex; después se repitieron los gates anteriores. No se declara PASS del reviewer. Véase el [acta](UI-REVISION-CLAUDE-2026-09-23.md). |
| `npm run gate:realidad` | **NOT RUN**: faltan `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` en el entorno de esta copia. El comando se intentó desde `CRM-Avance-Corp`; los fixtures no sustituyen el contraste contra producción. |
| Publicación y smoke productivo de esta mejora | **NOT RUN / pendientes**. |

Comando de los E2E desde `CRM-Avance-Corp/app`:

```bash
env CRM_E2E_CONTAINER=gestion-diaria-ui-e2e \
  CRM_E2E_VOLUME=gestion-diaria-f4-e2e-node-modules \
  CRM_E2E_TASK=gestion-diaria-ui \
  npm run test:e2e:docker -- \
  e2e/gestion-diaria-analista.spec.ts e2e/gestion-diaria-equipo.spec.ts
```

La primera ejecución detectó que el gráfico horario ensanchaba la tabla y no
respondía al desplazamiento por teclado. Se acotó el detalle al contenedor de
la tabla y se comprobó de nuevo el recorrido. Los artefactos locales de
Playwright quedan en `app/test-results/`; el gate integral final se guardó en
`/private/tmp/gestion-diaria-ui-check-revisado.log`.

Jev se usó únicamente como apoyo para priorizar el diagnóstico visual: clasificó
ambas pantallas como un problema de jerarquía. No recibió datos de clientes y su
clasificación no se cuenta como prueba ni aprobación.

La nueva UI todavía no está publicada. El avance de F4 y su jornada real del
24/09 conservan los estados del plan principal. El [mismo tablero de Figma](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L)
registra esta mejora por separado de las 76 casillas originales.

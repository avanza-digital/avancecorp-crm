# Resultados de hoy — implementación local, 18/10/2026

Sustituye la tarjeta «Acompañar el cierre» por las operaciones cerradas y el
capital del día. Reutiliza Facturación y abre un desglose por analista. La tarjeta
y su detalle comparten el agregado; PEN y USD permanecen separados. El aviso de
leads por repartir continúa independiente. No se publicó ni se usó navegador o Docker.

## Archivos

- `app/src/screens/hoy/supervisor-jornada.tsx` y `.css`: tarjeta, estados y detalle.
- `app/src/screens/hoy/use-resultados-hoy.ts`: consulta compartida de Facturación,
  disponibilidad, estado de los cortes y aislamiento demo.
- `app/src/screens/hoy/jornada-supervisor.ts`: suma por fecha y analista del ámbito ya autorizado.
- `app/src/lib/demo-metricas.ts`: proyección de los contratos demo existentes;
  sus fechas se conservan, aunque el resultado de hoy sea cero.
- `app/src/data/crm-api.ts`: metadato opcional de posible recorte, limitado al RPC
  tabular legado. El sobre JSON V2 no se confunde con un resultado truncado.
- Pruebas relacionadas de vista, hook, agregado, demo y frontera HTTP de Facturación.

## Revisión independiente y resolución

Claude actuó como SECONDARY_REVIEWER mediante `scripts/claude-review`. El primer
intento en sandbox no entregó un dictamen; se repitió fuera del sandbox con la
autorización del wrapper. El dictamen válido fue **CHANGES_REQUESTED**, confianza
MEDIA, conservado en `REVISION-RESULTADOS-CLAUDE.txt`. Codex implementó y verificó
las correcciones siguientes; no se pidió otra opinión para obtener un PASS.

| Hallazgo | Decisión y evidencia |
| --- | --- |
| P2: recorte local al supervisor directo | Aceptado. El agregado solo filtra por día; confía en el ámbito completo de Facturación. La demo se acota por separado a su supervisor. Una prueba conserva un analista de un sub-supervisor, al propio supervisor y la atribución histórica. |
| P2: hipótesis sobre el tipo y significado de `corte` | Resuelta con evidencia: `20261016204221_crm_capital_cortes_lecturas.sql:81` declara `corte date`, y `private.publicar_corte_capital` calcula hasta el día actual en Lima (líneas 145–158). La comparación ISO por fecha corresponde al contrato. Un corte anterior a hoy retira la cifra y muestra pendiente. |
| P2: umbral de 1000 aplicado también a V2 inactivo | Aceptado. El lector identifica el camino legado y marca `posibleRecorte` solo allí. `supabase/config.toml:18` fija `max_rows=1000`. La prueba HTTP diferencia 1000 filas legadas de 1000 filas dentro del sobre V2 inactivo. |
| P3: foco al volver a un botón deshabilitado | Aceptado. Si la fuente deja de estar disponible con el diálogo abierto, el foco vuelve al título del equipo. Verificado esperando el `requestAnimationFrame` que usa Dialog. |
| P3: aviso vivo duplicado | Aceptado. La tarjeta deja de anunciar el mismo estado cuando el detalle está abierto. |
| P3: singular «Resultado de hoy» en el error | Conservado: describe el resultado no disponible con concordancia singular. El título de la tarjeta sigue siendo «Resultados de hoy». No es un cambio de definición comercial. |

Los gaps de pruebas de monedas, fecha, ventas propias, atribución histórica y
totales del diálogo ya tenían cobertura, pero esos archivos no se adjuntaron
completos al reviewer. Se confirmó esa cobertura y se añadieron el subárbol,
el rol sin acceso, el recorte legado, la fuente demo real y la devolución del foco.

## Verificación final

- **PASS:** lint de todos los archivos modificados.
- **PASS:** typecheck inicial y compilación TypeScript final incluida en `npm run build`.
- **PASS:** build local; advertencia existente de chunks mayores de 500 kB.
- **PASS:** 32 pruebas en 5 archivos: `supervisor-jornada.test.tsx`,
  `jornada-supervisor.test.ts`, `use-resultados-hoy.test.tsx`,
  `demo-metricas.test.ts` y `crm-api-facturacion-msw.test.ts`.
- **PASS:** `npm run verify:bundle`; bundle de producción sin las fixtures demo de contratos.
- **NOT RUN:** E2E e inspección interactiva, por la instrucción de Miguel de
  trabajar localmente sin navegador, control del computador ni Docker.
- **NOT RUN:** conciliación con una sesión productiva y publicación, fuera de alcance.

Logs de esta sesión: `/private/tmp/hoy-resultados-{typecheck,tests,build,bundle}.log`.
No se afirman resultados productivos a partir de fixtures. Las nuevas lecturas
reutilizan el refresco de Facturación; el botón Actualizar de Hoy también las recarga.

# PWA de Analista — implementación y verificación

Fecha: 15/10/2026. Estado: **publicado y verificado**. Fuente y comprobaciones en [el acta de publicación](2026-10-15-publicacion-pwa-analista.md).

## Pedido y alcance

Miguel pidió llevar al Analista las mejoras de la PWA que ya tenía Gerencia y eligió la barra **Mi día · Gestión Diaria · Agenda · Más**. La confirmación en Android e iPhone dada al inicio de esta sesión corresponde a la versión anterior de **Gerencia**, no a esta adaptación.

- Navegación inferior por rol, con los módulos autorizados que ya entrega `Sidebar`. «Más» reúne los accesos secundarios y la cuenta. Se conservan el cierre con Escape, el retorno de foco y el cambio a menú lateral desde 768 px.
- Márgenes seguros, controles táctiles, inputs legibles, aviso de desconexión, actualización aplazable y ajuste de altura al teclado para Analista.
- Agenda móvil: datos de la tarea con espacio propio y acciones debajo; se evita comprimir el título y el importe. Estilos exclusivos de `vendedor`.
- «Mi día» conserva la información personal del Analista y añade hasta tres pendientes prioritarios del mismo proveedor que alimenta la campana. Incluye carga, error, reintento y estado vacío.
- Pendientes con filtros plegables en móvil y conservación de consulta, desplazamiento y foco al volver. La consulta persiste durante la sesión también al pasar a escritorio; allí los filtros permanecen visibles y se pueden limpiar.

No se cambian autorizaciones, datos, migraciones, contratos de API ni suscripciones push. Configuración sigue disponible para el calendario propio del Analista; Citas de Gerencia (`reuniones`) sigue restringido. El diseño de escritorio y los controles adicionales de Gerencia conservan su presentación anterior.

## Implementación

`NavegacionMovil` y `PendientesMovil` reutilizan los componentes originales de Gerencia con configuración por rol. El estado existente está separado por cuenta y rol. No se añade otro proveedor de alertas ni consultas periódicas.

Los nombres de algunas hojas de estilo y contenedores conservan «gerencia» para limitar el cambio. El atributo común es `data-navegacion-movil`; `data-gerencia-movil` permanece para el modal exclusivo de Facturación.

Se aplicó la skill **ECC `frontend-patterns`**: reutilización de componentes, estado existente y adaptación a las convenciones de la aplicación. No se cambió la instalación ni la configuración de ECC. Se preservaron los cambios previos de otras tareas presentes en el árbol.

## Revisión independiente

Una revisión con `scripts/claude-review` devolvió `CHANGES_REQUESTED`. Resolución por el PRIMARY:

| Observación | Resolución |
| --- | --- |
| La memoria de filtros también alcanza escritorio | Se conserva deliberadamente para no perder la consulta al rotar/cambiar de ancho. Los controles son visibles en escritorio. Prueba unitaria de conservación y limpieza añadida. |
| Nuevos tamaños de controles podían alcanzar Gerencia | Corregido: conjunto adicional `CONTROLES_ANALISTA`, activado solo para `vendedor`. |
| Posible efecto en formularios con teclado | Prueba de edición y guardado con altura de teclado simulada añadida; no sustituye un teléfono físico. |
| Estilos nuevos de pendientes podían sobreescribir Gerencia | Corregido: bases adicionales acotadas a `[data-rol='vendedor']`. |
| Bloque de pendientes en otros roles | Guarda explícita `yo?.rol === 'vendedor'`. |
| Menú con destinos principales no autorizados | Prueba unitaria: solo usa entradas recibidas, no reconstruye rutas ocultas. |
| Límite entre teléfono y tablet | Prueba explícita de menú lateral y ausencia de barra a 768 px. |

Evidencia local: `output/pwa-analista-20261015/review.txt` y `review-request.md`. No se atribuye al reviewer un PASS posterior que no emitió.

## Verificación inicial de la adaptación

| Comprobación | Resultado |
| --- | --- |
| `npm run check` | PASS: 420 archivos y 6706 pruebas unitarias; cobertura, release, service worker, build, bundle y duplicación. Lint conserva 11 advertencias anteriores. |
| Verificación tras ajustes finales de producto | PASS: lint, typecheck, 162 pruebas de 10 archivos, build y bundle. |
| Primer E2E dirigido | 22 PASS / 2 FAIL; un arranque lento de Gerencia y una expectativa incorrecta sobre el acceso al calendario propio. |
| E2E dirigido corregido | PASS: 26/26, sin reintentos. Anterior a los últimos ajustes de Agenda y prueba de teclado. |
| E2E completo en Docker | 408 PASS / 15 FAIL / 26 SKIP, sin reintentos (21,5 min). Catorce fallos por pasos que esperaban el antiguo menú lateral del Analista y uno por el arranque de Supervisor con el helper duplicado de 5 s. Los 15 casos se corrigieron y pasaron en la repetición dirigida. No se repitió la suite completa. |
| E2E final de la adaptación | PASS: 33/33, sin reintentos (1,6 min). Incluye los 15 casos anteriores, los diez casos de PWA del Analista, edición/guardado con teclado simulado, Agenda legible y límite de 768 px. |
| Inspección de capturas | PASS: Agenda a 360 px, Gestión Diaria, Mi día, Más y ficha con teclado simulado. |
| `git diff --check` del alcance | PASS. |
| `gate:realidad` completo | NOT RUN: falta `SUPABASE_URL` en el entorno administrativo del script. |
| Consulta complementaria de realidad | Lectura de agregados, sin mutaciones: 27 analistas activos, 3869 leads activos, 1819 tareas pendientes y 24 periodos con metas. No sustituye el gate completo ni una prueba de permisos. |
| Analista instalado en Android e iPhone físicos | NOT RUN: esta versión permanece local. |

La primera corrida completa incluyó pruebas antiguas que intentaban plegar un menú lateral del Analista después de cambiar a teléfono. Se actualizaron a esperar su navegación inferior, manteniendo las comprobaciones de negocio y de formulario. `demo-roles` ahora reutiliza el helper común de entrada (10 s y navegación según el rol). Se conservan los 15 contextos de fallo y el resumen real en `output/pwa-analista-20261015/e2e-completo-fallos/` y `e2e-completo-salida-capturada.log`. Esta última salida es parcial, con el resumen final íntegro; no se presenta como registro completo de stdout.

La repetición final está registrada en `output/pwa-analista-20261015/e2e-final.log`. Las capturas actualizadas están en `capturas/`. La regresión de Gerencia (navegación de 18 módulos, Pendientes, Citas, tamaños, desconexión y actualización) pasó en la corrida general con los estilos finales.

Comando de repetición dirigida, ejecutado desde `app/`:

```bash
npm run test:e2e:docker -- e2e/pwa-analista.spec.ts e2e/demo-roles.spec.ts e2e/f5-cartera.spec.ts e2e/f6-postventa.spec.ts e2e/ficha-multiempresa-visual.spec.ts e2e/gestion-diaria-analista.spec.ts e2e/sla-operacion.spec.ts e2e/upgrade-tasa.spec.ts --grep 'pwa-analista.spec|demo-roles.spec|móvil|vendedor 390px|Analista: dos columnas|Analista: Seguimiento|upgrade:.*390px' --workers=2 --retries=0 --reporter=list
```

## Preparación de la publicación

Se aplica el flujo `release-crm` a una copia limpia de `avancecorp/main`, inicialmente en `29357cbd4fd99b003e3ab4dc681dc7b1b3399eb3`. Se integran únicamente los cambios de esta adaptación, conservando los trabajos locales de otras tareas. La base ya contiene el commit vivo `d1796dd4cf8c771d7b35f3db608d536a99d51a9c`.

`npm run check` sobre la versión integrada: **PASS, 434 archivos y 6976 pruebas**, además de lint, typecheck, cobertura, configuración de release, service worker, build, bundle y duplicación. Evidencia: `output/pwa-analista-20261015/publicacion-check.log`.

La primera corrida Docker de preparación se interrumpió al detectar referencias de fuentes fuera de la carpeta montada, causadas por el enlace a dependencias del árbol original. No se usa como gate. Se instalaron las dependencias fijadas por el lockfile en la copia limpia y se reinició la suite completa con un volumen Docker exclusivo, dos workers y cero reintentos. Lint y typecheck con esas dependencias: PASS; seis advertencias preexistentes de lint.

Pruebas unitarias repetidas con las dependencias fijadas por el lockfile (`npm run test:run -- --maxWorkers=2`): **PASS, 434 archivos y 6976 pruebas**, 198,83 s. Registro: `output/pwa-analista-20261015/publicacion-unitarias-lock.log`.

La prueba física de la nueva vista del Analista sigue pendiente; la confirmación previa de Gerencia no la sustituye. El resultado de publicación se registra después de verificar el artefacto servido.

Suite completa final en Docker: **436 PASS / 0 FAIL / 26 SKIP**, dos workers, cero reintentos, 18,8 minutos. Incluye los diez casos nuevos de Analista y la regresión PWA de Gerencia. Registro de la suite: `output/pwa-analista-20261015/publicacion-e2e-completo.log`.

Integración completada por Miguel en [PR #305](https://github.com/avanza-digital/avancecorp-crm/pull/305), con controles `verify`, `app-check` y `preflight` en verde. Commit de implementación `eac8480271e0393824aa272847044215a4b503fa`; commit integrado y publicado `94ef6886b50d0734a29fff57c10d268680aaed9d`, con árbol idéntico. Se publicó mediante Hostinger y se verificaron por HTTPS 126 archivos contra el manifiesto. El login en navegador limpio pasó en móvil y escritorio.

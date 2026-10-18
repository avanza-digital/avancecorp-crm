# Ejecución del Goal — Hoy del supervisor

Autorizado por Miguel el 18/10/2026 mediante el objetivo adjunto.
Codex implementa, revisa y corrige cada fase. Claude será revisor independiente.
No navegador, control del computador, Docker, publicación ni escrituras de datos reales.

| Fase | Estado | Revisión y evidencia |
| --- | --- | --- |
| 1. Indicadores | CERRADA | `MATRIZ-INDICADORES.md`; definiciones contrastadas y 32 pruebas PASS. |
| 2. Datos y refresco | CERRADA | B1/B2/B4 corregidas; 88 pruebas, lint y tipos PASS. |
| 3. Acciones | CERRADA | `MAPA-ACCIONES.md`; B3 corregida, 29 pruebas, tipos y lint PASS. |
| 4. Interfaz | CERRADA | `REVISION-INTERFAZ.md`; build, lint y bundle PASS; visual NOT RUN. |
| 5. Claude | CERRADA | Dos dictámenes, último PASS; hallazgos corregidos; 44 + 101 tests, lint, tipos y build Main PASS. |
| 6. Validación integral | CERRADA | Gate completo PASS: 7.261 pruebas, lint, tipos, release config, SW, build, bundle y dup. |
| 7. Revisión para ZIP | PREPARADA | `PREPARACION-ZIP.md`; identidad definitiva y cierre en acta externa. |
| 8. ZIP y entrega | ACTA EXTERNA | Cierre y archivos en `releases/hoy-supervisor-2026-10-18/ENTREGA-ZIP.md`. |

## Condiciones verificadas al iniciar

- Rama actual `crm/conversion-adicional-renovacion-20261014`, commit `c58f85d1`;
  upstream remoto anterior eliminado. No se cambió la rama ni se movió Main.
- 313 entradas de estado Git, incluidas tareas ajenas. Inventario inicial en
  `/private/tmp/hoy-supervisor-goal-20261018/estado-inicial.txt`.
- El gate de realidad no pudo consultar por falta de `SUPABASE_URL`: NOT RUN.
- E2E/inspección visual: NOT RUN por instrucción explícita del usuario.
- El ZIP todavía no existe para esta ejecución. No se marca Goal completo hasta
  terminar las ocho fases y auditar los entregables contra el objetivo.

## Fase 2 — revisión de Codex y correcciones

- `useResumenCartera` separa la caché por actor y admite sondeo visible cada
  60 segundos solo cuando Hoy lo solicita; al volver se revalida. La invalidación
  existente por reparto sigue alcanzando todas las claves por prefijo.
- `useResumenCarteraOperativo` mantiene error → ausencia de cifra y ya no permite
  que un reintento manual consulte red en demo o con el lector deshabilitado.
- `useRefrescoMensualJornada` refresca cada cinco minutos con la pantalla visible,
  no solapa sus propias solicitudes y limpia el temporizador al desmontarse.
  Reutiliza `recargarMensual`; foco/reconexión siguen a cargo del store existente.
- Codex revisó ámbito, retorno al módulo, actualización, caché/error, demo y
  limpieza de recursos. No cambian fórmulas, SQL, permisos ni umbrales de negocio.
- Las pruebas reproducen nuevas llegadas, reparto parcial/total, error y recuperación,
  respuesta tardía de otro actor, segundo plano, demo y secuencia 0 → 4 → 1 → 0
  del aviso visible. El resumen mensual cubre intervalo, callback vigente,
  desmontaje, ausencia de actor, segundo plano y solicitud lenta/fallida.
- Se detectó un error de inferencia del tipo `null` en el test del refresco mensual;
  corregido antes de cerrar la fase y repetir TypeScript.
- **PASS:** 88 tests en 5 archivos; lint de los 8 archivos afectados; typecheck;
  `git diff --check` de los archivos seguidos. Logs `fase2-tests.log` y
  `fase2-tipos.log` en `/private/tmp/hoy-supervisor-goal-20261018/`.
- **Cierre:** B1/B2/B4 resueltas, sin defectos propios pendientes de esta fase.

## Reapertura y corrección durante fase 5

Se contrastaron de nuevo fases 1–4 contra Main vigente, sin cerrar fase 5 ni
avanzar a validación integral con defectos de cifras. Las ventas propias del
supervisor estaban en Main pero no en la vieja carpeta de diseño: se preservó
Main y se corrigió el desglose. Integración en copia local limpia, sin cambiar
la rama ni los 313 cambios del taller. Solo se trasladaron hunks propios de
API/queries; no se reemplazaron los archivos por sus versiones antiguas.

Codex corrigió los hallazgos de Claude (`RESOLUCION-HALLAZGOS.md`) y ejecutó 37
pruebas sobre fuentes/refresco/interfaz y TypeScript: PASS. Segunda revisión
justificada por el contrato nuevo de Main y evidencia del store antes ausente.

Fase 5 cerrada por Codex: ver `RESOLUCION-HALLAZGOS.md`. Se inicia fase 6.

## Fase 6 — hallazgo del gate completo

Primera ejecución: 7.258 pruebas PASS y tres FAIL en el consumidor clásico
`supervisor.test.tsx`. Codex aisló la causa: aserciones sin esperar la microtarea
nueva y conteo anterior sin el reintento acotado. Se mantiene la comprobación de
no mostrar metas viejas; se espera la recarga y se afirma el máximo de intentos.
Repetición dirigida: 59/59 PASS. Gate completo repetido; pendiente de resultado.

Fase 6 cerrada: segunda ejecución de `npm run check` completa PASS. La fase 7
fija el commit y la fase 8 construye desde él. Sus actas finales se escriben
junto al artefacto (directorio releases, ignorado por Git): así el registro de
la entrega no cambia el commit del ZIP después de haberlo construido.

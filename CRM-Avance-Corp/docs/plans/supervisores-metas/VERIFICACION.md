# Verificación: ventas propias de supervisores

16/10/2026. PRIMARY: Codex. Copia aislada autorizada desde main `65764411`.
Miguel autorizó la publicación y la rama temporal de pago, con eliminación al
terminar. Validación, promoción y publicación completas; rama temporal eliminada.
Fuente publicada: `3a0fa7075296149fa45c646cbb48beca3fbdbe41`.
Ver [acta productiva](PUBLICACION.md).

| Gate | Resultado | Evidencia y límite |
| --- | --- | --- |
| SQL local PostgreSQL | PASS | 59 aserciones; 54 lecturas antes/después; roles authenticated; contratos, cooperativas, historial, ACL y reversa/reaplicación. |
| `cd app && npm run check` | PASS | Lint, tipos, 434 archivos / 6.984 tests, cobertura, release config, push, build, bundle y duplicación 0,42 %. |
| E2E Docker completa | PASS | 438 passed / 26 skipped / 0 failed, 17,3 minutos, 2 workers. Incluye los tests reforzados con UUID del roster coincidentes con metas. `e2e-completo.log`. |
| `npm run check:scripts` | PASS | Repetido fuera del sandbox porque el servidor HTTP local no podía abrir puerto. |
| `npm run seed:preflight` | PASS | Variables ficticias y loopback; sin conexión. |
| `npm run test:rls:preflight` | PASS | Variables ficticias y loopback; sin conexión. No equivale a RLS HTTP real. |
| `npm run test:edge-preflight` | PASS | Suites offline existentes, sin desplegar funciones. |
| `git diff --check` | PASS | Sin errores de espacios. |
| SQL cloud | PASS | Las mismas 59 aserciones y rollback sobre las 1.110 funciones actuales de producción. `sql-cloud.log`. |
| Auth/PostgREST cloud | PASS | 37 comprobaciones, 10 identidades y sesiones Auth reales, 27 respuestas antes y después; `http-cloud.log`. |
| Advisors cloud | PASS | Sin hallazgos nuevos. Seguridad 382 → 380; rendimiento 336 → 334. La deuda anterior queda fuera de alcance. |
| Merge Supabase | PASS | Solo la migración prevista; 1.110 funciones iguales al banco, 23 Edge Functions sin cambios, 14 lecturas productivas y huellas de negocio antes/después iguales. |
| Publicación / smoke web | PASS | Paquete desde main limpio e igual al remoto; preflight y manifiesto válidos; portada, acceso y JS/CSS verificados, cero errores JavaScript. Detalle de imágenes optimizadas en el acta. |
| Advisors productivos / limpieza | PASS | Sin hallazgos nuevos: seguridad 381 → 381, rendimiento 192 → 192. Rama temporal eliminada y ausencia confirmada. |
| Replay completo desde cero / escritor de cierre | NOT RUN | No se modifican. Banco basado en plantilla existente; foto cerrada sintética. |
| Tipos generados | No aplica | Misma firma `date → jsonb`, sin tablas/columnas/grants nuevos. |

Primera ejecución E2E: 5 passed y 1 flaky por una consulta repetida de
`alertas_reconocimientos_vigentes` en el test histórico existente. Sin cambiar ese
test, la corrida posterior de los tres specs pasó completa (9/9).
La comprobación reforzada muestra analistas con capital y puestos 01/02, seguidos
por el supervisor con S/ 900.000 propios; ambas capturas se inspeccionaron.
El lint conserva 11 advertencias existentes ajenas a los cambios.

Los logs completos locales se guardan junto a este documento (`sql.log`,
`frontend.log`, `e2e.log`, `e2e-ventas.log`, `scripts.log` y los preflights).
Los guiones versionados permiten reproducir el ensayo SQL.

## Claude y JEV

JEV se usó mediante el selector de contexto del proyecto y la skill `typesafe-ai`.
Ordenó ocho extractos de código; [resultado](jev-contexto.json). No decidió
permisos, dinero, fórmulas ni sellos. Sus prioridades se adjuntaron a Claude.

Claude recibió evidencia saneada mediante `scripts/claude-review`, sin herramientas
ni acceso de escritura. Primera revisión válida: [arquitectura](claude-arquitectura.txt).
Segunda revisión: [dictamen final](claude-final.txt), CHANGES_REQUESTED: SQL correcto,
sin fuga identificada; solicita endurecer el campo derivado e inventariar sus
consumidores y las vistas por equipo. Resolución con cambios y evidencia:
[inventario y adjudicación](INVENTARIO-REVISION.md). Los intentos previos sin dictamen válido
fueron errores de ejecución/formato, no dictámenes descartados por desacuerdo.

Evaluación del PRIMARY sobre la arquitectura:

- **Aceptado:** reutilizar `fuera_ranking`, sin clave RPC nueva. Evita romper el esquema estricto y conserva el total de empresa para clientes previos.
- **Aceptado:** filtrar por UUID antes de joins y en JSON sellado; matriz de aislamiento abierta/cerrada y roles revocados PASS.
- **Aceptado:** no inventar filas sin actividad; el sello ya usa ese universo. Se conserva el estado vacío.
- **Aceptado:** sección final separada, sin otorgar puestos de analistas.
- **Corregido con evidencia:** `agregarCumplimientos` ya omite conversión real, numerador y divisor (F3.3). El riesgo concreto era diluir la **meta** media de conversión: ahora se conserva la del equipo; tests PASS.
- **Descartada la hipótesis de descuento monetario faltante:** ATR-4 (`20260901180000_crm_atr_4_sancion_de_anular_solo_conversion.sql`, `contratos_confirmados`) conserva capital y sanciona solo conversión. No se introduce otra regla financiera.
- **No se añade helper SQL para una única fecha:** comparación única en la función y constante única en el adaptador, con pruebas septiembre/octubre/años siguientes. No amplía superficie ni ACL.
- **Cambios de rol:** una baja de perfil/membresía o paso a analista revoca la nueva capacidad, abierto y cerrado. La pertenencia de metas ya publicada se conserva; no se cambia automáticamente la historia de una promoción a supervisor.

La revisión es asesoría; los resultados de los checks anteriores son la evidencia
de ejecución. Ver [decisión final](PLAN.md).

Medición adicional read-only previa a la promoción: bloque de ventas propias
181,270 ms, planning 4,405 ms; [EXPLAIN](rendimiento.txt). En esa medición no se
instaló la migración, no se devolvieron nombres ni importes y no se midió
HTTP/p95/concurrencia. La base local
quedó vacía tras el ensayo (0 miembros, 0 contratos) y con la huella original de
la función, confirmando el rollback de datos y DDL.

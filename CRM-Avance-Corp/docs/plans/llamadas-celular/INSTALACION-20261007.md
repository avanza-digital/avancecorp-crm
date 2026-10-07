# Instalación de llamadas desde el celular — 07/10/2026

**Estado al preparar este commit:** H1 (doce migraciones) y H2 (Edge) instalados y
verificados en producción. H3 habilita el frontend en este cambio; su publicación
se acredita con el manifiesto del release y el comentario de cierre del PR, no
solo con este archivo. **C1 aún no está activado; el piloto físico sigue pendiente.**

Esta acta actualiza el estado de instalación de `PUBLICAR-F2-F3.md`,
`SEGUIMIENTO.md` y los apartados históricos de `MIGRACIONES.md`. No cambia los
102 textos originales del plan ni marca tareas físicas como realizadas.

## Autorización y código

Miguel pidió completar la revisión, correcciones, fusión y publicación; autorizó
el banco local y la rama temporal de Supabase a US$0,01344/h. PR #190 ya estaba
fusionado. PR #215 se integró con main, volvió a pasar los gates y se fusionó
el 07/10 en `5f42e908155af3486cdf489a17b6eb8d6c673a16`. PR #221 incorporó los
documentos y decisiones en `8e1c521af3ea982ffd669caacbf137515412e41b`.

La habilitación cambia `LLAMADAS_CELULAR_APROBADAS` a `true`; conserva explícitamente
las cuatro pruebas del estado apagado. Los tipos se regeneraron desde producción
con `npm run gen:types`. El cambio de PostgREST a `14.5` refleja la versión real;
también incorpora la RPC de tasa administrativa ya instalada, sin cambiar su código.

## H1 — Migraciones aplicadas

Proyecto: `PortalAvanceCorp` (`dctqcbznekcyxhjujuci`). Orden aplicado:

| # | Versión | Migración |
| --- | --- | --- |
| 1 | 20261001145242 | datos |
| 2 | 20261001160219 | núcleo |
| 3 | 20261001212258 | ingesta |
| 4 | 20261001222431 | elegibilidad del dueño |
| 5 | 20261005143843 | corrección |
| 6 | 20261005155914 | enlace exacto |
| 7 | 20261005182227 | enlace sin ciclo |
| 8 | 20261005201010 | lecturas del analista |
| 9 | 20261005224330 | resueltas paginadas |
| 10 | 20261006150154 | bandeja con origen |
| 11 | 20261006150254 | salud sin hora exacta |
| 12 | 20261006162813 | cierre de revisión |

Rama de ensayo: `llamadas-cierre-20261007` (`nbbnhxcqlsyohcoieppx`). El replay
histórico inicial falló al ejecutar una migración antigua sobre censos vacíos. Se
reconstruyó exclusivamente esa rama con el esquema productivo, las 438 entradas
históricas exactas, catálogos de configuración y fixtures sintéticos; sin copiar
clientes. Se comprobó paridad de columnas, índices, triggers, RLS, funciones,
propietarios y permisos antes de aplicar las doce fuentes LF sin modificarlas.
Cada migración pasó su registrador inmediatamente después de aplicarse en el ensayo.

Publicación mediante `merge_branch`, concluida aproximadamente a las 21:53 UTC.
Postflight productivo PASS:

- 450 migraciones: las 438 anteriores idénticas y exactamente las doce nuevas.
- Las 56 funciones de llamadas y las siete tablas coinciden con la rama ensayada
  en cuerpos, propietarios, privilegios y RLS correspondientes.
- SLA permanece **activo**, revisión 1, misma primera activación y misma política.
- Cron y política coinciden con el ensayo: entrantes apagadas, desconocidas sin
  guardar, límites de 30/minuto y 600/día.
- Sin asignaciones, eventos, recepciones ni intenciones reales al cerrar el postflight.

Supabase registra el SQL dividido en varias sentencias. Se cotejaron las doce
fuentes con lo registrado mediante comparación léxica: solo se ignoran comentarios
externos, espacios y separadores; cadenas y cuerpos SQL se conservan. No ejecutar
de nuevo los registradores antiguos sobre producción: algunos comprueban cuerpos
intermedios que las siguientes correctivas reemplazan legítimamente.

## H2 — Edge publicada

`crm-llamadas-ingesta`, versión 1, ACTIVE, `verify_jwt=false`; autentica con la
credencial del celular. Sus dos fuentes descargadas de producción coinciden
exactamente con el repositorio. Las 22 Edge anteriores conservan sus versiones,
huellas y configuración JWT; ahora hay 23.

En producción, POST sin clave y con clave desconocida devuelven el mismo
**401 / No autorizado**. Las pruebas positivas, rotación y cierre se hicieron
con datos sintéticos en la rama, no creando un celular real en producción.

## Verificación y límites

| Gate | Resultado |
| --- | --- |
| Banco local completo con esquema actualizado y SLA activo | **PASS 3292/3292** |
| Reversa de las doce y reaplicación con registradores, solo banco | **PASS** |
| Rama remota: matriz de visibilidad + bloque original completo de llamadas | **PASS 328/328**, incluye las 197 de llamadas; no es toda la matriz global remota |
| Edge real en rama: llamada, repetición sin duplicar, latido, claves inválidas, rotación y cierre | **PASS 6 casos** |
| Unitarias Edge / mutantes | **PASS 17/17 y 18/18** |
| Frontend activado y tipos productivos: `npm run check` | **PASS 6397 tests / 399 archivos**, lint, tipos, build, bundle y duplicación |
| Docker: llamadas-celular, config-celulares, gestión diaria vuelta/pendientes | **7 passed + 1 flaky**; config-celulares repetido aisladamente: **2/2 PASS** |
| Integración de #215 antes de fusionar: configuración, demo y upgrade de tasa | **PASS 10/10 Docker** |
| Revisión secundaria adicional de la activación | **NOT RUN (sin dictamen aprovechable)**: dos intentos acotados del wrapper terminaron sin un VERDICT válido; no se presenta como aprobación. #190/#215 tienen sus revisiones anteriores |
| `gate:realidad` productivo, solo lectura | 8/9 coincidencias; 275 clientes activos sin dirección legal, divergencia previa de contratos/PDF ajena a llamadas |
| Activación física C1, noches y piloto de cinco días | **NOT RUN**, turno de Jhosep tras H3 |

Los fallos antiguos de la matriz local se resolvieron exclusivamente completando
fixtures/catálogos, incorporando la configuración de reparto ya productiva y
restaurando las condiciones esperadas de la siembra. No se debilitaron aserciones
ni se corrigió código de producto para obtener el PASS.

Advisors productivos: ningún ERROR nuevo. Hay **15 WARN nuevos por RPC
SECURITY DEFINER ejecutables por authenticated**, diseño intencional con guardas
de rol/ámbito verificadas por las negativas. Siete INFO de tablas RLS sin policies
son coherentes con su cierre a acceso API directo; veinte INFO de índices sin uso
corresponden a tablas recién instaladas. No hay nuevos WARN de rendimiento.

La rama temporal fue eliminada y se verificó su ausencia; la rama previa
`banco-f7` quedó intacta. Las credenciales temporales locales se retiraron.

Evidencia local saneada de la sesión:
`/private/tmp/llamadas-publicacion-20261007/`: `gate-local-final.log`,
`rama-rls-llamadas.log`, `rama-edge-e2e.log`, `prod-snapshot-final.json`,
`frontend-tipos-prod-check.log`, `frontend-activado-e2e.log` y
`config-celulares-e2e-confirmacion.log`. Son artefactos locales, no enlaces públicos.

## Turno siguiente y recuperación

Codex completa H3 desde main limpio e idéntico a `avancecorp/main`: release,
manifiesto, preflight y comprobación de los bytes JS/CSS servidos por
`crm.miavance.com`. El cierre debe identificar el commit, build y ZIP realmente
publicados; no atribuir esa publicación a un commit documental posterior.

Después Jhosep activa C1 según `ACTIVAR-C1.md`: Pro corporativo, credencial por
canal privado, cola de ensayo limpia y P1–P15 contra la Edge real. P1/P2 se juzgan
por el orden observado de llegada; el recuento excluye entrantes y distingue
recepciones de eventos identificados. Mantener la aceptación de diez salientes,
casos especiales, noches y cinco días. F4-e sigue después de F4-d con el diccionario
A1–A7 aprobado; Jev permanece apagado.

Recuperación después de dar de alta un celular: cerrar su asignación/credencial o
deshabilitar la UI con un release aprobado; conservar el historial y corregir
hacia adelante. No ejecutar las reversas SQL sobre un sistema con altas/uso.
El ZIP anterior se conserva con su manifiesto, pero su restitución requiere
el procedimiento de preflight y la decisión de rollback del repositorio.

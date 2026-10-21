# SLA: plan de la «foto» del servidor (2026-10-13, v3 del 14/10)

> **Para retomar: serial `FOTO-SLA-1610-MEDIR-F1`.**
> - Se retoma en el primer día laboral **sin publicaciones entre las 9:00 y las 18:00**, después de las 18:00, para medir la Fase 1 contra la línea base.
> - Pasos exactos en `~/dev/avancecorp-crm-foto-sla/CRM-Avance-Corp/supabase/scripts/foto-sla/CONTINUACION.md`.

**Estado (15/10/2026, 19:46):**
- ✅ **Fase 0 cerrada.** La línea base está en `…/foto-sla/fase0/linea-base-2026-10-14.md`.
- **Fase 1:** en producción desde el 14/10 a las 23:17, sin medir todavía.
- **Fase 2:** propuesta saltarla.
- **Fase 5:** 4 GB va justo.
- ✅ Tablero marcado el 15/10 a las 8:02 p. m.

## ✅ Cierre de la Fase 0 (15/10/2026)
- **Día «antes» (14/10, sin publicaciones):**
  - 82.073 peticiones y ~30 personas por hora.
  - La familia SLA/GD fue el **33,6 %** del tiempo de base estimado, con **679 s** en su hora pico (umbral del plan: 1.440 s).
  - Peor 5 %: `avisos_sla_resumen_v2_fn` **1,34 s** y `cola_accion_v3_fn` **1,88 s**.
  - Cero cortes.
- **Temporales en 43 h:** 42,6 GB, el **98 %** de la familia. Solo `avisos_sla_resumen_v2_fn` escribió el 61 %.
- **El trío de Metas** (`cumplimiento_metas_fn`, `configuracion_metas_fn` y `equipo_visible_fn`, siempre juntas) es **~19 %** del tiempo de base. Es el segundo bloque y no es del SLA.
- 🔴 **Memoria con 4 GB:**
  - 14/10 a las 10:50: **0,09 GB libres**. La caché estaba reducida a casi solo el `shared_buffers` de Postgres, y la memoria comprometida llegó a 4,55 GB con un límite de 2,87 GB.
  - 15/10: **swap de 0,21 GB** desde las 12:50.
  - CPU máxima: 18 %. Conexiones de la API: máximo 41 de 120. Disco sin espera.
- **El 15/10 no sirve para juzgar la Fase 1:** hubo 4 publicaciones en horario laboral. El aviso de versión nueva hace que la gente recargue: las entradas a la app se duplicaron a las 11:00.
- **Lectura contra las cifras del plan:**
  - se cumplen «peor 5 % > 1 s» y «memoria comprometida sobre su límite»;
  - no se cumplen los cortes, ni los 1.440 s, ni la CPU por encima del 70 %;
  - la atribución queda justo en un tercio.
- **Qué implica:**
  - **Fase 2:** saltarla, porque ya no cumple su propia regla de memoria.
  - **Fase 5:** no volver a 2 GB. Subir a 8 GB lo decide Miguel; conviene decidirlo si el día limpio repite menos de 0,2 GB libres o swap.
- **Cómo se midió** (sirve para repetirlo):
  - logs `edge_logs` por hora y por RPC;
  - tiempo de base estimado, calculado como llamadas por la media de `pg_stat_statements` con `transform(...)` de ClickHouse;
  - Observability leída por JavaScript desde la geometría de las barras.

- **Tablero FigJam:** https://www.figma.com/board/HlUg0CExmCMKxJz7wXyasZ — la v2 está a la izquierda y la v1 a la derecha, rotulada como reemplazada.
- **Plan completo con anexo técnico:** `~/.claude/plans/ok-haz-un-buen-elegant-journal.md`

## 🔴 Causa de la caída: MEMORIA (acreditada el 14/10, 1:00 a. m.)
Los gráficos de Supabase están en **Observability → Database** (ya no se llama «Reports»): `https://supabase.com/dashboard/project/dctqcbznekcyxhjujuci/observability/database`. Rango «Last 24 hours».

Hora de la caída (13/10, 4:00–4:59 p. m. Lima):

| Métrica | Valor |
|---|---|
| Memoria usada | 1,61 GB, con 15 MB libres |
| Swap | 1.024 MB |
| Memoria comprometida | **3,75 GB con un límite de 1,9 GB (197 %)** |
| CPU | 24,7 % |
| Disco | casi sin uso |
| Conexiones | ~35–40 de 90 |

- La memoria comprometida pasa del límite durante todo el horario de oficina; de noche se queda en ~1,4 GB.
- **Consecuencias:**
  - el plan Small (2 GB) se queda corto en hora pico con el patrón actual de consultas;
  - la Fase 2 (más `work_mem`) queda en duda;
  - la Fase 5 (subir de plan) pasa a decidirse ya.

## Por qué
- El 13/10 la base dejó de responder a las 4:58 p. m. y se reinició a las 4:59 p. m.
- **La causa NO está probada:** no dejó rastro de memoria ni de señal, y los timeouts (4:31–4:34 p. m.) pararon ~25 min antes.
- **Desperdicio medido:**
  - ~1.500 consultas pesadas por hora en el pico; cada consulta recalcula los leads visibles para esa persona (3.594 para gerencia);
  - ~10 GB de temporales en 6 h;
  - recalcular todo cuesta 1,1–1,4 s y escribe 12–24 MB al disco;
  - leer una foto guardada cuesta 0,27 s y no escribe al disco con `work_mem` de 16 MB (7 MB con 5 MB).
- Contexto previo: [[CRM - perfil de carga lectura vs escritura (2026-09-29)]] y [[Plan de escalabilidad del CRM a data gigante]], cuya F5 ya preveía una tabla resumen con lectura híbrida.

## Auditoría del 14/10
Tres revisiones: la de Miguel, la de Claude (con mediciones en producción) y la de Codex (BLOCK de la Fase 2 v1). La v1 no estaba lista; lo que se corrigió:

1. **Pérdida de cambios:** el diseño de marcas con `on conflict` + borrado perdía cambios.
2. **Pulso de días pasados:** congelarlo no vale, porque lleva pendientes y equipo actuales ([[Gestion Diaria - supervisor con consulta por fecha (2026-09-24)]]).
3. **Promesa de 30 s:** no se cumplía de punta a punta (servidor + pantalla).
4. **Modo observación:** sin primera activación, el SLA depende de `p_ahora` de forma continua.
5. **Escritura:** reescribir 7,9 MB cada 30 s daba ~1 GB/h de WAL archivado.
6. **Fallo del repaso:** todo volvía a calcularse a la vez, sin vía de recuperación.
7. **Tablas nuevas:** necesitan exención en la regla de auditoría.
8. **`cron.job_run_details`:** nunca se purga; lleva 47.000 filas.
9. **Triggers:** las tablas de transición no admiten varios eventos (probado en prod).
10. **Fase 1:** la fórmula de `staleTime` estaba mal planteada.
11. **Controles:** `assert_gestion_diaria_pulso` ya falla en prod por contadores sin declarar (`crm.gestiones_resumen_fn`, `private.citas_clientes_core`), así que el criterio es «mismo estado antes y después».

**Segunda revisión de Miguel (14/10, sobre la v2):** se aceptaron sus 4 ajustes al diseño de la foto.
1. La foto no se usa si cambiaron las reglas: cada fila guarda la revisión con la que se calculó.
2. «Válido hasta» solo cuenta umbrales estrictamente futuros; si no, los leads vencidos se recalcularían siempre.
3. El interruptor y el estado van en una tabla normal; solo la foto y las marcas son `UNLOGGED`.
4. Validez de 30 s con repaso cada 25 s, para no pasar de 1,5 min aunque falle un repaso; si falla, se lee en vivo.

**Cifras para decidir, confirmadas por Miguel (14/10, 12:55 a. m.):**
- **La memoria (Fase 2) se queda** si se cumplen las tres:
  - temporales al menos un 50 % menos;
  - la base no pasa del 75 % de su memoria con 30 consultas pesadas a la vez;
  - el p95 no empeora.
- **La foto (Fase 3) se construye** si, tras las fases 1 y 2, en 2 días laborales en hora pico, pasa alguna:
  - algún timeout del SLA o de Gestión Diaria;
  - p95 de avisos o cola por encima de 1 s;
  - el SLA usa más del 20 % de la base;
  - CPU por encima del 70 % o el disco al tope.

**Confirmado:**
- La salida por lead no depende del actor (`sla_hechos_actuales` y `sla_tareas_hechos` solo filtran por ámbito a nivel de lead).
- No hay choque con el grupo C: sus preflights miran nombres de sus puertas y el conjunto de triggers de `crm.inversionistas`.

## Decisiones de Miguel
1. **Orden (14/10):** medir → alivio en pantalla → memoria → decidir la foto con números.
2. **«No contactar» marcado en la ficha del CLIENTE y nombres de usuario (14/10):** hasta 1,5 min en reflejarse (hoy 1 min) mientras el grupo C no aplique el 2.10. Marcado en la ficha del lead: al instante.
3. **Encendido de la foto (13/10):** directo, con la foto ya llenada y comprobada antes, y con interruptor.
4. **Grupo C (13/10):** la foto va antes de C2 y no toca ningún control que C tiene fijado.

## Fases v2
- **0 · Medir:** Reports del 13/10 y línea base de un día laboral.
- **1 · Alivio en pantalla:** frescura bien calculada y la cola de trabajo deja de reintentar cada segundo cuando falla. El pulso no se toca.
- **2 · Memoria:** `work_mem` de 16 MB solo en el núcleo y el lector, medido con concurrencia.
- **3 · La foto rediseñada:** solo si los números lo piden.
- **4 · Gestión Diaria:** después del grupo C.
- **5 · Decidir el servidor.**

## Tablero: nodos para actualizarlo (v2)
- **Tablero v2:** `8:4`.
- **Estado general:** texto `8:8`.
- **Píldoras «estado · Fase N»:**

  | Fase | Nodo |
  |---|---|
  | F0 | `8:75` |
  | F1 | `8:86` |
  | F2 | `8:97` |
  | F3 | `8:108` |
  | F4 | `8:119` |
  | F5 | `8:128` |

- **Bitácora:** texto `8:146`, lo más reciente arriba.
- **Checklist de cada fase:** textos `13:3` (F0), `13:5` (F1), `13:7` (F2), `13:9` (F3), `13:11` (F4) y `13:13` (F5).
  - Al terminar una tarea, cambiar su «⬜» por «✅» y actualizar también la píldora, el estado general y la bitácora.
  - Es una regla de Miguel: marcar en vivo.
- **Avance:**
  - 14/10, 12:48 a. m.: Fase 0 en curso; hecha la foto de inicio de las cifras de la base.
  - 14/10, 8:35 a. m.: Fase 1 probada sin publicar, **PR #277** (commit `2021d21f`).
    - Escritor y verificador: subagentes Opus 5.5.
    - Resultados: 6.696 pruebas, e2e 83/83, Codex sin fallos graves.
    - Se publica el 15/10, después de la línea base.
  - Archivos en el worktree, en `supabase/scripts/foto-sla/fase0/`.
- **v1:** sección `1:2` con su rótulo `8:2`.
- **Colores:** Pendiente `#E6E6E6`, En curso `#3866BF`, Probada sin publicar teal, Hecho `#1F804D`, Espera decisión `#B33373`, Bloqueado `#BF2E2E`.

## Entorno ya preparado (sin cambios de código)
Worktree `~/dev/avancecorp-crm-foto-sla`, rama `crm/alivio-consultas-sla-20261014`, creado desde `avancecorp/main` `a2ea864f`.

## 16/10/2026 — Fase 2 ensayada: no se aplica (propuesta, espera la decisión de Miguel)

Detalle en el worktree: `supabase/scripts/foto-sla/fase2/RESULTADO-ENSAYO.md`.
- **Banco** igual a producción, con datos sintéticos calibrados: filas del SLA ±1 %, temporales ±3 %, planes ±5,5 %.
- **Ensayo A/B con 30–39 consultas pesadas a la vez.**
  - Disco −49,999 % (no llega al 50 %).
  - Memoria igual en el banco (sin medir en producción).
  - Tiempo sin mejora demostrada.
  - Con gerencia y supervisores con 3 pestañas, el banco se satura por CPU con o sin la F2.
- **Codex:** de acuerdo en no aplicarla; pidió decir «no acredita», no «refutada».
- **Lo que de verdad pesa:** armar un único `jsonb` con todo el SLA.
  - Una consulta de gerencia a la cola llega a ~210 MB de memoria del proceso; avisos, a ~140 MB.
  - De eso, el `jsonb_agg` son ~120 MB: ocupa unas 7 veces el JSON que arma, y `work_mem` no lo limita.
  - Ni `to_jsonb(array_agg)` ni `json_agg::jsonb` lo arreglan.
- **Mejora corta probada en el banco («opt1»):** calcular el «próximo cambio» dentro del mismo `SELECT` del agregado, en vez de
  recorrer otra vez el JSON.
  - Mismo resultado exacto (10/10 casos).
  - −23 % de memoria en la cola de gerencia y −20 % en avisos.
  - Los guardianes del SLA la aceptan.
  - Pendiente de plan y del OK de Miguel.
- **Trampas aprendidas:**
  - `pg_column_size` de un valor GUARDADO en una tabla mide el tamaño comprimido (TOAST): hay que medirlo antes de guardar.
  - Un comparador que redondea antes de decidir puede dar «pasa» a un 49,999 %.
  - En `psql`, `\!` no sustituye variables: usar `\g |cat > archivo`.
- **Tamaños de Supabase (documentación, 16/10):** Medium, 2 núcleos ARM compartidos y 4 GB · Large, 2 dedicados y 8 GB · XL, 4 dedicados y 16 GB.
- **Tarde del 16/10:**
  - Miguel cerró la F2 sin aplicarla.
  - La «opt1» da el mismo resultado exacto (verificado dos veces), pero con 30+ consultas a la vez no baja la memoria total, solo el
    disco (−17 %). Pendiente de que Miguel decida si se hace o se archiva.
  - La F1 se mide el lunes 19/10, desde las 18:10, con el kit `fase1/kit-medicion.md`.
- **Regla del día limpio (corregida):** el día no sirve si hubo publicación del CRM o cambio de la familia SLA/GD entre las 9:00 y
  las 18:00. La familia se comprueba por su huella y buscando por TEXTO en `postgres_logs`: `schema_migrations` no registra todas
  las aplicaciones (las de `db query --file` no dejan fila).
- **16/10, 15:24–15:27 · mejora corta EN PRODUCCIÓN** (Miguel decidió hacerla por el disco):
  - migración `20261016190408` (PR #311), aplicada con `db query --file` entre dos `verificar.sql` de solo lectura;
  - mismo resultado; −16 a −19 % de escrituras temporales con carga;
  - guardianes idénticos antes y después; acta en la PR #312.
  - Patrón que funcionó para cambiar una función DEFINER sellada por huella:
    - `pg_get_functiondef` + `replace` + `execute`;
    - precondición de md5 (función, productor, metadatos y md5 del DDL);
    - poscondición con todos los atributos y guardianes dentro de la transacción;
    - mutante de guardián rojo;
    - reversa condicionada que se aplica como migración nueva (el índice solo crece).

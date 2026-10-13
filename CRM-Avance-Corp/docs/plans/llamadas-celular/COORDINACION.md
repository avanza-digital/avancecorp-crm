# Coordinación — «Llamadas desde el celular» (Jhosep ↔ Miguel)

**Última actualización:** 13/10/2026, 15:14 UTC (10:14 Lima), por Jhosep (Claude). **PR #261 abierto: la pantalla de F4-e en
demo (pestaña «Llamadas del celular» y bloque «Su celular»), nada que aplicar; turno de Miguel.** El #255 (la decimotercera,
preparada y probada) lo fusionó Miguel el 12/10 a las 22:27 UTC, pero la migración **sigue sin aplicar** (ledger, tipos) y
faltan sus dos decisiones y la #21. El #254 (documentos) quedó fusionado a las 20:41 UTC. Lo
anterior: 08/10/2026, ~01:30 UTC (07/10 20:30 Lima). **H1–H3 hechos:** las doce migraciones y la
Edge están en producción y la app se publicó con el interruptor encendido (#222, `build-20261007T222046462Z`; acta
`INSTALACION-20261007.md`). **C1 está activo desde el 07/10 ~19:15 Lima (H4 en curso)**: P1–P3, P6, P7 y P15-A1 PASS; P9 parcial, con un hallazgo para Miguel (`REGISTRO.md` §5i). Las decisiones #16, #17 y #18 están aprobadas
(`DECISIONES-PENDIENTES.md`). Seguimiento tarea por tarea: `SEGUIMIENTO.md`. Para retomar: `HANDOFF-2026-10-08.md`.
**Para qué sirve:** que los dos agentes no trabajen cada uno por su lado. Antes de actuar, se lee este archivo. Aquí
están las reglas, el mapa de los PR, el turno de cada uno, el orden y lo que ya pasó.

## 1. Reglas

1. **Un solo PR abierto a la vez.** Hoy es el **PR del seguimiento de la instalación**, de
   `crm/llamadas-seguimiento-instalacion-20261007` (solo documentos).
   - El #190 (las doce migraciones, la Edge, el gate y F4-b) se fusionó en `main` el 06/10; el #198 había entrado en él.
   - El #215 (F4-c) se fusionó el 07/10 con squash (`5f42e908`).
   - El #221 (documentos) se fusionó el 07/10 (`8e1c521a`) y el #222 de Miguel (activación) también (`d4c9a689`).
   - Lo que prepara el que no tiene el turno va en una **rama aparte**, sin PR, montada sobre la cabeza del PR abierto.
   - La rama vieja `crm/llamadas-f4d-activacion-20261007` quedó obsoleta: estaba montada sobre el #215 y, tras el
     squash, su PR habría vuelto a mostrar F4-c. La nueva sale de `main` con solo los commits de documentos.
2. **Cada PR tiene un solo escritor, el que tiene el turno.**
   - Solo quien tiene el turno sube commits a esa rama.
   - El otro comenta y espera.
3. **Pedir el turno:**
   - Si el que no tiene el turno necesita escribir en esa rama (por ejemplo, para arreglar algo que falló en el gate), lo
     pide en un comentario: `TURNO: pido el #190 para <qué>`.
   - Espera la respuesta `TURNO: #190 para Jhosep`.
   - Al terminar, lo devuelve.
4. **Antes de actuar:** `git fetch`, leer este archivo y leer el último comentario del PR.
5. **Cada novedad va en un solo comentario, con este formato:**
   ```
   QUÉ HICE: <una línea>
   RESULTADO: PASS / FAIL (+ evidencia: líneas ✗, sha, captura)
   TURNO PARA: Miguel | Jhosep
   ```
6. **Este archivo lo escribe Jhosep (Claude).**
   - El agente de Miguel informa en el PR con el formato de arriba.
   - Nosotros lo pasamos a la bitácora de la sección 4.
   - Así cada cosa tiene un solo escritor.

## 2. Mapa de los PR

| Rama | Qué es | Turno | Estado |
| --- | --- | --- | --- |
| **#261** `crm/llamadas-f4e-pantalla-20261013` | Pantalla de F4-e (F6.3.1) sobre la puerta del #255, en demo: tercera pestaña «Llamadas del celular» en gerencia (tabla por equipo + ficha, solo hoy) y bloque «Su celular» en el supervisor (más su celular al pie); esquema del jsonb con sumas, demo del store, tipo a mano hasta `gen:types`; documentos (estado.json 243–249, SEGUIMIENTO, nota del vault). Verificado: typecheck, lint, 6659/6660, E2E Docker demo, `revisor-a11y`, navegador. NOT RUN: `gate:realidad`, producción. **Nada que aplicar en la base.** | **Miguel** | Abierto el 13/10 15:14 UTC. Le toca: fusionar (squash). Siguen del #255: aplicar la decimotercera, `gen:types` (si cambia la firma a mano, avisar), dos decisiones y la #21. Luego publicar y aceptar en C1 con los dos roles |
| **#255** `crm/llamadas-f4e-operacion-hoy-20261012` | F4-e (F6.3.1): decimotercera migración `20261012192500_crm_llamadas_celular_operacion_hoy.sql` (puerta `crm.llamadas_celular_operacion_hoy_fn` definer + núcleo invoker), reversa, registrador, oráculo O1–O17, 25 mutantes (453/453 local), bloque del gate (NOT RUN), ledger, encargo a Codex (NOT RUN) y estos documentos (tablero y `estado.json` hasta el cambio 241). `auditor-rls` PASS. **Nada aplicado.** Lleva además la **propuesta #21** (cierre en lote) con su encargo para Codex, solo para opinar | **Miguel** | Abierto el 12/10 20:46 UTC. Le toca: su banco y `EXPLAIN` < 100 ms, gate con `CRM_RLS_EXIGE_LLAMADAS_F4E=1`, advisors, aplicar, registrar, `gen:types`; confirmar dos decisiones (retención desde la política; sin porcentajes en el jsonb). Ojo: el #256 (suyo) también toca `MIGRACIONES.md`; el segundo en fusionarse resuelve un conflicto trivial |
| **#254** `crm/llamadas-docs-20261012` | Solo documentos: aceptación de F4.2.4 en C1 (48/102), I-1 a I-5 en `SOPORTE.md`, macros de C1 exportadas (`ACTIVAR-C2.md` §3A), hallazgos H-BLANCO y H-GUARDANDO, propuestas #19 y #20, decisiones de Miguel del 12/10, tablero y `estado.json` hasta el cambio 231 | — | **Fusionado** por Miguel el 12/10 20:41 UTC (`ebdc72c9`), sin comentarios |
| **#251** `crm/llamadas-c2-aviso-b7-20261010` | F4.2.4 (B7): botón «Unir a un resultado guardado» + panel «¿Es este su resultado?» (solo pantalla sobre `crm.enlazar_llamada_celular`); `ACTIVAR-C2.md`; borrador `AVISO-TRATAMIENTO.md`; seguimiento y `estado.json` hasta el cambio 212 | — | **Aprobado, fusionado (`7b0d0716`) y publicado** por el agente de Miguel el 10/10 (`build-20261010T224357802Z`); el **#253** (0 archivos) devolvió el historial del release a `main` (`3f81c40f`). **Aceptado en C1 el 12/10** |
| **#249** `crm/llamadas-f4e-contrato-20261010` | Contrato y oráculos de F4-e (`F4E-CONTRATO.md`), F7.2.2 en `SOPORTE.md` §2.2, decisiones de Miguel (C2/C3, alcance, F4.2.4) | — | **Fusionado** el 10/10 (`82e5edde`). **OK explícito de Miguel a la sección 9 el 12/10** (#251, 6128409126): se puede preparar la migración |
| **#190** `crm/llamadas-quinta-migracion-20261005` | Las doce migraciones de llamadas, la Edge, el gate, F4-b con la fuente real conectada y los planes de F4-c/F4-d/F4-e | — | **Fusionado en `main`** el 06/10 23:28 UTC (`d1f16fea`). **Aplicado en producción el 07/10** (H1, acta `INSTALACION-20261007.md`) |
| **#215** `crm/llamadas-f4c-celulares-20261006` | F4-c: la tarjeta «Celulares» de Configuración (solo gerencia), detrás del interruptor `LLAMADAS_CELULAR_APROBADAS`; sin migración | — | Aprobado por Miguel el 07/10 21:10 UTC (validación de cierre PASS, sin P0–P2; 6366/6366, E2E Docker 4/4) y **fusionado en `main`** a las 21:28 UTC con squash (`5f42e908`). Trae el checklist de las doce |
| **#221** `crm/llamadas-f4d-documentos-20261007` | `ACTIVAR-C1.md` (guía del día de F4-d), `SEGUIMIENTO.md`, `DECISIONES-PENDIENTES.md` y los documentos al día. Rehecha desde `main` con solo los commits de documentos de la rama vieja `crm/llamadas-f4d-activacion-20261007` (obsoleta) | — | **Fusionado** el 07/10 21:54 UTC (`8e1c521a`) |
| **#222** `crm/habilitar-llamadas-celular-20261007` (Miguel) | Activación: interruptor encendido, tipos regenerados desde producción, ledger «EN PROD» y acta `INSTALACION-20261007.md` | — | **Fusionado** el 07/10 22:18 UTC con autorización administrativa de Miguel (`d4c9a689`) y **publicado** (`build-20261007T222046462Z`, 121/121 archivos idénticos) |
| **#224** `crm/llamadas-seguimiento-instalacion-20261007` | `SEGUIMIENTO.md`, `estado.json`, el tablero y los documentos al día con la instalación acreditada, y `HANDOFF-2026-10-08.md` | — | **Fusionado** el 08/10 (`c80ef9aa`). Los PR del 08–10/10 (#227, #228, #231, #232, #235, #243) están en `SEGUIMIENTO.md` |

## 3. Orden

| # | Quién | Qué | Cómo |
| --- | --- | --- | --- |
| 1 | **Miguel** | ~~Aplicar en producción las doce, sin activar C1; después `LLAMADAS_CELULAR_APROBADAS = true` y release~~ | **Hecho el 07/10** (H1–H3, #222): ensayo con SLA activo en una rama temporal de Supabase, publicación con `merge_branch`, Edge activa y `build-20261007T222046462Z`. Acta: `INSTALACION-20261007.md` |
| 1b | **Miguel** | ~~Revisar y fusionar el #215 (F4-c)~~ | Hecho: aprobado a las 21:10 UTC y fusionado a las 21:28 UTC del 07/10 (`5f42e908`) |
| 2 | Miguel | ~~Los 8 fallos de fondo del gate global (fila bancaria ×1, R2/hito ×3, bandera `potencial_lead` ×4)~~ | **Resueltos el 07/10** completando fixtures, sin debilitar aserciones: banco local 3292/3292 (acta) |
| 3 | **Jhosep** | **Pro no se compra por ahora (Jhosep, 08/10 y 12/10); MacroDroid gratis se renueva cada 3 días (hechos el 09/10 y el 12/10; próximo 15/10…)** (#18; el 10/10 Miguel autorizó Pro corporativo para 2–3 celulares hasta S/ 57) | Con la cuenta corporativa. Comprobar que sigue en S/ 19 pago único; si cambia o pide suscripción, avisar antes de aceptar. Sin compartir credenciales ni datos de pago. Registrar equipo, licencia y fecha (saneado), confirmar que desapareció el límite por días y devolverle la evidencia a Miguel. La #16 también está aprobada: F0 con diez salientes por equipo |
| 4 | **Jhosep**, con gerencia; Claude guía | ~~**F4-d: activar C1 (H4) y correr P1–P15** contra la Edge real~~ | **Hecho:** C1 activo desde el 07/10; **F4-d aceptada en C1 el 09/10** (P1–P15 y la consulta sin números de Miguel, #231). `ACTIVAR-C1.md`; evidencia en `REGISTRO.md` §5i–§5j |
| 5 | Claude prepara; Miguel aprueba | F4-e: vista de supervisor y gerencia | **Contrato y oráculos en `F4E-CONTRATO.md` (#249, aprobado el 10/10)** con A1–A7 y D1–D5 respondidas. **OK explícito de Miguel a la sección 9 el 12/10.** **Hecho el 12/10 (PR #255):** plan corto con el OK de Jhosep, migración con oráculo O1–O17 y 25 mutantes (453/453 local), `auditor-rls` PASS. Sigue (Miguel): su banco y `EXPLAIN`, gate y advisors, aplicar, registrar, `gen:types`; después, la pantalla (PR aparte) |
| 6 | **Miguel** | ~~**#251**: revisar, fusionar y publicar; revisar el borrador del aviso~~ | **Hecho el 10/10** por su agente (aprobado 22:31 UTC, fusionado `7b0d0716`, publicado `build-20261010T224357802Z`; #253 devolvió el historial del release a `main`). **Aviso de tratamiento: resuelto** (Miguel, 12/10: Legal lo aprobó y tramitó; no se incorpora al sistema). H-P5 y H-P10 siguen en su sesión (hilo del #232) |
| 7 | **Jhosep**; Claude guía | ~~Lunes 12/10: renovar MacroDroid en C1; aceptar F4.2.4 en C1~~ · **C2 y C3** con `ACTIVAR-C2.md` cuando Jhosep tenga los celulares | **Hecho el 12/10:** MacroDroid renovado (próximo 15/10) y **F4.2.4 aceptada** (48/102; `REGISTRO.md` §5k). Para C2/C3 ya están los tres `.macro` de C1, limpios (§3A): ~10 min por celular, de a uno, evidencia sin números |
| 8 | **Miguel** | Decidir las propuestas **#19** (llamadas largas: margen desde el inicio) y **#20** (activar celulares sin trabajo manual, para después del piloto) y el arreglo de **H-BLANCO** (protección general de la pantalla que ofrezca actualizar en vez de quedar en blanco; solo pantalla) | Cuando le convenga: nada de esto bloquea C2/C3 ni F4-e |

En la guía del #190, **los pasos 2 (#193) y 3 (#195) ya no existen**: los reemplaza esta tabla.

**Si algo sale mal tras dar de alta un celular** (Miguel, 07/10): se cierra su asignación o su clave desde la tarjeta, o
se apaga la pantalla con un release aprobado; el historial se conserva y se corrige hacia adelante. **Nunca** se ejecutan
las reversas SQL con el sistema en uso.

## 4. Bitácora (lo más nuevo arriba)

- **12/10 17:00–17:15 Lima (22:00–22:15 UTC) — Miguel y Jhosep, en el #255:** el agente de Miguel corrió Codex r1 sobre
  el encargo de F4-e y subió a la rama del PR la corrección de su P2 (`868db397`, merge `628f9c09`): el registrador ahora
  certifica el catálogo instalado (huellas de los dos cuerpos, atributos y permisos) con 13 pasos nuevos en el banco
  local; la migración no cambió. Nuestra sesión lo trajo, lo verificó aquí (466/466) y lo aceptó en el PR. Antes
  (16:55 Lima) entró la propuesta #21. Pendiente de Miguel: lo mismo del PR, más su opinión sobre la #21.
- **12/10 (14:00–15:55 Lima) — Jhosep:** sesión desde su cuenta nueva de Claude (el tablero siguió escribible).
  **F4-e construida con su OK al plan corto:** rama `crm/llamadas-f4e-operacion-hoy-20261012` desde `main`,
  decimotercera migración + reversa + registrador + oráculo O1–O17 (doble del roster del pulso en el banco reducido) +
  pasada 19 con 25 mutantes (`test:llamadas:local` 453/453) + bloque del gate (NOT RUN aquí) + ledger + encargo a Codex
  (NOT RUN: no instalado). `auditor-rls` PASS: tres P3 aplicados antes del commit. **Miguel fusionó el #254** (20:41
  UTC, sin comentarios): `main` local al día, worktree retirado, rama rebasada. **PR #255 abierto (20:46 UTC)** con la
  tabla para Miguel; estos documentos entran al mismo PR (decisión de Jhosep: menos PR). Vigilante con el #255. El
  #256 (Miguel, conversión sin renovaciones) también toca `MIGRACIONES.md`: conflicto trivial para el segundo.
- **12/10 (09:50–12:10 Lima) — Jhosep:** el #251 ya estaba fusionado y publicado por el agente de Miguel desde el
  10/10 (su cierre: 6104173210; investigación I-1 a I-3 en banco). Relevo entregado en el #251 (6126783439: sección
  «Noche del 10/10» saneada, definición de I-5, cómo funciona el vigilante). **MacroDroid renovado** en C1 (10:22).
  **F4.2.4 aceptada en C1** (`REGISTRO.md` §5k; comprobado en la base en solo lectura) → 48/102, F4.2 cerrada.
  **I-5 confirmada** en banco desechable con las doce migraciones. **Macros de C1 exportadas** (tres `.macro` limpios,
  revisados sin ver su contenido; C1 operativo otra vez con su misma clave). Hallazgos vistos una vez: H-BLANCO y
  H-GUARDANDO. **Decisiones de Miguel (6128409126):** OK a la sección 9 de F4-e; aviso de tratamiento resuelto por
  Legal. Propuestas #19 y #20. Todo en este PR de documentos.
- **10/10 17:05 Lima (22:05 UTC) — Jhosep:** **revisión del agente de Miguel en el #251 corregida** (comentario
  6102475635: dos P2 y cuatro P3, todos comprobados por nuestra sesión; el P2 de las 500 actividades, reproducido con su
  prueba). Un commit en la misma rama: la búsqueda de la unión manual sigue hasta salir del margen y consulta los ya
  unidos en tandas de 500 (regresiones con 501); la demo descuenta los ya unidos; el panel dice «desde 10 minutos antes»;
  el aviso separa la anulación de la clave del apagado en el celular; la guía de soporte suma los pasos locales del
  retiro; ACTIVAR-C2 deja H-PERMISO como hipótesis y endurece la exportación desde C1; el plan corto ya no dice «mismo
  analista». Turno de Miguel: revisar ese commit.
- **10/10 15:55 Lima (20:55 UTC) — Jhosep:** **PR #251 abierto (listo)**: F4.2.4 programada (botón «Unir a un resultado
  guardado», solo pantalla; verificado: typecheck, lint, 6619 unitarias y E2E Docker 2/2), `ACTIVAR-C2.md`, borrador del
  aviso de tratamiento, seguimiento y `estado.json` hasta el cambio 207. Aviso en el PR con el turno para Miguel. Lo
  confirmado por Miguel en el #249 (10/10): C2 y C3 el lunes 12/10; doble SIM e internacionales fuera del alcance
  (F3.3.4 marcada, 47/102); F4-e: contrato aprobado, falta el OK a la sección 9.
- **07/10 19:10–20:20 Lima (08/10 00:10–01:20 UTC) — Jhosep:** **activa C1 en producción (H4).** Alta desde la tarjeta
  «Celulares» con gerencia (primer uso real tras el release), clave por WhatsApp, colas vacías y la Edge real en
  MacroDroid; a los ~5 min, «Al día» con `llamadas-v3`. Pruebas (`REGISTRO.md` §5i): P1, P2, P3, P6, P7 y P15-A1 PASS;
  **P9 PARCIAL**: tras «Deshacer» la llamada no vuelve a «Pendientes» y la pantalla no ofrece cómo unir el resultado
  corregido (hallazgo para Miguel). Incidencia: una captura mostró 16 de 64 caracteres de la clave; se rota en P11.
  Pro sin comprar (Jhosep: renovar con anuncios si hace falta). Sigue el 08/10 con P13, P12 y P11 (`HANDOFF-2026-10-08.md`).
- **07/10 ~23:30 UTC — Jhosep:** pasa la instalación acreditada al seguimiento y al tablero, sin cerrar tareas
  físicas: F2.4.3 y F3.2.1 marcadas (33/102); F2, F3 y F4 «Instalada»; F7.3.1 y F7.3.2 en curso con el primer release.
  Abre el PR de `crm/llamadas-seguimiento-instalacion-20261007` y deja `HANDOFF-2026-10-08.md`. Mañana: Pro y C1.
- **07/10 22:26 UTC — Miguel (Codex):** **H1–H3 PASS y publicados** (comentario en el #222). Las doce por
  `merge_branch` tras ensayar con SLA activo (banco 3292/3292, con los 8 fallos viejos resueltos completando fixtures;
  rama 328/328); Edge activa (401 sin clave; seis casos); #222 fusionado a las 22:18 con autorización administrativa de
  Miguel; release `build-20261007T222046462Z` con 121/121 archivos idénticos; smoke con Analista. Límites que declara:
  la revisión secundaria no dio veredicto, 15 WARN de advisors que considera intencionales y sin smoke manual de
  Gerencia. Turno: **Jhosep** (seguimiento, Pro, activar C1, P1–P15 y piloto).
- **07/10 21:54 UTC — Miguel:** fusiona el #221 (documentos) con squash (`8e1c521a`).
- **07/10 ~21:45 UTC — Jhosep:** pasa las tres decisiones aprobadas y la fusión del #215 a `DECISIONES-PENDIENTES.md`
  (texto de Miguel tal cual), `PROPUESTAS-DE-AJUSTE.md`, `SEGUIMIENTO.md`, `F4E-PLAN-CORTO.md`, `macrodroid.md`,
  `README.md`, `estado.json` y el tablero. Abre el PR de documentos desde `crm/llamadas-f4d-documentos-20261007`, rehecha
  desde `main` con solo los commits de documentos.
- **07/10 21:28 UTC — Miguel:** **fusiona el #215** en `main` con squash (`5f42e908`), después de actualizarlo con
  `main` (`e34a9172`: #218–#220, tasas, ajenos).
- **07/10 21:20 UTC — Miguel (Codex):** encarga a su agente «haz todo»: integrar el #215, ensayar con SLA activo en una
  rama temporal de Supabase (autorizada por Miguel), aplicar las doce, desplegar y publicar (H1–H3). **Aprueba las tres
  decisiones** (texto tal cual en `DECISIONES-PENDIENTES.md`): #18 Pro para el piloto (Jhosep compra C1 antes del
  09/10), #16 (F0 con diez salientes; las entrantes a la #14) y #17 con la decisión 4 (F4-e en F4 tras la aceptación de
  F4-d en C1; A1–A7 con cuatro condiciones). El piloto conserva sus cinco días y las noches que faltan; Jev sigue
  apagado. Turno: **Miguel** fusión y H1–H3; **Jhosep** compra de Pro, pendientes físicos y preparación de F4-d/F4-e en
  su rama. Avisará en el hilo del #215 al terminar la instalación para activar C1.
- **07/10 21:10 UTC — Miguel (Codex):** **aprueba el #215** (validación de cierre sobre `d7dfd5b4`): el P2 queda
  resuelto y no hay hallazgos P0–P2 nuevos. Sus pruebas: `npm run check` 6366/6366, E2E Docker 4/4
  (`config-celulares` + `config-demo`), `git diff --check` y `git merge-tree` con `main` (`ba702c61`) sin conflictos.
  Aclara que aprobar no instala nada ni cierra F0–F7, y que **no aprueba las decisiones #16, #17/A1–A7 y #18**: siguen
  abiertas. Producción: 0/12, sin tablas ni `crm-llamadas-ingesta`, SLA activo (revisión 1). Turno: **Miguel** fusiona
  e instala (ensayo con SLA activo, las doce desde LF, Edge y publicación); Jhosep sigue con F4-d y los pendientes
  físicos y de documentos, sin tocar la rama en revisión.
- **07/10 20:57 UTC — Jhosep:** pide a Miguel **cerrar el #215 en esta vuelta** (comentario 6046710649): qué es, qué
  cambió desde su revisión, evidencia (CI verde en `d7dfd5b4`, 6366/6366 en local, E2E 4/4, sin conflictos con `main`
  tras el #218 y el #219), qué no lo bloquea y un encargo listo para su agente. Propuesta: todos los hallazgos en un solo
  comentario; si no hay P0–P2, aprobar y fusionar; si hay algo, el turno a Jhosep y un solo commit; lo menor, al PR de
  F4-d. Turno: Miguel.
- **07/10 20:47 UTC — Jhosep:** manda a Miguel las **tres decisiones con propuesta**, validadas por Jhosep
  (`DECISIONES-PENDIENTES.md`; comentario 6046549470 del #215): #18 Pro (S/ 19 pago único; comprarla para C1 antes del
  09/10), #16 (cerrar F0 con salientes) y #17 (F4-e en F4, después de F4-d; A1–A7). Antes, pruebas físicas en C1 contra
  el receptor, todas PASS (`REGISTRO.md` §5h): 429 (cierra F3.3.2), fijo con +51, pantalla bloqueada, lead propio con
  celular y ráfaga de 3. Seguimiento: 31/102. Turno: Miguel.
- **07/10 ~19:15 UTC — Jhosep:** entrega el **seguimiento conciliado** que pidió Miguel: `SEGUIMIENTO.md` con las 102
  tareas (estado, evidencia, siguiente paso, responsable, dependencia), 30 cerradas con evidencia (+5), tablero y
  `estado.json` al día, y textos viejos corregidos (`README.md`, esta regla 1, `F4C-F4D-PLAN-CORTO.md`,
  `F4E-PLAN-CORTO.md`, `PUBLICAR-F2-F3.md`, `macrodroid.md`). Va en la rama aparte, sin tocar el #215.
- **07/10 18:24 UTC — Miguel (Codex):** recibe la corrección del P2 (`d7d498d2`) como entregada, pendiente de su
  validación de cierre sobre la cabeza final del #215 (`d7dfd5b4`, que integra `main`). Repasa el plan entero F0–F7 y
  pide el seguimiento conciliado por ID, documentos al día y las decisiones pendientes con propuesta (#16, #17/A1–A7,
  #18). Producción: 0/12, sin Edge, SLA activo, interruptor cerrado. Turno: Jhosep para el seguimiento; la revisión de
  cierre y la instalación siguen con Miguel.
- **07/10 18:17 UTC — Miguel:** «Update branch» del #215 (trae `main`: reparto libre y #211). Sin cambios en el código de
  F4-c.
- **07/10 15:52 UTC — Jhosep:** corrección del P2 en `d7d498d2` (alta y rotación separadas en la ventana de la clave,
  con regresión); `npm run check` 6338/6338 y E2E 4/4. Turno a Miguel.
- **07/10 15:33 UTC — Miguel (Codex):** revisión del #215, **CHANGES_REQUESTED, P2:** al rotar, la ventana de la clave
  repetía los pasos del alta y mandaba vaciar las colas del celular (avisos que aún no llegaron). Pide distinguir alta
  de rotación, conservar las colas al rotar y una regresión. Su verificación: `npm run check` 6338 PASS, E2E 4/4.
  **Producción:** 0/12 aplicadas, sin Edge, SLA **activo** (su banco estaba en `legado`): ensayar así antes de aplicar.
  Orden acordado: primero esta corrección; después las doce. Turno: Jhosep.
- **07/10 ~15:00 UTC — Jhosep:** **F4-c programada** en `crm/llamadas-f4c-celulares-20261006` (desde `main`, con
  `main` integrado): tarjeta «Celulares» en Configuración, solo gerencia, detrás del mismo interruptor que F4-b
  (`LLAMADAS_CELULAR_APROBADAS`, hoy `false`: en producción no se ve hasta que Miguel aplique la base y lo abra).
  Pruebas unitarias, API con MSW, E2E en Docker (4/4) y prueba manual en la demo. Va como PR borrador aparte; detalle en
  `F4C-F4D-PLAN-CORTO.md` («Decisiones al programar»). Comentario a Miguel en el #190 (6039930109) con el orden para
  aplicar las doce y el aviso del LF.
- **06/10 23:28 UTC — Miguel:** aprobó y **fusionó el #190 en `main`** (`d1f16fea`, squash). Su visto bueno: «la
  aplicación de las doce migraciones, el despliegue y la activación de C1 siguen siendo pasos separados». Los 8 fallos
  del gate quedan aparte.
- **06/10 ~22:00 — Jhosep:** analizó los 8 fallos de fondo del gate solo leyendo y los informó en el #190 (comentario
  6026187290): potencial ×4 confirmado (bandera encendida, una guarda escrita dos veces), R2 ×3 y bancaria ×1 por
  confirmar con sus líneas ✗. Decisión de Jhosep: solo informar; PR aparte, de Miguel.
- **06/10 ~23:50 — Jhosep:** prototipos de F4-c (tarjeta «Celulares») y F4-e (vista del día de supervisor y gerencia)
  hechos sobre las pantallas reales y **aprobados**. Enlaces en `HANDOFF-2026-10-07.md`. F4-c arranca en la rama
  `crm/llamadas-f4c-celulares-20261006` desde `main` (D1 resuelta: PR nuevo desde `main`).
- **06/10 ~21:00 — Jhosep:** revisó la entrega de Miguel con evidencia y le devuelve el turno.
  - Mismos números que Miguel: Edge 17 + 18 mutantes, app 6245/6245 y banco reducido 415/415.
  - Hallazgo P3: la duodécima compara huellas md5 del texto de siete funciones con los saltos de línea incluidos. Si las
    migraciones anteriores se instalaron desde una copia con CRLF (Windows con `autocrlf`), se niega a aplicarse. En
    producción no afecta si se aplica desde LF, igual que los registradores.
  - Puso el #190 al día con `main` (#205).
  - Sumó tres documentos: las decisiones de F4-c/F4-d, la macro final de C1 armada y probada (P1, P2, P4 y P5 PASS)
    y la propuesta #18.
  - Decisión de Jhosep: los 8 fallos de fondo del gate global se aceptan como previos y ajenos, y van en un PR aparte.
- **06/10 ~16:00 (Lima) — Jhosep, en C1:** MacroDroid gratuito estaba desactivado desde ~02/10 porque vencieron sus
  días gratis. Se reactivó (+3 días, vence ~09/10). Con eso salió la propuesta #18.
- **06/10 19:11 UTC — Miguel (Codex):** entrega `5df2764e`.
  - Integró la rama aparte entera.
  - **Duodécima** `20261006162813`: cierra los cinco P2.
  - Conectó la fuente real de la pestaña y la v5 con recibo, y cerró los pendientes de pantalla y de accesibilidad.
  - Tipos regenerados.
  - App 6245, E2E 17/17, banco reducido 415/415, bloque de llamadas 197/197. Gate global: 8/3014, los mismos de antes.
  - Informe: `CIERRE-CORRECCIONES-20261006.md`.
- **06/10 ~17:00 — Jhosep:** a pedido del agente de Miguel («si ya tienes cambios preparados, avísanos»), deja la rama
  aparte `crm/llamadas-190-integrar-jhosep-20261006` sobre `ae2435e2`. No toca el #190.
  - Lleva la fusión con `main` (`33694da6`) y la resolución de `router.ts` (`consultaCitas` 7.º, `llamadaOrigenId` 8.º).
  - Lleva la décima, que cubre el primer pendiente de pantalla del informe, y la undécima, la fuga del latido, que no
    estaba en el informe.
  - Lleva los planes cortos.
- **06/10 16:26 — Miguel:** su agente (Codex) toma el turno del #190 para corregir todos los pendientes del informe.
- **06/10 16:10 — Miguel:** ensayo en un banco Docker a paridad con producción.
  - PASS: las nueve con sus registradores, V1–V5 y las reversas.
  - Gate: el bloque de llamadas dio 188 ✓ y 0 ✗; los 8 rojos que quedan son ajenos a llamadas.
  - Advisors sin alertas nuevas de nivel aviso. Tipos: limpios, pero no subidos.
  - Causa del FAIL anterior: a su banco le faltaban las filas de `sla_operacion_control` y `piloto_f8_control`.
  - Pidió no fusionar todavía por el choque con `main`, cinco P2 de base y Edge (1 y 2 con decisión suya) y pendientes
    de pantalla.
- **06/10 — Jhosep:** análisis de las etapas siguientes y dos arreglos, todo en el #198 sin tocar el #190.
  - Planes cortos `F4C-F4D-PLAN-CORTO.md` (tarjeta «Celulares» y runbook para activar C1) y `F4E-PLAN-CORTO.md`
    (supervisor y gerencia, con el diccionario para Miguel). Solo documentos.
  - **Décima** `20261006150154`: la bandeja y el detalle traen el id de origen. Sin él, registrar desde la pestaña no
    unía la llamada.
  - **Undécima** `20261006150254`: la salud deja de mostrar la hora exacta del latido. Esa hora era casi la de la
    última llamada, personales incluidas. La macro ahora manda el latido solo cada 6 h.
  - El oráculo de la quinta acepta las dos formas de la salud, así que sigue valiendo en el #190.
  - Banco reducido 399/399 (pasadas 17 y 18, 15 mutantes). Commit `7fdfee5c`, sin aplicar.
- **06/10 04:51 — Miguel:** fusionó el #198 dentro del #190. Desde entonces hay un solo PR con todo.
- **06/10 01:00 — Miguel:** primer informe del paso 1.6. El gate dio FAIL por un banco local viejo, no por el PR.
- **05/10 23:27 — Jhosep:** los PR quedan ordenados.
  - #193, #195 y #197 se juntan en el **#198** (mismos commits, mismo contenido; 6141/6141 en la suite de la app).
  - El #190 queda en manos de Miguel: no le subimos nada.
  - Se crea este archivo.
- **05/10 23:22 — Miguel:** «Update branch» del #190 (paso 1.1 de la guía).
- **05/10 22:53 — Jhosep:** novena `20261005224330`.
  - Resuelve la revisión del #195: «Qué pasó hoy» por páginas, y «hoy» = lo resuelto hoy en Lima.
  - Banco reducido: 360/360.
- **05/10 22:28 — Jhosep:** guía ejecutable en el #190 (`CIERRE-PARA-EL-AGENTE-DE-MIGUEL.md`).
- **05/10 22:00 — Miguel:** revisión del #195. Pide paginar la lectura y definir qué es «hoy».
- **05/10 18:46 — Miguel:** tercera revisión del #190.
  - No hay defectos nuevos.
  - Para publicar falta el gate con el esquema de producción.
  - No se activa C1 antes de F4-b.

## 5. Lo que necesitamos de vuelta de Miguel

- [x] El #190 fusionado (06/10 23:28 UTC, `d1f16fea`). Los tipos vinieron dentro.
- [x] «Las doce aplicadas» y la Edge desplegada con el interruptor abierto (07/10, #222, `INSTALACION-20261007.md`).
- [x] Su revisión del #215 (07/10) y las decisiones #18, la 4 de F4-e y A1–A7 (07/10).
- [x] F4-d aceptada en C1 con su consulta sin números (09/10, #231); H-WA cerrado (#232).
- [x] Las decisiones del punto 1 del #251 (su revisión del 10/10 recomienda conservar las tres).
- [x] **#251** revisado, fusionado y publicado (su agente, 10/10); aviso de tratamiento **resuelto** (12/10).
- [x] **OK explícito a la sección 9 del contrato de F4-e** (12/10).
- [x] Lo anotado el 10/10 sobre la unión a mano, investigado: I-1 a I-3 por su agente en banco (10/10) e I-5 por
  nuestra sesión (12/10). Aceptamos sus recomendaciones: el nuevo dueño sí puede unir a mano (dentro del ámbito); el
  reloj adelantado es una limitación documentada; el supervisor sin pestaña se coordina con F4-e. `SOPORTE.md` al día.
- [ ] Decidir **#19** (llamadas largas), **#20** (activación sin trabajo manual) y el arreglo de **H-BLANCO**.
- [ ] H-P5 y H-P10 (su sesión; avisa en el hilo del #232).
- [ ] **#255 (F4-e):** su banco y `EXPLAIN` < 100 ms, gate con `CRM_RLS_EXIGE_LLAMADAS_F4E=1`, advisors, aplicar,
  `registrar-operacion-hoy.sql`, `gen:types`; y confirmar dos decisiones: la retención de las pendientes sale de la
  política (hoy 30 días) y ningún porcentaje viaja en el jsonb.
- [ ] **Propuesta #21** (cierre en lote de llamadas pendientes del mismo lead; idea de Jhosep, 12/10): su opinión y
  las cinco decisiones de `PROPUESTAS-DE-AJUSTE.md` #21; si quiere, pasar a Codex el encargo
  `docs/encargos/2026-10-12-codex-cierre-en-lote-propuesta-21.md` (solo análisis, sin código).

## En llano

El #251 ya está en producción y la unión a mano quedó probada en C1: van 48 de 102. Miguel destrabó lo que faltaba:
el aviso de tratamiento lo resolvió Legal y F4-e tiene su visto bueno para la migración. Las macros de C1 ya están
exportadas y limpias, así que C2 y C3 se activan en unos minutos cuando Jhosep tenga los celulares. El 12/10 por la
tarde quedó escrita y probada la consulta de F4-e (PR #255): a Miguel le toca aplicarla; después va su pantalla. La carpeta del plan (`PLAN.md`, `AVANCE.md`,
`estado.json`, `SEGUIMIENTO.md`) sigue siendo el espejo del tablero vivo.

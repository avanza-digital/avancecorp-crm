# Coordinación — «Llamadas desde el celular» (Jhosep ↔ Miguel)

**Última actualización:** 07/10/2026, ~21:20 UTC, por Jhosep (Claude). **El #190 ya está fusionado en `main`**
(`d1f16fea`); falta aplicarlo en producción, desplegar y activar C1 (pasos de Miguel). **F4-c está en el PR #215,
aprobado por Miguel el 07/10 a las 21:10 UTC**; falta que lo fusione. Seguimiento tarea por tarea: `SEGUIMIENTO.md`. Decisiones con propuesta para Miguel:
`DECISIONES-PENDIENTES.md`. Para retomar: `HANDOFF-2026-10-07.md`.
**Para qué sirve:** que los dos agentes no trabajen cada uno por su lado. Antes de actuar, se lee este archivo. Aquí
están las reglas, el mapa de los PR, el turno de cada uno, el orden y lo que ya pasó.

## 1. Reglas

1. **Un solo PR abierto a la vez.** Hoy es el **#215** (F4-c, la tarjeta «Celulares»).
   - El #190 (las doce migraciones, la Edge, el gate y F4-b) se fusionó en `main` el 06/10; el #198 había entrado en él.
   - Lo que prepara el que no tiene el turno va en una **rama aparte**, sin PR, montada sobre la cabeza del PR abierto.
     Hoy: `crm/llamadas-f4d-activacion-20261007` (la guía `ACTIVAR-C1.md` y `SEGUIMIENTO.md`), que se abre como PR
     cuando cierre el #215.
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
| **#190** `crm/llamadas-quinta-migracion-20261005` | Las doce migraciones de llamadas, la Edge, el gate, F4-b con la fuente real conectada y los planes de F4-c/F4-d/F4-e | — | **Fusionado en `main`** el 06/10 23:28 UTC (`d1f16fea`). **Sin aplicar en producción**; la lista para aplicar está en el #215 |
| **#215** `crm/llamadas-f4c-celulares-20261006` | F4-c: la tarjeta «Celulares» de Configuración (solo gerencia), detrás del interruptor `LLAMADAS_CELULAR_APROBADAS`; sin migración | **Miguel** (fusionar) | **Aprobado** el 07/10 21:10 UTC (validación de cierre PASS, sin P0–P2) sobre `d7dfd5b4`; sigue en borrador hasta que Miguel lo fusione. Su verificación: 6366/6366, E2E Docker 4/4. Trae el checklist de las doce |
| (sin PR) `crm/llamadas-f4d-activacion-20261007` | `ACTIVAR-C1.md` (guía del día de F4-d), `SEGUIMIENTO.md`, `DECISIONES-PENDIENTES.md` y los documentos al día; montada sobre el #215 | Jhosep | Solo documentos. Se abre como PR cuando cierre el #215 |

## 3. Orden

| # | Quién | Qué | Cómo |
| --- | --- | --- | --- |
| 1 | **Miguel** | ~~Fusionar el #190~~ (hecho) y **aplicar en producción las doce, sin activar C1**; después `LLAMADAS_CELULAR_APROBADAS = true` y release (abre F4-b y la tarjeta de F4-c) | Checklist con las doce, sus registradores y el orden en el **#215**; **desde una copia con LF**. Antes, comprobar el modo SLA real de producción (el banco estaba en `legado`) |
| 1b | **Miguel** | ~~Revisar el #215 (F4-c)~~ (aprobado el 07/10 21:10 UTC) y **fusionarlo** | Solo pantalla sobre puertas existentes; se puede fusionar antes de aplicar la base porque va detrás del interruptor |
| 2 | Miguel (o quien él diga) | Los 8 fallos de fondo del gate global (fila bancaria ×1, R2/hito ×3, bandera `potencial_lead` ×4) | **En un PR aparte**, después. Decisión de Jhosep (06/10): son previos y ajenos a llamadas, y no bloquean el #190 |
| 3 | **Miguel** decide | #18 MacroDroid Pro (**antes del 09/10**) y #16 cerrar F0 con salientes | `DECISIONES-PENDIENTES.md`, mandadas el 07/10. #18: S/ 19 pago único, visto en C1; propuesta: comprarla para C1 antes del 09/10. Si no decide a tiempo, Jhosep renueva los días gratis de C1 con un anuncio esa mañana |
| 4 | Los dos | F4-c (tarjeta «Celulares») y F4-d: activar C1 | `F4C-F4D-PLAN-CORTO.md` (decisiones de Jhosep del 06/10 y runbook). La macro final de C1 ya está armada y probada (`macrodroid.md` §3c, `REGISTRO.md` §5g). Nunca antes de aplicar («instalar no es activar») |
| 5 | **Miguel** decide, después los dos | F4-e: vista de supervisor y gerencia | #17 de `DECISIONES-PENDIENTES.md`: propuesta F4-e en F4, después de F4-d, y el diccionario A1–A7 de `F4E-PLAN-CORTO.md` |

En la guía del #190, **los pasos 2 (#193) y 3 (#195) ya no existen**: los reemplaza esta tabla.

## 4. Bitácora (lo más nuevo arriba)

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
- [ ] «Las doce aplicadas», con sha, hora y los veredictos `t` de los registradores (checklist del #215).
- [ ] La Edge desplegada y el interruptor abierto en un release.
- [ ] Su revisión del #215.
- [ ] Decisiones: #18 (MacroDroid Pro), la 4 de F4-e y A1–A7.

## En llano

Ahora hay dos PR, no cuatro: uno con la base y otro con la pantalla. El de la base es de Miguel y nadie más lo toca. El
de la pantalla espera a que él termine. Cada aviso va en un solo comentario con el mismo formato, y este archivo dice
siempre a quién le toca.

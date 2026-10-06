# Coordinación — «Llamadas desde el celular» (Jhosep ↔ Miguel)

**Última actualización:** 06/10/2026, 17:00 UTC, por Jhosep (Claude).
**Para qué sirve:** que los dos agentes no trabajen cada uno por su lado. Antes de actuar, se lee este archivo. Aquí
están las reglas, el mapa de los PR, el turno de cada uno, el orden y lo que ya pasó.

## 1. Reglas

1. **Hay un solo PR abierto: el #190.**
   - Trae la base (siete migraciones, la Edge y el gate) y F4-b (octava, novena y la pantalla del analista).
   - Miguel fusionó el #198 dentro del #190 el 06/10 a las 04:51 UTC.
   - Lo que prepara el que no tiene el turno va en una **rama aparte** montada sobre la cabeza del #190. El que tiene el
     turno la adopta (avance rápido si su cabeza no cambió) o toma sus commits.
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

| PR | Qué es | Base | Turno | Estado |
| --- | --- | --- | --- | --- |
| Rama | Qué es | Turno | Estado |
| --- | --- | --- | --- |
| **#190** `crm/llamadas-quinta-migracion-20261005` | Las siete + F4-b (octava, novena, pantalla) | **Miguel (Codex)** desde el 06/10 16:26 | Base PASS en banco a paridad (16:10). Falta: el choque con `main`, cinco P2 y los pendientes de pantalla |
| `crm/llamadas-190-integrar-jhosep-20261006` | Lo que Jhosep tenía listo, sobre `ae2435e2`: fusión con `main` (choque de `router.ts` resuelto), décima, undécima y planes cortos | (rama aparte) | Para adoptar o tomar commits. No es un PR |

## 3. Orden

| # | Quién | Qué | Cómo |
| --- | --- | --- | --- |
| 1 | **Miguel (Codex)** | Integrar la rama aparte y corregir los cinco P2 en una migración nueva, numerada **después** de `20261006150254` | P2 1 y 2 con la decisión de Miguel (06/10). Pruebas en el banco reducido y el gate |
| 2 | **Miguel** | Repetir el ensayo: las nueve + décima, undécima y la suya; gate, reversas y advisors | Igual que el informe del 06/10 16:10 |
| 3 | **Miguel** | Fusionar el #190 y aplicar en producción, **sin activar C1** | Pasos 1.7–1.8 de `CIERRE-PARA-EL-AGENTE-DE-MIGUEL.md`, con todos los registradores |
| 4 | Jhosep | Conectar la pestaña con los tipos | `npm run gen:types` tras aplicar |
| 5 | Los dos | F4-c (tarjeta «Celulares») y F4-d: activar C1 | Runbook en `F4C-F4D-PLAN-CORTO.md`. Nunca antes («instalar no es activar») |
| 6 | **Miguel** decide, después los dos | F4-e: vista de supervisor y gerencia | Decisión 4 (F4 o F6) y el diccionario A1–A7 de `F4E-PLAN-CORTO.md` |

En la guía del #190, **los pasos 2 (#193) y 3 (#195) ya no existen**: los reemplaza esta tabla.

## 4. Bitácora (lo más nuevo arriba)

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

## 5. Lo que necesitamos de vuelta del #190

- [ ] La tabla del paso 1.6 (update branch, las siete con sus registradores, gate, advisors y tipos).
- [ ] Los tipos (paso 1.5): el sha del commit, o por qué no se subieron.
- [ ] «Fusionado y aplicado» (paso 1.8), con sha y hora.

## En llano

Ahora hay dos PR, no cuatro: uno con la base y otro con la pantalla. El de la base es de Miguel y nadie más lo toca. El
de la pantalla espera a que él termine. Cada aviso va en un solo comentario con el mismo formato, y este archivo dice
siempre a quién le toca.

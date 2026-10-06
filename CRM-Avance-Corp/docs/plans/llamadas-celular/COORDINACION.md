# Coordinación — «Llamadas desde el celular» (Jhosep ↔ Miguel)

**Última actualización:** 06/10/2026, 15:24 UTC, por Jhosep (Claude).
**Para qué sirve:** que los dos agentes no trabajen cada uno por su lado. Antes de actuar, se lee este archivo. Aquí
están las reglas, el mapa de los PR, el turno de cada uno, el orden y lo que ya pasó.

## 1. Reglas

1. **Hay dos PR y nada más:**
   - **#190**: la base.
   - **#198**: la pantalla.
   - Los PR #193, #195 y #197 están cerrados. Todo su contenido está en el #198.
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
| **#190** | Siete migraciones, la Edge, el gate y las guías: la base, que se instala sin activar | `main` | **Miguel** | Paso 1.1 hecho (update branch, 23:22 UTC). Sigue el 1.2 |
| **#198** | F4-b: octava, novena, décima y undécima + la pantalla del analista (parte A y pestaña «Celular») + planes cortos de F4-c/F4-d y F4-e | rama del #190 | Jhosep (en espera) | Borrador. No se fusiona antes del #190. Le faltan los tipos |

## 3. Orden

| # | Quién | Qué | Cómo |
| --- | --- | --- | --- |
| 1 | **Miguel** | Cerrar el #190 hasta producción, **sin activar C1** | Pasos 1.2–1.8 de `CIERRE-PARA-EL-AGENTE-DE-MIGUEL.md` (en el #190). Informa con la tabla del 1.6 |
| 2 | Jhosep | Rehacer el #198 sobre `main` y conectar la pestaña con los tipos | Recién cuando el #190 esté fusionado y aplicado (aviso del 1.8) |
| 3 | **Miguel** | Revisar el #198 | `auditor-rls` + Codex sobre la octava, la novena, la décima y la undécima juntas. Gate con las once, `CRM_RLS_EXIGE_LLAMADAS=1` y `CRM_RLS_EXIGE_LLAMADAS_F4B=1` |
| 4 | **Miguel** | Fusionar y aplicar el #198 (las cuatro con la pantalla) | Igual que el paso 1.7, con sus registradores |
| 5 | Los dos | F4-c (tarjeta «Celulares») y F4-d: activar C1 (alta de la clave y macro productiva) | Recién aquí. Nunca antes («instalar no es activar»). Runbook en `F4C-F4D-PLAN-CORTO.md` |
| 6 | **Miguel** decide, después los dos | F4-e: vista de supervisor y gerencia | Decisión 4 (F4 o F6) y el diccionario A1–A7 de `F4E-PLAN-CORTO.md` |

En la guía del #190, **los pasos 2 (#193) y 3 (#195) quedan reemplazados por los pasos 2–4 de esta tabla**: esos PR ya
no existen.

## 4. Bitácora (lo más nuevo arriba)

- **06/10 — Jhosep:** análisis de las etapas siguientes y dos arreglos, todo en el #198 sin tocar el #190.
  - Planes cortos `F4C-F4D-PLAN-CORTO.md` (tarjeta «Celulares» y runbook para activar C1) y `F4E-PLAN-CORTO.md`
    (supervisor y gerencia, con el diccionario para Miguel). Solo documentos.
  - **Décima** `20261006150154`: la bandeja y el detalle traen el id de origen. Sin él, registrar desde la pestaña no
    unía la llamada.
  - **Undécima** `20261006150254`: la salud deja de mostrar la hora exacta del latido. Esa hora era casi la de la
    última llamada, personales incluidas. La macro ahora manda el latido solo cada 6 h.
  - El oráculo de la quinta acepta las dos formas de la salud, así que sigue valiendo en el #190.
  - Banco reducido 399/399 (pasadas 17 y 18, 15 mutantes). Commit `7fdfee5c`, sin aplicar.
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

# Llamadas desde el celular — F4-e: la migración de «la operación de hoy» preparada (2026-10-12)

Sesión de Jhosep del lunes 12/10/2026 por la tarde, desde su cuenta nueva de Claude. Sigue a
[[Llamadas desde el celular - F4.2.4 aceptada y macros de C1 exportadas (2026-10-12)]]. PR: #255 (solo SQL, pruebas y
estos documentos; nada aplicado). Tablero: cambios 232–240.

## Qué quedó hecho

- **La decimotercera migración de llamadas**, `20261012192500_crm_llamadas_celular_operacion_hoy.sql`: una puerta de
  SOLO LECTURA (`crm.llamadas_celular_operacion_hoy_fn`, definer, solo supervisor y gerencia) con su núcleo invoker en
  `private`. Devuelve, para hoy en Lima, las cifras de llamadas del celular por analista y por equipo, más la salud de
  los celulares, siguiendo al pie el contrato aprobado por Miguel (`F4E-CONTRATO.md`: D1–D5 el 10/10, sección 9 el
  12/10). Es la tarea **F6.3.1** del plan; la consumen la tercera pestaña de «Toda la operación hoy» (gerencia) y el
  bloque «Su celular» de «Mi equipo hoy» (supervisor), que van en otro PR.
- **Tres relojes, cada uno con su rótulo dentro de la respuesta:** llamadas de hoy por la hora de la llamada (si el
  reloj del celular va más de 5 min adelantado, manda la hora del servidor), repartidas en seis cubetas que suman el
  total (con resultado, deshechas sin corregir, sin resultado, ya no piden resultado, descartadas, por revisar);
  resultados de hoy por la fecha en que se registró la actividad, partidos por vía (al colgar, pestaña, a mano);
  pendientes como foto de ahora dentro de la retención, con las deshechas sin corregir aparte y sin tope.
- **Reglas del contrato que la consulta cumple y las pruebas demuestran:** cada llamada cuenta para quien marcó;
  los leads de baja no cuentan; un lead cerrado después pasa a «ya no piden resultado»; «sin dato» solo con 0 llamadas
  y ningún celular al día; el celular del supervisor va aparte y no suma al equipo; las cifras de un analista son las
  mismas las vea gerencia o su supervisor (regla D4), y las claves de equipo son las del pulso de Gestión Diaria.
- **Pruebas:** oráculo O1–O17 del contrato sobre el banco reducido (con un doble nuevo del roster del pulso),
  pasada 19 y 25 mutantes en `npm run test:llamadas:local`: **453/453 en verde** en la máquina de Jhosep. Reversa (drop
  exacto a la huella de las doce) y registrador generados. Bloque del gate `test-rls.mjs` escrito con la bandera
  `CRM_RLS_EXIGE_LLAMADAS_F4E` (sin correr: no hay base Supabase en esa máquina).
- **Revisión:** `auditor-rls` PASS sin cambios obligatorios y tres P3, los tres aplicados antes del commit (rol
  efectivo —equipo y perfil activos— para el ámbito del supervisor y el 22023 de gerencia; aserción de que el actor
  es el autenticado; precondición sin cast directo). Codex r1 no se corrió (no está instalado en esa máquina): el
  encargo quedó transcrito en `docs/encargos/2026-10-12-codex-f4e-operacion-hoy.md`.
- **Miguel fusionó el #254** (documentos) a las 20:41 UTC sin comentarios. H-BLANCO, #19 y #20 siguen sin decisión.

## Lo que le toca a Miguel (#255)

Su banco con historial acumulado → `EXPLAIN ANALYZE` del núcleo (objetivo < 100 ms, sin índice nuevo salvo que lo
pida) → gate con la bandera y advisors → aplicar → `registrar-operacion-hoy.sql` → `npm run gen:types`. Y confirmar
dos decisiones tomadas dentro del contrato: la retención de las pendientes sale de la política de llamadas (hoy 30
días) y no de un 30 fijo; ningún porcentaje viaja en el jsonb (la pantalla los calcula de cada par de la misma cohorte).

## Lecciones de trabajo

- Los ids de origen que acepta la v5 llevan la hora en epoch y tienen que ser recientes (ventana de 30 días hacia
  atrás y 1 hacia delante): en un oráculo no sirve un número fijo, se calculan desde `now()`.
- En este clon de Windows los `.sql` de llamadas deben pasarse a LF antes de `test:llamadas:local` (git no ve ningún
  cambio: solo finales de línea); antes de un `rebase` hay que restaurarlos, porque git sí los considera sucios.
- `/nueva-migracion` vive en `CRM-Avance-Corp/.claude/skills` y solo aparece cuando el cwd está dentro de esa carpeta.

## Cierre de la tarde: el #255 se fusionó (12/10, 22:27 UTC)

- **Miguel fusionó el #255** (squash `10e3411d` en `main`). Antes, su agente corrió Codex r1 sobre el encargo y subió
  a la rama la corrección de su único hallazgo (P2): el registrador ahora certifica el catálogo instalado con tres
  huellas (md5 del archivo y md5 de `pg_proc.prosrc` de la puerta y del núcleo) y rechaza cuerpos vacíos, accesos de
  más y permisos de menos. Verificado en la máquina de Jhosep: `test:llamadas:local` **466/466**. La migración no cambió.
- **Build nueva en producción a las 22:43 UTC** (`build-20261012T224322167Z`, de Miguel): el bundle vivo conserva
  «Unir a un resultado guardado» (F4.2.4). F4-e no tiene pantalla todavía, así que nada visible cambió.
- **Fusionar no es aplicar.** La migración sigue **sin aplicar**: el ledger en `main` dice «PREPARADA, SIN APLICAR»,
  `database.types.ts` no trae `llamadas_celular_operacion_hoy_fn` y Miguel no comentó. Sigue en su turno: banco,
  `EXPLAIN`, gate, aplicar, registrador, `gen:types`, las dos decisiones y su opinión sobre la propuesta #21
  (cierre en lote). No se da por aplicado nada sin esas huellas.
- La pantalla de F4-e (tercera pestaña de gerencia y bloque «Su celular») va en un PR aparte desde `main`, con plan
  corto y OK de Jhosep; puede empezar en demo aunque Miguel no haya aplicado, porque sus dos decisiones no cambian la
  forma del jsonb.
- Tablero: cambios 232–245. Handoff local: `_DEV_NO_SUBIR/HANDOFF-2026-10-12-tarde.md`.
- Lección extra: el registrador fija tres huellas; si la migración cambia antes de aplicarse hay que regenerarlas en
  LF y repetir el banco. Si ya se aplicó, cualquier cambio va en una migración nueva.

## La pantalla (13/10/2026, PR #261)

Sesión de Jhosep del martes 13/10 por la mañana (cuenta jhosep@). Al arrancar, Miguel no había aplicado la migración
ni respondido las dos decisiones ni la #21 (sin comentarios en el #255; `origin/main` solo traía el #258 y luego su
#259). Jhosep dio el OK a hacer la pantalla **en demo** (sus dos decisiones no cambian la forma del jsonb) y a que el
commit de documentos del cierre viajara en el mismo PR (`main` está protegida: el push directo lo rechaza GitHub).

- **Lo que entró (rama `crm/llamadas-f4e-pantalla-20261013`, asentada sobre el #259):**
  - `lib/llamadas-celular-operacion.ts`: el espejo del jsonb de §6 con **comprobaciones de suma** (las seis cubetas suman
    el total; equipos y totales = suma de sus analistas; `sin_dato` sigue D1) y lo que la pantalla deriva (porcentajes
    de cada par de la misma cohorte, filas por equipo, filtros, motivos de atención, detalles).
  - `lib/llamadas-celular-operacion-demo.ts`: la misma forma con el organigrama del store (d-sup1 → d-v1 C1 al día,
    d-v2 C2 sin latido con 3 en cola; d-sup2 → d-v3 C3 nunca habló = sin dato; su_celular C4 para d-sup1), pasando
    por el mismo esquema.
  - Tipo `llamadas_celular_operacion_hoy_fn` a mano en `database.types.ts`; llamada en `data/llamadas-celular-api.ts`;
    hook `useOperacionCelularHoy` (refresco 60 s, solo supervisor/gerencia, solo hoy).
  - Gerencia: tercera pestaña «Llamadas del celular» (`components/gestion-diaria/llamadas-celular-gerencia.tsx`):
    tabla por equipo + ficha con cuadros, «Necesitan atención» y los tres rótulos. Con otro día elegido: aviso y «Ver hoy».
  - Supervisor: bloque «Su celular» (`su-celular-analista.tsx`) entre la línea del día y los cuadros del resumen
    (`ResumenAnalista` ganó el hueco `antesDeCuadros`), y el celular del supervisor al pie de la tabla (A7).
- **Verificación:** typecheck, lint, suite completa 6659/6660 (la fallida pasa sola: CPU), E2E Docker en demo
  (`llamadas-celular-operacion.spec.ts`), `revisor-a11y` (1 P1 + 4 P2 + 3 P3, todos aplicados), navegador en demo con
  los dos roles. NOT RUN: `gate:realidad` (clave de servicio) y producción (puerta sin aplicar).
- **Decisiones de pantalla (ninguna toca el contrato):** sin listas por analista desde gerencia ni desde «Su celular»
  (no hay puerta; F6); «sin latido» cuenta también a los que nunca hablaron; en la tabla la antigüedad de la pendiente
  más vieja va en la ficha; el botón que alternaba columnas en la tabla del supervisor (prototipo, pantalla 2) queda
  fuera: el plan corto solo pedía el bloque.
- **Lecciones:** en este clon Windows el E2E en Docker se ahoga si corre a la vez que la suite unitaria completa
  (timeouts de 30 s en `page.goto`): correrlos por turnos. Docker Desktop vive en
  `%LOCALAPPDATA%\Programs\DockerDesktop` (no en Program Files). El tablero/`main` protegida: todo entra por PR.


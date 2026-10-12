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

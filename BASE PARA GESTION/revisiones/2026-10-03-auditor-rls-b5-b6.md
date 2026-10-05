# auditor-rls sobre B5 + B6 (primera versión) — 03/10/2026

**Veredicto:** CHANGES_REQUESTED. En seguridad y RLS estaban bien: definer con `search_path` vacío, dueño `postgres`, EXECUTE
solo para authenticated, ayudante sin EXECUTE para la API, sin fuga de PII nueva, nada en `public` y bundle viejo
compatible. Pidió cambios por el censo analítico y por una vía que saltaba la regla.

| # | Hallazgo | Verificación del PRIMARY | Resolución |
|---|---|---|---|
| P1 | B6 cambiaba el cuerpo de `crm.rescatar_descartes`, declarada en el censo analítico con su huella (clase 'operativo') → «EXENCIÓN CADUCADA», alerta diaria, `gate:analitica` en rojo. El banco de solo esquema no puede verlo (exenciones vacías). | Confirmado en producción: `huella_ok = true` hoy. | B6 ya **no toca** `rescatar_descartes`: la regla pasa a un trigger en el lead. |
| P1 (hipótesis) | El censo ya caía desde B3/B4: `obtener_base_gestion`, `base_gestion_resumen`, `base_gestion_intento_core` y `trg_actividades_enfriamiento_base` sin declarar. | **Confirmado** en producción: alerta f6a abierta el 03/10 06:49 con esas 4 (+ `gestion_diaria_cola_hechos`, de otra sesión, desde el 01/10). | Migración nueva **B3c**: los conteos salen del alcance (doctrina del censo); OK de Miguel. |
| P2 | La regla se saltaba reasignando desde la ficha (PATCH de `vendedor_id`). | **Confirmado** en el banco: S1 movió LA (en gestión) a B. Además «tomar lead libre» se lleva un descartado ajeno. | Candado en el lead (trigger BEFORE UPDATE): Miguel eligió «toda vía». Probado: rescate, ficha y tomar lead libre → P0409. |
| P2 | Faltan casos de B5/B6 en `test-rls.mjs`. | Cierto. | Pendiente para el gate (después de Codex). |
| P3 | `en_gestion_por` usa el dueño actual y el ámbito va por el analista del episodio. | Con el candado, un descartado en gestión ya no cambia de dueño. | Mitigado. |
| P3 | (a) un intento del propio supervisor bloquea su reparto; (b) una rellamada de un ciclo anterior marca «en gestión»; (c) `rescate_descartes_meses` cuenta los grises como pendientes. | — | (a) aceptado como regla; (b) **corregido**: la rellamada solo cuenta con un intento del ciclo vigente; (c) aceptado (está declarada en el censo: no se toca). |
| P3 | Postflights y reversas por fragmentos. | Cierto. | md5 de cada cuerpo nuevo, ACL exacta, guardas `is not true`; las reversas exigen el cuerpo de su migración antes de pisar. |
| P3 | Trazabilidad: el cuerpo vivo de `rescate_descartes_mes` no sale de ninguna migración del repo; faltaban registradores y `gen:types`. | Cierto. | Anotado en el ledger; registradores generados y probados; `gen:types` tras aplicar. |

Evidencia del banco tras los cambios: B2 25/25, B3 48/48, B4 17/17, B6 29/29; mutantes (ayudante que cuenta de más, regla
siempre NULL, trigger deshabilitado) → FALLAN; cadena de reversas B6 → B5 → B3c → huellas de producción.

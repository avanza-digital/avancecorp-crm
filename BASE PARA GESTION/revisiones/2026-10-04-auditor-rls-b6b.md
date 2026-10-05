# auditor-rls · B6b (03–04/10)

- **1.ª pasada: CHANGES_REQUESTED** (sin P0/P1). P2a marca desfasada entre leads de la misma persona (marcar/levantar
  escriben la actividad solo en `p_lead_id`); P2b nota del veto falsificable vía `actividades_insert` (→ B6c, decisión de
  Miguel); P3 motivo de postventa, casos del gate (miembro desactivado, bandeja, retirado en reactivaciones), comentarios.
- **2.ª pasada (r1): PASS** con P3: quitar la holgura de postventa (en la vía real el trigger sella con
  `clock_timestamp()`), tercer paso DNI en la persona, documentar el caso que fallaba a NULL.
- **3.ª pasada (r2): PASS**, sin P0/P1/P2. Verificado con archivo:línea: persona = enlace → puente canónico → DNI, igual que
  marcar (`20260910150039:855-872`) y levantar (`20261002061500:103-120`); conjunto `{propio} ∪
  private.leads_de_persona_veto(persona)` igual que marcar (:904), levantar (:152) y postventa (:477); orden fiable por
  `clock_timestamp()` (`20260904130000:1095`); filtro de visibilidad sin fuga; «última por lead y luego la más reciente» ≡
  «la última del conjunto»; el andamio de la suite (`cartera_f5_exigir`) vive entre `begin` y `rollback`.
  P3 abiertos (no bloquean): el postflight no ejecuta el camino `true` (cubierto por la rama con datos); la función no
  lee la bandera `resolver_en_puertas` (documentar en B6c); guarda de «solo banco local» en la suite (con B6c).

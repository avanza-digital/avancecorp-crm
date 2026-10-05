# auditor-rls · B2 (20261002061500_crm_base_gestion_no_contactar_supervisor.sql) — 02/10/2026

**VERDICT: CHANGES_REQUESTED** (solo por la matriz de pruebas; el SQL no tiene P0/P1). **APLICADO el 02/10 (noche):** P2 → fixtures de persona real + b2-rls estricto 25/25; P3 activo → añadido; P3 reversa → guarda + contrato/ACL; P3 orden → aceptado como canal lateral menor y documentado en la cabecera.

## Resumen del auditor
Gate de rol, ámbito previo y revalidación bajo candado correctos; ninguna vía por la que Supervisión escriba fuera de
`v_leads` ni de su subárbol. `vendedor_ids_visibles(v_uid)` dentro de la DEFINER funciona (auth.uid() no cambia con DEFINER).
Candados tomados antes del 42501 se liberan al abortar (impacto nulo). ACL y contrato OK; no re-sella nada (la única
aparición en verificaciones es la lista blanca de D-19, un `do` de un disparo). Postflight sin residuo. Reversa coincide
línea a línea con 20260906160000:278-434 (md5 NOT RUN por el auditor; la reversa se autoverifica).

## Hallazgos
- **[P2] La regla central «todos los leads de la persona en tu equipo → 42501» no tiene ninguna prueba efectiva.**
  `b2-rls.sql:46` acepta «ok o 42501»; `fixtures-b2.sql` crea LA_VETO y LD con el mismo DNI pero sin `crm.inversionistas`
  ni `inversionista_identificadores` (`inversionista_por_documento` exige identificador vigente y `verificado = true`) →
  `v_inv` NULL → `v_leads = [p_lead_id]` → la rama no se ejecuta. En `test-rls.mjs` no hay caso de dos equipos.
  **Hacer:** (1) fixtures con persona real (inversionista + identificador DNI 70000104 vigente/verificado, LA_VETO
  enlazada, LD suelto con el mismo DNI); `b2-rls.sql` exigiendo `42501` + «pídelo a Gerencia»; añadir «G levanta LA_VETO →
  ok y LD queda sin veto» y «S1 levanta LA (persona solo en equipo 1) → ok». (2) `test-rls.mjs`: caso fuera de banda de
  persona con leads en dos equipos (segundo lead descartado para esquivar el índice único de DNI vivo): sup1 → 42501
  /pídelo a Gerencia/, gerencia → ok. (3) Negativos de `directorio` y `clientBank` sobre `levantar`; paridad con bandera
  APAGADA incluyendo Supervisión.
- **[P3] El «espejo de leads_select» omite `activo = true`** (migración 81-87 y 176-180): un supervisor podría levantar
  por el UUID de un lead borrado (soft-delete) de su subárbol. Añadir `l.activo` / `v_lead.activo` a las dos comprobaciones
  del lead pedido (no a la de `v_leads`) y recalcular el md5 del postflight, o documentar la desviación.
- **[P3] Canales laterales menores por el orden** (40001 NOWAIT y 22023 motivo-documento corren antes del «todos en tu
  equipo»). Opcional: comprobar el ámbito de `v_leads` justo tras calcularlo (148) como fail-fast adicional.
- **[P3] La reversa verifica md5 pero no ACL ni que pisa B2.** Añadir preflight `md5(prosrc) = 2467b5068fc814ce42f18596d740ebcb`
  y replicar dueño/proconfig/aclexplode en el post-check.

## Test gaps
Dos equipos (P2) · directorio/clientBank sobre levantar · Supervisión con bandera apagada y sobre lead parqueado en su
subárbol (`vendedor_id is null and asignado_supervisor_id`) · md5 reales NOT RUN por el auditor.

## Riesgo señalado
El veto es por persona: al levantarlo Supervisión limpia también `crm.inversionistas.no_contactar` (afecta a
`persona_vetada_perfil` y a la herencia de leads futuros). Es D5, gateado por «todos los leads en tu equipo»: dejarlo
explícito en vault y ledger.

## Confianza
HIGH en la lógica; MEDIUM en lo que depende de ejecución.

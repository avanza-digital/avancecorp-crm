# F3 (Contrato-F2 «puertas canónicas») — diseño v3, fiel al Contrato F0

**Historia:** v1 (trigger único) y v2 («5 capas» improvisadas) → NO-GO de Codex. v3 implementa
el **Contrato arquitectónico consolidado F0** al pie de la letra e incorpora los **7 arreglos
concretos** del 3.er refute de Codex. Confirmado GO por Codex: el **split F2/F3** y el **fix del
resolver**. Este doc resuelve lo que faltaba.

**Spec:** `Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0
2026-08-31).md`; `Catalogo de puertas de escritura - identidad e inversiones (F0, 2026-09-03).md`.

## DECISIONES CONFIRMADAS por Miguel (03/09, tras el 4.º refute de Codex)
1. **UN SOLO LEAD TOTAL por persona** (invariante #6: vivos + convertidos + descartados). El §532
   del contrato («varios leads») queda como frase suelta a corregir; manda el invariante #6.
2. **Seguir el PHASING del contrato**, no el big-bang. Este paso = **Contrato-F2 (puertas),
   CONSERVANDO `UNIQUE(lead_id)`**. Se DIFIERE: «N inversiones por persona» → **F5** (con su
   reescritura de anulación/ajuste/estado que hoy son por-lead); métrica por inversionista/mes →
   **F3** (con delta medido). Así este paso NO toca cifras selladas.

### Correcciones del 4.º refute incorporadas
- **NO** se suelta `UNIQUE(lead_id)` (Codex #1: `cierre_anulado`, ajuste ATR-4 y `cierres_estado_fn`
  son por-lead; soltarlo sin reescribirlos rompe la anulación y el conteo). Se conserva hasta F5.
- **Carrera por alias (Codex #3):** tras resolver, `SELECT ... FOR UPDATE` de la fila
  `crm.inversionistas` **antes** de perfil/lead, para serializar por identidad (no solo por
  documento) y que dos documentos vigentes de la misma persona no revienten.
- **Idempotencia OBLIGATORIA (Codex #5), no condicional:** cablear `crm.multiempresa_idempotencia`
  (clave+hash+resultado) en ambas conversiones; el reintento post-commit hoy da «lead ya cerrado»/409.
- **`no_contactar` por RPC ordenada (Codex #4):** subir/bajar por RPC que bloquea identidad→leads;
  el trigger solo RECHAZA escrituras directas no autorizadas; la importación usa la misma puerta.
- **Retirar el trigger-only WIP** `20260903200000` (Codex #2): el resolver va DENTRO de las puertas.

---

## 0. La decisión de esquema (centro de v3) — cierres/inversiones cuelgan de la IDENTIDAD

**Problema (Codex fix #2):** el contrato exige «un solo lead por persona» (invariante #6) Y «dos
inversiones legítimas no se bloquean» (§8.3). Hoy `crm.cierres_externos` tiene
`constraint cierres_externos_un_cierre_por_lead unique (lead_id)` → un cierre por lead → con un
lead por persona, **la 2.ª inversión cooperativa no tiene dónde escribirse**.

**Hallazgo:** `crm.inversiones` **YA** cuelga de la identidad (`inversionista_id not null`, fuente
= cierre XOR contrato). Y el anti-doble-depósito real NO es ese UNIQUE: son
`ux_cierres_externos_transaccion` (número de operación único) + `crm.depositos_reclamados`
(`numero_norm unique`). El `unique(lead_id)` solo impedía dos cierres del **mismo** lead — que es
justo lo que ahora queremos permitir.

**Decisión (revisada tras el 4.º refute + Miguel):** **NO se suelta `UNIQUE(lead_id)` en este
paso.** Codex probó que tres consumidores son por-lead (`private.cierre_anulado`, el ajuste ATR-4
con `ON CONFLICT (lead_id)`, y `cierres_estado_fn`); soltar el constraint sin reescribirlos
rompería la anulación y el conteo. Por tanto:
- **Contrato-F2 (este paso):** una persona = un lead = su **primera** conversión (Avance o coop).
  Se conserva `UNIQUE(lead_id)`. Los 5 invariantes de concurrencia se cumplen para el modelo un-lead.
- **Contrato-F5 (después):** «N inversiones por persona» → ahí se suelta `UNIQUE(lead_id)` JUNTO con
  la migración de anulación/ajuste/estado a semántica por `cierre_id`/`inversion_id`, + índice no
  único por `lead_id`. No antes.

La primera conversión de una persona que ya tiene lead canónico (carrera por alias) se resuelve
serializando por identidad (`inversionistas FOR UPDATE`, §2), no demoviendo leads.

---

## 1. Orden total de locks (Codex fix #1) — idéntico en TODAS las puertas

Toda puerta (conversión Avance, conversión coop, fusión, corrección, reasignación) sigue esta
secuencia, y **revalida su estado tras esperar cada lock**:

```
1. validación pura (sin escritura; payload, formato de documento, autorización)
2. lock documental ordenado  → pg_advisory_xact_lock(hashtext(tipo||documento))   [identidad]
3. resolver/leer identidad(es), en orden de id ascendente si son varias           [identidad]
4. perfil (si aplica)
5. lead(s) FOR UPDATE, en orden de id ascendente                                  [lead]
6. conversion_reservas FOR UPDATE                                                  [reserva]
7. hechos: cierre / contrato / inversión / titular
8. UPDATE de crm.leads (etapa, perfil_id, inversionista_id) BAJO la válvula op_privilegiada
```

**Clave anti-deadlock:** el lock documental (paso 2) se toma **ANTES** del `FOR UPDATE` del lead
(paso 5). Hoy `convertir_lead`/`_externo` bloquean el lead primero; se **reordena** para tomar el
advisory documental primero. Como el documento se conoce desde el inicio (perfil en Avance;
parámetro en coop), es posible. Así conversión y fusión comparten el orden **identidad→lead** y el
ciclo que Codex marcó desaparece. `lead→reserva` se conserva (paso 5 antes de 6).

---

## 2. Conversión Avance — `crm.convertir_lead` (§8.2)

Dentro de la MISMA función/transacción, tras autorización y validación:
1. obtener `tipo_documento` + `dni` del perfil (`p_perfil_id`). **Codex #1b:** hoy la función solo
   lee `dni`; se añade leer `tipo_documento` (perfiles lo tiene) para llamar al resolver con firma
   completa `(tipo, documento)`.
2. `pg_advisory_xact_lock(hashtext(tipo||doc))` (paso 2 del orden).
3. resolver identidad: **si el perfil ya tiene identidad** (`crm.inversionistas.perfil_id=p_perfil_id
   AND estado<>'fusionado'`), reusarla; **si esa identidad está fusionada, seguir
   `inversionista_canonico_id`** (Codex #1); si no hay, `private.inversionista_resolver(tipo,doc,true,'conversion')`.
4. vincular perfil↔identidad si aún no está.
5. `FOR UPDATE` del lead (ya existente), revalidar etapa.
6. UPDATE bajo válvula: `etapa='convertido', perfil_id, convertido_en, inversionista_id=<identidad>`
   **en el MISMO UPDATE** (Codex #3: fuera del bloque con válvula el trigger #4 restauraría NULL).
7. **un solo lead total (invariante #6, decisión Miguel 03/09):** si la identidad ya tiene otro
   lead, convertir un segundo se **RECHAZA (P0409)** con mensaje de negocio — la nueva inversión
   sobre el cliente existente es **F5**, no una nueva conversión. (El lenguaje previo de «demover a
   histórico» queda anulado por la decisión de un-solo-lead.)
8. **fail-closed** (contrato §4.3): con bandera encendida, si no hay documento resoluble → raise de
   negocio. La edge ya exige documento; **la RPC directa `authenticated` hoy acepta perfil sin DNI**
   → el gate previo es un **inventario de consumidores directos** de la RPC (Codex #3), no «cero
   leads sin documento». Correo del Portal: **se conserva** el envío solo tras confirmar servidor
   (invariante + prueba de regresión — Codex #1).

## 3. Conversión cooperativa — `crm.convertir_lead_externo` (§8.3)

1. validación (ya valida DNI/CE/PASAPORTE); `advisory_xact_lock` documental (paso 2) **antes** del
   `FOR UPDATE` del lead.
2. resolver identidad dentro de la transacción.
3. tras resolver, `inversionistas FOR UPDATE` (serializa por identidad) → `FOR UPDATE` lead →
   `FOR UPDATE` reserva (orden conservado) → **un-solo-lead:** si la identidad ya tiene otro lead,
   RECHAZAR (P0409) — no se demueve nada; **se CONSERVA `unique(lead_id)`** (N inversiones = F5).
4. insertar cierre → insertar `inversión` (colgada de identidad, `es_primera_conversion` calculado
   = NOT EXISTS inversión previa del inversionista) → titular → UPDATE etapa bajo válvula fijando
   `inversionista_id`; replicar responsable (vendedor) + `no_contactar` (como el trigger 200000).
5. la reserva por `lead_id` se conserva (anti Avance/coop del mismo lead).

## 4. `no_contactar` monotónico y autoritativo (Codex fix #4, §7.3)

- **Subir a `true`:** cualquier lead vinculado puede elevarlo; se propaga a `crm.inversionistas` y
  a todos sus leads.
- **Bajar a `false`:** PROHIBIDO por UPDATE directo (trigger que rechaza el `true→false` en
  `crm.leads.no_contactar` salvo válvula de la puerta de Gerencia); solo la **puerta auditada de
  Gerencia** con motivo lo levanta, bloqueando identidad+leads y revalidando antes del commit.
- Todas las rutas que hoy leen solo `leads.no_contactar` — disponibilidad (`lead_libre_f2_tomar`),
  **reparto** (`reparto_coordinador_c1`), **rescate** (`centro_rescate_descartes`), seguimiento —
  pasan a consultar también `inversionistas.no_contactar`.

## 5. Fusión y corrección auditadas (Codex fix #5, §4.4)

**Fusión** (solo Gerencia): (1) genera **token/hash de previsualización**; (2) al ejecutar,
bloquea ambas identidades **por id ascendente**, **revalida que el hash coincide** con el estado
actual (si cambió, aborta); (3) elige canónica; (4) resuelve colisiones explícitas — un solo
perfil, un solo responsable de relación, `no_contactar := OR` de ambas, un solo lead canónico (el
otro pasa a histórico), identificadores vigentes trasladados/reemitidos hacia la canónica; (5)
conserva cierres/contratos/snapshots; (6) fila append-only en `crm.inversionista_fusiones`;
(7) `estado='fusionado'` + `inversionista_canonico_id` en la perdedora, nunca DELETE; (8) nunca
reescribe mes sellado. **El identificador vigente se reapunta a la canónica** para que el resolver
(con el fix del handler) devuelva la canónica y no falle (Codex #4/#5).
**Corrección de documento:** cambia la **vigencia** del identificador por puerta auditada; NO
reescribe cierres/contratos/titulares; realinea `leads.inversionista_id` bajo válvula; usa el
orden total de locks; trigger nombrado `trg_*` con timing definido.

## 6. Fix del bug del resolver (Codex fix #6, GO)
En `private.inversionista_resolver`, la rama `unique_violation` (F1:442-457) **copia literalmente
el SELECT de la rama normal** (con JOIN a `crm.inversionistas`, exigiendo `estado='vigente'`,
`verificado=true`, `inv.estado<>'fusionado'`); si no hay ganadora válida, conserva el error
higienizado. Migración mínima aparte.

## 7. Inventario COMPLETO de puertas F2 (Codex fix #3, §16-F2)
Adaptar / verificar cada escritor de identidad e inversión del catálogo:
`crear_lead_si_disponible` (alta atómica), toma/importación de leads, `convertir_lead`,
`convertir_lead_externo`, wrapper `convertir_lead_con_domicilio`, `public.crear_contrato` (cuando
deba verificar identidad), vinculación de perfil, puerta de reasignación de responsable, y las
vías **Portal/edge** que crean perfil/Auth (`crm-convertir-lead`, `crear-cliente`). Cada una: o
resuelve identidad por la primitiva, o no crea persona/lead fuera del punto único.

## 8. Banco / oráculos (Codex fix #7)
Exigir, con dos sesiones concurrentes en transacción (NO `psql -c` autocommit) y togglando
`resolver_en_puertas` de verdad:
- 1 identidad + 1 lead canónico + **N hechos económicos PRESERVADOS** (contar inversiones, no solo
  identidad/lead);
- cero Auth/perfil/correo en el camino cooperativo;
- reintento → mismo resultado (idempotencia §8.2: resolver idempotente + dedup por documento; si el
  ensayo muestra que no basta, cablear `crm.multiempresa_idempotencia`);
- **sin deadlocks** en conversión↔fusión, conversión↔corrección, alta↔`no_contactar`.

## 9. Reversa
Restaurar versiones previas de las funciones tocadas; **recrear** `cierres_externos_un_cierre_por_lead`
solo si no hay ya N cierres por lead (si los hay, la reversa documenta que ese constraint no vuelve);
soltar puertas nuevas; apagar `resolver_en_puertas`. No borra identidades ni hechos. `pg_trigger`
por `(tgname, tgrelid)`. Repetible dos veces.

## 10. Fuera de este paso
Contrato-F3 (métrica por inversionista/mes §9 + capital por empresa §10, con **delta medido** y
meses sellados intactos) y la **puerta F5** de nueva-inversión-sobre-cliente-existente.

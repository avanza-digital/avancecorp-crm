# Cuentas de pago — F6: lista de Operaciones y decisiones (2026-10-02)

**Estado: ENTREGADA A OPERACIONES el 02/10/2026 (~11:30 Lima).** Continuación de
[[Cuentas de pago - motivo del bloqueo, rezago y Asignar cuenta (2026-10-01)]] (serial
`AVC-CUENTAS-PAGO-20261002-R1`, Fases 1–5 cerradas ese mismo día). F6 es trabajo de personas: cada contrato
sale de la lista cuando administración le asigna su cuenta en Pagos.

## Decisiones de Miguel (02/10/2026, ~11:05)

1. **Botón en la agenda de Pagos:** «Asignar cuenta» **reemplaza** al «Marcar pagado» apagado en la fila
   bloqueada (una sola acción visible, la fila no crece). Los demás roles siguen viendo el botón apagado.
   Hecho en el portal (`pagos.js v47`, SW v139; tests 185/185); publicación por kit, archivo por archivo.
2. **`2026-01-444444` (demo, sin cuenta):** se deja como está y se marca como demostración en la lista; sirve
   para probar «Asignar cuenta» en producción sin tocar clientes. Igual `2026-01-000009` (demo, otra moneda).
3. **Negativa de modo de transacción para «Retirar cuenta» y «Cambiar cuenta de pago»:** sí, en migración
   aparte, **después** de entregar F6 (nivel 3: plan corto, auditor-rls, Codex, banco y ensayo).
4. **Entrega de F6:** lista de trabajo en Excel para Gloria + esta nota.

## La lista (censo de producción, 02/10/2026 11:16 Lima)

Archivo: `_DEV_NO_SUBIR/cuentas-pago-f6/Lista-Operaciones-cuentas-de-pago-2026-10-02.xlsx` (fuera de git:
lleva nombre, teléfono y correo del cliente). Tres hojas: la lista (columnas amarillas para Operaciones:
Hecho / Fecha / Notas), «Resumen» con fórmulas que se recalculan al marcar «Hecho», y «Cómo usar».
Se generó con `CRM-Avance-Corp/supabase/scripts/cuentas-pago-rezago/lista-operaciones.sql` (solo lectura, misma
clasificación que `censo-sin-funciones.sql`, más cliente y vencidos): para otro censo, `supabase db query --linked
--file` sobre ese archivo y volver a generar el Excel; no toca funciones.

22 contratos (20 reales + 2 demo), ordenados por urgencia:

| Prioridad | Contratos | Qué pasa |
|---|---|---|
| 1 · cuota vencida (8 reales) | 000644 (USD, otra moneda) · 000856 (PEN, sin cuenta) · 000858 (PEN, dos cuentas) · 000859 (USD, otra moneda) · 001325 (USD, otra moneda) · 000477 (PEN, sin cuenta) · 000734 (PEN, dos cuentas) · 000900 (PEN, dos cuentas) | Vencido: S/ 3.248,75 y US$ 541,67 en total |
| 2 · vence en octubre (10) | 000915 · 000762 · 000983 · 000793 · 001010 · 000797 · 001031 · 001039 · 001042 · 001064 | Hay tiempo de pedir o confirmar la cuenta antes de la cuota |
| 3 · más adelante (2) | 000753 (06/2028) · 000964 (07/2031) | Sin prisa; se gestionan igual |
| Demo (2) | 444444 · 000009 | No se gestionan |

Por caso (reales): 7 con dos cuentas en la moneda (confirmar con el cliente cuál), 11 con cuenta solo en la
otra moneda (pedir una en la moneda del contrato), 2 sin ninguna cuenta (pedir una).

## Dónde estaba la cuenta «perdida» (investigación 02/10 ~17:00–18:30)

Miguel preguntó por BERNUY MONTES GIANINA (`000477`, `000856`): se le pagaron 6 cuotas (mayo–agosto) y en el portal no
tiene cuenta. Tres agentes (archivos, base solo lectura, vault) + Gmail/Drive: **no se perdió nada en la base, nunca se
capturó**. `000477` es el PRIMER contrato de toda la plataforma (22/05/2026, cuatro días antes del importador de clientes
con datos bancarios obligatorios); el 2.º cliente (23/05) también nació sin cuenta; del 3.º en adelante los perfiles ya
traían cuenta. Bitácora completa del perfil (8 cambios desde 05/06) con los campos bancarios vacíos antes y después, cero
filas en cualquier tabla/jsonb/storage/auth con datos bancarios suyos, y P-0XX (26/09) ya la listaba como `sin_cuenta`.
Las cuotas se marcaron pagadas cuando el sistema aún no exigía cuenta (hasta el 25/09). **La cuenta vivía fuera del
sistema:** la hoja mensual de Operaciones «Contratos Junio 2026.xlsx» (correo de Miguel del 13/07/2026 a
avancecorp26; copia en `~/Downloads`), columnas CUENTA · CCI · BANCO. Esa hoja resuelve **8 de los 22** bloqueados
(000856 Pichincha soles; 000734/000793 BBVA y 000858 Falabella, que deshacen la duda de «dos cuentas»; 000753, 000762,
000797, 000859 con su cuenta en la otra moneda). El Excel de Operaciones lleva ahora esas columnas (azules) con la fuente.
**Faltan las hojas de mayo, julio, agosto y septiembre** (no están en el Gmail ni en el Drive de miguel@miavance.com):
con ellas se resolvería el resto (000477 está en la de mayo).

## Qué hace Operaciones por caso

- **Dos cuentas:** llamar al cliente, confirmar en cuál cobra ESTE contrato, y en Pagos → fila del contrato →
  «Asignar cuenta» (elegir la cuenta, motivo «confirmado con el cliente el dd/mm»). La lista dice banco,
  origen (contrato / perfil / portal), fecha y cuántos contratos ya cobran en cada una, sin números.
- **Otra moneda / sin cuenta:** pedir la cuenta, registrarla en Clientes → Cuentas (misma moneda del
  contrato) y después «Asignar cuenta». La asignación no avisa al cliente ni registra pagos.
- Si se asigna mal: «Cambiar cuenta de pago» (con correo del cliente). No hay deshacer.

## GitHub

PR #168 fusionada en squash el 02/10 (~12:35): `main` de GitHub `251f2b21`, mismo árbol que la rama
`crm/cuentas-pago-rezago-20261001`. El `main` LOCAL del taller sigue en `759aa310` hasta que las otras sesiones
commiteen su trabajo (entonces: `git merge --ff-only crm/cuentas-pago-rezago-20261001`).

## Qué queda

- ✅ Portal publicado 02/10 ~11:40 (`f69e190`, `pagos.js v47`, SW v139): 9/9 lecturas idénticas, `pagos.html` pide v47;
  bitácora en `public_html/CLAUDE.md`; `main` del portal en `4fb7c37`.
- ✅ Migración `20261002163158_crm_retirar_y_cambiar_cuenta_solo_read_committed` **EN PRODUCCIÓN 02/10 ~12:20**
  (Miguel con `!`: `RETIRAR_CAMBIAR_SOLO_READ_COMMITTED_OK` + registrador). Banco 25/26 (el ✗ es
  `test-cambio-cuenta-pago` en su `dry_run`, idéntico sin la migración); Codex r1 y auditor-rls APPROVE_WITH_NITS,
  nits aplicados. Guía: `CRM-Avance-Corp/supabase/scripts/cuentas-pago-negativa/LEEME.md`.
- Cuando Operaciones termine: nuevo censo (`censo.sql`) y cerrar esta nota.

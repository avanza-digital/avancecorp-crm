# Cuentas de pago — motivo del bloqueo, rezago y «Asignar cuenta» (2026-10-01)

**Estado: CONSTRUIDO, REVISADO Y PROBADO EN LOCAL. NADA APLICADO EN PRODUCCIÓN NI PUBLICADO.**
Lo lanza Miguel con `!` (ver «Cómo publicar»). Continuación de [[Cuentas bancarias por contrato]],
[[P-0XX - cierre productivo verificado (2026-09-26)]] y
[[Cuentas de Gloria - F3 cambiar la cuenta de pago, en producción (2026-09-26)]].

## El problema

Una cuota solo se puede marcar «pagado» si su contrato tiene una **cuenta de pago** vinculada
(`crm.contrato_cuentas_pago`), del mismo cliente y de la misma moneda. Quedaron 23 contratos viejos
sin ese vínculo y la pantalla decía siempre lo mismo: «Sin cuenta de pago — requiere conciliación».
Nadie sabía qué faltaba en cada uno, y no existía ninguna forma de vincular un contrato ya creado.

## Censo real (01/10/2026 18:24 Lima, lo lanzó Miguel)

705 contratos:

| Caso | Qué significa | Cuántos |
|---|---|---|
| `ok` | Se puede pagar | 682 |
| `una_cuenta` | Sin vínculo; el cliente tiene UNA cuenta activa en esa moneda | 1 (`2026-01-001086`) |
| `varias_cuentas` | Sin vínculo; tiene dos: nadie sabe en cuál cobra | 7 |
| `otra_moneda` | Sin vínculo; solo tiene cuenta en la otra moneda | 12 |
| `sin_cuenta` | Sin vínculo; no tiene ninguna cuenta vigente | 3 |

Ojo: el encargo original hablaba de 8 contratos «con cuenta disponible». **7 de esos 8 tienen DOS
cuentas**: vincularlos solos era elegir por el cliente. Nueve contratos reales ya tienen una cuota
vencida que no se puede pagar (001086, 000734, 000858, 000900, 000644, 000859, 001325, 000477, 000856).

## Qué se construyó (tres piezas)

1. **El bloqueo dice por qué** — migración `20261001233019_crm_cuentas_pago_motivo_y_rezago.sql`.
   Una sola regla (`private.cuenta_pago_diagnostico`) clasifica cada contrato y redacta el motivo.
   El bloqueo sigue igual de estricto (mismo código 23514, sin atajos); solo cambia el texto, y el
   detalle solo se le dice a quien puede registrar pagos. La **carga** vincula únicamente donde el
   cliente tiene exactamente una cuenta activa en la moneda: hoy, 1 contrato (001086).
2. **«Asignar cuenta»** — migración `20261002005004_crm_asignar_cuenta_pago.sql`. Decisión de Miguel
   (01/10): «solo quiero que pueda marcar los pagos» y «no hace falta correo, solo motivo». Solo
   admin y superadmin; solo contratos abiertos SIN cuenta de pago; solo cuentas vigentes del mismo
   cliente y moneda; motivo obligatorio (5 a 500 caracteres); sin adjunto; no avisa al cliente.
   Deja constancia inmutable (quién, cuándo, qué cuenta y por qué) en
   `crm.contrato_cuenta_pago_asignaciones`.
3. **Portal (Pagos)** — la fila bloqueada muestra una etiqueta corta con el caso y, para
   administración, el botón «Asignar cuenta» con su ventana.

## Textos exactos

Del servidor (a quien puede registrar pagos; nunca llevan número de cuenta, CCI ni documentos):

- `Contrato N sin cuenta de pago: el cliente ya tiene una cuenta en soles; falta vincularla a este contrato.`
- `Contrato N sin cuenta de pago: el cliente tiene 2 cuentas en soles; confirma con él en cuál cobra este contrato.`
- `Contrato N sin cuenta de pago: el contrato es en dólares y el cliente solo tiene cuenta en soles; pídele una en dólares.`
- `Contrato N sin cuenta de pago: el cliente no tiene ninguna cuenta bancaria vigente; pídele una en soles.`
- `Contrato N: su cuenta de pago no es del cliente o de la moneda del contrato; no se paga hasta corregirla.`
- A los demás (analista, cliente, anónimo): el genérico de siempre, `Sin cuenta de pago — requiere conciliación`.

Etiquetas del portal: «Falta vincular su cuenta» · «Tiene varias cuentas: confirmar cuál» · «Falta
cuenta en dólares/soles» · «El cliente no tiene cuenta» · «La cuenta no corresponde».

## Cómo publicar (lo lanza Miguel; el servidor antes que el portal)

Desde `CRM-Avance-Corp/` del worktree `AVANCECORP-desktop-worktrees/cuentas-pago-rezago-20261001`
(rama `crm/cuentas-pago-rezago-20261001`):

```bash
supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/ensayo-prod-sin-escribir.sql   # no escribe nada; debe decir "veredicto": "PASA"
supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/censo-sin-funciones.sql
supabase db query --linked --file supabase/migrations/20261001233019_crm_cuentas_pago_motivo_y_rezago.sql
supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/registrar.sql
supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/censo.sql                      # esperado: 683 ok · 0 · 7 · 12 · 3
supabase db query --linked --file supabase/migrations/20261002005004_crm_asignar_cuenta_pago.sql      # debe devolver ASIGNAR_CUENTA_PAGO_OK
supabase db query --linked --file supabase/scripts/cuentas-pago-asignar/registrar.sql
```

Si el ensayo dice `INCOMPLETO` por «otra sesión tenía ocupada la cuota», alguien estaba registrando
un pago justo ahí: se vuelve a lanzar. Si dice `FALLA`, no se aplica.

Después: publicar el portal una vez (rama `cuentas-pago-20261001` del worktree
`portal-cuentas-pago-20261001`), `npm run gen:types` en `app/`, y fusionar las dos ramas a `main` el
mismo día. Las guías están en `supabase/scripts/cuentas-pago-rezago/LEEME.md` y
`supabase/scripts/cuentas-pago-asignar/LEEME.md`.

## Verificación (banco local propio; nada en producción)

- Primera migración: ciclo completo de 523 pasos, 0 fallos, 20 731 comprobaciones (aplicar,
  repetir, revertir, pagos en curso a dos sesiones, ensayo en sus tres veredictos, mutantes).
- «Asignar cuenta»: ciclo completo de 386 pasos, 0 fallos, 19 237 comprobaciones (dos asignaciones
  a la vez, doble clic, cruce con la carga automática, cerrar → reabrir → asignar, mutantes).
- Portal: 200 de 200 pruebas.
- Revisiones: auditor de permisos ×2 y Codex ×2, sin hallazgos graves abiertos. Commits de cierre:
  CRM `787289b1`, portal `bd3aab6`.
- No se corrió: la matriz de permisos por HTTP, los advisors de Supabase ni nada contra producción.

## Qué NO se tocó

- Los 22 contratos que siguen bloqueados tras la carga (7 con dos cuentas, 12 con cuenta solo en la
  otra moneda, 3 sin cuenta): se destraban uno por uno con «Asignar cuenta», cuando administración
  confirme con el cliente (o registre la cuenta que falta en Clientes → Cuentas).
- `2026-01-444444` (demo, sin cuenta) y `2026-01-000009` (demo): intactos. Decide Miguel.
- El alta de contratos, `crear_contrato_con_cuenta`, «Cambiar cuenta de pago», «Retirar cuenta» y las
  métricas: sin cambios. No se inventan cuentas ni se convierte moneda.

## Pendiente de decidir

- En la agenda de Pagos, el botón «Asignar cuenta» va encima del «Marcar pagado» apagado (la fila
  crece un poco). Alternativa: que reemplace al botón apagado.
- Riesgo que ya existía, ahora medido en el banco: «Retirar cuenta», lanzado a mano en un modo de
  transacción distinto del normal, retira una cuenta recién asignada (en el modo normal se niega).
  Por la aplicación siempre va en el normal. Propuesta: una migración aparte que les ponga a
  «Retirar cuenta» y «Cambiar cuenta de pago» la misma negativa que ya lleva «Asignar».
- «Asignar cuenta» solo admite contratos abiertos. Hoy los 23 sin cuenta están activos; si un día
  apareciera un contrato cerrado sin cuenta y con cuotas por pagar, habrá que decidir qué hacer.
- La matriz de permisos por HTTP (`test-rls.mjs`) tiene las sondas nuevas escritas, pero no se
  corrió: necesita el banco local compartido y no se tocó sin turno.

## Lecciones

- **Un dato «faltante» puede ser una decisión faltante.** Antes de vincular en lote, contar cuántas
  cuentas posibles hay por contrato: con dos, no es un hueco, es una pregunta al cliente.
- **Un ensayo que «no dio error» no probó nada.** El ensayo de producción comprueba el efecto (la
  cuota quedó pagada y sellada) y distingue PASA, FALLA e INCOMPLETO.
- **Un candado no refresca la fotografía.** Esperar un candado y luego leer solo sirve en el modo de
  transacción normal (READ COMMITTED); por eso la carga, las reversas y «Asignar» se niegan en otro.
- **Las reversas y reaperturas se generan**, con una sola definición de «las piezas están enteras»;
  escritas a mano, cada una comprobaba cosas distintas.

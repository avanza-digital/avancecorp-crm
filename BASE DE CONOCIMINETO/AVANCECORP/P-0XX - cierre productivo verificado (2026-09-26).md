# P-0XX — cierre productivo verificado

**Cerrado el alcance técnico aprobado el 26/09/2026.** Miguel autorizó los dos
SQL finales después de integrar el PR #109. Main de referencia:
`1cb79aecce07ef7e4b66aa938931e81e79743c7e`.

- 501 registros bancarios válidos de perfil; **0 sin equivalente activo**.
- Dos nuevas versiones de cuenta y una reparación excepcional del nombre de
  un banco legado. Repetición del mismo SQL: **0 + 0**.
- Actor técnico identificable: ADMINISTRADOR AVANCE CORP. Dos INSERT de cuenta
  y un UPDATE del nombre de banco auditados; el trigger de solo lectura volvió
  a quedar habilitado. Los cuatro vínculos contractuales conservan su huella.
- Dos entradas de pantalla SECURITY INVOKER, con autorización privada
  SECURITY DEFINER intacta. Hechos/tablas cerrados; anon rechazado.
- Caso testigo: ficha y lectura del propio cliente **BCP PEN …6087 / USD …9168**.
- Advisors productivos: **0 hallazgos nuevos**, retirados exactamente los dos
  avisos añadidos por P-0XX.

La migración de permisos se registró como `20260926172402`.
La conciliación fue una transacción operativa auditada, sin ejecución automática
en ramas futuras. La rama propia `hhpjiygytwoayxymziqo` fue eliminada y se
verificó su ausencia el 26/09 a las 12:32:54 Lima; costo estimado US$0,3503.

## Operaciones y deuda acordada

**23 contratos activos sin vínculo: 21 operativos y 2 demo.** Los operativos
son 14 sin cuenta y 7 ambiguos; los dos demo no tienen cuenta. Se entregó la
lista con cliente, DNI, moneda, analista y marca demo. Un demo sin DNI está
identificado como «Sin DNI registrado». Permanecen bloqueados para pagar y
exportar hasta contar con una instrucción inequívoca y respaldada. Este reporte
es la entrega prevista para esos contratos; no se inventaron vínculos.

Archivo privado actualizado:
`_DEV_NO_SUBIR/releases/p0xx-conciliacion-actual-20260926.md` y su CSV.
Se conservan las columnas bancarias legadas, su trigger y el modo `perfil`
para un trabajo posterior. Número P definitivo pendiente de Miguel.

## Evidencia

Acta completa: `CRM-Avance-Corp/supabase/scripts/p0xx/CIERRE-PRODUCCION.md`.
Ensayos de rama: SQL, reversa, 287 HTTP/RLS y 10 HTTP PASS. PR #109: cuatro
controles SUCCESS. El frontend de P-0XX publicado conserva su evidencia de
4.440 tests y 274 E2E Docker aprobados; no se reconstruyó para este cierre SQL.
La revisión independiente no entregó un dictamen válido y no se declara PASS.

Relacionado: [[P-0XX - cierre de excepciones ensayado (2026-09-26)]],
[[P-0XX - publicación y conciliación pendiente (2026-09-25)]],
[[Cuentas bancarias por contrato]], [[Cuentas bancarias - ledger vs casillas del perfil]].


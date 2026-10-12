# Eliminar inversión: admin y gerencia, en las tres empresas (05/10/2026)

**Pedido de Miguel:** «mi usuario admin y gerencia deben poder eliminar cualquier inversión en las tres empresas».
**Estado (05/10 ~19:30):** PR #200 (`crm/eliminar-inversion`), migración `20261005200945_crm_eliminar_inversion.sql` r4 tras
Codex r1, auditor-rls y Codex r2. Banco limpio: 24/24, 16 mutantes, dos carreras de dos conexiones, mes cerrado, reversa al byte.
**SQL aplicado en producción 05/10 ~22:50 (APTA; huellas = banco).** ✅ FRONT PUBLICADO 06/10 ~00:00 Lima por `/release-crm`: squash `cce54754` (#200), build `build-20261006T045840575Z`, artefacto `crm-20261006T045841Z-cce54754f4f1.zip` (SHA-256 `a5a5f415…`). check 6174/6174 · preflight OK (contiene `1d4134e6`) · smoke: home 200, 136/148 archivos vivos idénticos al manifiesto (todo html/js/css/json; los 12 PNG los recomprime la CDN, iguales al release anterior).

✅ main local al día: se publicó desde GitHub (decisión de Miguel 06/10, el main local iba un commit atrás por archivos sin guardar de otra sesión); el 06/10 10:28 el main local ya era `33694da6` = `avancecorp/main` y contiene `cce54754`.

## Decisiones de Miguel (05/10)
- **D1 Eliminar con copia** (no «anular»): sale del capital, la cartera y la conversión; queda copia inmutable con motivo y autor.
  Ojo: en este CRM «anular» (regla ATR-4 del 31/08) quita la conversión pero CONSERVA el capital; no es lo mismo.
- **D2 Conversión:** si la inversión es la conversión de un lead y no está anulada, solo gerencia; se anula por la puerta de
  siempre (con su ajuste si el mes está cerrado) y se elimina en el mismo paso.
- **D3 Con historia propia no se elimina:** renovación, upgrade, reinversión, retiro, ajuste de mes cerrado, cotitulares
  históricos, cambios de analista o solicitudes posteriores.
- **D4 Número de depósito: queda libre** al eliminar, para que el registro correcto pueda usarlo; el número se guarda en la
  copia. No se reserva (Miguel, 05/10, «queda libre el numero»). No es un descuido: no «arreglarlo».

## Por qué hoy no se podía
- «Eliminar contrato» (15/09) solo lo ven admin/superadmin del portal, solo en Avance.
- Y además **falla con los contratos que son conversión** (64 de 143): `private.leads_before_update` revierte el
  `ON DELETE SET NULL` de `crm.leads.contrato_id` si no está encendida `crm.op_privilegiada`, y la FK rechaza el borrado.
- Las cooperativas no tenían ninguna vía: `crm.cierres_externos` prohíbe SIEMPRE el DELETE.

## Trampas que se descubrieron (y cómo se resolvieron)
- 🔴 **Una anulación de cooperativa vive en la FILA del cierre** (`anulado_en`). Si se anula y luego se borra la fila,
  `private.cierre_anulado(lead)` deja de verla y la conversión de **agosto o antes** (rama `lead_asignaciones`)
  **resucita**. Arreglo: la copia guarda `conversion_anulada` y `cierre_anulado` la consulta. Probado con un mutante.
- 🔴 **`crm.contrato_eliminar_auditado` está declarada en el vigía analítico**: cambiar su cuerpo caduca su huella y dispara la
  alerta diaria. No se tocó; por eso en Avance la puerta exige admin del portal (hoy los dos de gerencia lo son).
- Los candados de DELETE se abren con una **válvula única** (`private.inversion_eliminacion_autoriza`): llave de su copia, misma
  transacción, mismo actor y fila idéntica a la copiada. Ni con la llave de otra copia se abre.
- Ninguna función nueva puede combinar `crm.leads` con `count(` (el censo la atraparía): ver la nota del censo analítico.

## Pruebas
Banco Docker a paridad al byte: 24 bloques (todo en ROLLBACK), 16 mutantes muertos, dos carreras de dos conexiones, mes cerrado
(ajuste exactamente una vez), reversa que deja las huellas idénticas a producción y reaplicación idéntica. Gate de RLS con `testEliminarInversion`.

Relacionado: [[Acceso Avance - otro alta pendiente y borrado de FIEX (2026-10-05)]] ·
[[Eliminar contratos con pagos por administrador - preparado 2026-09-15]]

**✅ Cerrado el 06/10.** Se borraron el worktree, la rama y los bancos de prueba. Pendiente manual: borrar en Storage el comprobante de FIEX (bucket `f4-comprobantes`, carpeta `721b1f50…`).

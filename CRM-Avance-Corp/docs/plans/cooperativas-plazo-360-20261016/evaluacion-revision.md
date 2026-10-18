> Histórica: evaluación de la primera revisión, anterior al ensayo remoto.
> Estado final en [evaluacion-revision-final.md](evaluacion-revision-final.md).

# Evaluación del PRIMARY

Revisión LEVEL 3 por `scripts/claude-review`, una consulta entregada. El intento
inicial dentro del sandbox no completó la revisión; se repitió con permiso y
el mismo encargo. Dictamen: **CHANGES_REQUESTED**, no se afirma PASS del reviewer.

- **P1, desajuste temporal servidor/pantalla: aceptado.** Se documentó una
  ventana coordinada, servidor seguido de pantalla y actualización de todas
  las sesiones antes de reanudar altas. Se inspeccionó `version-publicada.tsx`:
  el aviso permite posponer y no fuerza recarga. La ventana y las PWA antiguas
  siguen siendo un riesgo de publicación que debe verificarse en el ensayo.
- **P2, huella del CHECK: aceptado y corregido.** Se añadió la huella productiva
  `d6a4d93538ee16cf31d5f373209c901f`, leída del catálogo. Replay desde cero PASS.
- **P2, permisos del helper: hipótesis descartada por catálogo.** Las puertas
  `convertir_lead_externo`, `preparar_inversion_fn`,
  `confirmar_inversion_revisada_fn`, `corregir_solicitud_inversion_fn` e
  `inversionista_corregir_coopac_fn` son SECURITY DEFINER de `postgres`.
  Los helpers invoker ejecutan dentro de ese contexto. El nuevo helper
  conserva propietario `postgres`, sin grants a PUBLIC/anon/authenticated.
  No hay motivo para ampliar permisos. Falta probar los recorridos autenticados.
- **P2, operaciones autenticadas sin ensayar: aceptado, pendiente.** No se
  presenta el banco de CHECKs como sustituto del ensayo de operaciones reales
  ni de la matriz RLS. Es un requisito antes de instalar/publicar.
- **P3, históricos sin condiciones:** se conserva calendario y no se inventa
  una nueva convención para un contrato anterior. Es coherente con el alcance
  comunicado de conservar contratos registrados.
- **P3, CASE sin ELSE:** se añadió también la lista de convenciones al mismo
  CHECK, además del NOT NULL y la restricción específica.
- **P3, fechas posteriores al año 9999:** sin cambio adicional; el formulario
  rechaza el desborde. No es un caso válido del flujo comercial.

El replay final se hizo en `coopac_360_replay_20261016`, esquema vacío anterior
al cambio. Así las comprobaciones de funciones, ACL y filas comparan una línea
base anterior real. La copia local omite únicamente el ACL de una función
GraphQL ausente en el dump, ajena a las funciones y tablas del CRM.

La corrección de Gerencia no muestra una fecha calculada por el helper nuevo:
para condiciones registradas explica el ajuste del servidor; solo los
históricos sin condiciones permiten una fecha manual. No hay previsualización
de calendario sustituida por 360 en ese formulario.

Un borrador reanudado todavía puede contener su fecha anterior. El cambio no
lo reescribe silenciosamente: debe pasar por editar/revisar; el formulario
compartido recalcula antes de enviar. El ensayo autenticado pendiente debe
confirmar tanto el rechazo inicial como la recuperación sin duplicados.

# Auditoría de atribución en Facturación

Fecha: 13 de octubre de 2026, aproximadamente 14:00–14:15, America/Lima.
Estado del diagnóstico inicial: confirmado mediante consultas de solo lectura.

**Actualización 13/10, 18:12 Lima:** la venta 001595 fue corregida Fiorella → Jorge mediante el CRM publicado y verificada en Facturación; véase [evidencia](correccion-real-verificada.json). El texto siguiente conserva el diagnóstico anterior a esa corrección.

La venta de S/ 150.000 del 11 de octubre sigue contando a Fiorella porque el contrato **2026-01-001595** conserva a Fiorella en `analista_cierre_id`. Se trasladó la atención del cliente a Jorge; no se ejecutó la reasignación de la venta. Una consulta nueva al servidor devuelve la misma cifra de la captura.

## Caso confirmado

| Hecho | Evidencia |
| --- | --- |
| Contrato | 2026-01-001595, activo, categoría nuevo, PEN 150.000, fecha comercial 11/10/2026 |
| Registro | Jorge lo registró el 12/10 a las 16:40:43 Lima; analista de la venta: Fiorella |
| Primer traslado | Perfil del cliente: Fiorella → Jorge, 12/10 a las 16:44:00 Lima |
| Segundo traslado | Responsable de relación: Fiorella → Jorge, 13/10 a las 13:59:46 Lima; motivo literal «venta de jorge» |
| Venta | Continúa atribuida a Fiorella; no hay filas de reasignación para ese contrato |
| Estado del analista | Fiorella sigue activa; la regla de herencia por baja no interviene |
| Lectura nueva | La RPC de la matriz y la RPC del detalle devuelven una operación, PEN 150.000, Fiorella, día 11 |

Fuente: `public.audit_log`, `crm.inversionista_responsables`, `crm.reasignaciones_analista`, funciones vivas de atribución y lecturas autenticadas de Gerencia. Las consultas se ejecutaron con `BEGIN READ ONLY` y `ROLLBACK`. Para las RPC se fijó la identidad de lectura únicamente dentro de la transacción; no se modificaron usuarios, roles ni datos.

### Impacto

Fiorella tiene en octubre PEN 159.600 y USD 17.690, distribuidos en cinco operaciones. Retirar de su atribución este contrato dejaría PEN 9.600 y USD 17.690, cuatro operaciones. Con el mismo tipo de cambio y las demás cifras de la captura, el total equivalente pasaría de S/ 220.496,06 a S/ 70.496,06.

La operación debe conservarse y atribuirse al vendedor correcto. El total de la empresa por moneda no cambia. No se promete conservar el subtotal de cada supervisor: se recalcula con la jerarquía aplicable al nuevo analista.

## Hallazgos

### P1 Corrección comercial incompleta en el contrato 001595

La intención de corregir el dueño de la venta está respaldada por el mensaje del usuario y el motivo «venta de jorge». Los cambios ejecutados modificaron responsabilidades del cliente, pero no el dueño contractual de la venta. Facturación aplica la atribución almacenada.

La corrección de una venta ya tiene una puerta propia: `public.reasignar_analista_contrato`. Su historial y el campo protegido no fueron modificados en este caso. No es necesario borrar el contrato ni cambiar el importe para resolver la atribución.

### P2 Los flujos de responsabilidad permiten confundir atención con mérito

`app/src/components/app/postventa-persona.tsx:110` guarda el responsable y anuncia «Responsable actualizado», sin explicar la atribución de las ventas. En el portal, `public_html/js/admin/clientes.js:1222` modifica directamente `perfiles.asesor_perfil_id` y anuncia «Analista actualizado correctamente».

El detalle del contrato sí distingue «Analista de la venta» y ofrece «Reasignar» (`app/src/components/app/contrato-detalle.tsx:547`). Las dos acciones existen, pero sus efectos no están presentados conjuntamente en el lugar donde se cambia la atención.

### P2 Las vías de atención pueden dejar dos responsables distintos

El contrato **2026-01-001546**, PEN 50.000 del 02/10, tiene el perfil del cliente asignado a Astrid desde el 13/10 a las 13:47:38 Lima; la persona unificada conserva a Jorge como responsable y la venta también sigue en Jorge. No hay reasignación de venta.

Esto confirma una divergencia de los datos de atención. **No demuestra que la venta deba pasar a Astrid**: cambiar la atención puede ser legítimo sin cambiar el mérito. Se necesita la intención comercial de ese caso para decidir si corresponde corregir su venta. En el caso 001595 los dos responsables quedaron alineados solo tras el segundo traslado, casi un día después.

## Comprobaciones de octubre

| Comprobación | Resultado |
| --- | --- |
| Operaciones | 71: 58 contratos y 13 cooperativas |
| Identificadores de operación duplicados | 0 |
| Operaciones sin analista | 0 |
| Importes no positivos | 0 |
| PEN | 59 operaciones, 2.728.900 |
| USD | 12 operaciones, 138.190 |
| Matriz frente al núcleo | Totales y cantidades coinciden por moneda |
| Detalle del día 11 de Fiorella | 1 operación, PEN 150.000, contrato 001595 |
| Contratos de octubre con analista efectivo distinto del asesor del perfil | 2: 001595 y 001546; no equivale a dos ventas mal asignadas |
| Cooperativa anulada incluida en capital | 1; permitido por la regla vigente que separa anulación de conversión y capital |

La auditoría cubre la causa del caso reportado, las vías de reasignación relacionadas y controles del mes de octubre. No constituye una auditoría exhaustiva de seguridad ni de todos los meses.

## Reglas que deben conservarse

Se comprobó también el origen: la solicitud de 001595 nació por la puerta `cartera`, con responsable esperado Fiorella y sin vendedor independiente. `crm.confirmar_inversion_revisada_fn` resuelve la venta desde ese responsable; `inversion-nueva.tsx:518` ofrece ese mismo nombre. Que Jorge registre la operación no la convierte en una venta suya. La prevención debe mostrar el vendedor resuelto antes de confirmar el alta, sin sustituirlo automáticamente por el registrador ni romper la regla especial de venta cruzada.

- `analista_cierre_id` identifica al vendedor; `creado_por`, al registrador; `asesor_perfil_id`, a quien atiende al cliente. La distinción es deliberada: migración `20260829180000`, líneas 11–20.
- Facturación usa `private.capital_episodios` → `private.analista_efectivo_contrato`; la matriz y su detalle comparten el núcleo.
- El analista activo conserva su atribución aunque se traslade la atención del cliente.
- La baja de un analista sí puede transferir la atribución efectiva al responsable activo; una vista previa debe mostrarlo.
- Una cadena de upgrade puede atribuir capital a una persona distinta del vendedor almacenado en la renovación.
- Las lecturas vivas y las fotos mensuales selladas tienen contratos distintos. No se deben resellar meses como efecto accidental de una corrección.

## Verificación ejecutada

PASS: cinco archivos / 49 pruebas existentes con:

```sh
cd app
npm run test:run -- src/data/facturacion-refresco.test.tsx src/data/operaciones-facturacion-refresco.test.tsx src/data/crm-api-facturacion-msw.test.ts src/data/crm-api-operaciones-facturacion-msw.test.ts src/components/app/contrato-detalle.test.tsx
```

PASS: reproducción y controles SQL de lectura en producción. Docker disponible, versión 29.8.2.

En esta fase de diagnóstico todavía no existía candidata. Después de la aprobación del usuario se implementó y verificó en el banco aislado; resultados actuales en [VERIFICACION.md](VERIFICACION.md).

La primera ejecución del wrapper de Claude falló y un intento fue interrumpido. El reintento posterior completó una revisión válida del diagnóstico y del plan: **CHANGES_REQUESTED**. Se incorporaron alcance de desgloses, prevención en el alta, estado esperado y decisiones de permisos del portal. Hubo una segunda revisión de implementación; ver [evaluación y decisiones](REVISION.md).

## Decisión del usuario

El 13/10 aprobó dos acciones separadas con su efecto visible antes de guardar: **Cambiar quién atiende al cliente** y **Corregir el dueño de una venta**. Después exigió expresamente el cumplimiento de las reglas de backend.

Luego autorizó implementar y probar en un banco aislado, mover el núcleo a private, conservar el adaptador de public y bloquear el cambio directo de asesor. Atención completa: Gerencia y administradores del portal. Ver [Plan de mecanismos](PLAN.md). La corrección puntual fue autorizada posteriormente y ejecutada el 13/10 a las 18:12 Lima; véase la actualización inicial.

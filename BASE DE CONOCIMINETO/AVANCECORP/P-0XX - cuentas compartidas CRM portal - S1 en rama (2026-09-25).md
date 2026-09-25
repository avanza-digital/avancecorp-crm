# P-0XX: cuentas compartidas CRM y portal — S1 en rama

**Fecha:** 2026-09-25. **Estado:** S1 ensayado en la rama `p0xx-cuentas-unificadas-20260925`; producción solo se consultó con `SELECT`. Sin merge ni publicación. Falta asignar el número definitivo de P.

## Decisión y alcance

Miguel confirmó que CRM y `miavance.com/public_html` deben mostrar los mismos valores del cliente. Identidad y contacto ya comparten `public.perfiles`; el problema divergente es banca. La cuenta vigente de la ficha se lee de `crm.cuentas_bancarias`, y la instrucción de pago sigue siendo `crm.contrato_cuentas_pago`.

Para contratos antiguos sin vínculo, Miguel autorizó enlazar **solo si existe exactamente una cuenta activa del mismo cliente y moneda**, aun cuando no hay prueba histórica de la instrucción original. Esta decisión sustituye para P-0XX la prohibición de backfill automático documentada en [[Cuentas bancarias por contrato]]. Con cero o varias candidatas, el contrato queda para conciliación. El vínculo creado es inmutable.

## S1 ensayado

- Migración `20260925153226_p0xx_cuentas_cliente_backfill_lectura.sql`: copia perfiles válidos al ledger sin reemplazar cuentas contractuales, vincula solo candidatas únicas y guarda los IDs insertados en `private.backfill_cuentas_p0xx` para reversa. Los insertos de backfill usan `creado_por = NULL`; la marca identificable es `migracion:p0xx:s1` en esa tabla. La auditoría histórica no se reescribe.
- `private.cuentas_cliente_vigentes` es el hecho de lectura; `crm.cuentas_bancarias_cliente_fn` conserva firma y aplica `private.puede_gestionar_cuentas_cliente`; `crm.cliente_detalle_fn` conserva firma y llena sus columnas bancarias desde el ledger. Banca de cliente inactivo queda oculta por el gate existente.
- El ensayo con siete clientes ficticios y siete contratos produjo 3 cuentas y 2 vínculos de backfill; 3 contratos activos quedaron sin vínculo (sin cuenta, perfil inválido, dos candidatas). También se verificaron CCI distintos y conflicto de mismo CCI. Segunda ejecución: 0 filas nuevas. La reversa borró solo las filas marcadas y la reaplicación las restauró.
- `supabase/scripts/p0xx/reporte-conciliacion-activos.sql` entrega contrato, cliente, DNI, moneda, analista vigente y motivo sin exponer números bancarios. En la rama lista los tres casos ficticios; repetirlo tras el merge manual para la lista real de operaciones.
- El caso ficticio equivalente al testigo mostró BCP PEN `…6087` y USD `…9168` mediante la ficha SQL. El caso real de DNI 02650333 aún no recibió la migración porque producción no se tocó.
- Advisors de seguridad y rendimiento: cero hallazgos nuevos frente a la línea base de la rama. `lint`, `typecheck`, 4.415 pruebas y `build` del CRM pasaron. El portal y Pagos se corrigen en S2/S3.

## Proyección de producción, solo lectura

De 500 secciones bancarias pobladas y válidas en perfiles: 256 ya equivalen a una cuenta activa CRM, 241 se podrían insertar y 3 tienen mismo CCI con datos distintos. Esos 3 exigen decisión manual; el objetivo de cero perfiles válidos sin equivalente no se alcanza sin resolverlos.

De 280 contratos sin vínculo, 257 tendrían candidata única (255 activos y 2 vencidos). Permanecerían 23 activos sin vínculo: 16 sin cuenta y 7 ambiguos; 2 de los 16 son demo. La lista detallada de operaciones debe leerse de un reporte de conciliación actualizado antes de cualquier merge; el responsable operativo es `perfiles.asesor_perfil_id`, mientras `contratos.analista_cierre_id` es histórico y puede ser nulo o distinto.

## Pendiente

S2: cerrar todas las escrituras bancarias a `perfiles`, registrar versiones en el ledger y actualizar la ficha/admin/analista/edges. S3: Pagos usa solo el vínculo contractual y bloquea pago/exportación sin cuenta. Eliminar columnas legacy y retirar modo `perfil` corresponden a un P posterior, tras un cierre estable.

Relacionadas: [[Cuentas bancarias - ledger vs casillas del perfil]] · [[Cuentas bancarias por contrato]] · [[Notificaciones de pagos]] · [[Arquitectura del portal]].

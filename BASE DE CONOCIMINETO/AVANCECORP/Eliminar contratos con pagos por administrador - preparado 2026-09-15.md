# Eliminar contratos con pagos por administrador — preparado

Miguel pidió que Admin pudiera eliminar contratos en el CRM y confirmó:
**también contratos con pagos, conservando una copia de auditoría**. Después pidió
validar todo y dejar listo para publicar; autorizó el banco temporal a US$0,01344/h.
Pausó el trabajo brevemente y ordenó continuar. No autorizó publicar en esta fase.

Implementado: botón en ficha, confirmación por número, rol activo revalidado en
servidor y copia privada e inmutable de contrato/pagos/relaciones. Copia y borrado
se confirman en una transacción; los PDF permanecen privados en sus rutas.

Los contratos vinculados al historial multiempresa y las restricciones de meses
cerrados/renovaciones siguen protegidos. No se cambió la anulación comercial ni
se eliminaron contratos reales.

Validación final: 3.620 pruebas frontend, 192 E2E (26 omisiones existentes), 46
Edge/Storage, siete grupos SQL, 284 aserciones remotas de permisos/contratos y
22 comprobaciones HTTP/Auth/Edge/Storage PASS. La prueba real confirmó pagos
archivados exactamente, concurrencia, actor y archivos conservados byte a byte.
Tipos y fuente desplegada en la rama coinciden; advisors sin nuevos WARN/ERROR.
La matriz global conserva deuda previa, desglosada en el acta; no declarar que pasó.
Antes y después: 44 aserciones fallidas y la misma interrupción D-13, cero nuevas.
Rama temporal propia eliminada el 15/09 a las 20:38 Lima; coste estimado US$0,0331.

Dos revisiones Claude evaluadas. Se cerraron las puertas antiguas, se protegió
TRUNCATE y se añadieron guardas para dependencias futuras, acción FK modificada
y UUID reintroducido. Los conflictos SQL muestran mensajes públicos seguros.

**Producción pendiente:** aprobar los SQL exactos `20260915222925` y
`20260916003000`, instalarlos en ese orden, desplegar la Edge y publicar el
artefacto del commit sincronizado con `avancecorp/main`. Instalar el SQL no
elimina contratos. No afirmar que este nuevo flujo esté activo todavía.

Acta técnica, hashes, evidencia y estado del banco:
`CRM-Avance-Corp/supabase/scripts/contratos-eliminar/README.md` y
`VERIFICACION.json`. No usar un db push general ni una copia de trabajo sucia.

Relacionadas: [[Inicio]] · [[Ciclo de vida de contratos]] ·
[[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]] ·
[[RETOMAR-61 - Contrato duplicado e idempotencia del alta (2026-09-05)]]

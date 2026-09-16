# Eliminar contratos con pagos por administrador — publicado

Miguel pidió que Admin pudiera eliminar contratos en el CRM y confirmó:
**también contratos con pagos, conservando una copia de auditoría**. Después pidió
validar todo y dejar listo para publicar; autorizó el banco temporal a US$0,01344/h.
Pausó el trabajo brevemente y ordenó continuar. Tras recibir el paquete y los SQL,
autorizó «ok hazlo para poder publicar». SQL y Edge instalados el 15/09 a las 21:44 Lima.

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
En aquella entrega, la matriz global conservaba 44 fallos anteriores y la misma
interrupción D-13. Miguel pidió repararlos después; estado vigente en
[[Matriz RLS global - reparacion y candado F8 2026-09-16]].
Rama temporal propia eliminada el 15/09 a las 20:38 Lima; coste estimado US$0,0331.

Dos revisiones Claude evaluadas. Se cerraron las puertas antiguas, se protegió
TRUNCATE y se añadieron guardas para dependencias futuras, acción FK modificada
y UUID reintroducido. Los conflictos SQL muestran mensajes públicos seguros.

**Backend instalado y verificado:** SQL `20260915222925` y `20260916003000`
registrados como `20260916024417` / `20260916024423`; Edge versión 18 ACTIVE,
con la verificación JWT conservada. Nueve archivos iguales al commit `2145f27`,
permisos y rechazos SQL/HTTP PASS; 594 contratos y 5.320 cuotas sin cambios,
cero auditorías. Sin nuevas alertas WARN/ERROR. No se borró ningún contrato real.

**Interfaz publicada:** la entrega autorizada de Cartera incluyó los cambios
anteriores de Main, incluida esta función. ZIP `crm-20260916T035915Z-a09ecad9aaed`,
build `build-20260916T035613621Z`. Comprobación HTTP independiente del 16/09:
78 recursos de código/configuración idénticos. La RPC conserva su cuerpo y ACL;
Edge v19 es el reempaquetado de las mismas fuentes durante ese merge. No se
realizó una eliminación de un contrato real para comprobarlo.

La publicación original ya no está pendiente. El ajuste F8 detectado al reparar
la matriz tiene su SQL separado y requiere autorización propia antes de instalar.
Relacionado: [[Cartera inversionistas - implementacion de filtros comerciales (2026-09-15)]].

Acta técnica, hashes, evidencia y estado del banco:
`CRM-Avance-Corp/supabase/scripts/contratos-eliminar/README.md` y
`VERIFICACION.json` y `PRODUCCION.json`. No usar un db push general ni una copia de trabajo sucia.

Relacionadas: [[Inicio]] · [[Ciclo de vida de contratos]] ·
[[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]] ·
[[RETOMAR-61 - Contrato duplicado e idempotencia del alta (2026-09-05)]]

Miguel pidió habilitar el comando también en Codex. Se agregó la habilidad
`.agents/skills/release-crm/SKILL.md` en la raíz del proyecto, con invocación
manual y metadatos para el selector. Crear la habilidad no publica la web.

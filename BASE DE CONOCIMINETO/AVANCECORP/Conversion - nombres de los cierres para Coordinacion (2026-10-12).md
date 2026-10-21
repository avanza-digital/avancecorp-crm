# Conversión - nombres de los cierres para Coordinación (2026-10-12)

Relacionado con [[Conversion - divisor de Coordinacion desde el nucleo (2026-09-30)]] y [[Coordinacion - Facturacion y Ranking en lectura (2026-10-12)]].

Miguel priorizó que Coordinación pudiera ver al cliente Uchanima en Conversiones octubre de Astrid. La consulta real de solo lectura confirma que ese cierre ya cuenta como referido manual del 1 de octubre; el formulario del 7 de octubre es otro cliente. No son dos formularios. La pantalla existente solo mostraba agregados.

Aprobó «Ver cierres» por analista con nombre, origen, fecha y registro manual/sistema, conservando los conteos. Implementación publicada: RPC `crm.conversion_cierres_coordinacion_fn` → núcleo `private.conversion_cierres_coordinacion` → episodios canónicos. Coordinación/Gerencia activas, detalle global mínimo, páginas de veinte. Incluye operaciones de cartera y aporta el peso canónico. No otorga contactos, documentos, importes ni fichas de clientes.

Mes calendario sellado: no hay lista histórica de clientes, se informa sin reconstruir. Rangos libres continúan con cálculo vivo como el resumen. La consulta anterior de Facturación permanece anónima; esta autorización corresponde exclusivamente a Conversiones.

**Publicado el 12/10/2026 a las 17:53 Lima** en https://crm.miavance.com, después de `$release-crm` y las autorizaciones expresas «Sí, instalar y continuar» y «Sí, instalar ambos cambios y publicar». Backend instalado por merge de la rama Supabase propia: versiones `20261012221444` (Ver cierres) y `20261012223850` (Facturación/Ranking). No se modificaron ni borraron filas de clientes, ventas o cierres.

Fuente exacta `10e3411deb2288cbf01c81513b63a5c1ca6d9a51`, Main local = avancecorp/main antes de publicar. ZIP `crm-20261012T224323Z-10e3411deb22.zip`, SHA-256 `265fbb65b89b0ed0527b8a9e36cf9f9a9a494dc65f83f4a915915fc04801b10e`, build vivo `build-20261012T224322167Z`.

PASS npm run check completo (6.640 tests), matrices SQL conjuntas, RLS pertinente HTTP/Auth (319 aserciones), permisos de la nueva RPC y ocho consultas reales de Coordinación en transacción READ ONLY. Confirmado en producción: Astrid octubre devuelve dos cierres, Catherine como formulario/sistema del 7 y Honorato Uchanima como referido/manual del 1. Son 1 formulario + 1 referido, total 2.

Smoke PASS: portada 200 y 121 JS/CSS idénticos al manifiesto. 147/159 archivos públicos con bytes exactos; 12 PNG servidos con codificación/tamaño distintos (7 con píxeles idénticos, 5 logos redimensionados a 1600 px, diferencia media por canal inferior a 0,57/255 contra el original redimensionado). Se conserva esta limitación de identidad binaria. El gate RLS general completo falló por fixtures/configuración/Storage del banco; no se presenta como PASS, se acredita la matriz pertinente de lectura. Advisors: dos avisos esperados de nuevas RPC SECURITY DEFINER protegidas y avisos de índices preexistentes sin uso, sin cambios de índices.

Acta y evidencia: `CRM-Avance-Corp/supabase/scripts/conversion-cierres-coordinacion/LEEME.md`, `publicacion.json` y `smoke-publicado.json`. Rama temporal propia eliminada después de verificar producción, sin tocar otras ramas. Artefacto anterior conservado para recuperación.

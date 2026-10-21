# Reemplazar inversión · Fase 4: cooperativas, construida (2026-10-18)

Continúa [[Reemplazar inversion - plan por fases (2026-10-17)]]. Las Fases 1–3 (Avance) están en producción desde el 17/10.

## Decisiones de Miguel (18/10/2026)
- **Alcance:** solo lo que «Corregir» no corrige en una cooperativa: la cooperativa (Prodelco ↔ Qorilazo), la fecha comercial (el mes de la venta) y el comprobante. Monto, moneda, plazo, tasa, número de operación y nota se copian de la original.
- **Comprobante:** se reutiliza el de la original salvo que suban otro.
- **Rechazos:** los de Avance (mes sellado, plazo de carga vencido, venta anulada, lead por revisar) más «ya tiene movimientos» (reinversión, retiro, ajustes de mes cerrado). Sin «quedarme con la otra». Solo la inversión INICIAL.
- **Quién: solo Gerencia.** La decisión original fue «Gerencia o admin del portal» sobre la premisa «los mismos que hoy eliminan una cooperativa», que era errada: toda inversión reemplazable es la venta inicial de un lead, y la venta de un lead la toca solo Gerencia en «Eliminar inversión» (anular) y en «Reemplazar» de Avance. Lo señaló el auditor RLS; se aplicó solo Gerencia y se le avisó a Miguel.

## Cómo funciona
Migración `20261018053228`: la original se copia en `crm.inversiones_eliminadas` («reemplazada por») y se borra con la misma válvula de «Eliminar inversión», sin anular la venta; nace la fila nueva de `crm.cierres_externos` con los mismos datos salvo lo que cambia (y el vencimiento recalculado), su depósito, su fila de inversión, sus cotitulares y su evento; la venta del lead pasa a la nueva con el único escritor de acreditaciones y un invariante (misma acreditación, estado, episodio, analista, persona, origen; el mes de la fecha que queda). Idempotente por la original.

El comprobante nuevo va al bucket `f4-comprobantes` en `<persona canónica>/reemplazo-<inversión>/<archivo>`: se parcharon por ancla (con huella) las dos funciones de las políticas del bucket para admitir esa ruta (solo Gerencia, inversión inicial vigente de esa persona) y para dejar ver el comprobante que ya respalda una inversión (como la ficha) o el de una inversión ya reemplazada (Gerencia).

## Lo que se aprendió
- Un reemplazo que recrea la fila debe comprobar que el comprobante sea EXACTAMENTE el de esta inversión y de la persona canónica, y que no respalde ya otra: si no, dos inversiones vivas podrían compartir voucher (auditor RLS).
- Una reversa que devuelve una función de visibilidad a su versión anterior puede cegar datos que la nueva función ya dejó entrar: la reversa debe mirar si hay datos adoptados antes de revertir (Codex).
- En plpgsql, un `CASE … THEN … END` dentro de la condición de un `IF` hay que ponerlo entre paréntesis: el `IF` corta en el primer `THEN`.
- `storage.objects` en el banco llega sin grants: `FOR KEY SHARE` exige UPDATE; en producción postgres lo tiene.

## Estado
**EN PRODUCCIÓN, servidor y pantalla.** Servidor: migración `20261018053228` aplicada por Miguel el 18/10 ~01:50 (fotos de producción limpias, registrada, `comprobar-tras-aplicar` → `APTA`). PR #325 fusionada (`main` = `avancecorp/main` = `f2594219`). Pantalla: publicada el 18/10 a las 02:30 con `/release-crm` (artefacto `crm-20261018T070707Z-f25942197d84`, build `build-20261018T070707022Z`, preflight y humo en verde). El MCP de Hostinger no conectaba (`@latest` reinstalaba en cada arranque; se fijó la versión 3.1.0) y la subida la hizo Miguel con el script `deploy-hostinger-mcp.mjs deploy`. Queda regenerar los tipos (`gen:types`) y comparar con los escritos a mano. Huecos declarados: políticas reales de Storage y concurrencia con dos conexiones no probadas; comprobantes subidos y no confirmados quedan huérfanos.

# Entrega A — ranking de cartera legada

Estado: implementación local, no publicada ni aplicada a producción.
Base aislada: commit publicado `526d6d90c621e4072251818d1325b7bd0c01b2ca`.
Clon: `/private/tmp/ranking-cartera.AfQUSa`. El árbol principal ajeno no se modifica.

## Alcance

Un único helper privado cambia el canal, no la categoría financiera.
Solo cuando no hay leads directos ni fallback temporal (ni siquiera ambiguos),
un ledger concordante permite mostrar Cartera. No infiere operaciones por
mera repetición del cliente ni depende del espejo de inversiones.
No modifica contratos/leads/conversión/capital ni la rama COOPAC.
No aborda todavía nueva inversión por empresa, upgrade o renovación en la UI.

## Evidencia — 26/09/2026

- PASS SQL Docker: 25 aserciones nuevas, regresión anterior del ranking,
  permisos internos, precedencia de leads, ambigüedad, ledger discordante,
  sin espejo, COOPAC, foto sellada no vacía, RPC de mes sellado y reversión exacta.
- PASS comparación íntegra antes/después de datos, producción y conversión.
- PASS `node --check` del runner y whitespace del diff.
- PASS compatibilidad estática con el frontend publicado: origen es string,
  Cartera ya tiene etiqueta y no muestra conversión; no hay nuevas claves JSON.
- Proyección real READ ONLY: 143 filas antes/después, cero duplicados;
  exactamente 12 cambios sin_origen → cartera, resto de columnas idéntico.
  8 PEN: 2.092.254; 4 USD: 54.971. Betzabeth: 3 PEN por 150.000.
  Oficina conserva PEN 72.450 + USD 30.000; Referido PEN 283.000.
- PASS tres mutantes: quitar las guardas de cliente, moneda o fecha provoca
  exactamente el fallo correspondiente; ninguno sobrevive.
- PASS 66 tests existentes del frontend publicado (3 archivos de ranking);
  es compatibilidad del consumidor intacto, no un E2E del candidato instalado.
- Claude, rol auditor SQL/RLS: PASS, sin cambios obligatorios; dictamen íntegro
  en `REVISION-CLAUDE.md`, evaluación PRIMARY más abajo.
- Preflights `test:rls:preflight` / `seed:preflight`: FAIL por configuración
  ausente (SUPABASE_URL); no prueban ni refutan el comportamiento del candidato.
- HTTP/RLS completo: NOT RUN, sin endpoint/credenciales de banco autorizado.
- Advisors, rama remota, merge y despliegue: NOT RUN, fuera de autorización.
- E2E Docker integral/build frontend: NOT RUN en esta entrega SQL local;
  no se modifica frontend. Exigibles según gate antes de una publicación CRM.
- Tipos: sin regeneración porque no cambian schema público, firma ni retornos.

## Repetir localmente

`node CRM-Avance-Corp/supabase/scripts/ranking-cartera/verificar-local.mjs`

Solo admite el contenedor `supabase_db_crm-avance-corp-local` y la base
`ranking_cartera_20260926`, copia sintética creada de
`ranking_enlaces_20260926`. No acepta URL ni credenciales remotas.
Requiere el banco previo de contratos BANCO-A1/A2/A3/B1/B2 y leads sintéticos.
No es un bootstrap desde cero; si falta el banco, detenerse y prepararlo
explícitamente. Cada bloque termina con ROLLBACK; un error cierra la conexión.
No deshabilita triggers. Las válvulas de mantenimiento solo afectan fixtures.

El fixture heredado conserva PEN 70.000, no copia clientes de producción.
Intentos previos de cambiar términos/fechas fueron rechazados por los guards
contractuales. Se corrigió el fixture, no los guards ni la lógica del producto.
El warning SQLSTATE 22P02 en regresión es intencional: prueba que una foto
inválida no bloquea el cierre. Agosto vacío no se usa como evidencia de capital.
La prueba de renovación cubre lectura del ledger, no valida el flujo financiero
de renovación ni cambio de moneda, fuera del alcance de esta entrega.

## Evaluación PRIMARY de Claude

- P2 fecha: comprobado READ ONLY. En `capital_episodios`, línea 27 del
  cuerpo vivo, la fecha es `c.fecha_cierre_comercial::timestamp at time zone
  'America/Lima'`; el lector la convierte de vuelta a fecha Lima.
  Septiembre: 12 sin lead con ledger; cero discordancias de fecha, cliente,
  moneda o tipo; cero diferencias entre fecha canónica y campo persistido.
  No relajar el requisito ante futuras discrepancias: investigar el dato.
- P3 mezcla de monedas: aceptado y reforzado con exactamente 3 PEN + 2 USD.
- P3 otro tipo: no existe otro valor válido; CHECK
  `operaciones_cartera_tipo_check` permite exclusivamente renovación/upgrade
  tanto local como producción. Se prueba rechazo real de un tipo inválido,
  sin deshabilitar constraints para crear un estado imposible.
- Índice: comprobado UNIQUE btree de `contrato_nuevo_id` en producción;
  nueva aserción local de índice único válido/listo y no parcial.
- Lead directo nulo/ambiguo: precedencia intencional preservada, documentada.
- Meses sellados: se conserva la historia; no se reescriben para igualar un
  nuevo cálculo. Test de snapshot no vacío y respuesta RPC iguales.
- No se solicita otro review: el SQL revisado no cambió, solo se reforzaron
  pruebas y se respondió a las observaciones con evidencia.

## Siguiente puerta

Revisar y aprobar el SQL exacto `20260927003433_crm_ranking_cartera_legada.sql`.
Después: revalidar huellas/datos y mes abierto, ensayar en rama autorizada,
ejecutar HTTP/RLS y advisors, integrar con Main vigente sin sobrescribir cambios,
y usar el merge nativo. Ninguna prueba local autoriza una instalación directa.
Reversión preparada en `revertir.sql`, con guarda de la huella del candidato.

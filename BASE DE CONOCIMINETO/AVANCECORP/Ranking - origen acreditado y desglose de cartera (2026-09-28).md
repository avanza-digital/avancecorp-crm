---
tags: [crm, ranking, origenes, cartera, diagnostico]
fecha: 2026-09-28
estado: corrección preparada y probada localmente; sin publicación
---

# Ranking — origen acreditado y desglose de cartera

Miguel reportó una ficha de septiembre con Formulario S/ 7.500, Referido S/ 0
con conversión 7,50 %, Cartera S/ 90.000 y Sin origen S/ 190.000. Pidió
corregir el problema y ver renovación/upgrade dentro de Cartera.

## Causa comprobada con lecturas productivas

- S/ 130.000 de Formulario y S/ 15.000 de Referido tienen acreditaciones
  explícitas de la misma fuente y fecha comercial. Sus leads fueron cargados
  después del cierre, sin contrato_id. El lector de capital ignoraba el nuevo
  vínculo acreditado y seguía exigiendo un lead previo al cierre para el fallback
  por perfil. La conversión ya usa la acreditación: por eso podía verse porcentaje
  sin el capital correspondiente.
- Los S/ 45.000 restantes pertenecen a dos contratos categoría `nuevo` sin lead
  por contrato, perfil, documento ni inversionista, y sin operación de cartera
  vinculada. Ambos clientes tienen contratos anteriores activos en Avance.
  No tienen un predecesor renovado hacia esos contratos. Esto descarta una
  renovación registrada, pero NO demuestra que no sean aportes adicionales
  mal clasificados. Miguel pidió verificar, no conoce el canal; no se inventó
  un origen ni se recategorizaron contratos/operaciones.
- Cartera S/ 90.000 concilia con categorías confirmadas: Renovación S/ 10.000,
  Upgrade S/ 80.000. El frontend anterior agrupaba todo sin mostrar el reparto.

## Cambio preparado

`20260928163532_crm_ranking_origen_acreditado.sql`: helper de lectura privado,
acreditación activa/elegible, fuente y fecha exactas; fallback únicamente después
de vínculo directo, perfil anterior y cartera legada. Ambigüedades conservadas.
Sin nuevas claves RPC ni cambios a importes, categorías, vendedor, conversión o
fotos selladas. Actualiza solo la huella de la declaración analítica existente.

UI: lee las categorías del cumplimiento existente, recupera ajustes de cierre
para comparar con el bruto de orígenes y muestra Renovación/Upgrade solo cuando
cuadran por moneda en céntimos. Si cartera legada conserva categoría financiera
`nuevo`, informa que el desglose no está disponible, sin fabricar un reparto.
Walking queda escrito correctamente. No se instala una segunda fórmula monetaria.

SELECT candidato READ ONLY sobre el universo real: 143 filas antes/después,
36 canales recuperados, cero diferencias en capital, moneda, categoría,
operación o vendedor. Para la captura, el resultado propuesto es:

| Grupo | Importe |
|---|---:|
| Landing | S/ 0 |
| Formulario | S/ 137.500 |
| Referido | S/ 15.000 |
| Walking | US$ 25.000 |
| Cartera | S/ 90.000 |
| Sin origen identificado | S/ 45.000 |

Con TC 3,3776 conserva S/ 371.940. Porcentajes intactos.

## Verificación y límites

- `npm run check`: PASS, 4.740 pruebas/313 archivos, typecheck, build, bundle y
  duplicación. Cuatro avisos de accesibilidad preexistentes en coverflow.
- E2E Docker focal: 2/2 PASS; capturas escritorio/móvil, móvil inspeccionado.
- SQL local de componentes: 13 casos, política inactiva, paridad monetaria y ACL
  del helper PASS. Dependencias sintéticas; NO es replay íntegro de la migración.
- Preflight de lectura productivo: inventario analítico sin pendientes,
  sello válido, declaración existente y techo 14.
- `gate:realidad`: NOT RUN por falta de URL/service role en su entorno.
  El diagnóstico productivo puntual sí se ejecutó con MCP en READ ONLY.
- Pendientes: ensayo completo en rama autorizada, RLS/advisors, aprobación del
  SQL exacto, merge nativo y publicación frontend mediante invocación humana
  de release-crm. Producción permanece sin cambios.

## Revisión independiente

Claude, una revisión efectiva (el primer intento falló por entorno de red):
CHANGES_REQUESTED, confianza media. PRIMARY incorporó guardas de ocurrencia única
en los reemplazos, recuento exacto de la actualización de huella, casos de 15:30 y
23:30 Lima y un grupo accesible alrededor del dl de cartera.

El P1 era condicional a una cadena SECURITY INVOKER: se cerró con lectura viva
de las tres funciones (RPC, ranking_origen_live y lector), todas SECURITY DEFINER
propiedad de postgres; el helper también declara ese propietario. El preflight
ahora comprueba esa cadena. RLS HTTP sigue pendiente del ensayo remoto.

La hipótesis de modificación retroactiva de meses sellados se rechazó con el
cuerpo de ranking_origen_vendedor_fn: su rama cerrada lee exclusivamente
cierre_mes_vendedor.origenes_ranking. No recalcula mediante ranking_origen_live.
El tipo de fecha ya es date por conversión explícita America/Lima; se añadieron
los casos de hora extrema para comprobarlo. No se pidió otra opinión para
obtener PASS; el dictamen original se conserva como CHANGES_REQUESTED con los
hallazgos evaluados por PRIMARY.

Relacionado con [[Ranking - capital por canal de llegada (decision 2026-09-25)]],
[[Ranking cartera - publicacion verificada (2026-09-26)]],
[[Conversion - publicacion verificada (2026-09-27)]] y
[[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]].

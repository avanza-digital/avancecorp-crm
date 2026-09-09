# Solicitud de tasa desde el lead: publicación del 9 de septiembre de 2026

El analista puede solicitar la tasa en «Condiciones de inversión» de la ficha
del lead. Una solicitud pendiente impide convertirlo en cliente de Avance;
Gerencia resuelve en su bandeja habitual. La autorización conserva condiciones,
identidad y vigencia, se enlaza al cliente resuelto y se consume una sola vez
cuando se crea el contrato. La aprobación no crea por sí misma un cliente.

Miguel aprobó el diseño, la implementación, la publicación y después el SQL
concreto y el banco temporal de US$0,01344/hora. La pausa fue reanudada por él.

## Artefactos publicados

| Elemento | Identificación verificada |
| --- | --- |
| Fuente | `8ccb0ca14fcf1f34e8e2158b11b1d88bf519b3f4`, checkout limpio; main original, aislado y avancecorp/main iguales antes de publicar |
| Migración local inmutable | `20260909042103_crm_solicitud_tasa_lead_preconversion.sql` |
| Registro remoto | `20260909165815_crm_solicitud_tasa_lead_preconversion` |
| SHA-256 SQL aprobado | `113a436ec25f13105d7321f527bbeb583d74c09feffb408ab3a8616ea418ca55` |
| Edge productiva | `crm-convertir-lead` v16, JWT requerido, seis archivos iguales a los probados |
| SHA-256 paquete Edge | `7fc27ab95b8253197c5185a3de9894c27509f1b4a66e17c6c0444a24f5153083` |
| Release frontend | `crm-20260909T171132Z-8ccb0ca14fcf` |
| SHA-256 ZIP | `8b1dad132809fb976f53bdd9fe9dba2820ddf38677cd7acc9aa108c195efff7c` |
| Build servido | `build-20260909T171131381Z` |
| Destino | `https://crm.miavance.com/`, Hostinger `u318796122` |

El merge de la rama Supabase incorporó únicamente la migración candidata y el
paquete Edge cambiado. Las otras dieciséis funciones conservaron sus hashes y
configuración. La diferencia de hash entre el paquete Edge del banco y el de
producción se contrastó leyendo los seis archivos: sus bytes coinciden.

El catálogo productivo de 1.353 entradas de funciones/ACL/restricciones coincide
con el banco salvo tres agrupaciones equivalentes de paréntesis en CHECK ya
existentes, producidas por dump/restore. Banderas productivas conservadas:
resolver de identidad ON; escritura de inversiones y ficha neutral OFF.

El despliegue estático se hizo desde el ZIP construido; se eliminó el ZIP del
hosting y se purgó caché. Los ochenta archivos públicos se verificaron contra el
manifiesto, con comprobación en origen para PNG optimizados por CDN. Tres
lecturas sucesivas de versión coinciden. El ZIP devuelve 404 tanto en CRM como
en el dominio del portal. El login público carga sin errores ni advertencias
de consola. No se hizo una conversión de prueba sobre datos productivos.

## Verificación y límites

- PASS: 3.140 pruebas frontend; Playwright local integral 152 PASS / 26 SKIP;
  Edge 67 Node + 5 Deno; checks de scripts y preflights.
- PASS: quince grupos SQL remotos con rollback, HTTP real con ambas banderas
  de identidad, permisos, contraoferta/aceptación, bloqueo antes de efectos y
  estados HTTP exactos. Concurrencia/reversión comprobadas en instancia local.
- PASS: los trece perfiles de prueba ven exactamente sus leads originales.
- PASS: CI [quality y E2E](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/34381294485)
  y [preflight RLS](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/34381294492)
  del commit publicado.
- FAIL: matriz RLS global, 1.775 PASS / 41 FAIL de 1.816 antes; 1.767 PASS /
  51 FAIL de 1.818 después. No son dos bancos limpios idénticos y no se presenta
  este gate como aprobado.
- NOT RUN: recorrido autenticado en producción, por falta de una sesión.
  El flujo se comprobó en el banco y se verificó la equivalencia de SQL y Edge
  y la integridad del frontend servido.

Las diecisiete etiquetas nuevas de la matriz general se analizaron por causa:

1. Diez conteos/conjuntos incluyen ocho leads TRANSIENT legítimos conservados
   por la primera ejecución. La sonda posterior de los siete IDs originales
   pasa con las trece sesiones; RLS de leads y helper de ámbito son idénticos.
2. Cinco comprobaciones presuponen que el cliente de la sonda no tiene domicilio,
   pero la primera ejecución ya lo completó. El propio runner advierte que ese
   bloque no se puede repetir en el mismo banco. Las funciones de domicilio son
   idénticas a producción; la prueba específica usa un cliente nuevo y cubre
   completar domicilio y consumir la aprobación.
3. Una expectativa de quince claves recibe diecisiete. La función de métricas
   correspondiente es idéntica a la versión productiva de partida.
4. D-10 compara la reserva de un argumento contra dos hashes antiguos
   (`test-rls.mjs:9917`). El SQL autorizado añade una validación previa de tasa
   en esa firma (`migración:742`): la igualdad textual dejó de ser una expectativa
   vigente. Las guardas y la compatibilidad ON/OFF pasaron pruebas de comportamiento.

Siete etiquetas anteriores desaparecieron. El PRIMARY aceptó publicar con los
gates específicos y la comparación de catálogo, conservando explícitamente la
deuda del runner global. No se suprimieron fallos para obtener un PASS.

Advisors: tres nuevas RPC authenticated esperadas y una función existente que
pasa a wrapper SQL. Se contrastaron los avisos de DEFINER con ACL/ámbito. Sin
nuevos avisos de rendimiento. La revisión de implementación recibió
CHANGES_REQUESTED; las decisiones y correcciones del PRIMARY están en
[REVISION.md](REVISION.md), sin atribuirle un PASS posterior al reviewer.

## Cierre y recuperación

La rama `tasa-lead-publicacion-20260909`, ref `ehzftpvxuwuzinvkyhzz`, ID
`d14a5bcc-532f-40b5-bdc0-5bc4b51d6618`, fue eliminada y su ausencia comprobada.
Los bancos F5 y F7 se conservaron. No quedan costos de esta rama activa.

El release anterior `crm-20260909T160038Z-baad8cfad3e8` queda respaldado fuera
del web root. La reversión SQL es condicionada al primer uso, como explica
[README.md](README.md); no se debe volver a una UI incompatible con solicitudes
que ya tengan lead ni borrar historial. Si hay uso, corregir hacia delante.

Evidencia saneada en [evidencias/publicacion-2026-09-09](evidencias/publicacion-2026-09-09/).
Respaldo operativo local: `_DEV_NO_SUBIR/pausas/tasa-lead-2026-09-09/publicacion/`.
Después de publicar se integró el avance remoto F5 `327d124` para guardar esta
documentación sin sobrescribir trabajo ajeno; no cambia el commit del artefacto
frontend aquí identificado.

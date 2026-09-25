# Evaluación de Claude — correo de primer acceso

Codex PRIMARY; Claude SECONDARY_REVIEWER/auditor RLS mediante `scripts/claude-review`,
sin herramientas ni escritura. Dos consultas LEVEL 3: arquitectura y SQL/código exacto.
No se solicitó otro dictamen para buscar aprobación. Ambos dictámenes fueron
CHANGES_REQUESTED; las decisiones y comprobaciones finales corresponden al PRIMARY.

## Hallazgos aceptados

- **Auth creado sin perfil + contacto distinto bloqueaba la UI.** Reproducido y
  corregido: el resultado autorizado agrega `acceso_creado`; UI permite completar
  y explica gestión de credenciales. Test de componente y GoTrue/Edge HTTP PASS.
- **Cambiar otro campo podía restablecer un correo importado.** Test HTTP RED con
  el candidato anterior, GREEN con trigger limitado a INSERT/cambio real de email.
  «Conservar correo» ahora es una operación explícita de la RPC, sin GUC de bypass.
- **Vaciar contacto antes de Auth fallaba.** Test HTTP RED/GREEN: se conserva el
  contacto vacío, solicitud pendiente intacta; el gate pide revisar antes de Auth.
- **Lock excesivo.** `FOR NO KEY UPDATE NOWAIT` basta para correo, mantiene protección
  contra upgrade circular y permite FK concurrente. `55P03` vuelve al editor porque
  es un rechazo transaccional definitivo. Carreras y prueba UI correspondientes PASS.
- **Versionar hash idéntico.** Helper no incrementa CAS si no cambia la huella.
- **Solicitud sin alta_portal.** La decisión de sincronizar exige objeto alta_portal.
- **Saga por claim sin índice.** Lectura usa su clave de persona y valida claim.
- **Reversión.** MD5 finales medidos, preflight fijado, poscondición comprueba tres
  cuerpos restaurados al byte. Ensayo con ROLLBACK PASS; guard Auth conservado.
- **Errores de refresco.** Refetch incidental no reemplaza el error de corrección.

## Decisiones razonadas

- `inversion_payload_acceso` sigue IMMUTABLE: `inversion_datos_portal` está declarado
  IMMUTABLE en el cuerpo de producción y en el banco; no hubo evidencia de mutabilidad.
- La autorización para sincronizar desde ficha es la RLS existente, conforme al pedido
  de Miguel. La sincronización no concede emitir inversiones ni acceso a otra persona;
  reclamar/confirmar siguen verificando identidad, ámbito, operador y responsable.
  Matriz HTTP de ocho roles: PASS. No se agregaron permisos a coordinador/directorio.
- No se acepta omitir el guard para una solicitud cancelada: permitirlo habilitaría
  una petición Auth atrasada que el candado debe rechazar. Una reutilización de claim
  cancelado por otra puerta requiere conciliación explícita, no un fail-open.
- No se crea un índice nuevo sobre Auth para este fix. El índice sobre solicitudes
  hace la selección del claim; sigue pendiente medir el crecimiento de Auth antes de
  proponer una optimización de su metadata.
- No se altera `test-rls.mjs` global: la matriz nueva está en `http.test.mjs` y usa
  PostgREST real; el gate global completo sigue pendiente en branch hospedada.

## Contrato de respuesta y publicación

Censo de producción en lectura: el resultado privado lo usan cancelar, corregir,
revisar, consultar y el núcleo de preparar. Todas sus rutas usan el esquema
`SolicitudInversionSchema`. El esquema es `v.object`; el campo aditivo opcional no
rompe al frontend anterior. Se inspeccionó también el bundle vivo de
`build-20260925T150218036Z`: `index-B9FsUGcG.js` define `Yv=V({...necesita_portal...})`,
con `V` importado como `Ka` de `crm-api-Ca16g9BU.js` (constructor `object`, no strict).
No se encontró su manifiesto en el directorio releases de este checkout; por eso
esta evidencia es del artefacto vivo, sin atribuirle un commit no comprobado.

El SQL se instala antes que el frontend. El banco local usa GoTrue real y verifica
que la escritura de metadata forma parte de la misma transacción (sin usuario por
correo al rechazar). **Pendiente antes de producción:** repetir garantía de ausencia
de huérfano con GoTrue hospedado, permisos del trigger sobre Auth, matriz RLS global
y advisors en branch autorizada. Se mantiene este bloqueo de despliegue; la revisión
local no se presenta como validación hospedada.

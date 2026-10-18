# Conversión: referidos activos y frontend publicado

Estado al 13/10/2026: **REGLA ACTIVA, FRONTEND PUBLICADO E HISTORIAL INTEGRADO EN MAIN.** La PR #266 quedó fusionada mediante merge commit el 13/10 a las 19:22:01 UTC.

Miguel autorizó validar y activar la regla en Supabase y publicar con `$release-crm`.
La PR #259 ya está fusionada. El límite mensual conjunto es el 15 % del total de
cierres referidos válidos de cada analista, sin redondeo hacia arriba. Se conserva
el orden cronológico de admisión; no es «0,15 % por cierre». Para el mecanismo de
ajustes de referidos sellados, la reducción de cuatro a tres cierres válidos
equivale a 0,15 (límite de 0,60 a 0,45). Esto no habilita nuevas anulaciones en
meses sellados: las puertas normales las rechazan; la excepción administrativa
conserva su auditoría y no crea un ajuste nuevo.
Renovaciones aportan cero. Divisor y reglas de upgrades conservan su definición.

## Activación y comprobación

- Migración local `20261012220959_crm_conversion_limite_total_referidos.sql`; versión remota `20261012232305`.
- SHA-256 SQL: `72ef4f4485447d3fb6956b08171d2d9e94700cfd6c4018d96fd4a7015da3bcc7`.
- Validación en rama temporal: 43 aserciones SQL, 319 de RLS/Auth y 44 de HTTP, todas PASS. Advisors sin alertas nuevas respecto a producción; 23 Edge Functions conservadas.
- Después del merge: octubre conserva divisor 833, sus cinco referidos válidos aportan 0,75 en conjunto y el numerador pasa de 44 a 41,75. Renovaciones: 0.
- Agosto/septiembre sellados conservan las mismas huellas de períodos y fotos. Las nueve combinaciones de acceso directo a la columna nueva siguen denegadas.
- Rama Supabase propia `76ac37c2-5026-43e1-88bf-83defc045da4` / `jcmotyosqstvbyyrpdwe` eliminada después de verificar producción.

## Frontend publicado

- Sitio: https://crm.miavance.com
- Commit fuente: `767e04447c94471b1b78cc05e43ced41b1c58278`.
- Artefacto: `crm-20261013T175343Z-767e04447c94.zip`.
- SHA-256 ZIP: `8b8428fa0d5dd6942739980de7b8ef80e02ab6e5d51ad71c2a1e72c6e83db524`.
- Versión publicada en esta intervención: `build-20261013T175342472Z`. Esta acta conserva esa evidencia histórica; una publicación posterior puede cambiar la versión viva.
- Gate integral: PASS, 6.660 tests, lint, tipos, build y bundle. E2E local Docker: **411 passed, 26 skipped, 0 failed** en 16,6 minutos.
- El árbol de `app` del commit publicado `767e0444` coincide con el commit verificado `b3f258bf`; los cambios entre ambos no modifican el frontend. Artefacto de fuente limpia, verificación del ZIP y preflight PASS.
- Smoke a las 17:55:38 UTC: portada y script principal HTTP 200; **123 archivos JS/CSS/HTML/versión con SHA-256 exacto**, cero diferencias.
- Recuperación conservada: `crm-20261013T153935Z-33a701156385.zip` y su manifiesto. Un rollback requiere decisión humana según el procedimiento vigente.

## Historial integrado

El preflight inicial rechazó Main porque el commit vivo `33a701156385` había
llegado con squash. Se utilizó la excepción de rescate de `CLAUDE.md`,
conservando los historiales y los cambios del Main de ese momento, `b85acb70`.
La [PR #265](https://github.com/avanza-digital/avancecorp-crm/pull/265) se fusionó
con squash como `c19fe165`, por lo que no conservó los ancestros publicados.

El pendiente quedó resuelto mediante la
[PR #266](https://github.com/avanza-digital/avancecorp-crm/pull/266), fusionada
el **13/10/2026 a las 19:22:01 UTC** con el commit
`6cffe735b96bef07c41458c58dcdfebd2e437719`, de dos padres. La comprobación de
ancestría confirmó que tanto `767e04447c94471b1b78cc05e43ced41b1c58278`
(publicación de esta intervención) como `33a7011563853baa86a50f43e610323716ac164e`
(publicación anterior) están contenidos en `avancecorp/main`.

Main verificado: `4ec46ba30838559142320692aa137305454a62d8`. No queda una fusión pendiente para
conservar el historial de esta publicación.

## Figma y entrega de pantallas

[Diagrama para Gerencia](https://www.figma.com/board/tO6Lpx3ieJ6QuwUxfZcSvM?node-id=50-19)
actualizado a ACTIVO y revisado visualmente. Contiene divisor, exclusiones,
numerador, límite, anulaciones y ejemplo completo.

Las dos anotaciones manuscritas de Miguel quedaron explicadas al costado:

- **«¿Qué ajustes tenemos pendientes?»**: tarjeta `79:115`, con definición de
  los ajustes ya registrados, descuento sobre el numerador, mínimo cero,
  saldo que puede pasar a otro mes y ejemplo de 10 menos 1 = 9. El divisor se
  conserva. Se aclara la restricción de anulaciones en meses sellados.
- **«Cuenta en empresa, sin analista»**: tarjeta `79:126`, con ejemplo de diez
  llegadas, ocho asignadas y dos sin asignar: divisor de empresa 10 y suma de
  divisores individuales 8. Se explica la primera asignación en un mes abierto
  y que una reasignación no duplica el lead.

Consulta de solo lectura del **13/10/2026 a las 13:35:14, hora de Lima**:
**0 ajustes pendientes**, aporte pendiente 0, 0 analistas con ajustes y
**0 leads automáticos de octubre sin primera asignación**. Son cifras del
momento de la consulta. Ambas tarjetas se verificaron visualmente, sin
texto desbordado.

[Comentario de implementación para pantallas](https://github.com/avanza-digital/avancecorp-crm/pull/259#issuecomment-6134503413).

Evidencia estructurada: `CRM-Avance-Corp/supabase/scripts/conversion-limite-referidos/publicacion-20261013.json`
y `smoke-publicacion-20261013.json`. No se modificó la migración versionada.

Esta nota actualiza el estado histórico de
[[Conversion - limite total de referidos y anulaciones (2026-10-12)]].
Relacionadas: [[Como se mide la conversion del asesor]],
[[Conversion mensual - definicion cerrada]], [[Inicio]].

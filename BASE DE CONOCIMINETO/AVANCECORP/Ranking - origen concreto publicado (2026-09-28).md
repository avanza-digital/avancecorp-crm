# Ranking — origen concreto publicado (28/09/2026)

Continuación de [[Ranking - correccion auditada de Otro (2026-09-28)]] y
[[Ranking - origen acreditado y desglose de cartera (2026-09-28)]].

## Resultado y alcance

Las siete reclasificaciones autorizadas anteriores quedaron auditadas. Dos fueron
confirmadas como Formulario; cinco se distribuyeron administrativamente entre
Formulario y Landing por indicación expresa de Miguel, sin afirmar que su canal
histórico estuviera acreditado. Esta distinción permanece en notas y auditoría.

El último contrato real sin origen, PEN 10.000, recibió la confirmación expresa
Landing. Se validó su fuente exacta: la pregunta previa contenía un número de
contrato transcrito incorrectamente. La corrección usa el registro real único
por cliente, vendedor e importe. Datos personales y UUID solo en la evidencia
privada y auditoría de producción.

No se creó un lead retroactivo. La transacción comparó contratos, cuotas,
externos, cartera, episodios, leads, fotos, stock sin origen y conversión mensual:
todos íntegros. La confirmación de este último caso no altera la conversión;
las siete reclasificaciones previas sí se rigen por su política de conversión,
según el acta anterior.

Consulta productiva final: **cero operaciones de capital de septiembre en Otro o
sin_origen**. No se afirma que todos los meses históricos hayan sido saneados.
Cartera conserva Renovación, Upgrade y Nueva inversión según lo registrado.

Nuevas altas manuales: Landing, Formulario, Referido o Walking. Otro y origen
vacío rechazados en cliente, RPC y trigger INSERT. Los canales concretos legados
se mantienen para integración/lectura; editar datos históricos no los reclasifica
silenciosamente. Las confirmaciones administrativas requieren mantenimiento SQL
autorizado; los roles API no tienen CRUD. Actor atribuido declarativamente a
Gerencia, con evidencia de autorización y auditoría.

## Publicación real

- SQL: 20260928192822, 20260928192823, 20260928193048, 20260928194818;
  merge nativo de rama, historial productivo 383 → 387.
- Rama de pruebas autorizada eliminada; ausencia confirmada con list_branches.
- Control analítico: cero pendientes/sello válido; 22 Edge Functions intactas.
- Fuente frontend: `5ccb30ac54f5fc85386efb7908ca282c2efb6245`, árbol limpio.
- Base viva preservada: `3c481f7f1a4f`, incluida la segunda publicación de Hoy.
- Artefacto: `crm-20260928T195628Z-5ccb30ac54f5.zip`.
- SHA-256: `759391f20657705202e79de6d21f31535e5da736ea285ec7ceb8195ccbbe3d08`.
- Build vivo: `build-20260928T195627661Z`.
- Destino: https://crm.miavance.com, Hostinger MCP oficial 2.x.
- Preflight PASS; smoke 99 archivos SHA-256/HTTP 200 PASS a las 20:03 UTC.
- Recuperación conservada: ZIP `crm-20260928T194324Z-3c481f7f1a4f.zip`.

## Commits, revisión y checks

Código de integración: `9a7d26e43030`; rescate publicado: `5ccb30ac54f5`.
El preflight rechazó la línea GitHub por no descender del commit vivo. Se creó una
copia aislada desde ese commit, se aplicó el cambio propio y se reconstruyó.
La rama de rescate ya se fusionó al main local, conservando archivos ajenos sucios.
No se empujó al repositorio CRM el historial local ajeno de portal/Gloria.

PR [#126](https://github.com/avanza-digital/avancecorp-crm/pull/126): código y acta.
La regla GitHub exige una revisión aprobatoria y Code Owner; fusión pendiente de
esa revisión, sin usar bypass de administrador. El despliegue ya está realizado.

Claude SECONDARY_REVIEWER: CHANGES_REQUESTED, hallazgos evaluados/corregidos por
PRIMARY. Matriz RLS/Auth/HTTP real, puente y modelo de confirmación: PASS.
Check del código exacto combinado: **4.768 tests / 313 archivos PASS**, lint,
tipos, build y bundle. E2E Docker final **34/34 PASS**. La corrida completa inicial
había tenido dos expectativas antiguas de Otro; sus archivos corregidos pasaron
25/25 y nuevamente 34/34 en la fuente final. No se oculta esa corrida inicial.

Detalle reproducible y recibos saneados:
`CRM-Avance-Corp/docs/auditorias/origen-concreto-20260928/`.

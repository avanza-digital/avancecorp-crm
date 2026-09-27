---
tags: [crm, conversion, release, verificado]
fecha: 2026-09-27
estado: publicada; SQL y conciliacion activos; smoke HTTP PASS
---

# Conversión — publicación verificada

Entrega de [[Conversion - fecha comercial y plazo de registro (propuesta 2026-09-26)]].
Conserva las decisiones de [[Ranking - conversion sin capital por clientes previos (2026-09-26)]]
y [[Ranking cartera - publicacion verificada (2026-09-26)]].

## Resultado productivo

- SQL integrado mediante merge nativo de la rama autorizada; nunca apply directo
  ni db push productivo. Versiones `20260927073637` y `20260927080006`: historial
  374 → 376, únicamente esas dos diferencias.
- Conciliación exacta autorizada activada el **27/09/2026 03:35:26 Lima**:
  108 episodios, 106 fuentes enlazadas, **97 acreditadas, 9 fuera de plazo y
  2 pendientes sin fuente**. Ninguna recepción antedatada.
- Vigencia desde septiembre de 2026. Mes de cierre comercial; confirmación y
  vínculo antes de las 00:00 del día 11 siguiente en Lima. Una carga tardía
  no gana crédito en el mes original ni en el de carga.
- Los cinco caminos de conversión coinciden: numerador ponderado 89,
  divisor 1423, **6,25 %**. No confundir 97 acreditaciones con el numerador
  ponderado, que aplica las reglas vigentes de origen.
- 661 contratos y 5784 cuotas conservan exactamente sus huellas antes/después.
  Cierres de enero–agosto idénticos. Cero sellos; Cron de cierre sigue OFF.
  Las 22 Edge Functions conservan exactamente su inventario, versiones y fechas.
- Tablas de hechos y activador sin acceso directo para anon, authenticated
  ni service_role. No se ampliaron permisos.

## Fuente y publicación

- PR [#113](https://github.com/avanza-digital/avancecorp-crm/pull/113), integrada
  por `miguejbs98` a las 08:28:24 UTC. La API no devolvió reviews; no atribuir
  una aprobación revisora que no figura. No se hizo merge admin desde el agente.
- Commit de fuente: `88db9ebf5e0848fb351862fb22ea376b597d83b6`.
  Main de la copia limpia y `avancecorp/main` iguales antes de construir y subir.
  Árbol idéntico al candidato probado `b4cedebbee284e4985399d0aef24f635f5238811`.
- URL: https://crm.miavance.com
- Build vivo: `build-20260927T083428413Z`.
- ZIP: `CRM-Avance-Corp/releases/crm-20260927T083429Z-88db9ebf5e08.zip`.
- SHA-256: `9f6703795498aa0e9ae7b571cbef9842f7ac64673cbca3bd677d9240cc2dee03`.
- ZIP y manifiesto conservados también en el workspace principal, fuera del
  web root. Fuente limpia en `/private/tmp/conversion-release.dliXK7`.
- Preflight obligatorio PASS; artefacto verificado PASS; Hostinger aceptó
  despliegue. **Smoke HTTP PASS: portada 200 y 80 JS/CSS/index/version con
  tamaño y SHA-256 idénticos al manifiesto**, sin parámetros anticaché especiales.
- Recuperación anterior conservada: `crm-20260926T214044Z-526d6d90c621.zip`,
  SHA-256 `c624754aa2bf8494004da06bb119642603099629d0b14d2be3f4fb706a358fc1`.
  No ejecutar rollback sin decisión de Miguel y el procedimiento de preflight.

## Verificación real

- Baseline remoto: 2267 aserciones / 0 fallos, PASS.
- Candidata inactiva: 2267 / 0, PASS.
- **Candidata activa final: 2268 / 0, salida 0, PASS**.
- Escritores HTTP/Auth/Storage: 15/15 PASS; estados y plazo HTTP: 5/5 PASS.
- Diez suites SQL, cinco mutantes y once carreras reales: PASS.
- Reversa remota ensayada con rollback: PASS, hechos preservados.
- Tipos integrales generados de la rama; npm run check: 4468 tests/301 archivos,
  lint/typecheck/cobertura/build/bundle PASS. Precommit/prepush y CI verify PASS.
- E2E Docker: 275 passed, 26 skipped, 1 flaky que pasó al reintentar.
  Focal Gestión Diaria posterior: 11/11 sin reintento. No E2E en GitHub.
- Revalidación nominal inmediatamente anterior a activar: 108 entradas,
  cero divergencias, cero episodios nuevos o identidades repetidas, mes abierto.
- Se reutilizó evidencia del mismo árbol: no se repitieron bancos por el squash.

## Límites, incidencias y transparencia

- El control analítico global conserva **cuatro hallazgos anteriores** idénticos:
  `crm.impacto_eliminacion_usuario_fn`, `private.ranking_capital_origen_filas`,
  `private.ranking_conversion_origen_mes` sin declarar, y huella anterior de
  `crm.contrato_eliminar_auditado`. **No se declara ese control PASS.**
  El complemento aprobado resuelve solamente los tres hallazgos del cambio;
  no eleva el techo ni oculta o modifica los cuatro ajenos.
- Advisors del banco: 304 → 306 seguridad, sólo dos INFO nuevos de tablas
  internas con RLS y deny-by-default; rendimiento sin nuevos hallazgos.
  Producción: 307 avisos de seguridad y 206 de rendimiento. La diferencia WARN
  con el banco es `pg_net` en public, objeto que esta entrega no modifica.
  No declarar el inventario global limpio. Referencias:
  [RLS sin policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
  [extensión en public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public).
- Claude: dos consultas consumidas; dictamen de implementación CHANGES_REQUESTED.
  PRIMARY corrigió y comprobó los hallazgos aceptados; no se inventa un PASS posterior.
- Primer build rechazado por falta de entorno en la copia limpia; el intento
  con `node --env-file --run` tampoco propagó el entorno al gate. Diagnóstico
  de variables sin imprimir secretos; carga mediante Node y spawn explícito
  con env conservado resolvió el empaquetado. Sólo se subió el artefacto PASS.
- El merge nativo es asíncrono: la primera lectura aún mostraba 374 migraciones;
  se esperó y se verificaron 376 antes de activar. No se repitió la escritura.
- Recorrido visual productivo **NOT RUN**: el conector de navegador no pudo
  iniciar su proceso local. HTTP/bytes sí PASS; no se crearon datos reales de prueba.
- Se usaron las habilidades `release-crm`, Supabase y sus controles; Context7
  sustentó la documentación de la fase de ensayo. No se actualizaron herramientas.

## Evidencia y limpieza

Evidencia privada: `/private/tmp/conversion-fecha-remoto.xjLqBU`, incluido
`matriz-activa.log`, `verificar-publicacion.mjs` y respaldos sintéticos.
El SQL de activación nominal permanece fuera de Git; SHA-256
`c21f972579a422e79455894ee2e139d080f65a31dde35068e2ee8a03154855ce`.

Rama exclusiva `conversion-fecha-20260927`
(`d16e1e75-5ade-45c0-b460-5edbc6778b5f`) eliminada tras el smoke PASS;
ausencia confirmada por listado nativo. Se retiró únicamente el banco sintético,
recuperable mediante los respaldos locales conservados. Otros bancos intactos.
Ventana aproximada 06:09–08:40 UTC, unas 2,52 h a US$0,01344/h:
**US$0,034 estimados**, no una factura. Ya no sigue generando coste de rama.
Acta resumida registrada también en el
[comentario de la PR #113](https://github.com/avanza-digital/avancecorp-crm/pull/113#issuecomment-5854286748).

Esta acta es posterior al artefacto: no atribuirle otro commit al despliegue,
ni volver a publicar únicamente por documentación.

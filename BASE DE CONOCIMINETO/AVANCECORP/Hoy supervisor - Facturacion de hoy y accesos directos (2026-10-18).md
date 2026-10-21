---
tags: [crm, hoy, supervisor, navegacion, release]
actualizado: 2026-10-18
estado: publicado-verificado
---

# Hoy supervisor - Facturacion de hoy y accesos directos (2026-10-18)

**Estado vigente: PUBLICADO el 18/10/2026 a las 18:20:40 Lima**, en https://crm.miavance.com/. «Facturación de hoy» abre Facturación; «Llamadas de hoy» abre Gestión Diaria desde título, cifra y acción. Se retiró el texto «Hora de Lima» conservando el cálculo horario comercial.

PR #330 integrado en Main `6ace3d441bd874a1e06613ee5718b1023e08c39d`. Build `build-20261018T231939891Z`; ZIP `crm-20261018T231940Z-6ace3d441bd8.zip`, 2,602,418 bytes. SHA-256 `d86eee8f9a799ff93b5d6bc6a5cceeb4fef92cba67351d2b524b2060d1ab906d`. Main local y remoto iguales, fuente limpia y preflight PASS sobre el vivo anterior `2686f755`.

PASS: check completo (7.262 pruebas) y 3 E2E locales, reutilizados porque el árbol completo de Main es idéntico al commit probado `d686a755`; nuevo build/verificación del ZIP; 127/127 JS/CSS, 165/165 HTTP 200 y acceso público escritorio/móvil. La comparación binaria completa conserva FAIL 153/165 por doce PNG del CDN, idénticos en fuente y entrega al diagnóstico del release anterior. Recorrido con sesión productiva NOT RUN. El gate de realidad original no pasó: configuración faltante y 42501 en el intento alternativo; la lectura SQL complementaria conserva su carácter de evidencia adicional.

Acta: `CRM-Avance-Corp/releases/hoy-supervisor-2026-10-18/publicacion-accesos-2026-10-18/PUBLICACION.md`. ZIP y manifiesto del anterior publicado `2686f755` conservados en `rollback/`. Un solo despliegue; sin cambios SQL, DNS, credenciales ni datos reales. No se consultó a Claude para este ajuste LEVEL 1; CodeRabbit SUCCESS en el PR integrado.

[[Hoy supervisor - publicado y verificado (2026-10-18)]] · [[Hoy supervisor - QA previo al release y correccion de pendientes (2026-10-18)]] · [[Inicio]]

## Historial previo a la publicación

Las menciones a bloqueo, pendiente o «no publicado» que siguen describen el estado anterior. Quedaron resueltas por la publicación registrada arriba.

Después del release, Miguel pidió renombrar «Resultados de hoy» a **«Facturación de hoy»** y abrir Facturación al pulsarlo. **«Llamadas de hoy» abre Gestión Diaria**. Se retiró «Hora de Lima» de la cabecera; la fecha conserva su zona horaria comercial.

Título, cifra y acción inferior enlazan al módulo correspondiente. Se retiró el modal de resultados que ya no se abre. Los importes, cálculos, estados vacíos y errores conservan su comportamiento; el acceso al módulo sigue disponible aunque no haya cifras.

Aplicado en el taller original y en la copia de Main `2686f755` usada para verificar. PASS: lint, tipos/build, 32 pruebas relacionadas, 3 E2E en Docker local y diff sin errores. El primer E2E detectó un selector que aún esperaba «Resultados de hoy» como botón; actualizado, los tres casos pasaron. Gate de realidad NOT RUN: falta `SUPABASE_URL` en esa copia. Riesgo LEVEL 1, sin consulta secundaria.

**Ajuste confirmado en `d686a755`, PR #330 abierto; publicación pendiente de integración.** Parche mínimo sobre Main y validación inicial en `CRM-Avance-Corp/releases/hoy-supervisor-2026-10-18/ajuste-accesos-2026-10-18/`. La versión publicada continúa siendo la del acta anterior; el ZIP publicado no se modificó.

[[Hoy supervisor - publicado y verificado (2026-10-18)]] · [[Hoy supervisor - QA previo al release y correccion de pendientes (2026-10-18)]] · [[Inicio]]

### Aclaración y comprobación de datos posterior

Miguel preguntó por qué faltaba la URL. La aplicación sí tiene `VITE_SUPABASE_URL` en su configuración local; la invocación del script esperaba `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` en el proceso. Además, al contrastar su acceso con el rol `service_role` se obtuvo 42501 por falta de SELECT sobre `crm.periodos_cerrados`. No se concedieron permisos ni se cambiaron credenciales.

Se midieron los mismos diez supuestos mediante el conector Supabase existente, con SQL READ ONLY y ROLLBACK, a las 20:40 UTC. Lectura completa: 26 periodos de metas, 0 vendedores sin supervisor activo, 4.070 leads, 29.982 actividades, 1.910 tareas pendientes, 31 miembros operativos y 0 revisiones anómalas bajo el sello. Conversión coherente en las cinco lecturas: 6,25 %, numerador 77,4 y divisor 1.239. Persisten las dos observaciones ya conocidas: 273 clientes sin domicilio legal y 45 ventas de analistas de baja. No se modificaron esos datos.

Es una comprobación SQL complementaria, no un PASS del script original ni una sesión HTTP de usuario productivo. Evidencia en `ajuste-accesos-2026-10-18/realidad-sql-complementaria.json` y `.sql`, junto al parche. El ajuste de nombres y enlaces sigue sin publicar.

### Release autorizado y bloqueo de integración

Miguel invocó `$release-crm` para este ajuste. Codex ejecutó `npm run check` completo: **PASS**, 450 archivos y 7.262 pruebas, más lint/tipos/cobertura/configuración/SW/build/bundle/duplicación. Los 3 E2E locales corresponden a los mismos archivos. Commit `d686a75528a0098789c0472822b82e97b13aab28`, rama de cambio `fix/hoy-accesos-modulos-20261018`, [PR #330](https://github.com/avanza-digital/avancecorp-crm/pull/330).

GitHub exige revisión y marca el PR `REVIEW_REQUIRED` / `BLOCKED`. La fusión normal con `--match-head-commit` fue rechazada por la política de Main. El preflight remoto pasó; los demás controles seguían en curso. No se usó `--admin` ni se alteraron reglas. El repositorio tiene fusión automática deshabilitada.

**No publicado.** ZIP definitivo y smoke posterior NOT RUN hasta integrar el cambio en Main. Main y el vivo siguen en `2686f755` / `build-20261018T200426345Z`. Se conservaron el ZIP anterior y el manifiesto como recuperación y se verificó la conexión Hostinger. Acta y evidencia: `CRM-Avance-Corp/releases/hoy-supervisor-2026-10-18/publicacion-accesos-2026-10-18/ESTADO-RELEASE.md`. Cuando el PR se integre, continuar el release ya autorizado desde el nuevo Main; comprobar equivalencia con el árbol probado `e3021d83870add578dfac9354dd9eea59301416a`, construir, verificar, ejecutar preflight, publicar y hacer smoke. No hace falta solicitar de nuevo autorización para publicar este ajuste.

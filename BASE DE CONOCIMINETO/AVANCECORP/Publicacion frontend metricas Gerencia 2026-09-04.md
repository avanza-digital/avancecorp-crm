---
tags: [crm, gerencia, metricas, deploy, main]
fecha: 2026-09-04
estado: frontend-publicado-y-verificado
verificado: "2026-09-04 23:49 America/Lima"
---

# Publicación del frontend de métricas de Gerencia

Relacionado con [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]], [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]], [[Main unico - sincronizacion y publicacion 2026-09-04]] y [[Deploy a Hostinger]].

## Autorización y alcance

Miguel pidió «commit a todo y deploy al frontend» después del cierre del punto 3. Se autoriza guardar el trabajo actual, sincronizar Main con `avancecorp/main` y publicar exclusivamente el frontend del CRM en `crm.miavance.com`.

- Incluir las correcciones y pruebas de Gerencia/Cartera, el inventario y requerimiento, y el trabajo concurrente presente en Main, sin sobrescribirlo.
- El SQL del punto 3 ya está aplicado como `20260905034917`; **no reaplicarlo**. Guardar archivos SQL o tipos generados no autoriza ejecutar migraciones adicionales.
- No publicar el portal `miavance.com`, no modificar autenticación, núcleos, permisos, Edge Functions ni datos de negocio.
- No crear ramas ni forzar historia. Confirmar el mismo commit local/remoto antes de construir y publicar un artefacto limpio de ese commit.
- Los puntos 4 y 5 del plan siguen pendientes; esta publicación no los da por resueltos.

## Línea base y reversión

Al comenzar, Main local estaba en `ed2b7ea` y `avancecorp/main` en `c477fec`; la actualización remota no encontró cambios divergentes. Se preserva el commit concurrente «Altas nuevas por analista» y los archivos locales.

El servidor estaba sirviendo `build-20260905T011157779Z`, correspondiente a `b8108ae3f4dca59be3c833ed039ca819235da6dd`.

Reversión frontend disponible fuera del directorio público:
`CRM-Avance-Corp/releases/crm-20260905T011158Z-b8108ae3f4dc.zip`, SHA-256 `c9fdcb382438a9f7d0eac3415942c16cd4075d82d2fcb15b171f6158f151a8a2`, con manifiesto hermano. No se revierte la exclusión SQL de pruebas por revertir el frontend.

## Comprobaciones previas

- La entrega local aprobó 2.741 pruebas y 120 E2E (26 omisiones previas) sobre una huella estable de código; tipos, build, bundle y duplicación aprobados.
- Revisión acotada de secretos en los 66 archivos modificados/no versionados iniciales: ninguna llave privada, token de GitHub, llave secreta Supabase ni JWT `service_role` detectado. No equivale a una auditoría integral de secretos.
- Configuración pública productiva presente y del proyecto correcto; credencial de rol `anon`, sin exponer su valor. Comprobada nuevamente dentro del artefacto final.
- Context7 confirmó que Vite fija la configuración al construir y que la preview debe usar el `dist` producido. La guía de Supabase orienta la exclusión de llaves privilegiadas; Browser se usa para revisar acceso e interfaz, no para extraer credenciales.

## Resultado

**Publicado y verificado en `https://crm.miavance.com/` el 4 de septiembre de 2026, antes de las 23:49 America/Lima.** Sólo frontend; no se ejecutó SQL adicional, no se publicaron Edge Functions ni se cambiaron datos de negocio o autenticación.

### Main y artefacto

- Commit de implementación: **`50f33a59b92b2263296863c857e4ef3e39619450`**; contiene los 67 archivos de la entrega, documentación y trabajo concurrente preservado. Main local y `avancecorp/main` coincidían y el árbol estaba limpio antes del build y antes del deploy. Se hizo push normal al repositorio privado `avanzadigitald/avancecorp-crm`; no se usó `origin`, ramas nuevas ni force push.
- Construcción reproducible en un worktree limpio separado, con HEAD separado, del mismo commit; instalación bloqueada por lockfile y configuración pública productiva inyectada sin copiar `.env` ni imprimir credenciales. La app publicada no contiene llaves privilegiadas ni fixtures demo según los gates del artefacto.
- Release: **`crm-20260905T043212Z-50f33a59b92b`**. Build: **`build-20260905T043211512Z`**. Entry: `assets/index-CzsdYbLC.js`.
- ZIP: **1.903.645 bytes**, SHA-256 **`131f17db0f2cf1fe1d0dc33d57cea1cd5209269e5a13c329b457469a83e1ef67`**. Archivo y manifiesto conservados en `CRM-Avance-Corp/releases/`, fuera del directorio público.
- `.htaccess` coincide con el release anterior. La ascendencia desde el commit que estaba vivo, la configuración pública, Ficha 360 y el manifiesto se verificaron antes de publicar.
- Esta nota es evidencia posterior del despliegue: el commit documental de cierre no requiere otro build/deploy si conserva exactamente el árbol de aplicación de `50f33a5`. No confundir el commit que registra la evidencia con el commit fuente del artefacto.

### Pruebas y publicación

- Hooks de commit/push y cobertura sobre el checkout del commit candidato: **2.741 pruebas aprobadas en 191 archivos**. Tipos, build, integridad del release, bundle y pruebas de configuración aprobados. No se modificaron dependencias para publicar.
- GitHub Actions del commit: [CRM app quality, ejecución 33944726961](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/33944726961), calidad y E2E aprobados: **120 E2E, 26 omisiones preexistentes, sin fallos**. [CRM RLS preflight, ejecución 33944726978](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/33944726978), aprobado; sólo preflight offline y pruebas puras, no semillas ni escrituras productivas.
- Persisten avisos no bloqueantes de lint en `coverflow-carousel.tsx`, tamaño de bundle/importación de demo-config y mantenimiento de Actions. Dos archivos SQL verbatim tenían una línea vacía final adicional; se preservaron, sin alterar sus cuerpos para esta publicación.
- Se confirmó por lectura el dominio CRM, la cuenta y la raíz `/home/u318796122/domains/crm.miavance.com/public_html`. El conector nativo de esta sesión no encontraba los dominios; se utilizó el MCP oficial de Hostinger con la credencial local ya documentada y validada, sin exponerla. Se publicó únicamente en esa raíz y se purgó su caché.
- Verificación remota: **79/79 comprobaciones**, sin fallos: 64 hashes exactos, 12 imágenes HTTP 200 (optimizadas por Hostinger), `.htaccess` 403 y ZIP 404 en CRM y portal. Además, tres lecturas consecutivas del build nuevo coincidentes y `miavance.com` HTTP 200, sin el marcador del build CRM.

### Acceso e interfaz reales

- Preview del artefacto exacto: acceso visible, correo/contraseña y botón Entrar habilitado; sin errores de consola. No se introdujeron credenciales.
- Producción, con la sesión de Gerencia ya existente: **Resumen, Conversiones y Cartera cargan sin errores de consola**; la sesión se conserva después de recargar. Esto verifica esa sesión y la pantalla de acceso; no equivale a probar un inicio de sesión nuevo con credenciales ni todos los roles.
- Resumen y Conversiones: rango 1–4 de septiembre, conversión 3,90 %, base automática 231 y 243 llegadas únicas (231 automáticas, 11 manuales, 1 referido). Se distinguen los 6 cierres de esas llegadas observados hasta hoy. Landing/Formulario/Referido, pesos y alcance de filtros visibles.
- Conversiones muestra «Reunión o avance posterior» (25) y «48 con señal de agenda o avance posterior · no confirma asistencia». Los gráficos indican semana de llegada y resultados hasta hoy, sin afirmar citas reales ni cierres ocurridos esa semana. Captura visual de la pantalla publicada inspeccionada.
- Cartera: 420 clientes; septiembre muestra capital contractual cerrado de S/ 471,1 mil y US$ 14 mil, identificado como mensual. «Todos los meses», una vez finalizada la transición visual, muestra S/ 19.485,4 mil y US$ 1.075,2 mil, redondeos coherentes con la conciliación SQL previa; 3 por vencer. «Sin analista» conserva su criterio de listado, no se certifica como equivalente al campo homónimo del resumen.
- Observación para el punto 5: una captura inmediatamente después de cambiar el mes a «Todos los meses» registró importes negativos transitorios; la lectura posterior quedó en los saldos positivos esperados. No se certifica todavía la causa ni su duración; revisar la transición visual y su regresión en la conciliación integral, sin alterar fórmulas por este hallazgo. No se cambió código adicional durante la publicación.

Los puntos **1–3 quedan guardados y su frontend publicado**. Los puntos **4 y 5 siguen pendientes**; estas comprobaciones de publicación no sustituyen el cierre integral del plan.

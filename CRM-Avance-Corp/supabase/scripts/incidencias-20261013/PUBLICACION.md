# Protección de sesión: frontend publicado

Miguel invocó `$release-crm` tras confirmar la fusión del [PR #273](https://github.com/avanza-digital/avancecorp-crm/pull/273).
El frontend está publicado en https://crm.miavance.com y fue verificado el
**13/10/2026 a las 22:19:43 Lima** (14/10 03:19:43 UTC).

El cliente bloquea localmente las peticiones al esquema CRM que no llevan token
de usuario o usan la clave pública. Auth y refresh siguen disponibles. No se
repiten escrituras ni se amplían permisos; no cambia el flujo de llamadas del
analista. F7 y SLA ya estaban aplicados: este release no ejecutó SQL ni Edge.

## Fuente y paquete

- Main local y `avancecorp/main`: `e791502ff6961a9ef71b434bdb50a1748e744331`.
- Fuente limpia; identidad reconfirmada justo antes del preflight y despliegue.
- Build: `build-20261014T031546721Z`.
- ZIP: `crm-20261014T031547Z-e791502ff696.zip`, 2.538.634 bytes.
- SHA-256: `bc5ab73f4cbce6ead31a3560f07f47f6eab48456315960422601d5e389a12a74`.
- Manifiesto: `crm-20261014T031547Z-e791502ff696.manifest.json`.
- ZIP y manifiesto conservados en `CRM-Avance-Corp/releases/` del taller original
  y de la copia de publicación `/private/tmp/avancecorp-pr255-fix`.

El Main antiguo de esta copia seguía otro remoto. Se conservó íntegro como
`historial/main-local-a2923647` y se creó Main siguiendo `avancecorp/main`.
No se modificó el working tree ajeno, ni se usó force push, rama de release o
`--allow-dirty`. El commit de esta acta no sustituye al del manifiesto.

## Gates

| Comprobación | Resultado |
| --- | --- |
| `npm run check` | PASS reutilizado: 419 archivos / 6.689 tests, lint, tipos, cobertura, build, bundle y duplicación |
| E2E local Docker | PASS reutilizado: 3 pruebas de entrada, foco/refresh y cierre; 11,0 s |
| Identidad de evidencia | Diff completo vacío entre `89ff2c48` y `e791502f`; árbol `d37aa08f1ea92b0805cf696ddda0edc0328cf845`. App idéntica también a `40bef333`, árbol `5093fb161492c744e644e4f50e3ded1ba10d3388` |
| `release:crm` y `release:crm:verify` | PASS con configuración pública productiva; sin secretos en ZIP |
| Preflight | PASS: publicado `6dd9fbb6c6ee` es ancestro de `e791502ff696` |
| Conector Hostinger | Upload success; deploy Request accepted, luego archivos servidos comprobados |
| Portada y versión | HTTP 200; HTML idéntico a `app/dist/index.html`, build esperado |
| JS/CSS | 121 archivos: HTTP 200 y SHA-256 idénticos al manifiesto |
| Acceso básico en navegador | Pantalla «Inicia sesión» visible, cero errores/warnings capturados |
| Archivo de configuración del servidor | `.htaccess` devuelve 403 y no expone su contenido |

El primer intento de empaquetado se detuvo porque la copia aislada no tenía las
variables públicas productivas. Se prepararon únicamente las dos variables
`VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` del entorno autorizado, validando
proyecto y rol público; se reconstruyó y todos los controles de paquete pasaron.
No se publicó el build incompleto.

## Diagnóstico del smoke y límites

[Evidencia HTTP y navegador](PUBLICACION-HTTP.json): 159 archivos públicos
consultados, 147 idénticos en bytes. Los 12 PNG restantes no cambiaron entre el
paquete anterior y el nuevo: siete conservan píxeles RGBA idénticos pese a distinta
compresión; cinco logos pasan de 3508×3253 a 1600×1484. La respuesta es de HCDN y
esto es compatible con su [optimización de imágenes](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/).
Para los cinco logos se conserva también la diferencia media contra un escalado
LANCZOS del original; no se presentan como igualdad exacta de bytes o píxeles.
No se cambió la configuración de CDN ni las imágenes.

El comparador inicial esperaba una ruta `/assets/` literal, mientras el HTML usa
`./assets/`. Se corrigió la resolución contra la URL base: HTML y JS ya coincidían
desde la primera descarga. El informe bruto y su huella están preservados; no se
reintentó el despliegue. Una primera ejecución Node carecía de DNS dentro del
sandbox; la descarga se repitió con permiso de red.

El smoke no inició una sesión de un usuario real ni creó/eliminó datos de negocio.
El comportamiento de sesión cuenta con los 13 tests y tres E2E Docker previos,
no con una prueba de expiración forzada en una cuenta real productiva. No promete
ausencia de timeouts bajo carga ni resuelve los hallazgos previos ajenos al cambio.

## Recuperación

Se retienen ZIP y manifiesto realmente publicados antes de este release:
`crm-20261014T012056Z-6dd9fbb6c6ee.zip`, SHA-256
`c4a433206c1c11d12ff42bc72d975fe82a28f5f983aa0ed2d6a48ee040bc6604`, build
`build-20261014T012055587Z`. El preflight verificó esa versión viva antes de subir.
Cualquier rollback requiere la decisión de Miguel; esta acta no autoriza saltar
el preflight ni revertir SQL o auditorías.

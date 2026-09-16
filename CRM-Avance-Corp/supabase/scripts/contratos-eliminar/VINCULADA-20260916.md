# Contratos vinculados a inversión — publicado y verificado

**Estado 16/09/2026:** autorización final recibida («ya ets aprobado»), PR #1
integrada y SQL/Edge/frontend publicados. [Recibo productivo](PRODUCCION-VINCULADA.json).
El contrato de la captura sigue presente: la eliminación requiere que el usuario
escriba su número y confirme desde el CRM.

## Problema y corrección

La captura de Miguel mostraba «no se puede eliminar» para un contrato nuevo con
inversión multiempresa. El mero enlace deshabilitaba el botón y la RPC rechazaba
todos esos contratos. El diagnóstico productivo de solo lectura confirmó siete
cuotas, ninguna pagada y ningún evento, solicitud, ajuste u origen cotitular.

Admin/Superadmin ahora puede confirmar la eliminación de un contrato vinculado.
La RPC archiva también inversión y titulares (snapshot versión 2), incluidos los
pagos, y retira esas filas en la misma transacción. PDF/adjuntos permanecen
privados e intactos. Los historiales propios, meses cerrados, renovaciones y
permisos previos conservan sus protecciones. Instalar SQL no borra contratos.

## Archivos exactos para aprobación

- [SQL candidato](../../migrations/20260916160000_crm_eliminacion_auditada_inversion_sin_historial.sql).
- [Reversa de comportamiento](REVERTIR-20260916160000.sql): conserva todas las
  auditorías; no restaura datos eliminados ni reabre las RPC legacy.
- [Pruebas y huellas](VERIFICACION-VINCULADA.json).
- [Revisión y decisiones](REVISION-VINCULADA.md).

PASS: 3632 pruebas frontend; 194 E2E (26 omisiones previas) y dos recorridos
específicos vinculados a 390/1440px; 48 pruebas Edge/Storage; 21 grupos SQL local
y remotos; cuatro carreras COMMIT; 23 comprobaciones Auth→Edge→SQL→Storage.
Reversa/reaplicación exactas PASS. Nueve archivos Edge idénticos; otras 652
funciones coincidentes con producción; sin nuevos advisors.

La rama exclusiva `pteyuzyzcpavqefiqidg` está eliminada, con ausencia verificada
16/09 16:27:43 UTC. Coste estimado US$0,006882. No tocar el banco-f7 ajeno.

## Integración requerida por GitHub

[PR #1](https://github.com/avanza-digital/avancecorp-crm/pull/1) contiene la
corrección. La regla de la organización exige una aprobación y el check `verify`.
Se alineó el nombre del job que ejecuta `npm run check` con esa regla y se retiró
el filtro de rutas de pull_request para que no quede pendiente en otras PR.
No se cambió la regla. Miguel aprobó la excepción de administrador; PR #1 quedó
integrada a las 16:54:52 UTC en `a0c47ebc1d4eaa38544fe1b0e550bdceab021007`.
El árbol integrado es idéntico al probado `f4cf98b`; verify/e2e/preflight PASS.
Se reconstruyó el ZIP desde Main limpio, igual a `avancecorp/main`.

## Publicación completada

1. SQL literal autorizado instalado a las 17:00:27 UTC; registro remoto
   `20260916170027`. SHA-256 del archivo aprobado
   `bbfa0aa413f5fd3045c9a948f24c4436ff6e748d8365713b38d051d5a8d92e68`.
   RPC `2d8210b77d1f6f1e3a4e06a1242cf85d` →
   `c0ae3e3167c82724b784d73b4f427868`; otras 652 funciones idénticas.
   No se fusionó el historial reconstruido ni se ejecutó un db push.
2. Edge `crm-contrato-pdf-v2` v20 ACTIVE, JWT habilitado y nueve archivos
   descargados idénticos a Main. Petición sin sesión rechazada con HTTP 401.
3. Release `crm-20260916T165912Z-a0c47ebc1d4e`, build
   `build-20260916T165911818Z`, SHA-256
   `58aa3548076ae892d6a564720c87f36bc26bb88aa075e9a2224da9ddb0736534`.
   MCP oficial Hostinger: deploy y purga aceptados en `crm.miavance.com`.
4. 96 controles HTTP PASS: 92 recursos del manifiesto (80 hashes exactos,
   11 imágenes optimizadas y `.htaccess` 403), ZIP 404 en ambos dominios,
   portada idéntica y Edge 401. Tres versiones consecutivas coincidentes.
   Acceso público en Chromium PASS, sin errores. Recorrido autenticado en
   producción NOT RUN: navegador con sesión no disponible; no se sustituyó
   por una eliminación real. El banco remoto acreditó el flujo completo.
5. Conteos antes/después: 594 contratos, 5320 cuotas, 26 inversiones,
   26 titulares, 0 documentos y 0 auditorías. Contrato e inversión de la captura
   presentes, sin eventos/solicitudes/ajustes/orígenes históricos. Permisos y
   RLS conservados; auditoría no consultable por anon/authenticated y RPC
   ejecutable solo por service_role/postgres. Advisors sin novedades
   (cinco grupos de seguridad y cinco de rendimiento, mismas observaciones).

Rollback frontend conservado: `crm-20260916T035915Z-a09ecad9aaed.zip`, SHA-256
`1adbd4b31dc413e87d55a7de062da2dfc70020698ded81dc9b27709441896c1c`.
La reversa SQL separada conserva auditorías; no restaura datos eliminados.

Las firmas y tipos públicos no cambian; solo el cuerpo y el contenido JSON de
la copia privada. No requiere una nueva definición TypeScript de la API.

## Reproducir en el banco propio

```sh
CONTRATOS_AUDITORIA_BANCO=contratos_vinculados_20260916 node --test CRM-Avance-Corp/supabase/scripts/contratos-eliminar/auditoria.test.mjs
node --test CRM-Avance-Corp/supabase/scripts/contratos-eliminar/concurrencia.test.mjs
```

La suite de concurrencia confirma fixtures sintéticos con COMMIT, exclusivamente
en el nombre Docker/base fijado en el script. La suite SQL usa ROLLBACK.
Los adaptadores remotos fijan la rama ya eliminada: no redirigirlos a producción.

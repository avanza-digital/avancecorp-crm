# Contratos vinculados a inversión — preparado, sin publicar

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
No se cambió la regla ni se eludió la revisión. Mientras la PR no esté integrada,
el ZIP de su commit es solo candidato y debe reconstruirse desde Main verificado.

## Publicación pendiente

1. Miguel aprueba el SQL exacto y su promoción literal. El ensayo reconstruyó
   una rama vacía para tener paridad: **no fusionar todo su historial** con
   producción ni ejecutar un db push. Solo aplicar la candidata autorizada,
   que exige la huella productiva anterior antes de sustituir el cuerpo.
2. Desplegar `crm-contrato-pdf-v2` con verificación JWT; cotejar archivos.
3. Publicar el ZIP limpio de Main sincronizado mediante `$release-crm`.
4. Verificar SQL/permisos, recursos HTTP y datos intactos. No borrar el contrato
   de la captura como prueba. El administrador decide y confirma ese borrado.

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

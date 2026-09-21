# Eliminar contratos del alta unificada — 21/09/2026

Miguel pidió habilitar permanentemente la eliminación por Admin y autorizó
eliminar `2026-01-001457` bajo `ADMINISTRADOR AVANCE CORP`.

## Causa comprobada

La corrección del 16/09 **sí estaba instalada** en producción: cuerpo
`c0ae3e3167c82724b784d73b4f427868`, Edge v21 y botón publicado. La nota anterior
«preparado» había quedado desactualizada. El alta unificada ahora crea un evento
`registro` y una solicitud confirmada; la RPC rechazaba cualquier evento/solicitud.
El contrato indicado tenía exactamente ese caso: 13 cuotas sin pagos, un registro,
una solicitud confirmada y una corrección de los datos de esa solicitud.

## Corrección

`20260921183436_crm_eliminacion_contrato_con_registro_inicial.sql` reemplaza
únicamente dos cuerpos de función. La copia inmutable v3 incluye los eventos
iniciales y las solicitudes completas. La solicitud queda cancelada, sin enlace
a la inversión retirada, conservando datos, resultado, revisiones y correcciones.
Confirmar nuevamente esa solicitud falla por cancelación. Los PDF se conservan.

La excepción al trigger inmutable permite retirar exclusivamente un `registro`
que coincida exactamente con su copia archivada, actor e inversión y con el token
de la reserva privada de eliminación. Una variable por sí sola no autoriza nada.
Los eventos posteriores de corrección/anulación, ajustes, cotitulares históricos,
meses cerrados y restricciones de renovación conservan sus protecciones.

No cambia el endpoint, sus tipos, la UI ni los permisos: `service_role` ejecuta
la RPC y ésta valida Admin/Superadmin activo. No se publica un bundle frontend.

## Verificación

Banco sintético local independiente `contratos_registro_20260921`, en
`supabase_db_avancecorp-f5-bank`. Instalación completa con pre/postflight PASS.
Los dos cuerpos anteriores coinciden con producción; las firmas públicas no cambian.

```sh
CONTRATOS_AUDITORIA_BANCO=contratos_registro_20260921 node --test --test-concurrency=1 \
  CRM-Avance-Corp/supabase/scripts/contratos-eliminar/auditoria.test.mjs \
  CRM-Avance-Corp/supabase/scripts/contratos-eliminar/registro-inicial.test.mjs \
  CRM-Avance-Corp/supabase/scripts/contratos-eliminar/concurrencia.test.mjs
```

PASS: 35 pruebas SQL/concurrencia (21 previas, 10 de registro inicial, 4 carreras);
48 Edge/Storage; `check:scripts`;
`test:edge-preflight`; preflights offline RLS/seed con configuración sintética.
El preflight offline no acredita una nueva matriz Auth/HTTP remota.
Se corrigió un EPIPE del arnés cuando psql cierra stdin tras un rechazo esperado.

NOT RUN: recorrido visual (no hay navegador conectado); matriz RLS remota completa;
build frontend (no cambia frontend). Revisión independiente y evaluación del
PRIMARY en `REVISION-REGISTRO-INICIAL-20260921.md`.

## Estado de instalación

**INSTALADA Y VERIFICADA EN PRODUCCIÓN.** Registro remoto `20260921185355`,
`crm_eliminacion_contrato_con_registro_inicial`. Archivo literal SHA-256
`aac4204aad7f23fc3652894e304e3b7e59a89698c6016525bb27f9742b6a68ed`.
RPC `4afcb3d1300f6e8bdcc64ede6eb57987`; trigger
`875118833ce96aac81356e8f63049695`; permisos exactos y cero avisos nuevos de advisors.
Instalación bajo la orden explícita de activación del usuario, después del banco
local; no se creó un banco remoto de pago ni se acredita ese ensayo.

El contrato **2026-01-001457 fue eliminado** el 21/09/2026 a las 13:54:14 Lima
bajo `ADMINISTRADOR AVANCE CORP` mediante la RPC auditada existente.
Auditoría `7ead0c0e-8ad3-4e2d-9a4c-b0f87de16389`.
Lectura posterior: contrato/cuotas/inversión ausentes; 13 cuotas archivadas;
huellas del contrato, cuotas, registro y solicitud idénticas al estado previo;
solicitud cancelada y su corrección conservadas; un PDF privado todavía presente.
No se eliminó ningún otro contrato real.

No aplicar otras migraciones pendientes ni fusionar el historial de un banco reconstruido.

## Recuperación

Los cuerpos anteriores están versionados en las migraciones
`20260916160000_crm_eliminacion_auditada_inversion_sin_historial.sql` y
`20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql`.
Restaurarlos revierte el comportamiento, **no** restaura contratos eliminados;
la auditoría v3 y los PDF se conservan. La capacidad administrativa es una
decisión permanente del usuario: no retirarla por limpieza o refactorización.

# F7 — ensayo remoto e instalación OFF

11/09/2026. Codex PRIMARY. SQL exacto y coste autorizados por Miguel.
**Instalación productiva en curso; G6 aún no firmado.**

## Banco exclusivo y reconstrucción

`multiempresa-f7-20260911`, proyecto `awshxyerdsvgjnteetfa`, rama
`429fa19f-d018-428c-94a5-731541fde6ed`, creada a las 20:42:52 UTC,
US$0.01344/h. El antiguo `banco-f7` de altas se conserva sin tocarlo.

El replay histórico se detuvo en 86 migraciones. Solo en el banco nuevo vacío
se restauró el esquema vigente `public,crm,private` y el registro completo de
274 migraciones. Los dos cron del banco se desactivaron. No se copiaron
usuarios, comprobantes ni registros comerciales de producción.

La comparación previa al ensayo verificó 619 funciones con definición,
propietario y ACL idénticos, y 1.447 funciones/restricciones. También se
compararon columnas, índices, triggers, RLS, vistas y permisos de schema/tabla/
columna. Tres CHECK difieren exclusivamente por la asociación de paréntesis
de AND, con los mismos operandos. Se conservaron las 19 Edge Functions.

El dump inicial omitió comentarios de dos funciones; se restauraron sus
definiciones exactas desde una lectura del padre antes de ensayar F7. Se
restituyeron el USAGE de PUBLIC sobre el schema public, las doce políticas
Storage y las tres relaciones Realtime que dependían de los schemas recreados.
Estas correcciones pertenecen al montaje del banco; no son SQL productivo.

La semilla usa quince usuarios Auth nuevos `@pruebas.example`, identidades de
empresa mapeadas y 66 archivos PDF/PNG ficticios en buckets privados. Dos cargas
rechazadas se revirtieron íntegramente por referencias incompletas. La carga
final restauró y validó todas las claves foráneas y estados de triggers en la
misma transacción; la comparación del esquema volvió a pasar.

## Verificación específica

- **16 pruebas SQL PASS**: instalación aditiva, permisos, paridad por empresa y
  moneda, atribución/conversión, cotitulares, identidad incompleta/contradictoria,
  medianoche Lima, céntimos, veto No contactar, vencimientos, meses sellados y
  reversa. El archivo tiene el SHA-256 aprobado, sin modificaciones.
- **12 pruebas HTTP PASS**: Auth/PostgREST alojados, siete roles, anon y
  service_role sin identidad; Gerencia pierde acceso con el mismo JWT cuando
  se desactiva su perfil o membresía. OFF rechaza cifras y el estado informa
  `habilitada=false`. El JSON se valida con el contrato real del frontend.
- Se corrigió exclusivamente el contexto de dos subpruebas del adaptador HTTP
  privado: la primera ejecución esperaba subpruebas en el contexto padre y fue
  interrumpida. No se cambió el producto ni se eliminaron aserciones.
- Tipos `public,crm` regenerados desde el banco remoto. Las dos declaraciones
  F7 del repositorio coinciden con las generadas; se conserva el orden existente.
- Tras ensayar se ejecutó la reversa y se retiraron únicamente los cuatro
  objetos nuevos y su bandera del banco para medir la línea base general.

## Integración y gates generales

Se integró `avancecorp/main@6293d24` en `92ca108`, conservando los nuevos avisos
de respuestas de tasas para analistas y supervisores. `VITEST_MAX_WORKERS=2
npm run check` terminó PASS: **3.355 pruebas en 235 archivos**, lint, tipos,
cobertura, configuración de release, service worker, build, bundle y duplicación.
La suite E2E integrada pasó **172 casos, con 26 SKIP preexistentes**. La
comparación RLS general sigue en curso.

La matriz general se prepara con sus trece cuentas demo adicionales y la baja
histórica controlada del miembro inactivo. Su semilla de contratos antiguos
requiere el modo de observación: se añadió una política ficticia de ese modo
en el banco, tras conservar el rechazo inicial del enforcement. El grant
temporal de seed sobre periodos_cerrados se revocó al terminar. El snapshot
sintético permite comparar la misma línea base antes/después sin alterar las
aserciones de la matriz ni llevar datos al padre.

Los advisors remotos previos están archivados: cuatro categorías de seguridad
y cinco de rendimiento. La comparación posterior está pendiente; no se declara
un PASS general de seguridad por tener pruebas F7 correctas.

## Cierre pendiente

Completar RLS antes/después; registrar solo el SQL F7 aprobado en la rama,
publicar el consumidor desde el commit común Main/remoto, realizar el merge
Supabase y verificar producción OFF, núcleos, permisos, historial, Vault y Edge
Functions. Eliminar después únicamente el banco propio para detener su coste.

G6 requiere cifras reales y firma humana. F3 permanece ON y F4/F5/F6 OFF.
Este ensayo no habilita el piloto F8, no hace backfill ni calcula comisiones.
Evidencia privada: `/private/tmp/avancecorp-f7-publicacion-20260911`.
Respaldo: `/Users/usuario/.codex/backups/avancecorp-f7-20260911`.

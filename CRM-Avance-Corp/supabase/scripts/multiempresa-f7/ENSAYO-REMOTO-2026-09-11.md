# F7 — ensayo remoto e instalación OFF

11/09/2026. Codex PRIMARY. SQL exacto y coste autorizados por Miguel.
**Ensayo completado; instalación y publicación OFF verificadas, banco cerrado.**
G6 aún no firmado. [Acta productiva](PUBLICACION-2026-09-11.md).

## Banco exclusivo y reconstrucción

`multiempresa-f7-20260911`, proyecto `awshxyerdsvgjnteetfa`, rama
`429fa19f-d018-428c-94a5-731541fde6ed`, creada a las 20:42:52 UTC,
US$0.01344/h. Eliminado y ausencia verificada a las 21:47:18 UTC.
El antiguo `banco-f7` de altas se conserva sin tocarlo.

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
Para capturas posteriores, `supabase db dump --keep-comments` evita aquella
pérdida de comentarios; se comprobó la opción en la ayuda de la CLI instalada.
El cotejo final detectó 71 autores históricos ausentes en el registro del banco:
se completaron desde la lectura del padre y las 274 entradas quedaron idénticas,
incluidos autores, sentencias, rollback e idempotencia. Las capturas de metadata
fijan UTC para evitar diferencias de representación horaria sin alterar datos.

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
- La candidata se registró después como `20260911212526`, con el archivo
  aprobado completo byte a byte. Se restauró la misma semilla y las doce
  pruebas HTTP finales volvieron a pasar. La comparación previa al merge
  confirmó solo cuatro funciones y una migración nuevas, con F7 OFF.

## Integración y gates generales

Se integró `avancecorp/main@6293d24` en `92ca108`, conservando los nuevos avisos
de respuestas de tasas para analistas y supervisores. `VITEST_MAX_WORKERS=2
npm run check` terminó PASS: **3.355 pruebas en 235 archivos**, lint, tipos,
cobertura, configuración de release, service worker, build, bundle y duplicación.
La suite E2E integrada pasó **172 casos, con 26 SKIP preexistentes**. La
comparación RLS general terminó sin regresiones: **1.772 PASS / 57 FAIL de
1.829 tanto antes como después**. El estado general es FAIL; el PASS de la
comparación no lo sustituye. Se comparó el multiconjunto de fallos, normalizando
únicamente UUID sintéticos; algunos conteos se ven afectados por convivir la
muestra F7 con el fixture general.

La matriz general se prepara con sus trece cuentas demo adicionales y la baja
histórica controlada del miembro inactivo. Su semilla de contratos antiguos
requiere el modo de observación: se añadió una política ficticia de ese modo
en el banco, tras conservar el rechazo inicial del enforcement. El grant
temporal de seed sobre periodos_cerrados se revocó al terminar. El snapshot
sintético permite comparar la misma línea base antes/después sin alterar las
aserciones de la matriz ni llevar datos al padre.

Los advisors remotos están archivados. Seguridad: 259 → 261 observaciones;
solo dos WARN nuevos por las RPC F7 autenticadas `SECURITY DEFINER`, con la
autorización interna y revocaciones comprobadas por SQL/HTTP. Ninguna nueva
inesperada. Rendimiento: 278 → 145, ninguna nueva; 133 observaciones de índices
sin uso desaparecieron al ejercitar el banco. No se declara un PASS global de
seguridad/rendimiento. Evaluación y enlace a la regla en
[el acta productiva](PUBLICACION-2026-09-11.md).

## Cierre completado

Se publicó el consumidor desde Main/remoto `32eae8a`, se instaló solo F7 por
merge Supabase y se verificó producción OFF. Las 274 migraciones y 619 funciones
previas permanecen intactas, total posterior 275 migraciones. Las 18 sentencias
registradas por el merge conservan los bytes y orden del archivo aprobado;
solo cambia su separación por el ejecutor. Datos/Auth, Vault, cron, permisos,
núcleos y las 19 Edge Functions conservados. Banco propio eliminado.

G6 requiere cifras reales y firma humana. F3 permanece ON y F4/F5/F6/F7 OFF.
Este ensayo no habilita el piloto F8, no hace backfill ni calcula comisiones.
Evidencia privada: `/private/tmp/avancecorp-f7-publicacion-20260911`.
Respaldo: `/Users/usuario/.codex/backups/avancecorp-f7-20260911`.

# Documentos del lead — ensayo local, 30/09/2026

Estado: **VALIDADA EN LOCAL Y SUPABASE REMOTO; publicación en curso**.
Miguel levantó la espera con «dale ya pouedes» y confirmó publicar solo documentos,
manteniendo F1 Llamadas pendiente. La autorización de organización y coste continúa
vigente (PortalAvanceCorp, máximo US$1). Los bloques inferiores de preparación
conservan la evidencia histórica; la retoma final se documenta al final de esta nota.

## Incidente y solución

El alta limitaba DNI a ocho caracteres y la edición eliminaba letras y recortaba
a ocho dígitos. Un CE podía quedar convertido en otro número antes de guardarse.
La conversión sí aceptaba CE, pero correctamente rechazaba un número distinto
del DNI del lead. No se elimina esa protección.

Alta y edición ahora ofrecen DNI, CE y pasaporte. El número es texto, sin recortes,
con validación del catálogo común. `crm.leads.dni` sigue aceptando únicamente DNI;
CE/pasaporte se guardan en `crm.inversionista_identificadores` y el lead enlaza
esa identidad. La ficha y la conversión leen el mismo documento canónico. Una
lectura fallida bloquea editar/convertir y ofrece reintento.

La edición del documento y los demás campos es atómica. El éxito solo se anuncia
después de guardar; ante rechazo, el formulario queda abierto. Un documento ya
reconocido solo se corrige con el permiso de Administración de la RPC existente,
identificador anterior y motivo auditado. Un analista puede editar los otros datos.

No se adivina el CE de la persona del incidente ni se modifica su registro real.
Administración deberá introducir el número completo y correcto al publicar.
Una identidad con varios leads/documentos que no pueda quedar coherente se
rechaza con indicación de conciliación; nunca se confirma una corrección parcial.
Se proyecta el documento primario con el mismo orden de inversión: DNI, CE,
pasaporte, identificador. No es un editor de todos los documentos de una persona.

## Banco y reproducción

Destino fijo: Docker `supabase_db_crm-avance-corp-local`, base
`lead_documentos_20260930`. Se creó desde el banco sintético
`conversion_tipos_v3_20260927`, con seis leads ficticios. Se actualizó únicamente
en este banco el núcleo `crear_lead_si_disponible` a su definición vigente, y se
repusieron grants de esquema/SELECT/UPDATE de leads cotejados con producción.
La migración verifica diez huellas de funciones de las que depende; todas
coinciden entre este banco y la lectura de producción del 30/09.

`banco.mjs` exige nombre y comentario exactos de la base antes de operar. No acepta
URL ni credenciales externas. Los fixtures usan UUID `d0000000-…`, teléfonos
`988770…` y documentos ficticios. Las pruebas revierten sus datos con ROLLBACK.
La base, su esquema y los actores sintéticos permanecen disponibles para repetir:

```sh
node supabase/scripts/lead-documentos/banco.mjs test
node supabase/scripts/lead-documentos/concurrencia.mjs
node supabase/scripts/lead-documentos/banco.mjs reversa-y-reaplicar
```

El primer comando cubre CE/pasaporte y ceros iniciales, lectura y preparación de
conversión, reintento idéntico o con otro documento, duplicados y huérfanos,
validación estricta, flag apagado, corrección DNI→CE, auditoría y restauración de
privilegios, atomicidad ante teléfono duplicado, ámbito, anon, UID nulo, usuario
inactivo, veto y la ruta DNI anterior. Cubre el enlace solo por puente y la
ambigüedad entre varios documentos: ambos rechazos revierten toda la corrección.
La concurrencia usa dos conexiones reales
al mismo PostgreSQL: el segundo alta del mismo CE espera y falla por candado;
ninguna transacción deja filas después del rollback.

## Verificación y límites

- PASS: 52 aserciones SQL en PostgreSQL aislado; dos sesiones de concurrencia;
  reversa y reaplicación de la migración con su preflight.
- PASS: `npm run check` en `app`: 4.958 pruebas, 321 archivos, lint, typecheck,
  cobertura, configuración, build, bundle y duplicación.
- PASS: preflight RLS offline con variables sintéticas loopback. No abre conexiones.
- Tipos de las cuatro RPC generados por Supabase CLI/postgres-meta desde este banco.
  Se incorporaron esos bloques sin sobrescribir cambios ajenos en `database.types.ts`.
- PASS: 33 E2E de UI en Docker: `npm run test:e2e:docker -- e2e/lead-documento.spec.ts
  e2e/acciones-real.spec.ts e2e/acciones-demo.spec.ts --workers=2`. El transporte de
  estas suites es simulado y bloquea HTTP no previsto; la persistencia y RLS se
  comprueban por separado en PostgreSQL real aislado.
- PASS: regresión E2E completa en Docker, **297 passed / 26 skipped / 0 failed**
  (11,2 minutos, dos workers). Los 26 casos omitidos aparecen como skipped;
  no se cuentan como pruebas aprobadas.
- NOT RUN: rama Supabase remota, matriz HTTP RLS completa y advisors de la rama.
  Son requisitos pendientes de la publicación. El preflight offline
  no sustituye esos gates. No se aplicó ninguna migración en producción.

## Revisión y reversa

Revisión inicial por el wrapper de Claude, con rol SECONDARY_REVIEWER y
especialidad auditor-rls; solo el PRIMARY implementa. Del diagnóstico inicial se
incorporaron: postcondición del lead objetivo, restauración de GUC, flag bajo
candado, validación previa al resolver y alta sin identidades huérfanas.
El segundo intento, sobre la implementación y evidencia, terminó con
«resultado incompleto o sin VERDICT válido». No se registra como aprobación ni
se sigue consultando para obtener un resultado favorable. El PRIMARY comprobó
las correcciones en SQL y frontend; el dictamen inicial fue CHANGES_REQUESTED.

Se conservan los UUID canónicos dentro del ámbito: `leads.inversionista_id` ya es
visible y el identificador anterior permite detectar cambios concurrentes. Ningún
UUID confiere permiso; cada RPC valida actor, ámbito y permiso administrativo.

Para revertir, retirar primero el frontend que usa las RPC nuevas y ejecutar
`reversa.sql`. Solo retira funciones; conserva documentos, identidades e historial
auditado válidos para las funciones existentes. No modifica objetos de public.

## Preparación de publicación, 30/09/2026

Se integraron en una copia limpia Main local, `avancecorp/main` (`6666eaf3`) y la
ascendencia del frontend vivo (`57e7b3b4`). Los merges conservan exactamente el
árbol remoto antes de incorporar esta corrección. Se retuvieron los nuevos bloques
de Coordinación en crm-api, tipos y helpers E2E; no se copiaron los demás cambios
sin confirmar del checkout habitual. No se hizo push ni publicación.

- PASS del código integrado: `npm run check`, **5.021 tests / 323 archivos**,
  lint/typecheck/cobertura/build/bundle/duplicación.
- PASS de Docker integrado: **298 passed / 26 skipped / 0 failed**, 11,7 minutos.
- PASS SQL final: **52 aserciones**, incluyendo destino ajeno, tres etapas no
  válidas, vínculo directo único, auditoría con actor y CE vacío que no borra DNI.
  Concurrencia y reversa/reaplicación vuelven a pasar con la versión definitiva.
- Revisión de publicación: `revision-publicacion.txt`, CHANGES_REQUESTED;
  no se registra como PASS. La hipótesis de bypass se descarta con las definiciones
  DEFINER de crear_lead_si_disponible/fijar_dni_lead_fn (auth.uid, rol, ámbito y
  etapas explícitos) y las pruebas nuevas. La hipótesis de dos vínculos directos
  se rechaza por leads_inversionista_uidx, único sin filtro de estado, reproducido
  como 23505. Además se exige que la operación auditada pertenezca al lead solicitado.
  El trigger trg_audit_leads → log_audit_sin_secretos conserva actor y vínculo y
  enmascara DNI incluso con op_privilegiada: se comprobó, no se duplica la bitácora.
  Se agregó rechazo de CE/pasaporte vacío cuando ya hay DNI. La ruta de mismo
  documento vuelve a ejecutar documento_lead_fn bajo candado y valida el ámbito.
  Las fichas terminales tienen `activa=false` y no ofrecen editar. Un reintento de
  alta tras mutar el lead mantiene el rechazo legado; no confirma datos obsoletos.
  Identidades sin documento verificado requieren conciliación administrativa.

### Banco remoto y bloqueo concreto

Banco propio `lead-documentos-20260930`, id
`ea9833de-a2a3-4453-92b6-5ce0574f9517`, ref `kuqsmbfqvqzuktsdbugd`.
Creado 21:17:26 UTC con tarifa confirmada US$0.01344/h y máximo autorizado US$1.
El replay histórico terminó MIGRATIONS_FAILED antes de crear tablas de aplicación.
Se extrajo solo el esquema vivo y los controles técnicos, sin datos de clientes.
Los intentos de restauración transaccional detectaron primero roles técnicos y,
al resolverlos, la ausencia de `storage.objects`. Storage respondió HTTP 400
`TenantNotFound: Missing tenant config`; Auth sí respondió 200. No se simuló el
esquema administrado ni se relajó el preflight. Los intentos revirtieron todo:
antes de cerrar, Auth=0 usuarios, tablas de aplicación=0, historial=0.

**NOT RUN:** aplicación candidata remota, matriz RLS HTTP y advisors posteriores.
El banco propio se eliminó correctamente para detener el coste. No se tocaron los
otros bancos, contratos, documentos ni datos productivos. El importe final depende
de la facturación de Supabase; no se afirma una factura calculada por nosotros.

### Retoma cuando el usuario dé aviso

1. Resolver la provisión del banco remoto; repetir allí la candidata exacta,
   SQL/HTTP RLS pertinente y advisors. Cotejar catálogo, historial y Edge Functions
   antes de cualquier merge. El fallo histórico/Storage no acredita estos gates.
2. Integrar cualquier avance nuevo en `avancecorp/main`; verificar Main/remoto
   iguales y volver a construir si cambió la fuente. La copia preparada no se ha
   enviado al remoto y conserva la ascendencia del build vivo.
3. Solo con el aviso del usuario y gates completos: merge de la rama SQL, comprobar
   funciones y permisos, verificar ZIP/manifiesto/preflight, desplegar Hostinger y
   comparar los hashes HTTP. El ZIP preparado por sí solo NO autoriza publicar.
4. El documento real afectado requiere su CE completo correcto y permiso de
   Administración. No borrar ni recrear el contrato para resolverlo.

## Retoma autorizada y validación remota, 30/09/2026

Nuevo banco `lead-documentos-publicacion-20260930`, ref `saiwhmjrgqdggscfimbu`,
creado 22:03:36 UTC. Storage sí se inicializó; el replay histórico se detuvo en
86 migraciones. Se reconstruyó el esquema vivo sin usuarios ni documentos reales,
preservando los servicios administrados. La restauración retiró los grants extra
heredados por el banco y repuso los comentarios que el dump había omitido en dos
funciones. Se restauró literalmente el juego de caracteres de un CHECK cuyo CR
se había normalizado al leer el dump. Otros tres CHECK solo difieren en paréntesis
redundantes de AND por la versión de PostgreSQL; se verificaron todas las FK.

Paridad previa y posterior (excluyendo las cinco funciones nuevas): 858 funciones,
333 triggers, 125 policies, 134 tablas/vistas, 1.320 columnas, 478 índices y
7.668 grants de columna, con las mismas huellas. Esquemas/ACL normalizados iguales;
cero triggers de aplicación deshabilitados al medir. Veintidós Edge Functions con
los mismos paquetes y verify_jwt, y cinco buckets con los mismos límites/permisos;
no se copió ningún objeto. Se alinearon las 400 migraciones históricas solo después
de comprobar la paridad, conservando versiones/nombres/SQL exactos. El merge tiene
una única migración nueva: `20260930193325`.

Fixtures: 13 cuentas ficticias del seed oficial, siete leads y cinco tareas. Se
restauraron los catálogos técnicos necesarios (SLA, empresas, flags y producto
legacy); los autores de esas configuraciones no se copiaron. La baja histórica
se construyó con la excepción documentada del seed y sus triggers/permisos quedaron
repuestos antes de medir. La prueba SQL convierte temporalmente al gerente ficticio
en admin dentro de su transacción y revierte tanto el permiso como todos sus datos.

- PASS: 52 aserciones SQL de documentos con rollback.
- PASS: 12 comprobaciones HTTP con Auth/PostgREST reales: CE/pasaporte completos,
  preparación de conversión, duplicados sin huérfanos, ámbitos y permisos.
- PASS: matriz RLS contractual 287; identidad D5 30.
- PASS: advisors antes/después, cero avisos nuevos (4 seguridad / 6 rendimiento).
- PASS final de Main integrado con F1 sin activar: `npm run check`, 5.100 tests
  en 328 archivos; Docker 298 passed / 26 skipped / 0 failed.

El commit `9815ad02` deja pendiente solo la activación de F1 y sus pruebas de
integración; conserva sus módulos y tests unitarios. Los archivos de documentos
no cambiaron respecto de la candidata revisada. La reactivación de F1 se explica
 en `docs/plans/llamadas-celular/PUBLICACION-PENDIENTE-2026-09-30.md`.

Evidencia: `VALIDACION-REMOTA.json`, `sql-remoto.log`, `http-remoto.log`,
`rls-contratos-remoto.log`, `rls-identidad-remoto.log` y `e2e-main-documentos.log`.

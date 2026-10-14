---
tags: [crm, supabase, diagnostico, f7]
fecha: 2026-10-13
estado: F7 y SLA aplicados; transporte de sesión publicado y verificado
---

# PostgreSQL — F7, rendimiento y transporte de sesión publicados

Consultas de catálogo y logs productivos de `dctqcbznekcyxhjujuci`, realizadas el
13/10/2026 desde 23:26 UTC. Ventana agregada: 12/10 23:26–13/10 23:26 UTC.
En ese diagnóstico inicial no se modificó producción. La corrección posterior
autorizada por Miguel queda registrada a continuación.

## Corrección aplicada por encargo de Miguel

Miguel autorizó corregir F7, timeouts y consultas sin sesión. Se prepararon las
migraciones `20261014001044` (solo sello F7) y `20261014001346` (agregación de tareas
por lead en el núcleo SLA), y una guarda de transporte que impide enviar RPC CRM
con la clave pública cuando falta sesión. Mantiene Auth/refresh y no reenvía
escrituras. Ensayo local: F7 verde con 15 piezas, seis ámbitos idénticos, 44 pares
de RPC/denegaciones idénticos, reversa exacta, 13 tests de sesión y 3 E2E Docker.
EXPLAIN sintético del núcleo: 667,874 → 301,780 ms; no es latencia productiva.

Miguel autorizó reconstruir solo `banco-f7` tras el fallo histórico de replay
F2.b b4. Se respaldó su contenido, se copió el esquema vigente y se sembraron datos
sintéticos. Se integraron las dos migraciones concurrentes de atención/venta.
SQL remoto: 13 bloques PASS; matriz HTTP: 3.931 aserciones PASS. El cierre del
fixture requirió restaurar por separado la fecha de una bandera, conservando
la evidencia del fallo del wrapper. Ninguna assertion HTTP se omitió.

Merge Supabase confirmado el 14/10/2026 a las 02:38 UTC (13/10 en Lima):
`20261014013757` F7 y `20261014013830` SLA. F7 verifica 15 piezas; el vigía cerró
la alerta a las 02:39:01 UTC, dejando cero abiertas. Los 473 registros anteriores
del ledger y todos los permisos se conservaron; 23 Edge con contenido idéntico.
Advisors posteriores sin hallazgos nuevos. EXPLAIN productivo puntual:
núcleo 1.808,639 → 1.244,137 ms, 3.594 filas; RPC de equipo authenticated
1.644,650 → 1.369,887 ms. No garantiza latencia HTTP bajo concurrencia.

El transporte de sesión quedó publicado tras fusionar el PR #273 y la invocación
humana `$release-crm`: Main `e791502ff6961a9ef71b434bdb50a1748e744331`, build
`build-20261014T031546721Z`, verificación el 13/10 a las 22:19 Lima. Los 6.689 tests
/419 archivos y 3 E2E Docker PASS se reutilizaron por identidad exacta del código.
Portada y 121 JS/CSS servidos idénticos; acceso visible sin errores. ZIP
`crm-20261014T031547Z-e791502ff696.zip`, SHA-256
`bc5ab73f4cbce6ead31a3560f07f47f6eab48456315960422601d5e389a12a74`.
Acta: `CRM-Avance-Corp/supabase/scripts/incidencias-20261013/PUBLICACION.md`.
El guardián analítico general mantiene su
deriva previa; esta corrección no normaliza sus declaraciones. Detalle y reversa:
`CRM-Avance-Corp/supabase/scripts/incidencias-20261013/LEEME.md`.

## Sello F7: causa confirmada

`crm.metricas_cartera_fn(date)` conserva propietario `postgres` y ACL esperada.
Su cuerpo vivo tiene MD5 `869853c25e903fe2f79245b8176c09b9`; el libro F7 conserva
`0b4ede547cf7079be1e56073311453b3`. La definición completa tiene MD5
`67cdc767f0d38277a920b2ec5aebf2ae`: coincide con la migración de reportes de
Coordinación aplicada como `20261012223850 crm_coordinacion_reportes_lectura`.
La diferencia conocida añade `or private.es_coordinador_reportes()` al lector;
no cambia la fórmula. El registro F7 no fue actualizado en ese cambio.

El error de 23:21:55 UTC proviene de `mgmt-api`, rol `postgres`, bloque de
diagnóstico que captura `private.assert_f7_piezas_cerradas()` y emite
`RESULTADO_F7`. La alerta del vigía ya estaba abierta desde 06:59:00 UTC.
«Cerrada» describe acceso directo de la función, no un mes contable cerrado.
Corregir mediante migración guardada que redeclare la huella autorizada y valide
F7; no copiar la huella viva sin verificar cuerpo, ACL, propietario y contrato.
Precedente: `20260924161110_crm_f7_redeclarar_huella_crear_contrato_con_cuenta.sql`.

## Otros registros del diagnóstico inicial

- 195 rechazos `permission denied for schema crm` por PostgREST en 24 h.
  Las muestras HTTP correlacionadas de 21:20–23:11 llegan con JWT `anon` (401),
  desde navegador y Node. `authenticated` y `service_role` conservan USAGE;
  `anon` no lo tiene. Revisar peticiones antes de autenticar o al perder sesión;
  el log de PostgreSQL identifica `authenticator`, no el rol efectivo del JWT.
  No ampliar permisos de `anon` como remedio. No se atribuyeron los 195 eventos
  individualmente ni se reprodujo todavía el ciclo de sesión del frontend.
- Diez DELETE rechazados corresponden al dashboard con
  `supabase_read_only_user`, intentando ejecutar un script de novedades.
  No acreditan un fallo de borrado originado en el CRM ni autorizan reejecutarlo.
- Nueve timeouts de PostgREST afectan consultas de Gestión Diaria/SLA/cola.
  Hay respuestas HTTP 500 para usuarios autenticados. Falta medir planes,
  concurrencia y recursos para determinar causa; no basta aumentar el timeout.
- A las 21:59:04 UTC PostgreSQL arrancó tras una interrupción y ejecutó
  recuperación automática; cinco FATAL rechazaron conexiones durante el arranque.
  A 21:59:05 ya aparecen conexiones autorizadas. A 23:26 está fuera de recuperación
  y la sesión de diagnóstico no está en solo lectura. La causa del reinicio
  no quedó acreditada en los eventos consultados.
- Los rechazos de negocio del informe no se validaron caso por caso; no
  deshabilitar sus controles ni clasificarlos todos como errores de aplicación.
- El estado oficial de Supabase confirma un incidente de Realtime; no se
  estableció causalidad con los problemas de PostgreSQL de este diagnóstico.

Verificado después de la corrección: bancos local/remoto, frontend integrado,
merge SQL, catálogo y ledger productivos, vigía, advisors y EXPLAIN puntual.
Publicación del transporte completada. La observación de errores/timeouts bajo
carga real no forma parte del smoke y no está automatizada por esta acta.
[PR #273](https://github.com/avanza-digital/avancecorp-crm/pull/273).

Relacionadas: [[Coordinacion - Facturacion y Ranking en lectura (2026-10-12)]],
[[Inicio]].

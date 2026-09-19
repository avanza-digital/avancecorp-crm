# Ensayo remoto autorizado — 19/09/2026

**PASS. SQL, Edge y frontend productivos todavía sin modificar.**
Miguel autorizó el SQL exacto con «HAZLO» y el banco con un máximo de US$5.
La tarifa confirmada fue US$0,01344/h. El banco exclusivo se creó a las
16:45:02 UTC: `conversion-inversion-20260919`, proyecto `omdgdbsbsabisykekziu`.
No se utilizó ni modificó el banco ajeno `banco-f7`.

## Resultado y alcance

- Candidata completa aplicada en la rama como `20260919172019`. Su única entrada
  SQL contiene los mismos 107.472 bytes y SHA-256 que el archivo autorizado
  `20260919161807_crm_conversion_inversion_unificada.sql`.
- Oráculo SQL económico con ROLLBACK: PASS, salida 0.
- Auth/PostgREST/Storage remotos: 15 pruebas, 14 escenarios, cero fallos.
- Gate vigente `test-rls.mjs --contratos`: 284 aserciones PASS. Comprueba
  jerarquía, domicilio, banca, contratos y anon. No es la matriz RLS global.
- Edge `crm-inversion-bienvenida` desplegada: nueve aserciones HTTP PASS,
  incluidos cliente/anon/servicio rechazados. Dos fuentes descargados idénticos
  a los versionados. La autenticación se realiza en la RPC con ámbito vigente.
- Producción conserva `RESEND_API_KEY`; sólo se consultó su presencia.
  El proveedor se sustituye en la integración; **no hubo correos reales**.
- CI del código final: `verify`, `e2e` y `preflight` PASS en el
  [PR #23](https://github.com/avanza-digital/avancecorp-crm/pull/23).

[Evidencia estructurada](verificacion-remota.json), [HTTP](http.txt),
[matriz bancaria](rls-contratos.txt), [Edge](edge.txt),
[advisors](advisors-delta.json). La evidencia local anterior se conserva;
no se reescriben como aprobados sus intentos fallidos.

## Banco equivalente, exclusivamente sintético

El replay histórico de una rama vacía falló por dependencias anteriores que
necesitan datos. Se reconstruyó exclusivamente esta copia desde un exportado
de esquema vigente, sin copiar clientes productivos. Se restauraron las
dependencias de extensiones, los permisos efectivos de `crm_metricas_bridge`,
cuatro policies Storage y el trigger diferido de Auth. La restauración masiva
se ejecutó en una transacción tras corregir esos prerrequisitos.

Antes de la candidata coincidieron ocho de nueve huellas de catálogo: 660
funciones completas con ACL/comentarios, 1.166 columnas, 272 triggers, 101
policies, 116 tablas con RLS, 428 índices, 306 migraciones y tres vistas.
Las 870 restricciones mantienen los mismos predicados: tres CHECK serializan
los AND asociativos con menos paréntesis. `pg_dump` compacta los huecos de
columnas eliminadas en `public.perfiles`; nombres, orden relativo, tipos,
defaults y permisos coinciden. Son diferencias de reconstrucción, no del SQL.

Después: exactamente 11 funciones nuevas y 10 modificadas. Propietarios,
ACL y permisos de las modificadas intactos; 33 comprobaciones de privilegios
de las nuevas aprobadas. Funciones, 127 columnas lógicas, 220 grants, 38
policies y 42 triggers de `public` iguales al padre.

Cron se desactivó en el banco y la cola HTTP quedó vacía. Antes del gate
bancario se retiraron los hechos sintéticos de HTTP siguiendo `LEEME-seed`,
se sembraron fixtures nuevos y se restauraron todos los triggers/grants
temporales antes de medir permisos. Ninguna excepción de fixture se promueve.

## Advisors

Seguridad: 277 avisos en padre, 280 en banco. Cuatro nuevos corresponden a
las RPC authenticated SECURITY DEFINER intencionales de contexto, preparación,
cancelación y estado de bienvenida. Están limitadas a usuarios autorizados,
revalidan actor/ámbito y fueron cubiertas por las pruebas HTTP de rechazo.
La entrega sólo admite service_role; helpers privados no son ejecutables
por anon/authenticated/service_role. [Criterio del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

El aviso `pg_net` en public sólo aparece en padre: el banco usa la versión
de plataforma 0.20.4 en extensions. La candidata no cambia esa extensión.
Rendimiento: 214/250 avisos; las 46 altas y 10 bajas son estadísticas de índices
sin uso de una copia nueva. No hay altas WARN/ERROR. No se deduce rendimiento
productivo de esas estadísticas ni se eliminan índices por ellas.

## Activación pendiente

La autorización del SQL y del costo persiste. Falta la invocación humana de
`$release-crm` exigida por `CLAUDE.md` y la habilidad de publicación. **Activar
SQL, Edge y frontend de forma coordinada:** la candidata bloquea las puertas
antiguas, por lo que dejarla con la web anterior cortaría las conversiones.

Antes de promover: revalidar las 18 anclas, reservas y historial productivos;
integrar el código y comprobar Main/avancecorp/main; construir una copia limpia;
promover sólo la candidata y la Edge verificadas. No promover SQL de
reconstrucción, fixtures ni configuración del banco, ni aplicar directo a prod.
El estado de control de la rama sigue `MIGRATIONS_FAILED` por el replay original;
los gates aquí documentados prueban el esquema reconstruido, no un merge ejecutado.

Los adaptadores sólo aceptan esta rama fija. Las credenciales y fixtures Auth
permanecen en archivos privados fuera del repositorio y no se publican.

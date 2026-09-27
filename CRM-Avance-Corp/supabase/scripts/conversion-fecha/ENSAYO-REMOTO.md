# Conversión por fecha comercial — ensayo remoto 27/09/2026

**ENSAYO EN CURSO. SQL exacto y flujo de publicación aprobados por Miguel,
condicionados a superar los gates. Producción intacta.**

## Estado vigente — 27/09, 03:07 Lima

- Baseline limpio: PASS, 2267 aserciones, salida 0.
- Candidata instalada inactiva: PASS, 2267 aserciones, salida 0.
- Migración nativa `20260927073637`, bytes idénticos al SQL aprobado.
- Complemento nativo `20260927080006`, aprobado expresamente por Miguel:
  dos declaraciones operativas y huella de deuda, sin alterar funciones,
  permisos, contratos, techo ni clases existentes. SHA-256
  `2b34a9b60f384bf09b83bf0c163cddb2cf7935c0bebe4d5442e72b19c0c69324`.
  Primer ensayo revertido por escapes de normalización; corregidos para ser
  idénticos al censo existente. Segundo ensayo revertido PASS, aplicación y
  lectura posterior PASS. No se debilitó el postflight.
- Política activada sólo en el banco con manifiesto vacío verificado: cero
  episodios convertidos pendientes. No se usó el manifiesto de clientes reales.
- Escritores HTTP/Auth/Storage: 15/15 PASS. Avance PEN/USD, DNI/CE/pasaporte,
  Qorilazo PEN, Prodelco PEN/USD, doble envío, dos pestañas, fusión y reasignación.
- Estado de crédito HTTP: 5/5 PASS. Ámbitos, anonimato, miembro revocado con
  el mismo token, tablas cerradas y enero registrado en septiembre: conserva
  inversión de 5000 y da cero crédito en enero/septiembre, reintento idéntico.
- Tipos completos generados desde la rama, public+crm, CLI 2.117.0. Typecheck
  y `npm run check` posteriores PASS. La CLI rechaza combinar project-id con
  query-timeout; se retiró esa opción sin cambiar servidor ni versión.
- Reversa remota ensayada y revertida: PASS, hechos/contratos intactos, RPC
  compatible, política restaurada y declaración de deuda coherente.
- Diez suites SQL locales y cinco mutantes repetidos tras ajustar reversa: PASS.
- Advisors sin nuevas advertencias ni errores: sólo dos INFO esperados de RLS
  sin policy para las tablas internas deny-by-default. No se les abrió acceso.
- Matriz final con ambos SQL y política activa: preparación/ejecución en curso.
  Respaldo de fixtures HTTP antes de restablecer la semilla; no clientes reales.
- Pendientes: resultado de matriz activa, PR/CI/revisión humana, merge nativo,
  revalidación+activación productiva, artefacto limpio y publicación verificada.

El control analítico global conserva **cuatro hallazgos previos idénticos a
producción**: tres funciones sin declarar y la huella anterior de
`crm.contrato_eliminar_auditado`. Los tres hallazgos agregados por este cambio
quedaron resueltos. Delta cero; el control global no se declara PASS. El
complemento comprueba que no desaparezca ni cambie ningún hallazgo ajeno.
Los apartados siguientes conservan la cronología de preparación, no sustituyen
este estado vigente. Las cabeceras cautelares de los SQL originales se conservan
para no cambiar sus bytes; la autorización vigente está registrada aquí.

## Autorización y aislamiento

Miguel autorizó crear y usar una rama nueva en AVANCECORP- CRM-PORTAL,
US$0,01344/hora (aproximadamente US$0,32/día). Confirmación posterior a la
petición específica de este objetivo, no reutilizada del ensayo de Ranking.

- Rama: `conversion-fecha-20260927`.
- Referencia: `qxpcuctzsnomnipqlrgn`.
- ID: `d16e1e75-5ade-45c0-b460-5edbc6778b5f`.
- Padre: `dctqcbznekcyxhjujuci`.
- Creación: 2026-09-27 06:09:50 UTC (01:09:50 Lima), sin datos productivos.
- Evidencia/credenciales privadas: `/private/tmp/conversion-fecha-remoto.xjLqBU`.
  No incorporar esa carpeta completa al repositorio público.

Producción sólo se consultó para estructura e historial; no se escribieron
contratos, conversiones, cifras ni sellos. Ninguna otra rama fue modificada.
No merge, push ni despliegue. Cron del banco: cero trabajos activos.

## Reconstrucción del banco

El replay nativo se detuvo en la migración histórica siguiente a
`20260811210049`: 86 versiones, Auth/perfiles/leads/contratos vacíos. Es el
postflight histórico dependiente de datos documentado en LEEME-seed.

Se reconstruyó exclusivamente la rama vacía desde la estructura base conservada
del ensayo anterior, luego las cuatro migraciones productivas posteriores y sus
arrays originales de historial. No se neutralizó una guarda de la candidata.
Un intento de concatenar el SQL registrado omitió separadores entre elementos
del array; falló sintácticamente y se revirtió entero. Se corrigió el transporte
con separadores, sin cambiar cuerpos ni los arrays guardados. Segundo intento PASS.

Paridad contra producción antes de instalar la candidata:

| Categoría | Objetos | Resultado |
|---|---:|---|
| Columnas | 1274 | Huella idéntica |
| Funciones, dueños, comentarios y ACL | 818 | Huella idéntica |
| Triggers | 318 | Huella idéntica |
| Policies RLS | 106 | Huella idéntica |
| RLS por tabla | 127 | Huella idéntica |
| Índices | 465 | Huella idéntica |
| Historial | 374 | Huella idéntica |
| Vistas | 3 | Huella idéntica |
| Restricciones | 945 | Tres diferencias de serialización, ver abajo |

Los tres CHECK distintos son `empresas_monedas_check`,
`producto_condiciones_capital_check` y
`alertas_reconocimientos_miembros_check`: agrupaciones de paréntesis AND
equivalentes, sin diferencia de condiciones. No se afirma paridad byte a byte
de esas tres representaciones.

## Fixtures y comprobaciones

- Preflights de seed y RLS: PASS con el entorno de la rama. Resuelven los
  anteriores fallos de configuración por SUPABASE_URL ausente.
- Seed canónico: PASS, 13 usuarios Auth/perfiles ficticios, 11 miembros CRM,
  7 leads/actividades, 5 tareas, dos contratos y cuenta contractual.
- Catálogos estáticos exportados del banco local sintético, no clientes reales.
  Reglas iniciales y flags según el banco canónico de Gestión Diaria.
- Permiso temporal de SELECT de service_role sobre periodos_cerrados retirado.
  La baja histórica del fixture inactivo se construyó con el guardia nombrado
  restaurado en la misma transacción; auditoría permanece activa.
- Advisors baseline capturados antes de la candidata; comparación pendiente.
- Matriz completa HTTP/Auth/RLS baseline: **FAIL, 22 de 2267 aserciones**,
  antes de instalar la candidata. Duración de esa ejecución: aproximadamente
  11 minutos; no representa todo el tiempo de preparación.
- Candidata, activación de ensayo, matriz posterior, tipos y reversa remotos:
  **PENDIENTES**.

Las guías Supabase y Context7 se usaron para la rama, sus credenciales separadas
y la documentación vigente. No se actualizaron CLI, servidor ni extensiones.

## Corrección del entorno y repetición de la base

Se verificaron tres omisiones de la reconstrucción, no del cambio de conversión:

- `crm_gestion_diaria_lector` estaba NOINHERIT y sin pertenencia a `authenticated`;
  producción tiene INHERIT y dicha pertenencia con INHERIT/SET, sin ADMIN.
- Faltaban seis conjuntos de metadatos técnicos privados, incluidos el sello
  de auditoría y sus exenciones. No son datos personales de clientes.
- Faltaba la política inicial de Gestión Diaria versión 1, histórica OFF.

Se repusieron exclusivamente en esta rama. El rol quedó igual al productivo;
el sello coincide con `private.huella_exenciones()` y la semilla histórica
existe. Auditoría activa; el guardia de inserción de política se restituyó
dentro de la misma transacción. No se amplió ningún permiso de producción.

**Verificación SQL de esas reparaciones: PASS.** La repetición HTTP focal
se detuvo en la precondición: el primer gate dejó 16 leads activos y la semilla
exige 7. **HTTP focal: NOT RUN por banco usado; precondición FAIL.** No se
omitió la precondición ni se alteró el gate para obtener verde. Las 22 aserciones
anteriores quedaron resueltas en la repetición integral descrita más abajo.

Antes de repetir, conservar la evidencia y reconstruir la misma rama sintética
con fixture limpio; preparar un respaldo limpio para las fases posteriores.
No crear otra rama, no tocar otros bancos y no copiar clientes productivos.
Después: baseline limpio, candidata, matriz pertinente, escritores HTTP,
advisors/tipos y reversa. Tras el PASS de baseline2 se restauró el snapshot
limpio (PASS) y se instaló la candidata exacta mediante apply_migration, sólo
en esta rama autorizada. `crm.conversion_politica.activada_en` sigue NULL.
La matriz general posterior, `matriz-candidato.log`, está EN CURSO; sesión
local del operador 26512. No equivale todavía a un PASS de la candidata.

Miguel confirmó «sí» después de recibir los enlaces a la migración exacta y
al activador privado, y la petición de autorización conjunta con `$release-crm`.
La autorización es condicional a las pruebas, no permite omitir sus fallos.
Huellas aprobadas: migración SHA-256 `21e615f519164d2eb68437f0e358a0d37df1cf5dbbb8bf221f0d614f134dd896`;
activador privado SHA-256 `c21f972579a422e79455894ee2e139d080f65a31dde35068e2ee8a03154855ce`.

Se respaldó el banco usado en `antes-reinicio-baseline2.dump` (archivo privado,
3,9 MB, catálogo de recuperación verificado). La reconstrucción se revirtió
primero por una dependencia externa de FK; se identificaron las siete tablas
privadas dependientes y se enumeraron explícitamente, sin CASCADE. No se tocó
Auth ni los metadatos técnicos privados. Se retiraron únicamente datos sintéticos
recuperables del respaldo. El modo de réplica fue local a la transacción de
fixture, según LEEME-seed; quedó `origin` antes del test, con triggers activos.

Fixture nuevo: 7 leads activos; comprobación PASS. Snapshot limpio guardado
antes de repetir el gate, para reutilizarlo en la fase candidata.
`matriz-baseline2.log`: **PASS — 2267 aserciones, cero fallos, salida 0**.
Esta ejecución acredita el banco base limpio; no sustituye la matriz posterior
a instalar la candidata ni las pruebas de su política activa.
Revalidación productiva de sólo lectura a las 02:20 Lima: 108 entradas,
0 divergencias, 0 episodios nuevos, 0 identidades repetidas, septiembre abierto.

Control analítico adicional: `private.assert_analitica_leads_citas()` ya falla
igual en producción y en el banco base por tres declaraciones anteriores:
`crm.impacto_eliminacion_usuario_fn`, `private.ranking_capital_origen_filas` y
`private.ranking_conversion_origen_mes`. No se atribuye al candidato aún no
instalado; comparar el delta y no declarar ese control PASS.

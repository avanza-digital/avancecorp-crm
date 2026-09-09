# F5 — prepublicación y corrección del salto de cartera

Actualización: Miguel confirmó el SQL original y el banco temporal. La prueba
remota está terminada y dejó dos correcciones documentadas en
[INSTALACION-2026-09-09.md](INSTALACION-2026-09-09.md). Se conserva abajo el
registro de la publicación de la web; sus pendientes reflejan aquel momento.

Fecha: 2026-09-09. Codex PRIMARY; Claude SECONDARY_REVIEWER solo de lectura.

## Alcance y autorización

Miguel aprobó el recorrido manual guiado de VoiceOver y pidió continuar el plan.
Después informó que la cartera saltaba durante la navegación. Autorizó publicar
su corrección y continuar la preparación de F5 con «ok hagamos eso y seguimos
con el plan por favor». La instalación del SQL F5 conserva su revisión y
confirmación separadas; este cambio no habilita operaciones económicas.

## Defecto confirmado y corrección

La web servía el release `crm-20260909T045534Z-887bef6e1bda`, construido desde
`887bef6e1bda65f2eb65b8cb9ae00d093f2bf883`. Su chunk
`mi-cartera-LJrQIGVL.js` ya contenía la comprobación de capacidad F5 cada 15 s.
El SQL F5 no está instalado: la RPC responde `PGRST202`. Al repetir una consulta
sin datos que había fallado, la consulta volvía a pendiente y desmontaba la
cartera Avance, cerrando la ficha y perdiendo los filtros. Se reprodujo contra
un backend HTTP sintético; también se cotejó el JavaScript publicado.

El commit `0eb66b79f61bfff3ff260ff76b6c53cfcaad30a3` convierte únicamente la
ausencia de esa RPC de capacidad en un resultado válido con lectura F5 y
escritura deshabilitadas. Así se conserva la vista durante la comprobación.
Los errores de permisos y del servidor siguen propagándose; las otras RPC
mantienen su contrato. Una respuesta posterior con F5 habilitada sigue siendo
detectada. No cambian SQL, banderas, comisiones ni permisos del servidor.

## Verificación y revisión

- Reproducción antes del arreglo: FAIL porque desaparecía la ficha al refrescar.
- Después: PASS en tres pruebas de navegador (persistencia de filtros/ficha,
  revocación de acceso y detección posterior de F5).
- Cuatro pruebas MSW con el cliente Supabase real: ausencia de la RPC de
  capacidad, denegación, fallo 503 y ausencia de otra RPC.
- Gate final `npm run check:all`: PASS; 3.131 pruebas unitarias en 222 archivos,
  150 recorridos de navegador y 26 omisiones preexistentes. Incluye lint,
  typecheck, cobertura, build, configuración de release y verificación del bundle.
  Persisten cuatro avisos de accesibilidad preexistentes de coverflow.
- Claude: primer intento sin dictamen válido; un reintento acotado devolvió
  `VERDICT: PASS`. Se aceptaron el tipo explícito del resultado y las pruebas
  HTTP. No se hicieron nuevas consultas tras incorporar esas recomendaciones.
- Riesgos residuales: los errores reales de red/servidor pueden seguir mostrando
  el panel de error; la compatibilidad conserva el sondeo y también el significado
  previo de `PGRST202` ante una firma no encontrada. No se cambió autorización
  ni se añadieron excepciones generales para ocultar esos errores.

El recorrido manual aprobado sigue limitado a cartera, ficha y campos del
formulario Qorilazo. Recuperación y errores con lector de pantalla: **NOT RUN**
manualmente; tienen cobertura automatizada. Ver [ACEPTACION.md](ACEPTACION.md).

## Destino y preflight de F5

Consulta de solo lectura a las 15:24 UTC:

- Proyecto `PortalAvanceCorp` (`dctqcbznekcyxhjujuci`), activo; Postgres 17.6.
- Prerrequisito F4 `20260908211349_crm_f4_publicacion_compatible_rentabilidad`
  instalado. No volver a ejecutar su candidata anterior.
- Migración F5 `20260908230249`, RPC de capacidad y tabla
  `crm.cartera_lecturas`: ausentes.
- `resolver_en_puertas=true`, `ficha_360_neutral=false`,
  `inversiones_escritura=false`.
- Hostinger: `crm.miavance.com`, usuario `u318796122`, sitio habilitado;
  `/home/u318796122/domains/crm.miavance.com/public_html`.

El censo usa solo SELECT y el cuerpo del lector candidato, sin instalar
funciones ni devolver datos personales:

| Empresa | Moneda | Fuentes | Sin identidad / no coherente |
| --- | --- | ---: | ---: |
| Avance | PEN | 468 | 3 |
| Avance | USD | 73 | 10 |
| Prodelco | PEN | 3 | 0 |
| Qorilazo | PEN | 14 | 2 |

Las 15 fuentes sin vinculación de identidad bloquean el encendido de F5, no
su instalación apagada. Requieren lotes F4 revisados; no se infieren identidades
ni se hace un backfill global. Las comisiones siguen fuera del CRM.

Advisors previos, sin F5 instalada: cero ERROR; seguridad 175 WARN/52 INFO y
rendimiento 5 WARN/104 INFO. Son la línea base, no una declaración de ausencia
de advertencias. Detalle completo conservado en el respaldo privado; reglas y
remediaciones en el [Database Linter de Supabase](https://supabase.com/docs/guides/database/database-linter)
y [protección de contraseñas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Paquete y siguiente paso

SQL exacto: [20260908230249_crm_f5_cartera_ficha_multiempresa.sql](../../migrations/20260908230249_crm_f5_cartera_ficha_multiempresa.sql).
SHA-256: `a13c7ec388993b8cba5299d61e33d9db1cff7d148146b06cbd0cd99cdcce22e5`.
El generador confirma nueve funciones y una tabla, sin cambios de banderas.
Los 38 ensayos de base local, replay, reversa y tipos del cierre anterior
siguen aplicando al mismo SQL; no se repitieron por este cambio de frontend.

El paquete de `133e4e5` queda obsoleto: contiene el defecto. Regenerar desde
el commit final sincronizado con Main y `avancecorp/main`. La publicación
del arreglo debe usar el ZIP estándar, su manifiesto y una copia limpia.
Antes de subirlo se preservó el ZIP exacto servido por producción, SHA-256
`57c12c4a3bf7c4513088f7b079dcc50e767a787fcd568be740ee0ea5c3fdd0b4`;
se verificaron todos sus archivos y la igualdad del index con la web real.

## Publicación del arreglo completada

Hostinger aceptó el ZIP y la limpieza de caché el 09/09. Verificación real
finalizada a las **16:09 UTC / 11:09 Lima**:

- Release `crm-20260909T160038Z-baad8cfad3e8`; versión
  `build-20260909T160038168Z`.
- Fuente `baad8cfad3e8ab23bc1aef2f96855944e47f102e`, igual a Main local,
  `avancecorp/main` y el remoto vivo antes de construir y antes de publicar.
  Incluye el cierre documental de Citas que llegó durante la preparación;
  su código de producto es idéntico al verificado en `da4d9d3`.
- ZIP SHA-256 `63600ca531370965541798667c0d3e6730b43fca00dcb1e28347e4ae306722f2`;
  80 archivos cotejados individualmente con el manifiesto, sin fuentes ni secretos.
- Los 79 archivos públicos devolvieron HTTP 200. Index, versión y 65 recursos
  coinciden byte a byte; los 12 PNG restantes conservan exactamente la
  transformación que ya servía Hostinger antes de subir el ZIP. Sus originales
  no cambiaron entre releases. `.htaccess` también coincide en contenido y tamaño
  mediante el lector de archivos de Hostinger.
- [GitHub quality/E2E](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/34373674625):
  job `quality` PASS al publicar; E2E remoto todavía en curso en ese momento,
  y finalizado posteriormente con **PASS**. Ambos jobs quedaron aprobados.
  La suite E2E local completa también pasó (150 recorridos).
  [RLS preflight](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/34373674661): PASS.
- Lectura posterior del servidor a las 16:11 UTC: `ficha_360_neutral=false`,
  `inversiones_escritura=false`, `resolver_en_puertas=true`; SQL F5 sigue ausente.
  No hubo migraciones, publicaciones Edge ni cambios de banderas en esta entrega.

El manifiesto de este release se conserva en `CRM-Avance-Corp/releases/`.
Los commits documentales posteriores describen la publicación; no cambian
el commit del ZIP que se verificó y publicó.

## Instalación F5 propuesta, pendiente de autorización

El siguiente paso es instalar el SQL exacto enlazado arriba: añade las consultas
de cartera/ficha/cuentas/documentos y el registro auditado de lecturas. No
registra inversiones, no calcula comisiones y mantiene F5 apagada. La tabla de
auditoría queda cerrada al acceso directo; las cinco RPC públicas conservan
su autorización del servidor y los cuatro auxiliares permanecen privados.

La prueba local del SQL ya está completada. El procedimiento de publicación
del repositorio exige además un banco Supabase dedicado: aplicar el archivo
aprobado, comprobar RPC/ACL/RLS/advisors, integrar y verificar producción antes
de desplegar `crm-inversion-documento`. Las ramas remotas existentes pertenecen
a otras tareas; no se reutilizaron ni modificaron.

Cotización leída para la organización del proyecto el 09/09: cómputo de rama
desde **US$0,01344/h**, más otros consumos que correspondan según
[facturación de Supabase](https://supabase.com/docs/guides/platform/manage-your-usage/branching).
No se confirmó el costo ni se creó la rama F5. Mostrar a Miguel el archivo SQL
y esta cotización para obtener una sola confirmación del paso completo.

La activación requiere resolver los 15 huecos de identidad y conserva los gates
F6, F7/G6, F8/G7 y F9/G8. Ver [README.md](README.md).

El paquete F5 se regeneró y verificó (81 archivos, SQL/reversa/función con SHA).
Después del commit de esta acta se prepara el paquete final desde el nuevo
Main sincronizado: su `manifiesto.json` identifica el commit exacto vigente.

Evidencia de trabajo: `/private/tmp/avancecorp-f5-prepublicacion-20260909/`.
Respaldo durable: `RESPALDOS-CARTERA/f5-publicacion-salto-20260909-1602/`, junto
al repositorio principal: ZIP publicado, reversa anterior, paquete F5,
historia Git y comprobaciones. Conservar también los respaldos de cierre F4/F5.

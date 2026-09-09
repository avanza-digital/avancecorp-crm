# F5 — prepublicación y corrección del salto de cartera

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

Estado al preparar esta acta: arreglo verificado, publicación pendiente.
Después registrar aquí el artefacto y la comprobación HTTP. La instalación F5
requiere mostrar y autorizar el SQL exacto; la activación económica mantiene
F6, F7/G6, F8/G7 y F9/G8. Ver [README.md](README.md).

Evidencia de trabajo: `/private/tmp/avancecorp-f5-prepublicacion-20260909/`;
copiar al cierre a `RESPALDOS-CARTERA/`, junto al ZIP nuevo y la reversa.

# F4 etapa 3 — Cortes de jornada

Estado: **implementada y verificada en local; publicación pendiente**.
Miguel pidió implementar/preparar y autorizó ensayar sólo el candidato
`20260921214018_crm_gestion_diaria_cortes.sql` en
`gestion_diaria_f4_vista_chvrqh`, incluida su reversión. No hay autorización
productiva, publicación ni activación. Plan: [GESTION-DIARIA.md](GESTION-DIARIA.md).

## Qué queda construido

Política `crm.politica_gestion_diaria` inmutable y versionada. La versión 1
histórica conserva 45/25/5 y deja los cortes apagados. F3 y F4 resuelven la misma
fuente al inicio del día consultado, no con la política de hoy.

Los parámetros tienen SELECT por columna bajo RLS. Motivo, autor y fecha
administrativa no son legibles directamente por ningún rol API, incluida
gerencia; el editor futuro tendrá una puerta propia. No hay DML de política
para authenticated/anon/service_role. La publicación con `expected_version`
y su pantalla son etapa 5, no se simulan aquí.

Cada revisión posterior exige autor, versión siguiente y vigencia a medianoche
Lima de una jornada futura no anterior a la última programada. La misma jornada
sí admite una corrección con versión mayor. La FK al perfil sigue el patrón
existente de las políticas CRM: no se modifican filas ni se emite ALTER sobre
`public`; la FK instala su dependencia referencial habitual.

`crm.gestion_diaria_equipo_fn` añade `cortes`, sin cambiar su firma. El núcleo
usa el roster autorizado y compone `private.gestion_diaria_llamadas` sin
modificarlo ni crear una segunda definición de llamada. El cliente admite
respuestas antiguas sin la clave, sin completarlas con ceros. `version: 1`
es la versión del contrato JSON; `politica_version` identifica la regla vigente.

Esta etapa **no modifica la pantalla**. Pop-up, reconocimiento y aplazamiento
son etapa 4. Un consumidor debe unir las filas por `analista_id`, no por posición;
el contrato de `DiaEquipoSchema` comprueba roster completo y ausencia de duplicados.

## Reglas y límites explícitos

De lunes a viernes hay cortes iniciales a las 11:30 (mínimo 3) y 16:00
(`min(30,max(8,ceil(base*2.5)))`). El sábado sólo 11:30, mínimo independiente 3;
domingo no evalúa. El calendario 09:00–18:00 / 09:00–13:00 es una regla fija
aprobada, no una nueva perilla. No se infieren feriados ni ausencias.

Las llamadas se acumulan desde medianoche Lima, incluidas no contestadas,
número errado y «no es la persona». Ventanas semiabiertas `[00:00,corte)`:
una llamada exactamente a las 11:30 no altera la base; sí puede recuperar
el primer aviso después de ese instante. Una llamada a las 16:00 exactas
ya no modifica el segundo corte ni recupera el primero.

El primer incumplimiento se retira si recupera antes del segundo corte.
El sábado puede recuperarse antes de las 13:00. El segundo conserva el
incumplimiento aunque llame después. `aviso_pendiente` expresa el resultado;
`puede_avisar` además exige día actual y jornada abierta. No es un reconocimiento:
**cerrar la jornada no borra el pendiente**, conforme a la decisión de Miguel.

La cartera se comprueba **al consultar**, con asignación y jerarquía actuales.
«Abierto» significa lead activo no convertido ni descartado. Sin cartera no
hay aviso de corte, pero se conserva la fila y las otras alertas. El histórico
no es una foto de lo que vio el supervisor entonces. Una corrección administrativa
del log puede cambiar el recálculo; nuevas llamadas posteriores al corte no
cambian su base. El instante de consulta ya viaja como `generado_en` del sobre.

`tasa_baja_diferencia_pp` sigue NULL y sin consumidor. Es diferencia en puntos
porcentuales, no una tasa absoluta; no se inventa el umbral ni se activa esa alerta.

## Verificación efectivamente ejecutada

### Complemento HTTP/Auth y matriz general — 21/09/2026, hora Lima

Miguel autorizó el banco separado `gestion-diaria-f4-http` y actualizar también
la matriz general. El SHA-256 del candidato no cambió. Resultado: baseline
**2.164 aserciones PASS** y candidato OFF **2.196 PASS**, cero fallos; las 32
adicionales de F4.3 se ejecutan obligatoriamente al detectar la migración.
Se actualizaron conversiones/fixtures al contrato vigente, no permisos del producto.

Instalación, excepción antes del commit, reversión de funciones/ACL/owner/comentario
con negocio y auditoría intactos, y reinstalación PASS. El nuevo banco termina
**instalado OFF**, a diferencia del ensayo SQL anterior. Siete respuestas HTTP
de equipo/analista mantienen el contrato en ambas transiciones. Los parsers de
Main `59dd1480` y del candidato aceptan ambos servidores: 28 casos PASS.

Playwright con login/API reales: dos supervisores aislados, detalle/registro,
analista, móvil y fallo de transporte sin falsos ceros PASS; repetido tras revertir
el servidor. SLA activo y seguimiento desde «No le interesa» PASS: actividad y tarea
persistidas, lead no descartado; modo inicial restituido y cortes siempre OFF.
22 E2E habituales (backend simulado) PASS, separados de esta evidencia real.
`npm run check` (4.085 tests / 272 archivos), `check:scripts`, preflights seed/RLS y Edge PASS; 25 pruebas
offline nuevas (17 guardas + 8 helper de conversiones).

Límites: handler Avance en proceso, no Edge desplegada; Edge de tipo de cambio
ausente en el banco; sin carga/concurrencia productiva ni activación. Dos consultas
Claude nuevas mediante wrapper no entregaron dictamen utilizable; no se registra
aprobación. El navegador integrado no estuvo disponible y se usó Playwright local.

Runbook de preparación: [F4-PUBLICACION-RECUPERACION.md](F4-PUBLICACION-RECUPERACION.md).
Scripts/evidencia: `supabase/scripts/gestion-diaria-cortes/http/README.md` y
`supabase/scripts/gestion-diaria-cortes/http/verificacion.json`.

### Ensayo SQL anterior (se conserva su alcance histórico)

Ensayo completo: **21/09/2026 22:19:30 UTC**, en Docker local por socket
Unix, base fija `gestion_diaria_f4_vista_chvrqh`. SQL SHA-256:
`8563bf8bf66e97a4e328d54582bbcf74e17f63d3d6056c6f9ae2dc4b9f940ea5`.

**PASS — banco SQL:** compilación, instalación y postflight F1–F4/SLA; políticas
OFF/histórica/futura y corrección de misma jornada; rechazo retroactivo, cadena
incorrecta y autor ausente; cero actividad, base 1/8/20, piso/techo/ceil, recuperación,
persistencia del segundo corte, fronteras exactas, sábado/domingo y medianoche Lima.
Lead inactivo/descartado/convertido excluido; analista revocado fuera del roster.
Paridad de cartera y cortes entre supervisor, gerencia y lector global, y de
umbrales entre las puertas F3/F4 para el mismo día. Las copias temporales cambian
sólo el reloj del código instalado, no reimplementan sus cálculos.

**PASS — permisos:** consultas reales bajo `authenticated` con identidades;
equipo ajeno, vendedor/coordinador, sesión sin identidad, supervisor revocado,
anon y service_role denegados según contrato. Motivo/autor y DML de política
denegados. Regresión de equipo, calendario, jerarquía (puentes inactivos/ciclos/
lector global) y núcleo SLA. **15 mutantes** de permisos, RLS, cuerpos, triggers
y redondeo detectados; incluye cuerpo y ACL de `umbrales()` heredado.

**PASS — restauración:** censo analítico idéntico; reversión exacta de las seis
definiciones previas y reinstalación determinista de sus cuerpos. El ensayo
termina **sin la tabla ni los helpers nuevos instalados**. Fixtures de negocio
revertidos por ROLLBACK. Se retiran sólo los objetos candidatos y su semilla OFF,
recuperables reinstalando el SQL; permanecen las entradas de auditoría local
de instalación, no se borra ese historial. La reversa se niega a eliminar
versiones posteriores a la semilla.

**PASS — tipos y cliente:** generación real desde la copia instalada y cotejo
exacto de la tabla; RPC compatible. `npm run check`: **4.073 tests / 272 archivos**,
lint, typecheck, cobertura, configuración de release, service worker, build,
bundle y duplicación. Advertencias previas de accesibilidad del coverflow y
tamaño de chunks, sin errores nuevos. Build local de prueba: **no es un artefacto
autorizado para publicar desde esta rama**.

**PASS — scripts:** `check:scripts`, siete pruebas offline nuevas y preflights
seed/RLS. Estos dos se ejecutaron con variables ficticias de loopback y sin
abrir conexiones: no prueban Auth ni PostgREST. Al ampliar el oráculo, un fixture
de descarte omitía su motivo obligatorio; se corrigió a `sin_interes` y el ensayo
completo posterior pasó. No se cambió el producto para eludir la restricción.

**Rendimiento local:** EXPLAIN ANALYZE/BUFFERS del roster mayor disponible
(3 analistas), con 6.000 llamadas ficticias por analista con cartera:
OFF 53,926 ms; ON 101,818 ms; cero bloques leídos de disco. El test comprueba
que ON realmente evalúa cortes. Mide volumen de llamadas, **no** concurrencia
ni un roster de tamaño productivo: no es una promesa de latencia.

**NOT RUN:** matriz HTTP completa `test-rls.mjs` sobre esta copia (no tiene
endpoint PostgREST propio), advisors remotos/producción, E2E visual nuevo,
publicación, activación, concurrencia de la futura puerta de publicación.
La matriz SQL/RLS local sí se ejecutó. El bloque HTTP permanente ahora exige
`cortes` si la tabla está instalada; opcionalmente también con
`CRM_RLS_EXIGE_CORTES=1`. No transforma una regresión en «no instalado».

## Revisión con Claude y decisión del PRIMARY

Dos revisiones mediante `scripts/claude-review`, read-only, sin agentes recursivos.
Último dictamen: **CHANGES_REQUESTED**, no se presenta como aprobación automática.
Codex resolvió los hallazgos con código y pruebas, sin una tercera consulta.

Se aceptaron grants por columna, resolutor sin SELECT `*`, autor obligatorio,
cadena futura ordenada con empates permitidos, comparaciones NULL-safe, ventana
vacía explícita del segundo corte sabatino, guarda de ocurrencia de cada reseñado,
y detección de migración instalada en el gate HTTP. Se añadieron casos de
cartera cerrada, revocación, paridad entre roles, puerta F3/F4 y carga sintética.

Se descartó como defecto confirmado la hipótesis de `p_ini` arbitrario: la puerta
F3 lo fija explícitamente como medianoche Lima del día pedido
(`20260920041500_crm_gestion_diaria_analista.sql:578–583`); el oráculo cruza ahora
las dos puertas con políticas diferentes por jornada. También se descartó que
`umbrales()` careciera de sello: `assert_gestion_diaria_analista` conserva sus
controles de owner/ACL/volatilidad/search_path y md5; dos mutantes lo demuestran.

El schema externo de equipo sí cruza cobertura por id; no hay que duplicar
ese chequeo dentro de `CortesJornadaSchema`. Se mantienen el fallo cerrado,
la ausencia de feriados inferidos y el pendiente visible después del cierre:
son contratos del proyecto o decisiones explícitas, no bugs que corregir.

Quedan para antes de **activar**, no ocultos como PASS: carga con roster y
concurrencia representativos, HTTP real, UI/negocio, escritura gerencial
concurrente y mecanismo de emergencia para detener la presentación de avisos
sin reescribir políticas históricas. No se habilita un cambio retroactivo
de reglas para resolver un problema de avisos.

Las guías de Supabase/PostgreSQL orientaron privilegios mínimos, RLS, composición
INVOKER, política histórica y ensayos reversibles. TypeSafe no decide cifras
ni permisos y no se usaron notas reales.

## Repetir y preparar publicación

Desde `CRM-Avance-Corp`:

- `npm run test:gestion-diaria-cortes:preflight`: sin SQL ni red.
- `node supabase/scripts/gestion-diaria-cortes/ensayar.mjs --ensayar-local`:
  sólo con autorización local; instala, prueba y termina revirtiendo.
- `--sellos-local` mide cuerpos en una transacción revertida; no edita archivos.

Evidencia resumida versionada: `supabase/scripts/gestion-diaria-cortes/verificacion.json`.
La reversa de este banco **no es un runbook productivo** para borrar versiones.

Publicación pendiente: integrar sin sobrescribir el trabajo concurrente,
comprobar Main local = `avancecorp/main`, obtener autorización del SQL exacto
y ejecutar el flujo humano `$release-crm`. SQL primero, cliente compatible después,
artefacto construido sólo desde el commit verificado. No usar un `db push` general.
La política inicial seguirá OFF. La siguiente implementación es **etapa 4:
pop-up, reconocimiento y posponer**, seguida de configuración (5) y activación (6).

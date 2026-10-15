# Plazo de carga por mes (migración 20261015000852)

**Estado (15/10/2026, Lima): APLICADA, REGISTRADA Y VERIFICADA EN PRODUCCIÓN (~10:40, pasos 1–4 de abajo).** Sigue: publicar el front (paso 6), que Gerencia fije el plazo de septiembre (paso 7) y reactivar el ciclo (paso 8). El primer ensayo en producción (15/10, 01:15) se negó sin escribir: `crm.cerrar_periodo` está declarada en el censo analítico de producción y el banco de solo esquema no tenía esa fila. Corregido con el re-sellado de su huella (plantilla de `20261013145852`) y probado sobre los registros reales de producción.

Gerencia decide hasta qué día se pueden cargar las ventas de un mes (sin tope; nunca antes del día 10 del mes
siguiente; solo un mes con metas publicadas, porque el ciclo solo sella esos: revisión Codex r2) y, si ese mes ya está
sellado y es el anterior al mes en curso, lo reabre con la misma acción. Diseño:
[`docs/plans/plazo-carga-mes/DISENO.md`](../../../docs/plans/plazo-carga-mes/DISENO.md). La reapertura reproduce, en el
mismo orden y con las mismas comprobaciones, la de septiembre del 14/10
([`../reexpresion-septiembre-2026/01-reabrir.sql`](../reexpresion-septiembre-2026/01-reabrir.sql)), sin `ALTER TABLE` ni
GUC: la fila de `crm.reaperturas_mes` es la autorización de los candados, solo para ese mes, solo en esa transacción (su
id y su instante, que fija un trigger) y, para un cierre en cooperativa, solo si esa reapertura lo respaldó y solo para
devolver su imputación a la fecha comercial (nada más de la fila, tampoco con la válvula de corrección abierta). La
autorización vale para la transacción superior entera, incluidas sus subtransacciones: es una sola llamada a la puerta.
`crm.cerrar_periodo` vuelve a mirar la ventana después de tomar sus candados: un sello que esperaba mientras Gerencia
ampliaba el plazo de ese mes se niega (22023) en vez de sellar antes de tiempo (revisión Codex r1, P1).

Nada de esta carpeta corre contra producción por sí solo: lo corre Miguel con `!`, en el orden de abajo.

| Archivo | Qué es |
|---|---|
| `../../migrations/20261015000852_crm_plazo_carga_mes.sql` | La migración: preflight por huellas de lo vivo, dos tablas, CHECK, núcleo, dos puertas, permisos, comentarios y postflight (incluye intentos que deben rebotar y la foto de trinquetes antes/después). Una transacción. |
| `registrar/20261015000852.sql` · `generar_registrador.py` | Registro en `supabase_migrations.schema_migrations` (`db query --file` NO registra). Regenerarlo si cambia la migración (lleva su md5). |
| `vista-previa.sql` | Se pega detrás de la migración en el ENSAYO (paso 1): muestra la lectura de Gerencia y lo que haría fijar el plazo de septiembre. Si esa operación simulada falla, el ensayo entero falla (no dice «ENSAYO OK»). Termina en ROLLBACK. |
| `verificar-produccion.sql` | Solo lectura, después de aplicar y registrar: veredicto (exige las 14 huellas exactas de lo creado o reemplazado), plazos vigentes, ciclo y trinquetes. |
| `reactivar-ciclo.sql` | Reactiva el job 3 (`crm-cierre-mes-diario`) SOLO si Gerencia ya fijó el plazo de septiembre y está en el futuro. |
| `reversa.sql` | Retira la migración (esquema) al byte. Se niega si ya hay decisiones o reaperturas. |
| `prueba.sql` | 186 casos por escenario en el banco, en 12 bloques (termina en ROLLBACK). |
| `mutantes.py` | 62 mutantes (cada uno debe hacer caer una aserción; el M49 solo desde el día 11 del mes) + 4 controles de defensa redundante que sobreviven a propósito. |
| `dos-sesiones.py` | Lo que no se ve en una sesión: otra transacción no hereda la autorización; la puerta espera los candados global y mensual, y la reevaluación el de la identidad; el sello que esperaba a una ampliación se niega (a mano y por el ciclo); mutantes sin esos candados y con el sello de antes. |
| `integracion-permisos.mjs` | `node supabase/scripts/test-rls.mjs --plazo-carga-mes`: Auth y PostgREST reales con escrituras (ampliar y REABRIR), en un banco LOCAL; limpia al terminar. |
| `huella-esquema.sql` | Huella del esquema que toca la migración: igual antes de aplicarla y después de la reversa. |
| `transporte.py` | Los guiones de producción tal como se mandan (un mensaje). Con el JSON de `leer-registros-produccion.sql` como segundo argumento, el mundo lleva los registros REALES de los trinquetes: el ensayo del paso 1 (y que falla si la operación simulada falla), el ciclo aplicar → registrar → verificar → reversa, 5 mutantes del re-sellado, la negativa de la reversa y el registrador. 21/21. |
| `leer-registros-produccion.sql` | RECOMENDADO ANTES DEL ENSAYO, solo lectura: los registros de los trinquetes (censo analítico, F7, vigencia, auditoría) y el cron de producción, para sembrarlos en el banco (`transporte.py <banco> <json>`). Un banco de solo esquema no los tiene: por eso el primer ensayo del 15/10 se negó. |
| `../test-rls.mjs` (bloque «Plazo de carga por mes») | En el gate general: rechazos por rol y la lectura de Gerencia, sin escribir (una decisión es historia permanente). |

## Pasos en producción (Miguel con `!`, desde `CRM-Avance-Corp/`)

Orden por dirección: **servidor primero** (la pantalla nueva llama a dos funciones que hoy no existen), después el front.

1. **Ensayo sin escribir** (la migración entera + la vista previa, en una transacción que termina en ROLLBACK):

   ```
   ! { sed '/^commit;$/d' supabase/migrations/20261015000852_crm_plazo_carga_mes.sql; cat supabase/scripts/plazo-carga-mes/vista-previa.sql; } > /tmp/ensayo-plazo-carga.sql && npx supabase db query --linked --file /tmp/ensayo-plazo-carga.sql
   ```

   Se espera UNA fila `vista_previa` con `"resultado": "ENSAYO OK: …"`, la lectura de Gerencia (septiembre abierto,
   plazo base el 10/10) y `fijar_septiembre_hasta_dentro_de_7_dias` con `reabierto: false` y cuántas acreditaciones
   «fuera de plazo» pasarían a acreditadas (`acreditaciones_reevaluadas`) o chocarían por identidad
   (`conflictos_identidad`). Si sale `PREFLIGHT …`, `POSTFLIGHT …` o `VISTA PREVIA: …`, **parar**: algo vivo no es lo
   revisado, o fijar el plazo de septiembre fallaría.
   (El ensayo toma un momento los candados del cierre y deja de pasar escrituras de acreditaciones de septiembre unos
   segundos; mejor fuera de horas de carga.)
2. **Aplicar** (un solo mensaje; si falla, no escribió nada):
   `! npx supabase db query --linked --file supabase/migrations/20261015000852_crm_plazo_carga_mes.sql`
3. **Registrar** en el ledger de Supabase (después de aplicar; idempotente):
   `! npx supabase db query --linked --file supabase/scripts/plazo-carga-mes/registrar/20261015000852.sql`
   → fila `version_registrada = 20261015000852`.
4. **Verificar** (solo lectura):
   `! npx supabase db query --linked --file supabase/scripts/plazo-carga-mes/verificar-produccion.sql`
   → `"veredicto": "APLICADA Y REGISTRADA"` (exige las 14 huellas de abajo: `huellas_ok: true`, `huellas_distintas: {}`),
   `decisiones: 0`, `reaperturas: 0`, plazo de septiembre = 11/10 00:00 (base) y `ciclo_diario.activo: false` (sigue en
   pausa).
5. **Tipos**: en `app/`, `npm run gen:types`; debe salir igual al `database.types.ts` de esta rama (79 líneas nuevas:
   las dos tablas y las dos funciones).
6. **Front**: fusionar la PR y `/release-crm` (tarjeta «Plazo de carga» en Configuración, solo Gerencia; publicada primero en Hoy el 15/10 y movida el mismo día).
7. **Gerencia fija el plazo de septiembre** desde la pantalla («Ampliar plazo»: septiembre ya está abierto, no se
   reabre). Al guardar, la conversión «fuera de plazo» de septiembre se reevalúa sola. (Solo un mes con metas publicadas
   admite plazo: septiembre las tiene; un mes sin metas responde «no tiene metas publicadas: no tiene cierre ni plazo de
   carga».)
8. **Reactivar el ciclo diario** (solo si el paso 7 ya está hecho y el plazo está en el futuro; si no, se niega sin
   tocar nada):
   `! npx supabase db query --linked --file supabase/scripts/plazo-carga-mes/reactivar-ciclo.sql`
   → `"CICLO DIARIO REACTIVADO"`. El ciclo sellará septiembre a las 09:20 de Lima del día siguiente al último día que
   fije Gerencia, y luego seguirá con octubre en su fecha.

Después de este flujo, `../reexpresion-septiembre-2026/02-resellar.sql` y `03-restaurar.sql` quedan **superados**: no
usarlos (02 sella con el ciclo, que ya respeta el plazo; 03 se niega en cuanto cambie la huella del mes).

Alternativa al paso 2–3: branch de Supabase + merge (la práctica de `20261014174026`). El archivo es una sola
transacción y no depende de nada de la sesión; si se usa el merge, el registro lo hace el merge (no correr el paso 3).

## Huellas (md5 de `pg_get_functiondef` con `search_path` vacío)

Antes (producción del 14/10, ancladas en el preflight): `conversion_plazo_hasta` `81fb7f2e…`, `conversion_decidir_plazo`
`07c1c7f0…`, `cierre_mes_ventana_desde` `fe15a998…`, `trg_cierre_mes_append_only` `51d92430…`, `f4_fuente_inmutable`
`808b1ac3…`, `trg_cierres_externos_inmutables` `34fd3c38…`, `crm.cerrar_periodo` `70e1ba04…`. Después (las que lleva el
preflight de `reversa.sql` y exige `verificar-produccion.sql`): `crm.cerrar_periodo` `93f09c45…`,
`crm.fijar_plazo_carga_mes` `d9ff1cf1…`, `crm.plazos_carga_mes_fn` `4e7fdee8…`, `fijar_plazo_carga` `927fd44b…`,
`plazos_carga_mes_lectura` `91cd95da…`, `conversion_plazo_hasta` `4ce98468…`, `reabrir_mes` `9983ea77…`,
`reapertura_autoriza(date,uuid)` `2dd1b119…`, `reapertura_impedimento` `bcd7f90a…`, `conversion_reevaluar_plazo`
`6154da0f…`, `trg_reaperturas_mes_llave` `961723b9…`, `f4_fuente_inmutable` `f4608368…`, `trg_cierre_mes_append_only`
`d0c47d99…`, `trg_cierres_externos_inmutables` `c9f55c70…`. Archivo de la migración: md5 `9821d93a…` (el que lleva el
registrador).

## Reversa

`! npx supabase db query --linked --file supabase/scripts/plazo-carga-mes/reversa.sql` — deja el esquema al byte como
antes (plazo fijo IMMUTABLE, los tres candados sin la rama de reapertura, el CHECK de igualdad con su nombre
`conversion_acreditaciones_check3`, `crm.cerrar_periodo` con su cuerpo de antes, sin tablas ni puertas). **Se niega** si
ya hay decisiones de plazo o reaperturas (se
perdería su historia y el plazo de un mes) o si alguna acreditación guarda un plazo distinto de la base. En ese caso la
salida es una migración nueva. Antes de revertir, retirar la tarjeta del front. La fila del registro se conserva.

## Banco (cómo se probó, y cómo repetirlo)

Banco Docker propio: stack local de Supabase con `project_id` `avancecorp-plazo-carga-20261014` y puertos 57420–57429
(config en un directorio temporal; el `config.toml` del repo no se tocó), esquema de producción del 14/10 por
`supabase db dump --linked --schema public,crm,private --keep-comments` (solo estructura), montado como
`../categoria-por-operacion/banco/montar.sh` (roles, extensiones, pg_cron, privilegios por defecto) sin datos.

```bash
B=supabase_db_avancecorp-plazo-carga-20261014
psql() { docker exec -i -e PGPASSWORD=postgres $B psql -X -U postgres -h 127.0.0.1 -d postgres "$@"; }
psql -At -F' || ' < supabase/scripts/plazo-carga-mes/huella-esquema.sql            # huella ANTES
docker cp supabase/migrations/20261015000852_crm_plazo_carga_mes.sql $B:/tmp/m.sql
docker exec $B sh -c 'PGPASSWORD=postgres psql -X -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -c "$(cat /tmp/m.sql)"'  # UN mensaje
psql -v ON_ERROR_STOP=1 -f - < supabase/scripts/plazo-carga-mes/prueba.sql       # PRUEBA PLAZO CARGA OK: 186 casos
python3 -I supabase/scripts/plazo-carga-mes/mutantes.py $B                        # 62 de 62 mueren; C1–C4 sobreviven
python3 -I supabase/scripts/plazo-carga-mes/dos-sesiones.py $B                    # 14/14 PASS
python3 -I supabase/scripts/plazo-carga-mes/transporte.py $B                      # 9/9 PASS
PLAZO_API_URL=… PLAZO_DB_URL=… PLAZO_ANON_KEY=… PLAZO_SERVICE_ROLE_KEY=… node supabase/scripts/test-rls.mjs --plazo-carga-mes   # 42 PASS
psql -v ON_ERROR_STOP=1 -f - < supabase/scripts/test-cierre-mes.sql               # oráculo del cierre: 22/22 antes y después
# reversa (UN mensaje) → huella-esquema.sql igual a la de ANTES → volver a aplicar → prueba.sql otra vez en verde
```

Las llaves del stack local salen de `supabase status --workdir <stack> -o env` (son las de desarrollo; no se imprimen).

## Revisión

Subagente `auditor-rls` (14/10): CHANGES_REQUESTED sin P0/P1. Aceptados y aplicados: **P2** la válvula del cierre
externo dejaba cambiar cualquier columna del cierre del mes en la transacción de la reapertura → ahora solo la
imputación, solo a la fecha comercial, nada más de la fila y solo de una venta que la reapertura respaldó (casos y
mutantes M13b–d, M10b, M14c); **P3** la llave (mes, transacción) se podía escribir → la fija un trigger y la autorización
exige además el instante de la transacción (M14b, M14d); **P3** el respaldo copiaba documento y nombre del cliente →
ya no, y la auditoría vuelve a ser `log_audit_crm` (así el rastro tardío retirado queda en `public.audit_log`); **P3** la
puerta aceptaba un mes sin sellar por detrás del último cierre → 22023 (M42b); **P3** capas: la puerta valida, autoriza
y delega en `private.fijar_plazo_carga` / `private.plazos_carga_mes_lectura`; brechas: candado de identidad con dos
sesiones (T5/T6), reapertura por HTTP, M49 consciente del día, salto ruidoso con `CRM_RLS_EXIGE_PLAZO_CARGA=1`.
Documentado sin cambiar código: lo que se pierde frente a 01 (la huella y `03-restaurar.sql`: deshacer una reapertura =
volver a sellar, y la foto se recalcula; la puerta permite reabrir el mes anterior más de una vez).

Codex r1 (14–15/10, `scripts/codex-review-mcp`, LEVEL 3): **FAIL**, 1 P1 + 2 P2 + 3 P3, todos con evidencia; aceptados y
corregidos los seis puntos de código y la vista previa:
- **P1** la carrera documentada era peor que lo dicho: con «sin tope», un mes que ya no es el anterior podía sellarse
  antes del plazo ampliado (y la pantalla no lo puede reabrir). Ahora `crm.cerrar_periodo` (cuerpo vivo + 13 líneas)
  vuelve a mirar la ventana con los candados tomados y se niega (22023); el ciclo lo anota en su `fallo` y al día
  siguiente ya ve el plazo nuevo. Probado con dos sesiones de verdad a mano y por el ciclo (T7) y con el cuerpo de
  antes como mutante (T8, idéntico al que restaura la reversa).
- **P2** con la válvula `crm.op_privilegiada` encendida, la rama de la reapertura de `f4_fuente_inmutable` dejaba cambiar
  el monto o la nota junto con la imputación: ahora exige la fila entera igual salvo la imputación (casos en B9, M07).
- **P2** un mes abierto con una decisión vigente, sin metas, desaparecía de la lectura al dejar de ser el mes anterior:
  ahora entra (B11, M51). De paso, un nombre en blanco sale «(sin nombre · …)» (el front exige texto no vacío; M52).
- **P3** la regla de identidad de la reevaluación va ANTES de decidir el estado, como en el escritor (también para una
  fuente demo o de cartera: queda intacta y cuenta como conflicto; B6 A13, M53).
- **P3** llave única `(transaccion, reabierto_en)`: un id de transacción repetido tras restaurar un volcado no impide
  una reapertura legítima (B9, M54).
- **P3** alcance de la autorización documentado: la transacción superior entera, incluidas sus subtransacciones; deshacer
  la que registró la reapertura la retira (B9; M56 cambia el instante de la llave).
- La vista previa ya no dice «ENSAYO OK» si la operación simulada falla (transporte E1b).

Codex r2 (15/10, última ronda): **FAIL por 1 P2, sin P0/P1**; confirmó que las correcciones de r1 cierran sus hallazgos.
- **P2** el ciclo solo sella meses con metas (`private.cierre_mes_pendiente`): un mes SIN metas con un plazo ampliado
  podía quedar saltado al sellarse el siguiente y después sin sello ni decisión modificable. Aceptado: solo un mes con
  metas publicadas admite plazo y reapertura. `private.fijar_plazo_carga` lo comprueba tras los candados y antes de mirar
  el sello (22023 «… no tiene metas publicadas: no tiene cierre ni plazo de carga»; tampoco reabre) y
  `private.reapertura_impedimento`, tras «no está cerrado» («… no tiene metas publicadas: el ciclo no lo volvería a
  cerrar»; la lectura lo muestra como motivo). Casos en B11 y mutantes M57/M58; las siembras que fijan plazo publican
  metas (B3 el mes en curso; B4 hace tres meses, como estado heredado; dos sesiones y transporte, el mes anterior).
- Prueba pedida: con M ampliado al futuro y M+1 con su ventana abierta, el ciclo sale en M sin sellar M+1 y
  `crm.cerrar_periodo(M+1)` se niega por «Falta cerrar» (B12): los meses siguientes esperan.
- Con la regla de metas, la rama de la lectura «meses abiertos con decisión» (Codex r1) queda redundante: todo mes con
  decisión tiene metas (la puerta lo exige y `crm.meta_periodos` es inmutable). Se conserva y su mutante pasa a control
  (C4, sobrevive a propósito).
Rechazado con evidencia: que la reevaluación «deje una identidad guardada vieja» (`inversionista_id`): el escritor
tampoco la refresca en su rama de reintento (devuelve la fila tal cual si la fuente no cambia), así que no es una
regresión de esta migración. Riesgos que Codex dejó como hipótesis sin objeto demostrado (dependencias transitivas de
lo IMMUTABLE, efectos de triggers no transcritos): sin hallazgo en el censo, el postflight ni las baterías.

## Lo que el banco NO acredita

- Los datos reales: el ensayo del paso 1 es el que corre preflight, postflight, foto de trinquetes y la vista previa
  contra producción.
- Los registros de los trinquetes (F7, exenciones analíticas, vigencia, auditoría) están vacíos en un volcado de solo
  esquema: en el banco se comparó la foto de los 36 `assert_*` y el censo antes y después (idénticos); la migración
  repite esa comparación en producción en su postflight.
- Advisors de Supabase (son de la nube) y la matriz general de `test-rls.mjs` (necesita el seed de una branch).
- La carrera del sello con una ampliación se probó con dos sesiones en el banco (T7/T8); en producción la cubre el mismo
  cuerpo de `crm.cerrar_periodo` (huella `93f09c45…`), pero no se ensaya contra el ciclo real.

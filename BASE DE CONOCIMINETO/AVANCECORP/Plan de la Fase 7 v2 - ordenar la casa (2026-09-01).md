# Plan de la Fase 7 v2 — «ordenar la casa» (2026-09-01)

Plan por tramos para retirar lo muerto con el método de Miguel: **CERRAR → OBSERVAR → DERRIBAR**,
con su OK por pieza y acta en el libro. **Esta es la v2: la v1 la auditó Codex y dio NO SIRVE.**
Los errores de la v1 y su corrección están al final, porque la lección importa tanto como el plan.

Relacionado: [[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]] · la sección F7
de `CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md` · [[Verificacion del Portal para la Ola 3 - el selector no se llama (2026-08-31)]]

## Estado medido el 01/09 (contra producción)

El libro `private.f7_piezas_en_observacion` tiene **14 filas**:

| Grupo | Qué son | Cerradas | Demolibles |
|---|---|---|---|
| 7 gemelas (F5.d) | crear/actualizar contrato con producto, en `crm` y `public` | 30/08 | **13/09** |
| 3 tableros (F7.1) | altas por analista · distribución de leads v1 y v2 | 31/08 | **14/09** |
| 4 pasillos (F7.1) | `cerrada_permanente` — no se demuelen nunca | 31/08 | — |

`vigia_alertas`: 0 filas. Los gates F7/vigencia/analítica/auditoría, verdes.

## 🔴 Los 14 días NO se tocan

La v1 proponía sustituir el CHECK de 14 días por «una regla con fundamento». **Se elimina esa idea.**
Razón medida: el mínimo no vive en un sitio, vive en **cinco** — el CHECK de la tabla, el trigger que
impide reducir `drop_no_antes_de`, el `assert_f7_piezas_cerradas` que rechaza una demolición
temprana, el postflight que exige literalmente `cerrada_en + 14`, y las fechas guardadas en cada
fila. Cambiarlo no es «ajustar un número»: es desmontar el trinquete entero que Miguel aprobó.
**Las fechas 13/09 y 14/09 se respetan.**

Lo que sí puede añadirse **para cohortes futuras** (nunca para acortar ésta): un requisito
ADICIONAL de evidencia guardada como dato en la fila — intervalo observado, fuentes, cobertura,
conteos y responsable. Para piezas de uso mensual, la fecha sería `máximo(14 días, primer cierre
posterior)`.

## 🔴 Lo que la evidencia PUEDE y NO PUEDE decir

- ⛔ **No se puede saber «cuántas veces se llamó» hacia atrás.** Medido: `track_functions = none`
  (Postgres no cuenta llamadas por función: sus ceros significan «no se mide», no «nadie llamó») y
  `pg_stat_statements` acumula desde el **2026-04-25** sin línea base en el cierre.
- ✅ **Sí se puede saber si alguien REBOTÓ.** Las piezas están revocadas: un intento real muere en
  `42501` y `log_min_error_statement = error` lo escribe en los registros del servidor. Eso es
  exactamente lo que el método pedía en D+7 y D+14.
- ⚠️ La retención de esos registros es corta y hay que declarar la ventana observada. **La ausencia
  de logs NUNCA se convierte en «cero uso probado»**: se reporta como «sin evidencia de uso en la
  ventana X, con cobertura Y».

## Los tramos

### A · La evidencia, con cobertura declarada  *(D+7 = 06/09 y D+14 = 13/09)*
- **Problema:** el vigía prueba que la puerta sigue cerrada, no que nadie la intentó abrir.
- **Qué:** leer los registros de producción buscando rebotes `42501`/`PGRST202` contra las 10 firmas,
  declarando el intervalo real cubierto y la retención. Más el censo estructural (que ya corre) y el
  estado del vigía. Codex refuta la medición.
- **Termina cuando:** cada pieza tiene su línea de evidencia CON su cobertura, no una impresión.
- ⚠️ Requiere el conector de Supabase que lee logs (hoy caído) o el panel.

### B · Cerrar `cerrar_altas_legacy_productos` ANTES que las gemelas  *(nuevo, lo trajo la auditoría)*
- **Problema medido:** esa función **nombra tres de las siete gemelas** (`crear_contrato_producto`,
  `actualizar_contrato_producto`, `actualizar_contrato_con_cuenta_producto`) para comprobar su
  existencia. Demoler las gemelas primero la deja devolviendo error. La v1 no lo veía.
- **Qué:** decidir su destino primero — retirarla (entra en el libro con su propia observación) o
  reescribirla para que no dependa de piezas que van a morir.
- **De Miguel:** su OK, porque es una pieza más que se cierra.

### C · Demoler las 7 gemelas  *(13/09 o después)*
- **Qué:** migración transaccional que las elimina, con **captura previa de su definición viva desde
  producción** (owner, ACL, atributos y comentario) como material de marcha atrás — el repo tiene 167
  de 193 archivos y F5.d cambió sus cuerpos después de nacer: la fuente es el REGISTRO, no la carpeta.
- **Artefactos — corrección de la v1:** `test-productos-inversion.sql` (1.559 líneas) **NO se retira**:
  es parte de `gate:config` y prueba también snapshots, inmutabilidad, selección y ACL. Se **poda**
  quirúrgicamente. Lo mismo con los mocks e2e: comparten ramas con los endpoints PDF **vivos**. Y
  `test-rls` debe pasar a exigir `PGRST202` exacto (hoy espera `42501`, que es lo correcto mientras
  existan).
- **Guardas:** cero alertas del vigía en preflight Y postflight (si aparece una, se para; no se
  «resuelve» dentro del paquete destructivo), acta por firma, ledger.
- **De Miguel:** OK por pieza y su `!`.

### D · Demoler los 3 tableros  *(14/09 o después)*
- **Corrección de la v1:** «esperar a que pase el cierre» **no es la condición** — son puertas de
  pantalla que aceptan cualquier rango de fechas, no funciones del cierre mensual. Su condición es la
  suya: su fecha y su evidencia. El sello del 10/09 se observa, pero no decide.
- **Ojo:** `metricas_altas_analista_fn` no tiene archivo local; su partida de nacimiento está en el
  registro remoto (versión `20260716203331`). Capturar la definición viva antes del DROP.

### E · El catálogo de productos — 🔴 ALCANCE MAL PLANTEADO EN LA v1
- **Lo medido:** el catálogo **no es retirable entero**. `public.contratos.producto_condicion_id` es
  **NOT NULL con FK RESTRICT** y **los 492 contratos la tienen llena**; el trigger
  `trg_contratos_producto_snapshot` está vivo en la tabla de contratos y participa en las altas
  actuales; las tres tablas versionadas tienen datos históricos.
- **Y el selector se usa en más sitios de los que vi:** además de la pantalla de Configuración, lo
  usa **«Corregir contrato»** (`contrato-corregir.tsx`) y el resumen de Configuración.
- **Alcance correcto:** lo retirable es **la UI administrativa y sus RPC de gestión**. Las tablas,
  los datos, la FK, la columna, el trigger y los metadatos de producto en las respuestas **se quedan**
  y salen del alcance de la Fase 7, declarado.
- **De Miguel — LA DECISIÓN:** ¿se retira la pantalla «Productos de inversión» y su gestión, o se
  queda? Con el matiz nuevo: aunque se retire, el catálogo sigue vivo por debajo porque los contratos
  dependen de él.
- **Si se retira:** front primero (release + verificar bundle vivo + drenar pestañas viejas) →
  observar los endpoints → REVOKE → 14 días → DROP.

### F · La segunda pasada
- **Corrección:** el «203» es un conteo crudo inútil como prueba de muerte. El criterio real es
  **privilegio efectivo** (`has_function_privilege` para anon/authenticated/service_role/PUBLIC,
  membresías incluidas) **en esquema expuesto** (`public`, `crm`, `graphql_public`), más dependencias
  por OID (triggers, vistas, policies, defaults, índices de expresión), `cron.job`, edges desplegadas
  —no solo las del repo—, `.gs`, Portal y bundles viejos.
- **Regla:** toda RPC expuesta con EXECUTE es superficie pública hasta demostrar lo contrario.

## Lo que la v1 se dejaba (y ahora está dentro)

- Las revisiones **D+7 y D+14** ya comprometidas en el ledger.
- El **freeze 08–10/09**: nada destructivo en esos días.
- **Stop-the-line**: cualquier alerta abierta para el tramo, y no se resuelve dentro del mismo
  paquete que demuele.
- **Acta y ledger por CADA firma** — un `!` a una migración no es aprobación individual de cada DROP.
- **Mutante de la fecha/CHECK** en el gate: hoy sus mutantes prueban «alerta abierta» y «vigía
  apagado», no la ventana temporal.
- Las **deudas del ciclo de banco** (mutante de herencia service_role, fixtures de atribución,
  mutante de ATR-4, absorción de deuda numerador-pura), bloqueadas por el aprovisionamiento.

## Las tres cosas que necesito de Miguel

1. **La decisión del catálogo** (tramo E), sabiendo ya que retirarlo no lo elimina por debajo.
2. **El destino de `cerrar_altas_legacy_productos`** (tramo B), que bloquea el tramo C.
3. **Sus `!` y su OK por pieza** cuando cada tanda esté ensayada y refutada.

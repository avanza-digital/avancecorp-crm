# Paso 3a «SLA por filas»: kit v3 tras el Codex de cierre · RESULTADO

17/10/2026, 14:35 → 14:52 (hora de Lima, tomada con `date`).

- **Qué se cambió:** SOLO el kit `supabase/scripts/sla-por-filas/`:
  - `reversa-m1/m2/m3.sql`;
  - `registrar-indice.sql`;
  - `registrar-reversa-m1/m2/m3.sql`;
  - `LEEME.md`.
- **Qué no se tocó:** M1–M3, `verificar.sql`, `test-rls.mjs`, `fase2/arnes/`, `MIGRACIONES.md`, `carga-3a/`, el banco 1
  (`foto-sla-f2-db`, 55620), producción, git, Codex y otros agentes.
  - M1–M3 y `verificar.sql` salen **byte a byte iguales** del generador v3. Se generaron en una carpeta aparte y se compararon
    con `cmp`; nunca se escribieron sobre el repo.
- **Cómo se generó:** con `ensayo-3a/migraciones/generar.py`, v3; la v2 queda en `generar.v2.py`. Solo cambia la parte del kit.
  Una copia del kit v2 queda en `kit-v3/kit-v2-copia/`.
- **Dónde se ensayó:** en un banco PROPIO, `foto-sla-f2-db-kit`, en 127.0.0.1:55622, con el volumen `foto-sla-f2-db-kit-data`.
  - **Montado** a las 14:45:05 con `fase2/banco/montar.sh` (11 s, 1 error esperado). La VM tenía 4,3 GiB libres; el banco usó
    108 MiB.
  - **Llevado a ANTES = producción** con las 3 migraciones del 16/10, igual que el banco 1 (`162937`, `183308` y `190408`, la
    opt1): `SERIE=ANTES · familia SLA=62 · 1adaf6c5… (la esperada)` y los 3 guardianes del SLA en OK.
  - **Parado y borrado** a las 14:50:07: contenedor y volumen, los dos creados por mí. La red compartida `foto-sla-f2-red` ya
    existía y no se tocó.
  - Todas las conexiones pasan por `kit-v3/comun.sh`, que se niega si la cadena no apunta al 55622.

## En corto

- **48 de 48 pasos como se esperaba, 0 inesperados** (14:48:53–14:49:00). Cada negativa sale por el motivo correcto: el mensaje
  de cada una está en `kit-v3/resultados-pasos.txt`.
- **Los 4 contraejemplos de Codex se niegan:**
  - el registrador de otra generación;
  - la segunda reversa registrada sin ejecutarla;
  - la versión ocupada antes de revertir;
  - el corte antes del registro.
- **Reproducción cronológica completa por versión ascendente:**
  - 9 eventos: originales → R3 < R2 < R1 → reaplicación con versiones nuevas;
  - se reprodujeron sobre ANTES con un índice vacío: **0 fallos**;
  - la huella del catálogo final es **igual** a la del estado vivo (`1112 · 64150c96…`), y el índice reproducido es igual al
    guardado;
  - `verificar`: `SERIE=M3 · 64 · f9ea9038…`.
- **Mutante Unicode `U&"…\0066ilas"`: la reversa M1 se niega.**
  - El control positivo demuestra que el consumidor resuelve a `_filas` (sale 42501 «No autorizado») y que la búsqueda por
    nombre no lo ve.
  - En el esquema de producción hay 0 cuerpos con `U&"`.
- **El ciclo normal sigue pasando:** aplicar M1 → M2 → M3 registrando, y revertir M3 → M2 → M1 registrando cada una.
  - Tras el ciclo, la huella del catálogo es la de ANTES (`1110 · 1525d824…`).

## Cada punto → cambio → prueba

| # | Punto | Cambio (kit v3) | Prueba en el banco del kit |
|---|---|---|---|
| 1 | Registradores: validar la TRANSICIÓN | Bloque común «historial de la serie»: reproduce las filas de la serie en orden de versión (`collate "C"`) con la máquina de estados ANTES → M1 → M2 → M3 y vuelta. Da el estado del historial, la última aplicación de cada mN y la versión máxima. **`registrar-indice`**: se niega si el historial va por delante de la serie viva, si la aplicación vigente de una mN es de otra generación, o si la versión por registrar está ocupada o no es posterior a la serie. **`registrar-reversa-mN`**: se niega si el último evento no es la aplicación de mN de su generación, o si la versión no es mayor que TODAS las de la serie (así R3 < R2 < R1). Idempotentes solo para el MISMO evento. | **CE1:** el registrador ORIGINAL con la serie reaplicada se niega, primero por «versión 054425 ocupada» y, con la generación 2 ya registrada, por «otra generación (990011)». **CE2:** la segunda reversa M3 (990002) sin ejecutar se niega con «el último evento… no es la aplicación de m3». **Orden:** la reversa M2 registrada con 990000 < R3 se niega; la R3 registrada con 054420 se niega. El mismo evento otra vez pasa: 0 nuevas y 3 vigentes / «ya estaba registrada». |
| 2 | Reversas: su versión y «registrar antes de revertir», ANTES del DDL | Marca `v_esta_version text := 'AAAAMMDDHHMMSS';`, que se rellena al copiar la reversa a la migración nueva y es su único cambio. Con el índice presente, la reversa se niega si: la marca está sin rellenar; la versión está ocupada o no es posterior a la serie; el historial no es válido; la aplicación de mN no es el último evento; o es de otra generación. Sin índice, igual que antes. El registrador registra la plantilla con su versión. | **CE4:** reversa M3 con M3 viva sin registrar → «registrar antes de revertir: el historial va por M2». **CE3:** versión ocupada por la serie (054426) y por una migración ajena (980000) → «ya está ocupada»; la serie sigue en M3. Marca sin rellenar → se niega. Reversa M3 otra vez (990001 ocupada, o 990005 nueva) → se niega. La negativa sale en la línea 43 del bloque (`CONTEXT … line 43 at RAISE`); el último RAISE del historial está en la 55 y el primer DDL en la 326 (M3), 166 (M2) y 233 (M1). |
| 2 | Callejón del corte | Las mismas comprobaciones, desde los dos lados. | Con la reversa M3 confirmada sin registrar: `registrar-indice` se niega («hay una reversa ejecutada sin registrar; regístrala antes») y la reversa M2 también. Con `registrar-reversa-m3`, todo sigue. |
| 2 | LEEME | El orden de versiones (`054427 < R3 < R2 < R1`), «registrar antes de revertir», generaciones y el corte después de una reversa. | — |
| 3 | Unicode | La reversa M1 se niega si algún cuerpo fuera de `pg_catalog`/`information_schema` contiene `U&"` (`~*`). El LEEME documenta el límite: lo dinámico y lo escapado. | Mutante `private.U&"sla_operacion_autorizada_\0066ilas"(NULL::uuid[])`, en ROLLBACK → se niega. Regresión: MAYÚSCULAS y vista sobre `_filas` → se niegan. |
| 4 | `v_exigidas_ok` en los registradores de reversa | **Decisión: no bloquea; lo informa.** La reversa no exige esas piezas, para poder volver atrás pese a cambios ajenos; exigirlas al registrar dejaría una reversa confirmada imposible de registrar. Sale en la última fila: «AVISO (no bloquea, ver LEEME): piezas exigidas CAMBIADAS… EXIGIDA CAMBIADA: <firma> def=<md5>». `registrar-indice` las sigue exigiendo, igual que M1–M3. | En ROLLBACK, con el productor cambiado: reversa M3 + su registrador → «registrada; serie viva M2 · AVISO… EXIGIDA CAMBIADA: private.sla_operacion_leads(…) def=c6bc0caa…». Tras el ROLLBACK, M3 y exigidas IGUALES. |
| 5 | GATE no es aprobación | LEEME: la línea identifica el estado de la serie; el veredicto exige además los 3 guardianes del SLA en OK y leer el informe. | — |
| 6 | Transporte de `verificar.sql` (rechazado: no se cambió) | LEEME: la evidencia de producción del 17/10 (`fase3/produccion/verificar-ANTES-20261017.txt`, `db query --linked --file`, informe completo). | `verificar.sql` byte a byte igual al de la v2 (`912be092…`). |
| — | Salida visible | Los 4 registradores dejan su informe en la última fila (`set_config` + `select`), porque `db query` no muestra los avisos. | En todos los pasos «ok» aparece la fila `REGISTRO…`. |

## El ensayo, paso a paso (`kit-v3/ensayo.sh`)

Se hizo con un índice de PRUEBA (`supabase_migrations.schema_migrations`, con la forma del de Supabase) y con las versiones de
prueba R3 `990001` < R2 `990002` < R1 `990003` y la reaplicación `990011/12/13`. Las copias de prueba cambian una sola línea
(diff de 2), igual que en producción.

- **A · ciclo normal con los originales:**
  - M1 → registrar (1 nueva) → M2 → registrar (1 nueva, 1 vigente) → M3;
  - CE4 → registrar (1 nueva, 2 vigentes) → registrar otra vez (0 y 3);
  - marca sin rellenar, CE3 ×2 y una versión anterior a la serie → se niegan;
  - R3 → callejón ×2 → registrador sin versión y con versión anterior → se niegan;
  - registrar R3 → otra vez → CE2 → R2 sin ejecutar → R3 otra vez ×2 → R2 con versión menor → se niegan donde toca;
  - R2 → registrar con versión menor (se niega) → registrar R2;
  - mutantes Unicode, MAYÚSCULAS y vista → se niegan; control Unicode;
  - R1 → registrar R1 → R1 otra vez (se niega) → M1 original (se niega) → registrar en ANTES (se niega);
  - huella = ANTES.
- **B · reaplicación con la generación 2:** M1, M2 y M3 nuevas.
  - CE1, y la reversa original sobre M3 sin registrar → se niegan.
  - Registrar con la generación 2 (3 nuevas) → otra vez (0 y 3).
  - Reversa original (otra generación), CE1 otra vez y M3 nueva repetida → se niegan.
- **C · reproducción:**
  1. Se guardó el historial de la serie (9 filas, sin la ajena) y se quitó el índice.
  2. Vuelta a ANTES con las reversas de la generación 2 en modo banco: sin índice, la marca sin rellenar está permitida. La huella
     coincide con la ANTES inicial.
  3. Con un índice vacío, por versión ascendente: se ejecutó el texto registrado y después se insertó su fila. Así se simula el
     ejecutor de migraciones.
  4. Resultado: 9 de 9 con rc=0. Huella final = estado vivo. Índice reproducido = guardado (md5 por versión, nombre y texto).

## Huellas del kit v3 (SHA-256)

| Archivo | SHA-256 |
|---|---|
| `reversa-m1.sql` | `75dea5dbf295975abaa85d8ba5721799195b8f19cee41aa77eb56a09ff7311f8` |
| `reversa-m2.sql` | `f2f7b4e2a043c846a947a3ef3eb185a054370d4b800e28f953adb8d24da6cf1c` |
| `reversa-m3.sql` | `6b0e58a41bd36d1c5096aaa6c22d106c17bb6c4c75888bd968b15cef2d4bacab` |
| `registrar-indice.sql` | `f081633cc234aa38fde0d6ec0dead95449bd0d36c7a6970da42083669fa64368` |
| `registrar-reversa-m1.sql` | `c19061049fd40c0b9dbaf91122c8977ac7cb7deeeceaf0358e435a40ee4072d3` |
| `registrar-reversa-m2.sql` | `78a477717971305c029f60c07a3879a567fe0fc56caa5ab3c24407d739f0e177` |
| `registrar-reversa-m3.sql` | `20e417a7b925c5a72da0fcbd8dd1f4308f25e640d6c788d7dbf471495c6bc151` |
| `verificar.sql` (sin cambios) | `912be092e4855ec4f68509967c1fb135b99e01da99f1ed0af434ba7a1b10b083` |
| M1 / M2 / M3 (sin cambios) | `e9c491d6…` / `468624e2…` / `94f695cb…` |

## Lo que queda abierto

1. **Qué archivo se ejecutó no se puede acreditar al 100 %.** Todas las generaciones dejan las mismas huellas. El kit v3 lo
   acota así:
   - cada mN se niega si su versión ya está en el índice;
   - los registradores y las reversas solo aceptan su generación y la transición válida siguiente.

   Atar versión y hash al DDL en la misma transacción exigiría cambiar M1–M3, y no se tocan.
2. **La reproducción es una simulación del ejecutor:** ejecutar el texto y después insertar la fila. No es un `supabase db
   reset` real, que además reproduciría las migraciones ajenas en su orden.
   - Las reversas solo exigen ser posteriores a la SERIE.
   - Que sean posteriores a TODO el índice lo cumple una migración creada «ahora», pero el kit no lo impone.
3. **Límite de la reversa M1:** no puede descartar las llamadas dinámicas por partes. Ante `U&"` se niega de forma conservadora;
   si un cuerpo legítimo lo usa, hay que revisarlo a mano.
4. **Ajenos a este encargo**, de la respuesta de Codex:
   - la corrección del informe de carga (temporales del escenario «peor»), en `carga-3a/`;
   - RLS integral con fixtures;
   - las 71 cadenas NOT RUN;
   - Gestión Diaria concurrente;
   - el experimento factorial de `estado`.
5. **Censo del banco del kit:** `47 · 2472bb54…`, frente a `45 · ff12620b…` del banco 1. Aquí no se sembraron los registros de
   control. Solo se usó para comparar dentro de este banco; la huella del catálogo es la comparación que cuenta.

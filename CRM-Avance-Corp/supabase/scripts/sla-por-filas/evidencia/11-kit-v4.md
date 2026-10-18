# Paso 3a «SLA por filas»: kit v4 tras el Codex de verificación · RESULTADO

17/10/2026, 16:14 → 16:29 (hora de Lima, tomada con `date`).

- **Qué se cambió:** SOLO el kit `supabase/scripts/sla-por-filas/`:
  - `reversa-m1/m2/m3.sql`;
  - `registrar-indice.sql`;
  - `registrar-reversa-m1/m2/m3.sql`, ahora retirados;
  - `verificar.sql`;
  - `LEEME.md`.
- **Qué no se tocó:** M1–M3, `test-rls.mjs`, el arnés, `MIGRACIONES.md`, `sla-por-filas/evidencia/`, el banco 1, producción, git,
  Codex y otros agentes.
  - **M1–M3 siguen byte a byte iguales.** El generador v4 las saca idénticas; se compararon con `cmp` en una carpeta aparte y
    nunca se escribieron sobre el repo. SHA-256: `e9c491d6…`, `468624e2…` y `94f695cb…`.
- **Cómo se generó:** con `ensayo-3a/migraciones/generar.py`, v4; la v2 queda en `generar.v2.py`. Una copia del kit v3 está en
  `kit-v4/kit-v3-copia/`.
- **Dónde se ensayó:** en el banco PROPIO `foto-sla-f2-db-kit` (127.0.0.1:55622, volumen `foto-sla-f2-db-kit-data`), con el
  procedimiento de la v3.
  - Se montó con `montar.sh` y se llevó a ANTES = producción con `162937`, `183308` y `190408`:
    `SERIE=ANTES · 62 · 1adaf6c5… (la esperada)`.
  - Se montó tres veces, una por corrida:
    - corrida 1: 16:22:19 → 16:24:44;
    - corrida 2: 16:24:53 → 16:25:39;
    - corrida 3: 16:27:30 → 16:28:00.
  - Cada vez se borraron el contenedor y el volumen, los dos creados por mí. La red compartida no se tocó.
  - Las conexiones pasan por `kit-v4/comun.sh`, que se niega si la cadena no apunta al 55622.

## En corto

- **Corrida final (la 3, 16:27:41–16:27:50): 49 de 49 pasos como se esperaba, 0 inesperados.** Cada negativa sale por su motivo;
  el detalle está en `kit-v4/resultados-pasos.txt`.
- **P1: las reversas se registran a sí mismas en la misma transacción que su DDL.**
  - En las 4 reversas ejecutadas con índice, la fila registrada es exactamente el bloque ejecutado: el md5 de `statements[1]` es
    igual al md5 del bloque de la copia.
  - Sin permiso de INSERT en el índice, la reversa no deja nada: la serie sigue en M3 y las filas siguen en 4.
- **Contraejemplos de Codex:**
  - **(a) «R ejecutada y R′ registrada» ya no puede pasar.** R se registra con su propia versión al ejecutarse.
    - El registrador v4 está retirado y se niega con «RETIRADO».
    - Hasta el registrador VIEJO v3 con R′ se niega, porque el último evento ya es la reversa.
  - **(b) «R3 pendiente + reaplicar M3 + registrador original "0 nuevas y 3 vigentes"» también se niega.** R3 no puede quedar
    pendiente. Con M3 reaplicada (generación P, 995020):
    - el registrador original se niega con «054427 ocupada»;
    - el de la generación 2 se niega con «otra generación»;
    - solo el de la generación P, la que se ejecutó, la registra.
- **P2, orden global.** Con una migración ajena X (995000) posterior a M3, la reversa con 990001 se niega antes del DDL: «no es
  posterior a TODO el índice (máximo 995000)».
  - `verificar.sql` informa «Versiones del índice posteriores a 20261017054425 que no son de la serie: 1».
  - `registrar-indice.sql` lo informa con un AVISO, sin bloquear.
- **P2, NULL.** `v_esta_version := NULL`, la vacía `''` y la marca sin rellenar se niegan antes del DDL. El RAISE está en la
  línea 45 del bloque y el primer DDL en la 174, 241 o 334; la serie sigue en M3.
- **Reproducción cronológica de TODO el índice** (12 filas: serie + ajena X + reversas auto-registradas + reaplicaciones), por
  versión ascendente sobre ANTES: **0 fallos**. La huella final es igual a la del estado vivo (`1112 · 64150c96…`), el índice
  reproducido es igual al guardado y `verificar` da `SERIE=M3 · f9ea9038…` con «coincide: SÍ».
- **Sin índice, como el arnés, todo sigue igual:** las reversas (incluso con NULL) y M1–M3 corren como siempre, no se registra
  nada y `verificar` dice «Índice de migraciones: AUSENTE».

## Cada punto → cambio → prueba

| # | Punto | Cambio (kit v4) | Prueba en el banco del kit (corrida 3) |
|---|---|---|---|
| 1 | El registro no identificaba el evento | Cada `reversa-mN.sql` lleva su bloque ejecutable en un literal (`v_cuerpo`) y lo ejecuta. El bloque es autosuficiente: fija `lock_timeout`, `search_path` y `quote_all_identifiers`, comprueba historial y versión antes del DDL, ejecuta el DDL y las poscondiciones, y pasa su versión al envoltorio por un ajuste local de la transacción. **Con el índice presente, el envoltorio inserta en la MISMA transacción** la versión `v_esta_version`, el nombre `crm_sla_<pieza>_por_filas_revertir` y `statements = [v_cuerpo]`. Sin índice no inserta nada. Los `registrar-reversa-mN.sql` quedan como avisos «RETIRADO (kit v4)» que no leen ni escriben. | Las 4 reversas con índice (R3 995001, R3 de P 995021, R2 995022, R1 995023) se registran solas, y su fila es el bloque ejecutado (md5 igual). **Atomicidad:** con INSERT retirado a postgres, la reversa falla con `permission denied for table schema_migrations` y no queda nada (M3, filas 4 → 4). **(a):** el registrador retirado → RETIRADO; el v3 con R′ 995009 → «el último evento… no es la aplicación de m3»; la misma reversa otra vez → «995001 ocupada». **(b):** tras R3, M3 de P (995020) → ok; el registrador original → «054427 ocupada»; el de la generación 2 → «otra generación»; el de P → 1 nueva y 2 vigentes. **Por fuera del kit:** una reversa del kit VIEJO v3 (que no se registra) + `registrar-indice`, en ROLLBACK → «el esquema cambió por fuera del kit… investigar». |
| 2 | Orden global | Antes del DDL, la reversa exige una versión **mayor que el máximo de TODO el índice** (`max(version::numeric)` de las versiones numéricas). `verificar.sql` informa «Versiones del índice posteriores a <M1 de la generación> que no son de la serie: N» y, además, «Historial de la serie en el índice: <estado> · coincide con la serie viva: SÍ/NO · eventos…». `registrar-indice.sql` añade a su informe ese mismo número, con AVISO si no es 0, sin bloquear. El LEEME dice que antes de M1 tiene que dar 0 y que, si no, no se aplica y se avisa. | **Publicación:** con una ajena 100000 registrada en ANTES, `verificar` da «…: 1». Con el índice vacío da 0. **Con la ajena X 995000** (exige `_filas`, ejecutada y registrada tras M3): el registrador da «0 nuevas y 3 vigentes · …: 1 (AVISO, no bloquea)»; la reversa M3 con 990001 → «no es posterior a TODO el índice (máximo 995000)»; con 995000 → ocupada; la reversa M2 con 995019 < 995021 → se niega. |
| 3 | NULL | `if v_esta_version is null or (v_esta_version ~ '^[0-9]{14}$') is not true` antes del DDL. El envoltorio vuelve a rechazar una versión NULL antes de insertar. | NULL, `''` y sin rellenar → «no tiene una versión válida (vacía, NULL o sin rellenar)». `CONTEXT … line 45 at RAISE`, frente al primer DDL en la 334 (M3), 174 (M2) y 241 (M1); la serie sigue en M3. Sin índice, NULL no se usa y la reversa M1 corre (fase D). |
| 4 | Transporte de `verificar.sql` (no se cambia) | LEEME: una petición POSTERIOR por la misma vía funciona. El 17/10, tras el `verificar.sql` con P0001, Miguel corrió por `db query --linked` el conteo H1 (`count = 0`). El 16/10, la serie de la opt1 corrió verificar → migración → verificar → registro sin `25P02`. Es la vía del Management API, una petición por conexión. | — (lo da el PRIMARY; el conteo H1 no está en un archivo que yo haya visto) |
| 5 | Ensayo | `kit-v4/ensayo.sh`, en 4 fases (abajo). | 49 / 0. |

## El ensayo, paso a paso (`kit-v4/ensayo.sh`, corrida 3)

Versiones de prueba:
- originales: `054425/26/27`;
- ajena X: `995000`;
- R3: `995001`;
- generación P (M3 sola): `995020`, y su R3: `995021`;
- R2: `995022`;
- R1: `995023`;
- generación 2: `995031/32/33`.

Las copias cambian una sola línea (diff de 2).

- **0 · publicación inicial:** ajena 100000 en el índice → `verificar` da «…: 1» (no aplicar y avisar). Se recrea el índice
  vacío → da 0.
- **A · con los originales:**
  - M1 → `verificar` da «Historial: ANTES · coincide: NO» → registrar → M2 → registrar → M3;
  - CE4 (reversa con M3 sin registrar) → «registrar antes de revertir» → registrar;
  - ajena X → registrar (AVISO 1) → la prueba «por fuera del kit» → orden global, NULL, vacía, ocupada, sin rellenar: todas se
    niegan;
  - atomicidad → R3 (se registra sola) → (a) ×3 → (b) ×4 → reversa original sobre la M3 de P (otra generación) → R3 de P;
  - R2 con versión menor (se niega) → R2 → mutantes Unicode, MAYÚSCULAS y vista (se niegan) → R1;
  - M1 original (se niega) → registrar en ANTES (se niega) → huella = ANTES.
- **B · generación 2:**
  - M1, M2 y M3 nuevas;
  - los registradores original y P → «054425 ocupada»;
  - el de la generación 2 → 3 nuevas → otra vez → 0 y 3.
- **C · reproducción:**
  1. Se guardó TODO el índice (12 filas) y se quitó.
  2. Vuelta a ANTES sin índice con las reversas de la generación 2, sin registrar nada. Huella = ANTES inicial.
  3. Con un índice vacío, por versión ascendente: se ejecutó cada `statements[i]` y después se insertó su fila. Las reversas
     reproducen su bloque, que vuelve a comprobar historial, versión y orden global con lo reproducido hasta ahí.
  4. Resultado: 12 de 12 con rc=0, huella = estado vivo e índice = guardado.
- **D · sin índice:** reversas M3 y M2 del kit sin rellenar y M1 con NULL → ok, ANTES. M1, M2 y M3 originales → ok, M3.
  `supabase_migrations` AUSENTE: nada registrado.

**Corridas anteriores (contadas aparte, no se mezclan):**
- **Corrida 1** (`resultados-pasos-corrida1-arnes-roto.txt`): 46 / 2 inesperados, **por un fallo de MI arnés**.
  - `psql -c` no sustituye variables `:'v'`, así que la fila de la ajena X no se insertó. El índice no tenía nada posterior y la
    reversa 990001 pasó con razón.
  - Arreglé el arnés (dollar-quoting y fallo explícito) y monté un banco nuevo.
- **Corrida 2:** 48 / 0.
- **Corrida 3:** 49 / 0, tras cambiar solo el mensaje de una negativa de `registrar-indice` (ya no remite al registrador
  retirado) y añadir la prueba «por fuera del kit».

## Huellas del kit v4 (SHA-256)

| Archivo | SHA-256 |
|---|---|
| `reversa-m1.sql` | `827896d5b2fc542a6d3ddd55f2412a6590649e2d5053d0c86f37106bc0e31b72` |
| `reversa-m2.sql` | `3e61a41263d9748c1e13d5a6dd60e460bccc5c09669ad0514d91a2b244858aa9` |
| `reversa-m3.sql` | `d28872aa0606fbbcae3147ff1e0192ab6e28f441ce8c9472a1b2aa2f232a179e` |
| `registrar-indice.sql` | `63208ebe46d0eb6ed05c731d738a0b526f1d0342da88e0e3db5915f6981cabd6` |
| `registrar-reversa-m1.sql` (retirado) | `6e4cb2318ebbc2a297622ce0e6d4cf6963e3320ae129b7ad9ef739304dfad82f` |
| `registrar-reversa-m2.sql` (retirado) | `e97bf7643baad02abaa333c1fe0f48a5fb61ca05e4d0ffed107873911b2ce4c4` |
| `registrar-reversa-m3.sql` (retirado) | `078dbb072ceca3dcabdc90ba3d23de89a60e1515365bf945c368baaac0766bc7` |
| `verificar.sql` | `3d5b89ec07f0ccc717899742d10f216cb520da5ae5ae272d03396a31cfaf5eef` |
| M1 / M2 / M3 (sin cambios) | `e9c491d6…` / `468624e2…` / `94f695cb…` |

## Lo que queda abierto

1. **Las APLICACIONES M1–M3 siguen sin constancia propia de su versión**, porque sus bytes no se tocan. El registrador las
   identifica por exclusión:
   - cada mN se niega a correr si su versión ya está en el índice;
   - el registrador solo acepta su generación y la transición siguiente;
   - las reversas ya no pueden quedar pendientes.

   Con dos generaciones que tengan libre la versión de la misma mN, habría que usar el kit de la que se ejecutó. En producción
   solo existe la original.
2. **La reproducción simula el ejecutor** (ejecutar `statements` y después insertar la fila); no es un `supabase db reset`
   real. La ajena X es de prueba.
3. **`registrar-indice` solo informa del orden global; no lo bloquea.** El DDL ya está hecho. La comprobación que cuenta es la
   de `verificar.sql` antes de M1: tiene que dar 0.
4. **El conteo H1 del 17/10** lo cito tal como lo dio el PRIMARY; no lo vi en un archivo.
5. **Andamiaje del ensayo:** `kit-v4/` (generaciones 2 y P, copias de prueba y resultados). El banco del kit ya no existe.

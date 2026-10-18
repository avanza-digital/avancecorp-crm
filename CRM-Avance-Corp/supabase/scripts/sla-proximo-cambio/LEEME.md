# SLA · «próximo cambio» en el mismo paso (`20261016190408`)

Mejora corta del plan «foto del SLA». Decisión de Miguel del 16/10/2026: hacerla por el disco.

## Qué cambia

Solo `private.sla_operacion_autorizada(uuid[], boolean)`.
- **Antes:** calculaba `proximo_cambio_en` recorriendo otra vez todo `v_filas` con `jsonb_array_elements`.
- **Ahora:** sale con `min()` en el mismo `SELECT` que arma `v_filas`.

Son 3 líneas (`cambio.diff` del plan). Firma, `SECURITY DEFINER`, `search_path`, dueño, ACL, volatilidad, paralelismo y comentario
quedan igual. Ninguna puerta, pantalla, tabla, policy ni grant cambia.

| | Huella `md5(prosrc)` | Huella de la familia SLA (62 funciones) |
|---|---|---|
| Antes | `0f4f44bed201e7eeb00301d82cc6401f` | `e17a083b3a64459b8f2f888928e03849` |
| Después | `a5fd870bf432dc907f5849a61a5fb9a8` | `1adaf6c5708637fd916705cc090a4218` |
| Productor exigido (`private.sla_operacion_leads`) | `e47f610fb4cde0741f2a22c3e2e7ee2c` | — |

## Evidencia

Banco Docker con el esquema de producción al byte; datos sintéticos calibrados con producción (±3 %).
- **Mismo resultado.** 2.403 comparaciones, con 0 diferencias, en una sola sentencia y con el mismo reloj:
  - los 35 usuarios;
  - entradas de cola, avisos, vacías, repetidas, inexistentes y ajenas;
  - errores y estados adversariales.
  Un verificador independiente añadió 43 más, también con 0 diferencias.
  - Única frontera: una zona horaria POSIX de ±16 h o más, con la que los dos cuerpos fallan igual. En producción no se alcanza:
    `TimeZone` = `UTC` y ningún rol ni base la cambia.
- **Con carga** (arnés, 30+ consultas pesadas a la vez, ABABAB): **−16 a −19 % de escrituras temporales**. No equivale a ese
  porcentaje del I/O total ni demuestra una mejora de latencia. La memoria total no cambia de forma medible.
- **Guardianes del SLA** (`assert_sla_nucleo`, `assert_cola_v3`, `assert_sla_avisos`): OK con la mejora.
- **Censo analítico:** 48 → 48.
- **Vigías nocturnos:** ninguno la sella. En producción, 0 de 15 patrones de F7 cambian.
- **Con ESTA migración aplicada en el banco** (verificador + revisor independiente):
  - 163 de 163 casos iguales al cuerpo anterior (49.785 filas; 35 usuarios; incluir `true`/`false`; 3 errores con el mismo SQLSTATE);
  - 20 de 20 llamadas a las puertas como `authenticated`, con la misma forma (1.621 rutas JSON);
  - planes: los mismos 2 `Sort` y un recorrido menos (`jsonb_array_elements(v_filas)`);
  - 8 llamadas seguidas en el mismo proceso, con planes genéricos desde la 6.ª: todas iguales.
- **Mutante:** si un guardián del SLA falla dentro de la transacción, la migración aborta y no queda nada aplicado (comprobado).
- **CI local** (`crm-rls-preflight`): 4/4 PASS. La suite completa `test:rls` queda NOT RUN: necesita una pila con fixtures que este
  banco no tiene. El cambio no toca permisos, y los casos existentes `test-rls.mjs:9038-9052` (`proximo_cambio_en` de la cola v3)
  ya pasan por la línea cambiada. Va al próximo ciclo de banco.
- **Migración ensayada en el banco como `postgres`** (el dueño):
  1. aplica;
  2. se niega a aplicarse dos veces;
  3. la reversa revierte;
  4. la reversa se niega a revertir dos veces;
  5. vuelve a aplicar.
- Revisiones de Codex al plan y su detalle: carpeta `foto-sla/fase2/plan-opt1/` de la copia aislada (sin versionar).

## Aplicación en producción (con el «!» de Miguel; nunca `db push` ni `apply_migration`)

Desde el commit ya fusionado en `avancecorp/main`:

```bash
npx supabase db query --linked --file supabase/scripts/sla-proximo-cambio/verificar.sql   # ANTES: cuerpo=ANTERIOR · e17a083b…
npx supabase db query --linked --file supabase/migrations/20261016190408_crm_sla_proximo_cambio_en_un_paso.sql
npx supabase db query --linked --file supabase/scripts/sla-proximo-cambio/verificar.sql   # DESPUÉS: cuerpo=MEJORA · 1adaf6c5…
```

- **`verificar.sql` es de solo lectura impuesta**: corre en `BEGIN READ ONLY` y termina siempre en `raise`; el informe sale en el
  mensaje del error.
  - **Los 7 guardianes deben dar el MISMO resultado antes y después.**
  - El 16/10, en producción, ya fallaban `assert_gestion_diaria`, `assert_analitica_leads_citas` y `assert_analista_vigencia`, por
    cambios ajenos (`actividades_select`, `cartera_filtrada_fn` y `proteger_campos_inmutable`).
- **La migración es atómica.** Exige la huella viva, el productor, los metadatos y el md5 del DDL ensayado. Después comprueba el
  resultado y TODOS los atributos de la función, y corre `assert_sla_nucleo`, `assert_cola_v3` y `assert_sla_avisos` antes del
  `commit`. Si algo no cuadra, falla con `PREFLIGHT`/`POSTFLIGHT` o con el error del guardián, y no queda nada aplicado.
- **Advisors** (`get_advisors` de seguridad y rendimiento) antes y después: se esperan sin alertas nuevas, porque no cambian ni
  `search_path` ni ACL.
- **Registrar la fila del índice SOLO si el `verificar.sql` de DESPUÉS da lo esperado**: `version` `20261016190408`, `name`
  `crm_sla_proximo_cambio_en_un_paso`. Marcar la fila de `MIGRACIONES.md` como APLICADA, con fecha.

## Si hay que revertir

El índice de migraciones solo crece: **nunca se borra la fila de `20261016190408`**.
1. Crear una migración NUEVA, `AAAAMMDDHHMMSS_crm_sla_proximo_cambio_revertir.sql`, con el contenido de `reversa.sql`.
2. Aplicarla con `db query --linked --file`, entre dos corridas de `verificar.sql`. La de DESPUÉS debe dar `cuerpo=ANTERIOR ·
   e17a083b…` y los mismos guardianes.
3. Registrar su fila en el índice y marcar `20261016190408` como REVERTIDA en `MIGRACIONES.md`, con el motivo.

`reversa.sql` solo actúa si sigue viva exactamente la mejora (`a5fd870b…` y sus metadatos). No exige el productor ni corre
guardianes, para que nada ajeno bloquee una vuelta atrás.

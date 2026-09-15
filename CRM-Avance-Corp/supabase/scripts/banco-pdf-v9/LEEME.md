# Banco del ensayo · plantilla v9 del PDF de contrato

Ensayo de `20260915005752_crm_contrato_pdf_plantilla_v9_cotitulares.sql` sobre una base
PostgreSQL 17.6 local y aislada, sin tocar producción ni el banco compartido de Supabase.

## Cómo se corre

```bash
psql -h 127.0.0.1 -p 55322 -U postgres -d postgres -c 'create database banco_pdf_v9;'
psql -h 127.0.0.1 -p 55322 -U postgres -d banco_pdf_v9 -v ON_ERROR_STOP=1 -f 00-siembra.sql
bash oraculo.sh
```

El puerto es el del stack local `crm-avance-corp-local`. Cada caso corre sobre una copia
limpia (`create database … template banco_pdf_v9`), así que un caso nunca contamina al
siguiente.

## Qué mide (45 aserciones)

1. **Camino feliz** — la migración termina en `CONTRATO_PDF_V9_MIGRATION_OK`; las reservas sin
   bytes pasan a v9; la que tiene bytes se queda en v8; los sellados no se tocan; el ledger de
   `contrato_pdfs` queda idéntico; propietario, ACL, `prosecdef`, `search_path`, volatilidad y
   **OID** de las dos funciones sobreviven; el trigger vuelve a `tgenabled='O'` y sigue
   bloqueando el DELETE; los dos CHECK están y rechazan una versión inventada.
2. **Reserva v8 en vuelo** (lease vivo) — el preflight aborta y no cambia nada.
3. **Mutante del P0** — se fuerza el fallo del UPDATE: el `begin`/`commit` revierte TODO
   (trigger habilitado, CHECK viejos, funciones en v8, default en v8). Sin la transacción
   este mutante sobrevive: es la prueba de que la defensa existe.
4. **Mutante del conjunto** — una tercera función de `private` con el literal: aborta.
5. **Mutante de la guarda** — una función de `public` con el literal: aborta y la nombra.
6. **Mutante del contador** — dos ocurrencias del literal en una función esperada: aborta.
7. **Re-aplicación** — la segunda pasada aborta en seco y no deja el trigger apagado.
8. **Lease vencido** — el preflight las cuenta aparte y avisa de que esperar NO las arregla:
   una reserva `procesando` con lease vencido no se mueve hasta que alguien la reclame.
9. **Concurrencia** — una sesión rival abre transacción, mete un job v8 `procesando` y no
   cierra: la migración NO se cuela entre el conteo y el candado (falla por `lock_timeout`
   o por el preflight), el trigger sigue habilitado y el job rival queda intacto.
10. **Reversa completa** (`../rollback-pdf-v9.sql`) — default de vuelta a v8, funciones de
   vuelta a v8, reservas sin bytes de vuelta a v8, ledger de sellados idéntico, y los CHECK
   **siguen admitiendo la v9** para que un PDF sellado v9 se pueda seguir leyendo.

## Que un contrato SIN co-titular no cambió ni una palabra

Actualizar el golden del renderer prueba que los BYTES cambiaron (la versión va en
`info.creator`); no prueba que el TEXTO sea el mismo (hallazgo de Codex en la v8). El
comparador vive en `../banco-pdf-v8/comparar-texto.py` (no se duplica: es agnóstico de
versión): extrae el texto de los dos PDFs, descuenta la paginación y compara carácter a
carácter.

```bash
cd ../../functions/crm-contrato-pdf-v2
git stash   # o un worktree en la v8: el render de referencia debe salir de la plantilla v8
deno run -A _render-muestra.ts /tmp/muestra-v8-sin.pdf 2026-08-17T20:00:00.000Z
git stash pop
deno run -A _render-muestra.ts /tmp/muestra-v9-sin.pdf 2026-08-17T20:00:00.000Z
python3 ../../scripts/banco-pdf-v8/comparar-texto.py /tmp/muestra-v8-sin.pdf /tmp/muestra-v9-sin.pdf
pdftoppm -r 100 -png /tmp/muestra-v8-sin.pdf /tmp/v8 && pdftoppm -r 100 -png /tmp/muestra-v9-sin.pdf /tmp/v9
```

Resultado del 14/09/2026: **22 233 caracteres, mismo hash `80c69029404fdf9e`** en ambos, y las
**8 hojas idénticas píxel a píxel** a 100 dpi (mismo sha256 de cada PNG). Con la plantilla v9 y la
constante todavía en v8, el render reproducía además el golden v8 exacto (`e0a32053…`, 218 672
bytes): el envoltorio del bloque de firmas no mueve nada cuando no hay co-titulares. Con 1
co-titular el contrato sigue en 8 hojas; con 5 (tope del CRM) pasa a 9.

## Límite declarado

Las FORMAS (columnas, constraints, trigger) se leyeron de producción en solo lectura el
08/09/2026 y se reproducen literalmente. Los CUERPOS de las dos funciones son **suplentes**
con la misma envoltura que los vivos (plpgsql, SECURITY DEFINER, `search_path=""`, dueño
`postgres`, ACL `{postgres=X/postgres}`, una sola aparición del literal). Los cuerpos reales no
se copian: la migración los toma en vivo. Producción confirmó que ninguno contiene `$$` ni
`$function$`, así que el redondeo por `pg_get_functiondef` no puede romper el entrecomillado.

Una aserción de la primera versión del oráculo daba verde sin medir nada (error SQL silencioso
por `text || "char"`): se corrigió con un cast y se añadió una aserción que exige que la huella
de atributos no venga vacía.

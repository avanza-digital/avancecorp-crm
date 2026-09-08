# Banco del ensayo · plantilla v8 del PDF de contrato

Ensayo de `20260908173000_crm_contrato_pdf_plantilla_v8_letra_legible.sql` sobre una base
PostgreSQL 17.6 local y aislada, sin tocar producción ni el banco compartido de Supabase.

## Cómo se corre

```bash
psql -h 127.0.0.1 -p 55322 -U postgres -d postgres -c 'create database banco_pdf_v8;'
psql -h 127.0.0.1 -p 55322 -U postgres -d banco_pdf_v8 -v ON_ERROR_STOP=1 -f 00-siembra.sql
bash oraculo.sh
```

El puerto es el del stack local `crm-avance-corp-local`. Cada caso corre sobre una copia
limpia (`create database … template banco_pdf_v8`), así que un caso nunca contamina al
siguiente.

## Qué mide (45 aserciones)

1. **Camino feliz** — la migración termina en `CONTRATO_PDF_V8_MIGRATION_OK`; las reservas sin
   bytes pasan a v8; la que tiene bytes se queda en v7; los sellados no se tocan; el ledger de
   `contrato_pdfs` queda idéntico; propietario, ACL, `prosecdef`, `search_path`, volatilidad y
   **OID** de las dos funciones sobreviven; el trigger vuelve a `tgenabled='O'` y sigue
   bloqueando el DELETE; los dos CHECK están y rechazan una versión inventada.
2. **Reserva v7 en vuelo** (lease vivo) — el preflight aborta y no cambia nada.
3. **Mutante del P0** — se fuerza el fallo del UPDATE: el `begin`/`commit` revierte TODO
   (trigger habilitado, CHECK viejos, funciones en v7, default en v7). Sin la transacción
   este mutante sobrevive: es la prueba de que la defensa existe.
4. **Mutante del conjunto** — una tercera función de `private` con el literal: aborta.
5. **Mutante de la guarda** — una función de `public` con el literal: aborta y la nombra.
6. **Mutante del contador** — dos ocurrencias del literal en una función esperada: aborta.
7. **Re-aplicación** — la segunda pasada aborta en seco y no deja el trigger apagado.
8. **Lease vencido** — el preflight las cuenta aparte y avisa de que esperar NO las arregla:
   una reserva `procesando` con lease vencido no se mueve hasta que alguien la reclame.
9. **Concurrencia** — una sesión rival abre transacción, mete un job v7 `procesando` y no
   cierra: la migración NO se cuela entre el conteo y el candado (falla por `lock_timeout`
   o por el preflight), el trigger sigue habilitado y el job rival queda intacto.
10. **Reversa completa** (`../rollback-pdf-v8.sql`) — default de vuelta a v7, funciones de
   vuelta a v7, reservas sin bytes de vuelta a v7, ledger de sellados idéntico, y los CHECK
   **siguen admitiendo la v8** para que un PDF sellado v8 se pueda seguir leyendo.

## `comparar-texto.py` — que no cambió ni una palabra

Actualizar el golden del renderer prueba que los BYTES cambiaron; no prueba que el TEXTO sea
el mismo (hallazgo de Codex). Este script extrae el texto de los dos PDFs, descuenta lo que es
paginación (número de contrato de la cabecera, pie «n / m» y la cabecera de la tabla, que
pdfmake repite cada vez que la tabla parte de hoja) y compara carácter a carácter.

```bash
python3 comparar-texto.py contrato-8.6pt.pdf contrato-9.6pt.pdf
```

Resultado del 08/09/2026: **22 233 caracteres, mismo hash `80c69029404fdf9e`** en ambos.
De paso: a 8.6 pt la tabla de liquidación PARTÍA de hoja (su cabecera salía 2 veces) y a
9.6 pt cabe entera (1 vez).

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

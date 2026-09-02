# Montar un banco de pruebas a paridad con producción

Un **banco** es una rama de Supabase con la MISMA estructura que producción y datos propios.
Sirve para lo que no se puede hacer arriba: la suite `test:rls` entera, los casos de la
cadena de upgrade, re-medir a 10 000 leads. **Nada de esto toca producción.**

El 01/09/2026 se montó uno completo: **196/196 versiones, paridad 9 de 9 categorías al
byte**. Estos son los guiones que lo hicieron y lo que costó aprenderlos.

## Receta

```bash
export S=/ruta/al/scratchpad          # donde viven banco-sql/ y los .txt de estado
# 1. crear la rama en Supabase y guardar su cadena de conexión
#    ⚠️ POOLER EN MODO SESIÓN: puerto 5432, NO 6543. `db.<ref>.supabase.co` no resuelve.
echo 'postgresql://postgres.<ref>:<pass>@aws-0-us-east-2.pooler.supabase.com:5432/postgres' > $S/banco-pooler.txt

# 2. volcar de producción el SQL de las versiones que la rama no replayó sola
python3 volcar.py                      # -> $S/banco-sql/<version>_<nombre>.sql

# 3. sembrar lo que las migraciones necesitan para EJECUTARSE (no son parches)
psql "$(cat $S/banco-pooler.txt)" -f siembra-banco.sql
psql "$(cat $S/banco-pooler.txt)" -f siembra-gerencia.sql
psql "$(cat $S/banco-pooler.txt)" -f siembra-actor-oraculos.sql

# 4. replayar; si algo muere, se lee el error y se decide (ver más abajo)
python3 replay.py

# 5. dejar el REGISTRO idéntico al de producción (texto y fronteras)
python3 reregistrar.py

# 6. la prueba de aceptación: la misma consulta en los dos lados
psql "$(cat $S/banco-pooler.txt)" -At -F'|' -f paridad-banco.sql
npx supabase db query --linked --file paridad-banco.sql
```

## Las cinco trampas, todas pagadas ya

**1. Un fichero sin transacción que muere en su postflight deja el banco con el trabajo
hecho y sin acta.** El siguiente intento falla en el *preflight* —diciendo la verdad, porque
la migración ya se comió el estado que anclaba— y parece corrupción. Antes de neutralizar un
ancla: **comprobar si la migración ya se aplicó** (correr su propio postflight y comparar sus
objetos con producción). `replay.py` ya no lo permite: envuelve en transacción todo fichero
que no traiga la suya.

**2. El fichero va en UN mensaje (`psql -c`), no sentencia a sentencia (`psql -f`).**
Producción aplica con `supabase db query --file`, que manda todo como una sola consulta.
`statement_timestamp()` es «la hora del último **mensaje** del cliente», así que con un solo
mensaje no avanza en toda la migración. Con `-f` sí avanza, y cualquier oráculo que fotografíe
un payload y lo vuelva a pedir ve cambiar su `generado_en` y aborta.

**3. `statements` es un ARRAY, no un texto.** Guardar todo en un elemento da el mismo texto
con fronteras distintas. La Ola R comprueba la identidad **por elemento** justamente porque
el md5 del texto unido no ve fronteras desplazadas. `reregistrar.py` copia el array real.

**4. La sesión va en `America/Lima`.** Banco y producción corren en `TimeZone=UTC`, pero los
gates comparan contra el «hoy» de Lima. Entre las 19:00 y las 24:00 de Lima, `current_date`
(UTC) va un día por delante y cualquier oráculo que lo pase como `p_hasta` recibe «Periodo
invalido» — **también en producción**. ⚠️ `PGOPTIONS` no sirve: el pooler se come las
opciones de arranque; hay que mandar un `SET` explícito.

**5. Las aserciones con hambre de datos.** Muchas migraciones llevan censos de filas de
producción («13 contratos sin analista», «568 condiciones», «1 coop anulada»). En un banco
vacío no se cumplen. Se neutralizan **una a una y por escrito**, tolerando **solo el caso
exactamente vacío**: con datos parciales la aserción vuelve a abortar.

## Las reglas

- Todo lo que se aparte del SQL de producción va a `parches/DIVERGENCIAS.md` con **tres
  columnas**: qué se neutralizó, por qué, y qué sigue vivo. Una divergencia sin fila ahí es
  un banco que miente.
- **Sembrar antes que parchear.** Si a la prueba le falta un actor o un dato, se le da el
  dato: así la aserción se ejecuta de verdad. Solo se neutraliza lo que ningún dato razonable
  puede satisfacer.
- **No se desmonta una guarda para poder seguir.** Dos de los cinco hallazgos de arriba los
  cazó una guarda ajena escrita para otra cosa; neutralizarlas habría dejado un banco
  sutilmente falso y creíble.

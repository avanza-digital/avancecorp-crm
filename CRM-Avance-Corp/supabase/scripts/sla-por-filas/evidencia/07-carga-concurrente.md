# Paso 3a · prueba de carga concurrente: ANTES (A) frente a M3 (B)

17/10/2026, de 12:54 a 13:16 (hora de Lima, tomada con `date`). Banco Docker `foto-sla-f2-db`: Postgres 17.6, esquema de
producción con la opt1, 3.869 leads sintéticos, contenedor con el límite de producción (4 GiB sin swap, 2 CPU), `work_mem` 7 MB y
`statement_timeout` 8 s para `authenticated`.

Para cambiar de variante, el arnés `fase2/arnes/arnes.py --modo serie` aplica los archivos FINALES con `psql -f`, como el dueño:
- A ← `reversa-m3` → `reversa-m2` → `reversa-m1`;
- B ← M1 → M2 → M3;
- `verificar.sql` corre detrás de cada guion y otra vez tras el reinicio;
- cada réplica arranca con el contenedor reiniciado y mide con un pool de 40 conexiones;
- al terminar, la serie queda en M3.

## Veredicto del arnés

| Escenario | Plan | Veredicto | Por qué |
|---|---|---|---|
| prueba corta «producción» | AB | PASA (con reservas: 1 réplica) | — |
| «producción» (las 35 personas, una pestaña, las llamadas de su rol) | ABABAB | **NO PASA** | Solo el p95 de ejecución de `estado`: 704 → 802 ms (+13,9 %; tolerancia +10 %) |
| «peor» (gerencia y supervisores, 3 pestañas, las 3 llamadas a la vez) | ABABAB | **NO PASA (con reservas)** | Solo el p95 de ejecución de `estado`: 703 → 915 ms (+30,2 %). Avisos y cola, censurados en el corte de 8 s en las dos |

Los otros dos criterios PASAN en los dos escenarios.
- **Memoria:**
  - «producción»: pico del contenedor de B 1,118 GiB (28 % del límite) frente a A 1,557 GiB;
  - «peor»: B 1,783 GiB frente a A 2,242 GiB;
  - sin swap, sin OOM y sin eventos `max`. La presión de memoria baja de 10 ms a 0.
- **Temporales** (corregido tras Codex: no bajan en los dos escenarios):
  - «producción», con el mismo trabajo en A y B: por ronda, −55 % (221,2 → 98,8 MiB; total 1.990 → 889 MiB);
  - «peor»: por ronda **SUBEN +34,5 %** (445,2 → 598,9 MiB; total 5.342 → 7.186 MiB), porque B completa 692 llamadas y A solo
    483 (A corta 273 por los 8 s, B 64), y las que A corta son las grandes;
  - en «peor», por llamada completada, −6 % (es el criterio del arnés, que no compara trabajo igual);
  - cola por llamada completada en «peor»: +268 %, con el mismo sesgo de composición;
  - ponderados con las llamadas reales, cada llamada sola (trabajo equivalente): −56 %.

## Lo que mejora (B frente a A)

- **Pico de memoria del contenedor,** las 3 réplicas de B por debajo de las 3 de A:
  - «producción»: −433 MiB de mediana (−28 %);
  - «peor»: −378 MiB de mediana (2.199 → 1.821 MiB, −17 %).
- **Pico anon menos reposo:** −68 % («producción»).
- **Avisos y cola, p95 de ejecución:**
  - avisos −28 % (3.077 → 2.204 ms);
  - cola −24 % (3.051 → 2.307 ms).
- **«Peor»:** las llamadas cortadas a los 8 s bajan de 273 a 64, y las completadas suben de 483 a 692.
- **Temporales por llamada:** avisos 3,87 → 1,89 MiB y cola 3,39 → 1,36 MiB.

## «estado»: qué pasa

`crm.estado_sla_leads_v2_fn('{}')` es la llamada que la app hace al entrar. Pasa por el envoltorio `sla_operacion_autorizada`, que M1
reescribe sobre `_filas`.

1. **Sola, sin carga, tarda lo mismo en las dos versiones** (`estado-aislado.sql`, en ROLLBACK, 400 llamadas de cada una
   alternadas, por rol, con `'{}'` y con un lead propio):

   | Rol · argumento | p50 vieja → nueva | p95 vieja → nueva |
   |---|---|---|
   | vendedor · `'{}'` | 1,23 → 1,17 ms | 1,95 → 1,70 ms |
   | vendedor · 1 lead | 3,24 → 3,27 ms | 4,91 → 5,20 ms |
   | supervisor · `'{}'` | 1,21 → 1,15 ms | 1,51 → 1,43 ms |
   | supervisor · 1 lead | 3,17 → 3,14 ms | 3,98 → 4,13 ms |
   | gerencia · `'{}'` | 1,12 → 1,12 ms | 1,36 → 1,31 ms |
   | gerencia · 1 lead | 2,79 → 2,81 ms | 3,48 → 3,34 ms |

2. **En la tormenta tarda de 150 a 900 ms; su trabajo propio es de 1 a 5 ms.** El resto es espera: CPU (2 núcleos, saturados en
   A y en B, estrangulados) y el pool. Con el mismo solape, la ejecución de `estado` es más lenta en B: «producción», solape
   20–30, p50 224 → 341 ms (`analizar-estado-salida.md`).
   - **Hipótesis, no demostrada:** en A, las pesadas pasan parte de su tiempo escribiendo y leyendo temporales (en espera de
     E/S); en B escriben 55 % menos y están más tiempo en CPU. Así, `estado` recibe una parte menor de la CPU por cada pesada que
     se le solapa.

3. **De punta a punta,** desde que la pestaña pide hasta que llega la respuesta, incluida la espera de conexión del pool:

   | Escenario · consulta | p50 A → B | p95 A → B |
   |---|---|---|
   | «producción» · avisos | 1.620 → 1.448 ms | 3.649 → 2.813 ms (−22,9 %) |
   | «producción» · cola | 1.616 → 1.433 ms | 3.652 → 2.713 ms (−25,7 %) |
   | «producción» · **estado** | 614 → 657 ms | 1.448 → 1.496 ms (**+3,3 %**) |
   | «peor» · avisos | 7.305 → 4.880 ms | 8.628 → 8.076 ms (−6,4 %) |
   | «peor» · cola | 8.104 → 6.933 ms | 8.803 → 8.320 ms (−5,5 %) |
   | «peor» · **estado** | 503 → 428 ms | 1.060 → 1.164 ms (**+9,8 %**) |

   - Cada tormenta (una ronda de recargas) termina antes: «producción» 3,81 → 2,82 s y «peor» 8,85 → 8,34 s (mediana por ronda).

**Lectura (del PRIMARY, para revisar):**
- La regla del arnés se cumple con la latencia de ejecución y falla por `estado`. No se cambia la regla después de medir: el
  veredicto se queda en NO PASA.
- Lo que ve la persona es el tiempo de punta a punta. Ahí `estado` queda dentro del +10 % en los dos escenarios, y avisos y cola
  mejoran mucho.
- Sola, `estado` tarda lo mismo con M1–M3 (punto 1). Eso no prueba que haga el mismo trabajo bajo contención: M1 le añade
  capas (`_filas`, que llama una vez al ámbito, y la materialización). Codex lo refutó. Lo zanja el experimento 2×2 (sonda
  vieja/nueva × carga vieja/nueva), que va abajo.
- Llevar `estado` y los otros consumidores del envoltorio a `_filas` es la Fase 4, que no está en este paso.

## Archivos

- **Comparaciones:**
  - `fase2/arnes/resultados-serie/comparacion-produccion-20261017-1305.md/.json`
  - `fase2/arnes/resultados-serie/comparacion-peor-20261017-1316.md/.json`
  - `fase2/arnes/resultados-serie/prueba-corta/`
- **Réplicas:** `fase2/arnes/resultados-serie/[AB]-20261017-*`, con `peticiones.csv`, memoria, monitor y docker.
- **Análisis de este informe:**
  - `carga-3a/estado-aislado.sql` y su salida, en este informe;
  - `carga-3a/analizar-estado.py` → `carga-3a/analizar-estado-salida.md`.
- **Estado final del banco:** serie M3, familia `64 · f9ea903841b9186ac985e103e050e6d5` (`serie-dejar-20261017-131647.log`).

## Añadido 17/10, 14:27–14:47 · la misma carga con la sonda `estado` VIEJA (`bench.v0_estado_sla_leads_v2_fn`, sobre el envoltorio de producción `a5fd870b`)

Una corrida con `ARNES_SQL_ESTADO="select bench.v0_estado_sla_leads_v2_fn('{}'::uuid[])"`, ABABAB, «produccion» y «peor»; salida en
`fase2/arnes/resultados-serie-estado-viejo/`. En las dos variantes la sonda NO pasa por el código de M1: es la celda «sonda
vieja × carga nueva» en B.

- **Veredicto del arnés:**
  - «produccion»: PASA (estado p95 395,9 → 413,7 ms, +4,5 %);
  - «peor»: NO CONCLUYENTE (avisos y cola censurados en 8 s; estado 1.198,6 → 1.048,8 ms, −12,5 %).
- **Por rol, «produccion»:** el mismo patrón que con la sonda nueva. Vendedor +12,0 % (antes +12,4 %) y supervisor +38,0 % (antes
  +33,5 %). Es decir, la sonda que NO tiene el código de M1 sube igual.
- **Dispersión entre réplicas de la MISMA variante (p95 de ejecución de `estado`, ms):**

  | Corrida | A (las 3 réplicas) | B (las 3 réplicas) |
  |---|---|---|
  | sonda nueva · produccion | 652 · 705 · 692 | 477 · 938 · 806 |
  | sonda nueva · peor | 798 · 703 · 568 | 1.094 · 800 · 283 |
  | sonda vieja · produccion | 210 · 443 · 448 | 232 · 484 · 355 |
  | sonda vieja · peor | 733 · 1.303 · 1.290 | 1.001 · 1.155 · 1.005 |

  - La variante A es idéntica en las dos corridas, y su p95 agregado pasa de 704 a 396 ms («produccion») y de 703 a 1.199 ms
    («peor»).
  - Dentro de una misma variante, las réplicas varían hasta 4 veces (283–1.094).
  - **Lectura:** con 3 réplicas, la tolerancia de +10 % sobre el p95 de `estado` es más estrecha que el ruido entre corridas.
- **Ojo:**
  - desde las ~14:30 otros dos agentes montan contenedores Docker en la misma máquina (un banco del kit y un stack del gate);
  - aun así, la CPU de la VM (todos los contenedores) no muestra más carga: 122–249 % de máximo, frente a 218–323 % en la corrida
    de las 12:57. No se puede descartar ruido de E/S;
  - las dos corridas no son simultáneas, así que comparar entre ellas mezcla el ruido del momento.
- **No cambia el veredicto de la corrida normal (NO PASA).** El 2×2 completo, con la celda que falta (sonda nueva × carga vieja) y
  más réplicas, lo hace el agente del arnés (`fase2/arnes/resultados-serie/INFORME-2x2-y-gestion.md`).

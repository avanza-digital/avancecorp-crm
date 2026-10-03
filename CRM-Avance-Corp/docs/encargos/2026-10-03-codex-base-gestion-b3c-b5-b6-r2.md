ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está transcrito aquí.
Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia, NEXT ACTIONS, CONFIDENCE.

# Encargo: Base para gestión · paquete B3c + B5 + B6 — segunda y ÚLTIMA ronda (LEVEL 3)

Tu ronda 1 (BLOCK, dos P2) se aplicó así. Revisa SOLO si quedan resueltos y si el arreglo abre algo nuevo. Sé breve.

## P2-1 «la suite puede imprimir FAIL y terminar sin excepción» → aplicado en las CUATRO suites del módulo
(b2-rls.sql, b3-puertas.sql, b4-enfriamiento.sql, b6-seguimiento.sql; el patrón venía de las anteriores):
```sql
update r set ok = coalesce(obtenido = esperado, false);  -- un NULL no es PASS
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, obtenido) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B6: hay casos FAIL'; end if; end $$;
```
(b2-rls.sql conserva su `case` de comparación propio; sus dos guardas pasaron a `ok is not true`.)
Mutante pedido: el último rescate leyendo `->>'no_existe'` en vez de `->>'rescatados'` → «FAIL … obtenido (vacío)»,
TOTAL 29 PASS · 1 FAIL y `ERROR: B6: hay casos FAIL` (psql sale con error). Sin mutante: 30/30.

## P2-2 «el detail del candado incluye el lead_id» → retirado; el detail solo lleva estado y fecha
Cuerpo nuevo de private.trg_leads_guard_seguimiento_activo() (DEFINER, search_path ''):
```sql

declare
  v_hasta date;
begin
  -- B6 (Miguel, 03/10/2026): a un lead descartado que su analista está trabajando nadie le cambia el responsable, venga por
  -- el Centro de rescate, la ficha o «tomar lead libre». Una baja (dueño inactivo) lo libera: la ayudante devuelve NULL.
  v_hasta := private.base_gestion_en_gestion_hasta(old.id);
  if v_hasta is not null then
    -- Sin nombres ni identificadores (Codex 03/10): quien lo intenta por «tomar lead libre» puede no ver al lead ni a su
    -- analista; el detail solo dice el estado y la fecha.
    raise exception 'Este lead lo está trabajando su analista hasta el %: no se le puede cambiar el responsable',
      pg_catalog.to_char(v_hasta, 'DD/MM/YYYY')
      using errcode = 'P0409',
            detail = pg_catalog.jsonb_build_object('estado', 'en_gestion', 'hasta', v_hasta)::text;
  end if;
  return new;
end;
```
Pruebas nuevas en b6-seguimiento.sql:
- El rescate rechazado: `detail->>'estado' = 'en_gestion'`, `detail->>'hasta' = hoy+7` y `not (detail ? 'lead_id')` → PASS.
- B (otro analista, que NO ve LA por RLS) llama a `crm.tomar_lead_libre(teléfono, dni)` de LA y captura sqlstate, mensaje y
  `pg_exception_detail` dentro de la misma sesión de B: P0409, sin clave lead_id, y el texto completo (mensaje + detail) no
  contiene el UUID de LA ni «BANCO» (el nombre de los analistas sintéticos) → PASS.
- test-rls.mjs (gate por la API, PostgREST): el bloque B6 exige `!('lead_id' in detalle)` y `detalle.hasta === hoy+7`.

## Pendiente que señalaste (equivalencia del ámbito del resumen) → probado
Nueva suite b3c-resumen-equivalente.sql: crea en la transacción una copia EXACTA del cuerpo vivo del resumen (antes de B3c)
como función temporal, siembra intentos de hoy (A con rellamada, C, y B con «agendó cita» → reactivación del mes) y compara
`nuevo EXCEPT ALL vivo` y `vivo EXCEPT ALL nuevo` por rol, con ROLLBACK:
- S1 (supervisor de A y B): 0/0 diferencias de 2 filas, con datos (en base > 0, intentos de hoy > 0), reactivaciones 1 → PASS
- S2 (supervisor de C): 0/0 de 1 fila, con datos, reactivaciones 0 → PASS
- G (gerencia): 0/0 de 3 filas, con datos, reactivaciones 1 → PASS

## Estado tras los arreglos (banco Docker con el esquema de producción)
B2 25/25 · B3 48/48 · B4 17/17 · B3c equivalencia 3/3 · B6 30/30. Mutantes: regla siempre NULL → FALLA; candado deshabilitado
→ FALLA; ayudante de intentos +1 → B3 y B4 FALLAN; NULL en un caso → FALLA. Cadena de reversas B6 → B5 → B3c → las seis
funciones con las huellas md5 de PRODUCCIÓN y sin restos; reaplicación en verde. Registradores regenerados (md5 = archivo;
segunda pasada no duplica). B3c y B5 no cambiaron respecto de la ronda 1; B6 solo cambió el detail y su comentario.

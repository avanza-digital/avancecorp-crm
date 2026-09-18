# Ensayo de «la cita atendida es la entrevista»

Verifica la migración `20260918213000_crm_entrevista_al_asistir.sql` **contra producción y sin
escribir nada**.

## Por qué así

El ensayo no prueba una copia de la función: pega la **migración real** (preflight, gates y
comentarios incluidos) dentro de una transacción que termina en `rollback`. Si alguien toca la
migración, el oráculo prueba lo tocado — no hay copia que se desactualice sola.

Y no usa un fixture inventado: levanta el escenario contra la **forma real** del esquema (los
CHECK, los triggers, la jerarquía de equipo y los actores vivos de producción). Un fixture cómodo
habría probado un mundo que no existe.

## Cómo se corre

```bash
# 1. El ensayo. Termina SIEMPRE en excepción: eso es el veredicto, no un fallo.
node supabase/scripts/entrevista-al-asistir/armar-ensayo.mjs > /tmp/ensayo.sql
npx supabase@2.114.0 db query --linked --file /tmp/ensayo.sql
#    → ENSAYO VERDE — 0 fallos

# 2. Los mutantes: rompen el arreglo a propósito y exigen que el oráculo lo grite.
bash supabase/scripts/entrevista-al-asistir/mutantes.sh
#    → MUTANTES: los 6 murieron.
```

Después del ensayo conviene comprobar que producción quedó intacta:

```sql
select to_regprocedure('crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)'),
       (select count(*) from crm.leads where nombre_completo like 'ENSAYO%');
-- null, 0
```

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Se niega si la migración trae un `commit` suelto. |
| `pruebas.sql` | El oráculo, 11 secciones: escenario feliz, idempotencia del recibo, segunda entrevista, 8 rechazos (5 de forma + 3 de autoridad), los permitidos (supervisor del equipo y gerencia), «no interesado» con y sin cifra, replay con otro capital, el núcleo sobre un lead descartado, los permisos de las tres funciones y el gate. |
| `mutantes.sh` | Seis mutantes que deben poner el ensayo en ROJO. Si uno sobrevive, esa defensa no estaba probada. |

## Trampas encontradas al escribirlo

- **Un rechazo que no rechaza se escapa hacia adelante.** El primer mutante cerró la cita que las
  pruebas siguientes daban por abierta, y el fallo salió como error crudo tres pasos después, sin
  informe. Por eso cada rechazo comprueba ahora que la cita sigue `pendiente`, y el último caso va
  envuelto: un imprevisto es un FALLO, no un abort.
- **Un caso condicional puede dar verde sin haber probado nada.** La prueba de ámbito estaba
  envuelta en «si existe un vendedor de otro equipo…» y su rama de aviso no sumaba fallos: sin ese
  actor, el único caso de denegación se saltaba en silencio. Los actores son ahora obligatorios y su
  ausencia aborta el ensayo.
- **Sembrar exige el JWT del dueño.** `trg_gestion_lead_serializada` rechaza una tarea cuyo
  `creado_por` no sea el usuario autenticado, y ningún lead puede NACER terminal
  (`trg_leads_disponibilidad_atomica`): se crea operativo y se descarta después.
- **Los gates de producción no están todos verdes.** Cuatro llevan en rojo desde antes por trabajos
  ajenos; el postflight de la migración solo llama a los cuatro del mundo SLA. Ver el ledger.

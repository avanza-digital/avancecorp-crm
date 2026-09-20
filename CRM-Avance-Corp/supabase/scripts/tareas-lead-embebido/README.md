# Lead embebido completo en las tareas por cursor (Fase 4b «sin topes»)

Migración `20260920045202_crm_tareas_pendientes_lead_embebido.sql`: cambio ADITIVO sobre la
Fase 2 (`20260919235100`). El núcleo `private.tareas_pendientes_core` pasa a embeber, por
tarea, ocho columnas más del lead (teléfono, monto, moneda, vendedor, supervisor, correo,
no_contactar, teléfono alternativo) bajo `leads_select`, para que la Agenda no necesite la
foto inicial de leads. Puerta, índice, gate y mutantes de la Fase 2 no cambian.

- `ensayar-local.sh` — copia local desde `conversion_inversion_base_20260919`, instala la
  Fase 2 tal cual y después esta migración; gate + 17 mutantes + matriz de 11 roles +
  valores embebidos = `crm.leads` bajo la misma sesión + errores + EXPLAIN.
- `generar-registrador.mjs` — genera `supabase/scripts/registrar-20260920045202.sql` con los
  md5 de puerta y núcleo MEDIDOS EN PRODUCCIÓN (`verificacion.json`), tras instalar.
- `verificacion.json` — acta del ensayo, de la instalación y de las revisiones.

Orden en producción: `!` con la migración → medir md5 → `node generar-registrador.mjs` →
`!` con el registrador → front (`/release-crm`). Como las claves nuevas van en la RESPUESTA y
el front las trata como opcionales, el orden entre servidor y front es libre.

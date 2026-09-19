# Grant por columna: `alta_manual` y `creado_por` en `crm.leads`

Estado: **instalado y registrado en producción el 19/09/2026** (acta en
`../../migrations/MIGRACIONES.md`, entrada `20260919211105`).

Origen: P3 del auditor RLS sobre `20260919170500` (procedencia del lead). La RPC
`crm.cartera_filtrada_fn` es SECURITY INVOKER y lee esas dos columnas para todo
analista; hoy son legibles solo por el ACL de TABLA (`authenticated=rw`,
`service_role=arwd`) y no tienen ACL propia. La convención de la casa (desde
`20260718000001`) es el grant explícito por columna. Solo SELECT, como
`tenencia_desde`: las escritoras (`crear_lead_si_disponible`, `importar_lead_fn`)
son SECURITY DEFINER y el trigger de inmutabilidad sella las dos columnas.

## Lo que vale y lo que no (hecho medido, PG 17)

Un `revoke select on crm.leads` de TABLA **arrastra** las ACL por columna del
mismo privilegio: `tenencia_desde` pierde su `authenticated=r`. Así que el grant
por columna **no** protege contra un revoke de tabla, al contrario de lo que
prometen notas de migraciones anteriores. Su valor real: convención, registro y
que, si algún día se pasa a privilegios por columna, estas dos estén en la lista
a reponer y PostgREST no las pierda por un olvido. El ensayo lo asevera para que
nadie vuelva a prometer lo contrario.

## Ensayo local

```bash
node supabase/scripts/leads-grant-procedencia/ensayar.mjs
```

Sobre la copia `cartera_procedencia_20260919` (ACL a paridad con producción):
hecho de la cascada (tras `revoke select` de tabla, `tenencia_desde` pierde su
`r` y las dos columnas tampoco se leen) → instalación deshecha → guarda del
preflight (ACL previa) → instalación real (ACL exacta, anon sin lectura, tabla y
otras columnas intactas) → cierre simulado a privilegios por columna (revoke de
tabla + re-grant de la lista documentada: las dos se leen, `nombre_completo` no)
→ oráculo como analista (select directo + RPC invoker) → guardas de la reversa
(ACL de tabla cerrada → se niega; sin nada que revertir → se niega), reversa y
reinstalación. Escribe `verificacion.json` y genera
`../registrar-20260919211105.sql`.

## Publicación y reversa

1. `db query --linked --file supabase/migrations/20260919211105_crm_leads_grant_columna_procedencia.sql`
2. `db query --linked --file supabase/scripts/registrar-20260919211105.sql`
3. Reversa: `reversa.sql` (se niega si el ACL de tabla ya no cubriera las columnas).
   No hay front que publicar: el cambio es solo de permisos y hoy es redundante.

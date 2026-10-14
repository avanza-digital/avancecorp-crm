# Resolución del PRIMARY

La revisión independiente devolvió `CHANGES_REQUESTED`. Codex evaluó los puntos
con el código y ejecutó las verificaciones siguientes; no se volvió a consultar
para obtener otro dictamen.

- P1, integración: el diff de `app/src/lib/supabase.ts` añade únicamente el import
  y `global.fetch`. `createClient` y `crearFetchCrm` reciben exactamente
  `CONFIG.SUPABASE_URL` y `CONFIG.SUPABASE_ANON_KEY`; no existía un fetch previo.
  Las llamadas usan `.schema('crm')`, como antes. Se añadió
  `supabase-transporte.test.ts`: importa el cliente compartido real, con URL/key
  normalizadas, usa la RPC real del SDK y comprueba error local y cero tráfico.
  PASS. El hallazgo era una ausencia en la evidencia adjunta, no una integración
  rota observada; ahora tiene una prueba directa.
- P2, ledger: ambas entradas están en `MIGRACIONES.md` como PREPARADA, sin
  aplicación productiva. Registran el bloqueo remoto y enlazan el kit que exige
  comprobar la versión real tras el merge. El diff se entrega en el PR.
- P3, F7: `IS DISTINCT FROM` para estado/ola, `LEFT JOIN` que detecta funciones
  ausentes y comparación completa de la fila salvo huella/nota con `to_jsonb`.
- P3, SLA: el postflight exige la huella nueva exacta y compara todo `pg_proc`
  excepto `prosrc`, incluidos coste, filas, soporte y leakproof. Reversa y
  reaplicación verificadas con estos controles: PASS.
- Pruebas añadidas: F7 con otra pieza derivada, vigilante verde y otra causa de
  error; todos rechazan. Agregados SLA: nueve casos, con ausencia de tareas,
  empates, datos inválidos, mezclas y NULL/infinity en el proyector; PASS.
  Transporte: HEAD, clave publishable y cabeceras de Request sobrescritas por
  init; PASS. Total de sesión: 13 tests.

Los guardianes específicos pasan; el gate HTTP remoto y el despliegue siguen
pendientes por el replay histórico fallido. No se afirma que la revisión aprobó
producción ni que las alertas productivas hayan desaparecido.

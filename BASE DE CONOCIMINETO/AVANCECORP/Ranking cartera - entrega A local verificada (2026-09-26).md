# Ranking cartera — entrega A local verificada

Relacionado: [[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]]
y [[Auditoria Claude - plan inversion por empresa (2026-09-26)]].

## Autorización y estado

Miguel autorizó implementar/probar localmente A, manteniendo producción intacta
hasta aprobar el SQL exacto. No se hizo commit, push, merge, deploy ni escritura
productiva. La restricción de nueva inversión por empresa (entrega B) no se inició.

Clon aislado: `/private/tmp/ranking-cartera.AfQUSa`, base publicada
`526d6d90c621e4072251818d1325b7bd0c01b2ca`. No es worktree ni rama de release.
El código del árbol principal, con cambios ajenos, quedó intacto.

## Regla y efecto

Solo el lector privado de capital/origen obtiene un fallback Cartera para
contratos `nuevo` sin leads directos ni fallback temporal, cuando el ledger
acredita continuidad y coincide contrato nuevo/cliente/moneda/fecha/tipo.
Conserva categoría financiera, montos, vendedor, conversión, cooperativas,
permisos y snapshots ya sellados. Leads ambiguos o directos sin origen mantienen
precedencia: no se ocultan como Cartera. No depende del espejo crm.inversiones.

Proyección productiva READ ONLY de septiembre: 143 filas antes/después,
12 diferencias solo de canal, cero duplicados; PEN 2.092.254 (8) y USD 54.971 (4).
Betzabeth: Cartera PEN 150.000 (3 contratos); Oficina PEN 72.450 + USD 30.000;
Referido PEN 283.000. Es proyección, NO estado instalado.
Diagnóstico adicional: cero discordancias de cliente/moneda/fecha/tipo entre
los 12 candidatos; fecha del episodio deriva del campo comercial persistido.

## Pruebas y revisión

- PASS 25 aserciones SQL nuevas en Docker, regresión existente, mes cerrado
  con foto no vacía y RPC intacta, reversión exacta y tres mutantes detectados.
- PASS 66 tests existentes del frontend publicado; consumidor intacto,
  no equivale a E2E del candidato instalado.
- Claude como auditor SQL/RLS: PASS. P2 fecha comprobado; P3 monedas reforzado;
  tercer tipo no existe por CHECK y se comprobó rechazo; índice único verificado.
- PASS sintaxis Node, whitespace de los siete archivos del patch,
  `git apply --reverse --check` contra el clon aislado.
- Preflights seed/RLS: FAIL por faltar SUPABASE_URL en clon, no error funcional.
- HTTP/RLS remoto, advisors, E2E integral y publicación: NOT RUN.

Banco dedicado: `ranking_cartera_20260926` del contenedor
`supabase_db_crm-avance-corp-local`, copia sintética del banco previo.
Todas las pruebas revierten; el lector original queda restaurado al terminar.
Sin deshabilitar triggers. Runner no admite destinos remotos.

## Entregable durable

Fuera de /tmp, en `releases/ranking-cartera-20260926/` del repositorio:

- `entrega-a.patch`: siete archivos propios (migración, ledger, tests,
  reversión, verificación y revisión Claude). No incluye trabajo ajeno.
- `20260927003433_crm_ranking_cartera_legada.sql`: SQL exacto para aprobación.
- `revertir.sql`, `VERIFICACION.md`, revisión, solicitud y log de pruebas.

SHA256 SQL: `e2bc5cbea16b2efb4f4d9336a7f2cf0af1046f6e1595906951bed94388e30451`.
SHA256 patch: `84411b52ecb4b2c9b41b9566e3a1c694616da8c61446489700a434f1af0a5966`.
Guías Supabase/PostgreSQL aplicadas: EXISTS sin duplicar capital, permisos
mínimos intactos, índice existente, prueba local y reversión antes de instalar.

## Siguiente paso

Actualización: el ensayo remoto autorizado ya se ejecutó; ver
[[Ranking cartera - ensayo remoto verificado (2026-09-26)]].
La evidencia local anterior se conserva como historia. Aún no está publicado.

# Conversión: límite total de referidos y anulaciones

Estado: **IMPLEMENTADO Y VERIFICADO EN LOCAL; SIN ACTIVAR EN PRODUCCIÓN**.

Miguel precisó que el 15 % es un límite calculado sobre el **total de cierres
referidos válidos por analista y mes**. Sustituye el límite anterior basado en
cierres automáticos y elimina su redondeo hacia arriba. Con 100 llegadas,
10 cierres automáticos y 4 referidos válidos: límite referido 0,60,
numerador 10,60 y conversión 10,60 %.

Se conserva admisión cronológica: con ocho referidos el aporte mostrado por
cierre es 1; 0,20; 0; 0; 0; 0; 0; 0. El tope se calcula sobre el mes completo
antes de recortar un rango. No se presenta como un peso fijo por cierre.

**Decisión adicional expresa de Miguel:** si se anula uno de cuatro referidos
de un mes sellado, descontar **0,15**, porque el límite baja de 0,60 a 0,45.
Se aplica a cualquiera de los referidos, sin depender de su posición. Cuatro
anulaciones suman 0,60. La columna privada `ajuste_anulacion_en_sello` congela
el descuento marginal; es distinta del aporte individual mostrado. Cambiar
el porcentaje después del sello no cambia la deuda ya congelada.

Renovaciones siguen en cero. Agosto/septiembre mantienen pesos y fotos.
Divisor y demás reglas no cambian. Migración `20261012220959` preparada;
reversa probada antes de cualquier sello desde octubre. Rama Supabase,
RLS Auth/HTTP, advisors, PR/merge y publicación del frontend siguen pendientes.
El frontend exige invocación humana `$release-crm` según CLAUDE.md.

Evidencia: 36 + 7 SQL, 8 escenarios de recuperación, 9 denegaciones de permisos,
6.640 tests de frontend y 3 E2E Docker PASS. Revisión independiente final PASS.
El primer review detectó la divergencia de la deuda por posición; se corrigió
con la decisión de Miguel. Detalles en `supabase/scripts/conversion-limite-referidos/`.

[Diagrama editable para Gerencia](https://www.figma.com/board/tO6Lpx3ieJ6QuwUxfZcSvM?node-id=50-19).
La regla de anulación está incluida; el Figma marca referidos en implementación.

Relacionadas: [[Conversion - aclaracion del limite de referidos (2026-10-12)]],
[[Conversion - renovaciones sin aporte desde octubre (2026-10-12)]],
[[Como se mide la conversion]], [[Inicio]].

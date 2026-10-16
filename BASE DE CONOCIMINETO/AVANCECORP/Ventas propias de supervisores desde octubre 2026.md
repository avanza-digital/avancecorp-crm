# Ventas propias de supervisores desde octubre 2026

Decisión de Miguel, 16/10/2026: las ventas propias del supervisor conservan su
atribución personal y también aportan al avance de la meta de su equipo. Los
supervisores aparecen al final del ranking, después de todos los analistas.
Vigencia: periodo comercial octubre de 2026 en adelante.

Continúa la atribución establecida en [[Lead propio del supervisor - 2026-09-16]].
Desde octubre, la presentación separa a Supervisión de la producción externa
descrita en [[Produccion fuera del ranking (decision 2026-09-02)]]. No se fijó
una nueva meta individual para supervisores. Capital y contratos se agregan por
categoría y moneda; la meta de conversión de analistas no se diluye.
Ver también [[Metas del asesor van en soles]].

Implementación preparada en copia aislada, **aún no publicada**:
`crm.cumplimiento_metas_fn` conserva el contrato `fuera_ranking` y desde octubre
permite al supervisor activo leer solo su propia producción. La foto del mes
cerrado manda; no se reescribe. El cliente suma el aporte a su equipo y conserva
el total de empresa una sola vez. Sin actividad no se fabrica una fila.

Migración `20261016162937_crm_supervisores_ventas_equipo.sql`.
Ensayo y límites: `CRM-Avance-Corp/docs/plans/supervisores-metas/VERIFICACION.md`.
Claude revisó y JEV seleccionó contexto; Codex implementó y ejecutó los checks.


## Revisión previa (auditor-rls interno, 06/10): CHANGES_REQUESTED sin P0/P1 — ya atendida en lo transcrito arriba
- P2 la reversa borraba el ayudante sin mirar si otra función lo llama (pg_depend no ve una llamada dentro de un cuerpo
  plpgsql/sql con texto) → preflight con P0409 si algún prosrc fuera de las diez piezas lo nombra; postflight: cero menciones.
- P2 la reversa resellaba el censo sin comprobar que el sello estaba al día → mismo par de comprobaciones que la migración.
- P3 la reversa no comprobaba el candado de migraciones ni prosecdef → añadidos.
- P3 guarda contra llamadores nuevos de las dos privadas que se recrean (migración y reversa).
- P3 gate de RLS: la paridad del desglose suma `cierres.base_cargada ?? 0` y hay un bloque propio de B11 (catálogo + contrato).
- Pantalla: la cabecera «Base» se oye «Base cargada»; el resumen (9 cifras) pasa a rejilla de 3 columnas.

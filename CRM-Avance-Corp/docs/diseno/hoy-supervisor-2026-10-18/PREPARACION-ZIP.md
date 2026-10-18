# Preparación de la revisión para el ZIP

La candidata parte de `49e2267c7814c3195b82eec4d4d1d88183d2cfd2`, confirmado contra
`avancecorp/main` por fetch y ls-remote el 18/10/2026. Se trabajó sobre `main` en
una copia local limpia; su upstream es `avancecorp/main`. El taller original
permanece en su rama anterior, con sus cambios ajenos conservados. No worktrees,
ramas de release ni push forzado.

## Integración revisada por Codex

- Nuevos componentes/estilos, lectores y pruebas de Hoy; enrutamiento solo del supervisor.
- Cambios mínimos compartidos: clave del resumen por actor y sondeo optativo,
  metadato de posible recorte legado de Facturación, ref de DialogTitle y lector
  demo procedente de contratos existentes.
- Se preservan las funciones posteriores de Main: reemplazos de inversión,
  plazos de carga, ventas propias de supervisores y reglas oficiales de valoración.
- No cambios en dependencias, lockfiles, SQL, Edge, permisos ni configuración de agentes.
- Gate integral PASS; detalles en `VERIFICACION-FINAL.md`.

## Configuración y dependencias

Configuración pública existente de producción, proyecto `dctqcbznekcyxhjujuci`;
clave anónima validada localmente, sin imprimirla. Demo desactivada. Archivo de
entorno ignorado y fuera del ZIP. `verify:release` vuelve a comprobar destino,
clave no privilegiada y presencia real en el bundle después de construir.

Reutiliza los lectores ya presentes en Main: resumen de cartera, Gestión Diaria
(equipo, llamadas y pendientes), Citas, conversión/cumplimiento mensual y
Facturación V2/legada. Este cambio no necesita instalar SQL/Edge nuevos.
El inventario de migraciones del manifiesto no acredita instalación productiva.
La conciliación autenticada no se ejecutó; no se afirma paridad comprobada contra
la base viva. Ausencia/error de una fuente se muestra sin sustituirla por cero.

## Reversión identificada

Artefacto anterior local: `crm-20261018T070707Z-f25942197d84.zip`, commit
`f25942197d84fa14b2082a8efb09483e98180ca3`, build `build-20261018T070707022Z`.
SHA-256 `9fae31c00e6eb960cfb281993239bd2f91549bfb969b883c9c1d92ab219b7e80`.
ZIP y manifiesto existen en el taller original; tamaño, SHA y CRC verificados.
`supabase/migrations/MIGRACIONES.md` de Main registra su publicación a las 02:30
Lima del 18/10. Es una referencia documentada y verificada localmente, no una
comprobación nueva de qué versión está viva al futuro momento de publicar.

El cierre de fase 7 se registra en el acta de entrega externa al código, una vez
creado el commit y comprobada igualdad local/remota. Se construye desde ese
commit limpio, sin `--allow-dirty`. La identidad final, el cierre de fase 8 y
los hashes se guardan en `releases/hoy-supervisor-2026-10-18/ENTREGA-ZIP.md` para
no introducir otro commit después del build ni volver inconsistente su identidad.

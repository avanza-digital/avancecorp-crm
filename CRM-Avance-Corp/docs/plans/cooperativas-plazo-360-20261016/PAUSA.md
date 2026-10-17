# Pausa segura — 16/10/2026

Solicitada por Miguel: «cuando sea seguro pausamos porfa».

- **Sin publicar, sin merge SQL a producción y sin push a Main.**
- Procesos de pruebas detenidos; el control de scripts terminó PASS y restauró
  sus mutaciones temporales. Contenedor E2E detenido.
- Banco temporal `bede730d-5858-43de-98ae-fe5fc17789f5` eliminado y ausencia
  verificada. No queda coste de ese banco desde su eliminación.
- Credenciales temporales y exportaciones privadas sensibles retiradas.
- Checkout compartido preservado en su rama original, con sus trabajos ajenos.

## Trabajo guardado

Clone aislado: `/private/tmp/avancecorp-coop360-release-20261016`.
Commit local de la funcionalidad: `d4d47502087b2ebd394c64456bee28a656317079`.
Base Main observada: `1170a5e36b957d186f079edf053d2e7745351cd5`.
Los ajustes de auditoría, fixtures y acta están preparados sin commit en el clone.
`release-pausado-desde-1170.patch` conserva el cambio completo y ficheros nuevos
contra esa base, por si se limpia `/private/tmp`. Se aplica sobre una copia
limpia de esa base; luego hay que integrar Main remoto vigente sin sobrescribirlo.

## Verificado

- App: `npm run check` PASS, 6.998 pruebas. E2E completo Docker: 439 passed,
  26 skipped, 0 failed. La app no cambió tras estas ejecuciones.
- Scripts, preflights seed/RLS/Edge y tipos: PASS.
- Auditorías de lectura: tres controles OK, 43 mutantes oficiales y 4
  adicionales detectados. Policies, ACL y propietarios conservados.
- SQL cooperativo: 95 comprobaciones Auth/RPC/Storage del ensayo inicial PASS.
- Rama de release: historial base de 487 filas idéntico al origen y solo las
  tres migraciones candidatas registradas con su SQL exacto.
- RLS integral: INCOMPLETO, detenido con 1.677 positivas y tres fallos antiguos
  identificados y corregidos en el código/fixture, pendientes de repetición.
  La salida parcial no acredita un PASS global.

## Retomar

1. Leer `ACTA-RELEASE.md` y este expediente; comprobar Git/producción vigentes.
2. Crear otro banco con la tarifa autorizada vigente. No reutilizar credenciales
   ni referencias de los bancos eliminados. No copiar clientes reales.
3. Restaurar esquema/historial base exactos y la configuración inicial de las
   migraciones; incluir catálogos de auditoría, miembros de roles internos,
   política histórica de Gestión Diaria, hito de rentabilidad y control de reparto.
4. Aplicar y comprobar los tres SQL candidatos del acta. Repetir la matriz RLS
   completa con las expectativas actuales de Coordinación y la firma F15.
5. Solo con gates pertinentes PASS: integrar Main, push sin forzar, construir
   desde commit limpio sincronizado, verificar ZIP/manifest y preflight.
6. Merge nativo de las migraciones, publicación Hostinger y smoke HTTP/UI.
   El ZIP d4d4750 que quedó preparado nunca se publicó y debe reconstruirse.
7. Comprobar conservación de históricos, eliminar el nuevo banco y registrar
   el commit realmente publicado en el acta y el vault.

La autorización de release y de corrección del control se conserva. No se
debe publicar saltándose los gates ni atribuir un PASS al review adicional:
su wrapper no devolvió VERDICT válido en los dos intentos acotados.

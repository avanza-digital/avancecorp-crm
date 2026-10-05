# Menú de Gerencia: integración del historial para publicar

La PR #194 incorporó el menú aprobado a `avancecorp/main` como el commit squash
`7da57c9786bde1a173aa8f2ddce5bca02b9d43ad`. Su árbol es idéntico al candidato
verificado `38ad8fcb8b19871186baf6a1426f6578c36a2095`.

El squash conserva los archivos, pero no la ascendencia del commit publicado
`5002b29725943d281cad3dd1eeeef1ae989616b4` ni la del Main local
`92c4554a4ac52f8c9047416bee060d1bd9973e81`. El preflight de publicación comprueba
esa ascendencia para impedir una regresión de producción.

La rama de rescate existente incorpora ahora también el squash de #194 mediante
un merge sin cambios de contenido. Su siguiente integración a Main debe hacerse
con **merge commit**, conservando sus padres. No usar squash ni rebase. La
excepción OrganizationAdmin ya configurada permite esta integración por PR;
no se modifican reglas ni se omite el preflight obligatorio de GitHub.

## Evidencia reutilizable del mismo código

- PR #194: `preflight`, `app-check` y `verify` PASS.
- `npm run check` local sobre `38ad8fcb`: PASS, 378 archivos / 6109 pruebas.
- E2E Docker: 337 passed / 2 failed / 26 skipped; los dos fallos de fixtures de
  fecha se corrigieron y sus grupos de pruebas dieron 13/13 y 2/2 PASS.
- Revisión independiente del menú y de la integración: PASS.
- Esta continuación cambia solo este documento respecto de Main #194; el
  código, los tests, las dependencias, los workflows y el SQL son idénticos.

La publicación se construirá desde el Main integrado y limpio, se verificará
contra la versión viva y se registrará después de comprobar los archivos
servidos. Este documento acredita la integración, no un despliegue ya realizado.

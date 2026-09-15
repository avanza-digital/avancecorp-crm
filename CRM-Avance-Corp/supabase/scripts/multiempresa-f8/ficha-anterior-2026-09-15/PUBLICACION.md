# Ficha anterior adaptada a multiempresa — publicación verificada

**Publicado en https://crm.miavance.com/.** Miguel aprobó el diseño y la secuencia de verificación real y publicación. Su aprobación visual no se registra como conformidad financiera ni cierre general G7.

Producto: `d93d8057e91d70b825722b77f395b525df35c21e`.
Build: `build-20260915T160348830Z`.
Artefacto: `CRM-Avance-Corp/releases/crm-20260915T160349Z-d93d8057e91d.zip`.
SHA-256: `f59c72d0dfd7e54d8f11f8200c0c263e3339c84e45807f631b6af5e807aa49a6`.

## Procedimiento y resultado

Se siguió `CRM-Avance-Corp/.claude/skills/release-crm/SKILL.md` con la autorización humana recibida. `main`, `avancecorp/main` y la consulta directa al remoto coincidían en el commit de producto antes de construir. El commit incorpora la publicación previa que cierra «Nuevo cliente» a analistas (`cdf03f2` y acta `de7cb97`).

La huella del código coincide con la verificación local: **3.596 pruebas y 23 recorridos relacionados PASS**, dos revisiones de Claude con hallazgos resueltos por el PRIMARY. El pre-push repitió las 3.596 pruebas con PASS. `release:crm` ejecutó configuración, build y verificación del bundle; `release:crm:verify` pasó. Además se contrastó cada archivo del ZIP contra su SHA-256 del manifiesto.

Se usó `--allow-dirty` exclusivamente por los mismos tres archivos ajenos ya documentados en el release anterior: una nota de terminales y dos evidencias F7. Ninguno es fuente de `app/` ni entra al ZIP. No había cambios pendientes en el código publicado. La comprobación automática exigió que esa lista coincidiera exactamente con la del artefacto anterior.

Hostinger aceptó el despliegue. La comprobación HTTP posterior verificó **92 entradas**: **80 hashes exactos**, once PNG preexistentes con transformación CDN y `.htaccess` bloqueado. Todos los PNG conservan el hash del artefacto anterior; no se repitió la comparación de píxeles del CDN. `/` coincide con el `index.html` del ZIP, `version.json` es el nuevo build y el portal responde HTTP 200. `.env`, `package.json` y el ZIP público devuelven 403/404.

La copia de reversa inmediata es el release productivo anterior `crm-20260915T154200Z-cdf03f266805`, SHA-256 `574641dfa9641fd44f9cfd7648db6a9b170957bd6958c6ffad5a35281f3b1061`. Su ZIP pasó el verificador antes de publicar; la versión y sus 80 archivos de código/configuración coincidían con la web anterior.

## Comprobación de la realidad

La conexión administrada permitió consultas de lectura sin pedir credenciales ni crear un banco adicional. Se midieron los ocho supuestos del gate por SQL: siete se cumplen y continúa una divergencia de datos históricos, **296 clientes activos sin domicilio legal**. La consulta de perfiles usó `public.perfiles`; se detectó que el script CLI original presupone `crm.perfiles`, que no existe. Por eso este resultado se declara como **medición SQL equivalente**, no como PASS de `npm run gate:realidad`. No se rellenaron domicilios ni se cambió ese script en esta publicación.

La cartera y primera ficha se consultaron con los cuatro contextos nominales, rol SQL `authenticated`, UID local, límite de ocho segundos por sentencia y `ROLLBACK`. Los cuatro pasaron: cartera habilitada, respuesta de ficha presente, capitales tipados por empresa/moneda y exclusión demo. Las carteras devolvieron 492, 237, 50 y 21 personas según el ámbito del actor. Los tiempos MCP incluyen transporte/cola y no se presentan como latencia SQL.

El control del piloto mantiene revisión 1 y cuatro participantes vigentes, hasta el **21/09/2026 a las 13:23 Lima**. No hubo migraciones, cambios de banderas ni operaciones económicas de prueba. Las auditorías transitorias de las lecturas se revirtieron con la transacción.

**NOT RUN:** login JWT/HTTP y recorrido visual productivo, porque no había navegador conectado; matriz E2E completa de toda la aplicación y nueva matriz RLS general. La aprobación de Miguel corresponde a la comparación visual con datos sintéticos.

## Evidencia y siguiente paso

- [Publicación estructurada](PUBLICACION.json).
- [Web anterior](web-antes.json) y [web publicada](web-despues.json).
- [Lectura real y roles](realidad-y-roles.json), [consulta del gate](gate-realidad-equivalente.sql) y [verificador HTTP](verificar_web.py).
- [Comparación aprobada](COMPARACION.html) y [preparación/revisiones](README.md).

G7-R01 queda **resuelto técnicamente**: la corrección publicada antes de este ajuste y esta nueva lectura productiva confirman que cartera/ficha responden para supervisor y Gerencia. El acta G7 conserva pendientes los recorridos humanos, el muestreo de identidades/inversiones, las situaciones especiales, las conciliaciones y firmas. Continuar desde `../ACTA-G7.md`; no interpretar la aprobación de la ficha como cierre de todo F8 ni apertura de F9.

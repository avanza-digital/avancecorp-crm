# Deploy de Beneficios MasCapitalGroup

Estado: **✅ PUBLICADO EN PRODUCCIÓN el 2026-08-25**.

La sección de Beneficios del portal ya muestra el título **Aliados de
MasCapitalGroup** en `https://miavance.com/beneficios.html`. El cambio vivía en
el commit local `403c252` de `public_html` (`Actualiza título de aliados en
beneficios`) desde el 24 de agosto y era de **una sola línea**: el `<h3
class="ben-splash-title">` pasó de «Los primeros aliados de la red AvanceCorp»
a «Aliados de MasCapitalGroup». Nada más se tocó.

## Cómo se publicó

Se usó el ZIP ya preparado
(`_no-subir-a-hostinger/deploy-pendiente-beneficios-mascapitalgroup/miavance-beneficios-mascapitalgroup-20260824.zip`,
SHA-256 `6950a205…`) con `hosting_deployStaticWebsite` sobre `miavance.com`,
`removeArchive: false`.

**El candado que hizo seguro un deploy de sitio completo:** antes de subir nada
se listó producción y se comparó archivo por archivo contra el ZIP —
**92 archivos en ambos lados, idénticos en ruta y tamaño salvo
`beneficios.html`** (31 719 → 31 704 bytes, exactamente los 15 caracteres que
se acortó el título). Esa comparación es lo que descarta el riesgo real de
`deployStaticWebsite`: sobrescribe el sitio entero, así que un ZIP incompleto
habría borrado lo que no contuviera. Ver [[cdn-delante-del-portal]].

## Trampas encontradas

- **El primer intento falla con un 500 al pedir las credenciales de subida.**
  Le pasó a la sesión del 24-ago (que lo leyó como «expiró») y volvió a pasar
  el 25-ago. **No es el deploy: es el paso previo de credenciales, y no sube
  nada.** El segundo intento, idéntico, funcionó. Antes de reintentar,
  comprobar producción (`hosting_getWebsiteFileContentV1` sobre el archivo, que
  esquiva la CDN y no gasta un `curl`).
- **429 «Too Many Attempts» inmediatamente después del deploy.** Purgar la
  caché y listar archivos devuelven 429 durante ~90 s tras publicar. Cede solo;
  no es un fallo del despliegue.

## Verificación que quedó hecha

1. Archivo en el servidor: 31 704 bytes con el título nuevo.
2. URL pública sirviendo el texto nuevo (el HTML sale con `max-age=0`, así que
   no hubo que esperar a la CDN — a diferencia del JS, que se cachea 7 días).
3. Caché purgada.
4. El ZIP **no** quedó en el document root: los 14 archivos de primer nivel son
   los mismos de antes.

Relacionado: [[Carrusel de beneficios táctil]] · [[cdn-delante-del-portal]].

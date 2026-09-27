---
tags: [crm, ranking, release, verificacion]
fecha: 2026-09-26
estado: publicado y verificado por HTTPS
---

# Ranking — publicación verificada

Publicado en https://crm.miavance.com el detalle de capital y conversión por
canal de llegada de la ficha del analista, tanto en Gerencia como en Equipo.
Esta acta actualiza el estado pendiente de [[Ranking - capital por canal de llegada (decision 2026-09-25)]].

## Fuente y artefacto efectivos

- PR integrada: https://github.com/avanza-digital/avancecorp-crm/pull/111.
- Commit construido y publicado: `526d6d90c621e4072251818d1325b7bd0c01b2ca`.
- Main local de la copia limpia y `avancecorp/main` coincidían antes de construir
  y se reconfirmó el remoto antes de subir. El árbol de implementación ensayado
  coincide con el de este commit. No se incluyeron cambios ajenos del workspace.
- Artefacto: `CRM-Avance-Corp/releases/crm-20260926T214044Z-526d6d90c621.zip`.
- SHA-256: `c624754aa2bf8494004da06bb119642603099629d0b14d2be3f4fb706a358fc1`.
- Manifiesto y reporte público: mismo prefijo, sufijos `.manifest.json` y
  `.https-verificado.json`, conservados junto al ZIP en releases.
- Compilación limpia con demo deshabilitado. `release:crm` y
  `release:crm:verify`: PASS. No se utilizó `--allow-dirty` ni push forzado.

## Verificación

- Hostinger aceptó el despliegue. Verificación pública completada a las
  `2026-09-26T21:43:56.525Z`: **80/80 PASS**, HTTP 200 y SHA-256 idéntico al
  manifiesto para index.html, version.json y todos los JS/CSS del paquete.
- La portada `/` devuelve HTTP 200 y sus bytes coinciden con el index construido
  (SHA-256 `cd3c27ed198f30549b53590cefcb94cc955d4cad2f695d90c978b2c938df395e`).
- `npm run check`: 4454 tests PASS. E2E local Docker: 276 PASS, 26 omitidos;
  smoke final focalizado de Ranking: 1 PASS. GitHub: todos los checks requeridos PASS.
- Revisión independiente final de Claude: PASS. Matriz focalizada de acceso
  usando Auth/PostgREST y pruebas de cierre real, céntimos, fotografía inmutable,
  peso referido y carga: PASS. Suite RLS general de conversiones: NOT RUN de nuevo.
- Interacción autenticada en el sitio productivo: NOT RUN; no se crearon ni
  modificaron datos reales para el smoke. El navegador integrado no estaba disponible.

## Servidor y límites

El SQL aprobado, SHA-256
`0e883ef84e778699a60223392dc62e2442f9a9f93e36a257159a890d67fc95ec`,
se publicó previamente por merge nativo de la rama exclusiva de Supabase.
Registro productivo: `20260926211038_crm_ranking_origen_vendedor`. Las funciones
productivas coinciden con las ensayadas; RPC sin acceso anónimo. Conciliación
de solo lectura: 17/17 analistas de agosto y 19/19 de septiembre, por moneda.
Las 21 Edge Functions conservaron su código y configuración de verify_jwt.
La rama temporal propia fue eliminada tras verificar el merge; las otras ramas
no se tocaron.

Las fotos históricas sin desglose guardado muestran «Desglose no disponible»;
no se reconstruyeron desde leads actuales. Los cierres futuros conservan su
desglose sellado. El grupo Cartera mantiene renovaciones y upgrades separados
del canal de llegada original.

## Recuperación

Se conserva el anterior artefacto efectivamente publicado
`crm-20260925T220851Z-caf999794655.zip` y su manifiesto en releases, SHA-256
`f0ab9a500e87507b8d268cbb4fcb8452435d6fd00c437e0c4e42e5a261d550bc`.
No fue necesario restaurarlo. Esta acta posterior no cambia la identidad del
commit desplegado ni requiere otra publicación.

Relacionado con [[Main unico - sincronizacion y publicacion 2026-09-04]],
[[Ranking de capital total unificado (TC BCRP)]] y [[Canales de origen de leads CRM]].

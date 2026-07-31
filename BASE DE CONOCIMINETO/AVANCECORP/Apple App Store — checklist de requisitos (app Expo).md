# Apple App Store — checklist de requisitos (app Expo)

> Creada 2026-07-30 a pedido de Miguel ("¿tú tendrías en cuenta lo que pide Apple?").
> Aplica a la [[App nativa Expo (portal clientes)]]. **Regla de trabajo:** antes de
> enviar a revisión (F5) se hace una pasada contra las App Review Guidelines
> **vigentes** en developer.apple.com — esta nota es el mapa, no la fuente final.

## Lo que YA está resuelto por diseño

- **4.2 Funcionalidad mínima (no web wrapper):** por esto se eligió Expo nativo y se
  descartó Capacitor. La app es React Native real, no una PWA embebida. ✅
- **Login nativo real** (espejo de auth.js, sin webview de login). ✅

## Lo que APLICA a esta app y hay que cumplir antes del submit

1. **3.2.1 — Apps financieras deben venir de la institución:** apps de inversión /
   manejo de dinero deben publicarse desde la cuenta del **ente financiero mismo**.
   ⚠️ Consecuencia directa: la cuenta Apple Developer (US$99/año) debe ser de tipo
   **Organization a nombre de AVANCE CORP** (requiere número **D-U-N-S** de la empresa,
   entidad legal y web corporativa), NO cuenta individual a nombre de Miguel.
   El D-U-N-S es gratis pero puede tardar días/semanas → tramitarlo temprano.
2. **2.1 Completitud — sin placeholders:** Apple rechaza apps con secciones vacías.
   Las pestañas Inversión / Documentos / Novedades (hoy placeholders F3/F4) deben
   estar funcionales antes de enviar. No se puede enviar "F0 + promesas".
3. **2.1 Cuenta demo para el revisor:** la app es solo-login → hay que dar al equipo
   de revisión de Apple credenciales de un **cliente de prueba con datos ficticios**
   (nunca un cliente real). Preparar ese usuario en Supabase antes del submit.
4. **5.1.1 / 5.1.2 Privacidad:**
   - URL de **política de privacidad** publicada (puede vivir en miavance.com).
   - **Etiquetas de privacidad** en App Store Connect (qué datos se recogen: identidad,
     datos financieros, etc. — declararlo honesto; mentir ahí es causal de baja).
   - **Purpose strings** en Info.plist vía app.json: p. ej. `NSFaceIDUsageDescription`
     cuando entre la biometría (F1).
5. **5.1.1(v) Eliminación de cuenta — CORREGIDO 2026-07-30:** la Guía Expo V2 (en
   `avancecorp-app/95_GUIAS_FUENTE/`) demuestra que "en principio no obliga" era
   optimista: sin botón de borrado dentro de la app (o con solo "desactivar") el
   rechazo es prácticamente garantizado en AMBAS tiendas, y Google exige además una
   página web pública de solicitud de borrado. Se implementa el flujo de 8 pasos de
   la guía: botón visible, distinción cuenta-del-portal vs contrato, reautenticación,
   borrado real de lo no retenido por ley, divulgación de la retención legal con norma
   nombrada, flujo de atención para lo contractual, confirmación y URL web pública.
6. **4.8 Sign in with Apple:** solo es obligatorio si ofreces login de terceros
   (Google, Facebook…). Nuestra app usa SOLO email/clave de cuentas empresariales
   → **no aplica**. No agregar logins sociales sin revisar esta regla.
7. **Push (F5):** pedir permiso con contexto, nunca condicionar el uso de la app a
   aceptarlo, y nada de push de marketing sin consentimiento explícito.
8. **Export compliance (cifrado):** al subir, App Store Connect pregunta por cifrado.
   Usamos solo HTTPS/TLS estándar → exención estándar; se declara en app.json
   (`ITSAppUsesNonExemptEncryption: false`) para no responderlo en cada build.
9. **Metadata:** ícono y splash reales de AVANCE CORP (hoy siguen los de plantilla),
   capturas por tamaño de dispositivo, descripción sin promesas de rentabilidad que
   suenen a asesoría financiera no regulada, clasificación de edad (finanzas → 4+,
   pero revisar el cuestionario vigente).

## Añadidos 2026-07-30 (de la Guía Expo V2)

- **Unlisted App Distribution** es la vía correcta en iOS (app para clientes de una
  empresa específica con distribución pública = motivo de rechazo documentado). Se
  solicita a Apple; la app queda accesible solo por enlace directo. Pasa App Review
  completo igual. Además: **disponibilidad restringida a Perú** en ambas tiendas.
- **2.3.3 Screenshots:** no pueden mostrar solo el login/splash — el principal debe ser
  el dashboard con datos ficticios (2.3.9: jamás datos de un cliente real).
- El **correo de enrolamiento debe ser del dominio corporativo** (el Gmail actual no
  sirve) y las URLs de soporte/marketing/privacidad deben estar en el dominio propio.

## Proceso acordado

- Cada fase nueva (biometría, documentos, push) se implementa consultando el requisito
  de Apple correspondiente EN ESE MOMENTO, no al final.
- Antes de F5: pasada completa contra las guidelines vigentes + `eas submit`.
- Android/Google Play tiene su checklist propio (menos estricto) — se documentará
  cuando toque, en su propia nota.

Relacionadas: [[App nativa Expo (portal clientes)]] ·
[[Visión fintech — app nativa y transferencias]]

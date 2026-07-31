# Visión fintech — app nativa y transferencias

> Decisión de dirección de Miguel (2026-07-29): AVANCE CORP será más adelante una
> **entidad bancaria con licencia propia** (no fintech con socio BaaS). La app debe
> poder transferir dinero cuando la licencia exista; mientras tanto, la instrucción
> es tener la app **lo más adelantada posible**.

## Arquitectura objetivo (acordada en conversación, sin ejecutar aún)

- **App nativa con Expo (React Native)** para el portal de clientes (miavance.com hoy es PWA).
  Elegida sobre Flutter / nativo puro / Capacitor: reutiliza el React del CRM, EAS Update
  despliega JS sin revisión de tienda, y da biometría + push (prerrequisitos de banca).
- **Supabase sigue siendo la base de datos y el login** (mismo Postgres, mismos JWT).
- **Core financiero en Python (FastAPI)**: servicio aparte que lleva el *ledger* de doble
  partida (inmutable, idempotente, auditable). Valida los JWT de Supabase — un solo login.
  Se madura primero con tareas sin plata (PDFs, IA) antes de confiarle saldos.
- El dinero físico se mueve SOLO por rieles regulados: pasarelas (Culqi/Niubiz/Izipay/
  Mercado Pago → Yape/Plin) para cash-in; APIs bancarias / CCE para pagos salientes.
  Las tarjetas nunca tocan nuestros servidores (PCI queda en la pasarela).

## Restricción legal (bloqueante antes de mover un sol)

Custodiar saldos y permitir transferencias entre usuarios es territorio **SBS**.
El plan de Miguel es la **licencia propia** (entidad bancaria); hasta que exista,
cualquier movimiento de dinero va por rieles regulados de terceros (pasarelas/APIs
bancarias). El hito legal lo maneja Miguel con su abogado; el software no lo espera:
se construye todo y las transferencias se activan cuando la figura legal exista.

## Roadmap por etapas (nada se bota)

1. App Expo F0–F5 contra Supabase (login+biometría → dashboard/inversión → resto → push y tiendas).
2. Core Python/FastAPI junto a Supabase (ledger + auditoría; primero PDFs/IA).
3. Cash-in por pasarela y pagos por API bancaria.
4. Transferencias entre usuarios — solo con figura legal resuelta.
   Aquí aplica `aws_fintech_stack_referencia.md` (raíz del repo): migrar a AWS
   (Aurora sigue siendo Postgres, FastAPI corre en Lambda) cuando regulación/escala lo pidan.

## Contexto que disparó esto

Google Play Protect bloquea la PWA instalada desde **Samsung Internet** ("app no segura",
problema de Samsung, no nuestro). Arreglo corto pendiente e independiente: detectar
`SamsungBrowser` en el portal y redirigir la instalación a Chrome; y/o TWA en Play Store.
La cuenta de Google Play (US$25 única vez) sirve para la TWA y para la app Expo.

Relacionadas: [[App nativa Expo (portal clientes)]] (por crear cuando arranque F0),
[[Ciclo de vida de contratos]] (los avisos de vencimiento serán push en la app).

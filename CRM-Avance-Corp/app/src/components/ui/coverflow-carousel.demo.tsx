"use client"

import {
  CoverflowCarousel,
  type CoverflowSlide,
} from "@/components/ui/coverflow-carousel"

const ALLY_SLIDES: CoverflowSlide[] = [
  {
    src: "/aliados/phoenix.png",
    alt: "Logo de Phoenix",
    title: "Phoenix",
    subtitle: "Academia de trading",
    meta: [
      { label: "Categoría", value: "Educación" },
      { label: "Estado", value: "Convenio en negociación" },
    ],
  },
  {
    src: "/aliados/belysh.png",
    alt: "Logo de Belysh",
    title: "Belysh",
    subtitle: "Belleza y bienestar",
    meta: [
      { label: "Categoría", value: "Bienestar" },
      { label: "Estado", value: "Convenio en negociación" },
    ],
  },
  {
    src: "/aliados/ntc-agency.png",
    alt: "Logo de NTC Agency",
    title: "NTC Agency",
    subtitle: "Marketing y branding",
    meta: [
      { label: "Categoría", value: "Negocio" },
      { label: "Estado", value: "Convenio en negociación" },
    ],
  },
  {
    src: "/aliados/qorilazo.png",
    alt: "Logo de Cooperativa Qorilazo",
    title: "Cooperativa Qorilazo",
    subtitle: "Cooperativa de ahorro y crédito",
    meta: [
      { label: "Categoría", value: "Finanzas" },
      { label: "Estado", value: "Convenio en negociación" },
    ],
  },
  {
    src: "/aliados/mascapital.png",
    alt: "Logo de MásCapital",
    title: "MásCapital",
    subtitle: "Servicios financieros",
    meta: [
      { label: "Categoría", value: "Finanzas" },
      { label: "Estado", value: "Convenio en negociación" },
    ],
  },
  {
    src: "/aliados/clinica-alvarez.png",
    alt: "Logo de Clínica Álvarez",
    title: "Clínica Álvarez",
    subtitle: "Salud y bienestar",
    meta: [
      { label: "Categoría", value: "Bienestar" },
      { label: "Estado", value: "Convenio en negociación" },
    ],
  },
  {
    src: "/aliados/prodelco.png",
    alt: "Logo de Prodelco",
    title: "Prodelco",
    subtitle: "Cooperativa de ahorro y crédito",
    meta: [
      { label: "Categoría", value: "Finanzas" },
      { label: "Estado", value: "Convenio en negociación" },
    ],
  },
]

export default function BenefitsCoverflowDemo() {
  return (
    <section className="w-full overflow-hidden rounded-3xl bg-background py-6">
      <div className="mb-1 px-6 text-center">
        <p className="text-xs font-semibold uppercase tracking-[0.16em] text-warning-text">
          Programa de beneficios
        </p>
        <h2 className="mt-2 text-2xl font-bold tracking-tight text-primary">
          Aliados de MasCapitalGroup
        </h2>
      </div>

      <CoverflowCarousel
        slides={ALLY_SLIDES}
        rotate={28}
        depth={0.36}
        perspective={4.5}
        falloff={0.7}
        fade={0.17}
        cardWidth="clamp(210px, 68vw, 292px)"
        gap={0.08}
        imageFit="contain"
        showCaption
        showPagination
        showNavigation
        label="Aliados de MasCapitalGroup"
        cardClassName="border border-border bg-white shadow-[0_22px_50px_-24px_rgb(17_30_61_/_0.42)]"
        imageClassName="p-7"
      />
    </section>
  )
}

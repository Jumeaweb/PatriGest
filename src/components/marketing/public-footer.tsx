import Image from "next/image";
import Link from "next/link";
import { APP_NAME, APP_SLOGAN, APP_VERSION } from "@/lib/app";

export function PublicFooter() {
  return (
    <footer className="border-t border-brand-accent/20 bg-white">
      <div className="mx-auto flex max-w-7xl flex-col gap-8 px-5 py-10 sm:px-8 lg:flex-row lg:items-end lg:justify-between lg:px-10">
        <div className="max-w-md">
          <Image src="/logos/patrigest-logo-full.png" alt={APP_NAME} width={509} height={559} className="h-28 w-auto" />
          <p className="mt-3 text-sm text-[#64748B]">{APP_SLOGAN}</p>
          <p className="mt-5 text-xs text-[#94A3B8]">© {new Date().getFullYear()} {APP_NAME}. Tous droits réservés.</p>
          <Link href="/historique-versions" className="focus-ring mt-1 inline-block rounded text-xs text-[#94A3B8] hover:text-[#64748B]">{APP_NAME} v{APP_VERSION}</Link>
        </div>
        <nav className="flex flex-wrap gap-x-6 gap-y-3 text-sm font-semibold text-[#64748B]" aria-label="Navigation de pied de page">
          <a className="focus-ring rounded-md hover:text-brand-accent" href="#fonctionnalites">Fonctionnalités</a>
          <a className="focus-ring rounded-md hover:text-brand-accent" href="#comment-ca-marche">Comment ça marche</a>
          <a className="focus-ring rounded-md hover:text-brand-accent" href="#compte-de-gestion">Compte de gestion</a>
          <Link className="focus-ring rounded-md hover:text-brand-accent" href="/connexion">Se connecter</Link>
          <Link className="focus-ring rounded-md text-[#EA580C] hover:text-orange-700" href="/inscription">Créer un compte</Link>
        </nav>
      </div>
    </footer>
  );
}

import Link from "next/link";
import { APP_CONTACT_EMAIL, APP_NAME, APP_PUBLISHER_NAME, APP_PUBLISHER_URL, APP_SUPPORT_EMAIL, APP_VERSION } from "@/lib/app";

export function PublicFooter() {
  return (
    <footer className="border-t border-brand-accent/20 bg-white">
      <div className="mx-auto max-w-7xl px-5 py-6 sm:px-8 lg:px-10">
        <nav className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3 text-sm font-semibold text-[#64748B] lg:justify-between" aria-label="Navigation de pied de page">
          <a className="focus-ring rounded-md hover:text-brand-accent" href="#fonctionnalites">Fonctionnalités</a>
          <a className="focus-ring rounded-md hover:text-brand-accent" href="#comment-ca-marche">Comment ça marche</a>
          <a className="focus-ring rounded-md hover:text-brand-accent" href="#compte-de-gestion">Compte de gestion</a>
          <a className="focus-ring rounded-md hover:text-brand-accent" href={`mailto:${APP_CONTACT_EMAIL}`}>Contact</a>
          <a className="focus-ring rounded-md hover:text-brand-accent" href={`mailto:${APP_SUPPORT_EMAIL}`}>Assistance</a>
          <Link className="focus-ring rounded-md hover:text-brand-accent" href="/connexion">Se connecter</Link>
          <Link className="focus-ring rounded-md text-[#EA580C] hover:text-orange-700" href="/inscription">Créer un compte</Link>
        </nav>
        <p className="mt-4 border-t border-brand-accent/20 pt-4 text-center text-xs leading-5 text-[#94A3B8]">© 2026 {APP_NAME}. Tous droits réservés. {APP_NAME} est édité par <a href={`${APP_PUBLISHER_URL}/`} target="_blank" rel="noopener noreferrer" className="focus-ring rounded hover:text-brand-accent">{APP_PUBLISHER_NAME}</a>. <Link href="/historique-versions" className="focus-ring rounded hover:text-[#64748B]">{APP_NAME} v{APP_VERSION}</Link></p>
      </div>
    </footer>
  );
}

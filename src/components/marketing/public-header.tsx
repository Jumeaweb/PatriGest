import Image from "next/image";
import Link from "next/link";
import { APP_NAME } from "@/lib/app";

export function PublicHeader() {
  return (
    <header className="sticky top-0 z-50 border-b border-[#E2E8F0]/80 bg-white/95 backdrop-blur">
      <div className="mx-auto flex h-20 max-w-7xl items-center justify-between gap-3 px-5 sm:gap-6 sm:px-8 lg:px-10">
        <Link href="/" className="focus-ring flex shrink-0 items-center gap-2.5 rounded-xl" aria-label={`${APP_NAME}, accueil`}>
          <Image src="/logos/logo.svg" alt="PatriGest" width={133} height={40} priority className="h-10 w-auto shrink-0" />
        </Link>
        <nav className="hidden items-center gap-7 text-sm font-semibold text-[#64748B] md:flex" aria-label="Navigation principale">
          <a className="focus-ring rounded-md transition-colors hover:text-[#2563EB]" href="#fonctionnalites">Fonctionnalités</a>
          <a className="focus-ring rounded-md transition-colors hover:text-[#2563EB]" href="#comment-ca-marche">Comment ça marche</a>
          <a className="focus-ring rounded-md transition-colors hover:text-[#2563EB]" href="#compte-de-gestion">Compte de gestion</a>
        </nav>
        <div className="flex shrink-0 items-center gap-2 sm:gap-3">
          <Link className="button button-secondary min-h-9! whitespace-nowrap px-3! sm:min-h-10! sm:px-5!" href="/connexion">Se connecter</Link>
          <span className="hidden sm:inline-flex"><Link className="button button-primary whitespace-nowrap" href="/inscription">Créer un compte</Link></span>
        </div>
      </div>
    </header>
  );
}

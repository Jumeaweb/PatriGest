import Image from "next/image";
import Link from "next/link";
import { APP_NAME } from "@/lib/app";

export function PublicHeader() {
  return (
    <header className="sticky top-0 z-50 border-b border-brand-accent/20 bg-brand-navigation/95 text-brand-foreground backdrop-blur">
      <div className="mx-auto flex h-20 max-w-7xl items-center justify-between gap-3 px-5 sm:gap-6 sm:px-8 lg:px-10">
        <Link href="/" className="focus-ring flex shrink-0 items-center rounded-xl bg-white/85 p-1" aria-label={`${APP_NAME}, accueil`}>
          <Image src="/logos/patrigest-symbol.png" alt="PatriGest" width={298} height={270} priority className="h-11 w-auto shrink-0" />
        </Link>
        <nav className="hidden items-center gap-7 text-sm font-semibold text-brand-foreground/85 md:flex" aria-label="Navigation principale">
          <a className="focus-ring rounded-md transition-colors hover:text-brand-foreground" href="#fonctionnalites">Fonctionnalités</a>
          <a className="focus-ring rounded-md transition-colors hover:text-brand-foreground" href="#comment-ca-marche">Comment ça marche</a>
          <a className="focus-ring rounded-md transition-colors hover:text-brand-foreground" href="#compte-de-gestion">Compte de gestion</a>
        </nav>
        <div className="flex shrink-0 items-center gap-2 sm:gap-3">
          <Link className="button button-secondary min-h-9! whitespace-nowrap px-3! sm:min-h-10! sm:px-5!" href="/connexion">Se connecter</Link>
          <span className="hidden sm:inline-flex"><Link className="button button-primary whitespace-nowrap" href="/inscription">Créer un compte</Link></span>
        </div>
      </div>
    </header>
  );
}

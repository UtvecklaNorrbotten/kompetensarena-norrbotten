import { Link } from "@tanstack/react-router";
import type { ComponentProps } from "react";

type AppLinkProps = Omit<ComponentProps<typeof Link>, "to"> & {
  /** Sökväg från konfiguration (string i stället för typad route-literal). */
  href: string;
};

/**
 * Wrapper runt TanStack Link som accepterar en vanlig sträng.
 * Används när länkmålet kommer från konfigurationsfiler (t.ex. navigationen)
 * och därför inte kan vara en typad route-literal.
 */
export function AppLink({ href, ...props }: AppLinkProps) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return <Link to={href as any} {...props} />;
}

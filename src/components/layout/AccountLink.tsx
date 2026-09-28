import { useEffect, useState } from "react";
import { Link, useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

/** Visar "Logga ut" när en session finns. Ingen inloggningslänk i publik navigation. */
export function AccountLink() {
  const [email, setEmail] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const navigate = useNavigate();

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setEmail(data.session?.user.email ?? null));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      setEmail(session?.user.email ?? null);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  if (!email) return null;

  async function signOut() {
    await queryClient.cancelQueries();
    queryClient.clear();
    await supabase.auth.signOut();
    navigate({ to: "/auth", replace: true });
  }

  return (
    <div className="hidden items-center gap-3 text-sm md:flex">
      <Link to="/admin/datakallor" className="text-brand-dark underline-offset-2 hover:underline">Admin</Link>
      <Link to="/byt-losenord" className="text-brand-dark underline-offset-2 hover:underline">Byt lösenord</Link>
      <button type="button" onClick={signOut} className="rounded-md border border-border px-3 py-1.5 hover:bg-neutral-surface">
        Logga ut
      </button>
    </div>
  );
}

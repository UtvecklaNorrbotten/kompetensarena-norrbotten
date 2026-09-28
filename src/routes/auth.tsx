import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, type FormEvent } from "react";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { supabase } from "@/integrations/supabase/client";
import { lovable } from "@/integrations/lovable/index";

export const Route = createFileRoute("/auth")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Logga in – Kompetensarena Norrbotten" },
      { name: "description", content: "Inloggning för Kompetensarena Norrbottens medarbetare och administratörer." },
      { property: "og:title", content: "Logga in – Kompetensarena Norrbotten" },
      { property: "og:description", content: "Inloggning för Kompetensarena Norrbottens medarbetare och administratörer." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { name: "robots", content: "noindex, nofollow" },
    ],
  }),
  component: AuthPage,
});

const btn =
  "inline-flex w-full items-center justify-center rounded-md border px-4 py-2.5 font-semibold transition-colors focus-visible:outline-2 disabled:opacity-60";

function AuthPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [forgot, setForgot] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      if (data.user) navigate({ to: "/admin/datakallor", replace: true });
    });
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "SIGNED_IN" && session) navigate({ to: "/admin/datakallor", replace: true });
    });
    return () => sub.subscription.unsubscribe();
  }, [navigate]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) setError("Fel e-postadress eller lösenord.");
  }

  async function onForgot(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: window.location.origin + "/reset-password",
    });
    setBusy(false);
    if (error) setError("Kunde inte skicka återställningslänk. Försök igen.");
    else setInfo("Om adressen finns registrerad har en återställningslänk skickats till din e-post.");
  }

  async function oauth(provider: "google" | "microsoft") {
    setError(null);
    const result = await lovable.auth.signInWithOAuth(provider, {
      redirect_uri: window.location.origin + "/auth",
    });
    if (result.error) setError("Inloggningen misslyckades. Försök igen.");
  }

  return (
    <Section className="py-10 md:py-14">
      <PageHeader eyebrow="Intern" title="Logga in" intro="Inloggning för behöriga medarbetare. Konton skapas av administratör." />
      <div className="mt-8 max-w-sm space-y-4">
        <button type="button" className={`${btn} border-border bg-surface hover:bg-neutral-surface`} onClick={() => oauth("microsoft")}>
          Logga in med Microsoft
        </button>
        <button type="button" className={`${btn} border-border bg-surface hover:bg-neutral-surface`} onClick={() => oauth("google")}>
          Logga in med Google
        </button>
        <p className="text-center text-sm text-ink-muted">eller med e-post</p>
        {forgot ? (
          <form onSubmit={onForgot} className="space-y-3">
            <label className="block text-sm font-semibold">
              E-post
              <input type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)}
                className="mt-1 w-full rounded-md border border-border bg-surface px-3 py-2 font-normal" />
            </label>
            <button type="submit" disabled={busy} className={`${btn} border-brand-dark bg-brand-dark text-primary-foreground hover:opacity-90`}>
              {busy ? "Skickar…" : "Skicka återställningslänk"}
            </button>
            <button type="button" onClick={() => { setForgot(false); setError(null); setInfo(null); }}
              className="w-full text-center text-sm text-brand-dark underline-offset-2 hover:underline">
              Tillbaka till inloggning
            </button>
          </form>
        ) : (
          <form onSubmit={onSubmit} className="space-y-3">
            <label className="block text-sm font-semibold">
              E-post
              <input type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)}
                className="mt-1 w-full rounded-md border border-border bg-surface px-3 py-2 font-normal" />
            </label>
            <label className="block text-sm font-semibold">
              Lösenord
              <input type="password" required autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)}
                className="mt-1 w-full rounded-md border border-border bg-surface px-3 py-2 font-normal" />
            </label>
            <button type="submit" disabled={busy} className={`${btn} border-brand-dark bg-brand-dark text-primary-foreground hover:opacity-90`}>
              {busy ? "Loggar in…" : "Logga in"}
            </button>
            <button type="button" onClick={() => { setForgot(true); setError(null); setInfo(null); }}
              className="w-full text-center text-sm text-brand-dark underline-offset-2 hover:underline">
              Glömt lösenord?
            </button>
          </form>
        )}
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        {info && <p role="status" className="text-sm text-ink-muted">{info}</p>}
      </div>
    </Section>
  );
}

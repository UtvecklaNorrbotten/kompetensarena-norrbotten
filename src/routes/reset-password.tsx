import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, type FormEvent } from "react";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/reset-password")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Nytt lösenord – Kompetensarena Norrbotten" },
      { name: "description", content: "Sätt ett nytt lösenord via återställningslänk." },
      { property: "og:title", content: "Nytt lösenord – Kompetensarena Norrbotten" },
      { property: "og:description", content: "Sätt ett nytt lösenord via återställningslänk." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { name: "robots", content: "noindex, nofollow" },
    ],
  }),
  component: ResetPasswordPage,
});

const btn =
  "inline-flex w-full items-center justify-center rounded-md border px-4 py-2.5 font-semibold transition-colors focus-visible:outline-2 disabled:opacity-60";

function ResetPasswordPage() {
  const navigate = useNavigate();
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") setReady(true);
    });
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) setReady(true);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (password !== confirm) {
      setError("Lösenorden stämmer inte överens.");
      return;
    }
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.updateUser({ password });
    setBusy(false);
    if (error) {
      setError("Kunde inte spara det nya lösenordet. Länken kan ha gått ut – begär en ny.");
    } else {
      navigate({ to: "/admin/datakallor", replace: true });
    }
  }

  return (
    <Section className="py-10 md:py-14">
      <PageHeader eyebrow="Intern" title="Nytt lösenord" intro="Välj ett nytt lösenord för ditt konto." />
      <div className="mt-8 max-w-sm">
        {ready ? (
          <form onSubmit={onSubmit} className="space-y-3">
            <label className="block text-sm font-semibold">
              Nytt lösenord
              <input type="password" required minLength={8} autoComplete="new-password" value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="mt-1 w-full rounded-md border border-border bg-surface px-3 py-2 font-normal" />
            </label>
            <label className="block text-sm font-semibold">
              Upprepa nytt lösenord
              <input type="password" required minLength={8} autoComplete="new-password" value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                className="mt-1 w-full rounded-md border border-border bg-surface px-3 py-2 font-normal" />
            </label>
            <button type="submit" disabled={busy} className={`${btn} border-brand-dark bg-brand-dark text-primary-foreground hover:opacity-90`}>
              {busy ? "Sparar…" : "Spara nytt lösenord"}
            </button>
          </form>
        ) : (
          <p className="text-sm text-ink-muted">
            Väntar på återställningslänken… Om du kom hit utan länk, gå till inloggningssidan och välj "Glömt lösenord?".
          </p>
        )}
        {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
      </div>
    </Section>
  );
}
